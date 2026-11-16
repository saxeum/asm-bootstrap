# Roadmap: from a fixture-printer to a language

## Where we are

The compiler is self-hosting. `cc` (44 238 bytes, built by `asm1` from `src/cc.c`) compiles
`src/cc.c` — the same compiler written in the subset — to `cc1.s`; `asm1` assembles it to `cc1`; and
`cc1` compiles `src/cc.c` to the same text. `make test-d2` is that proof, and `make test-port`
compares the port's output with `cc`'s on all 43 goldens (byte for byte). `asm1` (54 416 bytes, built from `src/asm1.c`) is
self-hosting, produces the 18 hand-emitted `ref/` binaries, and its branch pins are decoded by
`src/dis.s`; `docs/provenance.tsv` records every artifact.

`docs/continue-here.md` is the authoritative current state and the next task. **This file is the
ordered plan and its history**: sections below were true when written and some of their limits were
raised later. The bootstrap endgame is reached: `src/asm1.c` is compiled by `cc`, assembled by `asm1`
into `asm2`, and `make test-asm2` requires it to reproduce `asm1` byte for byte on the whole corpus
and to assemble its own compiler text into itself. Signed comparisons, `idiv` and `cqo` are in; the
next feature is `.data`, not another rewrite.

## History

The sections below are kept as the log of how the project got here. Where a limit is quoted (labels,
frame, buffers), the current numbers are in `docs/continue-here.md`; the important ones are 2 048
labels, a 65 536-byte frame, 64 000 bytes of arrays, 200 000-byte `cc` buffers, and 15-character
names.

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

## Being better than `asm0a`

Parity was the right first goal: chasing it found nine silent truncations. It is not the destination.
`asm0a` is a *bootstrap* — frozen, minimal, hand-written — and there is no reason `asm1` should stop
at reproducing it. Two measurements frame the gap:

```
hello_num.s, 99 000 bytes      asm0a: exit 1      asm1: exit 1        both refuse
hex/char/negative literals     asm0a: rejected    asm1: accepted      capability, 8 pairs
input limit                    asm0a: 65 536       asm1: 24 000        asm1 is WORSE
```

The last line matters most, and it is not a subtlety: on large inputs `asm1` is currently the weaker
tool. It also shows the shape of the work, because **`asm1` can become better without changing the
syntax it is written in** — and while it stays inside `asm0a`'s dialect, the cross-check between two
independent implementations survives.

### Phase 1 — better behaviour, no handover

`src/asm1.s` keeps using only forms `asm0a` parses, so `make bootstrap-check` still holds. The gains
are in what the assembler *does*, not what it accepts:

1. **No input size limit.** `asm0a` silently assumes ≤ 65 536 bytes; `asm1` currently assumes ≤ 24 000
   and refuses above it. Fix: chunked reads, advancing the pointer by a constant per chunk so a
   large source is read into a region the kernel maps as it goes. Gate: a source over 100 KB
   assembles to a working binary; `asm0a` fails on the same input.
2. **Say what is wrong, and where.** `asm0a` exits 1 in silence. `asm1` should print
   `line 42: displacement 1000 does not fit in disp8`. This needs line tracking and decimal output —
   real work in this dialect — and it is the single biggest usability difference.
3. **Never truncate input, and never emit a prefix.** Already true (`fail` on a full read); keep it
   true when reads become chunked.

Gates for this phase are *behavioural*: the binary's exit status and its stderr, both hand-specified
in the test. Nothing here needs an oracle derived from `asm0a`.

### Phase 2 — better syntax, and the handover

The first time `src/asm1.s` itself uses a form `asm0a` cannot parse, `make bootstrap-check` reports
**NOT APPLICABLE** and `seed/asm1` becomes the only builder. That is the moment `asm1` is
unambiguously better: the bootstrap can no longer reproduce the toolchain.

4. **Expressions** — `label+4`, `end - start`. Needs a value model that can say "not known yet",
   which is also what Stage 2 (`.data`) depends on, since section sizes are label differences.
5. **Sections** — `.text`, `.data`, `entry`, two program headers, a writable data segment. `asm0a`
   cannot express this at all, and `asm1`'s own fixed-address header template becomes unnecessary.
6. **Registers and addressing** — `r8`–`r15` via REX.B/R/X, `[base+index*scale+disp32]`, `push`/`pop`,
   `imul`, shifts, `and`/`or`/`test`.

### The oracle problem, and how it is already solved

Nothing above can be verified against `asm0a`, because `asm0a` rejects it. Three mechanisms, all of
which already exist in miniature:

- **Hand-computed bytes.** `mov eax, -1` is verified against `db 184, 255, 255, 255, 255` — bytes
  written by hand, in a form `asm0a` can assemble. Generalises to any new encoding: the reference is
  a `db` dump of the expected body.
- **Behaviour.** Run the produced binary and assert its output and exit status, hand-specified. This
  is the only oracle for features whose *effect* matters more than their encoding.
- **Equivalence.** Two spellings that must produce identical bytes (already: `0x10` vs `16`). Any new
  syntax gets a pair against an older spelling where one exists.

`tests/superior/` should become its own suite: every case asserts that `asm1` succeeds where `asm0a`
fails, with an independent expectation attached. It is the harness that replaces the `asm0a`
cross-check, and it must exist **before** the cross-check is lost, not after.

### What this means for the records

Once `asm1` outgrows `asm0a`, `docs/provenance.tsv` can no longer name `asm0a` as a builder for new
artifacts: it cannot build them. Provenance becomes a chain of `asm1` generations recorded in
`docs/toolchain.tsv`, and the fixtures' role changes — `ref/` stops being "what asm0a must equal" and
becomes "a hand-written program that any generation must still reproduce". The pinned sha, the
branch decodes and the seed chain carry the rest.

### Phase 1, item 1 done: `asm1` is now better than `asm0a` at input size

```
make test-superior
  superior: asm1 assembles 99032 bytes that asm0a cannot, and it runs (exit 42)
```

`asm0a` reads at most 65 536 bytes and `asm1` read 24 000, so **on large inputs `asm1` was the
weaker tool**. Both limits are gone: `asm1` now reads in 120-byte chunks until a short read, which
is bounded only by the region we reserve (200 000 bytes, refused above that rather than truncated).

The chunk size matters and the reason is not obvious. One large `read` does **not** work: the kernel
copies only into pages already mapped below `rsp`, so a 26 000-byte read 30 KB down returned 22 021
bytes — a silent partial read, which is how this whole defect was found. 120-byte chunks fault one
page at a time, and the kernel expands the stack for each, so reads now reach 300 KB — verified, not
assumed.

`asm1` 4 680 → **4 725 bytes**.

Gate: `tests/superior/` is a *behavioural* suite, because there is no `asm0a` output to compare
against — that is the point. The source is generated (9 000 instructions plus an exit with status
42), the test asserts `asm0a` fails on it, `asm1` succeeds, and the binary `asm1` produces **runs and
exits 42**. It also refuses to pass vacuously: if `asm0a` ever assembles the source, the test fails
saying it no longer discriminates.

Two self-inflicted defects, both from `sed` by line number:

- A deletion range applied *ascending* after an earlier deletion had shifted the file, so the second
  range removed a live line and 9 fixtures broke.
- The block I called "dead" `lblchk` was the live label scanner: the inline scan at `pline` jumps
  into it. Deleting it broke every fixture that uses a label.

Both were caught by the fixture corpus within one command, which is the argument for running it after
every structural edit rather than after the next one.

### Phase 1, item 2 done — and the handover happened

```
$ printf 'mov bl, 300\n' | ./asm1
line 1: rejected                      # asm0a: silence, exit 1

$ printf 'mov eax, 1\nmov eax, [rbx+1000]\n' | ./asm1
line 2: rejected
```

`asm1` 4 725 → **5 094 bytes**. It tracks the line number, prints it to stderr, and returns 1. The
reject suite grew `make test-reject-msg`: every rejection must name its line, because a refusal
nobody can locate is only half a refusal. (The text is still generic — "rejected" — and the next
increment is to say *what*, per check.)

How it is built, given no data section and no shifts: `div bl` repeatedly to extract decimal digits
into five slots, then print from the most significant with leading zeros suppressed. ~120
instructions, because the whole message is characters as immediates and the emit path is one byte per
syscall.

**And the handover arrived, a step earlier than planned and for an unplanned reason.** The message
code pushed `src/asm1.s` from 128 to 133 labels — over `asm0a`'s frozen limit of 128. So:

```
make bootstrap-check
  bootstrap: asm0a can no longer parse the dialect -- NOT APPLICABLE,
             seed/asm1 is the only builder
```

It was reached in two deliberate steps, which is worth recording because it is the only safe order:
first raise `asm1`'s own limit to 256 and move the label table to `rbp-3860`, promote *that* (it still
has 128 labels, so both builders can make it), and only then write source that needs 133. Doing it in
the other order leaves a source that nothing can build.

From here there is no independent implementation to cross-check against. The safety net is now
`ref/`, the reject suite, the capability pairs, the superiority suite, the seed chain and the pinned
decodes — which is why those had to exist first. `docs/provenance.tsv` still records `asm0a` for the
fixtures, because `asm0a` can still assemble those; it can no longer assemble the assembler.

### Phase 2, item 4 done: expressions

```
mov eax, 1 / end: / db end          ->  db 5     (label, resolved)
mov eax, 1 / end: / db end - 2      ->  db 3     (label arithmetic)
db fin / fin:                       ->  db 1     (FORWARD reference)
db nosuch                           ->  line 2: rejected
```

`asm1` 5 094 → **5 351 bytes**. `expr := term (('+'|'-') term)*`, where a term is a literal or a label,
spaces optional around the operator.

**The value model is the interesting part.** In pass 0, a forward label has no value yet — so a symbol
looks up as "unknown". That is *tolerated* in pass 0 (values there never affect a byte count) and
**refused** in passes 1 and 2, which is what keeps `db nosuch` an error rather than a silent zero.
That tolerance is also why the forward-reference case works at all: pass 1, the validate pass, has
every label and resolves it before a byte is written.

Capability pairs added: `expr-label`, `expr-arith`, `expr-fwd`, each against the hand-written constant
it must equal. 11 pairs now.

Four defects, and three of them are the same defect wearing different clothes:

1. **`term` returned the pass flag as the symbol's value.** `db end` emitted `02` — the pass number —
   instead of `05`. The lookup result was in `eax`, then clobbered by a `movzx eax, byte [rbp+16]`
   before it was copied to `ecx`.
2. **The accumulator slot was `[rbp+64]`, which is `emitmem`'s register field.** `lea` sets that field
   *before* calling `memop`, and `memop` calls `expr` — so `lea rsi,[rsp]` lost its register and
   `stack`/`count10` broke. Moved to `[rbp+12]` and `[rbp+4]`, verified free rather than assumed.
3. **A label named `term` already existed** as the startup's NUL-termination loop. Duplicate labels
   assemble and the *first* definition wins, so `call term` ran the startup loop and every expression
   failed. Renamed to `trm`. Same class as the duplicate `dbnext`/`d_x`/`ls1` found earlier: harmless
   to the assembler, fatal to the program.
4. **`end - 2` with spaces** was rejected because the expression did not skip spaces around the
   operator.

Every one was caught by a test rather than by reading: the fixtures for (2) and (3), the capability
pairs for (1) and (4).

### Phase 2, item 5: `entry` — attempted, reverted, and why

