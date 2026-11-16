# What the oracles prove, and what they do not

Short answer: `ref/hello`, `ref/count10`, `ref/fib`, `ref/jmp` are **neither necessary nor
sufficient** for "a working assembler". They are a *regression floor*, and their value comes
from one narrow property: they were each validated by **execution**, which is the only judge
in this project that is not me.

## The claim, stated precisely

An assembler is correct when, for every source `s`:

```
A(s) = Encode(Parse(s))
```

A fixture pair `(s, ref)` checks that equation for **one** `s`. A test suite is a finite
sample of an infinite domain. So "sufficient" is unattainable in the strict sense; the useful
question is *which failure classes the sample can catch*.

### Not necessary

A correct assembler may emit a **different but equally valid encoding**. `mov eax, 1` is
`B8 01 00 00 00` in our fixtures; `C7 C0 01 00 00 00` is the same instruction and a working
assembler could emit it. Such an assembler is correct and fails our byte-identity test. So the
fixtures pin *my encoding choices*, not correctness. (This is a feature for reproducibility
and a bug for the claim "necessary".)

### Not sufficient

Byte-identity on four programs constrains the encoder only on the forms those four programs
reach, and only along the parse paths they take. Untested by the current corpus:

- instruction forms the assembler will support later (every `lea` form, every disp8/disp32
  combination, 8-bit registers, `div`, `imul`, REX combinations);
- operand edge cases: label distance > 127 (rel8 overflow), label names > 7 chars, `disp8`
  values that need sign-extension, immediate values with the high bit set;
- the parse paths not exercised: comments, multiple spaces, tabs, a final line with no
  newline, a label on its own line followed by an instruction;
- every error path: rejection is tested for two inputs, and each rejection returns exit 1
  with no output — but nothing asserts *which* error, or that a valid program is never
  rejected by the same code path;
- the ELF header as judged by anything other than one kernel on one machine.

A concrete illustration of the coverage problem: `asm0a` supports exactly four forms
(`mov r32,imm`, `xor r32,r32`, `syscall`, `db "…"`) and the corpus reaches all four. Coverage
is complete *by accident of smallness*. The moment jumps and `lea` land, "the corpus passes"
stops implying "the encoder is right", because the corpus will reach a fraction of the table.

## The real hole: the oracle is not independent of the thing it judges

I wrote both the reference bytes and the encoding table. If I misunderstand a ModRM field,
the misunderstanding appears **in both**, and byte-identity passes while both are wrong.
This is not a new discovery: Weyuker's *On Testing Non-Testable Programs* (Computer Journal
25(4), 1982) names the case — a program is effectively non-testable when the correct output
cannot be specified independently of the program itself. An assembler's expected output is
exactly that: the expected bytes are produced by the same understanding as the encoder.

Four things break the circularity, in increasing independence:

1. **Execution.** The CPU does not care what I believe. `ref/hello` prints `Hello, World!`
   and `ref/jmp` exits 7 — so those bytes *mean* what we think they mean. Narrow caveat: only
   the executed path is validated, and a wrong encoding that happens to behave correctly
   would slip through. But this is the strongest independence available here, and it is why
   every reference is *run* before it is hashed, never merely hashed.
2. **An independent decoder.** `objdump` says which instruction the bytes are, using someone
   else's tables. It shares lineage with the CPU vendor's ISA, but not with my code.
3. **An independent encoder.** Assembling the same fixture with GNU `as` and comparing is the
   strongest check available and does **not** violate the build rule — `as` never touches an
   artifact, it only produces a second opinion in the verification path. Limitation: our
   dialect differs from `as` syntax, so this is per-fixture and partly manual.
4. **Self-hosting.** `asmN.s` assembled by `asmN` must equal `asmN`. Once wave 3 lands, this
   is the cheapest strong signal, and it is exactly GCC's `stage2`/`stage3` comparison.

Plus two cheap ones that make the *gates* honest rather than the oracle:

5. **Mutation testing.** Corrupt one byte of the encoder table and confirm the corpus fails.
   A gate that cannot be made to fail is a format check wearing a gate's costume. We did this
   once, for `docs/SHAS` (`hello: FAILED` after a one-byte flip), and not yet for the encoder.
6. **Coverage assertion.** Every supported form must appear in at least one fixture. Without
   it, adding a form adds untested code that the corpus silently ignores.

## What the PDP-8 people (and their predecessors) used

Nobody had a proof. They had layered redundancy and the machine as final judge.

- **Hand-assembly against the manual's opcode table.** The oracle was a human plus a table,
  with the machine's behaviour as the verdict. `ref/` is the same artefact: hand-computed
  bytes.
- **The machine itself.** Front panel, switch registers, lamps. Toggle a program in, watch
  what the accumulator does. Execution as oracle, before any assembler existed.
