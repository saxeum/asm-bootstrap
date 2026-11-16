# The encoding standard

Every opcode this assembler emits is checked against **ref.x86asm.net** — the *X86 Opcode and
Instruction Reference*, whose primary source is an XML document rather than HTML tables.

| | |
|---|---|
| URL | <http://ref.x86asm.net/x86reference.xml> |
| Site revision | 1.12, dated 2017-02-18 |
| `version` attribute in the file | 1.11 |
| Size | 503138 bytes |
| sha256 | `5a4627e36d8db0fbee0ba69ff60b1b32c66a99be76308de4d43479729a9383a9` |
| Author | Karel Lejska (MazeGen) |
| License | GPL-3.0 since 1.12; the pre-1.12 license is stated on the site as "not available anymore" |

**Not vendored.** The dataset is GPL-3.0 and this repository has no license yet, so
redistributing it here would decide licensing for the whole project. That is the owner's
call, not a build detail. It is fetched locally instead:

```bash
mkdir -p .refcache
curl -sSL http://ref.x86asm.net/x86reference.xml -o .refcache/x86reference.xml
sha256sum .refcache/x86reference.xml      # must match the sha256 above
```

`.refcache/` is in `.gitignore`. What *is* committed is this file: our own derived table of
the forms we emit, which is the thing that has to stay in sync with the assembler.

## What this standard can and cannot tell us

- **Can**: which primary opcode and which `/digit` group extension belong to a mnemonic and
  operand *shape* (the `<a>`/`<t>` codes: `Z`=opcode+reg, `E`=modrm r/m, `G`=modrm reg,
  `I`=immediate, `J`=relative), and which *modes* an opcode is valid in.
- **Cannot**: whether our ModRM/REX bits, displacement sizes and immediates are right. The
  reference constrains the operand *shape*; the bit-level encodings need execution (the machine)
  and a hand-computed dump. A system disassembler is not available for this: invariant 10 of
  `AGENTS.md` forbids it, so the decoder we may point at a byte sequence is our own
  `src/dis.s`, and only for the branch forms. See `docs/oracles.md` for what each rung proves.

## Verified table

Regenerated against the current artifact (`asm0a`, 3125 bytes). Rows are added when a form is
implemented, not when it is planned; the reference column is the primary opcode and group
extension, never inferred from entry order.

| our form | our bytes | ref primary | ext | ref syntax |
|---|---|---|---|---|
| `mov r32, imm32` | `B8+rd id` | `B8` | — | `MOV Zvqp, Ivqp` |
| `mov r8, imm8` | `B0+rb ib` | `B0` | — | `MOV Zb, Ib` |
| `mov r32, r32` | `89 /r` | `89` | — | `MOV Evqp, Gvqp` |
| `mov r32, [mem]` | `8B /r` | `8B` | — | `MOV Gvqp, Evqp` |
| `mov [mem], r32` | `89 /r` | `89` | — | `MOV Evqp, Gvqp` |
| `mov [mem], r8` | `88 /r` | `88` | — | `MOV Eb, Gb` |
| `mov byte [mem], imm8` | `C6 /0 ib` | `C6` | 0 | `MOV Eb, Ib` |
| `movzx r32, r8` | `0F B6 /r` | `B6` | — | `MOVZX Gvqp, Eb` |
| `movzx r32, byte [mem]` | `0F B6 /r` (memory rm) | `B6` | — | same primary opcode, `Eb` operand |
| `lea r32\|r64, [mem]` | `8D /r` (`48` prefix for r64) | `8D` | — | `LEA Gvqp, M` |
| `xor r32, r32` | `31 /r` | `31` | — | `XOR Evqp, Gvqp` |
| `add r8, imm8` | `80 /0 ib`, or `04 ib` for `al` | `80` | 0 | `ADD Eb, Ib` |
| `cmp r8, imm8` | `80 /7 ib` | `80` | 7 | `CMP Eb` |
| `cmp r32, imm32` | `81 /7 id` | `81` | 7 | `CMP Evqp, Iz` |
| `inc r8` / `inc r32` | `FE /0` / `FF /0` | `FE` / `FF` | 0 | `INC Eb` / `INC Evqp` |
| `dec r8` / `dec r32` | `FE /1` / `FF /1` | `FE` / `FF` | 1 | `DEC Eb` / `DEC Evqp` |
| `div r8` | `F6 /6` | `F6` | 6 | `DIV Eb` |
| `sub r64, r64` | `REX.W 29 /r` | `29` | — | `SUB Evqp, Gvqp` |
| `test` (wave 3) | — | `85` | — | not yet implemented |
| `imul r64, r/m64, imm8` (wave 3) | — | `6B` | — | not yet implemented |
| `jmp rel8` | `EB cb` | `EB` | — | `JMP Jbs` |
| `jz`/`jnz`/`jb` rel8 | `74`/`75`/`72 cb` | — | — | `JZ`/`JNZ`/`JB Jbs` |
| `jmp rel32` (`.l`) | `E9 cd` | `E9` | — | `JMP Jvds` |
| `jcc rel32` (`.l`) | `0F 8x cd` | `8x` under `0F` | — | `Jcc Jvds` |
| `syscall` | `0F 05` | `05` (0F) | — | `SYSCALL` (mode=e) |

