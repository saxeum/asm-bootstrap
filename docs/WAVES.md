# Bootstrap log

| Wave | Artifact | Size | sha256 | Oracle / status |
|---|---|---|---|---|
| 0 | `hello` | 165 | `4f386903…6552e1` | hand-emitted; prints. **FROZEN — oracle for 1b** |
| 0 | `count10` | 188 | `e61a23c9…94ec5bd9a` | hand-emitted; prints 1..10. oracle for wave 2 |
| 0 | `fib` | 334 | `f61cea2c…2e10098` | hand-emitted; fib(0..93) == OEIS. oracle for wave 3 |
| 1a | `asm0a` | 664 | `255ac2e1…cf3aa5e60` | assembles `src/exit42.s`, output byte-identical to hand-written, exits 42. **PASS — hand-emitted** |
| 1b | `asm0a` + xor/db | — | — | target: `hello.s` numeric form → `4f386903…` |
| 1c | `asm0a` + labels | — | — | target: `src/hello.s` → `4f386903…` |
| 2 | `asm1` | — | — | target: `count10.s` → `e61a23c9…`; jumps + labels |
| 3 | `asm2` | — | — | target: fixpoint — `asm2.s` by `asm2` == `asm2`; `fib` reproduced |

Rule: a wave is PASS only when the stronger oracle agrees byte-for-byte. Exit status is never
evidence. Never overwrite the previous wave.

## Incident, 15:36 — wave-0 artifacts missing

`hello`, `count10`, `fib` and `src/hello.s` were absent from the working directory when
wave 1a passed its acceptance test. Cause not determined; no command in the session should
have removed them. They were rebuilt from the recorded `printf` emitters
(`scripts/build-*.sh`) and verified against the recorded shas — all three matched exactly,
which is the only reason this was recoverable rather than a rewrite.

Consequences adopted:
- every artifact is checked with `sha256sum -c docs/SHAS`, not by trusting the file is there;
- the emitters are part of the record, not scaffolding to be deleted once the binary exists;
- wave N is not "kept" until its sha is in `docs/SHAS` and the check passes from a clean tree.

## Wave 1b — PASS (15:5x)

`xor r32, r32` and `db "…"` (escapes `\n \t \" \\`) added by **appending** a new block and
patching one rel32, so no existing code offset moved: the dispatch's `jmp fail` was retargeted
from `fail` to a new block at code offset 0x220 that tests `x`/`d` and falls through to `fail`.
The two absolute addresses (`TABLE` 0x400200, `TPL` 0x400220) and `e_entry` 0x400078 were
untouched, which is the entire argument for append-and-retarget over relayout.

Artifact: `asm0a`, 833 bytes, sha `9192d28f…16fa7989`.

Oracles, both byte-exact:

```
$ ./asm0a < src/hello_num.s | cmp - hello  &&  echo ok     # 1b: numeric hello
ok
$ ./asm0a < src/exit42.s   | cmp - expected && echo ok     # 1a: regression
ok
$ sha256sum hello
4f386903…6552e1
```

`src/hello_num.s` is `hello` written with a numeric address (`mov esi, 4194455` =
`0x400097`) and `xor edi, edi` instead of `entry`/labels. It is the same 165 bytes.

### Why 1b before 1c

