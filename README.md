# asm-bootstrap

An assembler built from nothing: hand-written machine code that assembles source into Linux
ELF executables. **No compiler, no system assembler, no interpreter** — every artifact was
produced by bytes written by hand, and every wave is judged by whether it reproduces a
previous artifact *byte for byte*.

The PDP-8 bootstrap done again deliberately: hand-assemble a minimal assembler, let it
assemble a better one, repeat. `docs/pdp8-to-gcc.md` has the history and the line that leads
to `as` and `gcc`; `docs/WAVES.md` is the log, including the failures.

## Use it

`asm0a` reads source on **stdin** and writes the executable on **stdout**. It takes no
arguments, so the shell supplies the filenames:

```bash
./asm0a < src/count10.s > count10
chmod +x count10        # required: asm0a cannot chmod a pipe
./count10               # prints 1..10
```

To prove the output is the *verified* object and not merely something that runs:

```bash
./asm0a < src/count10.s | cmp - ref/count10 && echo identical
```

## Self-hosting: it assembles itself

`src/asm1.s` is an assembler written **in the language it assembles**. `asm0a` — the hand-emitted
bootstrap — builds it once; after that the only tool needed is the artifact itself.

```bash
./asm0a < src/asm1.s > asm1
```

```bash
chmod +x asm1 && ./asm1 < src/asm1.s > asm1b
```

```bash
cmp asm1 asm1b && echo identical
```

The second generation is byte-identical to the first (`4295` bytes, sha256 `250e02c9…`), and so is
the third — the fixpoint is reached, not merely approached.

That the result is a *working* assembler, and not a coincidentally equal blob, is a separate check:

```bash
chmod +x asm1b && ./asm1b < src/count10.s | cmp - ref/count10 && echo identical
```

Three generations deep, it still reproduces the hand-emitted oracle exactly, and the binary it
produces prints `1`…`10`.

## State

| | |
|---|---|
| bootstrap | `asm0a`, 3745 bytes, `e_entry` = 0x400110, one R+X `PT_LOAD`, sha256 in `docs/SHAS` |
| self-hosted | `asm1`, 4295 bytes, sha256 `250e02c9…`, built by `asm0a` from `src/asm1.s` (1146 lines) |
| fixpoint | `asm0a(asm1.s) == asm1(asm1.s) == asm1(asm1.s)(asm1.s)`, all 4295 bytes, one sha256 |
| fixtures | 18, all byte-identical to hand-emitted references and behaviourally correct |
| branches | 290 sites pinned in `docs/branches.tsv`, verified by decoding |
| source language | `mov` in 8/32/64-bit widths, `movzx` from registers and memory, `lea`, `add`/`sub`/`cmp`/`xor`/`inc`/`dec`/`div`, `call`/`ret`, `jmp`/`jz`/`jnz`/`jb` with `rel8` and `.l` `rel32`, `syscall`, `db` with strings and escapes, labels, two passes, decimal immediates |

`src/asm1.s` assembles every fixture, including `src/count10.s` → exactly `ref/count10`.


`ref/` holds binaries written by hand **before** the assembler could read their source. They are
never regenerated casually: a binary whose bytes you did not write cannot judge an assembler.
`docs/oracles.md` explains what those references do and do not prove, and why byte-identity with
a hand-written reference is a floor rather than a proof.
