# Continue here

State of the project at the end of the session that added REX.W, `r8`–`r15`, the coverage gate and the
`[rbp]` fix. Written so a new session can start without re-deriving anything.

**The goal: a compiler.** A high-level language whose backend emits this dialect. That is what the
roadmap is ordered by; `docs/ROADMAP.md` has the requirement table and why `.data` is next.


**The goal: a compiler.** A high-level language whose backend emits this dialect. That is what the
roadmap is ordered by; `docs/ROADMAP.md` has the requirement table and why `.data` is next.

## The numbers

| | bytes | sha256 (16) | notes |
|---|---|---|---|
| `asm0a` | 3 745 | `6271c5ee79034ffd` | hand-written machine code, **frozen**, not a correctness reference |
| `asm1` | 7 903 | `5db95315a741a858` | built by `seed/asm1` from `src/asm1.s` |
| `seed/asm1` | 7 731 | `ac80d9f9094d7051` | the promoted stage; identical to `asm1` |
| `dis` | 1 343 | `2d2eb451d7c7a9a9` | built by `asm1` from `src/dis.s` — our decoder |
| `src/asm1.s` | 31 236 | — | 2 150 lines, 199 labels (limit 256), **no duplicates** |
| `src/dis.s` | 11 108 | — | 467 lines, 48 labels |
| `cc` | 7 765 | `ad243b31bd2ac10c` | built by `asm1` from `src/cc.s` (2 369 lines) — C to dialect TEXT |

Tags `milestone-fixpoint`, `milestone-handover` · 18 fixtures · 9 reject sources · **34 capability
pairs** · **6 superiority cases** (byte-level) + 3 behavioural · 8 exact messages · 38 decoder cases ·
**97 coverage forms** · **cc: 22 checks, 31 refusals** · 290 branch pins · 36 provenance records.

## Verify before touching anything

```
make clean && make && make check
```

`make check` must print, in order: **forbidden tools: none invoked** · **coverage 88/88 forms
exercised** · fixpoint holds · bootstrap NOT APPLICABLE · 9/9 rejections · 8/8 exact messages ·
33/33 capability pairs · 5/5 superiority cases (plus the 99 KB, `entry` and r8d cases) · 38/38 decoder
cases · cc 6 gates · 36 provenance records · SHAS match · `asm1.sha` match · and a real **`branch pins: 290/290`**
line naming both the subject's sha and the decoder's. If any line is missing or red, stop and fix
that first.

Two traps that have each cost a session:

- **`make` before `./asm1`, and check the build's exit code *and* that the sha changed.** A failed
  build leaves the old binary in place, and the next test then reports green about a stale subject.
  `make` and `make check` rebuild their prerequisites; a bare `./asm1` or `./dis` does not.
- **After any change to `src/dis.s`:** `make record` (the decoder is in `docs/provenance.tsv`).
  After any change to `src/asm1.s`: `make promote` and `make record`, or `make check` fails on
  `docs/asm1.sha` and the ledger. Those failures are correct — each has caught an omission once.

## What changed in the last four sessions

**The branch gate is ours** (`src/dis.s`, 290/290 pins, no objdump), **`[rbp]` disp 0 is fixed**
(`8b 45 00`, held by `tests/superior/rbp0`), and **coverage is measurable** (`make test-coverage`, 88
forms). Details in `docs/WAVES.md` and `docs/encodings.md`.

**REX.W, then `r8`–`r15`.** The width of a reg-reg instruction now comes from the operand names
(`reg32` records it in `[rbp+9]`; a mixed pair is refused), and one helper computes
`REX = 0x40|W<<3|R<<2|X<<1|B` from three slots each handler fills — `[rbp-64]` reg field,
`[rbp-68]` rm/base, `[rbp-72]` SIB index. Every code is masked with `and 7` before it enters a ModRM
or SIB byte. `r13`/`r12` needed no new code because the `mod = 00` and SIB rules are masks
(`base & 7 == 5`, `base & 7 == 4`).

