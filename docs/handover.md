# Handover gate: when may `asm0a` build `asm0b`?

The question this file answers: **what must be true before the next assembler is built by the
current one?**

It matters more than it looks, because the handover is the moment when one artifact's
behaviour is frozen into another's bytes. `asm0b` is not compiled from a specification — it is
*emitted* by `asm0a`. Every encoding choice `asm0a` makes becomes an encoding choice baked into
`asm0b` at birth, with no chance to differ. A bug in `asm0a` does not fail loudly at the
handover; it becomes `asm0b`'s starting condition.

## Necessary conditions — all six, no exceptions

| # | Condition | Why |
|---|---|---|
| 1 | **No red oracles.** Every wave `asm0a` claims is byte-identical on its fixture, and the runtime assertion passes. | A red wave means at least one encoding path is wrong. Handing over now bakes it in. |
| 2 | **Dialect closure.** `asm0b.s` uses only forms `asm0a` implements — established by `asm0a` assembling `asm0b.s` with exit 0. | An unimplemented form must fail, not be approximated. |
| 3 | **Per-form verification.** Every form `asm0b.s` uses has (a) a hand-emitted reference fixture it reproduces byte-identically, (b) a behavioural assertion whose value differs when the form is wrong, (c) a row in `docs/encodings.md` traced to the reference XML. | This is the only independent check on the encoding that `asm0b` will inherit. |
| 4 | **Loud failure.** Anything `asm0a` cannot encode exits non-zero. Never a plausible wrong binary. | A silent approximation in `asm0a` is a silent approximation in `asm0b`. |
| 5 | **Resource limits honoured by `asm0b.s`**: source < 64 KiB, ≤ 32 labels, names ≤ 7 chars, body < 0xF000, rel8 displacements within ±127, `83 /7`-style immediates within −128..127. | These are hard limits in `asm0a` today. Exceeding one is not an error the assembler detects — it is corruption. |
| 6 | **Reproducibility.** The exact `asm0a` (sha in `docs/SHAS`) and the exact command used are recorded. | Otherwise "asm0b was built by asm0a" is a claim with no object behind it. |

## Sufficient combination — handover is *complete* when

| # | Condition |
|---|---|
| 7 | `asm0b`, as built by `asm0a`, passes the **whole inherited corpus** byte-identically: `exit42`, `hello_num`, `jmp`. |
| 8 | **Fixpoint**: `asm0b` assembling `asm0b.s` produces bytes identical to what `asm0a` produced for `asm0b.s` (`stage2 == stage3`). Note it is `stage2 == stage3` that is required, **not** `asm0b == asm0a`: a different layout from a different generation is fine, exactly as GCC accepts `stage1 != stage2`. |
| 9 | **Superset demonstrated**: `asm0b` assembles at least one fixture `asm0a` cannot. Otherwise the wave had no purpose. |

Note what condition 8 does **not** do: the fixpoint detects *inconsistency between the two
assemblers*, not *incorrectness*. If `asm0a` emits a valid but non-canonical encoding, `asm0b`
inherits the same choice and the fixpoint passes — both agree, both non-canonical. Only
condition 3 (the reference table) catches that. This is why 3 is a precondition and 8 is not
sufficient on its own.

## Refusal criteria — reasons to *not* proceed

- **Any required fix to `asm0a` that is not a single same-size rel32 patch.** More than that
  means the layout is past hand-verification; re-emit instead. (This rule was adopted after
  wave 2a, where patching failed three times and a clean re-emission passed immediately.)
- **A form with no independent check.** No reference row, no decode check, no behavioural
  fixture → the encoding is a guess, and a guess is what gets frozen into `asm0b`.
- **"asm0a produced it" as the only evidence for `asm0b`.** That is the shared-authorship hole
  from `docs/oracles.md`: the same hands wrote the encoder and chose the source.

## Verdict today: NOT YET (2c green, 2d outstanding)

| # | Condition | State |
|---|---|---|
| 1 | No red oracles | **GREEN**: 1a, 1b, 2a, 2b-1, 2b-2 and 2c all pass — labels, two-pass flip, `jmp`/`jz`/`jnz` with range checks, `inc`/`dec`, and five fixtures byte-identical plus behaviourally correct. |
| 2 | Dialect closure | Unknown — `asm0b.s` does not exist yet. Foreseeable needs: `entry` directive (not implemented), more than 32 labels, names > 7 chars. |
| 3 | Per-form verification | 4 forms verified end to end (`mov r32,imm`, `xor r32,r32`, `syscall`, `db`). 25 more are documented in `docs/encodings.md` but not exercised by any fixture. |
| 4 | Loud failure | Partial. Unknown mnemonic and unknown register exit 1. But `mov eax,` with no operand assembles as `mov eax, 0` and exits 0, and the `83 /7` immediate range is unenforced. |
| 5 | Resource limits | Label count (32) and name length (7) are now **enforced and verified**: 32 accepted, 33 exits 1, 8-char exits 1, empty exits 1. Still unenforced: body < 0xF000, `83 /7` immediate range. |
| 6 | Reproducibility | Yes: `asm0a` sha in `docs/SHAS`, build command recorded in `docs/waves/`. |
| 7–9 | Corpus, fixpoint, superset | Not applicable — no `asm0b` exists. |

