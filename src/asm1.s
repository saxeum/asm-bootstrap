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

parse:
pline:
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
mov eax, 72
mov [rbp+44], eax
mov eax, 41
mov [rbp+48], eax
jmp.l prr
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
jmp.l pc32
d_add:
cmp al, 97
jnz.l d_c
movzx edx, byte [rbx+6]
cmp dl, 44
jz.l padd8
cmp dl, 32
jz.l padd8
mov eax, 0
mov [rbp+44], eax
mov eax, 1
mov [rbp+48], eax
jmp.l prr
padd8:
mov eax, 128
mov [rbp+44], eax
mov eax, 0
mov [rbp+48], eax
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
jmp.l pc32
d_i:
cmp al, 105
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
jmp.l pu8
d_i32:
mov eax, 255
mov [rbp+44], eax
mov eax, 0
mov [rbp+48], eax
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
cmp al, 106
jnz.l d_r
movzx edx, byte [rbx+1]
cmp dl, 98
jz.l jb3
cmp dl, 122
jz.l jz3
cmp dl, 110
jz.l jnz4
cmp dl, 109
jz.l jmp4
jmp.l fail
jb3:
mov eax, 114
mov [rbp+92], eax
jmp.l jscn
jz3:
mov eax, 116
mov [rbp+92], eax
jmp.l jscn
jnz4:
mov eax, 117
mov [rbp+92], eax
jmp.l jscn
jmp4:
mov eax, 235
mov [rbp+92], eax
jmp.l jscn
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
movzx eax, byte [rbx+2]
cmp al, 44
jz.l pmov8
cmp al, 32
jz.l pmov8
call reg32
mov [rbp+32], edx
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
mov eax, [rbp+32]
mov edx, 184
add eax, edx
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
jz.l regok
cmp al, 114
jnz.l fail
regok:
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
lea rbx, [rbx+1]
call skipsp
movzx eax, byte [rbx+1]
cmp al, 121
jz.l pzmem
call r8
mov eax, [rbp+32]
add eax, eax
add eax, eax
add eax, eax
add eax, edx
mov edx, 192
add eax, edx
mov [rbp+36], eax
mov eax, 15
call emital
mov eax, 182
call emital
mov eax, [rbp+36]
call emital
jmp.l pline

pmovrr:
call reg32
mov [rbp+36], edx
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
lea rbx, [rbx+1]
call skipsp
call reg32
mov [rbp+36], edx
mov eax, [rbp+44]
cmp al, 0
jz.l prr_nr
call emital
prr_nr:
mov eax, [rbp+48]
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

memop:
lea rbx, [rbx+1]
call reg32
mov [rbp+56], edx
mov eax, 0
mov [rbp+60], eax
movzx eax, byte [rbx]
cmp al, 93
jz.l memend
cmp al, 43
jnz.l memneg
lea rbx, [rbx+1]
jmp.l memnum
memneg:
cmp al, 45
jnz.l fail
memnum:
call expr
mov edx, 256
call chklim
mov [rbp+60], ecx
memend:
movzx eax, byte [rbx]
cmp al, 93
jnz.l fail
lea rbx, [rbx+1]
ret
ret
emitmem:
mov eax, [rbp+64]
add eax, eax
add eax, eax
add eax, eax
mov edx, [rbp+56]
add eax, edx
mov edx, [rbp+60]
cmp edx, 0
jz.l emmod1
mov edx, 64
add eax, edx
emmod1:
call emital
mov eax, [rbp+56]
cmp al, 4
jnz.l em_sib
mov eax, 36
call emital
em_sib:
mov eax, [rbp+60]
cmp al, 0
jz.l em_done
call emital
em_done:
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
mov eax, 139
call emital
call emitmem
jmp.l pline