- **Checksums in the transport format.** DEC's *BIN* format carried an octal checksum — the
  Binary Loader manual (DEC-08-LBAA-D) shows one explicitly: *"The octal checksum in this
  example is 0422."* Note what class this catches: a misread or mistyped **tape**, not a
  wrong **encoder**. It is a transport oracle, and it is the ancestor of `sha256sum -c`.
- **Listings.** PAL-III's optional third pass produced a listing with a symbol table and
  cross-reference, read by the programmer against the manual. The oracle was human, but the
  *representation* was designed for checking: octal addresses, one instruction per line.
  Our `docs/wave1a-asm0a.md` annotated listing serves the same purpose.
- **Diagnostics.** DEC shipped MAINDEC-08 diagnostics: programs that exercise the instruction
  set and report pass/fail. That is a test suite with its own verdict — the ancestor of
  "the fixture must exit 7, not 99".
- **A corpus that has to work.** DECUS library programs, and OS/8 itself. If the OS boots,
  the assembler was right about everything the OS touches. Integration as oracle, and the
  reason an assembler's bugs surface as "the editor won't assemble".
- **Differential testing across implementations.** PAL-X (Bob Bowering, PDP-10 → PDP-8) and
  AECL's PAL8 (CDC 6600 → PDP-8) had to agree with DEC's native assembler or they were
  useless. That is our rung 3, done because cross-assembly made it necessary.
- **Self-hosting.** PAL-III was "hacked up … from PAL II"; later DEC assemblers were
  assembled by their predecessors. The bootstrap chain *is* the long-run oracle.
- **Earlier still.** EDSAC's Initial Orders II was written in the notation it implemented and
  hand-translated into machine code; verification was hand-computed results and check sheets
  (Wilkes, Wheeler & Gill, 1951). Nathaniel Rochester's 1954 IBM 701 assembler was checked
  by comparing its output against hand-assembled programs — differential against hand
  assembly, which is precisely what `ref/` does here.

## What we may therefore claim

- `./asm0a < src/jmp.s | cmp - ref/jmp` proves `asm0a` still agrees with a byte sequence whose
  *behaviour* was verified by running it, on one program, through the parse paths that program
  takes.
- It does **not** prove `asm0a` is correct, complete, or that a different valid encoding is
  wrong.
- The corpus must grow with the instruction table, and each form needs a fixture **plus** a
  runtime assertion, because bytes and behaviour fail differently: `ref/jmp` exits 7 when the
  jump is encoded and 99 when it is dropped, so it distinguishes the two. A fixture that only
  exits 0 would pass either way.

## Consequences adopted

1. Every new form gets a fixture whose *behaviour* changes if the form is wrong — not just a
   byte comparison.
2. The gate for each wave is: byte comparison **and** a runtime assertion **and** a
   demonstrated failure (mutation or negative test).
3. `docs/SHAS` is checked from a clean tree; a wave is not "kept" until it passes.
4. Independence is added deliberately where it is cheap: `objdump` on every new encoding,
   GNU `as` as a second opinion where the syntax maps, and the fixpoint once wave 3 exists.

## References

- E. J. Weyuker, *On Testing Non-Testable Programs*, The Computer Journal 25(4):465–470, 1982.
- DEC, *Binary Loader*, DEC-08-LBAA-D (octal checksum example, `0422`).
- DEC, *PAL-III Symbolic Assembler Programming Manual*, DIGITAL 8-3-5, 1965 (listing, symbol
  table, cross-reference).
- D.B. Goulding, *PAL8: A Program to Assemble Programs for the PDP-8 Computer*, AECL-4593,
  1973 (a cross-assembler whose value depended on agreeing with the native one).
- M.V. Wilkes, D.J. Wheeler, S. Gill, *The Preparation of Programs for an Electronic Digital
  Computer*, 1951 (hand-translation and check sheets).
- GCC documentation, bootstrap `stage2`/`stage3` object comparison.

## Mutation test log

Run against a **copy** of `asm0a`, never the artifact. Mutation: swap table entry 0 (`eax`) and
entry 7 (`edi`), which still assembles fine but maps two register names to the wrong codes.

```
$ cp asm0a /tmp/mut   # then swap the two 4-byte entries at file offsets 120 and 148
$ /tmp/mut < src/hello_num.s > /tmp/mut.out ; echo $?
0                                     # assembler is happy: 165 bytes, no error
$ cmp /tmp/mut.out ref/hello
/tmp/mut.out ref/hello differ: byte 121
$ xxd -s 120 -l 10 /tmp/mut.out
00000078: bf01 0000 00b8 0100 0000      # mov edi,1 / mov eax,1 — swapped opcodes
```

The gate has teeth: a mutation that produces a plausible, running, wrong binary is caught by
byte comparison at the first wrong byte. This is the check that "a gate must be able to fail"
demands, and it is now recorded rather than assumed.

Note what it does *not* prove: that the unmutated table is **right**. For that, the
independence ladder above applies — execution (`ref/hello` prints), a decoder (`objdump`), an
independent encoder (`as`), and eventually the fixpoint.