Not landed. `asm1` is at the last green commit (5 351 bytes, 18/18, fixpoint, all gates).

The intended change: an `entry <expr>` directive, so a source can put data *before* code and choose
its own entry point. It is on the critical path twice over — `asm0a`'s own layout puts data first, and
reconstructing `src/asm0a.s` (Stage 5) needs exactly that.

It requires the header emission to stop being "copy 96 bytes, then filesz, then 8 bytes" and become
four parameterised copies with the entry field spliced in at offset 24:

    0..23 from the template | 8 bytes of entry | 32..95 from the template
    | filesz + memsz | 112..119 from the template

That is the right shape, and I had it working piecewise. What defeated it was the *editing*, not the
design: three `sed` line-range replacements in a row landed one or two lines off, and the last one
deleted the `mov eax, 2` that switches `emital` from counting to writing. Every fixture then failed,
because the assembler was silently back in count mode — and the header it produced was wrong in a way
that only `cmp` against `ref/` shows.

Reverted rather than half-landed. The lesson is already in `AGENTS.md` and I ignored it: structural
edits to this file are done by *appending self-contained blocks and anchoring on content*, not by
line numbers. A rewrite of the header belongs in a session that starts with the whole budget.

Next session starts here: extract the header emission into `hcp` (a copy helper taking pointer and
count), then splice the entry field, and check `18/18` after **each** of those two steps rather than
after the third.

### Phase 2, item 5 landed (first half): the `entry` directive

```
db 1, 2, 3, 4          # data first
code:
mov eax, 60
mov edi, 42
syscall
entry code             # e_entry = 0x40007c

$ make test-superior
  superior: entry directive -> e_entry 0x40007c, data first, runs (exit 42)
```

`asm1` 5 351 → **5 515 bytes**. A source can now put data before code and choose where execution
starts, which `asm0a` cannot express at all — it hardcodes entry to the first byte. This is the
layout `asm0a` itself uses, so it is the first requirement for reconstructing `src/asm0a.s`
(Stage 5).

**Done in two steps with a check after each, as planned after the revert:**

1. the header emission became three parameterised copies — 24 bytes, then the entry field, then 64 —
   with `hcp` taking a pointer in `rbx` and a count in `eax`. 18/18 and fixpoint checked before
   touching the entry field.
2. the entry field replaced the middle copy, defaulting to the template's `0x400078` when no
   directive is present — so every existing fixture stays byte-identical.

**Two defects, both from the same habit:**

- The middle copy needed `[rbp+28]` to mean "no directive", but that slot still held the byte count
  from the read loop, so the first run of step 2 put `0x00005xxx` in `e_entry` and broke every
  fixture. Cleared at startup, where the value stops being needed.
- The `d_en` handler was inserted *between* `d_r`'s body and its `jmp.l pret`, so `ret` fell into the
  `entry` handler — `callret` broke, and asm1 could not build itself (`line 183: rejected`, which is
  `emit_w:`). A label insertion has to be anchored on the *end* of the previous handler, not on one
  of its lines.

`entry` is also the first item where the *superior* suite gained a second case, and both now assert
that the produced binary **runs** with the expected exit status rather than only matching bytes.

Still open in item 5: `.text` / `.data` sections with two program headers and a writable data
segment. `entry` was the piece of that which does not change the header *shape* — the rest does, and
the second segment is what will change every fixture's bytes unless it is opt-in.

### Phase 2, item 6 begun: `and`, `or`, `test` with immediates

```
and eax, 255   -> 81 e0 ff 00 00 00
or  ebp, 255   -> 81 cd ff 00 00 00
test edi, 7    -> f7 c7 07 00 00 00
```

`asm1` 5 515 → **5 651 bytes**. Three forms from one change: `cmp r32,imm32` was already emitting
`81 /7 id`, so the opcode and the `/digit` became parameters (`[rbp+44]`, `[rbp+48]`) and the same
handler now serves `cmp` (81/7), `and` (81/4), `or` (81/1) and `test` (F7/0). Capability pairs added
against hand-computed `db` dumps: 14 pairs.

**Four defects, and they are the same defect four times: a dispatch letter change that broke a
neighbour.**

1. `and` shares its first letter with `add`, so the dispatcher tests the *second* character — but I
   dropped the guard that checked the first, so **`inc` was parsed as `and`** (`inc` and `and` match
   at offset 1). `inc al`, `inc bl`, `inc bh` failed; `inc eax` worked, because that path tests the
   operand's first character. Four fixtures caught it.
2. `or` (3 characters) and `test` (5) went through `pc32`, which advanced the cursor by 4 — right for
   `cmp`/`add`/`and`, wrong for both new ones. The advance moved into each dispatcher.
3. The new `d_o`/`d_t` handlers were inserted *before* their own letter checks, so a non-matching
   letter advanced the cursor before falling through to the next test.
4. `pc32`'s parameters were set by each caller but the advance stayed inside the handler — the split
   that caused (2).

Every one was found by a test rather than by reading, and (1) was found by the *fixtures*, not by the
new capability pairs — which is the argument for keeping both.

Still missing and noticed while testing: `test eax, eax` (register form, `85 /r`) is not implemented;
it is rejected with a line number, which is the right failure, not a wrong answer.

### Phase 2, item 6 continued: the register forms — and an `asm0a` defect they exposed

```
and   eax, ecx -> 21 c8      or eax, ecx   -> 09 c8
test  eax, ecx -> 85 c8      cmp eax, ecx  -> 39 c8
test  edi, edi -> 85 ff
```

`asm1` 5 651 → **5 781 bytes**. The parameterised handler gained a register arm: after the destination
is parsed, `e`/`r` as the next character means a register source, emitted as `C0|(src<<3)|dst` with a
per-mnemonic opcode (`cmp` 39, `and` 21, `or` 09, `test` 85) held in `[rbp+52]`. `test edi, edi` — the
form flagged as missing at the end of the last entry — now works.

**Then the capability suite refused one of my own pairs, and it was right to.**

```
tests/capability/and-rr.cap.s: asm0a ACCEPTS the new syntax (it should not)
```

`and eax, ecx` is *accepted* by `asm0a`, which should have been impossible. Probed:

```
and eax, ecx     asm0a emits 01 c8     asm1 emits 21 c8
```

`01 /r` is **`add`**. `asm0a` parses `and` by its first letter and never checks the rest of the
mnemonic, so it silently assembles a *different instruction than the one written*. That is a
wrong-answer defect of exactly the class this project has been hunting in `asm1` — found in the
frozen bootstrap, by a test that was supposed to be confirming `asm1`'s new syntax.

It cannot be fixed: `asm0a` is frozen. It is now recorded as a **superiority** case instead — `asm1`
emits `21 c8`, `asm0a` emits `01 c8`, and the test fails if they ever agree:

```
superior: and eax,ecx -> 21 c8 where asm0a emits 01 c8 (it reads "and" as "add")
```

The lesson is worth stating plainly: **an independent implementation is not a correct one.** The
cross-check between `asm0a` and `asm1` was valuable because they were *different*, not because
`asm0a` was right — and this is the first case where they disagree and `asm1` is the correct side.

### Phase 2, item 6 continued: shifts

```
shl eax, 1   -> c1 e0 01      shr eax, 1  -> c1 e8 01
sar eax, 31  -> c1 f8 1f      shr edi, 8  -> c1 ef 08
```

`asm1` 5 781 → **5 945 bytes**. `shl`/`shr`/`sar` are one handler: `C1 /digit ib` with the digit in
`[rbp+44]` (4, 5, 7). The `s` dispatcher already split syscall from `sub`; it now splits three ways on
the second character — `y` for syscall, `h` for `shl`/`shr`, `a` for `sar` — and `shl`-vs-`shr` on the
third. Capability pairs: 20.

**Three defects, all mine, all the same shape as last time: an insertion that cut a neighbouring
path.**

1. The `d_sh`/`d_sa` handlers were inserted *before* `jmp.l prr`, so the `sub` path lost its jump and
   fell into the shift handler. The build failed outright — which is the good case.
2. The `psh` tail was written with two `call emital`s where the second needed its operand loaded
   first, so every shift emitted the *modrm twice* and never the count: `shl eax,1` gave `c1 e0 02`,
   where `02` was not the count but whatever was left in `eax`.
3. My fix for (2) was a line-number `sed` insert that landed mid-block and duplicated lines — the
   same mistake recorded in `AGENTS.md` twice already. The block was then rewritten by content anchor
   (label to next label), which is the method that works.

Item 6 still open: `push`/`pop`, `imul`, `r8`–`r15` with REX, and indexed addressing
`[base+index*scale]`. The last two need the register and memory-operand machinery extended rather
than just another handler.

### Phase 2, item 6 continued: `push`/`pop` and `imul`

```
push rax -> 50     pop rax  -> 58     imul eax, ecx -> 0f af c1
push rdi -> 57     pop rbp  -> 5d
```

`asm1` 5 945 → **6 132 bytes**. `push`/`pop` are `50+rd` / `58+rd`; `imul r32,r32` is `0F AF /r`
with the destination in `reg`. Capability pairs: 23.

**One defect, and it is the most instructive of the lot:** `push ` is five characters and `pop ` is
four, but both shared a handler that advanced the cursor by four. So `push rax` parsed `h ax`, failed
in `reg32`, and was *rejected* — while `pop` worked, which made it look like a push bug rather than a
shared-handler bug. The advance moved into each path, and the same split had already been made for
`pc32` two entries earlier.

Also found: `d_p` and `psh_push` each defined *twice* because I both generated the dispatch inline and
appended a file containing it. Duplicate labels assemble and the first definition wins, so the file
"worked" while carrying dead code — the third time this session. Removed.

Item 6 remaining: `r8`–`r15` with REX, and indexed addressing `[base+index*scale]`. Both need the
register and memory machinery extended rather than another handler, and both are worth a session that
starts with the whole budget.

### A stopped attempt, and the rule it re-taught

Tried to add `neg` / `not` (F7 /3, /2 — the same shape as `inc`/`dec r32`, so a small change). It ended
in a revert, and the way it ended matters more than the feature.

Sequence: the handler advanced the cursor by 4 *and* `pu32` advanced by 4 as well, so the operand
landed on `ax` and failed. Fixing that with a line-number delete took out a neighbouring label; the
build then failed, and **the failed build left the previous `asm1` in place — so the next test run
reported "ok" and "fixpoint holds" against a stale binary.** That is the worst failure mode in this
project: a green result about the wrong subject, which `AGENTS.md` names as the most common defect in
evidence.

Reverted to the last commit. `asm1` is 6 132 bytes, 18/18, fixpoint, all gates green.

The rule, now learned for the third time in this session: **structural edits to `src/asm1.s` are
whole-block replacements anchored on a label and the next label.** Line-number deletes and mid-block
inserts have produced: deleted live lines (twice), duplicated labels (three times), and handlers
inserted inside a neighbour's body (four times). None of those were caught by the compiler; all were
caught by tests, after the fact.

And the corollary, which cost the most here: **rebuild before testing, and check the build succeeded.**
`make` failing and `./asm1` still existing is a silent stale-binary trap. `make` should be a
prerequisite of every test target — it is, for `test-asm1` — but a direct `./asm1` invocation bypasses
it, and that is what happened.

Remaining in item 6, deliberately deferred to a session that starts with budget: `neg`/`not`,
`r8`–`r15` with REX, and indexed addressing.

### Item 6: `neg` and `not`, the second time

