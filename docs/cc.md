# The compiler: `helloworld.c` to a running binary, and the gates it forces

This is the plan for the second half of the project: a **compiler** whose target is this dialect. It
starts with the smallest complete example, because compiling `helloworld.c` end to end already says
what every gate has to be.

## The design decision, first

**The compiler emits dialect source, not machine code.**

```
./cc < helloworld.c > hello.s        a compiler written in the dialect, built by asm1
./asm1 < hello.s > hello             the assembler is still the only thing that makes bytes
./hello                              Hello, World!
```

Three consequences, and they are the reason:

1. **The output is reviewable.** A compiler that emits text can be diffed, read, and argued about;
   one that patches an ELF cannot. Every mistake in the backend is visible as a line of assembly.
2. **`asm1` stays the only byte-producer.** The correctness of the encoding is already gated by 18
   fixtures, 12 rejections, 29 capability pairs, 88 coverage forms and the fixpoint. A compiler
   emitting bytes directly would need all of that again, for itself.
3. **The gates are cheap.** `cmp` against a golden text file, `cmp` against the machine's output.

## The subset, exactly (stage 0)

```
program  := decl
decl     := 'int' 'main' '(' 'void' ')' block
block    := '{' stmt* '}'
stmt     := 'write' '(' string ')' ';'
          | 'return' number ';'          (last statement only, optional)
string   := '"' any-bytes-except-quote '"'
number   := decimal 0..255
comment  := '/*' ... '*/'  |  '//' ... end-of-line
```

Semantics, which is the whole ABI at this size:

| source | meaning |
|---|---|
| `write("s")` | `syscall` 1, fd 1, the address of a `db` holding the literal's bytes, length = `end-start` |
| `return N` | `syscall` 60 with status N |
| nothing after `}` | required; trailing tokens are refused |
| no `return` | exit 0 |
| up to 9 `write`s | one label pair per literal, `m1`/`m1end` … |

`write` is a **statement, not a call**, and that is the honest part of stage 0: there is no calling
convention yet, so a function call cannot be compiled. Turning `write(...)` into a call is gate 5
below.

## The output text, which is a designed artefact

The emitted text has one shape, and `tests/golden/hello.s` is its specification:

```
main:
mov eax, 1
mov edi, 1
mov esi, 4194424+m1
mov edx, m1end-m1
syscall
mov eax, 60
mov edi, 0
syscall
m1:
db "Hello, World!\n"
m1end:
```

Three things are chosen deliberately:

- **`4194424+m1`** is `0x400078 + label`, the first body byte plus the label's offset: the dialect
  knows a label's value as an offset, and the image is loaded at a fixed address.
- **`m1end-m1`** is the string length as a label difference, so the compiler never counts bytes.
  This is what the expression support was built for, and it is why `label-label` had to lex without
  spaces (see the defect below).
- **All code, then all data.** A `db` between two `syscall`s would be *executed* when the write
  returns. So literals are collected during the parse and emitted after the exit block.

## The gates

```
make test-cc
```

| # | gate | fails when |
|---|---|---|
| 1 | `cc < helloworld.c` is byte-identical to `tests/golden/hello.s` | the emitted text changes shape |
| 2 | `asm1 < tests/golden/hello.s` produces a binary | the golden is not assemblable |
| 3 | that binary writes exactly `Hello, World!\n` and exits 0 | the semantics are wrong |
| 4 | eight inputs outside the subset are refused: exit 1, **no output at all** | the front end guesses |
| 5 | a second program (two writes, `return 255`) matches its own golden and runs | only one case ever works |

Gate 3 is what makes gate 1 mean anything. The golden cannot be an *oracle* for its own text — it is
a regression pin, and its validity rests on the machine judging the binary it assembles to. That is
the same split as `ref/`: bytes are pinned by a hand-written expectation, meaning is pinned by
execution.

Gates 1 and 3 were both checked by breaking them: a one-byte change to the golden fails gate 1 with a
diff, and changing the string to `Hello, World?` fails gate 1 *and* gate 3 (`the binary exited 0 and
wrote [Hello, World?]`).

## What writing the oracle found in the assembler

The C file and its hand-written golden were written before the compiler, and that act alone found
defects. This is the pattern the project already uses (`ref/` before the tool): the oracle is the
first client, and the first client finds the awkward edges.

