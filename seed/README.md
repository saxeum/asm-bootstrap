# seed/ — the bootstrap toolchain

`asm0a` is frozen: it is 3 745 bytes of hand-written machine code and it does not change.

The live assembler is `src/asm1.c`; the live compiler is `src/cc.c`. They are built from the
promoted C seeds, and `asm1`/`cc` must reproduce themselves:

    seed/cc1 < src/asm1.c > text ; seed/asm1 < text > asm1
    cc       < src/asm1.c > text ; asm1      < text > asm1b ; cmp asm1 asm1b
    seed/cc1 < src/cc.c   > text ; asm1      < text > cc
    cc       < src/cc.c   > text ; asm1      < text > cc2   ; cmp cc cc2

A binary never builds *itself* from its own output. The seed is the authority, and it is replaced
only by `make promote`, as a deliberate act with a diff to read — because promoting is the assertion
"this new stage is good", and a build step that promoted automatically would make the chain
unfalsifiable.

`src/asm1.s` and `src/cc.s` are frozen historical witnesses: they are pinned by `docs/frozen.tsv`,
and `make test-frozen` assembles `src/cc.s` with `asm1` and compares it with `seed/cc`.

## Why a committed binary

Because the alternative is a self-referential build. If `asm1` were built by whatever `asm1` happened
to be lying around, a miscompilation could be preserved across generations with nothing to compare
against — the same failure the fixpoint alone cannot exclude, which is why `ref/count10` (hand-written
before any of this existed) is part of the gate.

Committing the seeds also means a fresh clone can build the C tools without any assembly-built
compiler.

## The chain

`docs/toolchain.tsv` records every promotion: the new stage's sha256, the builder that produced it,
and that builder's sha256. The chain runs back to `asm0a`, which is the one link with no builder —
`docs/toolchain.tsv` says so explicitly rather than leaving the column blank.

## `seed/asm1`, `seed/cc1` and `seed/cc`

- `seed/asm1` (54 416 bytes, `ccb1607d…`) is the promoted C assembler.
- `seed/cc1` (44 154 bytes, `5e9ad682…`) is the promoted C compiler.
- `seed/cc` (10 429 bytes, `a81345ad…`) is the frozen dialect compiler: `asm1` built from `src/cc.s`.
  It is kept as the witness for `make test-cc-source` and as the pre-signed compiler the differential
  can fail against; `make from-c` uses `seed/cc1`, not it.

`docs/SHAS` pins all three.
