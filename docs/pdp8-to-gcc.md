# The PDP-8 assembler, and bootstrapping an assembler from bytecode with an LLM

Two things in one document: how DEC's PDP-8 assembler actually came to exist, and a staged
plan for doing today what the PDP-8 world did by hand — get from a byte stream to a working
assembler that can assemble its own source.

---

## Part 1 — History: how the PDP-8 assembler was created

### The name and the family

PAL = **P**rogram **A**ssembly **L**anguage. It is not one program and not one author. It is
a lineage that starts before the PDP-8 exists:

| Assembler | Date | Who / what | Evidence |
|---|---|---|---|
| PAL for the **PDP-5** (DEC product 5-1-S) | Dec 1964 catalog | author unnamed; conventionally "PAL-I" | Field Guide: *"DEC product number 5-1-S, the Program Assembly Language for the PDP-5 in the PDP-5 program catalog from December 1964"* |
| **PAL-II** | ~1965 | source of PAL-III; **no manual or catalogue reference found** | Jones FAQ says PAL-III came "from PAL II"; the Field Guide says *"I have yet to come across a reference to anything called 'PAL-II'"* |
| **PAL-III** | Aug 1965 (earliest manual) | **Ed Yourdon** "helped hack up" it from PAL-II | Jones FAQ: *"Ed Yourdon helped hack up the PAL III assembler for the -8 from PAL II."* |
| **PAL-D** | manual Apr 1968 | **John Everett**, with Roger Pyle, adapted PAL-III for the Disk Monitor System | Jones FAQ; Everett, alt.sys.pdp8, Dec 1996 |
| **PAL8** | named product by Oct 1970 (PS/8, then OS/8) | DEC | Field Guide |
| **PAL-X** | ~1967 | **Bob Bowering** (author of MACRO for PDP-6/-10), PDP-10 cross-assembler, to specs from Everett and Don Witcraft | Everett: *"Based upon specs provided by Don and me, Bob wrote PAL-X in a very short time."* |
| **AECL PAL8** | Oct 1973 | **D.B. Goulding**, Chalk River — CDC 6600 cross-assembler for PAL III/D/8, report AECL-4593 | the report's title page |

The PDP-8 shipped upward-compatible with the PDP-5, and the PDP-5's assembler was its
assembler. *"That catalog also says that the replacement for PDP-5 PAL is an early version of
PAL-III for the PDP-8"* (Field Guide). The PDP-8 did not grow an assembler from nothing; it
inherited a working one.

### How it ran, and why that shaped it

PAL-III shipped on punched paper tape as the "PDP-8 Assembly System". Assembling took **at
least two passes through the tape reader** to produce a BIN object tape, plus an optional
third pass for a printed listing (Field Guide).

That constraint is the design. The source lives on a tape that can only be read forwards, so
you read it twice: **pass 1 assigns addresses and builds the symbol table** (the tape is
rewound), **pass 2 emits the instruction words** now that every label has a value. The
optional third pass re-reads to print listings and cross-references. Two-pass assembly is not
an algorithmic preference here — it is what a paper-tape reader forces, and it is what almost
every assembler still does today.

### The parts nobody documented

Be precise about the gaps rather than filling them with a nice story:

- **The author of PAL (PDP-5, 1964) and of PAL-II is not named in any source I could reach.**
  Yourdon "helped hack up" PAL-III *from* PAL-II; who wrote PAL-II, nobody says.
- **PAL-II's existence is contested** — the Field Guide searched and found nothing; Jones's
  FAQ treats it as real. Both are careful authors.
- **Nothing documents how PAL-I/PAL-II themselves were bootstrapped.** Front-panel entry and
  cross-assembly on another DEC machine are both plausible; neither is sourced. Do not assert
  either.

What *is* documented is that hand-assembly was routine when no assembler existed. Everett,
describing the R-L Monitor System, says the code was created by *"bizarre and arduous means
[direct deposit into memory of hand-assembled code]"*.

### Why this is an important part of programming history

**1. The assembler is where notation becomes machine truth.** Before it, you wrote machine
words by hand or toggled them in. After it, a program could be expressed in names and
addresses and *translated*. Every layer above — compilers, linkers, virtual machines — sits
on that boundary.

**2. The assembler is the first program that writes programs, and bootstrapping is a
1950s invention.** EDSAC's Initial Orders II (David Wheeler, 1952) was itself hand-translated
into machine code, and its input notation was designed so that the assembler's own source
could be written in it. Wilkes, Wheeler and Gill's *The Preparation of Programs for an
Electronic Digital Computer* (1951) is the first programming textbook, and it is about
subroutines and an assembly scheme. The self-hosting idea is as old as the tools themselves.

