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
