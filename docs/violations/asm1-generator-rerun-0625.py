import struct

hdr = bytearray(open('/home/george/soper/genesis/ref/addr32', 'rb').read()[:120])
hdr[96:112] = b'\0' * 16
assert len(hdr) == 120
blob = '\n'.join('db ' + ', '.join(str(b) for b in hdr[i:i + 16]) for i in range(0, 120, 16))

regs = ['eax', 'ecx', 'edx', 'ebx', 'esp', 'ebp', 'esi', 'edi']
lit = {r: struct.unpack('<I', (r + ',').encode())[0] for r in regs}
chain = []
for i, r in reversed(list(enumerate(regs))):
    chain += [f'mov edx, {i}', f'cmp eax, {lit[r]}', 'jz.l regret']
regchain = '\n'.join(chain)

src = f'''; asm1 — step 3: syscall / mov r32,imm32 / db, with a real ELF header.
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
{blob}
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
cmp al, 115             ; 's'
jz.l psys
cmp al, 109             ; 'm'
jz.l pmov
cmp al, 100             ; 'd'
jz.l pdb
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
call reg32
mov [rbp+32], edx
lea rbx, [rbx+1]
call skipsp
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
jnz.l dbdone
lea rbx, [rbx+1]
call skipsp
call num32
mov eax, ecx
call emital
jmp.l dbnext
dbdone:
jmp.l pline

skipsp:
movzx eax, byte [rbx]
cmp al, 32
jnz.l skipd
lea rbx, [rbx+1]
jmp.l skipsp
skipd:
ret

num32:                  ; decimal -> ecx ; 10x = 8x + 2x
xor ecx, ecx
ndigit:
movzx eax, byte [rbx]
add al, 100             ; -48 mod 256 in two steps: no sub r8,imm8, and
add al, 108             ;   immediates are range-checked to -128..127
cmp al, 10
jb.l ndig
jmp.l numdone
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
numdone:
ret

reg32:
mov eax, [rbx]
{regchain}
jmp.l fail
regret:
lea rbx, [rbx+3]
ret

fail:
mov eax, 60
mov edi, 1
syscall
'''

open('/tmp/g2_out.s', 'w').write(src)
print('wrote src/asm1.s', len(src.splitlines()), 'lines')