**The method that made it possible, and it is worth repeating:** the machinery went in *inert* —
after every step `asm1 < src/dis.s` had to be byte-identical to the previous build, proving no
8-register encoding had moved — and only then did the parser learn the new names. `asm1` 6 947 →
7 488.

## The compiler exists: `helloworld.c` compiles and runs

`docs/cc.md` is the plan and the gate list. One command, and it is the whole pipeline:

```
make hello
```

prints `Hello, World!`. Underneath it is two stages, and the second is not optional: `cc` writes
dialect TEXT, `asm1` makes the program. Skipping the assembler means running a text file full of
assembly as a shell script -- so the emitted text now starts with a `;` comment saying what it is,
which is a comment to `asm1` and a syntax error to the shell, and that line is part of the golden
text and therefore pinned.

Five gates in `make test-cc`: the emitted text is byte-identical to `tests/golden/hello.s`; the
golden assembles; the binary prints exactly `Hello, World!\n` and exits 0; eight inputs outside
the subset are refused with no output; and a second program (two writes, `return 255`) matches its
own golden and runs.

**Writing the oracle found an assembler defect before the compiler existed**: `msg1end-msg1`
was rejected because the lexer did not stop a symbol at `+` or `-` (fixed, pinned by the pair
`expr-nospace`). `docs/cc.md` lists the other seven edges the first client hit and the gate for
each thing that comes next.

## Stage 1 of the compiler: variables and a loop

`cc` 2 030 -> 2 917 bytes. The subset now has `int x = N;`, `x = x ± N;` and `while (x) { … }`,
with one local at `[rbp-8]` and the prologue a person would write. `make test-cc` grew a
sixth gate, and it is a new kind of oracle: the compiled loop's **output** is compared with
the output of `tests/oracle/dots.s`, the same program written by hand in the dialect. Two
sources, one behaviour, neither produced by the other.

That gate found two wrong answers the same day, both in `docs/encodings.md`:

- **`mov r64, imm` was one byte short.** `B8+rd` with `REX.W` takes an eight-byte immediate;
  `mov rax, 1` emitted nine bytes and the immediate ate the next four bytes of the program.
  Now `C7 /0 id`. My own hand-computed expectation had the same error, so the byte gate was
  satisfied — the oracle program segfaulted, and the CPU was the only witness that disagreed.
- **`jbe` assembled as `jb`**, `jnb`/`jno`/`jns` as `jnz`: the dispatcher decided on two
  characters. That is `asm0a`'s `and`-as-`add` defect inside `asm1`. Mnemonics are matched in
  full now, followed by a delimiter, and `jbe x` is a pinned rejection.

## The next assembler work: `.data`, then disp32

The compiler found this by compiling hello world: the string lives in `.text` (readable, so
`write` works), but a *mutable* global, a buffer or a heap cannot. `asm1` emits one `R+X`
`PT_LOAD`, so every byte of the image is code.

1. `.data` directive, opt-in so the 18 fixtures stay byte-identical
2. a second `PT_LOAD` with `R+W`; `filesz`/`memsz` from label differences
3. `db` and labels must know their segment, because file offset and vaddr no longer differ by
   one constant -- `mov eax, 0x400078+label` stops being true for data
4. **disp32**: `lea rax, [rbp-40000]` cannot be written today, so every buffer base is
   `lea rax,[rbp+1]` plus a `sub`. A frame over 127 bytes hits this immediately.

Gate: a compiled program that increments a counter in `.data` and prints it; fixtures
byte-identical; fixpoint; then `make promote`, `make record`, re-pin `docs/SHAS`.

## How to edit `src/asm1.s` (this is not optional)

