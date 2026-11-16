; asm1 — step 3: syscall / mov r32,imm32 / db, with a real ELF header.
;
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
mov eax, 0              ; SYS_read
mov edi, 0
lea rsi, [rbp+56]
mov edx, 4000
syscall
mov [rbp+28], eax       ; n
mov eax, 0
mov [rbp+16], eax       ; pass = 0 (count)
mov [rbp+20], eax       ; count = 0
lea rbx, [rbp+56]
mov ecx, [rbp+28]
term:
cmp ecx, 0
jz termd
lea rbx, [rbx+1]
dec ecx
jmp term
termd:
mov byte [rbx], 0
lea rbx, [rbp+56]       ; pass 0 starts at the beginning, not at the NUL
call parse

mov eax, [rbp+20]       ; filesz = 120 + count
mov ecx, 120
add eax, ecx
mov [rbp+24], eax
mov eax, 1              ; the header is written, not counted
mov [rbp+16], eax
mov ebx, 4194426        ; 0x40007a, the header template
mov eax, 96
mov [rbp+40], eax
hdr1:
movzx eax, byte [rbx]
call emital
lea rbx, [rbx+1]
mov eax, [rbp+40]
dec eax
mov [rbp+40], eax
cmp eax, 0
jnz.l hdr1
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
mov ebx, 4194538        ; 0x4000ea = 0x40007a + 112 (p_align)
mov eax, 8
mov [rbp+40], eax
hdr2:
movzx eax, byte [rbx]
call emital
lea rbx, [rbx+1]
mov eax, [rbp+40]
dec eax
mov [rbp+40], eax
cmp eax, 0
jnz.l hdr2

mov eax, 1              ; pass 1: emit
mov [rbp+16], eax
lea rbx, [rbp+56]
call parse
mov eax, 60
xor edi, edi
syscall

emital:
mov [rbp+8], al
movzx eax, byte [rbp+16]
cmp al, 0
jnz.l emit_w
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
cmp al, 115             ; 's'  syscall or sub
jnz.l d_m
movzx edx, byte [rbx+1]
cmp dl, 121             ; 'y'
jz.l psys
mov eax, 72             ; sub r64,r64: REX.W (0x48), opcode 29
mov [rbp+44], eax
mov eax, 41
mov [rbp+48], eax
jmp.l prr
d_m:
cmp al, 109             ; 'm'  mov or movzx
jnz.l d_d
movzx eax, byte [rbx+3]
cmp al, 122             ; 'z'
jz.l pzx
jmp.l pmov
d_d:
cmp al, 100             ; 'd'  db or div
jnz.l d_a
movzx edx, byte [rbx+1]
cmp dl, 98              ; 'b'
jz.l pdb
mov eax, 246            ; div r8: F6 /6
mov [rbp+44], eax
mov eax, 6
mov [rbp+48], eax
jmp.l pu8
d_a:
cmp al, 97              ; 'a'  add r8,imm8: 80 /0, with the al special case
jnz.l d_c
mov eax, 128
mov [rbp+44], eax
mov eax, 0
mov [rbp+48], eax
mov eax, 1
mov [rbp+52], eax
jmp.l p8i
d_c:
cmp al, 99              ; 'c'  cmp r8,imm8: 80 /7
jnz.l d_i
mov eax, 128
mov [rbp+44], eax
mov eax, 7
mov [rbp+48], eax
mov eax, 0
mov [rbp+52], eax
jmp.l p8i
d_i:
cmp al, 105             ; 'i'  inc r8: FE /0
jnz.l d_x
mov eax, 254
mov [rbp+44], eax
mov eax, 0
mov [rbp+48], eax
jmp.l pu8
d_x:
cmp al, 120             ; 'x'  xor r32,r32: 31 /r
jnz.l fail
mov eax, 0
mov [rbp+44], eax
mov eax, 49
mov [rbp+48], eax
jmp.l prr
psp:
lea rbx, [rbx+1]
jmp.l pline
peol:
lea rbx, [rbx+1]
jmp.l pline
pcom:
movzx eax, byte [rbx]
cmp al, 0
jz.l pdone
lea rbx, [rbx+1]
cmp al, 10
jnz.l pcom
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
movzx eax, byte [rbx+2]  ; a delimiter third means the name was 2 chars: 8-bit
cmp al, 44              ; ','
jz.l pmov8
cmp al, 32              ; ' '
jz.l pmov8
call reg32
mov [rbp+32], edx
lea rbx, [rbx+1]
call skipsp
movzx eax, byte [rbx]
cmp al, 101             ; 'e' => register source, not a number
jz.l pmovrr
cmp al, 114             ; 'r'
jz.l pmovrr
call num32
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
call num32
mov eax, ecx
call emital
dbnext:
movzx eax, byte [rbx]
cmp al, 44
jnz.l pline
lea rbx, [rbx+1]
call skipsp
call num32
mov eax, ecx
call emital
jmp.l dbnext

