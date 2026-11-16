# asm-bootstrap

An assembler built from nothing, and a C compiler on top of it. `asm0a` is 3 745 bytes of
hand-written machine code that assembles source into Linux ELF executables; it built a better
assembler, which assembles itself. `cc` is a compiler written *in that dialect* whose output is
that dialect, so the pipeline is `cc` → text → `asm1` → an executable.

**No compiler, no system assembler, no disassembler, no interpreter, no debugger** — in the creation
path or the diagnosis path. `make test-tools` fails if one is invoked anywhere in the `Makefile` or
`tools/`; `objdump` is on that list, because a disassembler is the tool this project replaces and so
cannot be the thing that verifies it (`src/dis.s` is the decoder that replaced it).

The PDP-8 bootstrap done again deliberately: hand-assemble a minimal assembler, let it assemble a
better one, repeat. `docs/pdp8-to-gcc.md` has the history; `docs/WAVES.md` is the log, failures
included; `docs/continue-here.md` is where a session starts.

## Where this stands

| | artifact | bytes | sha256 (16) | built by |
|---|---|---|---|---|
| bootstrap | `asm0a` | 3 745 | `6271c5ee79034ffd` | hand-written, **frozen** |
| self-hosted | `asm1` | 7 731 | `ac80d9f9094d7051` | `seed/asm1` from `src/asm1.s` |
| seed | `seed/asm1` | 7 731 | `ac80d9f9094d7051` | the promoted previous stage |
| decoder | `dis` | 1 343 | `2d2eb451d7c7a9a9` | `asm1` from `src/dis.s` |
| compiler | `cc` | 9 126 | `fe09a9d2938d0b21` | `asm1` from `src/cc.s` |

Past the bootstrap. `asm1` is self-hosting, reaches its fixpoint, and is demonstrably better than
what built it — 6 byte-level cases where `asm0a` answers wrongly and 30 syntax pairs it cannot parse.
`asm0a` can no longer build the source at all (more than 128 labels), which is the handover, and
`make bootstrap-check` says **NOT APPLICABLE** out loud rather than passing quietly.

The compiler is real and small: `int x = 3`, `while`, `if`/`else`, thirty-two variables, expressions
with precedence, function calls with a calling convention, recursion, and pointers (`&x`, `*p`, `*p = v`),
int and char arrays, a buffer that can cross a call, `read()` and `write()`, over a 64-bit value model.
It emits text, not bytes, and every gate the assembler has applies to that text.

What is next is in `docs/ROADMAP.md`. One assembler feature stands between this and a compiler that
could compile itself: **`.data`**, so that string literals live in memory and a program can address its
own text. A call inside a larger expression used to be the other blocker; it works now, and the cause
of the corruption that hid it was a missing `sub rsp` in `cc`'s own prologue.

## Use it

`asm1` (and `asm0a`) read source on **stdin** and write the executable on **stdout**. They take no
arguments, so the shell supplies the filenames:

```bash
make
```

builds `asm1` with `seed/asm1`, the decoder with `asm1`, and the compiler with `asm1`, then checks
the fixpoint. From there:

```bash
./asm1 < src/count10.s > count10 && chmod +x count10 && ./count10
```

prints `1`…`10`. `chmod` is required because a pipe cannot carry a mode bit. To prove the output is
the *verified* object rather than merely something that runs:

```bash
./asm1 < src/count10.s | cmp - ref/count10 && echo identical
```

`ref/count10` was written by hand, before any assembler here could read its source — an oracle
cannot be produced by the thing it judges.

The whole pipeline is one command:

```bash
make hello
```

## The C compiler: `cc`

`cc` compiles a subset of C to this dialect's **text**. Not bytes: its output is a file you can read
and diff, it is compared byte for byte against a hand-written golden, and `asm1` stays the only thing
that produces an executable, so every assembler gate applies to the compiler's output too. The text
begins with a `;` comment saying what it is — a comment to the assembler, a shell syntax error to
anything that tries to run it directly.