Checked against the reference one more time when this table was rewritten:

```
81 /7 -> CMP      89 -> MOV (direction 0)      8B -> MOV (direction 1)
F6 /6 -> DIV      8D -> LEA
```

**Two rows are marked "not yet implemented" on purpose.** `test` and `imul` are needed by
`fib`, not by self-hosting, and listing them as verified when the assembler cannot emit them
would be the same lie this section exists to prevent.

## How to re-verify, without Python

`xmllint` is enough; no other language enters the repo. One form:

```bash
X=.refcache/x86reference.xml
xmllint --xpath 'string(//one-byte/pri_opcd[@value="83"]/entry[opcd_ext="7"]/syntax/mnem)' "$X"
# CMP
xmllint --xpath 'string(//one-byte/pri_opcd[@value="83"]/entry[opcd_ext="7"]/syntax/src/a)' "$X"
# E      <- operand shape: modrm r/m
```

Mode-dependent opcodes need the filter, and the trap is easy to reproduce:

```bash
xmllint --xpath 'string(//two-byte/pri_opcd[@value="05"]/entry[1]/syntax/mnem)' "$X"   # LOADALL
xmllint --xpath 'string(//two-byte/pri_opcd[@value="05"]/entry[@mode="e"]/syntax/mnem)' "$X"  # SYSCALL
```

The 29-row table above was produced with a loop of exactly this shape (container, opcode,
extension, expected mnemonic → compare), preferring `entry[@mode="e"]` whenever it exists.
Verified output of the shell version on six representative forms, including the mode trap:

```
  OK   05   -  SYSCALL  SYSCALL
  OK   83   7  CMP      CMP
  OK   B8   -  MOV      MOV
  OK   31   -  XOR      XOR
  OK   F6   6  DIV      DIV
  OK   73   -  JNB      JNB
--- without the mode filter ---
LOADALL
```

## Consequences for the plan

What this standard buys, precisely: **opcode selection** (primary opcode, group `/digit`,
alias, and the operand *shape* implied by `<a>`/`<t>`), plus **mode validity**. What it does not
buy: any of our ModRM/REX/SIB/displacement bits, the ELF container, or the parser. It is one rung
of the ladder in `docs/oracles.md`, and it does not replace the machine or a hand-computed dump.

Concretely, four changes:

1. **A new form's checklist is now six steps**, not five: (a) look up the reference entry and
   record opcode + ext + operand shape in this file, (b) implement, (c) write down the expected
   bytes yourself — a `db` dump — and compare, or for a branch form ask `./dis <site>` what the
   bytes are, (d) a behavioural fixture whose *value* changes if the form is wrong, (e) byte-compare
   against a hand-emitted reference, (f) a mutation test where it is cheap. The lookup happens
   *before* implementation, so the encoder is written against an authority rather than recalled.
   Step (c) used to say "`objdump` the bytes back"; that is forbidden now, which makes (c) human
   work or ours — never a system tool's opinion.

2. **A real implementation requirement surfaced: narrow-form selection.** Arithmetic and
   branch instructions have two widths, and the narrow one is only valid when the value fits:
   `83 /7 ib` (sign-extended byte) vs `81 /7 iz`; `6B /r ib` vs `69 /r iz`; `EB cb` (±127) vs
   `E9 cd`. Policy, chosen for simplicity: **emit the narrow form and `fail` if the value does
   not fit**, rather than silently widening. One mechanism, an explicit error, and no second
   encoding convention invented on the fly. Widening gets added when a fixture actually needs
   it — no mechanism without a present user.

