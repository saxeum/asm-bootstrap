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
bootstrap — builds it once; after that the only tool needed is the artifact itself. From here on the
supported build is `make`, which uses `seed/asm1`; that `asm0a` produces the same bytes is the
cross-check `make bootstrap-check` asserts.

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


## Provenance: which assembler built this?

`asm0a` is frozen, and from here on only `src/asm1.s` moves — so `asm1` changes, and an artifact is
only meaningful together with *which build of which assembler* produced it. "asm1" identifies
nothing once asm1 has been rebuilt, so every record is a sha256 pair.

`docs/provenance.tsv` — one line per artifact per assembler:

```
addr32  734b5a48…  asm0a  6271c5ee…       artifact sha, assembler, assembler sha
addr32  734b5a48…  asm1   250e02c9…
```

`docs/asm1.sha` pins the sha256 of the current `asm1`, so the build is identified as a *content*
claim rather than by name.

```bash
make record
```

rebuilds everything and rewrites both files. It is the only thing that writes them — recording is an
assertion that a change is intended, and a build step that absorbed drift silently is exactly how a
stale record goes unnoticed.

```bash
make which FILE=count10
```

answers the question directly, by looking the file's content sha up in the ledger:

```
  count10  sha256 e61a23c9ef326d27...
    built by asm0a (sha256 6271c5ee79034ffd) as count10
    built by asm1 (sha256 2b4aada60da42df8) as count10
```

Unknown content exits non-zero rather than saying nothing.

`make check` verifies six things, and each can fail: that no compiler, assembler, disassembler or
debugger is invoked anywhere in the Makefile or `tools/`; the pinned artifact shas; that this `asm1`
is the recorded one; that the ledger reproduces exactly; that every one of the 290 pinned branches
decodes as recorded — by `src/dis.s`, our own decoder, not by a binutils one; and that every form the
assembler claims to support is reached by at least one test input. If `src/asm1.s` is edited and the
ledger is not re-recorded, `make check` says so and names the command to fix it.

## The bootstrap chain

`asm0a` is frozen. From here on, `src/asm1.s` is built by **`seed/asm1`** — the promoted previous
stage — and never by the binary it produces:

```bash
make
```

is this rule:

```
seed/asm1 < src/asm1.s > asm1        build the new stage with the previous one
asm1      < src/asm1.s > asm1b       the new stage must reproduce itself
cmp asm1 asm1b                       or the build is not trusted
```

A binary is never its own reference. If `asm1` were built by whatever `asm1` was lying around, a
miscompilation would be preserved across generations with nothing to compare against — the failure
mode the fixpoint alone cannot exclude, which is why `ref/count10`, written by hand before any of
this existed, is part of the gate too.

```bash
make promote
```

replaces `seed/asm1` and is the only thing that does. It is a deliberate act with a diff to read,
because promoting asserts "this stage is good", and an automatic promote would make the chain
unfalsifiable. `docs/toolchain.tsv` records every promotion: the stage's sha256, its builder, and
that builder's sha256. The chain runs back to `asm0a`, the one link with no builder — recorded as
`-`, because a blank would read like an omission rather than a fact.

```bash
make bootstrap-check
```

requires that `asm0a` and `seed/asm1` — two independent implementations — agree on `src/asm1.s`.
That agreement disappears the moment `src/asm1.s` uses a form `asm0a` cannot parse, which is the
first thing Stage 1 of `docs/ROADMAP.md` makes possible. When that happens the target says
**NOT APPLICABLE** out loud and names the reason. It does not pass quietly: a check that cannot run
is not a check that passed.
## Milestones

Two tags mark the points where the project changed kind. Both carry the evidence in the tag message,
so `git tag -n99` reads without the repository.

| tag | commit | what it marks |
|---|---|---|
| `milestone-fixpoint` | `c2240bf` | `asm1` assembles itself: `X == X' == X''`, 4295 bytes, one sha256 |
| `milestone-handover` | `c806e95` | `asm1` is better than `asm0a` — and `asm0a` can no longer build it |

Rebuilding the fixpoint tag. There was no `Makefile` at that commit, so the path is the two commands
the commit itself documents:

```bash
mkdir -p /tmp/fx && git archive milestone-fixpoint | tar -x -C /tmp/fx && cd /tmp/fx && ./asm0a < src/asm1.s > X && chmod +x X && ./X < src/asm1.s > Xp && cmp X Xp && echo identical
```