1. **`label-label` without spaces did not assemble.** `msg1end-msg1` was read as one long symbol,
   because the lexer's symbol-terminator set was `:`, space, newline and NUL — not `+` and `-`. With
   spaces it worked, which is why no test had noticed. Fixed in `lcpy`, pinned by the capability pair
   `expr-nospace`.
2. **`cmp r32, [mem]` does not exist** and the compiler needed it immediately (`cmp eax, [rbp+20]`).
   Worked around by loading into a register. It is on the compiler's list for a reason.
3. **`add r32, imm32` does not exist.** `add eax, 48` had to become `mov ecx, 48` + `add eax, ecx`,
   in three places.
4. **`ja`/`jae`/`jbe`/`js`/`jg` do not exist.** Three comparisons had to be inverted by hand; a
   compiler emitting comparisons will want them, and a *compiler* inverting them is fine only while
   the relation is discoverable syntactically.
5. **rel8 is 127 bytes.** Every loop in a 500-line program needs `.l`, and the assembler refuses
   rather than wrapping — which is the right failure, hit five times while writing `cc.s`.
6. **No disp32.** `lea rax, [rbp-40000]` cannot be written; the buffer bases are computed as
   `lea rax, [rbp+1]` then `sub rax, rdx`. A compiler with a frame larger than 127 bytes hits this on
   its first non-trivial function. This is the largest single gap on the assembler side.
7. **Label names are ≤ 7 characters.** `f_mainlab` and `f_return` were rejected at assembly time;
   the compiler now uses `f_hdr` and `f_ret`. A code generator must shorten symbol names, which means
   it needs its own symbol table from day one.
8. **A string on a `db` line ends that line.** `db ":", 10, "db "` silently drops everything after
   the first string. The compiler emits one `db` per item.

And two defects in my own `cc.s`, both the same shape as ones already in the log:

- **`[rbp+8]` (input size) was never initialised.** It only mattered when the input was ≥ 120 bytes,
  because that is when the read loop reads it — so `cc` compiled every small test and refused
  `helloworld.c`. Found by finding the size boundary, not by reading.
- **`mov esi, eax` truncated a 64-bit pointer.** The output buffer is at `rbp-30000`, a stack address;
  `mov esi, eax` kept the low 32 bits and the `write` syscall silently returned `-EFAULT`, so the
  compiler produced no output and exited 0. A compiler must know which of its values are pointers —
  that is a type, and it does not have one.

## The gates for what comes next, in order

Each of these is a *thing a program needs*, and each has a gate that can fail:

| next | what it unblocks | gate |
|---|---|---|
| **`.data`** (second `R+W` `PT_LOAD`, opt-in) | a mutable global, a string built at runtime, a heap | a compiled program that increments a counter in `.data` and prints it; the 18 fixtures stay byte-identical |
| **disp32** in `[base+disp32]` and `lea` | frames and structs over 127 bytes | a compiled function with 200 bytes of locals |
| **`cmp`/`test`/`mov` with `[mem]` operands** | any expression with memory | capability pairs, hand-computed |
| **a calling convention** — args in registers or on the stack, return in `rax`, callee-save rules | `write(...)` becoming a real call; functions at all | a fixture that calls a function with arguments, checks the return value, and would print garbage if the register assignment were wrong |
| **locals, and a frame pointer discipline** | `int x = 5;` | a fixture with two nested calls and a local that survives both |
| **`if`/`while`** | anything interesting | a compiled `while` loop that counts to 10 and prints as `count10` does — the existing fixture becomes the oracle for the *compiler*, not just the assembler |
| **signed condition codes `ja/jae/js/jg/jo`** | `<`, `>`, `<=`, `>=` on signed integers | handwritten golden text + a program that takes the right branch on negatives |

The first two are assembler work and are already on `docs/ROADMAP.md`'s compiler list. The third is a
handful of handlers. The fourth is the point at which the C subset stops being a toy: a calling
convention is a *design*, and its gate has to be a program whose output would be wrong if the
registers were assigned differently.

## What this stage is not

- **Not a C compiler.** One function, no expressions, no variables, no control flow, no types.
- **Not self-hosting.** `cc.s` is ~500 lines of dialect assembled by `asm1`; it does not compile
  itself, and it will not for a long time.
- **Not fast, not small.** It reads at most 8000 bytes and writes at most 8000, and refuses beyond
  rather than truncating.

But it *is* the whole pipeline, gated, with a program at the end that prints the right bytes — and the
list above is what the next gates have to be.