3. **Wave 2b scope is unchanged**, because labels and `jmp rel8` are exactly where the range
   check is needed immediately: a forward label past +127 must fail loudly rather than wrap.
   `ref/jmp` keeps `+5` well inside range, and a new negative fixture will pin the failure.

4. **This file is a maintained artefact.** It is regenerated when a form is added and it is part
   of the wave gate, not a one-off record. A row that is documented but not implemented is a
   spec; a form that is implemented but not rowed here is a defect.

What it deliberately does **not** change: the shape of `asm0a`. The standard constrains the
*specification*, not the code structure — the handlers keep their hardcoded bytes, because a
table-driven encoder is a mechanism with no present user.

Honest scorecard so far: the check has confirmed 29 forms that were already right, and it has
*caught* nothing except my own query bug (LOADALL vs SYSCALL). Its value today is confirmation;
its value later is that the table will roughly triple, and the `/digit` and width-rule errors it
prevents are exactly the ones that produce plausible wrong bytes.
## Fixed in `asm1`, frozen in `asm0a`: `[rbp]` (and `[r13]`)

`emit_mem` sets `mod = 01` when the displacement is non-zero and `mod = 00` otherwise. That rule is
correct for every base register except `rbp`/`r13`, where `mod = 00, rm = 101` does not mean `[rbp]`
— it means **RIP-relative with a disp32**:

```
movzx eax, byte [rbp]     -> 0f b6 05          WRONG: 3 bytes; the next four bytes of the program
                                               are read as the displacement
movzx eax, byte [rbp+1]   -> 0f b6 45 01       correct
```

`[rbp]` must encode as `mod = 01, rm = 101, disp8 = 00`.

**`asm1`: fixed.** `emitmem` now chooses `mod = 01` when the displacement is non-zero, a SIB is
present, **or the base is `rbp`**, and emits the disp byte under exactly that same condition. Both
halves are needed: mod 01 without the zero byte leaves a two-byte instruction whose following byte
is read as the displacement.

| probe | before | after |
|---|---|---|
| `mov eax, [rbp]` | `8b 05` | `8b 45 00` |
| `mov [rbp], eax` | `89 05` | `89 45 00` |
| `lea rax, [rbp]` | `48 8d 05` | `48 8d 45 00` |
| `movzx eax, byte [rbp]` | `0f b6 05` | `0f b6 45 00` |
| `mov byte [rbp], 1` | `c6 05 01` | `c6 45 00 01` |
| `mov eax, [rbp+1]` | `8b 45 01` | unchanged |
| `mov eax, [rbx]` | `8b 03` | unchanged (mod 00, no byte) |
| `mov eax, [rsp]` | `8b 04 24` | unchanged (mod 00 + SIB, no byte) |

Held by `tests/superior/rbp0.s` with the hand-computed `8b4500`, which also fails if `asm0a` ever
starts agreeing. That case could not exist before the coverage gate: **no test input in this repo had
ever written `[rbp]` with a zero displacement**, so the entire corpus was blind to a wrong answer.

The defect remains in `asm0a`, which is frozen and has to stay that way. The bootstrap and `asm1` now
disagree here, and `make test-superior` records which side is right.

When `r8`–`r15` land, `r13` needs the same test: base code 13 with `mod = 00` is RIP-relative too.

## REX.W: the width comes from the operand names

The reg-reg ALU forms had no notion of width. `add`/`xor` *refused* 64-bit operands (a check that
looked like safety), while `mov`, `cmp`, `and`, `or`, `test` and `imul` **silently emitted the 32-bit
encoding** for 64-bit operands, and `sub` emitted `REX.W` unconditionally, so `sub eax, ecx` was
byte-identical to `sub rax, rcx`. Four of those six were wrong answers that assembled cleanly:

```
before                                     after
add rax, rbx   -> line 1: rejected         48 01 d8
xor rax, rax   -> line 1: rejected         48 31 c0
mov rax, rbx   -> 89 d8   (mov eax, ebx)   48 89 d8
and rax, rbx   -> 21 d8   (and eax, ebx)   48 21 d8
cmp rax, rbx   -> 39 d8   (cmp eax, ebx)   48 39 d8
test rax, rbx  -> 85 d8                    48 85 d8
sub eax, ecx   -> 48 29 c8 (sub rax, rcx)  29 c8
```

**The rule now:** `reg32` records the width of the register it parsed (byte `[rbp+9]`, 0 = 32-bit,
1 = 64-bit); handlers that take two registers compare the two widths and **refuse a mix**, and every
handler emits `0x48` iff the width is 64-bit — before the opcode, never after. One concept, one
byte, one place to look.