**`asm0a` cannot self-host yet, but the blocker has moved.** Condition 1 is green after 2b-1.
What blocks now is completeness: conditions 2, 3 and 4 need the remaining forms (2b-2, 2c, 2d)
plus numeric `db` and `entry` — see "What `asm0a.s` needs" below. The gate is no longer about
trusting the current artifact; it is about the dialect being able to express an assembler.

## The 2b failure, and what it says about the method

Six defects were found and fixed in the 441-byte appended block, and each fix revealed the
next. Every one was displacement or REX arithmetic:

1. `mov r11,rcx` written `4c 89 cb` — REX.B set for `rcx`, so it was `mov r9,rbx`.
2. `add rbx,3` assumed 3 bytes; with REX it is 4, shifting three displacements.
3. `mov rdx,[rsp+disp32]` assumed 9 bytes; it is 8, shifting nine displacements.
4. Four branch targets recomputed for the pre-shift layout, landing one byte off.
5. `jmp notfound` written one byte late, clobbering the `8b` of `mov eax,[rdi]`.
6. `sub rdx,r14` written `4d 29 f2` — REX.B for `rdx`, so `sub rdx,r10`.

The pattern is not "six mistakes", it is **one mistake repeated**: hand-computing byte offsets
across a 441-byte region with variable-length instructions. `objdump` caught every one, and
caught nothing before it was emitted — which is the general lesson: hand-laid code is verified
by decoding it and executing it, never by re-reading the arithmetic.

Consequence: 2b gets **re-emitted from one coherent layout**, smallest-possible blocks, sizes
asserted at every boundary, and every branch target checked against the label it should reach
before the next block is appended. The existing attempt is preserved on branch `wip/2b` so the
diagnosis is not lost; `main` keeps the green 2a artifact.

## Correction from the historical record: grow in place, do not write a fresh `asm0b`

Before planning `asm0b` as a new 29-form assembler, check what DEC actually did for the second
generation. The evidence is thin but consistent:

- Jones's FAQ: Ed Yourdon *"helped **hack up** the PAL III assembler for the -8 **from PAL II**"*.
- Jones's FAQ: John Everett *"**adapted** PAL-III to make PAL-D"*.
- Field Guide: PAL-III shipped on paper tape as the "PDP-8 Assembly System"; two passes through
  the tape reader minimum.

**"Hacked up" and "adapted" are both descriptions of source modification, not of writing a
new program.** A successor produced by editing the predecessor's source and reassembling it is
the only reading consistent with both verbs, and it is the cheap one: the delta is a few
hundred lines, not a rewrite.

What the record does **not** say — and this is why the check was worth doing but not worth
repeating: the implementation language of PAL-II/PAL-III, the size of the delta, and whether
the source was kept in a dialect the predecessor could assemble. Two searches produced no
source for any of it; the PAL-III manual on bitsavers is a scan with no text layer. Treat
"PAL-III was written in PAL and reassembled by PAL-II" as a strong inference, not a citation.

### What that changes here

Not "write `asm0b` from scratch", but **self-host `asm0a` and then grow it**:

1. Extend `asm0a`'s dialect until it can express an assembler (that is waves 2c and 2d — the
   missing 25 forms). This is not optional: an assembler's source needs labels, jumps,
   arithmetic, memory operands and tables, so a 4-form assembler can never assemble its own
   successor.
2. Write **`asm0a.s`**: `asm0a`'s own logic as source text in `asm0a`'s dialect, transcribed
   from the annotated byte listings.
3. Self-host: `asm0a < asm0a.s` must produce a working assembler `X`; then `X < asm0a.s` must
   produce `X'` with `X' == X`. That is condition 8, and it does **not** require `X == asm0a`.
4. From then on, every new feature is an **edit to `asm0a.s`**, reassembled by the current
   binary. That is precisely "hacked up", and it is the point of the whole exercise: after
   step 3 there is no more hand-emission of the assembler, ever.

Consequences for the gate:

- Condition 2 (dialect closure) is no longer about `asm0b.s`; it is about **`asm0a.s`**: every
  form `asm0a`'s own source uses must be supported and verified.
- Condition 9 (superset) is satisfied by editing the source, not by writing a second program.
- The name `asm0b` is retired. After self-hosting, the artefacts are `asm0a.s` plus a series of
  binaries from it; the interesting object becomes the source file, which is the thing a human
  can read.

