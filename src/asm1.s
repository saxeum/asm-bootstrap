; FRAME. rbp = rsp, taken once before the first call, and every scratch slot hangs
; off it. This is not style: "call" pushes the return address AT rsp and lowers
; rsp, so [rsp] inside a called routine is the return address — addressing scratch
; that way corrupted every return until the frame base was introduced.
;   [rbp+8] emit scratch   [rbp+16] pass flag   [rbp+20] count   [rbp+24] filesz
;   [rbp+28] n             [rbp+32] reg code     [rbp+36] number  [rbp+40] loop counter
;   [rbp+56] input buffer
;
; "jmp start" is 2 bytes, so the embedded header template sits at the fixed address
; 0x40007a — constant only because it is at the very front of the image.
;
; Two passes: pass 0 counts body bytes (the header needs filesz before any body byte
; is written), pass 1 writes.

jmp start
db 127, 69, 76, 70, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0
db 2, 0, 62, 0, 1, 0, 0, 0, 120, 0, 64, 0, 0, 0, 0, 0
db 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
db 0, 0, 0, 0, 64, 0, 56, 0, 1, 0, 0, 0, 0, 0, 0, 0
db 1, 0, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
db 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0
db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
db 0, 16, 0, 0, 0, 0, 0, 0
start:
lea rbp, [rsp]
mov eax, 0
mov [rbp+28], eax
lea rsi, [rbp+1]
mov ecx, 300001
sub rsi, rcx
rdloop:
mov eax, 0
mov edi, 0
mov edx, 120
syscall
mov [rbp+68], eax
mov ecx, [rbp+28]
mov edx, [rbp+68]
add ecx, edx
mov [rbp+28], ecx
mov eax, [rbp+68]
mov ecx, 120
sub rax, rcx
jnz.l rddone
lea rsi, [rsi+120]
mov eax, [rbp+28]
mov ecx, 200000
sub rax, rcx
jb.l rdloop
jmp.l fail
rddone:
mov eax, 0
mov [rbp+16], eax
mov [rbp+20], eax
mov [rbp+80], eax
mov [rbp+2], al
mov ecx, 1
mov [rbp+120], ecx
lea rbx, [rbp+1]
mov ecx, 300001
sub rbx, rcx
mov ecx, [rbp+28]
term:
cmp ecx, 0
jz termd
lea rbx, [rbx+1]
dec ecx
jmp term
termd:
mov eax, 0
mov [rbp+28], eax
mov byte [rbx], 0
lea rbx, [rbp+1]
mov ecx, 300001
sub rbx, rcx
mov ecx, 1
mov [rbp+120], ecx
call parse

mov eax, [rbp+20]
mov ecx, 120
add eax, ecx
mov [rbp+24], eax
mov eax, 1
mov [rbp+16], eax
mov eax, 0
mov [rbp+20], eax
lea rbx, [rbp+1]
mov ecx, 300001
sub rbx, rcx
mov ecx, 1
mov [rbp+120], ecx
call parse
mov eax, 2
mov [rbp+16], eax
mov ebx, 4194426
mov eax, 24
call hcp
mov eax, [rbp+28]
cmp eax, 0
jz.l hdrdef
mov ecx, 4194424
add eax, ecx
mov [rbp+4], eax
movzx eax, byte [rbp+4]
call emital
movzx eax, byte [rbp+5]
call emital
movzx eax, byte [rbp+6]
call emital
movzx eax, byte [rbp+7]
call emital
mov eax, 0
call emital
mov eax, 0
call emital
mov eax, 0
call emital
mov eax, 0
call emital
jmp.l hdrnx
hdrdef:
mov ebx, 4194450
mov eax, 8
call hcp
hdrnx:
mov ebx, 4194458
mov eax, 64
call hcp
movzx eax, byte [rbp+24]
call emital
movzx eax, byte [rbp+25]
call emital
movzx eax, byte [rbp+26]
call emital
movzx eax, byte [rbp+27]
call emital
mov eax, 0
call emital
mov eax, 0
call emital
mov eax, 0
call emital
mov eax, 0
call emital
movzx eax, byte [rbp+24]
call emital
movzx eax, byte [rbp+25]
call emital
movzx eax, byte [rbp+26]
call emital
movzx eax, byte [rbp+27]
call emital
mov eax, 0
call emital
mov eax, 0
call emital
mov eax, 0
call emital
mov eax, 0
call emital
mov ebx, 4194538
mov eax, 8
call hcp

mov eax, 2
mov [rbp+16], eax
mov eax, 0
mov [rbp+20], eax
lea rbx, [rbp+1]
mov ecx, 300001
sub rbx, rcx
mov ecx, 1
mov [rbp+120], ecx
call parse
mov eax, 60
xor edi, edi
syscall

emital:
mov [rbp+8], al
movzx eax, byte [rbp+16]
cmp al, 2
jz.l emit_w
mov eax, [rbp+20]
inc eax
mov [rbp+20], eax
ret
emit_w:
mov eax, 1
mov edi, 1
lea rsi, [rbp+8]
mov edx, 1
syscall
mov eax, [rbp+20]
inc eax
mov [rbp+20], eax
ret

rex:
; The REX byte for the instruction being parsed, from four inputs and nothing
; else: [rbp+11] = W (0 or 1), [rbp-64]/[rbp-68]/[rbp-72] = the codes destined
; for the ModRM reg field, the rm/base field and the SIB index. A slot holding 0
; means "no such operand", which is also the correct answer for rax (code 0), so
; one representation serves both. 0x40 alone is not emitted: it changes nothing
; and would cost a byte on every instruction.
mov eax, 64
movzx edx, byte [rbp+11]
add edx, edx
add edx, edx
add edx, edx
add eax, edx
mov edx, [rbp-64]
shr edx, 3
and edx, 1
add edx, edx
add edx, edx
add eax, edx
mov edx, [rbp-72]
shr edx, 3
and edx, 1
add edx, edx
add eax, edx
mov edx, [rbp-68]
shr edx, 3
and edx, 1
add eax, edx
cmp eax, 64
jz rex_r
call emital
rex_r:
ret