**3. Two passes, symbol tables and object formats are the ancestors of the linker.** PAL's
"BIN object tape" is a relocatable-ish object file in embryo: a stream of address/value
records the loader consumes. Add relocation records and you have `ld`'s input.

**4. Cross-assembly invented the host/target split.** PAL-X (PDP-10 → PDP-8), AECL's PAL8
(CDC 6600 → PDP-8) are cross-assemblers: build the tool on a machine that already has one.
That is exactly what a modern cross toolchain is, and it is why `as` and `ld` are
*table-driven* multi-target programs today.

**5. Trust in a toolchain is a bootstrap-shaped problem.** Ken Thompson's *Reflections on
Trusting Trust* (1984) is the canonical statement: a compiler can hide a backdoor in the
compiler that compiles it, and no source review will ever show it. The only defence is an
auditable chain from something you can check by hand. Which is the real reason the plan in
Part 2 is worth doing: it makes every byte attributable to one human-checkable step.

### How the PDP-8 world answered "is the source or the assembler wrong?"

This project hit the ambiguity directly: when a self-hosting build fails, the same binary is both
the tool and the subject, so a failure could be the source or the assembler. The PDP-8 world did not
solve it with a diagnostic. They arranged not to need one, four ways:

**1. The assembler was never built by itself.** PAL-III was "hacked up … from PAL II" — a program for
the **PDP-5**, a different machine. Later, cross-assemblers removed the question entirely: PAL-X
(PDP-10 → PDP-8, Bob Bowering to Everett's and Witcraft's specs) and AECL PAL8 (CDC 6600 → PDP-8,
D.B. Goulding). In every case the PDP-8 assembler was produced by an **independent implementation on
a different machine**, which can be inspected, corrected and rerun on its own terms. That is exactly
the role `asm0a` plays here, and it is why `make bootstrap-check` is worth keeping for as long as
possible. The modern name for the practice is *diverse double-compiling* (Wheeler, 2005).

**2. The medium verified itself.** PDP-8 programs were distributed on paper tape in formats whose
loaders check every block as it is read (the BIN format ends each block with a checksum word). A tape
that had been mis-assembled, mis-punched or mis-read was caught by the loader at load time — not by
the assembler, and not by a person. Byte-comparison was built into the transport, which is the same
move as this project's sha pins and `cmp`-based tests. *(Format details from DEC's tape-format
descriptions; not re-verified against a manual for this document.)*

**3. The listing was the record.** PAL-III's optional third pass produced a printed listing with
addresses and emitted words beside the source lines. That is what a human compared when something
looked wrong: the listing against the source, line by line, by hand. A listing is an artefact that
can be filed, checked and argued about — the ancestor of `docs/branches.tsv` and the pinned decodes.

**4. The frozen original stayed in the archive.** The tapes were kept and the manuals record which
version produced which object tape. Nobody regenerated the cross-assembler "casually"; the chain was
the evidence. This is precisely why `asm0a` is frozen here, and why `docs/toolchain.tsv` exists.

What none of it solves is Thompson's point (*Reflections on Trusting Trust*, 1984): a tool that
deliberately miscompiles can reproduce itself forever, and no amount of self-reproduction detects it.
The PDP-8 answer is the only kind of answer available — a frozen, hand-checkable origin, an
independent implementation to cross against, and media that carry their own checksums.

For this project the practical consequence is that `make triage` answers *"which artefact is
inconsistent with the recorded past"*. It cannot answer *"which artefact is correct"*. Correctness
rests on the frozen hand-written `asm0a`, the hand-emitted `ref/` oracles, and — until Phase 2 of the
roadmap — an independent builder that must agree. Once `src/asm1.s` outgrows `asm0a`, only the first
two remain, which is exactly the position DEC was in.

### The line from PAL to `as` and `gcc` on Linux

Be careful here: this is **design lineage and role lineage, not code lineage.** No line of
PAL-III survives in GNU `as`.

- **The name and the job pass straight into DEC's next machine family.** DEC reused PAL for
  the PDP-11: PAL-11, "Program Assembler Loader" — the predecessor of the macro assembler
  whose syntax Unix was written in (Wikipedia, *PDP-11 architecture*). The PDP-8's own
  assembler was then adapted twice more under DEC names (PAL-D, PAL8), so "the DEC assembler
  that takes two passes over a symbol table and writes an object file" is a continuous
  product line from 1964 to OS/8.
