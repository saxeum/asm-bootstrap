# Continue here

State of the project at the end of the session that took `asm1` from self-hosting to being better
than its own bootstrap. Written so a new session can start without re-deriving anything.

## The numbers

| | bytes | sha256 (16) | notes |
|---|---|---|---|
| `asm0a` | 3 745 | `6271c5ee79034ffd` | hand-written machine code, **frozen**, not a correctness reference |
| `asm1` | 6 820 | `2b4aada60da42df8` | built by `seed/asm1` from `src/asm1.s` |
| `seed/asm1` | 6 820 | `2b4aada60da42df8` | the promoted stage; identical to `asm1` until the next edit |
| `src/asm1.s` | 24 177 | — | 1 847 lines, 189 labels (limit 256) |

88 commits · tags `milestone-fixpoint`, `milestone-handover` · 18 fixtures · 11 reject sources ·
28 capability pairs · 3 superiority cases · 5 exact messages.

## Verify before touching anything

```
make clean && make && make check
```

`make check` must print, in order: fixpoint holds · bootstrap NOT APPLICABLE · 11/11 rejections ·
5/5 exact messages · 28/28 capability pairs · 3/3 superior · 34 provenance records · SHAS match ·
`asm1.sha` match · and then the **SUSPENDED** branch line. If any line is missing or red, stop and
fix that first.

Two traps that have each cost a session:

- **`make` before `./asm1`.** A failed build leaves the old binary in place, and the next test then
  reports green about a stale subject. Check the build's exit code *and* that `asm1`'s sha changed.
  (`make fixpoint` and `make test` depend on `asm1`, so they rebuild; a bare `./asm1` does not.)
- **After any change to `src/asm1.s`:** `make promote` and `make record`, or `make check` fails on
  `docs/asm1.sha` and the provenance ledger. That failure is correct — it caught this omission once.

## The open debt: there is no disassembler of our own

`tools/check-branches.sh` used to decode `asm0a` with `objdump`. **`objdump` is forbidden** — a
disassembler is the tool this project replaces, so it cannot verify us. The script now refuses to run:

```
branch pins: SUSPENDED -- the decoder must be written in the dialect (src/dis.s)
             docs/branches.tsv holds 290 recorded sites, currently unverified
```

`docs/branches.tsv` (290 sites) is hand-recorded evidence and is **currently unverified**. The
instruction-mix table in `docs/ROADMAP.md` was also produced with `objdump` and is **provisional**.
No claim in this repo may call either verified until `src/dis.s` exists. See `AGENTS.md`.

## The next task: `src/dis.s`

A decoder written in the dialect, assembled by `asm1`. Scope is exactly what the branch gate needs —
not a general x86 decoder:

```
in : a binary, a byte offset
out: mnemonic and target for
       EB        jmp rel8          E9        jmp rel32       E8  call rel32
       70-7F     jcc rel8          0F 80-8F  jcc rel32
     target = site + length + displacement
     printed as hex, in the same `0xSITE 0xTARGET  mnemonic` shape as docs/branches.tsv
```

Needed: `je jne jz jnz jb ja jae js jg jo jmp call`. Hex output is expressible now — `shr` and `and`
both exist, which they did not when the gate was written.

Two decisions to make first:

1. **How does it read a file?** `asm1` reads stdin and writes stdout, so either the gate pipes the
   binary in (`tools/dis < asm0a`) or `asm1` learns `argv` — `[rsp]` at entry is `argc`, which is
   worth doing anyway.
2. **Where does it live?** `src/dis.s` (a program in the dialect) rather than `tools/`, because it is
   built by `asm1` and belongs in the fixture/regression corpus like anything else.

Gate when it works: `make check` prints a real branch line again, `tools/check-branches.sh --selftest`
rejects known-bad sites, and the 290 recorded pins validate. Then re-derive the `asm0a` instruction
mix with our own decoder and replace the provisional table.

## How to edit `src/asm1.s` (this is not optional)

**Whole-block replacement, anchored on a label and the next label.** Five positional edits were
attempted this session and all five failed: deleted live lines, duplicated labels (three times),
handlers inserted inside a neighbour's body (four times), a stray label before a branch, and an
insertion inside `chklim`'s flag-dependent sequence that turned a range check into a no-op. Tests
caught every one, none was caught by reading.

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
  duplicate silently hides dead code.
- every four-byte frame slot within `disp8` is in use: slots are `[rbp+8]`…`[rbp+124]` plus `[rbp+2]`
  (reason byte), `[rbp+4]`, `[rbp+12]` (expression scratch). Negative displacements work now, so
  `[rbp-64]`…`[rbp-128]` are free if a slot is needed (below the call frames, above nothing).
- no `add r32,imm32` (`add eax,100` is rejected) — use two `add`s or a register; `add r64,imm8` is
  **not implemented**; `cmp r8,imm8` is signed (−128..127).
- 64-bit operands in a reg-reg form whose opcode carries no REX are **refused**, not mis-assembled:
  `mov rax,rbx` → `line 1: rejected`. `sub rsi,rcx` works (its opcode sets REX.W).
- `emital` destroys `rcx`, `rax`, `rdx`, `rsi`, `rdi`: anything needed after it lives in memory or in
  `rbx`/`rbp`.
- buffers go **below** `rsp`; above `rsp` the mapping ends within a few KB.
- three passes: 0 counts, 1 validates (resolves labels, range-checks, no output), 2 emits. Anything
  that must fail with no output is checked in pass 1.

## Deferred, in the order the measurement supports

`docs/ROADMAP.md` has the reasoning; the short version:

1. `src/dis.s` (above) — unblocks the gate and the measurements.
2. **REX.W for reg-reg ALU + `r8`–`r15`**: one mechanism (REX byte from codes ≥ 8 and the 64-bit
   flag, `and` to mask codes). Turns today's refusals into support and gives 16 registers.
3. **The forms `asm0a` itself needs** to be rebuilt from source: `add r64,imm8` (60 uses),
   `cmp r8/r32,[mem]` (10), `imul r32,r32,imm8` (8), and the missing condition codes
   `ja/jae/js/jg/jo` (~30). Counts are provisional — from `objdump`.
4. **`src/asm0a.s`** — then `asm1 < src/asm0a.s | cmp - asm0a`. Two mechanisms away, and the
   strongest statement the project can make.
5. `.data` sections (must be opt-in or every fixture changes), scale factors, self-testing generator.

## Where things are

| | |
|---|---|
| `AGENTS.md` | invariants with their checks, the defect table, the objdump suspension |
| `docs/ROADMAP.md` | phases, what is done, what is deferred, and why in that order |
| `docs/WAVES.md` | the log, failures included |
| `docs/encodings.md` | chosen encodings and the known `[rbp]` disp-0 defect |
| `docs/oracles.md` | what `ref/` does and does not prove |
| `seed/README.md` | the bootstrap chain |
| `docs/toolchain.tsv`, `docs/provenance.tsv`, `docs/SHAS`, `docs/branches.tsv` | the records |