plea:
lea rbx, [rbx+4]
movzx eax, byte [rbx]
mov edx, 0
cmp al, 114
jnz.l plea1
mov edx, 72
plea1:
mov [rbp+68], edx
call reg32
mov [rbp+64], edx
lea rbx, [rbx+1]
call skipsp
movzx eax, byte [rbx]
cmp al, 91
jnz.l fail
call memop
mov eax, [rbp+68]
cmp al, 0
jz.l plea2
call emital
plea2:
mov eax, 141
call emital
call emitmem
jmp.l pline

lblchk:
lea rdx, [rbx]
ls1:
movzx eax, byte [rdx]
cmp al, 58
jz.l lbldef
cmp al, 32
jz.l lcret
cmp al, 10
jz.l lcret
cmp al, 59
jz.l lcret
cmp al, 0
jz.l lcret
lea rdx, [rdx+1]
jmp.l ls1

lcret:
ret
lbldef:
call lcpy
lea rbx, [rbx+1]
movzx eax, byte [rbp+16]
cmp al, 0
jnz.l pline
mov eax, [rbp+80]
cmp eax, 256
jb.l lok
jmp.l fail
lok:
lea rcx, [rbp+1]
mov esi, 3861
sub rcx, rsi
mov edx, [rbp+80]
lget:
cmp edx, 0
jz.l lgoth
lea rcx, [rcx+12]
dec edx
jmp.l lget
lgoth:
mov eax, [rbp+72]
mov [rcx], eax
mov eax, [rbp+76]
mov [rcx+4], eax
mov eax, [rbp+20]
mov [rcx+8], eax
mov eax, [rbp+80]
inc eax
mov [rbp+80], eax
jmp.l pline

lcpy:
mov eax, 0
mov [rbp+72], eax
mov [rbp+76], eax
lea rcx, [rbp+72]
xor edx, edx
lcpyl:
movzx eax, byte [rbx]
cmp al, 58
jz.l lcpyd
cmp al, 32
jz.l lcpyd
cmp al, 10
jz.l lcpyd
cmp al, 0
jz.l lcpyd
cmp edx, 8
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
mov esi, 3861
sub rcx, rsi
mov edx, [rbp+80]
lfind:
cmp edx, 0
jz.l fail
mov eax, [rcx]
mov esi, [rbp+72]
xor eax, esi
mov edi, [rcx+4]
mov esi, [rbp+76]
xor edi, esi
add eax, edi
cmp eax, 0
jz.l lbfnd
lea rcx, [rcx+12]
dec edx
jmp.l lfind
lbfnd:
mov eax, [rcx+8]
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

pc32:
call reg32
mov [rbp+32], edx
lea rbx, [rbx+1]
call skipsp
call expr
mov [rbp+36], ecx
mov eax, [rbp+32]
mov edx, [rbp+48]
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
fail:
call msg
mov eax, 60
mov edi, 1
syscall
lku:
lea rcx, [rbp+1]
mov esi, 3861
sub rcx, rsi
mov edx, [rbp+80]
lkul:
cmp edx, 0
jz.l fail
mov eax, [rcx]
mov esi, [rbp+72]
xor eax, esi
mov edi, [rcx+4]
mov esi, [rbp+76]
xor edi, esi
add eax, edi
cmp eax, 0
jz.l lkux
lea rcx, [rcx+12]
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
mov eax, [rcx+8]
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
mov eax, [rcx+8]
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
jmp.l pc32
d_t:
cmp al, 116
jnz.l fail
lea rbx, [rbx+5]
mov eax, 247
mov [rbp+44], eax
mov eax, 0
mov [rbp+48], eax
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

lku0:
lea rcx, [rbp+1]
mov esi, 3861
sub rcx, rsi
mov edx, [rbp+80]
lk0l:
cmp edx, 0
jz.l lk0z
mov eax, [rcx]
mov esi, [rbp+72]
xor eax, esi
mov edi, [rcx+4]
mov esi, [rbp+76]
xor edi, esi
add eax, edi
cmp eax, 0
jz.l lk0f
lea rcx, [rcx+12]
dec edx
jmp.l lk0l
lk0f:
mov eax, [rcx+8]
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