| stage | what it added | gate |
|---|---|---|
| 1 | `int x = N`, `x = x ± N`, `while (x)` | `twowrites` golden; `loop` compared by output with `tests/oracle/dots.s` |
| 2 | `== != < > <= >=`, `if`/`else` — no new instruction, `jb`/`jz`/`jnz` plus an operand swap | same output as `tests/oracle/branch.s` |
| 3 | a symbol table: variables and names | `twovars` golden and oracle |
| 4 | expressions with precedence, one register per depth | `(2 + 3*4) - 10 + 14` exits 18 |
| 5 | a calling convention: args in `rdi`/`rsi`/`rdx`/`rcx`, return in `eax` | `add(2,3)` exits 5, `sub2(3,2)` exits 1 |
| 6 | `return` anywhere, arguments as `+`/`-` terms, recursion | `f(10,0)` with an accumulator exits 10 |
| 7 | 64-bit values, then `&x`, `*p`, `*p = v` — addresses, with no type system yet | `*p = 33` after `int y = *p` exits 40; a callee writing through `&x` exits 42 |
| 8 | `int a[N];`, `a[i]`, `a[i] = v` — the index may be any expression | `a[0] + a[i]` with `i=2` exits 42; `f(a[i])` exits 42 |
| 9 | a call inside a larger expression — the live registers are pushed around it | `fact(5)` exits 120; `sum(4)` exits 10 |
| 10 | `char a[N];` — one byte per element, no stride | `a[0]=65, a[i]=66` exits 131; `char a[9]` beside an `int` exits 72 |

The subset, exactly: `int` declarations, assignment, `while`, `if`/`else`, `return`, six comparisons,
`+ - *` with precedence, `&`/`*` on a name, function definitions with up to four arguments, calls, and
recursion. Values are 64-bit; an `int` may hold an address and the compiler neither knows nor checks
which.

Boundaries are refusals with no output, and all **31** are pinned in `make test-cc`: `int main()`
without `void`, `void main`, an undeclared name (three spellings), a duplicate declaration, a ninth
variable, a name of eight characters, an assignment inside a condition, `else if`, `x <= 255`,
division, an unterminated string, an unterminated comment, `return 300`, five arguments, a call inside
an argument list, `&5`, `*q` with `q` undeclared, `&nope`, `a = 1` and `int y = a;` where `a` is an
array, a subscript of a non-array, a nested subscript, an array of nine, a duplicate array name, ten
`write` calls in one function, a `char` scalar, `char a[4]; a = 1;`.
`docs/cc.md` gives the reason for each — most are consequences of a choice, not of an omission.

Three kinds of check, because each sees something the others cannot:

- **text goldens** — 14 C sources whose emitted dialect is pinned byte for byte. A regression pin,
  not an oracle: it cannot tell a plausible mistake from a correct answer, which is what the next two
  are for.
- **behaviour** — each one is assembled and run; the exact exit code or stdout is asserted. This is
  the machine judging the code generator.
- **oracles** — three hand-written dialect programs that do the same job, compared by *output*
  ("two sources, one behaviour"). The only gate that catches plausible-but-wrong codegen.

### The defect that was explained

`cc` used to refuse a nested `expr`, because nesting it corrupted the symbol-name buffer and the
writer of those bytes could not be found. The writer is now known: **`cc` never reserved stack.** Its
prologue was `lea rbp, [rsp]` and nothing else, so every `call` pushed a return address into the slots
where `cc` keeps its state — and `[rbp-208]`, the "inside an argument list" flag, is exactly the
`1` that appeared where a name should have been. `mov ecx, 320; sub rsp, rcx` fixed it, and with that
in place the parse that had corrupted the buffer produces byte-identical output.

So the guard is gone, and so is `argexpr`, the smaller parser written to avoid nesting: an argument is
now a whole expression, which is why `f(x * 2)` works (`docs/cc.md`, `docs/WAVES.md`).

What is still refused is narrower still: a call inside an *argument list* (`f(g(1))`), because it
would overwrite the argument registers — a different resource from the depth registers, and the one
place where the fix is not a push.

## What stands between here and a self-compiling `cc`

Nothing about calls. `cc` has functions, locals, recursion, arrays with computed indices, pointers and
a 64-bit value model. What it does not have is what a *compiler* needs to hold a symbol table:

- **`char` and byte strings** — a name is bytes, and today a string exists only as a `write` literal.
- **`.data`** — a mutable global table, and the last assembler feature with no user at all.
- **`/`** — refused because the dialect has no `div r32` (`div bl` exists). An *assembler* gap.
- **names longer than seven characters** — the limit is `asm1`'s, and `cc` refuses them everywhere,
  its own source included. Raising it is a bootstrap step in `asm1`, not a compiler change.

That last one is the awkward one, and the reason the ordering matters: "identifier" is longer than
seven characters.

## The goal

```bash
src/asm1.c  →  cc  →  asm1  →  asm2
```

Rewrite the assembler's source in C, compile it with the compiler this project grew, and require the
result to be **byte-identical to `asm1` on the whole corpus** — every fixture, every capability pair,
every rejection, the 99 KB source, and `src/asm1.s` itself. Only then is `asm2` accepted.

What that buys, and why the corpus is the criterion rather than "it runs": an assembler that produces
the same bytes on 18 hand-emitted references, 30 syntax pairs, 290 pinned branches and a fixpoint is
the same program in every way this repository can measure. The standing counterexample is `asm0a`,
which assembled `and eax, ecx` as `add` and agreed with itself perfectly while doing it; agreement
between implementations is evidence about *them* until neither is known to be wrong.

