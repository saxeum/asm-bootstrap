# Continue here

State of the project at the end of the session that gave the gate its own decoder. Written so a new
session can start without re-deriving anything.

## The numbers

| | bytes | sha256 (16) | notes |
|---|---|---|---|
| `asm0a` | 3 745 | `6271c5ee79034ffd` | hand-written machine code, **frozen**, not a correctness reference |
| `asm1` | 6 820 | `2b4aada60da42df8` | built by `seed/asm1` from `src/asm1.s` |
| `seed/asm1` | 6 820 | `2b4aada60da42df8` | the promoted stage; identical to `asm1` |
| `dis` | 1 348 | `8c9bd9b356874875` | built by `asm1` from `src/dis.s` — our decoder |
| `src/asm1.s` | 24 177 | — | 1 847 lines, 189 labels (limit 256) |
| `src/dis.s` | 11 108 | — | 467 lines, 48 labels |

Tags `milestone-fixpoint`, `milestone-handover` · 18 fixtures · 11 reject sources · 28 capability
pairs · 3 superiority cases · 5 exact messages · 37 decoder cases · 290 branch pins · 35 provenance
records.

## Verify before touching anything

```
make clean && make && make check
```

`make check` must print, in order: fixpoint holds · bootstrap NOT APPLICABLE · 11/11 rejections ·
5/5 exact messages · 28/28 capability pairs · 3/3 superior · **38/38 decoder cases** · 35 provenance
records · SHAS match · `asm1.sha` match · and a real **`branch pins: 290/290`** line naming both the
subject's sha and the decoder's. If any line is missing or red, stop and fix that first.

Two traps that have each cost a session:

- **`make` before `./asm1`, and check the build's exit code *and* that the sha changed.** A failed
  build leaves the old binary in place, and the next test then reports green about a stale subject.
  `make` and `make check` rebuild their prerequisites; a bare `./asm1` or `./dis` does not.
- **After any change to `src/dis.s`:** `make record` (the decoder is in `docs/provenance.tsv`).
  After any change to `src/asm1.s`: `make promote` and `make record`, or `make check` fails on
  `docs/asm1.sha` and the ledger. Those failures are correct — each has caught an omission once.

## What changed last: the branch gate is ours

`tools/check-branches.sh` no longer mentions `objdump`. It runs `./dis`, compares every one of the 290
pins in `docs/branches.tsv` with `cmp`, and prints the sha of `asm0a` and of `dis` beside the count.
It refuses to be quietly green: no decoder, no subject, or a table shorter than 290 sites fails; a
deliberate mismatch must be reported; and any disagreeing pin fails the gate.

`src/dis.s` decodes exactly the branch forms the gate consumes (`EB`, `E9`, `E8`, `70`–`7F`,
`0F 80`–`0F 8F`) and refuses everything else. A refusal is exit 1, nothing on stdout, and one reason
word on stderr: `offset`, `input`, `site`, `form`, `trunc` or `target`. The last two are the truncation
rule — an instruction must fit inside the input, and its target must be a byte in it.

```
./dis 0x142 < asm0a
```

prints `0x142 0x373 jmp`. `make test-dis` runs 38 hand-written cases from `tests/dis/cases.tsv`:
26 that must decode (16 of them the jcc names, plus both directions of rel8 and rel32 and the `argv`
spellings) and 12 that must be *refused*, each with the reason it must give — a refusal that names
the wrong rule fails.

**What is still provisional:** the instruction-mix table in `docs/ROADMAP.md`. `dis.s` covers branch
forms, so it confirms the 290 branch sites and says nothing about `mov` (135), `add` (130), `inc`
(107) or `cmp` (101). Do not describe that table as ours. No claim may say the decoder verifies
anything but branches.

## The next task: `r8`–`r15` and REX.W, one mechanism

`docs/ROADMAP.md` has the reasoning and the measurement. In short: `add rax, rbx` is *refused* today
because the reg-reg ALU handler never emits REX.W, so 64-bit operands would silently assemble as
32-bit (`sub rsi,rcx` works only because its opcode sets REX.W). The fix is one mechanism — compute a
REX byte from operand codes ≥ 8 and the 64-bit flag, emit it before the opcode, mask the codes with
`and` — and it buys both 16 registers and the 64-bit ALU forms at once.

Gate for it: capability pairs against hand-computed dumps (`add rbx,rcx` → `48 01 c9`, `add r8,r9` →
`4d 01 c8`), the 18 fixtures byte-identical, fixpoint, and `make record` after. Ranges are checked in
pass 1, so a new form needs its own out-of-range cases in `tests/reject/` — every form added so far
has needed one.

