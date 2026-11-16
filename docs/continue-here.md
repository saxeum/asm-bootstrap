# Continue here

State after the signed-semantics fix. The assembler and compiler are C-built; `asm1` is the C
assembler, `cc` the C compiler, and both reach their own fixpoints. The assembly sources are frozen
witnesses.

## The numbers

| | bytes | sha256 (16) | notes |
|---|---|---|---|
| `asm0a` | 3 745 | `6271c5ee79034ffd` | hand-written machine code, **frozen** |
| `seed/cc` | 10 429 | `a81345ad5a67490d` | dialect compiler witness (`src/cc.s`) |
| `asm1` | 54 416 | `ccb1607db88a2ee1` | C assembler, `seed/cc1` + `seed/asm1` from `src/asm1.c` |
| `seed/asm1` | 54 416 | `ccb1607db88a2ee1` | promoted C assembler |
| `cc` | 44 154 | `5e9ad682b3564711` | C compiler, `asm1` from `src/cc.c` |
| `seed/cc1` | 44 154 | `5e9ad682b3564711` | promoted C compiler |
| `dis` | 1 343 | `2d2eb451d7c7a9a9` | `asm1` from frozen `src/dis.s` |
| `src/asm1.c` | 28 500-ish | — | the assembler in the subset |
| `src/cc.c` | 25 300-ish | — | the compiler in the subset |
| `src/asm1.s`, `src/cc.s`, `src/dis.s` | — | — | frozen, pinned by `docs/frozen.tsv` |

161 frozen `.s` sources · 113 coverage forms · 234 asm2 checks · 36 cc refusals · 43 goldens ·
9 rejections · 8 exact messages · 290 branch pins · 36 provenance records.

## Prove it

```
make clean && make && make check
```

Must print: frozen 161 · frozen `src/cc.s` still equals `seed/cc` · port 43/43 · d2 self-host ·
asm2 234 checks · coverage 113/113 · C assembler fixpoint (54 416) · signed superior · wc 4/4 ·
calc 10/10 + 2/2 · sort 6/6 + 2/2 · lisp 29/29 + 17/17 · provenance 36 · SHAS · 290/290 pins.

The C-only chain:

```
make from-c
  from-c: asm2 54416 ccb1607db88a2ee1, cc1 44154 5e9ad682b3564711
  from-c: cc2 == cc1 and asm2b == asm2
  from-c: wc, calc, sort and lisp built and run by cc1 + asm2
```

The differential (gcc is the second opinion, never an artifact; run by hand, not from `check`):

```
tools/differential.sh              -> 5/5 AGREE
tools/differential.sh seed/cc ./asm1 -> 1/5 (the pre-signed witness DIFFERS on all four negative cases)
```

## Signed semantics, and what moved

`asm1` now has `jl/jle/jg/jge/js` (rel8 and `.l`), `cqo`, `idiv r32/r64`. `cc` emits `jl` for `<`,
`jg` for `>`, and `cqo` + `idiv` for `/` and `%`; `<=`/`>=` are still normalised to `<`/`>` with an
adjusted bound. The internal comparisons in `cc.c` are on non-negative counts and offsets, so signed
emission is safe for them; a comment says so.

Two byte-packing defects had to be fixed for a signed compiler: `pd`/`pda`/`pw`/`pwa` and `ex4`/`ex8`
split values with `/ 256`, and signed division truncates toward zero, so a negative value wrote zeros
instead of `0xff` in the high bytes. They now shift arithmetically (subtract one when negative and
the remainder is non-zero). `calc.c` was then rewritten to use `v < 0` and signed `/`/`%`; its
magnitude workaround is deleted.

**The seeds changed.** `seed/asm1` is now the C assembler and `seed/cc1` the C compiler; `seed/cc` is
the dialect witness. The canonical `asm1` is built from `src/asm1.c`, the canonical `cc` from
`src/cc.c`. `src/asm1.s` and `src/cc.s` are frozen and pinned.

## The four programs

`wc.c`, `calc.c`, `sort.c` and `lisp.c` are built and run by both chains. `lisp.c` reads numbers,
symbols, lists and quote; evaluates numbers, symbols, `if`, `define`, `quote`, `+ - * /`,
comparisons, `car`, `cdr` and `cons`; and writes one value per line. Its memory is one `char[140000]`
passed as an `int`: input at 0, 4096 nodes at 65536 (16 bytes each), and the parser/name/env/output
state above 131072. The arena, 64 definitions, the 60000-byte input and the output buffer are fixed
and each exhaustion is `lisp: error` on stderr with exit 1.

It has no closures, no `set!`, no user functions, no GC and no dotted-pair reader. The reader,
evaluator and printer recurse, and every call has the compiler's 260000-byte frame, so deeply
nested lists are a known limit rather than a tested feature; the tests stay shallow. The arena-full
case is a flat run of definitions, not a 3000-deep chain.

## What is left

1. **`.data`** — a second read-write `PT_LOAD`, and string literals in memory. This is the next
   assembler feature with no user.
2. **Assembler gaps**: `add r32, imm32`, `cmp`/`mov` with `[mem]`, `[base+index*scale]`, `imul r,r,imm`.
3. **Differential in CI** is deliberately manual; it is rung 4 in `docs/oracles.md`.


## Where things are

| | |
|---|---|
| `AGENTS.md` | invariants with their checks |
| `docs/cc.md` | compiler stages and gates; Stage 13 is signed semantics |
| `docs/ROADMAP.md` | ordered plan and history |
| `docs/WAVES.md` | the log, failures included |
| `docs/encodings.md` | opcode table, including signed jumps/idiv/cqo |
| `docs/oracles.md` | what `ref/`, the oracles and the differential do not prove |
| `tools/differential.sh` | gcc second opinion (the one named `test-tools` exemption) |
| `tests/differential/` | the intersection programs |
| `tests/programs/` | `wc.c`, `calc.c`, `sort.c`, `lisp.c` |
| `docs/frozen.tsv`, `docs/SHAS`, `docs/provenance.tsv`, `docs/toolchain.tsv` | the records |

## Violations

`docs/violations/python-in-edit-and-diagnosis.md` records the python and awk invocations made while
editing and diagnosing this work. They are recorded, not omitted.