Why it matters at all is Thompson, 1984: a tool can carry a miscompilation that no amount of reading
its source reveals. The defence is never one check. It is a ladder of independent ones — hand-written
references, refusals, superiority cases, a fixpoint, a provenance ledger, and one decoder written in
the dialect so that no forbidden tool is in the loop. `docs/oracles.md` ranks the rungs and says what
each one does *not* prove.

`asm1`'s dialect stays frozen as the witness: it is the one thing every artifact in the chain must
reproduce, so it must not move while `asm2` is being made to match it.

Reaching the goal needs what is still missing: `.data` (mutable globals and byte arrays), pointers and
arrays, `div`, `add/sub r32,imm`, `[base+index*scale]`, and `char`. `docs/ROADMAP.md` orders them.

## Provenance: which assembler built this?

`asm0a` is frozen and only `src/asm1.s` moves, so `asm1` changes and an artifact is meaningful only
together with *which build of which assembler* produced it. "asm1" identifies nothing once asm1 has
been rebuilt, so every record is a sha256 pair.

`docs/provenance.tsv` — one line per artifact per assembler:

```
addr32  734b5a48…  asm0a  6271c5ee…       artifact sha, assembler, assembler sha
addr32  734b5a48…  asm1   ac80d9f9…
```

`docs/asm1.sha` pins the sha256 of the current `asm1`, so the build is identified as a *content* claim
rather than by name. `make record` rebuilds everything and rewrites both files, and it is the only
thing that writes them: recording is an assertion that a change is intended, and a build step that
absorbed drift silently is exactly how a stale record goes unnoticed.

`make which FILE=count10` answers the question directly, by looking the file's content sha up in the
ledger; unknown content exits non-zero rather than saying nothing.

## The bootstrap chain

`asm0a` is frozen. `src/asm1.s` is built by **`seed/asm1`** — the promoted previous stage — and never
by the binary it produces:

```
seed/asm1 < src/asm1.s > asm1        build the new stage with the previous one
asm1      < src/asm1.s > asm1b       the new stage must reproduce itself
cmp asm1 asm1b                       or the build is not trusted
```

A binary is never its own reference. If `asm1` were built by whatever `asm1` was lying around, a
miscompilation would be preserved across generations with nothing to compare against — the failure
mode the fixpoint alone cannot exclude, which is why `ref/`, written by hand before any of this
existed, is part of the gate too.

`make promote` replaces `seed/asm1` and is the only thing that does. It is a deliberate act with a
diff to read, because promoting asserts "this stage is good", and an automatic promote would make the
chain unfalsifiable. `docs/toolchain.tsv` records every promotion: the stage's sha256, its builder,
and that builder's sha256. The chain runs back to `asm0a`, the one link with no builder — recorded as
`-`, because a blank would read like an omission rather than a fact.

`make bootstrap-check` used to require that `asm0a` and `seed/asm1` — two independent
implementations — agree on `src/asm1.s`. That is now **NOT APPLICABLE**: the source grew past
`asm0a`'s 128-label limit, so `asm0a` cannot parse it. The check says so out loud and names the
reason, because a check that cannot run is not a check that passed. What holds the chain up instead,
in order of strength: `ref/`; the rejection, capability and superiority suites; the fixpoint; and the
promotion ledger, with every earlier generation recoverable by `git show <rev>:seed/asm1`.

Triage, when a build fails: the same binary is both tool and subject, so a failure could be your edit
or your seed. `make triage` asks which artefact is inconsistent with the last commit — a state that
passed every gate when it was made — instead of guessing and bisecting source.

## Milestones

Two tags mark the points where the project changed kind. Both carry the evidence in the tag message,
so `git tag -n99` reads without the repository.

| tag | commit | what it marks |
|---|---|---|
| `milestone-fixpoint` | `c2240bf` | `asm1` assembles itself: `X == X' == X''`, 4 295 bytes, one sha256 |
| `milestone-handover` | `c806e95` | `asm1` is better than `asm0a` — and `asm0a` can no longer build it |

Rebuilding them. There was no `Makefile` at the fixpoint commit, so the path is the two commands the
commit itself documents:

```bash
mkdir -p /tmp/fx && git archive milestone-fixpoint | tar -x -C /tmp/fx && cd /tmp/fx && ./asm0a < src/asm1.s > X && chmod +x X && ./X < src/asm1.s > Xp && cmp X Xp && echo identical
```

At the handover tag `asm0a` is no longer a valid builder and `make` uses `seed/asm1`:

```bash
mkdir -p /tmp/ho && git archive milestone-handover | tar -x -C /tmp/ho && cd /tmp/ho && make > /dev/null && ./asm1 < src/asm1.s | cmp - asm1 && echo identical
```

Each prints `identical`, and `milestone-fixpoint` produces 4 295 bytes with sha256 `250e02c9…` while
`milestone-handover` produces 5 094 bytes with sha256 `7a10451b…` — the values the tag messages claim.

## State

| | |
|---|---|
| bootstrap | `asm0a`, 3 745 bytes, `e_entry` = 0x400110, one R+X `PT_LOAD`, sha256 in `docs/SHAS` — frozen history, and **not** a correctness reference: it assembles `and` as `add` |
| self-hosted | `asm1`, 8 053 bytes, sha256 `f66710306234bd05…`, built by `seed/asm1` from `src/asm1.s` (2 269 lines) |
| seed | `seed/asm1`, 8 053 bytes, the promoted stage that builds the next one (sha256 in `docs/SHAS`) |
| builder | `asm1` is built by `seed/asm1`, never by itself. Since the source needs more than 128 labels, `asm0a` can no longer parse it: `make bootstrap-check` reports NOT APPLICABLE |
| fixpoint | `asm1(asm1.s) == asm1`, 8 053 bytes, one sha256, idempotent |
| fixtures | 18 in `ref/`, all byte-identical to hand-emitted references and behaviourally correct |
| rejections | 9 sources refused by both assemblers with no output, and 8 exact messages: line number *and* reason |
| capability | 36 pairs where `asm1` accepts syntax `asm0a` cannot parse; both spellings must agree byte for byte |
| coverage | 100 claimed forms, each required to appear in a test input (`make test-coverage`) — the gate that says which paths nothing has ever executed |
| superior | six cases where `asm1` is right and `asm0a` is not (`and`-as-`add`, `[rbp]` disp 0, a negative disp, 64-bit vs 32-bit width, `r8`–`r15`, disp32), each against a hand-computed body; plus a 99 KB source, a chosen `entry` point and `r8d` arithmetic, which must RUN |
| branches | 290 sites in `docs/branches.tsv`, all decoded by `src/dis.s` — a decoder written in the dialect and assembled by `asm1` |
| source language | `mov` (8/32/64-bit, register, immediate and memory), `add`, `sub`, `cmp`, `and`, `or`, `xor`, `test`, `imul`, `inc`, `dec`, `neg`, `not`, `shl`/`shr`/`sar`, `movzx`, `lea`, `div` (8-bit form: `div bl`, quotient in `al`), `push`/`pop`, `call`/`ret`, `syscall`, `jmp`/`jz`/`jnz`/`jb` with rel8 and `.l` rel32, `[base]` and `[base+index]` with disp8/disp32, `db` with strings, labels, expressions (`label+4`, `end - start`), `entry`, two-pass assembly with validation, hex/char/negative literals. Width comes from the operand names and a mixed pair is refused; registers `rax`…`r15` with `REX.R`/`X`/`B` |
| not in the language | `imul r,r,imm`, `div` needs a register of 32 or 64 bits, not 8, `[base+index*scale]`, `je`/`jne`/`ja`/`jae`/`jbe`/`js`/`jg`/`jo` as mnemonics (only `jz`/`jnz`/`jb` exist), `cmp r32,[mem]`, `mov` between two memory operands, rel8 beyond 127 bytes (use `.l`), names longer than 15 characters |
| compiler | `cc`, 9 126 bytes, built by `asm1` from `src/cc.s` (2 761 lines): C subset → dialect **text** → `asm1` → executable. 32 text goldens, 3 output oracles, 36 refusals (`make test-cc`, `docs/cc.md`) |
| `make check` | 62 lines: forbidden tools, coverage, fixpoint, bootstrap NOT APPLICABLE, 9/9 rejections, 8/8 messages, 36/36 capability, 8/8 superiority plus three behavioural, 38/38 decoder cases, the compiler's 35 checks, 36 provenance records, `docs/SHAS`, `docs/asm1.sha`, 290/290 branch pins — every line able to fail |

`ref/` holds binaries written by hand **before** the assembler could read their source. They are
never regenerated casually: a binary whose bytes you did not write cannot judge an assembler.
`docs/oracles.md` explains what those references do and do not prove, and why byte-identity with a
hand-written reference is a floor rather than a proof.

Two rules that have each caught a real defect here:

- **Exit status is never evidence.** Every test compares bytes with `cmp`. A stage can exit 0 and
  leave a stale binary in place reporting green.
- **A zero is not a clean result.** An absence check cannot tell "removed" from "never there", so
  every gate that counts something also asserts the thing it counts exists.