1b is additive and unlocks the strongest oracle available (`hello`'s sha) with zero
restructuring. 1c replaces the single-pass parser with two passes and a symbol table — a
structural change that is much easier to validate *after* the instruction set can express
`count10` and `fib`, i.e. after wave 2's jumps. Doing 1c first would mean rewriting the
parser twice.

### Failed attempt, reverted (recorded because it is the useful part)

Adding a bounds-checked `db` (unterminated string currently segfaults) by the same
append-and-retarget method produced a patch pile that broke a passing oracle. Three causes:

1. `add rbx, 3` is **4 bytes** with REX, not 3 — three displacement fields were computed
   against a 3-byte instruction, so the handler's internal jumps landed off by one.
2. `dd seek=376` wrote four bytes (376–379) and clobbered the `ret` at 378 and `eol`'s first
   opcode at 379; the "restore" covered only 374–377, so the file stayed broken and the sha
   did not match. Caught only by comparing against the recorded sha.
3. `head -c … > t && mv t asm0a` drops the `+x` bit (`Permission denied` on the next run).

Reverted to the recorded 1b bytes; sha matched `9192d28f…` exactly, which is what "the
restore is correct" means. The bounds fix moves to wave 2 rather than more `dd` patching:
beyond two patches the provenance of the file stops being checkable, and an unverifiable
artifact is worth less than a smaller verified one.

## Wave 2 plan (next)

Single coherent emission, no patching — a deliberate relayout that pays for itself:

- **data first**: `TABLE` at code offset 0x00, `TPL` at 0x20, entry at 0x98, so data addresses
  are fixed forever and adding instructions never changes them;
- **bounds checks** in every scan loop (`dbl`, `ml`, `sb`, `xsb`) → `jae fail`, so malformed
  input exits 1 instead of reading uninitialised stack;
- **relative jumps**: `jmp`/`jz`/`jnz`/`jb`/`ja` with rel8, falling back to rel32 when the
  displacement does not fit — this is what `count10` and `fib` need;
- acceptance: `count10.s` → `e61a23c9…`, and `hello_num.s`/`exit42.s` unchanged.

## Wave 2a — PASS: relayout (data first) + bounds checks

Rebuilt `asm0a` as one coherent emission instead of more `dd` patches. Three changes:

1. **Data first.** `TABLE` at code offset 0x00 (address 0x400078) and `TPL` at 0x20
   (0x400098), with the entry point at 0x98 (0x400110). Data addresses are now independent of
   code size, so adding instructions can never churn them again — this removes the bug class
   from wave 1a, where `TABLE`'s address kept being written as its code-relative offset.
2. **Bounds checks in every scan loop**: `sb` (skip blanks), `ml` (number), `xsb` (xor
   operands), `dbl` (db text). Each loop now begins `cmp rbx, r13 / jae fail`, so the source
   end is a hard boundary instead of whatever is next on the stack.
3. **`eol` test-first**, replacing the wave-1b hack of jumping to `eol+3` from handlers that
   already sat on the newline. Callers now enter `eol` directly; it tests, then advances.

Artifact: `asm0a`, 883 bytes, sha `5f1ba8cfadc9b65a7591ec1baa4f17f186496f9503fbbecd977d786b71299fa7`, entry 0x400110, filesz 0x373.

```
$ ./asm0a < src/exit42.s   | cmp - expected && echo ok   # wave 1a oracle
ok
$ ./asm0a < src/hello_num.s | cmp - hello    && echo ok   # wave 1b oracle
ok
$ printf 'db "unterminated\n' | ./asm0a >/dev/null ; echo $?
1                                                         # was SIGSEGV (139) in 1b
$ printf 'db "a\tb\"c\\d\n"\n' | ./asm0a | xxd -s 120
00000078: 6109 6222 635c 640a                             # escapes intact
```

Both earlier oracles still reproduce byte-for-byte, which is the point of doing the relayout
as its own phase: it changed where everything lives while changing nothing it produces.

Remaining limitation, unchanged: `mov eax,` with no operand assembles as `mov eax, 0` and
exits 0. Number parsing needs an "at least one digit" flag, which arrives with wave 2b's
operand handling.

## Layout change: frozen oracles moved to ref/

`hello`, `count10`, `fib` moved from the repository root to `ref/`, with `ref/README.md`
stating the rule that matters: they were written by hand, so they may not be regenerated
casually — a binary whose bytes you did not write cannot judge an assembler. `docs/SHAS`
paths updated and re-checked.

Commands quoted *above* this note were run when the files were at the root; they are left
verbatim because the log is a record of what was executed, not a tutorial to be retconned.
From here on the oracles are `ref/hello`, `ref/count10`, `ref/fib`.

## Plan correction before wave 2b

The original plan said "wave 2: relative jumps, so `count10` is reachable". That was
optimistic by about twelve instruction forms. `count10` needs, beyond jumps: `mov r8,imm8`,
`movzx r32,r8`, `div r8`, `add r8,imm8`, `mov [rsp+d8],r8`, `mov byte [rsp+d8],imm8`, `lea`
(two addressing forms), `sub r64,r64`, `inc r8`, `cmp r8,imm8`. Jumps get you none of that.

So wave 2 splits:

| Wave | Adds | Oracle |
|---|---|---|
| **2b** | labels, `entry`, two passes, `jmp label` (forward and backward) | `src/jmp.s` → `ref/jmp`, sha `f1efca3a…` |
| **2c** | conditional jumps (`jz jnz jb ja`), `inc`/`dec` r32, `cmp r32,imm8` | a loop fixture: count down, exit with the counter |
| **2d** | the eleven forms above, i.e. everything `count10` uses | `src/count10.s` → `ref/count10`, sha `e61a23c9…` |
| **3** | everything `fib` uses, then the fixpoint | `src/fib.s` → `ref/fib`, then `asmN.s` by `asmN` equals `asmN` |

Why 2b first and why it is small: a **forward** jump is the smallest feature that cannot be
done in one pass, so it forces the architecture (labels recorded in pass 1, resolved in pass
2) without dragging in arithmetic. `ref/jmp` is hand-emitted and exits 7; if the jump were
dropped, control would fall into `mov edi, 99` and the status would be 99 — an oracle that
distinguishes "jump emitted" from "jump ignored", which a passing exit status alone would not.

### 2b design (decided, not yet implemented)

- **Two passes by re-parse, not two code paths.** Pass 1 parses exactly as today — handlers
  write their bytes into the body buffer, and that is fine: its output is garbage that pass 2
  overwrites. What pass 1 additionally does is record `label -> (r15 - r14)` as each label
  definition goes by. At end of source, reset `r15` to `r14`, rewind `rbx` to `r12`, flip a
  pass flag and re-parse. No handler needs a "counting" mode, which is what makes this
  cheap.
- **Label table**: 32 entries of 12 bytes (8-byte zero-padded name, 4-byte offset) at
  `rsp+0x1F800` — inside the existing 128 KiB scratch allocation, above the 120-byte header
  buffer at `rsp+0x1F000`. Lookup is an 8-byte compare, so label names are limited to 7
  characters plus terminator (enough for `_start`, `msg`, `loop`, `done`).
- **Label detection** at line start: after skipping spaces, scan while the character is not
  space, newline or `:`; if it is `:`, it is a definition, else rewind and dispatch as now.
  Needed because `skip:` and `syscall` both start with `s`.
- **`jmp name`** → `EB rel8` with `rel8 = target_off - (here_off + 2)`, failing if it does not
  fit. Backward and forward both work because pass 1 already filled the table.
- **Registers**: `r8d` label count, `r9d` pass flag.

## Wave 2b-1 — PASS: labels, label table, two passes. No jumps.

Split from 2b because the single 441-byte block produced six displacement/REX defects
(`docs/handover.md`). 2b-1 adds only the symbol table and the pass flip, so the only new
failure mode is the table itself.

Layout (segment offsets; code starts at 0x98, data first):

- **labscan 0x2FB** — the new loop top. Detection has to come before dispatch because `skip:`
  and `syscall` both begin with `s`: scan from `rbx` for `:` before space or newline; a colon
  means a definition, otherwise jump to the existing dispatch at 0xD3.
- **islabel 0x339** — length 1..7, then record `(offset, name8)` into a 32-entry table at
  `rsp+0x1F800` (4-byte offset, then 8 zero-padded name bytes). **In pass 2 it skips the
  record** (`r9d` is the pass flag), so entries are not duplicated and the 32-entry limit is
  a real limit rather than half of one.
- **eos 0x3B2** — end of source. First time: `r15 = r14`, `rbx = r12`, `r9d = 1`, re-parse.
  Second time: `done`.
- Retargeted: loop top → `jmp labscan`; `adv` and `eol4` → `jmp labscan`; `eol3`'s
  end-of-source → `jae eos`.

Artifact: `asm0a`, 1092 bytes, sha `1b54ea9a098588600b055ced0b102f8cb835af2cea99f56d028196e7447f218a`, entry `0x400110`, filesz `0x444`.

Gate, all verified:

```
exit42                        byte-identical
hello_num                     byte-identical
labels emit no bytes          "mov eax,60 / syscall" == "start: mov eax,60 / between: syscall / end:"
7-char label                  accepted
8-char label                  exit 1
empty label                   exit 1
32 labels                     accepted
33 labels                     exit 1
jmp                           still exit 1 (2b-2, not implemented — correctly not claimed)
```

### Process result worth recording

For the first time in this project **all 15 branch targets were correct on first emission**,
because each one was decoded with objdump and compared against the intended label offset
*before* anything was run:

```
  ok   0x376 -> 0x42a    ok   0x3be -> 0x2b3    ok   0x425 -> 0x14b
  ok   0x385 -> 0x425    ok   0x3c7 -> 0x2b3    ok   0x42d -> 0x257
  ok   0x391 -> 0x3b1    ok   0x3d0 -> 0x41a    ok   0x43f -> 0x373
  ...
```

15/15, against six defects in the same class in the previous attempt.

One defect did slip through, and it was a **repeat** of an earlier mistake: `mov r11,rcx`
written `4c 89 cb`, which is `mov rbx,r9` — the destination `r11` needs REX.B. Caught by
decoding the instruction, not by re-checking the arithmetic. The lesson stands: arithmetic is
verified by decoding, never by re-reading.

## Wave 2b-2 — PASS: `jmp rel8`, comments, and the range check

Artifact: `asm0a`, 1371 bytes, sha `4ddab4e1bcd0e886cda1332fbb93bcf5142b994ba672d519ac8a86c23edc5a93`, entry `0x400110`, filesz `0x55b`.

Blocks appended from segment 0x3CC: `disp2` (dispatch tail: `j` → `do_jmp`, `;` →
`do_comment`, else `fail`), `do_jmp` (name into a scratch at `rsp+0x1F7F0`, then an 8-byte
compare walk of the symbol table), `found` (compute `rel = target - (here + 2)`, range-check,
emit `EB rel`), `notfound`, `do_comment`. The dispatch's `jmp fail` was retargeted to `disp2`
— a same-size rel32 patch, the only change to existing code.

### Gate

```
src/jmp.s -> 139 bytes, byte-identical to ref/jmp        PASS
the produced binary exits 7, not 99                      PASS
exit42, hello_num                                        byte-identical (regressions)
jump of +120 bytes (24 instructions)  -> eb 78           accepted, exactly at the limit
jump of +132 bytes (26 instructions)  -> exit 1          refused by the range check
undefined label                       -> exit 1
backward jump top:...jmp top          -> b8 3c 00 00 00 eb f9   correct negative rel8
```

### The pass-1 / pass-2 asymmetry, which is the subtle part

A forward `jmp` cannot be resolved in pass 1, because the label has not been seen yet. So
`notfound` does not fail unconditionally: it tests `r9d` (the pass flag) and, in pass 1, emits
a `EB 00` placeholder and advances `r15` by 2 — the correct width, so pass-1 offsets match
pass-2 offsets — then continues. In pass 2, an unresolved label is a hard error. Without this,
assembling any program with a forward jump died in pass 1, which is exactly what the first
attempt did.

### Verification

All 21 branch targets in the new blocks were decoded with `objdump` and compared against the
intended label offsets before running anything: 21/21. Combined with 2b-1's 15/15, that is 36
consecutive hand-laid branches verified correct at emission, against six defects in the earlier
single-block attempt. The decode-before-test step is now the standard, not an improvisation.

## Wave 2c — PASS: `inc`/`dec r32`, `jz`, `jnz`

Artifact: `asm0a`, 1553 bytes, sha `a75e63c9f27b189b7e801d7c7597b777eca9d1ca5fd37ba031039c985fbcc9ea`, entry `0x400110`, filesz `0x611`.

New: `jdisp` (dispatch on the *second* character of a `j…` mnemonic: `m`→jmp, `n`→jnz, `z`→jz),
per-mnemonic blocks that load the opcode into `r11b` and skip the right number of characters,
`regop` (shared `inc`/`dec` emitter: `FF` plus `modrm = 0xC0 | (sel<<3) | reg`), and `ddisp`
(distinguishes `db` from `dec` — both start with `d`).

Three existing sites retargeted, plus two in-place emits changed:

| site | change |
|---|---|
| main dispatch `je do_db` | → `ddisp` |
| `disp2` `je do_jmp` | → `jdisp` |
| `disp2` `jmp fail` | → `disp3` (handles `i` → `inc`) |
| `found` and `notfound` | `41 C6 07 EB` (emit `0xEB`) → `45 88 1F 90` (emit `r11b`, nop) |

Making the old `do_jmp` path emit `r11b` is what lets one handler serve `jmp`, `jz` and `jnz`
without duplicating the name parse, the table walk or the range check.

### Gate

Two hand-emitted references, both behaviourally discriminating:

```
snapshot  asm0a exit  byte-identical  behaviour
loop      0           yes             exit 10   (iteration count; 0 would mean the loop never ran)
jz        0           yes             exit 5    (99 would mean the conditional was ignored)
exit42, hello_num, jmp — all byte-identical (regressions)
```

`ref/loop` and `ref/jz` were themselves run before use: 140 and 146 bytes, exiting 10 and 5.
The first attempt to build them emitted 161 and 167 bytes and segfaulted — my helper
double-emitted the ELF header. Caught because the references are executed, not just hashed.

### Defects found this wave, both by decoding

1. **`do_dec`'s `jmp regop` had rel `+5`** where `regop` immediately follows (rel must be 0).
2. **Two dispatch patches written one byte early**: `0F 84 rel32` has a *two-byte* opcode, so
   the displacement starts at opcode+2. Writing at opcode+1 clobbered the `84`, turning
   `je ddisp` into `(bad)` — visible immediately because the decoded target was nonsense.

Both were caught by the decode-and-compare step, not by re-reading arithmetic. That step is
now applied to *patches* as well as new blocks: three patched sites plus 21 new branches were
verified against intended targets before any test ran.

## Wave 2d-1 — PASS: the 8-bit register class, `mov r8,imm8`, `movzx r32,r8`

Wave 2d is split into four because it is the last and largest: eleven forms stand between here
and `count10`. 2d-1 installs the machinery the rest of 2d needs — a **register class** — and
proves it with the two forms that use it.

Artifact: `asm0a`, 1841 bytes, sha `dfd580678c20e17e40d9fc5cb84721a2bc9a6eff3044ca2e959060273279493d`, entry `0x400110`, filesz `0x731`.

New blocks: `mdisp` (disambiguates `mov`/`movzx`/`mov r8` by looking at character 3 and 6),
`do_mov8`, `do_movzx`, `lookup8` (an 8-entry table `al cl dl bl ah ch dh bh`, compared with a
**16-bit** `cmp ax,[rcx]` because 8-bit names are 2 characters), and the `R8TAB` data.

`lookup8` leaves `rbx` past the name and past a following comma *if there is one* — the
conditional skip is load-bearing: a fixed skip of 3 stepped over the newline for
`movzx edi, bl` (last operand on the line), and `eol3` then ate the following instruction.

### Gate

```
snapshot  asm0a exit  byte-identical  behaviour
r8        0           yes             exit 7
exit42, hello_num, jmp, loop, jz — all byte-identical (regressions)
```

### Defects found this sub-wave

1. **`66 3B 01` is 3 bytes, not 4** (16-bit `cmp`), so `lookup8` was 44 not 45 and the table,
   its address and two displacements were each one byte off.
2. **`do_mov8` never advanced past the register name**, so the number parser started at `'b'`
   and every immediate came out 0 — `mov bl, 7` assembled to `b3 00`. Caught by byte comparison
   against the reference, not by reading the code.
3. **Address computed from a *file* offset as if it were a segment offset**: `0x400078 + 0x711`
   instead of `0x400000 + 0x711`. The table pointer was 0x78 too high and every lookup missed.
4. **The `0F 84` patch at opcode+1 again** (rel32 is at opcode+2), which clobbered the `84` and
   made `asm0a` itself `SIGILL` on every input — including five previously-passing ones. That
   loud, total failure is the only reason it took seconds to find; the same mistake inside a
   rarely-taken branch would have been invisible.

## Wave 2d-2 — PASS: `inc r8`, `dec r8`

Artifact: `asm0a`, 1915 bytes, sha `7be1fa0675d0282cd13c8506bd5dc678855ab543fe8faa6b8cc117ea100f1778`, entry `0x400110`, filesz `0x77b`.

`regsel` decides between the 32-bit path (`regop`, `FF /x`) and the 8-bit path (`regop8`,
`FE /x`) by looking at character 2 of the register name; `regop8` reuses the `sel` in `r11d`
that `do_inc`/`do_dec` already set, so the modrm construction is identical to the 32-bit case.
Two retargets: `do_inc` and `do_dec` now jump to `regsel` instead of straight to `regop`.

### Gate

```
snapshot  asm0a exit  byte-identical  behaviour
inc8      0           yes             exit 3
exit42, hello_num, jmp, loop, jz, r8 — all byte-identical
```

`src/inc8.s` counts in `cl` while a separate register counts down: `inc cl` / `dec bl` / `jnz top`
/ `movzx edi, cl` / `syscall`, so it exercises `inc r8`, `dec r8`, the existing `jnz`, and
`movzx` in one program, and exits 3.

### Defects

1. **`[rbx+2]` was tested for `,` and space only.** With one operand the terminator is a
   newline, so `inc cl` fell through to the 32-bit path, the table lookup missed `cl`, and the
   whole assembly failed. Fixed additively: `regsel`'s fall-through was retargeted to
   `regsel2`, which adds the newline case — no bytes shifted.
2. **Both displacements in that new block were 2 bytes off**, computed from a wrong base, so
   `je` landed mid-instruction (`SIGILL`). Caught by decoding at the instruction address rather
   than at the rel32 byte — the checker had been given the wrong start addresses as well, which
   is its own reminder that a verifier needs verifying.

The pattern across 2d-1 and 2d-2 is consistent: every defect was found by decode-and-compare or
by byte-identical comparison, and none by re-reading the hex.

## Wave 2d-3 — PASS: `cmp r8,imm8`, `jb`, `add r8,imm8`

Artifact: `asm0a`, 2155 bytes, sha `764cfff2b4c455575423d236fa6934371e522b4744d9b3aceccd8864aa7291d3`, entry `0x400110`, filesz `0x86b`.

New: `num8`, the first *shared* operand parser — skip blanks, accumulate decimal, then
**range-check into −128..127** and `fail` outside it. That check is the point: `80 /7` takes a
sign-extended byte (`I bs` per `docs/encodings.md`), so `cmp bl, 200` must be refused rather
than truncated into `cmp bl, -56`. Verified: `cmp bl, 200` → exit 1, `add al, 200` → exit 1.
`do_cmp` emits `80 /7`, `do_add` emits `80 /0` — except for `al`, which uses the short `04 ib`
form, because `ref/count10` contains `add al,'0'` as `04 30` and byte-identity is the standard.
`jb` is one more entry in the existing `jdisp` chain (`72`, rel8, same handler as `jz`/`jnz`).

### Gate

```
snapshot  asm0a exit  byte-identical  behaviour
cmp8      0           yes             exit 12
exit42 42 | hello_num prints | jmp 7 | loop 10 | jz 5 | r8 7 | inc8 3 — all identical
```

### The interesting failure: the reference was wrong

`ref/cmp8` as I first hand-emitted it was **not** what the assembler produces: I wrote
`jmp top` as `E9` with a rel32 (5 bytes) when this dialect's rule is `EB` rel8 (2 bytes). The
assembler emitted the short form, 26 bytes of body against my 29, and the byte comparison failed.

The behavioural check did *not* catch it — both forms compute the same thing and both exited
the same value. Worse, my predicted value was also wrong: I said the loop runs 3 times and exits
9; it runs 4 times and exits 12. The assembler was right on both counts.

Two lessons worth keeping:

1. **A hand-emitted reference is only an oracle after it has been compared, not just executed.**
   Both binaries ran correctly; only the byte comparison revealed they disagreed.
2. **When assembler and reference disagree, neither is presumed right.** Here the reference was
   wrong. Had I "fixed" the assembler to match it, I would have introduced a second, longer
   encoding for `jmp` that the dialect's own rule forbids — the exact class of silent
   divergence `docs/handover.md` condition 3 exists to prevent.