```
neg eax -> f7 d8     neg edi -> f7 df
not eax -> f7 d0     not ebp -> f7 d5
```

`asm1` 6 132 → **6 205 bytes**. Unary `F7 /3` and `F7 /2`, reusing `pu32` exactly as `inc`/`dec r32`
do — no cursor arithmetic in the handler at all, which was the first attempt's bug.

Done the way the rule says: the blocks were **appended whole** and the single dispatch retarget was
one anchored line. Then `make` was run *and its exit checked* before any test, because the previous
attempt's "green" results came from a stale binary left behind by a failed build.

One defect, and it is the same one as ever: the `not` branch compared the mnemonic's **third**
character against `o` — but `not` is `n,o,t`, so the third character is `t`. And the first attempt to
fix it hit the wrong line, which was visible only because the rebuilt binary's sha was *unchanged*.
Checking the sha as well as the exit status is what caught it.

### Item 6: indexed addressing `[base+index]`

```
mov eax, [rbx+rcx]     -> 8b 44 0b 00
mov eax, [rbx+rcx+8]   -> 8b 44 0b 08
mov eax, [rsp+rax]     -> 8b 44 04 00
```

`asm1` 6 205 → **6 561 bytes**. `memop` now recognises a register after `+` as an index (stored as
`code+1` in `[rbp+124]`, so 0 means "none"), and `emitmem` emits a SIB with `scale=0` when one is
present. Scale and `r8`–`r15` bases are still absent.

**This is the first change of the session that is machinery rather than a handler, and the method
mattered more than the code.** Two blocks were rewritten *whole* — `emitmem` and `memop`, each
anchored from its label to the next label — plus one appended dispatch. Nothing was edited by line
number. It worked on the second attempt, and the first attempt failed for a reason worth recording:
a *stray label* (`memnum`) landed before `memneg`, so every `+disp` operand fell into the minus test
and was rejected. A whole-block rewrite made that visible in one read; the positional edit that
created it did not.

Three encoding details that a hand-computed dump forces you to get right, and all three bit:

1. with a SIB, the modrm `rm` field must be **4**, not the base register — the base moves into the
   SIB byte;
2. for correctness the mod field must be **01** whenever an index is present, so a disp8 (possibly 0)
   is always emitted — legal, if one byte longer than necessary;
3. `[rbp+rdi]` is `8b 44 3d 00`: `reg=0, rm=4`, SIB `index=7, base=5`. My first expectation wrote
   `8b 7c 3d 00`, which would be `reg=7` — asm1 was right and the test was wrong.

Remaining in item 6: `r8`–`r15` (REX.B/R/X across every emit site — the last machinery change) and
scale factors `*2`/`*4`/`*8`.

### A third stopped attempt: message *reasons*

Tried to make the rejection message say *what* — `line 1: range` / `line 1: label` / `line 1:
rejected` — by setting a reason code in `chklim` and in the symbol lookup, and branching in `msg`.
It worked for two of three cases: `db nosuch` said `label`, `frobnicate` said `rejected`.

Then `mov bl, 300` **exited 0**. A range check that stops rejecting out-of-range immediates is not a
cosmetic failure, and it was introduced by inserting two lines into `chklim` at a computed offset —
the insertion landed inside the flag-dependent sequence, so the `sub`/`jb` pair no longer decided
anything.

Reverted. `asm1` is 6 561 bytes, 18/18, fixpoint, and `mov bl, 300` is refused with a line number
again.

The score for this session's positional edits: five attempts, five failures, every one caught by a
test within one command. The method that works is not in doubt — whole-block replacement anchored on
a label — and this attempt used it for `msg` (which worked) and then abandoned it for `chklim`
(which did not).

Deferred with the rest: message reasons, `r8`–`r15` with REX, and scale factors. The reason codes need
a slot that survives `putch` and `msg`, and every four-byte slot within `disp8` is already in use —
worth solving once, deliberately, rather than by borrowing `[rbp+92]` from the branch opcode.

### Phase 1 item 2, second half: messages that say *what*

```
mov bl, 300          -> line 1: range
mov eax, [rbx+1000]  -> line 1: range
db nosuch            -> line 1: label
jmp nosuch           -> line 1: label
frobnicate 1         -> line 2: rejected
```

`asm1` 6 561 → **6 765 bytes**. A reason byte at `[rbp+2]` — genuinely unused, and it survives
`putch`, which is what the previous attempt got wrong by borrowing `[rbp+92]` from the branch opcode.
`make test-msg-exact` asserts each message **verbatim**, so a vague one fails instead of passing.

**And it exposed a real bug in line numbering:** `db nosuch` reported `line 2: label` for a failure on
line 1. The counter kept advancing *across passes* — pass 0 consumed the newline tolerantly (an
unknown symbol is fine when counting) and pass 1 then started at 2. The counter is now reset before
each of the three passes, and `frobnicate` on line 3 reports line 3.

Three functions were rewritten whole (`chklim`, `trm`, `lfind`) rather than patched — the first
attempt's failure was an insertion inside `chklim`'s flag-dependent sequence, which turned a range
check into a no-op. Rewriting whole costs a diff to read and nothing else.

Still deferred: `r8`–`r15` with REX, scale factors `*2`/`*4`/`*8`, and `.data` sections with two
program headers.

## The next phase, measured rather than planned

Before choosing, the question was asked in a form that could be answered: **what would rebuilding
`asm0a` from source actually require?** A disassembly of `asm0a`'s own 3 745 bytes (made with
`objdump`, before invariant 10 forbade it — which is why the numbers below stay **provisional**)
gives the instruction mix it uses, and comparing that against what `asm1` accepts gives the gap:

```
mov 135   add 130   jmp 117   inc 107   cmp 101   je 67    call 37
movzbl 36 movb 29   jne 29    or 21     sub 17    cmpb 16  xor 14
test 12   jb 12     jae 12    ja 10     ret 9     shl 8    imul 8
lea 6     js 6      syscall 5 ...
```

| needed by a rebuilt `asm0a` | uses | `asm1` |
|---|---|---|
| `add r64, imm8` (`48 83 c3 04`) | 60 | **missing** |
| `add r64, r64` | many | **missing** (see below) |
| `cmp r8/r32, [mem]` (`cmpb`, `cmp (%rcx),%rax`) | 10 | **missing** |
| `imul r32, r32, imm8` (`6b /r ib`) | 8 | **missing** |
| `ja` / `jae` / `js` / `jg` / `jo` | ~30 | **missing** (only `jb`, `jz`, `jnz`, `jmp`) |
| `movzbl` (from memory) | 36 | have (`movzx`) |
| `movb [mem], imm8` | 29 | have (`mov byte`) |
| `shl`, `or`, `test`, `sub` | — | have |

### And one wrong answer found on the way

`add rbx, rcx` emitted **`01 cb`** — the *32-bit* encoding of a 64-bit instruction. The reg-reg ALU
handler never emitted REX.W, so `add`/`and`/`or`/`xor`/`test`/`mov` with 64-bit operands were silently
assembling as 32-bit. Exactly the class of defect found in `asm0a`'s `and`, in `asm1` itself, and
caught by asking what `asm0a` would need.

Fixed by **refusing** rather than guessing: a 64-bit operand in a form whose opcode carries no REX is
now rejected with a line number (`mov rax, rbx` → `line 1: rejected`), and `sub rsi, rcx` — whose
opcode *does* set REX.W — is unchanged. Emitting the REX byte is the right fix and belongs with
`r8`–`r15`, which needs the same machinery.

### So the order is

1. **REX.W for the reg-reg ALU forms** plus `r8`–`r15`. One mechanism: compute a REX byte from operand
   codes ≥ 8 and the 64-bit flag, emit it before the opcode, mask the codes with `and` (now available).
   This turns the refusals above into support and gives 16 registers. Gate: capability pairs against
   hand-computed dumps for `add rbx,rcx` → `48 01 c9`, `add r8, r9` → `4d 01 c8`, and so on.
2. **The forms `asm0a` itself needs** (table above): `add r64,imm8`, `cmp` against memory,
   `imul r32,r32,imm8`, and the missing condition codes. Each is a handler; each gets a capability
   pair or a hand-computed dump.
3. **`src/asm0a.s`** — Stage 5. With 1 and 2 done, the frozen 3 745 bytes become *derivable*:
   `asm1 < src/asm0a.s | cmp - asm0a`. That is the strongest statement the project can make, and it is
   finally reachable rather than aspirational.
4. **`.data` sections**, then **scale factors**, then the self-testing generator (Stage 6).

The order changed because of the measurement: **Stage 5 is no longer the far end.** It is two
mechanisms away, and those two mechanisms are the ones `asm0a`'s own instruction mix says are needed.

## Correction: the decoder must be ours

The instruction-mix table above was produced with `objdump`, and the branch gate has been using it
since wave 1b. Both are violations of the project's own rule, recorded in `AGENTS.md`: a disassembler
is the tool this project replaces, so it cannot be the thing that verifies it.

**So the next phase is not `r8`–`r15`. It is `src/dis.s` — a decoder written in the dialect and
assembled by `asm1`** — and it comes first because it is what makes every later measurement and every
gate *ours*.

### Scope: exactly what the gate consumes

```
in : a binary and a byte offset
out: mnemonic and target for EB, E9, E8, 70-7F, 0F 80-0F 8F
     jmp · je · jne · jz · jnz · jb · ja · jae · js · jg · jo · call
     target = site + length + disp
```

Nothing else is needed: not a general x86 decoder, not a printer for operands, not a symbol table.
Hex output is now expressible (`shr` and `and` exist, which they did not when the gate was written).

### Why this is the right next step even though it is not the biggest feature

1. It **removes a system dependency from a gate**, which is a correctness question, not a comfort one.
2. It makes the branch pins evidence about *our* encoder checked by *our* decoder — weaker in one
   sense (a shared bug could hide) and stronger in the only sense that matters here: nothing outside
   the project is trusted.
3. It re-derives the `asm0a` instruction mix with our own tool, replacing the provisional numbers
   above with measured ones.
4. It is real work for the dialect: a byte-at-a-time decoder with a jump table expressed as compares,
   hex printing, and argument handling — the first `asm1`-built program that reads a file, rather
   than stdin.

### Consequences to plan for

- `asm1` writes to stdout and reads stdin; a decoder needs a *file* argument. Either the gate passes
  the binary on stdin (`dis < bin`) or `asm1` learns `argv` — the second is worth doing anyway, since
  `[rsp]` at entry is `argc`.
- A shared-bug risk appears the moment our decoder audits our encoder. The mitigation is the existing
  one: hand-emitted `ref/` binaries whose bytes were written before either existed, plus capability
  pairs that pin encodings against hand-computed dumps.

## `src/dis.s` landed: the gate is ours, and 290/290 pins agree

```
make check
```

ends with `branch pins: 290/290 decoded by src/dis.s -- asm0a sha 6271c5ee79034ffd, dis sha
8c9bd9b356874875`.

`src/dis.s` is 1 348 bytes, built by `asm1` from 467 lines of the dialect, and it is the first program
in this repo that takes an *argument*: `./dis <site> < binary`. It reports `0xSITE 0xTARGET mnemonic`
for `EB`, `E9`, `E8`, `70`–`7F` and `0F 80`–`0F 8F`, and refuses everything else — three refusals, in
fact: a site outside the input, bytes that are not one of those forms, and an instruction that would
run past the end of the input or a target that is not a byte in it. That last one is the truncation
rule doing double duty: it cannot print a negative target because a target below zero wraps to a huge
unsigned value and is refused.