| form | 32-bit | 64-bit |
|---|---|---|
| `add`/`sub`/`and`/`or`/`test`/`cmp` r,r | `01`/`29`/`21`/`09`/`85`/`39` `/r` | `48` + same |
| `add`/`and`/`or`/`test`/`cmp` r,imm32 | `81` or `F7` `/digit` | `48` + same |
| `mov r,r` / `mov [mem],r` / `mov r,[mem]` | `89`/`89`/`8B` `/r` | `48` + same |
| `mov r64, imm32` | `48 C7 /0 id` | `C7` | 0 | `MOV Evqp, Ivqp` (`REX.W` + sign-extended imm32; **not** `48 B8+rd`, which takes eight immediate bytes) |
| `inc`/`dec`/`neg`/`not` | `FF`/`F7` `/digit` | `48` + same |
| `shl`/`shr`/`sar r,imm8` | `C1` `/digit ib` | `48` + same |
| `imul r,r` | `0F AF /r` | `48 0F AF /r` |
| `push`/`pop` | **refused** (`50`/`58` push 8 bytes, so a 32-bit name is a mistake) | `50+rd`/`58+rd` |

`push eax` is now a rejection rather than a silent 8-byte push, and `add eax, rbx` is a rejection
rather than a guess. Held by `tests/superior/width64.s`, whose `.hex` carries a hand-computed
expectation per line, and by `tests/reject/width-mix.s`.

Two notes worth keeping:

- **`asm0a` was right about `sub`.** It emitted `29 c8` for `sub eax, ecx` where `asm1` emitted
  `48 29 c8`. This is the reverse of the usual direction — the frozen bootstrap, which is not a
  correctness reference, had the better answer, and it was found by writing the width rule down
  rather than by testing `sub` specifically. Agreement is evidence about the two implementations,
  not a proof; here the older one won.
- `movzx rax, cl` still emits the 32-bit form (`0f b6 c1`). That is *correct* for a byte source —
  32-bit `movzx` zero-extends into the full register — so no `REX.W` is needed and none is emitted.

Not done yet: `r8`–`r15`. The width is in place, but the extended-register codes (REX.R/X/B and the
3-bit masking of every code) are the next step; until then `mov r8, rax` is a rejection, not a wrong
answer.

## `r8`–`r15`: REX.R/X/B, and three traps the register names set

`reg32` now parses `r8`…`r15` and `r8d`…`r15d` (the `d` suffix is the 32-bit form), and every
handler feeds three slots — the code destined for the ModRM *reg* field, the *rm*/base field, and the
SIB index — to one helper:

```
REX = 0x40 | W<<3 | R<<2 | X<<1 | B        emitted only when it is not 0x40
```

Every register code is masked with `and ..., 7` before it is shifted into a ModRM or SIB byte: the
extended bit lives in REX and nowhere else. `r13` needed no special case for the `mod = 00` trap,
because the test is `base & 7 == 5`, which `rbp` and `r13` share — and `r12` shares `rsp`'s
`base & 7 == 4`, so the SIB rule holds for it too.

| form | bytes | why |
|---|---|---|
| `mov r8, rax` | `49 89 c0` | W + B (rm = r8) |
| `add r8, r9` | `4d 01 c8` | W + R (reg = r9) + B (rm = r8) |
| `add rax, r8` | `4c 01 c0` | W + R |
| `mov r9, [r8]` | `4d 8b 08` | W + R + B, mod 00 |
| `mov [r13], rax` | `49 89 45 00` | B; base & 7 = 5 → mod 01, disp8 00 |
| `mov rax, [r12]` | `49 8b 04 24` | B; base & 7 = 4 → SIB, sib 00 100 100 |
| `lea r10, [r8+r9]` | `4f 8d 54 08 00` | W + R + X + B, mod 01 + disp8 00 |
| `movzx r11, cl` | `4c 0f b6 d9` | W + R |
| `mov r10d, 1` | `41 ba 01 00 00 00` | B only, no W |
| `mov r8d, [r9]` | `45 8b 01` | R + B, no W |
| `inc r12` | `49 ff c4` | W + B, ModRM /0 |
| `pop r15` | `41 5f` | B only |

### Trap 1: dispatch by fixed offset