parse:
pline:
mov eax, 0
mov [rbp-64], eax
mov [rbp-68], eax
mov [rbp-72], eax
movzx eax, byte [rbx]
cmp al, 0
jz.l pdone
cmp al, 10
jz.l peol
cmp al, 32
jz.l psp
cmp al, 59
jz.l pcom
lea rdx, [rbx]
ls1:
movzx eax, byte [rdx]
cmp al, 58
jz.l lbldef
cmp al, 32
jz.l dsp
cmp al, 10
jz.l dsp
cmp al, 59
jz.l dsp
cmp al, 0
jz.l dsp
lea rdx, [rdx+1]
jmp.l ls1
dsp:
movzx eax, byte [rbx]
cmp al, 115
jnz.l d_m
movzx edx, byte [rbx+1]
cmp dl, 121
jz.l psys
cmp dl, 112
jz.l d_spc
cmp dl, 104
jz.l d_sh
cmp dl, 97
jz.l d_sa
jmp.l dsubreg
d_spc:
; `space N` -- N zero bytes in the image. The segment is read-write-execute, so
; a label before it gives the address of a buffer the program can write to. It
; is deliberately not a `.bss` with memsz > filesz: that needs a fixup for the
; labels that live past the end of the file, and nothing here needs zeros that
; are not already on disk.
lea rbx, [rbx+5]        ; past "space"
call skipsp
call expr
mov [rbp+136], ecx
d_spl:
mov eax, [rbp+136]
cmp eax, 0
jz d_spd
mov eax, 0
call emital
mov eax, [rbp+136]
dec eax
mov [rbp+136], eax
jmp d_spl
d_spd:
jmp.l pline

d_sh:
movzx edx, byte [rbx+2]
cmp dl, 108
jz.l shl_
cmp dl, 114
jnz.l fail
mov eax, 40
jmp.l shx
shl_:
mov eax, 32
shx:
mov [rbp+44], eax
jmp.l psh
d_sa:
mov eax, 56
mov [rbp+44], eax
jmp.l psh

d_m:
cmp al, 109
jnz.l d_d
movzx eax, byte [rbx+3]
cmp al, 122
jz.l pzx
jmp.l pmov
d_d:
cmp al, 100
jnz.l d_a
movzx edx, byte [rbx+1]
cmp dl, 98
jz.l pdb
cmp dl, 101
jz.l d_dec
jmp.l d_div
d_div:
; `div` in the F7 group (/6) for 32- and 64-bit registers, and /6 of F6 for the
; 8-bit form that already existed. The register's width decides, and the width is
; read from the text: an 8-bit name is two characters, so the byte where a
; three-character name has its last letter is a delimiter. `r8`..`r15` are
; recognised first, because `r` followed by a digit is a 64-bit register whose
; delimiter sits one byte earlier.
movzx edx, byte [rbx+4]
cmp dl, 114
jnz d_div8
movzx edx, byte [rbx+5]
add dl, -48
cmp dl, 10
jb d_div32
d_div8:
movzx edx, byte [rbx+6]
cmp dl, 32
jz d_divgo
cmp dl, 9
jz d_divgo
cmp dl, 10
jz d_divgo
cmp dl, 0
jz d_divgo
cmp dl, 59
jz d_divgo
d_div32:
mov eax, 247
mov [rbp+44], eax
mov eax, 6
mov [rbp+48], eax
jmp.l pu32
d_divgo:
mov eax, 246
mov [rbp+44], eax
mov eax, 6
mov [rbp+48], eax
jmp.l pu8

d_dec:
movzx edx, byte [rbx+4]
cmp dl, 101
jz.l d_d32
cmp dl, 114
jz.l d_d32
mov eax, 254
mov [rbp+44], eax
mov eax, 1
mov [rbp+48], eax
jmp.l pu8
d_d32:
mov eax, 255
mov [rbp+44], eax
mov eax, 1
mov [rbp+48], eax
jmp.l pu32
d_a:
cmp al, 97
jnz.l d_c
movzx edx, byte [rbx+1]
cmp dl, 100
jz.l d_add
cmp dl, 110
jnz.l d_c
mov eax, 129
mov [rbp+44], eax
lea rbx, [rbx+4]
mov eax, 32
mov [rbp+48], eax
mov eax, 33
mov [rbp+52], eax
jmp.l pc32
d_add:
cmp al, 97
jnz.l d_c
; r8..r15 have their comma at offset 6, where a three-character register has its
; last character; check for the extended form before deciding by position.
movzx edx, byte [rbx+4]
cmp dl, 114
jnz daddc8
movzx edx, byte [rbx+5]
add dl, -48
cmp dl, 10
jb daddreg
daddc8:
movzx edx, byte [rbx+6]
cmp dl, 44
jz.l padd8
cmp dl, 32
jz.l padd8
daddreg:
mov eax, 0
mov [rbp+44], eax       ; 01 /r: the register form
mov eax, 1
mov [rbp+48], eax
mov eax, 0
jmp immpeek
dsubreg:
mov eax, 41             ; 29 /r: the register form
mov [rbp+48], eax
mov eax, 40             ; 5*8: pc32 expects the /digit already shifted
jmp immpeek

immpeek:
; eax is the /digit of the imm32 form. If the byte after the comma is a digit,
; emit `81 /digit id` and finish the line; otherwise jump to prr, the register
; form, which is unchanged. A leading `-` is not a digit, so `add eax, -1` still
; refuses rather than assembling something else.
;
; The width comes from pc32/reg32, which refuses 8-bit registers, so `add al, 5`
; keeps taking the padd8 path and `sub al, 5` keeps refusing.
mov [rbp-76], eax
lea rdx, [rbx]
ipsk:
movzx eax, byte [rdx]
cmp al, 44
jz ipcom
cmp al, 0
jz.l prr
cmp al, 10
jz.l prr
lea rdx, [rdx+1]
jmp ipsk
ipcom:
lea rdx, [rdx+1]
ipsp:
movzx eax, byte [rdx]
cmp al, 32
jnz iptok
lea rdx, [rdx+1]
jmp ipsp
iptok:
cmp al, 48
jb.l prr
cmp al, 58
jb ipdig               ; no `jae` in this dialect: test the other way round
jmp.l prr
ipdig:
lea rbx, [rbx+4]       ; pc32 expects rbx at the first operand
mov eax, 129
mov [rbp+44], eax
mov eax, [rbp-76]
mov [rbp+48], eax
jmp.l pc32

