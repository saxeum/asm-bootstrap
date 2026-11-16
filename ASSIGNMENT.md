# Assignment: bootstrap a toolchain, then write a Lisp compiler in your own dialect of C

You will build, from nothing, an assembler, a C-subset compiler and a Lisp compiler — and you will
prove that each one is what it claims to be. The Lisp is not the point. The chain of trust is the
point, and an LLM will be your fastest hands and your worst witness. The deliverable is a chain in
which every link can be checked by something that does not share the previous link's failure mode.

```
   you write bytes          asm(asm.s) == asm            cc(cc.c) == cc           lisp -> C -> asm -> ELF
   ----------------   G1    ------------------      G5    --------------    G7    ----------------------
   seed/hello  -----> asm ------------------------> asm'  ---------------> cc  ----------------> corpus
   hand-emitted             in your dialect          self-hosted            self-hosted        G8, G10
```

Nothing in this chain may be produced by a compiler, assembler, linker, interpreter, disassembler or
script. You may use anything you like to *check* your work — but see Rule 4, because that is where
this assignment is actually marked.

## What is given to you

Nothing but this document, a container, and an oracle:

- `corpus/*.l` and `corpus/*.out` — Lisp programs and their exact expected stdout, frozen by the
  instructor. You do not get the interpreter that produced them. They are data, not a tool.
- No starter code. No reference assembler. No `gcc`, no `as`, no `ld`, no `python` in the container.
- The grade is computed by the commands in **The gates**, run by the instructor, from your tree.

## The five rules

1. **No forbidden tool produces an artefact.** `gcc`, `clang`, `as`, `ld`, `nasm`, `objcopy`,
   `readelf`, `objdump`, `python`, `perl`, `ruby`, `node` may not be invoked by any rule in your
   `Makefile` or by anything under `tools/`. Your `make check` must detect a violation of this and
   fail; the instructor's container does not have most of these, so a build that secretly used one
   dies at grade time. Decoding your own output is allowed — `od`, `xxd`, `cmp`, `awk`, `sed` — but
   the decoder you trust for *verification* should be one you wrote (`src/dis.s` in the reference
   project is 1 343 bytes and replaced `objdump` entirely).
2. **A gate must be shown failing once.** Every check you write must be delivered together with a
   command that breaks the artefact and makes the check go red. A check that has never failed is a
   format check wearing a gate's clothes, and it earns nothing.
3. **One wave, one gate.** Never change two things between two runs of `make check`. When it fails
   you must be able to say which change did it.
4. **Disclose every tool used outside the chain, in the same commit.** A generator, a script, an LLM
   prompt that rewrote a file, a hand-copied hexdump from another binary: all of it goes in
   `DISCLOSURE.md` with what it produced and what is now pinned to compensate. Undisclosed is an
   automatic zero for the section, however good the code is. Disclosed and pinned is full marks:
   covered shortcuts are engineering, uncovered ones are cheating.
5. **Never regenerate a reference to make a test pass.** `ref/` and `corpus/*.out` are the floor. If
   your tool and the reference disagree, neither is presumed right: produce the evidence, decide,
   and write down which one was wrong and why.

## Required layout

The instructor's commands assume exactly these paths. Create them all; leave nothing implicit.

```
seed/hello            hand-emitted program, committed binary   (Gate 1)
seed/asm              hand-emitted 4-form assembler, committed (Gate 2)
ref/*                 hand-emitted reference binaries, committed, never regenerated
src/*.s               dialect sources (your assembler, your decoder, fixtures)
src/*.c               C-subset sources (your cc, your Lisp compiler)
lisp/*.l              Lisp sources, including the interpreter in Lisp (Gate 10)
corpus/*.l  corpus/*.out
tests/*.s  tests/*.c  tests/*.l   and the refusal sources
tools/*.sh            every checker, each with a --selftest
pins.sha              sha256sum -c format, for every committed binary
mutation.sites        one line per declared mutation site: offset<TAB>what it breaks
Makefile              make check runs every gate; nothing else is implied
RECORD.md             the defect log
DISCLOSURE.md         tools used outside the chain
REPORT.md             the numbers, each with the command that printed it
```

## The gates

Ten weeks, one gate each. The commands are the instructor's; `make check` in your tree must contain
at least these properties, but the instructor does not accept your `make check` as the evidence — it
runs these.

### Gate 1 — a program, written as bytes

Build `seed/hello`: an ELF64 executable that writes one line to fd 1 and exits 0, emitted as literal
bytes with a text editor and `printf`. No assembler exists yet; that is the point.

```
./seed/hello
```

prints exactly `bootstrap` followed by a newline, and exits 0.

```
od -An -tx1 -N16 seed/hello
```

prints ` 7f 45 4c 46 02 01 01 00 00 00 00 00 00 00 00 00`.