**What the dialect needed that it did not have**, and how each was paid for:

| need | how |
|---|---|
| `argv` | `pop rcx` / `pop rax` / `pop rbx` at entry — the stack *is* `argc`, `argv[0]`, `argv[1]`, so no pointer arithmetic on a 64-bit pointer, which `mov r32,[mem]` would truncate |
| a `jmp` table | 18 slots of 5 bytes, `len` then up to four letters, indexed by `cc*5` (`*4 + *1`); `putmn` prints it |
| hex output | 8 nibbles shifted out with `shr eax,28` / `shl edx,4`, leading zeros suppressed, `0` for zero |
| sign-extending `rel8` | `test edx,128` then `or edx,0xffffff00`; the sum is done in 32 bits so a wrapped target is caught by the range check |
| a 40 000-byte input buffer | `rbp-40000`, filled 120 bytes at a time — the same chunked read `asm1` uses, for the reason recorded above |
| a refusal with a message | six reason words (`offset`, `input`, `site`, `form`, `trunc`, `target`) in 8-byte slots, printed with the same `putmn`, to the fd in `[rbp+80]` (1 for output, 2 for complaints) |

**Four defects, all found by tests, all worth recording:**
1. **The hex accumulator was never initialised.** `mov eax,0` zeroed the digit counter and not the
   accumulator, so the site became `garbage*16^n + value` from whatever the env area held (`8` in that
   run). It showed up as sites `0x190`.. decoding `0x1`a` — a *wrong site*, silently, which is the
   worst kind of defect here. Every two-digit offset happened to come out right, which is why the first
   probes looked fine.
2. **The nibble test was `cmp eax,9; jb`**, so the digit `9` fell into the letter branch and printed
   `` ` `` instead of `9` (87+9). It corrupted 93 of 290 pins at once — the gate as a whole was
   visibly broken, which is the good failure.
3. **A negative `rel8` fell through into the `rel32` load**: `d_re8`'s sign-extended value was
   overwritten by the 4-byte load in `d_re32`, because `d_re8` had no `jmp` over it. Only two of the
   290 pins are backward `rel8` branches, and both were refused — 288/290 is exactly the kind of
   near-miss that a "does it run" test would have called green.
4. **Two labels were longer than 7 characters** (`chkbnd_ok`, `msg_fail`), which the assembler refused
   with `line 244: rejected` — the dialect's own limit, caught at build time, which is the right place.