skipsp:
movzx eax, byte [rbx]
cmp al, 32
jnz.l pdone             ; shared ret
lea rbx, [rbx+1]
jmp.l skipsp

num32:                  ; decimal -> ecx ; 10x = 8x + 2x
xor ecx, ecx
ndigit:
movzx eax, byte [rbx]
add al, 100             ; -48 mod 256 in two steps: no sub r8,imm8, and
add al, 108             ;   immediates are range-checked to -128..127
cmp al, 10
jb.l ndig
jmp.l pdone
ndig:
mov edx, ecx
add edx, edx            ; 2x
add ecx, ecx            ; 2x
add ecx, ecx            ; 4x
add ecx, ecx            ; 8x
add ecx, edx            ; 10x
add ecx, eax            ; + digit (0..9)
lea rbx, [rbx+1]
jmp.l ndigit
reg32:                  ; e??/r?? -> edx = 0..7 ; matches the last two chars only
movzx eax, byte [rbx]
cmp al, 101             ; 'e'
jz.l regok
cmp al, 114             ; 'r'
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

r8:                     ; 8-bit register name -> edx ; consumes 2 chars
movzx edx, byte [rbx]
movzx ecx, byte [rbx+1]
add ecx, ecx            ; second char * 256, eight doublings (no shift in the dialect)
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

pmov8:                  ; mov r8,imm8 -> B0+code ib
call r8
mov [rbp+32], edx
lea rbx, [rbx+1]
call skipsp
call num32
mov [rbp+36], ecx       ; spill: emital's syscall destroys rcx
mov eax, [rbp+32]
mov edx, 176            ; 0xB0
add eax, edx
call emital
mov eax, [rbp+36]
call emital
jmp.l pline

pzx:                    ; movzx r32,r8 -> 0F B6 /r
lea rbx, [rbx+6]
call reg32
mov [rbp+32], edx
lea rbx, [rbx+1]
call skipsp
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

pmovrr:                 ; mov r32,r32 -> 89 /r (reg=source, rm=dest)
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

p8i:                    ; add/cmp r8,imm8 ; [rbp+44]=opcode [rbp+48]=digit [rbp+52]=al-special
lea rbx, [rbx+4]
call r8
mov [rbp+32], edx
lea rbx, [rbx+1]
call skipsp
call num32
mov [rbp+36], ecx
mov eax, [rbp+52]
cmp al, 0
jz.l p8gen
mov eax, [rbp+32]
cmp al, 0
jnz.l p8gen
mov eax, 4              ; add al,imm8 has its own opcode
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

pu8:                    ; inc/div r8 ; [rbp+44]=opcode [rbp+48]=digit
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

prr:                    ; reg,reg ; [rbp+44]=REX byte or 0 [rbp+48]=opcode
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

fail:
mov eax, 60
mov edi, 1
syscall
