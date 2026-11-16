# seed/ — the bootstrap toolchain

`asm0a` is frozen: it is 3 745 bytes of hand-written machine code and it does not change.

`seed/asm1` is the **promoted** `asm1`: the binary that builds the next one. Development happens in
`src/asm1.s`, and the rule is:

    seed/asm1 < src/asm1.s > asm1        build the new assembler with the previous one
    asm1      < src/asm1.s > asm1b       the new assembler must reproduce itself
    cmp asm1 asm1b                       or the build is not trusted

A binary never builds *itself* from its own output. The seed is the authority, and it is replaced
only by `make promote`, as a deliberate act with a diff to read — because promoting is the assertion
"this new stage is good", and a build step that promoted automatically would make the chain
unfalsifiable.

## Why a committed binary

Because the alternative is a self-referential build. If `asm1` were built by whatever `asm1` happened
to be lying around, a miscompilation could be preserved across generations with nothing to compare
against — the same failure the fixpoint alone cannot exclude, which is why `ref/count10` (hand-written
before any of this existed) is part of the gate.

Committing the seed also means a fresh clone can build without `asm0a` once the dialect outgrows it —
which happens in Stage 1 of `docs/ROADMAP.md`, the first time `src/asm1.s` uses a form `asm0a` cannot
parse. Until then, both paths are checked and must agree.

## The chain

`docs/toolchain.tsv` records every promotion: the new stage's sha256, the builder that produced it,
and that builder's sha256. The chain runs back to `asm0a`, which is the one link with no builder —
`docs/toolchain.tsv` says so explicitly rather than leaving the column blank.

## `seed/cc`

`seed/cc` (10 429 bytes, sha256 `a81345ad5a67490d…`) is the frozen C compiler seed: `cc` built by
`asm1` from `src/cc.s`. It is what `make from-c` uses, together with `seed/asm1`, to compile
`src/asm1.c` and `src/cc.c` from scratch. It is a copy of the recorded `cc` artifact, not a new
implementation; `docs/SHAS` pins it.
