# Continue here

State after D3: the compiler compiles itself, and the assembler is written in C too. `src/asm1.c`
is compiled by `cc`, assembled by `asm1` into `asm2`, and `asm2` reproduces `asm1` on the whole
corpus and assembles the text of its own compiler into itself.

## The numbers

| | bytes | sha256 (16) | notes |
|---|---|---|---|
| `asm0a` | 3 745 | `6271c5ee79034ffd` | hand-written machine code, **frozen**, not a correctness reference |
| `asm1` | 8 053 | `71c5dbdba797ed40` | built by `seed/asm1` from `src/asm1.s` |
| `seed/asm1` | 8 053 | `71c5dbdba797ed40` | the witness and the builder |
| `dis` | 1 343 | `2d2eb451d7c7a9a9` | built by `asm1` from `src/dis.s` |
| `cc` | 10 429 | `a81345ad5a67490d` | built by `asm1` from `src/cc.s` |
| `asm2` | 51 776 | `3804b0269d7a165d` | `cc` + `asm1` from `src/asm1.c`; the D3 artifact |
| `src/asm1.c` | 27 969 | — | 1 475 lines, the assembler in the subset |
| `src/cc.c` | 24 742 | — | 1 680 lines, the compiler in the subset |
| `src/cc.s` | 58 892 | — | 3 108 lines |
| `src/asm1.s` | 34 496 | — | 2 269 lines |
| `src/dis.s` | 11 108 | — | 467 lines |

`cc1.s` (the text `cc` emits for `src/cc.c`) is 135 839 bytes; `asm1.c.s` (the text for
`src/asm1.c`) is 158 806 bytes. Frames are 260 000 bytes, arrays 255 000, `cc` buffers 200 000,
labels 2 048, literals 999, numeric literals up to 16 777 215.

43 compiler goldens (42 in `tests/golden/` plus `helloworld.c`) · 9 reject sources · 36 capability
pairs · 8 byte-level superiority cases · 8 exact messages · 38 decoder cases · 100 coverage forms ·
36 cc refusals · 290 branch pins · 36 provenance records · **220 asm2 checks**.

## Prove it before touching anything

```
make clean && make && make check
```

`make check` must print: forbidden tools · nothing outside the tree · header · `cc source invariant` ·
`port: 43/43` · `d2: THE PORT COMPILES ITSELF` · **`asm2: 220 checks, 0 failures -- corpus and
self-assembly`** · coverage 100/100 · fixpoint · bootstrap NOT APPLICABLE · 9/9 rejections · 8/8
messages · 36/36 capability · superiority · 38/38 decoder · 45 cc gates · 36 provenance records ·
SHAS · `asm1.sha` · `branch pins: 290/290`.

The D3 command on its own:

```
make test-asm2
```

builds `src/asm1.c` with `cc`, assembles it with `asm1`, and runs `tools/asm2-check.sh`: the 17
hand-emitted references, the 80 capability/superior inputs, the 100 coverage forms, the 9 refusals,
the 8 exact messages, `src/dis.s`, `src/cc.s`, `src/asm1.s`, the 99 032-byte source (and it runs,
exit 42), and `asm2 < asm1.c.s == asm2`.

## What changed in this session

**The compiler grew to make the assembler possible.** Numeric literals now go to 16 777 215 (not
65 535); `emitnum` prints eight digits; condition jumps are emitted as `.l` (a rel8 condition around
a large block is now a real overflow); `werr(buf, n)` is a new builtin writing to fd 2, which is how
both compilers name a line and a reason; the frame is 260 000 and arrays are 255 000, so
`src/asm1.c` can hold a 200 000-byte source and a 2 048-label table. Every golden was re-pinned for
the frame, the argument-parking base and the `.l` conditions, and the behaviour gates were re-run.

**`src/asm1.c` is complete.** Three passes (labels, count with labels, emit), the 120-byte ELF
header, labels to 2 048, input to 200 000, exact `line N: reason` messages (`range`, `label`,
`duplicate`, `rejected`). It reproduces every reference and every corpus input byte for byte, and its
own compiler text assembles to itself.

**The compiler port caught two real defects in itself**: `gd`/`pd` (32-bit state accessors) were
missing while the condition bound had been moved to a 32-bit slot; and the array allocator's 16-bit
offset would not survive the larger limits. Both are fixed.

## The port's constraints, which are the subset's

- Arrays store their **end**; base = `rbp-end`, index `i` at `rbp-end+i`.
- A subscript in the right side of an array store clobbers `[rbp-308]`; read through a temporary.
- A call inside an argument list is refused; stage through a local.
- `exit(n)` and `werr(buf, n)` are the only ways out / to stderr.
- The port's own input cap is 26 000; `src/cc.c` is 24 742.

## What is left

1. **Promote `asm2` or keep `asm1` as the witness.** `asm1` is still the thing the hand-emitted
   references and all historical records were checked against; it must not be deleted. The next
   decision is whether `make` should build the assembler from `src/asm1.c` (with `cc` + `asm1`) and
   what `seed/` means after that — recorded, not assumed.
2. **`.data`** — a second read-write `PT_LOAD`, and string literals in memory.
3. **Assembler gaps**: `add r32, imm32`, `cmp`/`mov` with `[mem]`, signed condition codes,
   `[base+index*scale]`.
4. **The 2 048-label and 200 000-byte inputs are now shared limits**; if either grows again, both
   `asm1.c` and the compiler's frame must move in the same wave.

## Where things are

| | |
|---|---|
| `AGENTS.md` | invariants with their checks |
| `docs/cc.md` | the compiler's stages and gates; Stage 12 is `asm2` |
| `docs/ROADMAP.md` | the ordered plan and its history |
| `docs/WAVES.md` | the log, failures included |
| `docs/encodings.md` | chosen encodings |
| `docs/oracles.md` | what `ref/` does and does not prove |
| `seed/README.md` | the bootstrap chain |
| `tests/coverage/forms.tsv` | the claim of what is supported |
| `tools/asm2-check.sh` | the D3 gate |
| `docs/toolchain.tsv`, `docs/provenance.tsv`, `docs/SHAS`, `docs/asm1.sha` | the records |
| `docs/violations/` | recorded violations, including this session's |