### What `asm0a.s` needs that `asm0a` does not yet have

The self-hosting loop only closes if the dialect can express an assembler. Verified gaps, each
with the observed failure:

| Need | Why `asm0a.s` cannot do without it | Today |
|---|---|---|
| branch instructions | an assembler is loops and dispatch | **absent** (2b, red) |
| `cmp`/`inc`/`dec`/`add`/`sub`, conditional jumps | counters, table walk, bounds checks | **absent** (2c) |
| memory operands (`[rsp+d8]`, `[rdi+rcx]`), `movzx`, `div`, `lea`, `test`, `imul` | the parser, the symbol table, the number printer | **absent** (2d) |
| **numeric `db`** | the ELF header template is mostly zero bytes, and `db` accepts only a quoted string | `db 0` → exit 1 |
| **`entry label`** | with tables placed first (which fixes their addresses), code starts at 0x98, so the output needs `e_entry` = 0x400110. `asm0a` hardcodes 0x400078 in its template | `entry x` → exit 1 |
| `mov r32, label` (optional) | otherwise table addresses are decimal literals like `4194424`; correct, but brittle-looking | `mov eax, x` → exit 1 |

The `entry` gap is the one that is easy to miss and fatal: `asm0a`'s template contains
`e_entry = 0x400078` as a literal, so a data-first source with code at 0x98 assembles into a
binary that starts executing its tables. Wave 2a's "data first" decision — made to stop
addresses churning — is exactly what makes `entry` mandatory.

### The loop, stated precisely

```
asm0a.s  --[asm0a]-->  X      X is a working assembler with the same dialect
X        --[asm0a.s]--> X'    X' == X  (fixpoint; X == asm0a is NOT required)
```

Only after the fixpoint holds does "the next version" exist, and then it arrives by **editing
`asm0a.s`** and reassembling with the current binary. The first `X` is the same version as
`asm0a`, merely self-produced; the version numbers start from the edits after it.

Why the weaker requirement is the right one: it means the source does not have to reproduce
`asm0a`'s exact bytes or offsets. Any source whose *behaviour* is equivalent will do, and the
fixpoint then proves the loop is closed. Requiring `X == asm0a` would demand re-deriving a
1351-byte layout byte for byte, which is a transcription exercise with no verification value.

### Remaining before `asm0a.s` can be written

2c (conditional jumps, `inc`/`dec`, `cmp r32,imm8`, hex literals), then 2d (memory operands
with SIB/disp8, `movzx`, `div`, `lea`, `test`, `imul`, numeric `db`, `entry`). Then:

   write asm0a.s (~400-600 lines transcribed from the byte listings)
   X  = asm0a(asm0a.s)      must be a working assembler
   X' = X(asm0a.s)          must equal X  (fixpoint)

Then every later version is an edit to `asm0a.s`.

### The next step is therefore unchanged in substance, but re-scoped

2b is split, because the failure mode was hand-laying 441 bytes with 30-odd hand-computed
displacements:

| Wave | Content | Gate |
|---|---|---|
| **2b-1** | label definitions, label table, pass 1 / pass 2 flip. **No jumps.** | `exit42` and `hello_num` still byte-identical; a program with labels but no jumps assembles identically to the same program without them |
| ~~**2b-2**~~ | ~~`jmp rel8` with the ±127 check~~ | **DONE** — `src/jmp.s` byte-identical to `ref/jmp`, binary exits 7, +120 accepted, +132 refused |
| ~~**2c**~~ | `inc`/`dec r32`, `jz`, `jnz` | **DONE** — `src/loop.s` → `ref/loop` (exits 10), `src/jz.s` → `ref/jz` (exits 5). `jb`/`ja`, `cmp r32,imm8` and hex literals deferred to 2d, where `asm0a.s` has actual users for them |
| **2d** | split four ways. **2d-1 DONE** (8-bit register class, `mov r8,imm8`, `movzx r32,r8`). **2d-2 DONE** (`inc`/`dec r8`). **2d-3 DONE** (`cmp`/`add` on r8, `jb`, and the shared range-checked number parser). **2d-4 DONE** (memory operands with SIB/disp8, `lea`, `mov byte [mem],imm8`). Remaining: 2d-5 `sub r64,r64`, `test`, `imul`, `entry`, hex literals, numeric `db` | `src/count10.s` → `ref/count10` (`e61a23c9…`), then `asm0a.s` self-hosts |

And the process fix that matters more than the split: after emitting each block, **decode every
branch in it with `objdump` and compare its target against the intended label offset**, as a
mechanical check, before appending the next block. Six of six 2b defects were displacement or
REX arithmetic that decoding would have caught immediately; none were caught by re-reading the
hex.
