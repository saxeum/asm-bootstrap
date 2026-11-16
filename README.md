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
    built by asm1 (sha256 250e02c95d3adbb3) as count10
```

Unknown content exits non-zero rather than saying nothing.

`make check` now verifies four things, and each can fail: the pinned artifact shas, that this `asm1`
is the recorded one, that the ledger reproduces exactly, and that every pinned branch decodes as
recorded. If `src/asm1.s` is edited and the ledger is not re-recorded, `make check` says so and
names the command to fix it.

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
| self-hosted | `asm1`, 5515 bytes, sha256 `26e20a1eb8f6308c…`, built by `seed/asm1` from `src/asm1.s` (1263 lines, 17004 bytes) |
| seed | `seed/asm1`, 5515 bytes, the promoted stage that builds the next one (sha256 in `docs/SHAS`) |
| builder | `asm1` is built by `seed/asm1`, never by itself. Since the source needs more than 128 labels, `asm0a` can no longer parse it: `make bootstrap-check` reports NOT APPLICABLE |
| fixpoint | `asm1(asm1.s) == asm1`, 5515 bytes, one sha256, idempotent |
| fixtures | 18, all byte-identical to hand-emitted references and behaviourally correct |
| rejections | 11 sources that must be refused by both assemblers, with no output (`tests/reject/`) |
| capability | 11 pairs where asm1 accepts syntax asm0a cannot parse; both spellings must agree byte for byte |
| superior | asm1 assembles a 99 KB source asm0a cannot, and a chosen `entry` point -- both must RUN |
| branches | 290 sites pinned in `docs/branches.tsv`, verified by decoding |
| source language | `mov` in 8/32/64-bit widths, `movzx` from registers and memory, `lea`, `add`/`sub`/`cmp`/`xor`/`inc`/`dec`/`div`, `call`/`ret`, `jmp`/`jz`/`jnz`/`jb` with `rel8` and `.l` `rel32`, `syscall`, `db` with strings and escapes, labels, two passes, decimal immediates |

`src/asm1.s` assembles every fixture, including `src/count10.s` → exactly `ref/count10`.


`ref/` holds binaries written by hand **before** the assembler could read their source. They are
never regenerated casually: a binary whose bytes you did not write cannot judge an assembler.
`docs/oracles.md` explains what those references do and do not prove, and why byte-identity with
a hand-written reference is a floor rather than a proof.
