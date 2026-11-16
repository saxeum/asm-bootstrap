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

Things that break the circularity, in decreasing strength — and the list is shorter than it
was, because invariant 10 of `AGENTS.md` forbids the tools that supplied the middle rungs. A
tool that translates or decodes the artifact cannot judge it, however useful a second opinion
it would be.

1. **Execution.** The CPU does not care what I believe. `ref/hello` prints `Hello, World!`
   and `ref/jmp` exits 7 — so those bytes *mean* what we think they mean. Narrow caveat: only
   the executed path is validated, and a wrong encoding that happens to behave correctly
   would slip through. But this is the strongest independence available here, and it is why
   every reference is *run* before it is hashed, never merely hashed.

2. **Hand-computed bytes.** `db 184, 255, 255, 255, 255` written *before* the encoder for
   `mov eax, -1`, and the capability pairs that compare a new spelling against a hand-written
   dump of the expected body. The expected bytes come from a person reading the encoding, not
   from code in this repo. It does not scale and it is the only rung that is fully independent.

3. **An opcode authority.** `ref.x86asm.net`'s XML reference, queried by `<opcd_ext>`, says
   which primary opcode and group extension belong to each mnemonic and operand shape — the
   canonical opcode for a form, with no vote from my code. All 29 forms we emit are checked
   against it in `docs/encodings.md`, 0 problems, including the finding that our first query
   matched `LOADALL` rather than `SYSCALL` for `0F 05` because that opcode is mode-dependent.
   Limitation: it constrains operand *shape*, not our ModRM/REX/disp bits.

4. **Our own decoder, `src/dis.s`.** For the branch forms it says what the bytes at an offset
   are, and `make check` requires it to agree with all 290 recorded pins. It was written here,
   so it is a *consistency* check between encoder and decoder, not an independent one — a
   shared misunderstanding of `rel8` would hide in both. Its coverage is exactly `EB`, `E9`,
   `E8`, `70`–`7F`, `0F 80`–`0F 8F`, and nothing else.

5. **Self-hosting.** `asmN.s` assembled by `asmN` must equal `asmN`. The cheapest strong
   signal, and it is exactly GCC's `stage2`/`stage3` comparison. It proves stability, not
   correctness: a buggy stage can be perfectly self-reproducing.

Two cheap ones that make the *gates* honest rather than the oracle:

6. **Mutation testing.** Corrupt one byte of the encoder table and confirm the corpus fails.
   A gate that cannot be made to fail is a format check wearing a gate's costume. Done for
   `docs/SHAS` (a one-byte flip), for the branch gate (a corrupted pin and a corrupted
   subject, both recorded in `docs/WAVES.md`), and for `make test-tools`.

7. **Coverage assertion.** Every supported form must appear in at least one fixture. Without
   it, adding a form adds untested code that the corpus silently ignores.