Submit `LISTING-1.md`: every instruction with its byte count, its file offset and its meaning in
decimal, and the ELF header field by field. This listing is the artefact a reader checks *instead of*
trusting you, and it is marked as such.

What this gate catches: an ELF that runs is one kernel's opinion; the listing is the independent
check. If you cannot write the listing, you do not know what you emitted.

### Gate 2 — a 4-form assembler, byte-identical

Build `seed/asm` (hand-emitted, like Gate 1) for `mov r32, imm32`, `xor r32, r32`, `syscall` and
`db "…"`, reading source on stdin and writing an executable to stdout.

```
./seed/asm < tests/hello.s | cmp - seed/hello
```

prints nothing and exits 0. Byte identity, not "it runs".

What this gate catches: your assembler's ELF header, `p_filesz`, entry point and encoding table, all
at once, against bytes that existed before your assembler did.

### Gate 3 — labels, two passes, and a range check

Add label definitions, a symbol table, two passes by re-parse, and `jmp label` with rel8.

```
./seed/asm < tests/jmp.s | cmp - ref/jmp
```

prints nothing.

```
./seed/asm < tests/far.s > /dev/null 2>&1
```

leaves the shell's `$?` at **1**, and writes nothing to stdout. The grader reads the exit status, not
the presence of a message: a missing or broken `seed/asm` exits 127, and a silently-wrapping one
exits 0, so only the number 1 counts. A forward jump past ±127 bytes must fail loudly, not wrap.

What this gate catches: the two-pass architecture, and the difference between "the jump was emitted"
and "control happened to land somewhere harmless". Your `tests/jmp.s` must be a program whose exit
status differs depending on whether the jump was emitted — 7 if it was, 99 if it fell through.

### Gate 4 — register class and memory operands, observed

Add `mov r8, imm8`, `movzx r32, r8`, `mov [base+disp8], r8`, `mov byte [base+disp8], imm8`, `lea`.

```
./seed/asm < tests/mem.s > /tmp/mem && chmod +x /tmp/mem && /tmp/mem | od -c
```

prints `0000000   H  \n`.

What this gate catches: a wrong SIB byte, a wrong displacement, a register-class confusion. None of
them stop the program running; only an *observed* value does. Encode one byte, load it back, write it
out — the addressing mode is then on stdout where you can look at it.

### Gate 5 — the assembler assembles itself

Rewrite the assembler in its own dialect in `src/asm.s`, build it with the Gate-4 assembler, then
promote that binary to `asm` and require the fixpoint.

```
./asm < src/asm.s | cmp - asm
```

prints nothing. Every earlier reference must still be byte-identical.

Submit `promote.md`: the sha256 of the binary you promoted, the binary that built it and *its*
sha256, and a one-line argument for why this is a promotion and not a self-build.

What this gate catches: a miscompilation that would otherwise be preserved forever, because the next
generation would be built by the flawed one and agree with it. A binary never builds itself from its
own output; the seed is the authority and promotion is a deliberate act with a diff to read.

### Gate 6 — a C-subset compiler

Write `src/cc.c` — a compiler for the subset in **Appendix A** — in the assembler's dialect, and
build it with `asm`.

```
./cc < tests/p.c > /tmp/p.s && ./asm < /tmp/p.s > /tmp/p && chmod +x /tmp/p && /tmp/p
```

exits 42, printing nothing. You must supply at least ten such programs whose exit status or stdout
changes if codegen is wrong, and at least eight refusals:

```
./cc < tests/unsupported.c > /dev/null 2>&1
```

leaves `$?` at **1**, writes nothing to stdout, and names the offending line number on stderr. Eight
such files, each refused for a different reason.

What this gate catches: plausible wrong code. `int a = 0 - 5; if (a < 0)` must agree with C, or be
refused with a message. There is no third option — an unsigned comparison silently taken is the worst
defect class in this assignment, because it produces a running program with the wrong answer.

### Gate 7 — the compiler compiles itself

Port `cc` to its own subset in `src/cc.c` (yes, that means writing it twice; the second time is the
one that counts), build it, and require the fixpoint.

```
./cc < src/cc.c > /tmp/cc1.s && ./asm < /tmp/cc1.s > /tmp/cc1 && chmod +x /tmp/cc1 && /tmp/cc1 < src/cc.c | cmp - /tmp/cc1.s
```

prints nothing. This is GCC's stage2/stage3 property, and it is the strongest single signal you will
produce all term: a compiler that emits text which compiles to a compiler that emits the same text.

### Gate 8 — a Lisp compiler, and the corpus

Write `src/lisp.c` — a compiler from **Appendix B**'s Lisp into your C subset — in the C subset,
build it with `cc`, and provide `tools/run-lisp.sh`, which takes a `.l` file and runs the whole
pipeline: Lisp → C-subset text → `cc` → `asm` → executable → stdout.

