; asm1 — step 3: syscall / mov r32,imm32 / db, with a real ELF header.
;
; "jmp start" occupies 0x400078-0x400079, so the embedded 120-byte header template
; sits at the fixed address 0x40007a and is copied out by a loop. That address is
; a constant only because it is at the very front of the image: it does not move
; when this program grows, which is the only reason a dialect with no
; label-as-immediate can read its own data at all.
;
; Two passes: pass 0 counts body bytes, because the ELF header needs filesz before
; the first body byte is written; pass 1 writes. The pass flag lives in memory at
; [rsp+8] because syscall destroys rcx and r11, and rax/rdx/rdi/rsi are arguments.

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
mov eax, 0              ; SYS_read
mov edi, 0
lea rsi, [rsp+120]
mov edx, 4000
syscall
mov [rsp+24], eax       ; n
mov eax, 0
mov [rsp+8], eax        ; pass = 0 (count)
mov [rsp+16], eax       ; count = 0
lea rbx, [rsp+120]
mov ecx, [rsp+24]
term:
cmp ecx, 0
jz termd
lea rbx, [rbx+1]
dec ecx
jmp term
termd:
mov byte [rbx], 0       ; NUL-terminate: no length bookkeeping in the parser
call parse

mov eax, [rsp+16]       ; filesz = 120 + count
mov ecx, 120
add eax, ecx
mov [rsp+20], eax
mov ebp, 96
mov edx, 4194426        ; 0x40007a
hdr1:
movzx eax, byte [rdx]
call emital
lea rdx, [rdx+1]
dec ebp
jnz hdr1
movzx eax, byte [rsp+20]
call emital
movzx eax, byte [rsp+21]
call emital
movzx eax, byte [rsp+22]
call emital
movzx eax, byte [rsp+23]
call emital
mov eax, 0
call emital
call emital
call emital
call emital
mov ebp, 16
mov edx, 4194522        ; 0x4000da = 0x40007a + 96
hdr2:
movzx eax, byte [rdx]
call emital
lea rdx, [rdx+1]
dec ebp
jnz hdr2

mov eax, 1              ; pass 1: emit
mov [rsp+8], eax
lea rbx, [rsp+120]
call parse
mov eax, 60
xor edi, edi
syscall

; ----------------------------------------------------------- emit one byte
emital:
mov [rsp], al
movzx eax, byte [rsp+8]
cmp al, 0
jnz emit_w
mov eax, [rsp+16]
inc eax
mov [rsp+16], eax
ret
emit_w:
mov eax, 1
mov edi, 1
lea rsi, [rsp]
mov edx, 1
syscall
ret

; ----------------------------------------------------------- parse
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
cmp al, 115             ; 's' syscall
jz psys
cmp al, 109             ; 'm' mov
jz pmov
cmp al, 100             ; 'd' db
jz pdb
jmp.l fail
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
jnz pcom
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
call reg32
mov [rsp+28], edx
lea rbx, [rbx+1]        ; past ','
call skipsp
call num32
mov [rsp+32], ecx
mov eax, [rsp+28]
mov edx, 184            ; 0xB8 + reg
add eax, edx
call emital
movzx eax, byte [rsp+32]
call emital
movzx eax, byte [rsp+33]
call emital
movzx eax, byte [rsp+34]
call emital
movzx eax, byte [rsp+35]
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
jnz.l dbdone
lea rbx, [rbx+1]
call skipsp
call num32
mov eax, ecx
call emital
jmp.l dbnext
dbdone:
jmp.l pline

; ----------------------------------------------------------- helpers
skipsp:
movzx eax, byte [rbx]
cmp al, 32
jnz skipd
lea rbx, [rbx+1]
jmp skipsp
skipd:
ret

num32:                  ; decimal -> ecx ; 10x = 8x + 2x
xor ecx, ecx
ndigit:
movzx eax, byte [rbx]
sub al, 48
cmp al, 10
jb ndig
jmp numdone
ndig:
mov edx, ecx
add edx, edx            ; 2x
add ecx, ecx            ; 2x
add ecx, ecx            ; 4x
add ecx, ecx            ; 8x
add ecx, edx            ; 10x
add ecx, eax            ; + digit (eax is 0..9 from movzx)
lea rbx, [rbx+1]
jmp ndigit
numdone:
ret

reg32:                  ; "xxx," -> edx = 0..7, rbx past the name
mov eax, [rbx]
mov edx, 7
cmp eax, 745104485
jz regret
mov edx, 6
cmp eax, 745108325
jz regret
mov edx, 5
cmp eax, 745562725
jz regret
mov edx, 4
cmp eax, 745567077
jz regret
mov edx, 3
cmp eax, 746087013
jz regret
mov edx, 2
cmp eax, 746087525
jz regret
mov edx, 1
cmp eax, 746087269
jz regret
mov edx, 0
cmp eax, 746086757
jz regret
jmp.l fail
regret:
lea rbx, [rbx+3]
ret

fail:
mov eax, 60
mov edi, 1
syscall