**Gone, and not coming back:** a system disassembler (`objdump`) and a system assembler
(`as`). Earlier waves used both and this document ranked them above everything except
execution; they are now forbidden by invariant 10, which is the same rule that made the branch
gate legitimate again. The replacement for `objdump` is `src/dis.s`, which is rung 4 — weaker,
and ours. The replacement for `as` is nothing: a second assembler would have to be written
here, and writing it would not make it independent either.


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
  useless. That is the `asm0a`-against-`seed/asm1` cross-check this project had until the
  handover, and it is evidence *about the two implementations*, not proof that either is right:
  `asm0a` assembles `and` as `add` (`AGENTS.md`). The cross-check ended when `asm0a` could no
  longer parse the source, which is why it is not on the ladder above any more.
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
4. Independence is added deliberately where it is *allowed*: execution, hand-computed dumps,
   the opcode reference, `src/dis.s` for branch forms, and the fixpoint. Not a system
   disassembler and not a system assembler — invariant 10 rules both out, which is why the
   list above got shorter rather than longer.

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
$ cp asm0a .work/mut   # then swap the two 4-byte entries at file offsets 120 and 148
$ .work/mut < src/hello_num.s > .work/mut.out ; echo $?
0                                     # assembler is happy: 165 bytes, no error
$ cmp .work/mut.out ref/hello
.work/mut.out ref/hello differ: byte 121
$ xxd -s 120 -l 10 .work/mut.out
00000078: bf01 0000 00b8 0100 0000      # mov edi,1 / mov eax,1 — swapped opcodes
```

The gate has teeth: a mutation that produces a plausible, running, wrong binary is caught by
byte comparison at the first wrong byte. This is the check that "a gate must be able to fail"
demands, and it is now recorded rather than assumed.

Note what it does *not* prove: that the unmutated table is **right**. For that, the ladder
above applies — execution (`ref/hello` prints), hand-computed dumps, the opcode reference,
`src/dis.s` for branch forms, and the fixpoint. The two rungs that used to sit between them (a
system disassembler and a system assembler) are gone: this project may not use them.

## Audit of the existing references (before wave 2b)

The concern raised by this document is *sufficiency*, not validity. This is the check that the
existing references are at least **valid** — that no wave is standing on a bad floor.

**The `independent decode` column below was produced with `objdump`, in wave 2b, before
invariant 10 forbade it. It is kept as a record of an audit that was made, and it is not
reproducible: there is no site list for these files, so `src/dis.s` cannot be pointed at them,
and nothing else here can decode a non-branch instruction.** The `execution` column is the one
that can be re-run, and it is the stronger one:

```
./ref/hello
```

prints `Hello, World!`; `./ref/count10` prints `1` through `10`, one per line;

```
./ref/jmp
```

exits 7, where 99 would mean the jump had been dropped; and `./ref/fib` with no argument exits
2 with `fib: need an integer 0..93` on stdout. Those four are the rungs this audit actually
stands on.

| ref | independent decode (objdump, wave 2b — historical, not re-runnable) | execution (re-runnable) |
|---|---|---|
| `ref/hello` | 8 instructions as designed (`mov eax,1` … `xor edi,edi` … `syscall`) | prints `Hello, World!` |
| `ref/count10` | loop as designed, from `mov bl,1` through `lea 0x1(%rsp),%rsi` | prints `1 2 3 4 5 6 7 8 9 10` |
| `ref/fib` | fail block at `0x78`, entry `0x9a` (`cmpq $0x2,(%rsp)`) — matches the documented entry, not `0x78` | `fib 10` → 55, `fib 93` → 12200160415121876738, no arg → exit 2 |
| `ref/jmp` | `jmp 0x84` skipping `mov $0x63,%edi`; lands on `mov $0x7,%edi` | exit 7 (99 would mean the jump was dropped) |

And the assembler still agrees with the validated references:

```
$ ./asm0a < src/hello_num.s | cmp - ref/hello && echo identical
identical
$ ./asm0a < src/exit42.s | cmp - .work/e42.expected && echo identical
identical
```

**Coverage of instruction *forms* by execution.** Every form in the corpus has been executed
at least once: all of `hello` runs; all of `count10`'s loop runs; `fib`'s fail block runs when
invoked with no argument and its main path runs otherwise; `ref/jmp` never executes
`mov edi,99` (it is jumped over), but that is the same form as `mov edi,7`, which does run.
So the corpus validates *forms* by execution even where it does not validate every instance.

**Verdict: no restart required.** The references are valid — each was confirmed by *running* it,
which is the rung that remains open. What this document rejects is the stronger claim that they
make the assembler *correct*, and that rejection stands unchanged.

Residual risks that continue with us, and where each is addressed:

| risk | status |
|---|---|
| non-canonical but valid encodings | accepted: byte-identity is our convention, not correctness |
| forms not yet exercised | each new form gets a fixture **and** a behavioral assertion |
| shared-authorship bias on new forms | `ref/jmp` is built so bytes and behaviour disagree (7 vs 99) |
| `asm0a` error paths coarse (`mov eax,` → `mov eax,0`, exit 0) | recorded as a defect; fixed with 2b's operand handling |
| ELF header judged by one kernel on one machine | accepted for now; the entry field is asserted as four bytes at offset 24 with `od`, which is the check that exists |

## Rung 4: the differential

`tools/differential.sh` compares the compiler's programs with `gcc -O0 -funsigned-char` on stdout
bytes and exit status. It is the only oracle here that is independent of every implementation in this
repository, and it is deliberately **not** part of `make check`: gcc is named in `FORBIDDEN`, so the
script is the one explicit exemption in `make test-tools`, and it is run by hand.

It is in `tests/differential/*.c`, in the intersection of both dialects (no pointer-typed ints, no
`&&`, no `for`). The prelude maps the subset's two-argument `read`/`write` to POSIX
`read(0,...)`/`write(1,...)`.

The gate was shown failing before it was trusted:

```
tools/differential.sh seed/cc ./asm1
  negcmp     DIFFERS (exit 2 vs 1)
  negdiv     DIFFERS (exit 252 vs 253)
  negmod     DIFFERS (exit 0 vs 255)
  signedloop DIFFERS (exit 0 vs 15)
  1/5 programs agree
```

With the signed compiler it is `5/5 AGREE`. A green differential is evidence about the cases it
contains, not a proof of the dialect: `char` is zero-extended, `int` is 64-bit, and the programs avoid
the documented differences.