```
for f in corpus/*.l; do ./tools/run-lisp.sh "$f" | cmp - "${f%.l}.out" || echo "FAIL $f"; done
```

prints nothing when every program agrees with the frozen oracle.

What this gate catches: everything at once, which is why it is last-but-one. A bug in the reader, the
environment layout, the tag scheme or the assembler shows up as a disagreement with data the
instructor froze before your compiler existed.

### Gate 9 — heap, and a program that survives it

Make the heap real: cons cells from a fixed region, a bump or free-list allocator, overflow refused by
name (or collected — say which), and at least one corpus program that allocates more cells than fit
at once.

Same command as Gate 8. Submit a second corpus directory `corpus/stress/` with its own `.out` files
produced by *your* compiler and inspected by hand, plus a statement of the heap size, the allocation
policy and what happens on exhaustion (refusal with a message, or collection — say which).

What this gate catches: an allocator that works only when nothing is freed, and a Lisp that quietly
returns garbage on overflow.

### Gate 10 — the closure

Write an interpreter for the Lisp in **Lisp** (`lisp/interp.l`), compile it with your Lisp compiler,
and run the corpus through it.

```
./tools/run-lisp.sh lisp/interp.l < corpus/fact.l
```

prints the same stdout as `corpus/fact.out`.

Now three languages and three levels agree: `cc` compiled the Lisp compiler, the Lisp compiler
compiled the interpreter, the interpreter ran the program, and the answer is the one the instructor
froze before any of it existed. Submit `RECORD.md`, `DISCLOSURE.md`, `REPORT.md` and the signed
line: *I read every line of the final diffs.*

## Working with an LLM

Use one. You will not finish otherwise, and refusing to use one is not the skill being taught. These
ten rules are the skill; each one exists because it was violated in the reference project this
assignment is modelled on, and the violation has a name there.

1. **One wave, one gate.** A session that changes two things cannot tell you which broke it. A
   441-byte block emitted in one go cost six defects; the same feature split into two waves cost one.
2. **Start every session by reading the artefact, not the model's memory of it.** Run
   `sha256sum -c pins.sha`, `git log -1`, and the gate. Summaries go stale; a README in the reference
   project asserted a false byte count for eight waves, and a table of "implemented" encodings was
   two waves behind twice.
3. **Decode before you run.** The model proposes hex; your first act is to decode it and compare to
   the intended operands. "It ran" says it did not crash. In the reference project, over thirty
   defects were recorded with their cause and their catcher, and not one was caught by re-reading
   the code.
4. **Ask for the gate before the code.** One sentence: "this wave is done when this command prints
   nothing". Write it in the commit message of the *first* commit, then write the code.
5. **When it fails, forbid guessing.** Require a discriminating experiment: what does the failing case
   depend on that the passing case does not? A bug that looked like arithmetic was a tail jump
   leaving `rsp` eight bytes low; it was found by splitting the symptom on what the next line needed.
6. **A rule in prose is not a rule.** If the model says "always decode patched sites", it must also
   deliver the checker and a `--selftest` that feeds it a known-bad input and requires a failure.
   The prose version of that rule was violated twice more after being written down; the mechanised
   version has now held for 290 pinned branch sites.
7. **Record every defect where the fix is**, same commit: symptom, cause, the observation that
   discriminated it, the check that now catches the class. This is `RECORD.md` and it is 15% of your
   mark. An LLM cannot reconstruct it for you afterwards and will invent a tidier story than the one
   that happened.
8. **Disclose, in the same commit, any tool used outside the chain.** In the reference project the
   only genuine breach was a Python script that wrote one source file at its birth: no gate could see
   it, it did almost none of the work, and it damaged the claim more than any of the thirty defects.
   That is Rule 4, and it is the most transferable thing in this assignment.
9. **Never let the model regenerate a reference to make a test pass.** In the reference project the
   hand-emitted reference was the thing that was wrong (a rel32 jump where the dialect mandates
   rel8), both binaries behaved correctly, and only the byte comparison found it. Escalate with
   evidence instead.
10. **You read the final diff.** Not the model. You sign it. The integrity claim of your submission is
    that a person read every line once.

The one-line version: **the model writes candidates; you own the oracle.**

## The record

`RECORD.md` — one entry per defect, no exceptions, including the ones you fixed within a minute:

```
## 4 — `jmp` to a label 132 bytes away wrapped instead of failing
symptom    the program exited 7 that it should not have reached
cause      rel8 subtraction in file space, segment base not subtracted
discriminated by  decoding the two-byte jmp and comparing the displacement to the
           intended label offset, which was 132
now caught by     tools/check-branches.sh, site 0x785; `make gate-3` refuses tests/far.s
```

