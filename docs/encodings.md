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

## Known defect: `sub r32, r32` is encoded as 64-bit

`sub` is the one ALU form whose opcode sets `REX.W` (`48 29 /r`), so the width comes from the
encoding rather than from the operand names, and nothing checks that the two agree:

```
sub eax, ecx      -> 48 29 c8       byte-identical to `sub rax, rcx`
```

For a 32-bit operand that is a wrong answer of the same class as `asm0a`'s `and`-as-`add`: correct
while the upper halves are zero, silently wrong when they are not.

**Status: not fixed, and deliberately not pinned.** The fix is not a check but the REX mechanism
itself — take the width from the operand names, emit `REX.W` only for the 64-bit form, refuse a mix.
That is the next task in `docs/ROADMAP.md`, and pinning `48 29 c8` now would turn a wrong answer into
a recorded expectation. Until then: **`sub` is 64-bit, whatever the source says.**