padd8:
mov eax, 128
mov [rbp+44], eax
mov eax, 0
mov [rbp+48], eax
mov eax, 133
mov [rbp+52], eax
mov eax, 1
mov [rbp+52], eax
jmp.l p8i
d_c:
cmp al, 99
jnz.l d_i
movzx edx, byte [rbx+2]
cmp dl, 108
jz.l d_call
movzx edx, byte [rbx+4]
cmp dl, 101
jz.l d_c32
cmp dl, 114
jz.l d_c32
mov eax, 128
mov [rbp+44], eax
mov eax, 7
mov [rbp+48], eax
mov eax, 0
mov [rbp+52], eax
jmp.l p8i
d_c32:
lea rbx, [rbx+4]
mov eax, 129
mov [rbp+44], eax
mov eax, 56
mov [rbp+48], eax
mov eax, 57
mov [rbp+52], eax
jmp.l pc32
d_i:
cmp al, 105
jnz.l d_x
movzx edx, byte [rbx+1]
cmp dl, 109
jz.l pimul
cmp dl, 110
jnz.l d_x
movzx edx, byte [rbx+4]
cmp dl, 101
jz.l d_i32
cmp dl, 114
jz.l d_i32
mov eax, 254
mov [rbp+44], eax
mov eax, 0
mov [rbp+48], eax
mov eax, 133
mov [rbp+52], eax
jmp.l pu8
d_i32:
mov eax, 255
mov [rbp+44], eax
mov eax, 0
mov [rbp+48], eax
mov eax, 133
mov [rbp+52], eax
jmp.l pu32
d_x:
cmp al, 120
jnz.l d_l
mov eax, 0
mov [rbp+44], eax
mov eax, 49
mov [rbp+48], eax
jmp.l prr
d_l:
cmp al, 108
jnz.l d_j
jmp.l plea
d_j:
; The mnemonic must be matched in full. Deciding on the first two characters
; alone turned `jbe` into `jb`, `jnb` into `jnz` and `jno` into `jnz`: a wrong
; instruction, assembled silently. That is asm0a's `and`-as-`add` defect in this
; assembler, and it was found by using `jbe` in my own compiler -- the coverage
; gate noticed the mnemonic and the build refused it.
cmp al, 106
jnz.l d_r
movzx edx, byte [rbx+1]
cmp dl, 98
jz jb3
cmp dl, 122
jz jz3
cmp dl, 110
jnz d_jmp
movzx edx, byte [rbx+2]
cmp dl, 122
jnz.l fail
jmp jnz4
d_jmp:
cmp dl, 109
jnz.l fail
movzx edx, byte [rbx+2]
cmp dl, 112
jnz.l fail
jmp jmp4
jb3:
movzx eax, byte [rbx+2]
call jend
mov eax, 114
mov [rbp+92], eax
jmp.l jscn
jz3:
movzx eax, byte [rbx+2]
call jend
mov eax, 116
mov [rbp+92], eax
jmp.l jscn
jnz4:
movzx eax, byte [rbx+3]
call jend
mov eax, 117
mov [rbp+92], eax
jmp.l jscn
jmp4:
movzx eax, byte [rbx+3]
call jend
mov eax, 235
mov [rbp+92], eax
jmp.l jscn
jend:
; the byte after a mnemonic must be a delimiter: space, tab, or the dot of the
; `.l` form. Anything else means the mnemonic was longer than what was matched.
cmp al, 32
jz jendx
cmp al, 9
jz jendx
cmp al, 46
jnz.l fail
jendx:
ret
psp:
lea rbx, [rbx+1]
jmp.l pline
peol:
mov eax, [rbp+120]
inc eax
mov [rbp+120], eax
lea rbx, [rbx+1]
jmp.l pline
pcom:
movzx eax, byte [rbx]
cmp al, 0
jz.l pdone
lea rbx, [rbx+1]
cmp al, 10
jnz.l pcom
mov eax, [rbp+120]
inc eax
mov [rbp+120], eax
jmp.l pline
pdone:
ret
psys:
lea rbx, [rbx+7]
mov eax, 15
call emital
mov eax, 5
call emital
jmp.l pline
pmov:
lea rbx, [rbx+4]
movzx eax, byte [rbx]
cmp al, 91
jz.l pmovmem
movzx eax, byte [rbx+1]
cmp al, 121
jz.l pmbyte
; An extended register (r8..r15) puts a comma at offset 2, exactly where a
; two-character register like `al` has it. So the offset test below must be
; skipped for it, before anything decides the form by position.
movzx eax, byte [rbx]
cmp al, 114
jnz pmvc8
movzx eax, byte [rbx+1]
add al, -48
cmp al, 10
jb.l pmvreg
pmvc8:
movzx eax, byte [rbx+2]
cmp al, 44
jz.l pmov8
cmp al, 32
jz.l pmov8
pmvreg:
call reg32
mov [rbp+32], edx
movzx eax, byte [rbp+9]
mov [rbp-64], edx
mov [rbp-64], edx
mov [rbp+10], al
lea rbx, [rbx+1]
call skipsp
movzx eax, byte [rbx]
cmp al, 91
jz.l pmovld
cmp al, 101
jz.l pmovrr
cmp al, 114
jz.l pmovrr
call expr
mov [rbp+36], ecx
mov eax, 0
mov [rbp-64], eax
mov [rbp-72], eax
mov eax, [rbp+32]
mov [rbp-68], eax
movzx eax, byte [rbp+10]
mov [rbp+11], al
call rex
; A 64-bit destination CANNOT use B8+rd: with REX.W that opcode takes an
; eight-byte immediate, so `mov rax, 1` as `48 b8 01000000` is a nine-byte
; instruction whose immediate swallows the next four bytes of the program.
; The narrow form for a value that fits in 32 bits is C7 /0 id, sign-extended.
movzx eax, byte [rbp+10]
cmp eax, 0
jz pmv32
mov eax, 199            ; C7 /0
call emital
mov eax, [rbp+32]
and eax, 7
mov edx, 192
add eax, edx
call emital
jmp pmvimm
pmv32:
mov eax, [rbp+32]
and eax, 7
mov edx, 184
add eax, edx
call emital
pmvimm:
movzx eax, byte [rbp+36]
call emital
movzx eax, byte [rbp+37]
call emital
movzx eax, byte [rbp+38]
call emital
movzx eax, byte [rbp+39]
call emital
jmp.l pline
pdb:
lea rbx, [rbx+3]
call skipsp
movzx eax, byte [rbx]
cmp al, 34
jz.l pdbstr
call expr
mov edx, 384
call chklim
mov eax, ecx
call emital
dbnext:
movzx eax, byte [rbx]
cmp al, 44
jnz.l pline
lea rbx, [rbx+1]
call skipsp
call expr
mov edx, 384
call chklim
mov eax, ecx
call emital
jmp.l dbnext
pdbstr:
lea rbx, [rbx+1]
pdbstrl:
movzx eax, byte [rbx]
cmp al, 34
jz.l pdbstre
cmp al, 92
jz.l pdbesc
call emital
lea rbx, [rbx+1]
jmp.l pdbstrl
pdbesc:
lea rbx, [rbx+1]
movzx eax, byte [rbx]
cmp al, 110
jz.l pdbnl
cmp al, 116
jz.l pdbtab
call emital
lea rbx, [rbx+1]
jmp.l pdbstrl
pdbnl:
mov eax, 10
call emital
lea rbx, [rbx+1]
jmp.l pdbstrl
pdbtab:
mov eax, 9
call emital
lea rbx, [rbx+1]
jmp.l pdbstrl
pdbstre:
lea rbx, [rbx+1]
jmp.l pline