Rebuilding the handover tag, where `asm0a` is no longer a valid builder and `make` uses `seed/asm1`:

```bash
mkdir -p /tmp/ho && git archive milestone-handover | tar -x -C /tmp/ho && cd /tmp/ho && make > /dev/null && ./asm1 < src/asm1.s | cmp - asm1 && echo identical
```

Each prints `identical`, and `milestone-fixpoint` produces 4295 bytes with sha256 `250e02c9…` while
`milestone-handover` produces 5094 bytes with sha256 `7a10451b…` — the values the tag messages claim.

## State

| | |
|---|---|
| bootstrap | `asm0a`, 3745 bytes, `e_entry` = 0x400110, one R+X `PT_LOAD`, sha256 in `docs/SHAS` |
| self-hosted | `asm1`, 7506 bytes, sha256 `9ae3db24b9d814dd…`, built by `seed/asm1` from `src/asm1.s` (2049 lines, 28535 bytes) |
| seed | `seed/asm1`, 7506 bytes, the promoted stage that builds the next one (sha256 in `docs/SHAS`) |
| builder | `asm1` is built by `seed/asm1`, never by itself. Since the source needs more than 128 labels, `asm0a` can no longer parse it: `make bootstrap-check` reports NOT APPLICABLE |
| fixpoint | `asm1(asm1.s) == asm1`, 7506 bytes, one sha256, idempotent |
| fixtures | 18, all byte-identical to hand-emitted references and behaviourally correct |
| rejections | 12 sources refused by both assemblers with no output, and 5 exact messages: line number *and* reason |
| capability | 30 pairs where asm1 accepts syntax asm0a cannot parse; both spellings must agree byte for byte |
| coverage | 88 claimed forms, each required to appear in a test input (`make test-coverage`) — the gate that says which paths nothing has ever executed |
| superior | five cases where asm1 is right and asm0a is not (`and`-as-`add`, `[rbp]` disp 0, a negative disp, 64-bit vs 32-bit width, `r8`–`r15`), each against a hand-computed body; plus a 99 KB source, a chosen `entry` point and r8d arithmetic, all of which must RUN |
| branches | 290 sites in `docs/branches.tsv`, all decoded by `src/dis.s` — a decoder written in the dialect and assembled by `asm1`, because a system disassembler is forbidden |
| source language | `mov`, `add`, `sub`, `cmp`, `and`, `or`, `test`, `xor`, `inc`, `dec`, `neg`, `not`, `shl`/`shr`/`sar`, `imul` in 8-bit (where it exists), 32-bit and 64-bit forms — the width comes from the operand names, and a mixed pair is refused; registers `rax`…`r15` (`r8d`–`r15d` for the 32-bit forms) with `REX.R`/`X`/`B`, `movzx` from registers and memory, `lea`, `div`, `push`/`pop`, `call`/`ret`, branches rel8 and `.l` rel32, `[base]` and `[base+index]`, `syscall`, `db` with strings, labels, expressions, `entry`, two-pass assembly with validation, hex/char/negative literals |
| compiler | `cc`, 2030 bytes, built by `asm1` from `src/cc.s`: `helloworld.c` → dialect text → `asm1` → a binary that prints `Hello, World!`. It emits TEXT, so its output is diffed against a hand-written golden (`make test-cc`, `docs/cc.md`) |

`src/asm1.s` assembles every fixture, including `src/count10.s` → exactly `ref/count10`.

```bash
make hello
```

compiles `helloworld.c`, assembles the result and prints `Hello, World!`. The two stages are visible
and the second one is not optional:

```bash
./cc < helloworld.c > hello.s     the compiler writes dialect TEXT
./asm1 < hello.s > hello          the assembler is what makes a program
```

`cc` emits text and not bytes on purpose: its output is a reviewable file that is compared byte for
byte against a hand-written golden, and `asm1` stays the only thing that produces an executable, so
every gate above applies to the compiler's output too. The text begins with a `;` comment saying what
it is — a comment to the assembler, a shell syntax error to anything that tries to run it directly.

`ref/` holds binaries written by hand **before** the assembler could read their source. They are
never regenerated casually: a binary whose bytes you did not write cannot judge an assembler.
`docs/oracles.md` explains what those references do and do not prove, and why byte-identity with
a hand-written reference is a floor rather than a proof.