`DISCLOSURE.md` — every tool outside the chain, with what it produced and what now compensates. An
honest file with three entries scores higher than an empty one.

`REPORT.md` — every number with the command that printed it, so a reader can re-run it. Typed numbers
are checked; stale numbers are the most common way a good project loses marks.

## Marking

| weight | what |
|---|---|
| 40 | the ten gates, in the instructor's container, 4 each |
| 25 | quality of your oracles: each accompanied by the command that makes it fail, and a `--selftest` for every checker |
| 15 | `RECORD.md` and `DISCLOSURE.md`: causes and catchers, and the truth about your tools |
| 15 | Lisp behaviour: the corpus, the stress corpus, and the Gate-10 interpreter |
| 5 | the oral |

## How it is graded

```
docker run --rm -v "$PWD:/w" -w /w --network none bootstrap-grade:latest make check
```

The image has `bash`, `make`, `coreutils` and `git`; it has no network, no `gcc`, no `as`, no `ld`,
no `python`. A build that secretly used any of them fails here rather than in your viva.

Then the mutation test, which is the part you cannot talk your way out of:

```
./tools/mutate.sh 1 && (make check > /dev/null 2>&1 && echo 'gate did not fail' || echo caught)
```

prints `caught` for each site declared in `mutation.sites`. The instructor applies each declared
mutation independently — flipping one byte of a register table, one displacement, one opcode — and
requires `make check` to go red. Eight of ten declared sites must be caught. A site that is declared
but benign is a point lost, because it means you do not know what your gate covers.

Two oral questions, ten minutes each, worth 2.5 each:

1. "Here is a mutated copy of your assembler. Which gate catches it, what does the failure look like,
   and what do you do next?"
2. "Here are three claims from your `REPORT.md`. One is false. Find it and prove it."

## Honours extensions

- Self-host the Lisp compiler in Lisp, and require its output for the corpus to be byte-identical to
  the C-subset compiler's. That is the Lisp analogue of Gate 7.
- A mark-and-sweep collector over an explicit root set, with a stress corpus that proves it runs.
- Proper tail calls: a 100 000-deep tail-recursive loop must not exhaust the stack.
- Compile the same Lisp with a second code generator (register-threaded rather than stack-based) and
  make both pass the corpus, then measure the difference and say what it cost in lines.

## What this assignment does not prove

Read this section twice; it is marked in the oral.

Byte identity proves your assembler agrees with bytes whose behaviour you verified on the programs you
ran. It does not prove your assembler is correct: a different but valid encoding is still correct, and
would fail your test. A fixpoint proves two assemblers agree, not that either is right. Your corpus is
a finite sample of an infinite domain. Exit status is never evidence. Every claim you make should be
narrower than the evidence you have, and the report should say which evidence decides which claim.

## Appendix A — the C subset

Two types: `int` (64-bit) and `char` (a byte, zero-extended on load). Arrays; pointers via `&` and
`*`; functions with up to four arguments; recursion; `while`, `if`/`else`; `+ - * / %`, all six
comparisons *signed*; assignment; declarations anywhere in a block; `read(buf, n)`, `write(buf, n)`,
`exit(n)` as builtins. No `for`, no `switch`, no structs, no `sizeof`, no preprocessor, no
floating point, and **anything outside the subset must be refused with a message naming the line**.

## Appendix B — the Lisp

```
form    := atom | '(' form* ')' | "'" form
atom    := integer | symbol | #t | #f | ()
special := quote | if | define | lambda | let
builtin := cons car cdr eq? atom? null? + - * = < >
```

- Values are tagged words: fixnum `n << 1 | 1`; cons is a pointer into a static heap; `()` is 0.
- `lambda` closes over nothing at runtime: free variables are resolved to environment-array slots at
  compile time, and each generated function receives its environment as its first argument.
- `define` at top level allocates a global slot.
- The reader is recursive descent over a byte buffer; comments are `;` to end of line.
- Errors (unbound symbol, `car` of a non-cons, heap exhaustion) print one line to stderr and exit 1.
- Required corpus behaviour is fixed by `corpus/*.out`; nothing else about the language may differ.

## Appendix C — submission checklist

- [ ] `make check` exits 0 in the grading container, from a clean clone, with no network.
- [ ] `sha256sum -c pins.sha` passes; every committed binary is pinned.
- [ ] every checker under `tools/` has a `--selftest` and it fails on a known-bad input.
- [ ] `mutation.sites` has at least ten entries, each annotated with what the flip breaks.
- [ ] `RECORD.md` has an entry for every defect, including the ones that lasted a minute.
- [ ] `DISCLOSURE.md` names every tool used outside the chain.
- [ ] `REPORT.md` quotes a command for every number in it.
- [ ] the signed line: *I read every line of the final diffs.*
