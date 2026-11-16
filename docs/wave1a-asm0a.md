# Wave 1a — `asm0a`: first assembler, hand-emitted machine code

**Status: working.** 664-byte hand-emitted executable, sha256
`255ac2e1f13b2a0ae54f9375d5f6be1b285120ea395014bcfbea4bbcf3aa5e60`.
No assembler, no compiler, no script: `printf` wrote every byte; the encoding tables are in
the listing below.

## What it assembles

```
mov eax, 60          ; B8+reg  + imm32   (reg32 from an 8-entry table)
mov edi, 42
syscall              ; 0F 05
```

Leading spaces and blank lines are skipped. `mov` must be followed by exactly one space
(the parser skips 4 characters for `"mov "`). Anything else — unknown mnemonic, unknown
register — exits 1 with no output at all. Not yet in this slice: `xor`, `db`, hex literals,
labels, `entry`, comments.

Runs as `./asm0a < source.s > output` — no argv parsing, no `open`, no `chmod` yet.

## Oracle, and the result

An assembler is correct when its output is **byte-identical** to bytes written by hand.

```
$ ./asm0a < src/exit42.s > .work/e42.out ; echo $?
0
$ wc -c < .work/e42.out
132
$ cmp .work/e42.out .work/e42.expected && echo identical
identical
$ chmod +x .work/e42.out && .work/e42.out ; echo $?
42
$ sha256sum .work/e42.out
d93aa7e7fd49e17fb09ac7cd6b0cd0776dea9e40503595ae28b1abf7c71c48c7
```

Rejection path, which must produce *nothing*, not a partial file:

```
$ printf 'bogus\n'      | ./asm0a > .work/x ; echo $? $(wc -c < .work/x)
1 0
$ printf 'mov zzz, 5\n' | ./asm0a > .work/x ; echo $? $(wc -c < .work/x)
1 0
```

## Memory map and registers

After `sub rsp, 0x20000`: source `rsp+0x00000`, body `rsp+0x10000`, header scratch
`rsp+0x1F000`. `r12` source base, `r13` source end, `r14` body base, `r15` body cursor,
`rbx` parse cursor. All jumps are `rel32` on purpose — uniform sizes mean every offset is
fixed before any displacement is known, which is what breaks hand-laid code.

## Listing (code offsets are from the first byte of code, file offset 0x78)

