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
| `asm1` | 6 947 | `3c932ea1cfc5b897` | built by `seed/asm1` from `src/asm1.s` |
| `seed/asm1` | 6 947 | `3c932ea1cfc5b897` | the promoted stage; identical to `asm1` |
| `dis` | 1 343 | `2d2eb451d7c7a9a9` | built by `asm1` from `src/dis.s` — our decoder |
| `src/asm1.s` | 25 422 | — | 1 878 lines, 188 labels (limit 256, 7 of them duplicated dead code) |
| `src/dis.s` | 11 108 | — | 467 lines, 48 labels |

Tags `milestone-fixpoint`, `milestone-handover` · 18 fixtures · 12 reject sources · **29 capability
pairs** · **4 superiority cases** (byte-level) + 2 behavioural · 5 exact messages · 38 decoder cases ·
**77 coverage forms** · 290 branch pins · 35 provenance records.

## Verify before touching anything

```
make clean && make && make check
```

`make check` must print, in order: **forbidden tools: none invoked** · **coverage 60/60 forms
exercised** · fixpoint holds · bootstrap NOT APPLICABLE · 12/12 rejections · 5/5 exact messages ·
29/29 capability pairs · 4/4 superiority cases (plus the 99 KB and `entry` cases) · 38/38 decoder
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

## What changed in the last three sessions

**The branch gate is ours.** `tools/check-branches.sh` no longer mentions `objdump`. It runs `./dis`,
compares all 290 pins in `docs/branches.tsv` with `cmp`, and prints the sha of `asm0a` and of `dis`
beside the count. The pins themselves were transcribed from objdump in earlier waves, so a green gate
is an independent check *of the decoder* and no check of either encoder — stated in `AGENTS.md`.

**A wrong answer fixed: `[rbp]` with displacement 0.** It encoded as `8b 05` (RIP-relative, the next
four bytes read as the displacement) and no test input had ever written it. `emitmem` now takes
`mod = 01` when the displacement is non-zero, a SIB is present, or the base is `rbp`, and emits the
disp byte under the same condition. Held by `tests/superior/rbp0.s`. `asm0a` still gets it wrong.

**Coverage is measurable.** `make test-coverage`: every claimed form must be exercised by some test
input, and every mnemonic a test uses must be claimed. 77 forms. Its first run found two untested
shapes and two unclaimed mnemonics; it found three more untested forms the hour after REX.W landed.

**REX.W: the width comes from the operand names.** Before this, `add`/`xor` refused 64-bit operands
while `mov`/`and`/`or`/`test`/`cmp` silently encoded 32-bit, and `sub` always encoded 64-bit. Now
`reg32` records the width, two-register handlers refuse a mixed pair, and `0x48` is emitted iff the
width is 64-bit. `asm1` 6 679 → 6 947. Details: `docs/encodings.md`.

## The next task: `r8`–`r15`

The width machinery is in place; the extended codes are not. What it needs, in this order:

1. **The parser.** `reg32` accepts three characters (`eax`, `rax`). `r8`…`r15` are 2–3 (`r8`, `r10`),
   and `r8d`…`r15d` are 3–4, so the register matcher has to stop assuming a fixed width. Codes 8–15
   come out of it.
2. **The REX bits.** `REX.R` for the ModRM *reg* field, `REX.B` for the rm/base, `REX.X` for the SIB
   index: `0x40|W<<3|R<<2|X<<1|B`, emitted where the `0x48` is emitted now — one helper, called from
   the same nine handlers.
3. **The mask.** Every code must be `and`ed with 7 before it is shifted into a ModRM or SIB byte; the
   extended bit lives only in REX. `emitmem` and `memop` are where this is decided.
4. **`r13`** is the second member of the `mod = 00` exception `rbp` already has.

Gate: hand-computed cases for `mov r8, rax` → `49 89 c0`, `add r8, r9` → `4d 01 c8`,
`add rax, r8` → `4c 01 c0`, `mov r9, [r8]` → `4d 8b 08`, `lea r10, [r8+r9]` → `4f 8d 14 08`, plus
`r13` with displacement 0; the 18 fixtures byte-identical; fixpoint; coverage green; then
`make promote`, `make record`, and **re-pin `docs/SHAS`** (it pins `seed/asm1`, and `make check` fails
until it is).

Then, in order: `.data` (a second `R+W` `PT_LOAD`, opt-in), disp32 + `[base+index*scale]`, the signed
condition codes and `imul …,imm8`, a calling convention with a fixture that exercises it.
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
| `docs/encodings.md` | chosen encodings, the fixed `[rbp]` defect, the REX.W width rule |
| `docs/oracles.md` | what `ref/` does and does not prove |
| `seed/README.md` | the bootstrap chain |
| `tests/dis/cases.tsv` | the decoder's hand-written expectations, positive and negative |
| `tests/coverage/forms.tsv` | the claim of what is supported; every row must be exercised |
| `tools/shape.awk` | how two source lines are decided to reach the same encoder path |
| `docs/toolchain.tsv`, `docs/provenance.tsv`, `docs/SHAS`, `docs/branches.tsv` | the records |