- **Unix `as` is the same program on the next machine.** Unix's assembler was written for the
  PDP-7 and then the PDP-11 — the machine family that inherited PAL's role. The command kept
  the name `as` in every Unix since, and GNU `as` (binutils) is its free reimplementation: two
  passes, a symbol table, an object file out — now ELF instead of a BIN tape.
- **GCC deliberately preserves the layer boundary PAL established.** `gcc` does *not* emit
  machine code. It emits **assembly text**, then invokes `as` to encode it into a relocatable
  ELF object, then `ld` to link it. That division of labour — symbolic source in, object file
  out, encoding done by a separate assembler — is PAL-III's division of labour, unchanged
  across 60 years and several machine families. The reason it survives is the same reason
  PAL had it: the encoder is the thing that must be right about addressing modes, and it is
  better to have exactly one of those.
- **GCC's own build is a PDP-8-style bootstrap.** `make bootstrap` builds stage1 with the
  system compiler, stage2 with stage1, stage3 with stage2, then **compares stage2 and stage3
  object files byte for byte**. If the compiler cannot reproduce itself, the build fails. That
  is the same self-hosting invariant Part 2 is built around.

---

## Part 2 — Plan: LLM bootstraps itself from bytecode to a working assembler

### The problem, stated exactly

An LLM can emit bytes. It cannot be trusted to emit *correct* bytes, and it has no assembler
to check them with — that is the thing being built. So the bootstrapping plan has to answer:
**what is the oracle at each step, when no assembler exists yet?**

Three oracles, in increasing strength:

1. **The kernel.** A file with an ELF header is executed or it is not. Weak: exit status 0 is
   not evidence (this project has already shipped a 186-byte program that printed nothing and
   exited 0).
2. **Known-good artifacts already in the repository.** `hello` (165 B, sha `4f386903…`),
   `count10` (188 B, sha `e61a23c9…`), `fib` (334 B, sha `f61cea2c…`) were hand-emitted and
   hand-verified. They are the differential oracle: an assembler is correct when its output
   for the same program is *byte-identical*.
3. **The fixpoint.** An assembler that can assemble its own source, and whose output for its
   own source equals itself, is self-validating in the same way GCC's stage2/stage3 compare is.

### Ground rules (non-negotiable, learned the hard way)

- **Never overwrite the last working wave.** `asm0` … `asmN` all stay on disk. A regression is
  then a diff, not an archaeology project.
- **Every wave has a sha256, and the sha in the document is the sha that was run.** A sha of a
  file you did not execute is not evidence.
- **Never accept exit status.** Assert on output bytes (`od -c`) and on file bytes (`cmp`).
- **Regression corpus grows, never shrinks.** Each wave must still assemble every earlier `.s`
  file to its recorded bytes.
- **One instruction form per change, with its encoding derivation written down before the
  bytes.** An LLM's failure mode is confident wrong bytes; the countermeasure is a test that
  can fail, per form.
- **A gate must be demonstrated failing once** before it is trusted. Assemble a deliberately
  wrong source and see the assembler reject it.

### The waves

**Wave 0 — no assembler at all (done).** Hand-emit `hello`: 165 bytes, ELF header, one
`PT_LOAD`, `write` + `exit` syscalls, string in the tail. This establishes the layout facts
everything else depends on: entry `0x400078`, `p_filesz` = real size, code offset `0x78`,
string at `0x400097`.
*Acceptance:* prints `Hello, World!`, 165 bytes, sha `4f386903…`.

**Wave 1 — `asm0`, hand-emitted bytecode.** The smallest thing that deserves the name: a
two-pass assembler for `mov r32,imm|label|label.len`, `xor r32,r32`, `syscall`, `db "…"`,
`entry`, labels; it computes the ELF header fields itself, which is the whole point (the
`p_filesz` bug disappears forever).
*Key trick:* the oracle for wave 1 is wave 0. `asm0 hello.s` must produce a file whose sha is
`4f386903…` — identical to the hand-emitted bytes. Nothing else counts as "working".
*Acceptance:* (a) byte-identical to `hello`; (b) the produced file runs; (c) `asm0`'s own
source is in its own dialect, so wave 2 can start.