skipsp:
movzx eax, byte [rbx]
cmp al, 32
jnz.l pdone
lea rbx, [rbx+1]
jmp.l skipsp

num32:
xor ecx, ecx
ndigit:
movzx eax, byte [rbx]
add al, 100
add al, 108
cmp al, 10
jb.l ndig
jmp.l pdone
ndig:
mov edx, ecx
add edx, edx
add ecx, ecx
add ecx, ecx
add ecx, ecx
add ecx, edx
add ecx, eax
lea rbx, [rbx+1]
jmp.l ndigit
reg32:
movzx eax, byte [rbx]
cmp al, 101
jz.l r32e
cmp al, 114
jnz.l fail
; 'r' followed by a digit is an extended register (r8..r15), which needs REX;
; 'r' followed by a letter is one of the original eight.
movzx edx, byte [rbx+1]
mov ecx, edx
add cl, -48
cmp cl, 10
jb.l regx
mov eax, 1
jmp.l r32w
r32e:
mov eax, 0
r32w:
mov [rbp+9], al
movzx edx, byte [rbx+1]
movzx ecx, byte [rbx+2]
add ecx, ecx
add ecx, ecx
add ecx, ecx
add ecx, ecx
add ecx, ecx
add ecx, ecx
add ecx, ecx
add ecx, ecx
add ecx, edx
mov edx, 7
cmp ecx, 26980
jz.l regret
mov edx, 6
cmp ecx, 26995
jz.l regret
mov edx, 5
cmp ecx, 28770
jz.l regret
mov edx, 4
cmp ecx, 28787
jz.l regret
mov edx, 3
cmp ecx, 30818
jz.l regret
mov edx, 2
cmp ecx, 30820
jz.l regret
mov edx, 1
cmp ecx, 30819
jz.l regret
mov edx, 0
cmp ecx, 30817
jz.l regret
jmp.l fail
regret:
lea rbx, [rbx+3]
ret
regx:
cmp cl, 1
jz regx10
cmp cl, 8
jb.l fail
mov eax, edx
add al, -48
movzx eax, al
lea rbx, [rbx+2]
jmp regxw
regx10:
movzx edx, byte [rbx+2]
mov ecx, edx
add cl, -48
cmp cl, 5
jb regx10b
jz regx10b
jmp.l fail
regx10b:
mov eax, 10
movzx ecx, cl
add eax, ecx
lea rbx, [rbx+3]
regxw:
movzx edx, byte [rbx]
cmp edx, 100
jnz regx64
lea rbx, [rbx+1]
mov edx, 0
jmp regxst
regx64:
mov edx, 1
regxst:
mov [rbp+9], dl
mov edx, eax
ret
r8:
movzx edx, byte [rbx]
movzx ecx, byte [rbx+1]
add ecx, ecx
add ecx, ecx
add ecx, ecx
add ecx, ecx
add ecx, ecx
add ecx, ecx
add ecx, ecx
add ecx, ecx
add ecx, edx
mov edx, 7
cmp ecx, 26722
jz.l r8ok
mov edx, 6
cmp ecx, 26724
jz.l r8ok
mov edx, 5
cmp ecx, 26723
jz.l r8ok
mov edx, 4
cmp ecx, 26721
jz.l r8ok
mov edx, 3
cmp ecx, 27746
jz.l r8ok
mov edx, 2
cmp ecx, 27748
jz.l r8ok
mov edx, 1
cmp ecx, 27747
jz.l r8ok
mov edx, 0
cmp ecx, 27745
jz.l r8ok
jmp.l fail
r8ok:
lea rbx, [rbx+2]
ret

pmov8:
call r8
mov [rbp+32], edx
lea rbx, [rbx+1]
call skipsp
call expr
mov edx, 384
call chklim
mov [rbp+36], ecx
mov eax, [rbp+32]
mov edx, 176
add eax, edx
call emital
mov eax, [rbp+36]
call emital
jmp.l pline

pzx:
lea rbx, [rbx+6]
call reg32
mov [rbp+32], edx
mov [rbp-64], edx
movzx eax, byte [rbp+9]
mov [rbp+10], al
lea rbx, [rbx+1]
call skipsp
movzx eax, byte [rbx+1]
cmp al, 121
jz.l pzmem
call r8
mov [rbp-68], edx
movzx eax, byte [rbp+10]
mov [rbp+11], al
call rex
mov eax, 15
call emital
mov eax, 182
call emital
mov eax, [rbp+32]
and eax, 7
add eax, eax
add eax, eax
add eax, eax
mov edx, [rbp-68]
and edx, 7
add eax, edx
mov edx, 192
add eax, edx
call emital
jmp.l pline
pmovrr:
call reg32
mov [rbp+36], edx
movzx eax, byte [rbp+9]
movzx ecx, byte [rbp+10]
cmp eax, ecx
jnz.l fail
mov [rbp+11], al
mov eax, [rbp+36]
mov [rbp-64], eax
mov eax, [rbp+32]
mov [rbp-68], eax
call rex
mov eax, 137
call emital
mov eax, [rbp+36]
and eax, 7
add eax, eax
add eax, eax
add eax, eax
mov edx, [rbp+32]
and edx, 7
add eax, edx
mov edx, 192
add eax, edx
call emital
jmp.l pline
pmvnr:
mov eax, 137
call emital
mov eax, [rbp+36]
add eax, eax
add eax, eax
add eax, eax
mov edx, [rbp+32]
add eax, edx
mov edx, 192
add eax, edx
call emital
jmp.l pline
p8i:
lea rbx, [rbx+4]
call r8
mov [rbp+32], edx
lea rbx, [rbx+1]
call skipsp
call expr
mov edx, 256
call chklim
mov [rbp+36], ecx
mov eax, [rbp+52]
cmp al, 0
jz.l p8gen
mov eax, [rbp+32]
cmp al, 0
jnz.l p8gen
mov eax, 4
call emital
jmp.l p8imm
p8gen:
mov eax, [rbp+44]
call emital
mov eax, [rbp+48]
add eax, eax
add eax, eax
add eax, eax
mov edx, [rbp+32]
add eax, edx
mov edx, 192
add eax, edx
call emital
p8imm:
mov eax, [rbp+36]
call emital
jmp.l pline