Three handlers decided which form they were looking at by the *position of the comma*:
`mov r8, 1` has a comma at offset 2 (like `mov al, 1`), so it took the 8-bit immediate path and was
rejected; `add r8, r9` has one at offset 6 (where `add eax, …` has its last letter), so it took
`add r8, imm8`. Both now test for `r` followed by a digit *before* deciding by position. A parser
that keys on offsets is keyed on the length of a register name, and `r8` is shorter than `eax`.

### Trap 2: `push`/`pop` must not set REX.W

`50` pushes eight bytes in long mode, so the width is not a field of the instruction. The first
version of `ppsh` set W like every other handler, which turned `push rax` into `48 50` — legal, and
wrong as an encoding. **Nothing in the fixture corpus uses `push`/`pop`**, and the capability pairs
compare two *spellings* of the same instruction, so both moved together and stayed green. It was
found because `dis` (built by this assembler from `src/dis.s`, which does use `pop`) came out 3 bytes
longer than the previous build. A systematic encoding change passes a spelling comparison by
construction; only a hand-computed byte or a byte-identity fixture catches it.

### Trap 3: `B8+rd` has no ModRM reg field

`mov r10d, 1` is `B8+rd`, so the register number lives in the opcode and only `REX.B` applies. The
first version set `REX.R` as well (`45 ba …` where `41 ba …` is canonical): harmless on the machine,
wrong as an encoding. Caught by the hand-computed `.hex` in `tests/superior/regs64`, which is exactly
what that file is for — the coverage gate cannot see this, because `r8` and `rax` are the same *shape*
(`r64`). Register identity is pinned by hand-computed bytes, not by the census.

### A reject case that stopped rejecting

`tests/reject/bad-register.s` was `mov r9, 1`, which this assembler rejected because `r9` did not
exist. It exists now, so the case assembled and `make test-reject` failed — the suite saying its own
premise had changed. It now holds `mov r7, 1` and `mov r16, 1`, which are still not registers. A
reject case that passes for a reason nobody intended is a hole, and the fix is to replace the input,
never to delete the case.

## Two wrong answers found by *using* the assembler, not by reading it

Both were found in one session by writing a compiler against this dialect. Neither was visible in
the test suite, and one of them was actively *blessed* by a hand-computed expectation that contained
the same misunderstanding.

### `mov r64, imm` was nine bytes long where the CPU reads ten

`B8+rd` with `REX.W` is `MOV r64, imm64`: the immediate is **eight** bytes. `mov rax, 1` was emitted
as `48 b8 01 00 00 00` — a nine-byte instruction whose immediate swallows the next four bytes of the
program, so every instruction after it is misread.

The narrow form for a value that fits in 32 bits is `C7 /0 id`, sign-extended:

```
before                          after
mov rax, 1  -> 48 b8 01000000   mov rax, 1  -> 48 c7 c0 01000000
mov r12, 10 -> 49 bc 0a000000   mov r12, 10 -> 49 c7 c4 0a000000
mov eax, 1  -> b8 01000000      unchanged: 32-bit keeps B8+rd, and that is what
                                every hand-emitted ref/ fixture contains
```

**`tests/superior/width64.hex` had `48b801000000` hand-computed as correct**, so the byte comparison
agreed with the defect. What caught it was the *machine*: a hand-written dialect program that used
`mov r12, 10` segfaulted, and the sixty-byte program had one candidate. This is the strongest
evidence in the repo for running what you build — a shared misunderstanding between encoder and
expectation is invisible to both, and visible immediately to the CPU.

### `jbe` assembled as `jb`, `jnb` and `jno` as `jnz`

The branch dispatcher decided on the first two characters after `j`: `b` → `jb`, `z` → `jz`, `n` →
`jnz`, `m` → `jmp`. Anything longer that *started* that way was silently the shorter instruction:

```
jbe x -> 72 fe   (jb)      jnb x -> 75 fe   (jnz)      jno x -> 75 fe   (jnz)
```

That is `asm0a`'s `and`-as-`add` defect, in `asm1`, five waves after it was written up as the
bootstrap's worst property. The mnemonics are now matched in full (`jn` must be followed by `z`, `jm`
by `p`) and followed by a delimiter (`jend`: space, tab or `.`), so a longer mnemonic is refused
instead of being truncated. `jne`, `jnb`, `jno`, `jns`, `jbe` are all rejections now, pinned by
`make test-msg-exact`.

It was found by the coverage gate noticing the mnemonic `jbe` in a corpus file — my own compiler used
it — and the build then refusing it. Two gates catching each other's blind spots is the arrangement
working.