And one defect in the **test**, which is the most instructive of the lot. The refusal message started as a
single `not a branch`, which was a lie for five of the six reasons (a 100 000-byte input is not "not a
branch"). It became six reason words, pinned verbatim by `make test-dis`, and the first pinned
expectation I wrote was wrong:

    0f050000 0 refuse:form      ->  REFUSAL: [0f050000] -> 'dis: trunc' (exit 1), want 'refuse:form'

`0f050000` is four bytes and the `0F 8x` form needs six, so the bounds rule fires before the opcode rule:
`trunc`, not `form`. The decoder was right and the expectation was wrong — which is the whole argument
for pinning the reason rather than accepting "it refused". The order of the checks is part of the
contract, so both cases are now in the file, the 4-byte one as `trunc` and an 8-byte one as `form`.

**The gate itself was then made to fail on purpose**, twice, because a gate that cannot fail is a
format check wearing a gate's clothes. First the pin, with `0x373` recorded as `0x374`:

```
./tools/check-branches.sh
```

prints `pin 0x142: got '0x142 0x373 jmp', recorded '0x142 0x374 jmp'` and `branch pins: 289/290
agree, 1 DISAGREE`, and exits 1. Then the subject: the same site, in a copy of `asm0a` whose opcode
byte `0x73` (`jae`) is changed to `0x77` (`ja`).

```
cp asm0a .work/asm0a.bad && printf '\167' | dd of=.work/asm0a.bad bs=1 seek=436 conv=notrunc 2>/dev/null && ./dis 0x1b4 < .work/asm0a.bad
```

prints `0x1b4 0x139 ja`, where the same site in the real `asm0a` prints `0x1b4 0x2b3 jae`. That
second one is the one that matters: it proves the decoder is reading the subject, not repeating the
table.

### What is still provisional

The instruction-mix table above was produced with `objdump` and is **still provisional**, but for a
narrower reason: `dis.s` decodes branch forms only. It now confirms that every one of the 290 recorded
branch sites is real (mnemonic, target, and byte-for-byte the recorded line), and it says nothing about
`mov` (135), `add` (130), `inc` (107) or `cmp` (101). Re-deriving the whole mix needs a decoder for
every form `asm0a` uses — a general disassembler, deliberately not built, because nothing in the gate
consumes it.

### Next, unchanged by this

1. **REX.W for reg-reg ALU + `r8`–`r15`** — one mechanism, and it turns today's refusals into support.
2. **The forms `asm0a` needs** to be rebuilt: `add r64,imm8`, `cmp r8/[mem]`, `imul r32,r32,imm8`, and
   the missing condition codes `ja/jae/js/jg/jo`.
3. **`src/asm0a.s`** — then `asm1 < src/asm0a.s | cmp - asm0a`.
4. `.data` sections, scale factors, the self-testing generator.

## The coverage gate: what the corpus actually reaches

`make test-coverage` now exists, and its first run was not green. `tests/coverage/forms.tsv` claims 60
forms; each probe must assemble **and** its normalised shape (`tools/shape.awk`) must appear in some
test input. Shapes are what the encoder branches on — register class, and for a memory operand its
base (rbp and rsp encode differently from everything else), whether a SIB is present, and whether a
displacement is present, negative, or absent.

```
make test-coverage
  coverage 60/60 forms exercised by a test, every corpus mnemonic claimed
```

The first run found three things, which is the argument for having it:

```
UNTESTED: 'mov eax, [rbx-8]'  (mov r32 mem:other:noindex:negdisp) appears in no test input
UNTESTED: 'lea eax, [rbx]'    (lea r32 mem:other:noindex:nodisp)  appears in no test input
UNCLAIMED: 'jb.l' / 'jnz.l'   used by the corpus, absent from the inventory
```

The other direction is checked too: a mnemonic a *test* uses must be claimed, so adding a case cannot
widen what is supported without recording the claim. That is how `jb.l` and `jnz.l` were caught — the
inventory was incomplete, not the corpus. `tests/reject` is excluded from that direction on purpose:
`frobnicate` appears in a test in order to be refused, and demanding a claim for it would be demanding
a lie.

What it cannot do, stated in the script: prove the inventory complete. Shape is coarser than the code
in places (two displacement values share one path) and finer in others, so it is a lower bound on
coverage and an upper bound on the claim. It is made to fail in the gate itself (a probe with a shape
no test reaches) and by removing a case: delete `tests/superior/negdisp.s` and the gate says
`UNTESTED: 'mov eax, [rbx-8]'`.

## The wrong answer it exposed: `[rbp]` with displacement 0

No test input in this repository had ever written `[rbp]` with a zero displacement, so nothing could
see that it encoded as `8b 05` — RIP-relative, with the next four bytes of the program read as the
displacement. The fix is in `docs/encodings.md` with the before/after table; in short, `emitmem` now
chooses `mod = 01` when the displacement is non-zero, a SIB is present, **or the base is `rbp`**, and
emits the disp byte under the same condition.

```
tests/superior/rbp0.s   mov eax, [rbp]   hand-computed 8b4500
  superior: tests/superior/rbp0 -> 8b4500, and asm0a does not
```

`asm0a` still gets it wrong and always will; the case fails if the two ever agree, which is the same
shape of test as the `and`-as-`add` case.

This wave also deleted the dead code that made the fix dangerous to attempt: `emitmem` had a second,
shadowed copy of its tail (`emm1`…`em_done`, 7 duplicate labels) plus an unreachable `emmod1`. 52
lines and 10 label definitions went, `asm1` 6820 → 6644, and the fix added 35 back (6679). The
deletion was checked the way the rule says: 18/18 fixtures and the fixpoint *after* the deletion and
before the fix.

Still duplicated, and recorded rather than fixed: `chkok`, `trm`'s `termok`/`termnum`, and the
unreachable `lblchk` block with its own `ls1`. They need a pass-1 duplicate-label check in `asm1` to
force them out, which is a deliberate change of its own.

## The goal has changed the order: a high-level language

The destination is no longer "be better than `asm0a`" for its own sake. It is a **compiler**: a
high-level language whose backend emits this dialect. That reprioritises everything, because a
compiler's output needs things a bootstrap's does not, and three of them are hard blockers:

| a compiler needs | today |
|---|---|
| **writable memory** — globals, string constants, a frame the program owns | **absent**: one `R+X` `PT_LOAD`, no `.data`, so every byte of the image is code |
| **64-bit integer arithmetic** — pointers, sizes, addresses | `add rax, rbx` is *refused*; `sub eax, ecx` silently assembles 64-bit |
| **more than 8 registers** | 8 |
| **`[base+index*scale]`** — arrays, fields, `a[i]` | index without scale |
| **displacements past 127** — frames and records over ~120 bytes | disp8 only |
| signed comparisons `ja/jae/js/jg/jo` | absent (`jb`, `jz`, `jnz`, `jmp` only) |
| `imul r32, r32, imm8` | absent |
| a calling convention, and something that can check it | `call`/`ret`/`push`/`pop`; no ABI, no frame layout |

Every row but the last is one mechanism or one handler. In this order, each testable on its own:

1. **REX.W and `r8`–`r15`** — one mechanism: a REX byte computed from operand codes ≥ 8 and the
   64-bit flag, emitted before the opcode, codes masked with `and`. It turns `add rax,rbx` from a
   refusal into `48 01 c9`, gives 16 registers, and **fixes `sub eax, ecx`** in the same stroke
   (the width comes from the operand names instead of from the opcode).
2. **`.data`** — a second `PT_LOAD`, `R+W`, opt-in so no existing fixture changes. Without it a
   compiled program cannot have a mutable global or a string it can build at runtime.
3. **disp32 and `[base+index*scale]`** — one memory-operand change; both are needed for `a[i]` and
   for frames larger than 127 bytes.
4. **The compiler staples**: signed condition codes (`ja/jae/js/jg/jo`), `imul r32,r32,imm8`,
   `cmp r,[mem]`, `test r,[mem]`. Each is a handler plus a hand-computed dump.
5. **A calling convention**, written down and checked by a fixture that does a call with arguments
   and a return value. An ABI nobody tests is a convention in a comment.

Not on that path, and still the strongest statement this project can make: **`src/asm0a.s`**, so that
`asm1 < src/asm0a.s | cmp - asm0a` explains the frozen 3745 bytes. It is archaeology, not capability —
it belongs after the compiler has something to run, or in a session of its own.

## REX.W landed: the width comes from the operand names, not the opcode

```
add rax, rbx   -> 48 01 d8        (was: line 1: rejected)
mov rax, rbx   -> 48 89 d8        (was: 89 d8, i.e. mov eax, ebx)
and rax, rbx   -> 48 21 d8        (was: 21 d8)
cmp rax, rbx   -> 48 39 d8        (was: 39 d8)
sub eax, ecx   -> 29 c8           (was: 48 29 c8, i.e. sub rax, rcx)
add eax, rbx   -> line 1: rejected
push eax       -> line 1: rejected
```

`asm1` 6 679 → **6 947**, and this is the first item on the compiler's list: a compiler does pointer
arithmetic in 64 bits, and until now four of the six reg-reg families silently emitted the 32-bit
encoding for 64-bit operands while two refused them. The one that mattered most was `and`/`or`/`test`/
`cmp`, which share a handler that had no width check at all — the same class of defect as `asm0a`'s
`and`-as-`add`, in this assembler, found by writing the rule down.

**One concept:** `reg32` records the width of the register it parsed in a byte slot; a handler with
two register operands compares the widths and **refuses a mix**; any handler emits `0x48` iff that
width is 64-bit, before the opcode. `push`/`pop` refuse 32-bit names outright, because `50` pushes
eight bytes whatever the source says.

**And the direction of the evidence was reversed for once:** `asm0a` emitted the *correct* `29 c8` for
`sub eax, ecx` while `asm1` emitted `48 29 c8`. The frozen bootstrap had the better answer. That is
worth stating plainly, because the project's habit is to assume the newer stage is the better one:
`docs/encodings.md` says it, and it was found by writing down what width *means*, not by testing
`sub`.

Held by `tests/superior/width64.s` — 15 lines, one hand-computed expectation each, `.hex` carrying
its own arithmetic as comments — and by `tests/reject/width-mix.s`, which requires both assemblers to
refuse a mixed-width pair with no output. `make test-coverage` grew 17 rows for the 64-bit shapes,
which is exactly the direction that gate was built to force: a form with no test is a red gate.

### What is left of this item

`r8`–`r15`. The width machinery is in place; the extended codes need `REX.R`/`REX.X`/`REX.B` and a
3-bit mask on every code before it is shifted into a ModRM or SIB byte — one pass over the same
handlers, and `r13` needs the `mod = 00` exception that `rbp` already has. Until then `mov r8, rax`
is a rejection, not a wrong answer, and the compiler work that needs 16 registers waits.

## `r8`–`r15` landed: sixteen registers, and the width machinery paid for itself

```
mov r8, rax -> 49 89 c0     add r8, r9 -> 4d 01 c8     mov r9, [r8] -> 4d 8b 08
mov [r13], rax -> 49 89 45 00                            lea r10, [r8+r9] -> 4f 8d 54 08 00
mov r10d, 1 -> 41 ba 01 00 00 00                         mov r8d, [r9] -> 45 8b 01
```

`asm1` 6 947 → **7 488**. One helper computes `0x40|W<<3|R<<2|X<<1|B` from three slots that each
handler fills, and every code is masked to three bits before it enters a ModRM or SIB byte. The width
slot that REX.W introduced last wave is exactly what the extended registers needed — no second
mechanism.

`r13` and `r12` needed no new code: the `mod = 00` exception and the SIB-forced-rm rule are written
as `base & 7 == 5` and `base & 7 == 4`, which `rbp`/`r13` and `rsp`/`r12` share. That is what
writing those rules as masks bought.

**Ordering mattered.** The machinery went in first and provably *inert*: after every step in that
pass, `asm1 < src/dis.s` was byte-identical to the previous build, which meant no 8-register encoding
had moved. Only then did the parser open, and the corpus stayed 18/18 throughout. Doing it the other
way round would have made a build failure ambiguous between "the parser" and "the sixteen emit
sites".

Three traps, all in `docs/encodings.md`:

1. **Dispatch by fixed offset.** `mov r8, 1` puts the comma where `mov al, 1` has it, and `add r8, r9`
   puts it where `add eax, …` has its last letter. Both handlers now detect `r`+digit first.
2. **`push`/`pop` must not set REX.W.** `48 50` is legal and wrong, and nothing in the fixture corpus
   uses push/pop; the capability pairs compare spellings, so both sides moved together and stayed
   green. Found because `dis`, which does use `pop`, came out 3 bytes longer.
3. **`B8+rd` has no ModRM reg field**, so `mov r10d, 1` takes `REX.B` only. The first version also
   set `REX.R` (`45 ba` vs canonical `41 ba`): harmless on the machine, wrong as an encoding, and
   caught only by the hand-computed `.hex`. The coverage census cannot see it — `r8` and `rax` are
   the same shape.

`tests/superior/regs64` pins 15 lines against hand-computed bytes, and the superiority suite gained a
*behavioural* case: a program that adds in `r8d`/`r9d` and exits 42, which `asm0a` cannot assemble at
all. Bytes and behaviour fail differently, so both are there.

### The reject suite's premise moved, and it said so

`tests/reject/bad-register.s` was `mov r9, 1` — refused because `r9` did not exist. It exists now, so
the case assembled, and `make test-reject` failed. Replaced with `mov r7, 1` and `mov r16, 1`, which
are still not registers. A case that passes for a reason nobody intended is a hole: replace the
input, never delete the case.

### What the compiler still needs

| | |
|---|---|
| **writable memory** — the hard blocker | one `R+X` `PT_LOAD`; no `.data`, so every byte is code |
| `[base+index*scale]` | index without scale |
| disp32 | disp8 only |
| signed comparisons `ja/jae/js/jg/jo` | absent |
| `imul r,r,imm8` | absent |
| a calling convention, tested | absent |

`.data` is next because it is the one that makes a *program* possible rather than more instructions:
a global, a string built at runtime, a heap. It needs a second `PT_LOAD` with `R+W`, an opt-in
directive so the 18 fixtures stay byte-identical, and a way for `db`/labels to know which segment
they belong to.

## The compiler exists: `helloworld.c` compiles and runs

```
./cc < helloworld.c > hello.s
./asm1 < hello.s > hello
./hello            -> Hello, World!
```

`docs/cc.md` is the plan and the gate list. The design decision that matters: **`cc` emits dialect
source, not machine code** — 1 958 bytes built by `asm1` from `src/cc.s`, whose output is a reviewable
text file compared byte-for-byte against a hand-written golden. `asm1` stays the only thing that
produces bytes, so every gate the assembler already has applies to what the compiler writes.

This is the wave where the assembler's gaps stopped being a list and became blockers hit in the
first 600 lines of a compiler: `cmp r32,[mem]`, `add r32,imm32`, `ja`/`jae`, rel8's 127 bytes, no
disp32, label names ≤ 7 characters, and a `db` line that ends at the first string. And writing the
*golden* found an assembler defect before the compiler existed — `msg1end-msg1` was rejected because
the lexer did not stop a symbol at `+` or `-`.

The next two items are unchanged and now have a user: `.data`, then disp32. After those, the C subset
grows by the thing it is missing most: a calling convention, with a fixture whose output is wrong if
the register assignment is wrong.

## Stage 1 of the compiler: variables, a loop, and the oracle that found two bugs

`cc` 2 030 → 2 917 bytes. Subset: `int x = N;`, `x = x ± N;`, `while (x) { … }`, plus what stage 0
had. Emitted code is a prologue, one local at `[rbp-8]`, `mov ecx, N` + `add eax, ecx` (no
`add r32,imm32`), and `.l` loop branches (rel8 is 127 bytes and a body exceeds it).

The sixth gate is a new *kind* of oracle for this project: the compiled loop's output is compared
against the output of `tests/oracle/dots.s` — the same program written by hand in the dialect. Two
sources, one behaviour, neither derived from the other. It is the only gate that catches
plausible-but-wrong codegen, and it caught two real defects on first use:

- **`mov r64, imm` was one byte short.** `B8+rd` with `REX.W` takes an eight-byte immediate, so
  `mov rax, 1` as `48 b8 01000000` swallowed the next four bytes of the program. Now `C7 /0 id`.
  My own hand-computed expectation in `tests/superior/width64.hex` contained the same error and the
  byte gate passed; the oracle program segfaulted and the CPU disagreed. **A shared misunderstanding
  is invisible to the encoder and to its expectation, and obvious to the machine.**
- **`jbe` assembled as `jb`** — and `jnb`/`jno`/`jns` as `jnz` — because the branch dispatcher
  decided on two characters. That is `asm0a`'s `and`-as-`add` defect reproduced in `asm1`. Mnemonics
  are matched in full now, followed by a delimiter; five more mnemonics are pinned rejections.

The coverage gate and the build caught each other here: the census noticed the mnemonic `jbe` in
`src/cc.s` and demanded a claim, and the build then refused it.

Next for the compiler: expressions (`x = x + 1 + 1`), then `if`, then a second variable. Next for the
assembler, unchanged and still without a pressing user: `.data`, then disp32.

## disp32 landed: the 127-byte wall is gone

```
mov eax, [rbx+1000]  -> 8b 83 e8 03 00 00      mod 10 when disp8 does not fit
mov eax, [rbx+127]   -> 8b 43 7f               mod 01 when it does
lea rax, [rsp+1000]  -> 48 8d 84 24 e8 03 00 00    SIB then disp32
mov rax, [r13+1000]  -> 49 8b 85 e8 03 00 00   r13 & 7 = 5, the RIP trap
```

`asm1` 7 623 → 7 669. The displacement is classified once (none / disp8 / disp32) and `memop` no
longer range-checks it, because every 32-bit value is encodable. Three `tests/reject` cases stopped
rejecting — the suite correctly announcing that the language grew — and became
`tests/superior/disp32`, hand-computed.

**`cc` got smaller.** Its buffer bases were three instructions each, with a comment saying disp32 did
not exist; they are one `lea` each now.

This is what the compiler's next milestone needed: a frame or an array over 127 bytes. `.data` is
still the item after it, and its user is a mutable global or a heap — neither of which the subset has
yet.

### One thing learned that is not about disp32

`emitmem` needs a byte of state. `[rbp+3]` looks free (it is inside the argc slot, which nothing
reads) and **does not work**: with the classifier there, `src/cc.s` fails at a short `jz` with
`line 629: rejected` — a rel8 range error, the signature of the validation pass disagreeing with the
count pass. Moving the byte to `[rbp-80]` gives output byte-identical to the previous assembler.

Measured across candidate slots: `[rbp+0]` and `[rbp-80]` work; `[rbp+1]`, `[rbp+3]` fail;
`[rbp+5..7]` assemble and emit the **wrong bytes**. The last three are inside the 4-byte expression
scratch at `[rbp+4]`, so they are explained. The first two have no writer anywhere in
`src/asm1.s` and are recorded as an open question, with the rule in `docs/encodings.md`: state goes in
`[rbp+2]`, `[rbp+8..11]` or the negative slots, never `[rbp+0..7]`.

## No linker, and now a reason that is checkable

The question came up: does the compiler need a linker? `docs/cc.md` has the analysis; the short
version is that `asm1` already does symbol resolution, relocation and the ELF, because every address
is baked in as an immediate against a fixed base — and a real linker would force the assembler to stop
resolving addresses, which is the property that makes the dialect easy to target.

Two translation units are combined with `cat a.s b.s | asm1`, which *is* the absence of a link step.
That was unsafe until this wave: duplicate labels assembled silently and the first won. `asm1` now
refuses them (`line N: duplicate`), so a `cat` of two files that both define `main` fails instead of
picking one.

The check could not be added first: `src/asm1.s` carried seven dead duplicate labels of its own, so
the debt recorded in `docs/continue-here.md` had to be paid — the unreachable `lblchk` block, a second
`chkok: ret`, and `trm`'s `termok`/`termnum`. `asm1` 7 669 → 7 598 (deletions) → 7 731 (check and the
fourth reason word). The fixpoint then failed at `line 1882: duplicate` on my own source, which is the
new check working on itself within minutes.

## Compiler stage 2: comparisons, `if`, `else`