pu8:
lea rbx, [rbx+4]
call r8
mov eax, [rbp+48]
add eax, eax
add eax, eax
add eax, eax
add eax, edx
mov edx, 192
add eax, edx
mov [rbp+36], eax
mov eax, [rbp+44]
call emital
mov eax, [rbp+36]
call emital
jmp.l pline

prr:
lea rbx, [rbx+4]
call reg32
mov [rbp+32], edx
movzx eax, byte [rbp+9]
mov [rbp+10], al
lea rbx, [rbx+1]
call skipsp
call reg32
mov [rbp+36], edx
; both operands must be the same width: 32-bit and 64-bit are different
; instructions, and picking one of them is how 64-bit code silently becomes
; 32-bit.
movzx eax, byte [rbp+9]
movzx ecx, byte [rbp+10]
cmp eax, ecx
jnz.l fail
mov [rbp+11], al
mov eax, [rbp+36]
mov [rbp-64], eax
mov eax, [rbp+32]
mov [rbp-68], eax
call rex
mov eax, [rbp+48]
call emital
mov eax, [rbp+36]
and eax, 7
add eax, eax
add eax, eax
add eax, eax
mov edx, [rbp+32]
and edx, 7
add eax, edx
mov edx, 192
add eax, edx
call emital
jmp.l pline
memop:
lea rbx, [rbx+1]
call reg32
mov [rbp+56], edx
mov [rbp-68], edx
mov eax, 0
mov [rbp+60], eax
mov [rbp+124], eax
movzx eax, byte [rbx]
cmp al, 93
jz.l memend
cmp al, 43
jnz.l memneg
lea rbx, [rbx+1]
movzx eax, byte [rbx]
cmp al, 101
jz.l memidx
cmp al, 114
jz.l memidx
jmp.l memnum
memidx:
call reg32
mov [rbp-72], edx
inc edx
mov [rbp+124], edx
movzx eax, byte [rbx]
cmp al, 43
jnz.l memend
lea rbx, [rbx+1]
jmp.l memnum
memneg:
cmp al, 45
jnz.l fail
memnum:
call expr
; no range check: a displacement is either encodable (disp8 if it fits, disp32
; otherwise) and every 32-bit value is encodable as disp32.
mov [rbp+60], ecx
memend:
movzx eax, byte [rbx]
cmp al, 93
jnz.l fail
lea rbx, [rbx+1]
ret
emitmem:
; Every register code is masked to three bits here: the extended bit of a
; register number belongs in the REX byte, which the handler has already
; emitted, not in the ModRM or SIB byte.
;
; The displacement is classified once into [rbp-80]: 0 = none, 1 = disp8,
; 2 = disp32. mod 00 needs "no displacement", mod 01 needs a byte, mod 10 needs
; four. Two things force at least a disp8: an index (mod 00 with a SIB and
; base 101 means "no base"), and a base of rbp/r13 (mod 00 with rm 101 means
; RIP-relative).
mov eax, 0
mov [rbp-80], al
mov eax, [rbp+60]
cmp eax, 0
jz emdcd
mov ecx, eax
mov edx, 128
add ecx, edx
cmp ecx, 256
jb emdc8
mov eax, 2
mov [rbp-80], al
jmp emdcd
emdc8:
mov eax, 1
mov [rbp-80], al
emdcd:
mov eax, [rbp-80]
cmp eax, 0
jnz emdmode
mov edx, [rbp+56]
and edx, 7
cmp edx, 5
jz emdf
mov eax, [rbp+124]
cmp eax, 0
jz emdmode
emdf:
mov eax, 1
mov [rbp-80], al
emdmode:
; modrm = mod << 6 | (reg & 7) << 3 | rm, rm = 4 when a SIB follows
mov edx, [rbp+124]
cmp edx, 0
jnz emrm4
mov edx, [rbp+56]
and edx, 7
cmp edx, 4
jnz emrm
emrm4:
mov edx, 4
emrm:
mov eax, [rbp+64]
and eax, 7
add eax, eax
add eax, eax
add eax, eax
add eax, edx
mov edx, [rbp-80]
cmp edx, 0
jz emm0
cmp edx, 1
jz emm1
mov edx, 128
jmp emmod
emm0:
mov edx, 0
jmp emmod
emm1:
mov edx, 64
emmod:
add eax, edx
call emital
; SIB, when rm was 4: scale 0, index (4 = none when there is no index), base
mov edx, [rbp+124]
cmp edx, 0
jnz emsib
mov edx, [rbp+56]
and edx, 7
cmp edx, 4
jnz emdisp
emsib:
mov eax, [rbp+124]
cmp eax, 0
jz emsib0
dec eax
and eax, 7
add eax, eax
add eax, eax
add eax, eax
jmp emsib1
emsib0:
mov eax, 32
emsib1:
mov edx, [rbp+56]
and edx, 7
add eax, edx
call emital
emdisp:
mov edx, [rbp-80]
cmp edx, 1
jz emd8
cmp edx, 2
jz emd32
jmp emdone
emd8:
mov eax, [rbp+60]
call emital
jmp emdone
emd32:
movzx eax, byte [rbp+60]
call emital
movzx eax, byte [rbp+61]
call emital
movzx eax, byte [rbp+62]
call emital
movzx eax, byte [rbp+63]
call emital
emdone:
ret
pmovmem:
call memop
lea rbx, [rbx+1]
call skipsp
movzx eax, byte [rbx]
cmp al, 101
jz.l pms32
cmp al, 114
jz.l pms32
call r8
mov [rbp+64], edx
mov eax, 136
call emital
call emitmem
jmp.l pline
pms32:
call reg32
mov [rbp+64], edx
mov [rbp-64], edx
movzx eax, byte [rbp+9]
mov [rbp+11], al
call rex
mov eax, 137
call emital
call emitmem
jmp.l pline
pmbyte:
lea rbx, [rbx+5]
call memop
mov eax, 0
mov [rbp+64], eax
lea rbx, [rbx+1]
call skipsp
call expr
mov edx, 384
call chklim
mov [rbp+36], ecx
mov eax, 198
call emital
call emitmem
mov eax, [rbp+36]
call emital
jmp.l pline

