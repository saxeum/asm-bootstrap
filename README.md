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

## State

| | |
|---|---|
| artifact | `asm0a`, 3125 bytes, `e_entry` = 0x400110, one R+X `PT_LOAD` |
| identity | sha256 in `docs/SHAS` |
| fixtures | 15, all byte-identical to hand-emitted references and behaviourally correct |
| branches | 235 sites pinned in `docs/branches.tsv`, all verified by decoding |
| source language | 8-, 32- and 64-bit operands, memory operands, labels, two passes, decimal immediates |

`src/count10.s` — the largest oracle — assembles to exactly `ref/count10` (188 bytes) and the
result prints `1`…`10`.

## Verify

```bash
sha256sum -c docs/SHAS            # every artifact matches its recorded sha
tools/check-branches.sh           # 235 pinned branch sites still decode to their targets
tools/check-branches.sh --selftest # and the checker rejects three known-bad sites
```

`--selftest` is the important one: a checker that cannot fail is decoration. It is run against
`0x15e`, `0x5c5` and `0x1b6` — three sites that were genuinely wrong in waves 2d-5/2d-6/2d-7 —
and must report failure.

## What the dialect accepts

One instruction per line; labels; `;` comments; `entry` is **not** implemented (the entry point
is always `0x400078 + code offset`, which means data must follow code).

| category | forms |
|---|---|
| moves | `mov r32,imm32` · `mov r8,imm8` · `mov r32,r32` · `movzx r32,r8` |
| memory | `mov r32,[mem]` · `mov [mem],r32` · `mov [mem],r8` · `mov byte [mem],imm8` · `lea r32\|r64,[mem]` |
| ALU | `add r8,imm8` · `cmp r8,imm8` · `cmp r32,imm32` · `inc`/`dec r8` and `r32` · `div r8` · `sub r64,r64` · `xor r32,r32` |
| control | `jmp` · `jz` · `jnz` · `jb` — **rel8 only, ±127 bytes** |
| other | `syscall` · `db "…"` · `db n,n,n` |

Addressing is `[base]` or `[base+disp8]`; base may be any 32- or 64-bit register. Immediates
are **decimal only**.

## Known limits (open, not hidden)

- **No rel32 branches.** A jump beyond ±127 bytes fails rather than wrapping. This is the last
  blocker for writing the assembler *in its own dialect*.
- **Three parses are still silent**, and are the next target: `mov eax, 0x10`, `add al, -1` and
  `db 0x48` assemble as `0`; `mov bl, 256` truncates to 0. A validating end-of-line handler is
  written and works, but four handlers (`do_xor`, `regop`, `do_br` ×2) leave the parse cursor
  *at* their last operand rather than past it, so they must be fixed before it can land.
- **No `entry`**, so data must follow code and its addresses are decimal literals.
- 32 labels maximum, 7-character names, no `test`/`imul` (needed for `fib`, not for
  self-hosting).

## Provenance

`ref/` holds binaries written by hand **before** the assembler could read their source. They are
never regenerated casually: a binary whose bytes you did not write cannot judge an assembler.
`docs/oracles.md` explains what those references do and do not prove, and why byte-identity with
a hand-written reference is a floor rather than a proof.