**Wave 2 — `asm1` assembles itself from `asm0`.** Add what `count10` needs: relative jumps
with label fixups (`jmp/jz/jnz/jb/ja`, rel8, with a hard error when the displacement does not
fit), `mov r8,imm8`, `mov [mem],reg`, `mov byte [mem],imm8`, `lea`, `movzx`, `div r8`,
`add/sub/cmp/test/inc/dec`, and 64-bit forms where they matter.
*Acceptance:* (a) `asm1` built by `asm0` still passes `hello.s` → `4f386903…`; (b) `asm1`
assembles `count10.s` → `e61a23c9…`; (c) `asm1` assembling its own `asm1.s` produces a
working assembler (fixpoint candidate, not yet byte-equal).

**Wave 3 — `asm2`, self-hosting fixpoint.** Add the rest of what `fib` needs (register
extensions `r8d`, `movzx r32,byte [mem]`, `imul r64,r64,imm8`, `div r64`,
`cmp r64,imm8`, absolute symbol references, stderr fail path).
*Acceptance — the strong one:* `asm2.s` assembled by `asm2` must equal `asm2` byte for byte.
Then `asm2` must still reproduce `hello`, `count10`, `fib` exactly. At this point the chain is
self-validating in the GCC stage2/stage3 sense.

**Wave 4+ — start to resemble `as`.** Sections and `org`, expressions, `.equ`, macros,
relocation records, a separate link step, then a second target to force the table to be data
rather than code. Each wave keeps the fixpoint green.

### Where the LLM is genuinely useful, and where it is dangerous

Useful: it supplies the labour the PDP-8 engineers did by hand — deriving ModRM/REX bits,
computing jump displacements, keeping a symbol table consistent — and it can write the *test*
as easily as the implementation.

Dangerous: everything that needs to be *true* rather than *plausible*. Concretely:

| Failure | How it looks | Defence |
|---|---|---|
| Hallucinated opcode/ModRM | assembles, runs, produces wrong numbers | differential test: `objdump -D -b binary` the output and compare mnemonics against the source |
| 32-bit truncation of a pointer | prints nothing, exits 0 | every pointer-form instruction tested at a real runtime address, and asserted on output bytes |
| Header/entry mismatch | every run takes the error path | assert `readelf -h` entry *and* file size separately |
| Regression in an earlier form | wave N silently breaks `count10` | accumulated corpus, byte-compared each wave |
| "It worked" from exit status | silent success | assert on bytes, never on `$?` |

### Why this is worth doing at all

Not because the result is a good assembler. Because it produces a **complete chain of trust**:
every byte in the final assembler traces back to a wave whose source is small enough to read,
and the last link is bytes a human can check against an encoding table. That is the only
answer to Thompson's problem that does not bottom out in "trust the binary someone handed
you" — and it is the same reason Wheeler's Initial Orders II was written in the notation it
implemented, 70 years earlier.

---

## References

- Doug Jones, *DEC PDP-8 FAQs* — https://homepage.cs.uiowa.edu/~jones/pdp8/faqs/
- *A Field Guide to PDP-8 Assemblers* (PiDP-8/I project) — https://tangentsoft.com/pidp8i/wiki?name=A+Field+Guide+to+PDP-8+Assemblers
- alt.sys.pdp8, "pdp-8 PAL8 assembler", John Everett et al., Dec 1996 — https://groups.google.com/g/alt.sys.pdp8/c/d1cyT2rhl0M
- D.B. Goulding, *PAL8: A Program to Assemble Programs for the PDP-8 Computer*, AECL-4593, Chalk River Nuclear Laboratories, October 1973
- DEC, *PAL-D Disk Assembler Programmer's Reference Manual*, DEC-D8-ASAA-D, April 1968
- DEC, *PAL-III Symbolic Assembler Programming Manual*, DIGITAL 8-3-5, 1965
- M.V. Wilkes, D.J. Wheeler, S. Gill, *The Preparation of Programs for an Electronic Digital
  Computer*, Addison-Wesley, 1951 (Initial Orders; the first bootstrap)
- Ken Thompson, *Reflections on Trusting Trust*, CACM 27(8), 1984
- Wikipedia, *PDP-11 architecture* (PAL-11, "Program Assembler Loader") — https://en.wikipedia.org/wiki/PDP-11_architecture
- GCC documentation, *Building and testing* — the stage1/stage2/stage3 bootstrap comparison
- This repository: `hello` (165 B), `count10` (188 B), `fib` (334 B) and their `.s` sources —
  the differential oracle for wave 1 onward