pmovld:
call memop
mov eax, [rbp+32]
mov [rbp+64], eax
mov eax, [rbp-64]
mov [rbp-64], eax
movzx eax, byte [rbp+10]
mov [rbp+11], al
call rex
mov eax, 139
call emital
call emitmem
jmp.l pline
plea:
lea rbx, [rbx+4]
call reg32
mov [rbp+64], edx
mov [rbp-64], edx
movzx eax, byte [rbp+9]
mov [rbp+11], al
lea rbx, [rbx+1]
call skipsp
movzx eax, byte [rbx]
cmp al, 91
jnz.l fail
call memop
call rex
mov eax, 141
call emital
call emitmem
jmp.l pline
lbldef:
call lcpy
lea rbx, [rbx+1]
movzx eax, byte [rbp+16]
cmp al, 0
jnz.l pline
; A duplicate definition used to assemble, with the first one winning: dead
; code hidden behind a name that already existed, and a `cat a.s b.s | asm1`
; "link" that silently kept one of two `main:` labels. Refused now, in pass 0,
; before anything is emitted.
call lku0
cmp edx, 0
jz lbdnew
mov eax, 3
mov [rbp+2], al
jmp.l fail
lbdnew:
mov eax, [rbp+80]
cmp eax, 2048           ; the table holds 2048 entries: 20 bytes each, below rbp
jb.l lok
jmp.l fail
lok:
lea rcx, [rbp+1]
mov esi, 60001            ; 2048 entries of 20 bytes, below rbp
sub rcx, rsi
mov edx, [rbp+80]
lget:
cmp edx, 0
jz.l lgoth
lea rcx, [rcx+20]
dec edx
jmp.l lget
lgoth:
mov eax, [rbp-18900]
mov [rcx], eax
mov eax, [rbp-18896]
mov [rcx+4], eax
mov eax, [rbp-18892]
mov [rcx+8], eax
mov eax, [rbp-18888]
mov [rcx+12], eax
mov eax, [rbp+20]
mov [rcx+16], eax
mov eax, [rbp+80]
inc eax
mov [rbp+80], eax
jmp.l pline

lcpy:
; The name scratch lives at rbp-18900, sixteen bytes, zeroed first so a short
; name compares equal only to itself. Fifteen characters plus that zero is the
; limit: `cmp edx, 16` refuses the sixteenth.
mov eax, 0
mov [rbp-18900], eax
mov [rbp-18896], eax
mov [rbp-18892], eax
mov [rbp-18888], eax
lea rcx, [rbp-18900]
xor edx, edx
lcpyl:
movzx eax, byte [rbx]
cmp al, 58
jz.l lcpyd
; a symbol ends at +/- as well: `label-2` and `label+4` must lex as a term and
; an operator, or the no-space spelling is read as one long (unknown) name
cmp al, 43
jz.l lcpyd
cmp al, 45
jz.l lcpyd
cmp al, 32
jz.l lcpyd
cmp al, 10
jz.l lcpyd
cmp al, 0
jz.l lcpyd
cmp edx, 16
jz.l fail
mov [rcx], al
lea rcx, [rcx+1]
inc edx
lea rbx, [rbx+1]
jmp.l lcpyl
lcpyd:
ret

pbr:
call skipsp
call lcpy
movzx eax, byte [rbp+16]
cmp al, 0
jnz.l pbr1
mov eax, 0
call emital
call emital
jmp.l pline
pbr1:
lea rcx, [rbp+1]
mov esi, 60001            ; 2048 entries of 20 bytes, below rbp
sub rcx, rsi
mov edx, [rbp+80]
lfind:
cmp edx, 0
jnz.l lfok
mov eax, 2
mov [rbp+2], al
jmp.l fail
lfok:
call lcmp
cmp eax, 0
jz.l lbfnd
lea rcx, [rcx+20]
dec edx
jmp.l lfind
lbfnd:
mov eax, [rcx+16]
mov edx, [rbp+20]
mov esi, 2
add edx, esi
sub rax, rdx
mov [rbp+84], eax
mov eax, [rbp+84]
mov ecx, 128
add eax, ecx
cmp eax, 256
jb.l pbr_chk
jmp.l fail
pbr_chk:
mov eax, [rbp+92]
call emital
mov eax, [rbp+84]
call emital
jmp.l pline

pu32:
lea rbx, [rbx+4]
call reg32
mov [rbp-68], edx
movzx eax, byte [rbp+9]
mov [rbp+11], al
mov eax, [rbp+48]
add eax, eax
add eax, eax
add eax, eax
mov edx, [rbp-68]
and edx, 7
add eax, edx
mov edx, 192
add eax, edx
mov [rbp+36], eax
call rex
mov eax, [rbp+44]
call emital
mov eax, [rbp+36]
call emital
jmp.l pline
pu32_n:
mov eax, [rbp+44]
call emital
mov eax, [rbp+36]
call emital
jmp.l pline
pc32:
call reg32
mov [rbp+32], edx
movzx eax, byte [rbp+9]
mov [rbp+10], al
lea rbx, [rbx+1]
call skipsp
movzx eax, byte [rbx]
cmp al, 101
jz.l pc32rr
cmp al, 114
jz.l pc32rr
call expr
mov [rbp+36], ecx
mov eax, [rbp+32]
mov [rbp-68], eax
movzx eax, byte [rbp+10]
mov [rbp+11], al
call rex
mov eax, [rbp+48]
mov edx, [rbp+32]
and edx, 7
add eax, edx
mov edx, 192
add eax, edx
mov [rbp+40], eax
mov eax, [rbp+44]
call emital
mov eax, [rbp+40]
call emital
movzx eax, byte [rbp+36]
call emital
movzx eax, byte [rbp+37]
call emital
movzx eax, byte [rbp+38]
call emital
movzx eax, byte [rbp+39]
call emital
jmp.l pline
pc32rr:
call reg32
mov [rbp+36], edx
movzx eax, byte [rbp+9]
movzx ecx, byte [rbp+10]
cmp eax, ecx
jnz.l fail
mov [rbp+11], al
mov eax, [rbp+36]
mov [rbp-64], eax
mov eax, [rbp+32]
mov [rbp-68], eax
call rex
mov eax, [rbp+36]
and eax, 7
add eax, eax
add eax, eax
add eax, eax
mov edx, [rbp+32]
and edx, 7
add eax, edx
mov edx, 192
add eax, edx
mov [rbp+40], eax
mov eax, [rbp+52]
call emital
mov eax, [rbp+40]
call emital
jmp.l pline
fail:
call msg
mov eax, 60
mov edi, 1
syscall
lku:
lea rcx, [rbp+1]
mov esi, 60001            ; 2048 entries of 20 bytes, below rbp
sub rcx, rsi
mov edx, [rbp+80]
lkul:
cmp edx, 0
jz.l fail
call lcmp
cmp eax, 0
jz.l lkux
lea rcx, [rcx+20]
dec edx
jmp.l lkul
lkux:
ret