`x < N`, `>`, `<=`, `>=`, `==`, `!=` and `if (cond) { … } else { … }`, with **no assembler change**:
`jb`, `jz` and `jnz` cover all six relations on unsigned values, which is exact for the 0..255 the
subset allows. `>` swaps the operands; `<=`/`>=` shift the bound (`N+1`, `N-1`) and refuse when the
shifted bound leaves 0..255. `cc` 2 902 → 3 862 bytes.

Gate 7 compares the compiled `branch.c`'s output with a hand-written dialect program doing the same
thing — the second construct validated by a *second implementation* rather than by bytes alone. Both
gates were broken on purpose and both failed as intended.

Three defects, all caught by gates: a fragment name that had been renamed, two meanings in one frame
slot (the emitted jump read `jb L1 ` with a space), and **nested blocks sharing one id counter** — an
`if` inside a `while` emitted `L2e` twice, which the duplicate-label check added the previous session
caught as `line 36: duplicate`. That check was added to make `cat` a safe link step; it earned its
place by catching a code-generator bug in a generated file at assembly time.

Next for the compiler: a second variable (a symbol table), then expressions with precedence, then
`imul`/`div` in expressions. `.data` waits for a mutable global; functions wait for a calling
convention, which is the largest remaining design decision.

## Compiler stage 3: a symbol table

Eight variables with names, slots at `[rbp-8*(i+1)]`, and `a = b + 3` works because both sides are
looked up independently. `cc` 3 862 → 4 386 bytes. Gate 8 compares `twovars.c`'s output with a
hand-written dialect program with two counters.

Six defects, all mine, all caught by gates: uninitialised state (the third time in this project),
`varoff` shifting the wrong register, the declaration emitting an index instead of an offset, a
missing `want(";")` that then clobbered the value, a missing load in the assignment, and the loop
label emitted *after* the condition's load so `while (x < 3)` never re-read `x`.

And one hole in my own tooling worth recording: an `awk` that matched the first `call gcur` in
`cc.s` inserted a jump into the **main flow** and deleted `call flush`, so `cc` emitted zero bytes
while exiting 0 — "succeeding" on every input. The goldens caught it in one command. Anchor edits on
content, never on the first match of a short pattern; four of the six defects above came from edits
applied by pattern.

Next: expressions with precedence (`x = 1 + 2 * 3`), then functions and a calling convention — which
will also force the frame question (locals sit at `[rbp-8k]` with no `sub rsp` today, which is only
safe because nothing calls anything).

## Compiler stage 4: expressions with precedence

`expr := mulk (('+'|'-') mulk)*`, `mulk := term ('*' term)*`, over numbers and variables, used in
initialisers, assignments and `return`. One register per nesting depth (eax, ecx, edx, esi, edi, r8d),
so no stack traffic in the generated code and `x + 1` still emits the three lines it always did.
`cc` 4 386 → 4 877 bytes.

`/` is refused, and it is an *assembler* gap: the dialect has `div r8` only, never `div r32`. That is
a two-line handler away (`F7 /6` with the 32-bit form) whenever division is wanted.

`return` became uniform (`mov edi, eax; mov eax, 60; syscall`), which changed all five goldens. They
were regenerated and then *run*, and one was read line by line — a golden regenerated without being
read pins whatever the compiler happens to do.

Gate 10 is behavioural: `return a + b * 4` with a=2, b=3 must exit 14, and left-to-right evaluation
would exit 20. A precedence bug is a wrong number, not a diff.

Next: a calling convention. That is the largest remaining decision, and it also retires the frame
shortcut (locals at `[rbp-8k]` with no `sub rsp`, safe today only because nothing calls anything).

## Compiler stage 5: a calling convention

Arguments in rdi/rsi/rdx/rcx, return in eax, the callee copies its arguments into locals at entry
(syscall destroys rcx, so an ABI that trusted rcx would corrupt the fourth argument), a 64-byte frame
that is exactly the symbol table's capacity, nothing callee-saved because nothing is live across a
call, and `entry main` so the entry point does not depend on function order.

Gate 11 is behavioural: `add(2,3)` exits 5, `sub2(3,2)` exits 1, and swapping the argument registers
gives 5 and 255. Verified by corrupting the golden.

Open, and first in the queue: **a call with a variable argument fails** inside the recursive
expression parse. `f(3)` works; `f(x)` is refused. Recursion, and any real program, needs it.

`cc` 4 877 → 5 734 bytes. Coverage of the assembler is unchanged: the emitted code uses only forms
that already had fixtures, which is the payoff of emitting text.

### Fixed: the variable-argument defect

`f(x)` worked as `f(3)` did not, and the cause was `callargs` calling the *whole* `expr` parser
recursively while already inside an expression: the nested `ex1`/`ex2` frames shared the stack the
enclosing parse was using, and the symbol name buffer did not survive it. Found by probing state —
the name buffer held `1` where it should have held `x` — not by reading.

The fix is a smaller design rather than a workaround: **an argument is one term**, so `callargs`
calls `ex3`. Gated: `f(x)` with `x = 41` exits 42.

Next, in order: allow an expression as an argument (blocked then by a nesting bug that turned out to
be a missing stack reservation — see `docs/cc.md`), then recursion (`f(n - 1)`), then `if` inside a
function with a local that survives the call. All three landed.

## Compiler stage 6: recursion

`return` anywhere a statement is, and therefore a recursive function: `f(n, acc)` counting ten frames
exits 10, gated. Arguments were a small dedicated parser then (`argexpr`) because nesting the general
one corrupted the symbol-name buffer — a bug whose mechanism stayed unknown for three waves. It was
that `cc` never reserved stack (`docs/cc.md`), and both the workaround and the guard that replaced it
are deleted: an argument is a whole expression now, so `f(x * 2)` works and exits 42, gated.

What that leaves blocked: **a call inside a larger expression** (`n * f(n - 1)`), which needs the
result moved out of `rax` after the call. Pointers and arrays have since landed.

## Compiler stage 7: 64-bit values and addresses

