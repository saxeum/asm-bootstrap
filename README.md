# asm-bootstrap

An assembler built from nothing: hand-written machine code that assembles source into Linux
ELF executables. **No compiler, no system assembler, no interpreter, no scripts** — each
artifact is produced by bytes written by hand, and every wave is judged by whether it
reproduces a previous artifact *byte for byte*.

This is the PDP-8 bootstrap exercise done again, deliberately: hand-assemble a minimal
assembler, let it assemble a better one, repeat. See
[`docs/pdp8-to-gcc.md`](docs/pdp8-to-gcc.md) for the history that motivates it (PAL-III, its
unknown original author, the paper-tape two-pass design, and the line that leads to `as` and
`gcc`) and for the staged plan.

## Status

| Wave | Artifact | Size | sha256 | Judge |
|---|---|---|---|---|
| 0 | `hello` | 165 B | `4f386903…6552e1` | hand-emitted; prints `Hello, World!` |
| 0 | `count10` | 188 B | `e61a23c9…94ec5bd9a` | hand-emitted; prints `1`..`10` |
| 0 | `fib` | 334 B | `f61cea2c…2e10098` | hand-emitted; `fib(0..93)` matches OEIS A000045 |
| 1a | `asm0a` | 664 B | `255ac2e1…3aa5e60` | assembles `src/exit42.s`, byte-identical to hand-written |
| 1b | `asm0a` | 833 B | `9192d28f…16fa7989` | assembles `src/hello_num.s` → **equals `hello`**, sha `4f386903…` |
| 2a | `asm0a` | 883 B | `5f1ba8cf…71299fa7` | relayout: data first, bounds checks in every scan loop; both oracles unchanged |
| 1c | — | — | — | labels + `entry` + two passes, so `src/hello.s` assembles |
| 2 | — | — | — | relative jumps; `src/count10.s` → sha `e61a23c9…` |
| 3 | — | — | — | fixpoint: `asmN.s` assembled by `asmN` equals `asmN` |

`asm0a` currently understands `mov r32,imm`, `xor r32,r32`, `syscall`, `db "…"` (escapes
`\n \t \" \\`), decimal immediates only. No labels, no jumps, no hex literals.

## Verify it yourself

```bash
sha256sum -c docs/SHAS                                 # every artifact matches its recorded sha

./asm0a < src/hello_num.s | cmp - hello && echo ok      # wave 1b: byte-identical to hand bytes

./asm0a < src/exit42.s > /tmp/e && chmod +x /tmp/e      # wave 1a
/tmp/e; echo $?                                        # 42
```

The oracle rule: an assembler is correct when its output is **byte-identical** to bytes
written by hand. Exit status is never evidence — this project shipped a 186-byte program
that printed nothing and exited 0, and found four defects in `asm0a` that only execution
exposed.

## Layout

```
asm0a            the wave-1 assembler (hand-emitted machine code, 833 bytes)
hello count10 fib  wave-0 reference binaries — the oracles
src/*.s          sources: hello.s (symbolic), hello_num.s (numeric), exit42.s
docs/WAVES.md    the log: what passed, what broke, why, and what is next
docs/SHAS        the gate
docs/wave1a-asm0a.md   annotated byte listing of asm0a + the four defects found
docs/pdp8-to-gcc.md    PDP-8 assembler history, references, and the bootstrap plan
```

## Known defects (open, not hidden)

- `mov eax,` with no operand assembles as `mov eax, 0` and exits 0 — number parsing needs an
  "at least one digit" flag (arrives in 2b).
- No overflow check on `mov` immediates.
- No labels, no jumps yet (wave 2b).
- Source is read from stdin; output goes to stdout, so the caller must `chmod +x`.

Fixed in 2a: `db "unterminated` used to SIGSEGV, because the scan loop had no bound against
the source end. Every scan loop now checks `rbx >= r13` first and exits 1.

## Build rule

`printf` writes literal bytes; nothing derives instructions from mnemonics except `asm0a`
itself. No `as`, `ld`, `nasm`, `objcopy`, and no assembler written in another language —
[`docs/pdp8-to-gcc.md`](docs/pdp8-to-gcc.md) explains why that is the whole point.