plng:
call skipsp
call lcpy
movzx eax, byte [rbp+16]
cmp al, 0
jnz.l plng1
mov eax, 0
call emital
call emital
call emital
call emital
call emital
movzx eax, byte [rbp+92]
cmp eax, 235
jz.l pline
call emital
jmp.l pline
plng1:
call lku
mov esi, 6
movzx eax, byte [rbp+92]
cmp eax, 235
jnz.l plng2
mov esi, 5
plng2:
mov eax, [rcx+16]
mov edx, [rbp+20]
add edx, esi
sub rax, rdx
mov [rbp+84], eax
movzx eax, byte [rbp+92]
cmp eax, 235
jz.l plng3
mov eax, 15
call emital
movzx eax, byte [rbp+92]
mov esi, 16
add eax, esi
call emital
jmp.l plng4
plng3:
mov eax, 233
call emital
plng4:
movzx eax, byte [rbp+84]
call emital
movzx eax, byte [rbp+85]
call emital
movzx eax, byte [rbp+86]
call emital
movzx eax, byte [rbp+87]
call emital
jmp.l pline

pcall:
call skipsp
call lcpy
movzx eax, byte [rbp+16]
cmp al, 0
jnz.l pcal1
mov eax, 0
call emital
call emital
call emital
call emital
call emital
jmp.l pline
pcal1:
call lku
mov eax, [rcx+16]
mov edx, [rbp+20]
mov esi, 5
add edx, esi
sub rax, rdx
mov [rbp+84], eax
mov eax, 232
call emital
movzx eax, byte [rbp+84]
call emital
movzx eax, byte [rbp+85]
call emital
movzx eax, byte [rbp+86]
call emital
movzx eax, byte [rbp+87]
call emital
jmp.l pline

pret:
mov eax, 195
call emital
lea rbx, [rbx+3]
jmp.l pline

jscn:
lea rdx, [rbx+2]
jsc1:
movzx eax, byte [rdx]
cmp al, 46
jz.l jlng
cmp al, 32
jz.l jshrt
cmp al, 0
jz.l fail
lea rdx, [rdx+1]
jmp.l jsc1
jlng:
lea rdx, [rdx+2]
lea rbx, [rdx+1]
jmp.l plng
jshrt:
lea rbx, [rdx+1]
jmp.l pbr

d_r:
cmp al, 114
jnz.l d_en
movzx edx, byte [rbx+1]
cmp dl, 101
jnz.l fail
jmp.l pret

d_en:
cmp al, 101
jnz.l d_o
movzx edx, byte [rbx+1]
cmp dl, 110
jnz.l fail
lea rbx, [rbx+6]
call skipsp
call expr
mov [rbp+28], ecx
jmp.l pline

d_o:
cmp al, 111
jnz.l d_t
lea rbx, [rbx+3]
mov eax, 129
mov [rbp+44], eax
mov eax, 8
mov [rbp+48], eax
mov eax, 9
mov [rbp+52], eax
jmp.l pc32
d_p:
cmp al, 112
jnz.l d_n
movzx edx, byte [rbx+1]
cmp dl, 117
jz.l psh_push
cmp dl, 111
jnz.l fail
mov eax, 88
lea rbx, [rbx+4]
mov [rbp+44], eax
jmp.l ppsh
psh_push:
lea rbx, [rbx+5]
mov eax, 80
mov [rbp+44], eax
jmp.l ppsh
d_t:
cmp al, 116
jnz.l d_p
lea rbx, [rbx+5]
mov eax, 247
mov [rbp+44], eax
mov eax, 0
mov [rbp+48], eax
mov eax, 133
mov [rbp+52], eax
jmp.l pc32

d_call:
mov eax, 235
mov [rbp+92], eax
lea rbx, [rbx+5]
jmp.l pcall

pzmem:
lea rbx, [rbx+5]
call memop
mov eax, [rbp+32]
mov [rbp+64], eax
mov eax, [rbp-64]
mov [rbp-64], eax
movzx eax, byte [rbp+10]
mov [rbp+11], al
call rex
mov eax, 15
call emital
mov eax, 182
call emital
call emitmem
jmp.l pline
chklim:
mov eax, ecx
mov esi, 128
add eax, esi
sub rax, rdx
jb.l chkok
mov eax, 1
mov [rbp+2], al
jmp.l fail
chkok:
ret

numlit:
mov eax, 0
mov [rbp+96], eax
movzx eax, byte [rbx]
cmp al, 45
jnz.l nl_pos
mov eax, 1
mov [rbp+96], eax
lea rbx, [rbx+1]
nl_pos:
movzx eax, byte [rbx]
cmp al, 39
jz.l nl_chr
cmp al, 48
jnz.l nl_dec
movzx eax, byte [rbx+1]
cmp al, 120
jz.l nl_hex
nl_dec:
call num32
jmp.l nl_done
nl_chr:
lea rbx, [rbx+1]
movzx eax, byte [rbx]
lea rbx, [rbx+1]
movzx edx, byte [rbx]
cmp dl, 39
jnz.l fail
lea rbx, [rbx+1]
mov ecx, eax
jmp.l nl_done
nl_hex:
lea rbx, [rbx+2]
xor ecx, ecx
nl_hl:
movzx edx, byte [rbx]
mov eax, edx
add al, 100
add al, 108
cmp al, 10
jb.l nl_hd
mov eax, edx
add al, 100
add al, 69
cmp al, 16
jb.l nl_hc
jmp.l nl_hend
nl_hc:
cmp al, 10
jb.l nl_hend
nl_hd:
mov edx, ecx
add edx, edx
add edx, edx
add edx, edx
add edx, edx
add edx, eax
mov ecx, edx
lea rbx, [rbx+1]
jmp.l nl_hl
nl_hend:
nl_done:
mov eax, [rbp+96]
cmp al, 0
jz.l nl_ret
mov eax, 0
sub rax, rcx
mov ecx, eax
nl_ret:
ret

putch:
mov [rbp+124], al
mov eax, 1
mov edi, 2
lea rsi, [rbp+124]
mov edx, 1
syscall
ret