## disp32: displacements that do not fit in a signed byte

`[base+disp32]` is now emitted when the displacement needs it, which removes the wall that stopped
any frame or record from exceeding 127 bytes:

```
mov eax, [rbx+1000]       -> 8b 83 e8 03 00 00          mod 10, disp32
mov eax, [rbx+127]        -> 8b 43 7f                   mod 01, disp8
mov eax, [rbx+128]        -> 8b 83 80 00 00 00          128 does not fit
mov eax, [rbx-129]        -> 8b 83 7f ff ff ff          -129 does not fit either
lea rax, [rsp+1000]       -> 48 8d 84 24 e8 03 00 00    SIB, then disp32
mov eax, [rbp+rcx+1000]   -> 8b 84 0d e8 03 00 00       index, then disp32
mov rax, [r13+1000]       -> 49 8b 85 e8 03 00 00       r13&7 = 5
```

The displacement is classified once (`emitmem`, byte slot `[rbp-80]`): 0 = none, 1 = disp8, 2 =
disp32. mod 00 needs "none", mod 01 needs a byte, mod 10 needs four. Two things force at least a
disp8 and the classification has to know both: an **index** (mod 00 with a SIB and base 101 means "no
base") and a base of **rbp/r13** (mod 00 with rm 101 means RIP-relative).

`memop` no longer range-checks the displacement at all: every 32-bit value is encodable as disp32, so
the check that used to refuse `[rbx+1000]` is gone, and three reject cases became a superiority case
(`tests/superior/disp32`, hand-computed).

**The workaround in `cc` died with it.** Its buffer bases were three instructions each
(`lea rax,[rbp+1]` then `sub rax, rdx`) because a 40 000-byte displacement could not be written. They
are now `lea rax, [rbp-40000]` and `cc` shrank by 15 bytes for it.

### A byte slot that is not safe, measured rather than assumed

`emitmem` needs one byte of state. The obvious free-looking byte, `[rbp+3]` (inside the argc slot,
which nothing reads), **does not work**: with the class stored there, `cc.s` fails at a short `jz`
with `line 629: rejected`, i.e. a rel8 range error, which is the symptom of the validation pass
disagreeing with the counting pass. Moving the same byte to `[rbp-80]` makes the output *identical to
the previous assembler's* for the whole corpus.

Measured, by putting the class in each candidate slot and assembling `src/cc.s`:

| slot | result |
|---|---|
| `[rbp+0]` | works |
| `[rbp+1]` | fails (rel8 range error downstream) |
| `[rbp+3]` | fails (same) |
| `[rbp+5]`, `[rbp+6]`, `[rbp+7]` | assembles, **wrong output** |
| `[rbp-80]` | works, byte-identical to the previous assembler |

`[rbp+5..7]` are explained: they are inside the 4-byte expression scratch at `[rbp+4]`. `[rbp+1]` and
`[rbp+3]` are **not** explained — no code in `src/asm1.s` writes them, and the failure mode says
something does. That is recorded here as an open question rather than a conclusion, and the rule until
it is answered is: **the safe bytes are `[rbp+2]`, `[rbp+8..11]`, `[rbp+104]`'s companions and the
negative slots `[rbp-64]`…`[rbp-128]`; do not put state in `[rbp+0..7]`.**

## Duplicate labels are refused, and that is what makes `cat` a link step

`asm1` assembled a duplicate label silently and the first definition won. That is a wrong-answer
class of its own: the second definition is dead code, which then hides whatever it was meant to do.
It also made the obvious way to combine two translation units —

```
cat a.s b.s | asm1 > prog
```

— quietly wrong whenever both files defined the same name, which for two C translation units is
`main` every time.

`lbldef` now looks the name up before adding it, in pass 0, and refuses with its own reason:
`line N: duplicate` (the fourth reason word, after `range`, `label` and the generic `rejected`).

**The check had to be preceded by three deletions**, because `src/asm1.s` itself carried seven dead
duplicate labels — a second `chkok: ret`, `trm`'s `termok`/`termnum` pair, and the unreachable
`lblchk` block with its own `ls1` copy. An assembler cannot refuse what its own source does, so the
debt recorded in `docs/continue-here.md` had to be paid first. `asm1` 7 669 → 7 598 after the
deletions and → 7 731 with the check and the new message.

The duplicate check is also the first place the assembler looks a symbol up *without* failing when it
is absent, which is why it uses `lku0` (which reports found/not-found in `edx`) rather than `lku`.
