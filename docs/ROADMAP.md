# Roadmap: from a fixture-printer to a language

## Where we are

`asm0a` (3 745 bytes, hand-written machine code) assembles `src/asm1.s` into `asm1` (4 295 bytes),
and `asm1` assembles itself to the same bytes — `X' == X`, idempotent. `asm1` builds all 18
fixtures byte-identically to their hand-emitted references, every artifact is attributable to an
assembler sha via `docs/provenance.tsv`, and `make check` verifies pinned shas, branch decodes and
provenance.

That is a *bootstrap*. What it is not yet is a *language*, and there is one thing it gets wrong in a
way that matters more than any missing feature.

## Stage 0 — rejection parity (blocking; do this first)

`asm1` silently truncates where `asm0a` rejects:

```
mov bl, 300           asm0a rejects    asm1 emits b3 2c       300 & 0xFF
add bl, 200           asm0a rejects    asm1 emits 80 c3 c8    200 read as signed -56
cmp bl, 200           asm0a rejects    asm1 emits 80 fb c8
db 300                asm0a rejects    asm1 emits 2c
mov eax, [rbx+1000]   asm0a rejects    asm1 emits 8b 43 e8    disp8 wraps to 0xe8
mov eax, [rbp+200]    asm0a rejects    asm1 emits 8b 45 c8
lea rax, [rsp+1000]   asm0a rejects    asm1 emits disp 0xe8

and the worst of them, because it corrupts control flow rather than data:

jz x (x is 202 bytes back)   asm0a rejects    asm1 emits rel8 0x36   (-202 wrapped)
jmp skip (skip is 200 ahead) asm0a rejects    asm1 emits rel8 0xc8
```

Every one is a program that assembles cleanly and does the wrong thing. They are latent only because
`asm1.s`'s own source stays in range — the fixpoint is not evidence of correctness here, and neither
is the fixture corpus, which contains no out-of-range value anywhere.

This inverts the project's oldest rule: *reject rather than truncate, and fail loudly*. `asm0a` does.
`asm1` must.

Work: range-check imm8 (0..255 for `mov r8`, −128..127 for `add`/`cmp r8`), disp8 (−128..127),
imm32, rel8 (±127), label name length (≤7), label count (≤128) in `asm1` as `asm0a` does.

**Gate, and it is a new kind of gate:** a suite of sources that *must be rejected* —
`tests/reject/*.s` — with `make test` requiring a non-zero exit **and no output bytes** from both
assemblers. Until now every test was positive. A positive suite cannot see a truncation, because a
truncated encoding is still an encoding.

## Stage 1 — literals and expressions

Today: decimal only, no negatives, no hex, no character literals, no symbol arithmetic. That is why
`asm1` patches ELF sizes at fixed offsets instead of computing `end - start`.

- `0x` hex, `'c'` character, unary `-`, and `+`/`-` between a symbol and a constant
- symbols carry values, so `filesz = data_end - data_start` becomes expressible
- `times n db v`-style repetition, if it earns its place

**Gate:** a fixture per literal form, hand-emitted first; the 18 existing fixtures must stay
byte-identical; `X' == X` must still hold.

## Stage 2 — sections, and a data segment that is not executable

`asm1`'s program header is one `R+X` `PT_LOAD` and its entry point is `0x400078 + 0`. That is why its
own header template had to be *readable at a fixed address* and why the emit path is byte-at-a-time:
there is nowhere to put data.

- `.text` / `.data` / `entry`, two program headers, data `R+W`
- this deletes `asm1`'s fixed-address template hack and lets data be addressed by label