The value model moved from `eax` to `rax` in one step that changed no behaviour — same exit codes,
same output bytes, every gate green — and then `&x`, `*p` and `*p = v` landed on top, with no type
system. Two exact gates: 40 (`*p = 33` after `int y = *p`) and 42 (a callee writing through the
caller's pointer). Three refusals added, 23 now.

Next, and the reason this mattered: **`int a[N]` with a computed index.** A symbol table is parallel
arrays, and `a[i]` is `lea rax, [rbp-B]` + the index + three `add rax, rax` for the stride + `add rax,
rcx` + `mov rax, [rax]` — all forms the dialect already has. So it is parser and layout work, not
codegen.

After that: `div` (both the 8-bit dialect form's limitations and `/` in `cc`), `char` and byte
strings, then `.data` for mutable globals — the point at which `cc` could hold a string table, which
is what compiling its own source needs.

## Compiler stage 8: arrays

`int a[N];`, `a[i]` and `a[i] = v` with a computed index, gated by two programs that exit 42. The
enabling change was `exprd` (an expression at a caller-given depth), which is also what retires
`argexpr`.

The bug this wave found is bigger than the feature: **`cc` never reserved stack space**, so its state
slots sat exactly where every `call` pushes return addresses, and the "unexplained nesting corruption"
of two waves ago was a return address landing on a flag. Fixed with `mov ecx, 320; sub rsp, rcx`
(`docs/cc.md`, `docs/WAVES.md`).

Next, in order:

1. ~~Remove the `expr` nesting guard and delete `argexpr`~~ — done: an argument is a whole
   expression, `f(x * 2)` works, and both the workaround and the guard are gone.
2. **A call inside a larger expression** (`n * f(n-1)`): the result comes back in `rax`, so a call at
   depth `d` needs `mov <reg d>, rax` after it, and its arguments must be evaluated at `d+1`.
3. `div r32` is an *assembler* gap and `/` is refused because of it; `add`/`sub r32,imm` likewise
   (`cc` loads a register instead, which is why its code is longer than it needs to be).
4. `char` and byte strings, then `.data` for a string table — at which point a C version of `cc` is
   within reach.

## Compiler stage 9: a call inside a larger expression

`fact(5)` exits 120 and `sum(4)` exits 10, gated. Recursion is ordinary now, not tail-shaped: the
callee's result comes back in `rax` and the live depth registers are pushed and popped around the
call, because a call destroys `rax`, `rcx`, `rdx` and `rsi` (`docs/cc.md`).

That closes the compiler work that began with "an argument must be one term". What remains toward a
self-compiling `cc` is no longer about calls: `char` and byte strings, `.data` for a mutable table of
names, `/` (blocked by the dialect having no `div r32`), and the seven-character name limit.

The name limit is the one to watch: a compiler's symbol table holds identifiers longer than seven
characters, and `cc` refuses them everywhere today — in its own source as much as in what it
compiles. That is a change to `asm1` (labels and names), which means a bootstrap step.

## Compiler stage 10: `char` arrays

`char a[N];` with byte load and store, no element stride, packing proven by a gate (nine bytes take
exactly two slots). The element size doubles as the array's kind, so allocation needs no branch.

What a self-compiling `cc` still lacks, in the order that makes sense:

1. **`add r32, imm` and `div r32` in `asm1`.** Both are assembler gaps that `cc` works around today;
   `add r32, imm` has now cost three workarounds, and `/` is refused outright. Adding `add` needs the
   usual bootstrap step: build with `seed/asm1`, promote, then the source may use it.
2. **Labels and identifiers longer than seven characters.** `asm1`'s label limit is the binding
   constraint on `cc`'s growth (252 of 256 labels), and `cc` refuses identifiers longer than seven
   characters, which is what `identifier` is. Widening both is a bootstrap step in `asm1`.
3. **`.data`** for a mutable table outside the frame, then string literals that live in memory rather
   than being emitted as `db` and written straight out.

## Assembler: `add`/`sub r32, imm`

Both exist now (`81 /0 id` and `81 /5 id`), with capability pairs whose bytes are hand-computed, and
the coverage gate extended to 97 forms. `cc` immediately lost an instruction.

Next on the assembler side, in order of what `cc` needs:

1. **Label and name length.** `asm1` labels are ≤ 7 characters and 256 of them; `cc` is at 252. `cc`'s
   own identifiers are ≤ 7 characters from an 8-byte name field. A C compiler's symbol table is full of
   `identifier`, `keyword`, `emitstr`.
2. `.data` — a second read-write `PT_LOAD`, `filesz`/`memsz` from label differences, and a string table
   that lives in memory instead of being written straight out.
3. `div r32` (`F7 /6`), so that `/` stops being a refusal.

## Labels and identifiers: 15 characters

`asm1`'s labels and `cc`'s identifiers are both 15 characters now. The assembler's widening went
through the bootstrap in the required order (widen, build with the old seed, promote, then the source
may use it), and `cc` followed with its own table, name buffer and comparisons.

That was the last *size* limit blocking a self-compiling `cc`. What is left is capability, not width:

1. **`.data`** — a mutable table that outlives a function, and string literals that live in memory
   instead of being written straight out by `write`.
2. **`div r32`** (`F7 /6`) so `/` stops being a refusal.
3. Then the real thing: `src/cc.c`, compiled by `cc`, assembled by `asm1`, byte-identical to
   `src/cc.s`'s product on the whole corpus. `cc` 7 888 bytes is a large but finite target, and every
   construct it uses now exists in the subset it compiles — except `.data` and `/`.

## Assembler: `div r32` and `div r64`

`div` takes 32- and 64-bit registers now (`F7 /6`, with REX.W for the 64-bit form), so the dialect can
finally divide at the width everything else uses. Four hand-verified encodings, a capability pair each
for the 32- and 64-bit form, two coverage forms and a superiority case whose body bytes are
hand-assembled.

Two things follow, in order:

1. **`/` and `%` in `cc`.** The instruction exists; the compiler still refuses `/`. The emission is
   `mov rax, <left>` / `xor rdx, rdx` / `div <right>`, quotient in `rax` and remainder in `rdx`, which
   needs its own path in `ex2` rather than the one-instruction `emitop`.
2. **`.data`** — a read-write segment, `filesz`/`memsz` from label differences, and string literals
   that live in memory. `write("...")` emits its literal with `db` and writes it straight out; a C
   program needs the bytes to be addressable.

## Compiler: `/` and `%`; assembler: 512 labels

`q = 100/7; r = 100%7; return q*10 + r;` exits 142, gated. The label table holds 512 entries so that a
compiler with three hundred labels still has room.

What is left before `cc` could compile a C version of itself is now a short and specific list:

1. **`.data`** — a read-write segment and string literals that live in memory. Today `write("...")`
   emits its literal with `db` and writes it straight out; a program cannot *address* its own text.
2. **`read`** — the compiler's input is stdin; the subset has no way to read it. (The dialect has
   `syscall`, so this is a `cc` feature: a builtin `read(buf, len)` over a `char` array, using the
   byte array work already done.)
3. Then the port itself: `src/cc.c`, compiled by `cc`, assembled by `asm1`, and compared — the way the
   assembler was bootstrapped, with the dialect frozen as the witness.

## Compiler: `read`, and what the loop found

`read(a, N)` reads stdin into a char array and returns the count; gated by a program that loops over
its input and exits 198, 193 and 0 for three different inputs.

The gate was written the awkward way round because `while (i < n)` does not compile: a condition's
bound must be a literal. That is now the top of the list, ahead of `.data`:

1. **Comparisons against a variable** (`i < n`, `n == want`) — `cond` resolves the bound with
   `numval`, so it must be a constant. Two registers and one register-form `cmp` would do it: the
   dialect has `cmp r32, r32` and `jb`.
2. **`.data`** — string literals that live in memory, so a program can address its own text.
3. Then the port: `src/cc.c`, compiled by `cc`, assembled by `asm1`, compared on the whole corpus.

## Compiler: comparisons against a variable

`while (i < n)`, `if (a > b)`, `a == b`, `a != b` all work; `<=` and `>=` with a variable bound are
refused and say so. The gate is the read loop written naturally: 198 for `ABC`, 193 for ten bytes.

What is left before `cc` could compile a C version of itself:

1. **`.data`** — string literals that live in memory, so a program can address its own text.
2. **`<=`/`>=` against a variable** (`inc`/`dec` on the bound in a register).
3. **Structs, or a disciplined pair of parallel arrays.** A symbol table without either is possible
   but painful: `cc` has eight variables per function and no way to pass an array to a function.
4. **Arrays as arguments.** Today a bare array name is refused, so a function cannot be handed a
   buffer — a compiler's `emit(char *buf)` has no equivalent.
5. Then the port itself: `src/cc.c`, compiled by `cc`, assembled by `asm1`, compared on the whole
   corpus, with the dialect frozen as the witness.

## Compiler: a subscript of a scalar is a pointer

`p[i]` where `p` holds an address works, so a buffer can cross a call: `sumbuf(&s, 3)` reads the
caller's array and exits 198. The element kind in the flags table (0 pointer, 1 char, 8 int) picks the
base (load or `lea`), the stride and the width, so an array and a pointer are one path with different
constants.

What is left before `cc` could compile a C version of itself:

1. **`.data`** — string literals that live in memory, so a program can address its own text. Today
   `write("...")` emits a `db` and writes it out; a compiler needs bytes it can index.
2. `<=`/`>=` against a variable.
3. **More than eight variables per function** and a symbol table that can grow: a compiler has tables,
   and cc has eight slots.
4. Then the port: `src/cc.c`, compiled by `cc`, assembled by `asm1`, compared on the whole corpus.

## Compiler: thirty-two variables

A function has 32 slots instead of 8, in a 264-byte frame. That was the last *count* limit: there is
no longer anything about `cc` that a compiler function would exhaust by being written normally.

Left, in order:

1. **`.data`** — string literals that live in memory. This is now the only thing standing between `cc`
   and a program that parses text, because everything else it needs exists.
2. `<=`/`>=` against a variable.
3. Then the port: `src/cc.c`, compiled by `cc`, assembled by `asm1`, compared on the whole corpus, with
   the dialect frozen as the witness.

## Assembler: `space N`

`space N` reserves N zeroed bytes and a label before it gives their address. It is committed without
the writable segment, because making the segment writable is a header change and a header change
cannot pass the fixpoint gate before it is promoted (`docs/WAVES.md` has the analysis and the two
escape routes).

Next, in order of what unblocks the most:

1. **A large local array in `cc`** — grow the frame for an array instead of refusing one over 32 slots.
   The stack is read-write already, so a compiler's input buffer needs no assembler change at all.
2. **The two-step promote for header changes**, if a writable segment turns out to be needed after
   all. `p_flags` patched at emit time, template untouched, and a `promote-header` target whose
   evidence is the superiority suite rather than the fixpoint.
3. Then the port: `src/cc.c`, compiled by `cc`, assembled by `asm1`, compared on the whole corpus.

## Compiler: `<=` and `>=` against a variable

Both work, so every comparison operator now takes either a literal or a variable on the right. The
literal range checks stay, and so do the two refusals that pin them.

What is left is short and no longer about the language:

1. **A large local array** — the frame is 264 bytes and arrays take slots out of it, so a compiler's
   input buffer does not fit. The stack is read-write already and `cc` emits its own `sub rsp`, so this
   needs no assembler change: allocate arrays from a byte counter and grow the frame.
2. Then the port: `src/cc.c`, compiled by `cc`, assembled by `asm1`, compared on the whole corpus, with
   the dialect frozen as the witness.

## Compiler: arrays are byte-allocated

An array no longer consumes slots: it comes from a byte counter in an 8 200-byte frame, with its offset
in a table beside the kinds. `char buf[200]` written in a loop exits 65; `int a[200]` works.

Two limits stand between this and a compiler's input buffer, and the first is trivial:

1. **Numeric literals are 0..255**, and `emitnum` cannot print four digits. `char b[1024]` is refused by
   the literal parser, not by the frame. Both ends need widening together — the parse limit and the
   printer — and the `return` range check (0..255, one byte) has to stay where it belongs rather than
   living in the shared parser.
2. The frame constant (8 200) caps an array at ~7.7 KB.

Then the port: `src/cc.c`, compiled by `cc`, assembled by `asm1`, compared on the whole corpus.

## Compiler: literals up to 65 535

`char b[2000]` works: `numval` takes five digits and `emitnum` prints them. The frame constant (8 200)
is now the only limit on an array, at about 7.7 KB, and raising it is one instruction if the stack
depth is kept in mind.

That leaves the port itself as the next piece of work rather than another feature: `src/cc.c`, compiled
by `cc`, assembled by `asm1`, compared on the whole corpus, with the dialect frozen as the witness.

## Compiler: `write(buf, n)` — input becomes output

`cat` and a character filter both work: a program can read stdin, transform it, and write the result,
which is the shape of a compiler. `write(a, n)` is the mirror of `read`, with the count as an
expression.

Two gaps that writing them exposed, in order:

1. **A condition cannot be on an array element.** `if (b[i] == 97)` is refused because `cond` parses a
   name rather than a term; the filter hoists into a temporary instead. Fixing it means `cond` taking
   a general term for its left side, which is the same shape as the bound work already done.
2. `int k = write(b, n);` after statements in a block is accepted, but a declaration in the middle of
   a block is worth checking more widely.

Then the port: `src/cc.c`, compiled by `cc`, assembled by `asm1`, compared on the whole corpus.

## Compiler: a condition takes a term

`if (b[i] == 97)` and `while (a[i] > 0)` work: `cond` takes a general term on the left (one `call expr`
where three calls used to be) and a literal or a variable on the right, so every comparison form is
now available on any expression.

What is left is the port itself, and one detail worth checking before it starts: a declaration in the
*middle* of a block (`int k = write(b, n);` after a while loop) is accepted, but whether that is by
design or by luck has not been tested. A C version of `cc` will declare in the middle of blocks
everywhere, so it should be a gate rather than an accident.

Then: `src/cc.c`, compiled by `cc`, assembled by `asm1`, compared on the whole corpus, with the dialect
frozen as the witness.

## Compiler: the subset is described

Every construct the language claims is covered by a gate or a refusal, and the restrictions that are
left are *written down* rather than discovered: no name shadowing (the symbol table is per function),
`<=`/`>=` bounds must be 0..255 when literal, arrays up to ~7.7 KB, 32 scalars, five-digit literals.

The next piece of work is the port, and it is the last one:

**`src/cc.c`** — a C version of this compiler, in the subset it compiles, then

```
cc < src/cc.c > cc1.s        # compiled by the compiler this project grew
asm1 < cc1.s > cc1           # assembled by the assembler it bootstrapped
cc1  < src/cc.c > cc2.s      # and the result must compile itself
cmp cc1.s cc2.s              # identically, on the whole corpus's worth of input
```

The dialect stays frozen as the witness: `asm1` must not move while `cc1` is being made to match it.

## Compiler: grouping, and a routine ported

`(expr)` works, so any expression can be grouped, and `putn` — the decimal formatter, `emitnum`'s
equivalent — is now written in the subset, compiled by `cc`, and gated on its output.

That is the first *piece* of the port rather than a capability added for it, and it went in without any
new assembler feature: `p[i] = p[j]`, `while (i < j)`, `int t = p[i]` and arithmetic with `/` and `%`
were all already there.

What the port still wants, in the order `putn`'s neighbours will hit them:

1. **`char` literals** (`'a'` rather than 97) — cosmetic in the emitted code, but every C source uses
   them, and `cc` prints bytes as numbers today.
2. **`&&` and `||`** — `cond` handles one comparison; a compiler's conditions are usually two.
3. **A function that returns `char *`** — the port will want `emit(char *s)`, and today a pointer is an
   `int` and a string is a buffer plus a length.
4. Then the port itself, one routine at a time, starting with the ones that have no dependencies:
   `putn` (done), then `emitname`, then the literal table.

## Compiler: character literals

`'a'` works in expressions and as a comparison bound, so the subset's programs can be written the way C
is written: `p[len] = '0' + (m - d * 10)`, `if (b[i] == 'a')`.

Next for the port, in the order it will need them:

1. **`&&` and `||`** — a compiler's conditions are usually two comparisons, and today `cond` handles
   exactly one.
2. **A way to return a pointer** — `emit(char *s)` has no equivalent: a string is a buffer and a length.
3. Routines ported one at a time, `putn` and the filter having shown the way.

## The port: slice 1 written, one defect away from running

`src/cc.c` is the output side of the compiler in the subset it compiles. It compiles and assembles; it
does not yet reproduce `tests/selfhost/slice1.expected`, because the emitted text hits a defect in `cc`:

**The block-id counter is saved and restored around a nested body, so sibling blocks share a label.**
Reproduction, smallest form: one function with two sibling `while` loops emits two `L<n>` labels with
the same `n`, and `asm1` refuses the file (`duplicate`). `src/cc.c` (four functions, each with a loop)
is refused at `line 152`.

The fix is to remove the save/restore in `stwhile` and `stif` so the counter only grows, and to raise
the nine-block limit (the labels already go through `emitnum`, so 99 costs nothing). It was attempted
twice with pattern edits and botched twice — the next attempt should change those two blocks with an
edit whose `oldText` includes the surrounding lines, and check `git diff --stat` before building.

Then: slice 2 (the literal section and the prologue/epilogue of a function), slice 3 (the symbol table),
slice 4 (statements), slice 5 (expressions), and the acceptance test

```
cc < src/cc.c > cc1.s ; asm1 < cc1.s > cc1 ; cc1 < src/cc.c > cc2.s ; cmp cc1.s cc2.s
```

## Next: one defect between the port and its first slice

`src/cc.c` compiles and assembles but crashes at run time. The reproduction is in `docs/WAVES.md`:
a call with several arguments and a string literal among them writes at the wrong offsets (three
literals registered in one argument list). Prime suspect: `ex3lit` increments the literal counter while
`wblock` computes its label as `[rbp+20]+1`, so the two indices may disagree when a literal is a *value*
rather than a `write` argument.

After that, the slices in order — the literal section, the prologue and epilogue, the symbol table,
statements, expressions — and the acceptance test:

```
cc < src/cc.c > .work/cc1.s ; asm1 < .work/cc1.s > .work/cc1 ; ./.work/cc1 | cmp - tests/selfhost/slice1.expected
```

Fixed this session and worth not re-breaking: the block-id counter grows monotonically (a gate covers
it, and `asm1` refuses duplicate labels loudly), and `div` saves the live registers around itself.

## The port: slice 1 passes

`make test-selfhost` runs the real pipeline and compares against text written before the code:

```
cc < src/cc.c > .work/cc1.s ; asm1 < .work/cc1.s > .work/cc1 ; ./.work/cc1 | cmp - tests/selfhost/slice1.expected
```

Slice 1 is the output side — a byte buffer, `emitstr`, `emitc`, `putn`, `line` — and it is the first
piece of the port that is *verified* rather than asserted.

Next slices, in order, each with its own expected text written first:

2. the literal section and one function's prologue/epilogue (so the same program can be emitted from a
   table rather than by hand),