**Whole-block replacement, anchored on a label and — this is the part that bit last time — on where
the block *ends*.** Five positional edits were attempted in one session and all five failed: deleted
live lines, duplicated labels (three times), handlers inserted inside a neighbour's body (four
 times), a stray label before a branch, and an insertion inside `chklim`'s flag-dependent sequence
that turned a range check into a no-op. Tests caught every one, none was caught by reading.

A replacer that skips "to the next label" is wrong for `memop`, `emitmem` and anything else with
labels inside them: it stopped at `memend:` and appended the block's tail a second time, producing
seven duplicate label definitions that the assembler accepted silently (first wins). **Always say
where the block ends, and count duplicate labels after every replacement:**

```
grep -o '^[a-z_0-9]*:' src/asm1.s | sort | uniq -d
```

The working pattern, used for `memop`, `emitmem`, `chklim`, `trm`, `lfind`, `msg`, `d_n`:

```
cat > /tmp/block.txt <<'EOF'
<the complete replacement block>
EOF
awk 'BEGIN{skip=0} /^label:$/ { while ((getline l < "/tmp/block.txt") > 0) print l; skip=1; next }
     skip && /^[a-z_0-9]+:$/ { skip=0 } skip { next } { print }' src/asm1.s > /tmp/new.s
cp /tmp/new.s src/asm1.s && make && <run the fixtures>
```

Then **immediately**: `make` (check exit code and sha changed), fixtures 18/18, fixpoint.

## Dialect limits that will bite

- label names ≤ 7 characters; ≤ 256 labels; **duplicate labels assemble and the first wins**, so a
  duplicate silently hides dead code. `src/asm1.s` still carries 11, in three dead regions: a second
  `chkok`, `trm`'s `termok`/`termnum`, and the unreachable `lblchk` block with its own `ls1`. (The
  `emitmem` duplicate was deleted this session, which is why the fix there was safe to attempt — see
  `docs/encodings.md`.) All three remaining are dead and harmless to the output, but the *assembler*
  accepting them is what hides the next one, which will not be dead. The fix is a pass-1 duplicate
  check in `asm1`, which would fail on its own source until those blocks are deleted: one deliberate
  change, with `make promote` and `make record`.
- every four-byte frame slot within `disp8` is in use in `asm1.s`: slots are `[rbp+8]`…`[rbp+124]`
  plus `[rbp+2]` (reason byte), `[rbp+4]`, `[rbp+12]` (expression scratch). Negative displacements
  work, so `[rbp-64]`…`[rbp-128]` are free — but `[rbp-8]` and below are the call stack.
- no `add r32,imm32` (`add eax,100` is rejected) — use two `add`s, a register, or `lea`. `add r64,imm8`
  is **not implemented**. `cmp r8,imm8` is signed (−128..127), so compare opcodes ≥ 128 at 32 bits.
- only `jb`, `jz`, `jnz`, `jmp` exist as conditions (plus `.l`): **no `ja`, `jae`, `jbe`, `js`, `jg`**.
  Invert the test, or use `add dl,-N; cmp dl,K; jb` to range-test a byte.
- 64-bit operands in a reg-reg form whose opcode carries no REX are **refused**, not mis-assembled:
  `mov rax,rbx` → `line 1: rejected`. `sub rsi,rcx` works (its opcode sets REX.W).
- `emital` destroys `rcx`, `rax`, `rdx`, `rsi`, `rdi`, and any `syscall` destroys `rcx` too: anything
  needed after one lives in memory or in `rbx`/`rbp`.
- buffers go **below** `rsp`; above `rsp` the mapping ends within a few KB. Read in 120-byte chunks —
  one large read returns a partial count because the kernel only copies into mapped pages.
- a label's value is its **offset from the first body byte**; the load address is `0x400078 + label`.
  `mov eax, 4194424+label` is how a program in the dialect reaches its own data.
- three passes: 0 counts, 1 validates (resolves labels, range-checks, no output), 2 emits. Anything
  that must fail with no output is checked in pass 1.