**Gate:** `asm1`'s own source rewritten to use `.data` for its template, `X' == X` still holding, and
`docs/provenance.tsv` re-recorded deliberately.

## Stage 3 — the instruction set a real program needs

Currently the register file is 8 registers, addressing is `[base]` and `[base+disp8]`, and there is
no shift, bitwise, or multiply. A program bigger than a fixture hits that wall immediately.

- `r8`–`r15` via REX.B/R/X; indexed `[base+index*scale+disp8/32]`; disp32
- `push`/`pop`, `imul`, `shl`/`shr`/`sar`, `and`/`or`/`test`
- rejects stay rejects: every new form needs its own out-of-range cases (Stage 0's lesson)

**Gate:** each form hand-emitted as a fixture; one "torture" fixture using all of them, judged
behaviourally as well as by bytes.

## Stage 4 — say *what* is wrong, on which line

`asm1` exits 1. A real assembler names the line and the reason. `asm1` can write bytes, so it can
write `src/x.s:42: displacement 1000 does not fit in disp8` — but it needs line tracking and decimal
output, which is real work in this dialect (16-bit division by 10 for multi-digit numbers).

**Gate:** the negative suite asserts the *message text*, not just the exit code. Exit status is not
evidence; a rejection and a crash both exit non-zero.

## Stage 5 — close the loop on the hand-written bytes

`asm0a` is 3 745 bytes nobody has a source for. Write `src/asm0a.s` in the new dialect and require:

    ./asm1 < src/asm0a.s | cmp - asm0a

If that holds, the hand-emitted binary is *explained* by a source file, and provenance finally starts
at text rather than at bytes. That is the strongest true statement of "from nothing" this project can
make, and it is only reachable after Stages 1–3, because `asm0a` uses forms `asm1` cannot yet encode.

**Gate:** byte-identity against the frozen `asm0a`, and `docs/provenance.tsv` recording `asm0a` as
derived as well as hand-written.

## Stage 6 — a self-testing assembler

A generator written *in the dialect* (no scripts, per the project's rules) that emits sources and
requires `asm1` and `asm0a` to agree byte for byte on all of them — differential testing where both
sides are hand-built and neither is an oracle for the other. Seeded, so a failure is reproducible,
and the corpus committed so it grows monotonically.

## What stays out, deliberately

- **No linker.** One source file, one executable. `asm0a` and `asm1` both do this; keep it.
- **No optimisation.** Bytes out are bytes written.
- **No GNU `as` compatibility for its own sake.** Encodings are chosen, documented in
  `docs/encodings.md`, and pinned by branch/site decodes — matching GNU is not a goal.
- **No second mechanism.** Stage 2 deletes a hack rather than adding a layer; Stage 0 adds checks,
  not parallel code paths. If a stage needs two ways to do one thing, the stage is wrong.

## Ordering rationale

Stage 0 first because a silently miscompiled program invalidates every other claim — including the
fixture corpus, which cannot detect it. Stage 1 before 3 because expressions are what make data
buffers and `.data` sizes expressible. Stage 2 before 5 because `asm0a.s` will want a data segment.
Stages 3 and 4 can interleave; Stage 6 last because a generator is only worth writing once the
language stops changing shape underneath it.

## A note on the build rule, before Stage 0

`asm0a` is frozen, and from now on `src/asm1.s` is built by `seed/asm1` — the promoted previous
stage — not by the binary it produces. `make promote` replaces the seed and is the only thing that
does; `make bootstrap-check` additionally requires `asm0a` and `seed/asm1`, two independent
implementations, to agree on `src/asm1.s`.

That check is the reason Stage 1 is the interesting one: hex literals, `.data` and `r8`–`r15` all
make `src/asm1.s` unparseable by `asm0a`, at which point the cross-check between the two
implementations ends and only the seed remains. `bootstrap-check` says so out loud rather than
passing quietly, and after that point the safety net is `ref/` plus the fixture corpus, which is
why Stage 0's rejection suite matters more afterwards, not less.

### Stage 1 progress: literals done, expressions open

`asm1` now parses **hex literals** (`0x1f`, lowercase digits) and **character literals** (`'A'`),
everywhere a number was accepted: immediates, `db` values, displacements.

These are the first forms `asm1` accepts that `asm0a` cannot parse, so they needed an oracle that no
reference binary could supply — nobody hand-emitted syntax that did not exist. The oracle is the old
spelling of the same thing:

    tests/capability/hex.cap.s       mov eax, 0x10      asm0a rejects
    tests/capability/hex.ref.s       mov eax, 16        asm0a accepts

`make test-capability` requires that `asm0a` reject the `.cap` spelling, accept the `.ref` spelling,
and that `asm1` produce **identical bytes** for both. Two spellings, one encoding: if they ever
differ, one of them is wrong. Four pairs so far (hex, char, a mask, a hex displacement).

Still open in Stage 1: negative literals and **symbol arithmetic** (`filesz = end - start`). Both
need a value model rather than a number parser — a symbol table whose entries can be subtracted —
which is the part of Stage 1 that changes `asm1`'s architecture rather than extending it.

Note what did *not* happen yet: `src/asm1.s` has not been rewritten to use hex, so `asm0a` can still
parse it and `make bootstrap-check` still holds. That cross-check between two independent
implementations is worth keeping for as long as possible; the handover will happen when the source
starts using the new syntax, and it will be visible.

### Stage 1, second increment: negatives, negative displacements — and the source outgrowing its own buffer

`asm1` 4587 → 4680 bytes. Negative literals (`-1`), and `[rbp-8]` / `[rbx-100]` (negative displacements
were previously unrepresentable, which is why the label table needed a `sub`-based address).

Range checks became **signed**: the value is biased by +128 and compared unsigned, so `-128..127`
maps onto `0..255`. That is the same trick the `rel8` check already used. Sites that take a byte
immediate now accept `-128..255`; `add`/`cmp r8` and `disp8` accept `-128..127`.

**Then the source outgrew the assembler's own input buffer.** `src/asm1.s` reached 24 581 bytes while
`asm1` read at most 24 000, so the seed silently assembled a *truncated* source and failed with a
bare exit 1. `asm0a` reads 65 536, which is why it still accepted — two builders, one of them
silently seeing a prefix.

The failure mode is the defect, not the size: **a short read was treated as the whole input.** Two
changes:

1. A read that returns exactly the buffer size now **fails loudly** — the source may have been cut,
   and a prefix is not a source.
2. A larger buffer was tried first (60 KB at `rbp-70000`) and *partially worked*: `read` returned
   22 021 of 26 000 bytes because the kernel only copies into pages already mapped below `rsp`.
   Measured, not assumed. The buffer stayed at the proven `rbp-26000` / 24 000.

So the source had to shrink: 24 581 → **17 004 bytes** by deleting inline comments, keeping every
full-line comment. The detail they carried lives in this file and `docs/WAVES.md`, which is where the
project's own rule puts prose that repeats what the code already says.

Checked that stripping comments changed no semantics: `asm0a` produced the identical 4 680 bytes
before and after.

After that the seed could read the source again, so the build went back through `seed/asm1` as the
invariant requires — no exception was needed, and `bootstrap-check` still has `asm0a` agree.
