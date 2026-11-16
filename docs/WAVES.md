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