After that: the forms `asm0a` needs to be rebuilt (`add r64,imm8`, `cmp r8/[mem]`,
`imul r32,r32,imm8`, the condition codes `ja/jae/js/jg/jo`), then `src/asm0a.s`, then
`asm1 < src/asm0a.s | cmp - asm0a`.

## How to edit `src/asm1.s` (this is not optional)

**Whole-block replacement, anchored on a label and the next label.** Five positional edits were
attempted in one session and all five failed: deleted live lines, duplicated labels (three times),
handlers inserted inside a neighbour's body (four times), a stray label before a branch, and an
insertion inside `chklim`'s flag-dependent sequence that turned a range check into a no-op. Tests
caught every one, none was caught by reading.

The working pattern, used for `memop`, `emitmem`, `chklim`, `trm`, `lfind`, `msg`, `d_n`:

```
cat > /tmp/block.txt <<'EOF'
<the complete replacement block>
EOF
awk 'BEGIN{skip=0} /^label:$/ { while ((getline l < "/tmp/block.txt") > 0) print l; skip=1; next }
     skip && /^[a-z_0-9]+:$/ { skip=0 } skip { next } { print }' src/asm1.s > /tmp/new.s
cp /tmp/new.s src/asm1.s && make && <run the fixtures>
```

Then **immediately**: `make` (check exit code and sha changed), fixtures 18/18, fixpoint.

## Dialect limits that will bite

- label names ≤ 7 characters; ≤ 256 labels; **duplicate labels assemble and the first wins**, so a
  duplicate silently hides dead code. `src/asm1.s` carries 11 today, in four dead regions: a second
  `chkok`, `trm`'s `termok`/`termnum`, the unreachable `lblchk` block with its own `ls1`, and the
  second `emm1`…`em_done` tail of `emitmem`. All are dead (`lblchk` has no caller), and all are
  harmless to the output — but the *assembler* accepting them is what hides the next one, which will
  not be dead. The fix is a pass-1 duplicate check in `asm1`, which would fail on its own source until
  those blocks are deleted: do it as one deliberate change with a `make promote` and `make record`.
- every four-byte frame slot within `disp8` is in use in `asm1.s`: slots are `[rbp+8]`…`[rbp+124]`
  plus `[rbp+2]` (reason byte), `[rbp+4]`, `[rbp+12]` (expression scratch). Negative displacements
  work, so `[rbp-64]`…`[rbp-128]` are free — but `[rbp-8]` and below are the call stack.
- no `add r32,imm32` (`add eax,100` is rejected) — use two `add`s, a register, or `lea`. `add r64,imm8`
  is **not implemented**. `cmp r8,imm8` is signed (−128..127), so compare opcodes ≥ 128 at 32 bits.
- only `jb`, `jz`, `jnz`, `jmp` exist as conditions (plus `.l`): **no `ja`, `jae`, `jbe`, `js`, `jg`**.
  Invert the test, or use `add dl,-N; cmp dl,K; jb` to range-test a byte.
- 64-bit operands in a reg-reg form whose opcode carries no REX are **refused**, not mis-assembled:
  `mov rax,rbx` → `line 1: rejected`. `sub rsi,rcx` works (its opcode sets REX.W).
- `emital` destroys `rcx`, `rax`, `rdx`, `rsi`, `rdi`, and any `syscall` destroys `rcx` too: anything
  needed after one lives in memory or in `rbx`/`rbp`.
- buffers go **below** `rsp`; above `rsp` the mapping ends within a few KB. Read in 120-byte chunks —
  one large read returns a partial count because the kernel only copies into mapped pages.
- a label's value is its **offset from the first body byte**; the load address is `0x400078 + label`.
  `mov eax, 4194424+label` is how a program in the dialect reaches its own data.
- three passes: 0 counts, 1 validates (resolves labels, range-checks, no output), 2 emits. Anything
  that must fail with no output is checked in pass 1.

## Where things are

| | |
|---|---|
| `AGENTS.md` | invariants with their checks, the decoder section, the defect table |
| `docs/ROADMAP.md` | phases, what is done, what is deferred, and why in that order |
| `docs/WAVES.md` | the log, failures included |
| `docs/encodings.md` | chosen encodings and the known `[rbp]` disp-0 defect |
| `docs/oracles.md` | what `ref/` does and does not prove |
| `seed/README.md` | the bootstrap chain |
| `tests/dis/cases.tsv` | the decoder's hand-written expectations, positive and negative |
| `docs/toolchain.tsv`, `docs/provenance.tsv`, `docs/SHAS`, `docs/branches.tsv` | the records |