```
00  48 81 EC 00 00 02 00   sub  rsp, 0x20000
07  49 89 E4              mov  r12, rsp
0A  4D 89 E6              mov  r14, r12
0D  49 81 C6 00 00 01 00   add  r14, 0x10000
14  4D 89 F7              mov  r15, r14
17  31 C0                 xor  eax, eax
19  48 89 C7              mov  rdi, rax          ; fd 0
1C  4C 89 E6              mov  rsi, r12
1F  BA 00 00 01 00        mov  edx, 0x10000
24  0F 05                 syscall                ; read(0, src, 64K)
26  4D 89 E5              mov  r13, r12
29  49 01 C5              add  r13, rax
2C  4C 89 E3              mov  rbx, r12
2F  4C 39 EB              loop:   cmp rbx, r13    ; REX.B must be 0: rbx is not extended
32  0F 83 E8 00 00 00     jae  done
38  0F B6 03              movzx eax, byte [rbx]
3B  3C 20                 cmp  al, ' '
3D  0F 84 1D 00 00 00     je   adv
43  3C 0A                 cmp  al, 10
45  0F 84 15 00 00 00     je   adv
4B  3C 73                 cmp  al, 's'
4D  0F 84 15 00 00 00     je   do_sys
53  3C 6D                 cmp  al, 'm'
55  0F 84 24 00 00 00     je   do_mov
5B  E9 1C 01 00 00        jmp  fail
60  48 FF C3              adv:    inc rbx
63  E9 C7 FF FF FF        jmp  loop
68  48 83 C3 07           do_sys: add rbx, 7             ; past "syscall"
6C  41 C6 07 0F           mov  byte [r15], 0x0F
70  49 FF C7              inc  r15
73  41 C6 07 05           mov  byte [r15], 0x05
77  49 FF C7              inc  r15
7A  E9 87 00 00 00        jmp  eol+3                     ; rbx is already ON the '\n'
7F  48 83 C3 04           do_mov: add rbx, 4             ; past "mov "
83  E8 50 00 00 00        call lookup                    ; edx = register code
88  89 D6                 mov  esi, edx
8A  48 83 C3 03           add  rbx, 3                    ; past register name
8E  48 FF C3              inc  rbx                       ; skip ','
91  0F B6 03              sb:     movzx eax, byte [rbx]
94  3C 20                 cmp  al, ' '
96  0F 85 08 00 00 00     jne  num
9C  48 FF C3              inc  rbx
9F  E9 ED FF FF FF        jmp  sb
A4  31 C9                 num:    xor ecx, ecx
A6  0F B6 03              ml:     movzx eax, byte [rbx]
A9  2C 30                 sub  al, '0'
AB  3C 09                 cmp  al, 9
AD  0F 87 0D 00 00 00     ja   numend
B3  6B C9 0A              imul ecx, ecx, 10
B6  01 C1                 add  ecx, eax
B8  48 FF C3              inc  rbx
BB  E9 E6 FF FF FF        jmp  ml
C0  8D 86 B8 00 00 00     numend: lea eax, [rsi+0xB8]
C6  41 88 07              mov  [r15], al                 ; 3 bytes, not 4
C9  49 FF C7              inc  r15
CC  41 89 0F              mov  [r15], ecx                ; 3 bytes, not 4
CF  49 83 C7 04           add  r15, 4
D3  E9 2E 00 00 00        jmp  eol+3
D8  8B 03                 lookup: mov eax, [rbx]
DA  25 FF FF FF 00        and  eax, 0x00FFFFFF
DF  B9 00 02 40 00        mov  ecx, 0x400200             ; TABLE = 0x400000+0x78+0x188
E4  31 D2                 xor  edx, edx
E6  3B 01                 lk:     cmp eax, [rcx]
E8  0F 84 14 00 00 00     je   lkok
EE  48 83 C1 04           add  rcx, 4
F2  FF C2                 inc  edx
F4  83 FA 08              cmp  edx, 8
F7  0F 82 E9 FF FF FF     jb   lk
FD  E9 7A 00 00 00        jmp  fail
102 C3                    lkok:   ret
103 48 FF C3              eol:    inc rbx                ; for multi-line skipping
106 4C 39 EB              cmp  rbx, r13                 ; <- handlers that already
109 0F 83 11 00 00 00     jae  done                     ;    sit on '\n' enter HERE
10F 80 3B 0A              cmp  byte [rbx], 10
112 0F 85 EB FF FF FF     jne  eol
118 48 FF C3              inc  rbx
11B E9 0F FF FF FF        jmp  loop
120 4C 89 F8              done:   mov rax, r15
123 4C 29 F0              sub  rax, r14
126 48 83 C0 78           add  rax, 120                  ; filesz
12A 48 8D BC 24 00 F0 01 00  lea rdi, [rsp+0x1F000]
132 BE 20 02 40 00        mov  esi, 0x400220             ; TPL = 0x400000+0x78+0x1A8
137 B9 78 00 00 00        mov  ecx, 120
13C F3 A4                 rep  movsb
13E 48 89 47 E8           mov  [rdi-0x18], rax           ; p_filesz (0x60)
142 48 89 47 F0           mov  [rdi-0x10], rax           ; p_memsz  (0x68)
146 48 89 FE              mov  rsi, rdi
149 48 83 EE 78           sub  rsi, 120
14D B8 01 00 00 00        mov  eax, 1
152 BF 01 00 00 00        mov  edi, 1                    ; stdout
157 BA 78 00 00 00        mov  edx, 120
15C 0F 05                 syscall
15E B8 01 00 00 00        mov  eax, 1
163 BF 01 00 00 00        mov  edi, 1
168 4C 89 F6              mov  rsi, r14
16B 4C 89 FA              mov  rdx, r15
16E 4C 29 F2              sub  rdx, r14
171 0F 05                 syscall                        ; body
173 B8 3C 00 00 00        mov  eax, 60
178 31 FF                 xor  edi, edi
17A 0F 05                 syscall
17C B8 3C 00 00 00        fail:   mov eax, 60
181 BF 01 00 00 00        mov  edi, 1
186 0F 05                 syscall                        ; exit 1
188 TABLE:  "eax\0ecx\0edx\0ebx\0esp\0ebp\0esi\0edi\0"   32 bytes
1A8 TPL:    120-byte ELF64 header + PT_LOAD (e_entry 0x400078,
            p_filesz/p_memsz zero, patched at runtime)
file = 120 + 0x220 = 664 bytes
```

## The four defects the first run found (all invisible on paper)

1. **`4D 39 EB` instead of `4C 39 EB`** at `cmp rbx, r13` (two sites). REX.B extends the *rm*
   field; `rbx` is not an extended register, and `r13` is in the *reg* field, so only REX.R
   is set. With B=1 the instruction compared `r11` against `r13` — a decode said
   `cmp %r13,%r11`, which is how it was caught. (It was a system `objdump`, at a time when that
   was allowed; `src/dis.s` is the decoder a session may use now, and it does not cover `4C 39 EB`,
   so this defect class is caught by a hand-computed dump or by running the code.)
2. **`mov [r15], al` is 3 bytes, not 4.** My offset table counted `REX opcode modrm` as four.
   Two of them made the table 2 bytes earlier than planned, so `TABLE` was at 0x188, not
   0x18A, and every later offset was wrong.
3. **Symbol addresses forgot the 0x78.** `TABLE` is at `0x400000 + 0x78 + 0x188 = 0x400200`;
   I had written `0x400188` (the code-relative offset). The lookup compared 4 bytes of
   register name against a pointer to unmapped low memory, missed all 8 entries and exited 1.
   Symptom was `mov eax, 60` producing nothing while `syscall` alone worked — that split is
   what localised it to `lookup`.
4. **`eol` consumed the next line.** It began with `inc rbx` and then tested for `'\n'`, but
   both the number parser and `add rbx, 7` leave `rbx` *on* the newline, so the `inc` stepped
   over it and the loop skipped the following line. Fix: entry point `eol+3` for handlers
   that are already on the newline (a 2-byte patch, no relayout).

Lesson for the plan: three of these four produce a *working-looking* binary or a clean exit.
None is visible by reading the bytes. They were found only by running the assembler and
comparing bytes against an independent expectation.

## Next

- **1b**: `xor r32, r32` and `db "…"` with escapes; then the oracle becomes `hello` itself —
  `asm0a` on a numeric source (`mov esi, 4194583`, `mov edx, 14`) must equal sha
  `4f386903…`, 165 bytes.
- **1c**: labels + `entry` + two passes, so the real `src/hello.s` assembles.
- **2**: relative jumps, so `count10` and `fib` are reachable.