## Where things are

| | |
|---|---|
| `AGENTS.md` | invariants with their checks, the decoder section, the defect table |
| `docs/ROADMAP.md` | phases, what is done, what is deferred, and why in that order |
| `docs/WAVES.md` | the log, failures included |
| `docs/encodings.md` | chosen encodings, the fixed `[rbp]` defect, the REX.W width rule |
| `docs/oracles.md` | what `ref/` does and does not prove |
| `seed/README.md` | the bootstrap chain |
| `tests/dis/cases.tsv` | the decoder's hand-written expectations, positive and negative |
| `tests/coverage/forms.tsv` | the claim of what is supported; every row must be exercised |
| `tools/shape.awk` | how two source lines are decided to reach the same encoder path |
| `docs/toolchain.tsv`, `docs/provenance.tsv`, `docs/SHAS`, `docs/branches.tsv` | the records |

## Next task: `add r32, imm` in `asm1`, then the name limits

`cc` now has functions, locals, recursion (tail or not), pointers, int and char arrays, and a 64-bit
value model. What it does not have is entirely on the *assembler* side, and the first two are the ones
that bite daily.

### 1. `add r32, imm` (and `sub`, `cmp`)

`add r32, imm` is refused, and it has cost `cc` three separate workarounds (`mov edx, 7; add ecx, edx`
appears wherever a constant is added). `add r8, imm` exists; `and`/`or`/`xor`/`test` have the 32-bit
immediate form. The machinery is there:

- `pc32` emits `op r/m32, imm32` — opcode in `[rbp+44]` (129 = `0x81`), the `/digit` in `[rbp+48]`,
  four immediate bytes. `d_and` reaches it by setting those and jumping.
- `d_add` decides the form by looking at the byte where a three-character register ends
  (`[rbx+6]`), and falls into `daddreg` — the register form — when it is not a comma or a space.
  For `add ecx, 7` that byte is `x`, so it takes the register path and then refuses the immediate.
- The change: after `daddreg` consumes the destination and the comma, peek at the next token; if it
  is a digit, go to `pc32` with `[rbp+44] = 129`, `[rbp+48] = 0` (0 add, 5 sub, 7 cmp). `cmp` is a
  different handler and needs its own check.

Gates that must be extended with it: a capability pair (`asm0a` refuses `add eax, 5`, `asm1` emits
`83 c0 05` or `81 c0 …`), a coverage form in `tests/coverage/forms.tsv`, and a fixture. Then
`make promote`, because after that `src/asm1.s` itself may use the form.

### 2. The name limits

Two separate limits, and only the second needs a bootstrap step:

- **`asm1` labels ≤ 7 characters**, 256 of them. `cc` is at 252 labels of 256: the *label* budget is
  now the binding constraint on `cc`'s growth, and a C function named `emitstr` cannot become a label.
- **`cc` identifiers ≤ 7 characters**, from an 8-byte name field in its own table (`rbp-16000`,
  8 entries, 8 bytes each) and an 8-byte name buffer at `rbp-16064`. Widening to 16 bytes is
  `ident`'s length check, `idfind`'s comparison (two words instead of one), `defvar`/`defarr`'s copy,
  and the buffer. No bootstrap step: it is `cc`'s own table.

Order: labels first (asm1), because a longer name in `cc`'s output must be assemblable.

### 3. `.data`

The last assembler feature with no user: a second read-write `PT_LOAD`, `filesz`/`memsz` from label
differences, and `0x400078+label` stops being true for data. A string table that lives in memory is
the user — today a string exists only as a `write` literal emitted with `db`.

### The rule that would have saved four defects

A fixed frame slot is only safe across a nested parse if nothing else writes it. `-140`, `-268`,
`-128` and `-244` were each shared by accident; the slot table in `docs/cc.md` lists what owns what
and which slots are unsafe across a call. `-304` upward is free.
