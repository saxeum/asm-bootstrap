# Continue here

State of the project at the end of the session that gave the gate its own decoder, fixed `[rbp]`, and
added the coverage gate. Written so a new session can start without re-deriving anything.

**The goal, since this session: a compiler.** A high-level language whose backend emits this dialect.
That is what the roadmap is now ordered by; `docs/ROADMAP.md` has the requirement table and why
`REX.W` + `r8`–`r15` is first.

## The numbers

| | bytes | sha256 (16) | notes |
|---|---|---|---|
| `asm0a` | 3 745 | `6271c5ee79034ffd` | hand-written machine code, **frozen**, not a correctness reference |
| `asm1` | 6 679 | `d2bb52b219f485ac` | built by `seed/asm1` from `src/asm1.s` |
| `seed/asm1` | 6 679 | `d2bb52b219f485ac` | the promoted stage; identical to `asm1` |
| `dis` | 1 348 | `8c9bd9b356874875` | built by `asm1` from `src/dis.s` — our decoder |
| `src/asm1.s` | 24 198 | — | 1 810 lines, 180 labels (limit 256, 11 of them duplicated dead code) |
| `src/dis.s` | 11 108 | — | 467 lines, 48 labels |

Tags `milestone-fixpoint`, `milestone-handover` · 18 fixtures · 11 reject sources · **29 capability
pairs** · **3 superiority cases** (byte-level) + 2 behavioural · 5 exact messages · 38 decoder cases ·
**60 coverage forms** · 290 branch pins · 35 provenance records.

## Verify before touching anything

```
make clean && make && make check
```

`make check` must print, in order: **forbidden tools: none invoked** · **coverage 60/60 forms
exercised** · fixpoint holds · bootstrap NOT APPLICABLE · 11/11 rejections · 5/5 exact messages ·
29/29 capability pairs · 3/3 superiority cases (plus the 99 KB and `entry` cases) · 38/38 decoder
cases · 35 provenance records · SHAS match · `asm1.sha` match · and a real **`branch pins: 290/290`**
line naming both the subject's sha and the decoder's. If any line is missing or red, stop and fix
that first.

Two traps that have each cost a session:

- **`make` before `./asm1`, and check the build's exit code *and* that the sha changed.** A failed
  build leaves the old binary in place, and the next test then reports green about a stale subject.
  `make` and `make check` rebuild their prerequisites; a bare `./asm1` or `./dis` does not.
- **After any change to `src/dis.s`:** `make record` (the decoder is in `docs/provenance.tsv`).
  After any change to `src/asm1.s`: `make promote` and `make record`, or `make check` fails on
  `docs/asm1.sha` and the ledger. Those failures are correct — each has caught an omission once.

## What changed in the last two sessions

**The branch gate is ours.** `tools/check-branches.sh` no longer mentions `objdump`. It runs `./dis`,
compares all 290 pins in `docs/branches.tsv` with `cmp`, and prints the sha of `asm0a` and of `dis`
beside the count. `src/dis.s` decodes `EB`, `E9`, `E8`, `70`–`7F`, `0F 80`–`0F 8F` and refuses
everything else with one reason word on stderr (`offset`, `input`, `site`, `form`, `trunc`, `target`).
The pins themselves were transcribed from objdump in earlier waves, so a green gate is an independent
check *of the decoder* and no check of either encoder — stated in `AGENTS.md`, not just here.

**A wrong answer fixed: `[rbp]` with displacement 0.** It encoded as `8b 05` (RIP-relative, the next
four bytes read as the displacement) and **no test input had ever written it**, so nothing could see
it. `emitmem` now takes `mod = 01` when the displacement is non-zero, a SIB is present, or the base is
`rbp`, and emits the disp byte under the same condition. Held by `tests/superior/rbp0.s`
(hand-computed `8b4500`). `asm0a` still gets it wrong — it is frozen — and the case fails if they ever
agree. Details and the before/after table: `docs/encodings.md`.

**Coverage is now measurable.** `make test-coverage` (`tests/coverage/forms.tsv`, `tools/shape.awk`,
`tools/coverage.sh`) requires every claimed form to be exercised by some test input, and every
mnemonic a test uses to be claimed. First run: 2 untested forms and 2 unclaimed mnemonics. It is a
lower bound, and it says so.

**Dead code deleted from `emitmem`**: a shadowed second copy of its tail (7 duplicate labels) and an
unreachable `emmod1`. 52 lines, 10 label definitions, `asm1` −176 bytes.

## The next task: REX.W and `r8`–`r15`, one mechanism

`docs/ROADMAP.md` has the requirement table. The short version: this is the first item on the
compiler's list and it is one mechanism — a REX byte computed from operand codes ≥ 8 and the 64-bit
flag, emitted before the opcode, with the codes masked by `and`. It buys three things at once:

- `add rax, rbx`, `mov rax, rbx` stop being refused;
- 16 registers instead of 8;
- **`sub eax, ecx` stops assembling as 64-bit** (`docs/encodings.md` "known defect") because the width
  comes from the operand names instead of from the opcode.

Gate: capability pairs against hand-computed dumps (`add rbx,rcx` → `48 01 c9`, `add r8,r9` →
`4d 01 c8`, `sub eax,ecx` → `29 c8`), the 18 fixtures byte-identical, fixpoint, `make test-coverage`
green, `make promote` + `make record`. Note that `docs/SHAS` pins `seed/asm1` and has to be re-pinned
by hand after any promote — `make check` fails until it is.

Then, in order: `.data` (a second `R+W` `PT_LOAD`, opt-in), disp32 + `[base+index*scale]`, the
signed condition codes and `imul …,imm8`, a calling convention with a fixture that exercises it.
`src/asm0a.s` is the strongest statement the project can make and is *not* on the compiler path.

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
  duplicate silently hides dead code. `src/asm1.s` still carries 11, in three dead regions: a second
  `chkok`, `trm`'s `termok`/`termnum`, and the unreachable `lblchk` block with its own `ls1`. (The
  `emitmem` duplicate was deleted this session, which is why the fix there was safe to attempt — see
  `docs/encodings.md`.) All three remaining are dead and harmless to the output, but the *assembler*
  accepting them is what hides the next one, which will not be dead. The fix is a pass-1 duplicate
  check in `asm1`, which would fail on its own source until those blocks are deleted: one deliberate
  change, with `make promote` and `make record`.
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
| `docs/encodings.md` | chosen encodings, the fixed `[rbp]` defect, the open `sub r32` one |
| `docs/oracles.md` | what `ref/` does and does not prove |
| `seed/README.md` | the bootstrap chain |
| `tests/dis/cases.tsv` | the decoder's hand-written expectations, positive and negative |
| `tests/coverage/forms.tsv` | the claim of what is supported; every row must be exercised |
| `tools/shape.awk` | how two source lines are decided to reach the same encoder path |
| `docs/toolchain.tsv`, `docs/provenance.tsv`, `docs/SHAS`, `docs/branches.tsv` | the records |