3. the symbol table: names, kinds, offsets — the machine that `src/cc.s` implements in dialect,
4. statements: `int x = N`, assignment, `while`, `if`,
5. expressions with precedence, and the emitter for calls,
6. then the acceptance test: `cc1 < src/cc.c > cc2.s ; cmp cc1.s cc2.s`.

What the port still lacks in the language, and will hit in that order: `&&`/`||` (write nested `if`s
instead), and a way to return a pointer (`emit(char *s)` has no equivalent; a string is a buffer and a
length).

## Next: an array element as an argument, inside a loop

Four probes in `docs/WAVES.md` narrow it: `es(p,l,t[0])` outside a loop works, `es(p,l,"ab")` inside a
loop works, and the two combined segfault — including with the element hoisted into a variable *inside*
the loop. Suspect: `[rbp-292]` (argument depth) or the subscript slots overlapping what the loop's body
uses.

Fix that, then slice 2 (the prologue from a table), then the symbol table, statements, expressions, and
the acceptance test `cc1 < src/cc.c > cc2.s ; cmp cc1.s cc2.s`.

## The port: slice 2 passes

`make test-selfhost` is green with the prologue and epilogue emitted from tables of literal addresses.
The attempted version that passed the tables into a function is deleted rather than kept: it was not
blocked by a defect, it was wrong about the language, and keeping it would suggest a bug that does not
exist.

Next slices: the literal section, the symbol table, statements, expressions, then
`cc1 < src/cc.c > cc2.s ; cmp cc1.s cc2.s`.

The language gaps the port will meet, in order: an `int` array cannot cross a call (use tables in the
caller, or a `char` buffer with a length); `&&`/`||` (write nested `if`s); returning a pointer
(`emit(char *s)` has no equivalent).

# Definition of done

"Asking whether we are there" is only answerable if "there" is a command. These are the four criteria, in
order, each falsifiable, each a target that can be run rather than an adjective.

## D1 — the port is the *same compiler*

For every program in the corpus, the port and the dialect compiler must emit the same text:

```bash
for f in tests/golden/*.c; do ./.work/cc1 < $f | cmp - <(./cc < $f) || echo "differs: $f"; done
```

40 programs, including the refusals (both must refuse) and the behaviours (both binaries must exit the
same). Equivalence, not merely self-consistency: a compiler that agrees with itself and disagrees with
the one it replaced has changed the language.

## D2 — it compiles itself, and the result compiles itself identically

```bash
./cc  < src/cc.c > .work/cc1.s      # the dialect compiler compiles the port
./asm1 < .work/cc1.s > .work/cc1    # the assembler makes a compiler binary
./.work/cc1 < src/cc.c > .work/cc2.s
cmp .work/cc1.s .work/cc2.s         # a compiler that emits itself, byte for byte
./.work/cc1 < src/cc.c > /dev/null  # and it must still work, not just agree
```

This is the fixpoint the whole project is built on, now for `cc` instead of `asm1`.

## D3 — the assembler too (the stated endgame)

`src/asm1.c` — the assembler in the same C subset — compiled by `cc`, and the resulting `asm2`
byte-identical to `asm1` on the whole corpus: 18 fixtures, 36 capability pairs, 9 rejections, the
99 032-byte source, and `src/asm1.s` itself. Only then is the chain `src/asm1.c → cc → asm1 → asm2`
closed, with `asm1`'s dialect frozen as the witness throughout.

## D4 — and the record stays clean

Every gate in `make check` green at each step; the dialect frozen; no forbidden tool in the creation or
diagnosis path, disclosed if one ever is; nothing outside the repository; `docs/provenance.tsv`,
`docs/SHAS` and the toolchain ledger current. A port that passes D1–D3 with a record that says otherwise
is the defect this repository was founded to prevent, and it has already happened once.

## Where this stands, measured

| | dialect `cc` | port `src/cc.c` |
|---|---|---|
| lines | 2 968 | 123 |
| routines / functions | 312 labels, ~40 areas | 5 functions |
| gates | 45 checks, 40 goldens | 2 (bytes and behaviour, one fixed program) |
| what it does | compiles the subset | emits the emitter's primitives |

Done in the port: the emission primitives — `emitc`, `emitstr`, `putn` (the decimal printer), `line`,
and one literal-section entry.

Not started, in the order the port needs them:

1. **input and scanning**: `gcur`, `bump`, `skipws` (with comments), `ident`, `numval`, `isword`, `want`.
2. **the symbol table**: `idfind`, `findvar`, `defvar`, `defarr`, `isarr`, `varoff` — names, kinds,
   offsets, and the byte counter that cost this project three defects.
3. **statements**: `int x = N`, `char a[N]`, assignment, `a[i] = v`, `while`, `if`/`else`, `return`.
4. **expressions**: precedence, the six comparison forms, calls, subscripts, literals, `&`/`*`, division.
5. **the literal section** for arbitrary literals rather than one fixed one.
6. **the argument path**, once the defect below is fixed.

## The four things that must be fixed in `cc` first, or written around

1. **Arguments collide with depth registers** (found, reproduced, *not* fixed): `cc` computes an
   argument at depth `d+1`, and at `d = 1` that register is `rdx`, which is the third argument register,
   so a call as the right operand of `+` with three or more arguments passes the wrong values. Fix: park
   arguments in frame slots and load the argument registers just before the call.
2. **An `int` array cannot cross a call** — a pointer subscript is char-indexed by design, so a callee
   cannot index an `int` array it is given. Written around by keeping tables in the caller.
3. **No `&&` or `||`.** Written around with nested `if`s.
4. **No pointer return.** `emit(char *s)` has no equivalent; a string is a buffer and a length.

At the rate of the last three sessions — roughly one slice per session, each slice adding 30–60 lines and
one or two gates — the port is **four to six sessions** away from D2, and `src/asm1.c` is a further
project of comparable size. That is the honest number, and it is the one worth writing down: the work
left is not uncertain, only long.

## Next: the argument spill, again — and the crash it caused

The fix is designed and its acceptance tests exist (`1 + f(1,2,3,4)` = 11, `f(..)+h(..)` = 20, a literal
as a depth-1 argument = 105). What it lacks is an answer to: **why does `cc` segfault on `src/cc.c` with
it applied?** Five functions with loops and 21 literals reproduce it; every gate in the suite still
passes. The reverted patch is `.work/cc.s.argspill` — reapply it, then bisect `src/cc.c` by deleting one
function at a time, which is cheap and was not done here.

Until then the port writes around the collision: no call at depth > 0 with three or more arguments.

## D2 is now a target, and it says how far away it is

`make test-d2` runs the real pipeline: `cc` compiles `src/cc.c` (10 933 bytes), `asm1` assembles it, and
the result must compile `src/cc.c` to the *same* 10 933 bytes. It currently prints

```
d2: the port is not yet a compiler: 288 bytes emitted, expected 10933
```

and exits 1. Everything the port still needs is listed above under "Not started": scanner, symbol table,
statements, expressions, the general literal section. Each replaces one `pro[]` entry with real work, and
the target is the only measure that matters.

The infrastructure around it is now in place: `cc` can compile a 4.7 KB source into 10.9 KB of text
(buffers and limits raised, refusal instead of overrun), the argument path is correct at every depth
(spill), and the port's own slice 3 remains byte- and behaviour-exact.

## Next: finish slice 4a, and the else-chain question

`docs/selfhost-slice4a-attempt.c.txt` is a front end that has passed the scanner and is stopped at a
three-level `else { if ... }` chain (cursor 1796). The tool for it exists now: build
`docs/tools-diagnostic-cc.s.txt` with `asm1` and it prints the input offset of any refusal, so the next
failure is a position rather than a guess.

In order: answer the else-chain question; then the remaining front end (while, if/else in the real file,
calls, arrays); then D2.

## Next: bisect the file, not the construct

Every construct in `docs/selfhost-slice4a-attempt.c.txt` compiles in isolation; the file as a whole is
refused at cursor 1809, on a `}` that its neighbours do not explain. So the failure is contextual and the
next step is mechanical: build the diagnostic `cc` (`docs/tools-diagnostic-cc.s.txt`, prints the input
offset of any refusal), then delete functions from the top of the attempt one at a time until the cursor
moves. The first deletion that changes it names the context.

Candidates worth checking first, in order: the block-id counter (monotonic now, and nothing resets it
between functions), the literal table (99 entries; the attempt has ~40), and the state array's pointer
fields `s[10..14]` — a *pointer stored in an int array* is a shape only the port uses.

## Next: `skipws`, thirteen lines, and a diagnostic that cannot lie

The file-level bisect localised the port's first refusal to `skipws` (function 6 of 21, lines 71–83) with
the sizes recorded, so the search space is thirteen lines rather than a file. The probe method used
against it produced contradictory results, and those are withdrawn.

The next move is to make the diagnostic report something that cannot be stale — the **byte being examined**
when the refusal is raised, or the input line number — rather than the input cursor, which a nested routine
may have moved after the decision to fail was made. Then re-run the three probes that disagree; whichever
of them is real will be visible.

Everything else about D2 is unchanged: `src/cc.c` is slice 3, `make test-d2` is red and says so, and the
attempt at a front end is preserved with its bisect result beside it.