msg:
mov eax, 108
call putch
mov eax, 105
call putch
mov eax, 110
call putch
mov eax, 101
call putch
mov eax, 32
call putch
mov ecx, [rbp+120]
mov bl, 10
lea rdx, [rbp+100]
mov esi, 5
dgl:
mov eax, ecx
div bl
movzx edi, ah
mov [rdx], edi
movzx ecx, al
lea rdx, [rdx+4]
dec esi
jnz.l dgl
mov eax, 0
mov [rbp+88], eax
mov eax, [rbp+116]
call prd
mov eax, [rbp+112]
call prd
mov eax, [rbp+108]
call prd
mov eax, [rbp+104]
call prd
mov eax, [rbp+100]
call prd
mov ecx, [rbp+88]
cmp ecx, 0
jnz.l mnex
mov eax, 48
call putch
mnex:
mov eax, 58
call putch
mov eax, 32
call putch
movzx eax, byte [rbp+2]
cmp eax, 1
jz.l mrng
cmp eax, 2
jz.l mlbl
cmp eax, 3
jz.l mdup
mov eax, 114
call putch
mov eax, 101
call putch
mov eax, 106
call putch
mov eax, 101
call putch
mov eax, 99
call putch
mov eax, 116
call putch
mov eax, 101
call putch
mov eax, 100
call putch
jmp.l mdone
mrng:
mov eax, 114
call putch
mov eax, 97
call putch
mov eax, 110
call putch
mov eax, 103
call putch
mov eax, 101
call putch
jmp.l mdone
mdup:
mov eax, 100
call putch
mov eax, 117
call putch
mov eax, 112
call putch
mov eax, 108
call putch
mov eax, 105
call putch
mov eax, 99
call putch
mov eax, 97
call putch
mov eax, 116
call putch
mov eax, 101
call putch
jmp.l mdone
mlbl:
mov eax, 108
call putch
mov eax, 97
call putch
mov eax, 98
call putch
mov eax, 101
call putch
mov eax, 108
call putch
mdone:
mov eax, 10
call putch
ret
prd:
cmp eax, 0
jnz.l prp
mov ecx, [rbp+88]
cmp ecx, 0
jz.l prx
prp:
mov esi, 1
mov [rbp+88], esi
add al, 48
call putch
prx:
ret

lcmp:
; Compare the label entry at rcx with the name scratch: result eax = 0 when the
; sixteen-byte names are equal. rcx, rdx and rbx are preserved, so a caller's
; walk and stride survive it; r8..r11 are this routine's own.
lea r9, [rcx]
lea r10, [rbp-18900]
mov edi, 0
mov r8, 4
lcml:
mov eax, [r9]
mov r11, [r10]
xor eax, r11d
or edi, eax
lea r9, [r9+4]
lea r10, [r10+4]
dec r8
cmp r8, 0
jnz lcml
mov eax, edi
ret

lku0:
lea rcx, [rbp+1]
mov esi, 60001            ; 2048 entries of 20 bytes, below rbp
sub rcx, rsi
mov edx, [rbp+80]
lk0l:
cmp edx, 0
jz.l lk0z
call lcmp
cmp eax, 0
jz.l lk0f
lea rcx, [rcx+20]
dec edx
jmp.l lk0l
lk0f:
mov eax, [rcx+16]
mov edx, 1
ret
lk0z:
mov eax, 0
xor edx, edx
ret

expr:
mov eax, 0
mov [rbp+12], eax
call trm
mov [rbp+12], ecx
exl:
call skipsp
movzx eax, byte [rbx]
cmp al, 43
jz.l expos
cmp al, 45
jz.l exneg
jmp.l exret
expos:
lea rbx, [rbx+1]
call skipsp
call trm
mov eax, [rbp+12]
add eax, ecx
mov [rbp+12], eax
jmp.l exl
exneg:
lea rbx, [rbx+1]
call skipsp
call trm
mov eax, [rbp+12]
sub rax, rcx
mov [rbp+12], eax
jmp.l exl
exret:
mov ecx, [rbp+12]
ret

trm:
movzx eax, byte [rbx]
cmp al, 97
jb.l termnum
call lcpy
call lku0
mov [rbp+4], eax
cmp edx, 0
jnz.l termok
movzx eax, byte [rbp+16]
cmp eax, 0
jz.l termok
mov eax, 2
mov [rbp+2], al
jmp.l fail
termok:
mov ecx, [rbp+4]
ret
termnum:
jmp.l numlit


hcp:
mov [rbp+40], eax
hcpl:
movzx eax, byte [rbx]
call emital
lea rbx, [rbx+1]
mov eax, [rbp+40]
dec eax
mov [rbp+40], eax
cmp eax, 0
jnz.l hcpl
ret

psh:
lea rbx, [rbx+4]
call reg32
mov [rbp+32], edx
mov [rbp-68], edx
movzx eax, byte [rbp+9]
mov [rbp+10], al
mov [rbp+11], al
lea rbx, [rbx+1]
call skipsp
call expr
mov edx, 256
call chklim
mov [rbp+36], ecx
mov eax, [rbp-68]
and eax, 7
mov edx, [rbp+44]
add eax, edx
mov edx, 192
add eax, edx
mov [rbp+40], eax
call rex
mov eax, 193
call emital
mov eax, [rbp+40]
call emital
mov eax, [rbp+36]
call emital
jmp.l pline
psh_n:
mov eax, 193
call emital
mov eax, [rbp+40]
call emital
mov eax, [rbp+36]
call emital
jmp.l pline
ppsh:
call reg32
movzx ecx, byte [rbp+9]
cmp ecx, 0
jz.l fail
mov [rbp-68], edx
mov eax, 0
mov [rbp+11], al
call rex
mov eax, [rbp+44]
mov edx, [rbp-68]
and edx, 7
add eax, edx
call emital
jmp.l pline
pimul:
lea rbx, [rbx+5]
call reg32
mov [rbp+32], edx
movzx eax, byte [rbp+9]
mov [rbp+10], al
lea rbx, [rbx+1]
call skipsp
call reg32
mov [rbp+36], edx
movzx eax, byte [rbp+9]
movzx ecx, byte [rbp+10]
cmp eax, ecx
jnz.l fail
mov [rbp+11], al
mov eax, [rbp+32]
mov [rbp-64], eax
mov eax, [rbp+36]
mov [rbp-68], eax
call rex
mov eax, 15
call emital
mov eax, 175
call emital
mov eax, [rbp+32]
and eax, 7
add eax, eax
add eax, eax
add eax, eax
mov edx, [rbp+36]
and edx, 7
add eax, edx
mov edx, 192
add eax, edx
call emital
jmp.l pline
pim_n:
mov eax, 15
call emital
mov eax, 175
call emital
mov eax, [rbp+32]
add eax, eax
add eax, eax
add eax, eax
mov edx, [rbp+36]
add eax, edx
mov edx, 192
add eax, edx
call emital
jmp.l pline
d_n:
cmp al, 110
jnz.l fail
movzx edx, byte [rbx+2]
cmp dl, 103
jz.l d_neg
cmp dl, 116
jnz.l fail
mov eax, 247
mov [rbp+44], eax
mov eax, 2
mov [rbp+48], eax
jmp.l pu32
d_neg:
mov eax, 247
mov [rbp+44], eax
mov eax, 3
mov [rbp+48], eax
jmp.l pu32

