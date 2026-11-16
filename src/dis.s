; dis.s — the branch decoder, written in the dialect and assembled by asm1.
;
; Why it exists: the branch-pin gate decoded asm0a with objdump, and a
; disassembler is the tool this project replaces, so it cannot be the thing
; that verifies us. This is the decoder the gate is allowed to use.
;
; Interface, and it is deliberately one site per run:
;
;     ./dis <site> < binary
;
;   <site> is a hex byte offset into the input, with or without a 0x prefix.
;   The binary arrives on stdin. One line goes to stdout:
;
;     dis <site> < asm0a      ->  0x142 0x373 jmp
;
;   which is the shape of docs/branches.tsv, so the gate can compare bytes.
;
; It decodes exactly what the gate consumes and nothing else:
;
;     EB        jmp rel8       E9        jmp rel32     E8  call rel32
;     70-7F     jcc rel8       0F 80-8F  jcc rel32
;
;   target = site + instruction length + displacement, printed as lowercase
;   hex with no zero padding.
;
; Refusals. Every one exits 1 with NOTHING on stdout and one reason on stderr,
; where the reason is one of six words:
;
;   offset  no argument, or an argument that is not a hex offset
;   input   the input could not be read, or is larger than the buffer
;   site    the site is not a byte offset inside the input
;   form    the bytes there are not one of the forms above
;   trunc   the instruction would run past the end of the input
;   target  the computed target is not a byte in the input
;
; (trunc) and (target) are the truncation rule: a decoder that reads past its
; input has the same defect as an assembler that emits a prefix. It is also what
; makes negative targets impossible to print by accident -- target >= size is
; refused, and a branch before the start of the file wraps to a huge unsigned
; value.
;
; FRAME. rbp = rsp after the three pops that take argc/argv off the stack, so
; every slot below is in the argv/env area and nothing pushes over it.
;   [rbp+8]   input size      [rbp+16]  site offset
;   [rbp+24]  hex accumulator [rbp+32]  hex digits seen
;   [rbp+48]  table offset    [rbp+56]  target
;   [rbp+64]  scratch         [rbp+72]  scratch
;   [rbp+80]  output fd       [rbp+88]  hex: started flag
;   [rbp+96]  hex: value      [rbp+104] hex: nibbles left
;   [rbp+112] refusal reason  [rbp+124] putch's byte -- the one slot that
;                                       cannot be moved
;
; The input buffer lives BELOW rsp, 40 000 bytes at rbp-40000, and is filled
; 120 bytes at a time: one large read does not work, because the kernel only
; copies into pages it has already mapped below rsp (measured, see ROADMAP).

start:
pop rcx                 ; argc
pop rax                 ; argv[0]
pop rbx                 ; argv[1]: the site, as text
lea rbp, [rsp]
mov eax, 1
mov [rbp+80], eax       ; stdout
mov eax, 0
mov [rbp+24], eax       ; accumulator -- and it must start at zero, not at
mov [rbp+32], eax       ; whatever the env area happened to hold
cmp ecx, 2
jb.l r_off

; ---- the site offset, parsed from argv[1] ------------------------------
; "0x" is optional; every other character must be a hex digit, and an empty
; offset is refused rather than read as zero ("0x" is not a site).
movzx eax, byte [rbx]
cmp eax, 48
jnz.l ph_loop
movzx eax, byte [rbx+1]
cmp eax, 120            ; 'x'
jz ph_skip
cmp eax, 88             ; 'X'
jnz.l ph_loop
ph_skip:
lea rbx, [rbx+2]
ph_loop:
movzx eax, byte [rbx]
cmp eax, 0
jz.l ph_done
mov edx, eax
add dl, -48             ; c - '0', wrapped: 0..9 only for a digit
cmp dl, 10
jb ph_dig
mov edx, eax
add dl, -97             ; c - 'a'
cmp dl, 6
jb ph_low
mov edx, eax
add dl, -65             ; c - 'A'
cmp dl, 6
jb ph_up
jmp.l r_off
ph_dig:
mov edx, eax
mov ecx, 48
sub edx, ecx
jmp ph_acc
ph_low:
mov edx, eax
mov ecx, 87             ; 'a' - 10
sub edx, ecx
jmp ph_acc
ph_up:
mov edx, eax
mov ecx, 55             ; 'A' - 10
sub edx, ecx
ph_acc:
mov eax, [rbp+24]
add eax, eax
add eax, eax
add eax, eax
add eax, eax
add eax, edx
mov [rbp+24], eax
mov ecx, [rbp+32]
inc ecx
mov [rbp+32], ecx
lea rbx, [rbx+1]
jmp ph_loop
ph_done:
mov ecx, [rbp+32]
cmp ecx, 0
jz.l r_off
mov eax, [rbp+24]
mov [rbp+16], eax

; ---- read the whole input into the buffer -----------------------------
inbuf:
lea rbx, [rbp+1]
mov ecx, 40001
sub rbx, rcx            ; rbx = rbp - 40000
lea rsi, [rbx]
mov eax, 0
mov [rbp+8], eax
rdloop:
mov eax, 0              ; read
mov edi, 0
mov edx, 120
syscall
cmp eax, 120
jb rddone               ; short read: end of input
jz rdmore
jmp.l r_in              ; a read error, not a prefix to guess at
rdmore:
mov ecx, [rbp+8]
mov edx, 120
add ecx, edx
mov [rbp+8], ecx
mov edx, 39000
cmp ecx, edx
jb rdnext
jmp.l r_in              ; bigger than the buffer: refused, not truncated
rdnext:
lea rsi, [rsi+120]
jmp rdloop
rddone:
mov ecx, [rbp+8]
add ecx, eax
mov [rbp+8], ecx

; ---- dispatch on the opcode at the site -------------------------------
doff:
mov eax, [rbp+16]
mov ecx, [rbp+8]
cmp eax, ecx
jb doff_ok
jmp.l r_site
doff_ok:
lea rsi, [rbx+rax]      ; rsi = input + site
movzx eax, byte [rsi]
mov ecx, 112            ; 0x70: the jcc rel8 block starts here
sub eax, ecx            ; eax = op - 0x70, unsigned, so below it is huge
cmp eax, 16
jb.l d_cc8
add eax, ecx            ; back to the opcode
cmp eax, 235
jz.l d_eb
cmp eax, 233
jz.l d_e9
cmp eax, 232
jz.l d_e8
cmp eax, 15
jz.l d_0f
jmp.l r_form

; the table is 18 slots of 5 bytes: a length byte and up to four letters.
; slot = cc * 5, which is cc * 4 + cc.
d_cc8:
mov ecx, eax
add eax, eax
add eax, eax
add eax, ecx
mov [rbp+48], eax
mov edx, 2
call chkbnd
jmp.l d_re8

d_eb:
mov eax, 80             ; 16 * 5: jmp
mov [rbp+48], eax
mov edx, 2
call chkbnd
jmp.l d_re8

d_e9:
mov eax, 80             ; 16 * 5: jmp
mov [rbp+48], eax
mov edx, 5
call chkbnd
jmp.l d_re32

d_e8:
mov eax, 85             ; 17 * 5: call
mov [rbp+48], eax
mov edx, 5
call chkbnd
jmp.l d_re32

; 0F 8x. The bounds check comes first, because the second byte is only
; readable once site + 6 <= size has been established.
d_0f:
mov edx, 6
call chkbnd
movzx eax, byte [rsi+1]
mov ecx, 128
sub eax, ecx
cmp eax, 16
jb d_0f_cc
jmp.l r_form
d_0f_cc:
mov ecx, eax
add eax, eax
add eax, eax
add eax, ecx
mov [rbp+48], eax
lea rsi, [rsi+1]        ; so every form reads its displacement at [rsi+1]
jmp.l d_re32

; site + len must be inside the input, or the displacement bytes are not
; ours to read. edx in, [rbp+72] = site + len out.
chkbnd:
mov eax, [rbp+16]
add eax, edx
mov ecx, [rbp+8]
cmp eax, ecx
jb cb_ok
jz cb_ok
jmp.l r_trunc
cb_ok:
mov [rbp+72], eax
ret

; ---- displacement, target ---------------------------------------------
d_re8:
movzx edx, byte [rsi+1]
test edx, 128
jz.l d_sum
or edx, 4294967040     ; 0xffffff00: sign-extend the byte
jmp.l d_sum
d_re32:
mov edx, [rsi+1]        ; the four bytes in one load, little-endian
d_sum:
mov eax, [rbp+72]       ; site + length
add eax, edx
mov ecx, [rbp+8]
cmp eax, ecx
jb d_tok
jmp.l r_tgt              ; the target is not a byte in this input
d_tok:
mov [rbp+56], eax

; ---- print: site, target, mnemonic ------------------------------------
mov eax, 48
call putch
mov eax, 120
call putch
mov edx, [rbp+16]
call prhex
mov eax, 32
call putch
mov eax, 48
call putch
mov eax, 120
call putch
mov edx, [rbp+56]
call prhex
mov eax, 32
call putch
mov eax, 4194424+cc_tab ; 0x400078, the first body byte
mov ecx, [rbp+48]
add eax, ecx
call putmn
mov eax, 10
call putch
mov eax, 60
mov edi, 0
syscall

; ---- refusals: each one says which rule fired ---------------------------
; Six words, one per reason, in 8-byte slots indexed by reason number. The
; refusal is the only thing on stderr; stdout stays untouched, because a gate
; comparing a line must never have to delete a diagnostic first.
r_site:
mov eax, 0
jmp.l setr
r_form:
mov eax, 1
jmp.l setr
r_trunc:
mov eax, 2
jmp.l setr
r_tgt:
mov eax, 3
jmp.l setr
r_off:
mov eax, 4
jmp.l setr
r_in:
mov eax, 5
jmp.l setr
setr:
mov [rbp+112], eax
mov eax, 2
mov [rbp+80], eax       ; stderr: the refusal goes where complaints go
mov eax, 4194424+msg_pre
call putmn
mov eax, [rbp+112]
add eax, eax
add eax, eax
add eax, eax            ; reason * 8
mov ecx, 4194424+re_tab
add eax, ecx
call putmn
mov eax, 10
call putch
mov eax, 60
mov edi, 1
syscall

; ---- output primitives ------------------------------------------------
; One byte, to the fd in [rbp+80]. It clobbers rax, rcx, rdx, rsi, rdi, so
; everything that has to survive it lives in memory.
putch:
mov [rbp+124], al
mov eax, 1
mov edi, [rbp+80]
lea rsi, [rbp+124]
mov edx, 1
syscall
ret

; A length-prefixed string: byte 0 is the count, the bytes follow.
putmn:
mov [rbp+64], eax
movzx edx, byte [rax]
mov [rbp+72], edx
putmn_l:
mov ecx, [rbp+72]
cmp ecx, 0
jz putmn_d
mov eax, [rbp+64]
movzx eax, byte [rax+1]
call putch
mov eax, [rbp+64]
lea eax, [eax+1]
mov [rbp+64], eax
mov ecx, [rbp+72]
dec ecx
mov [rbp+72], ecx
jmp putmn_l
putmn_d:
ret

; edx as lowercase hex, most significant nibble first, leading zeros
; suppressed, and "0" for zero. Eight nibbles, shifted out four bits at a
; time -- a 32-bit shift by an immediate is what the dialect has.
prhex:
mov eax, 0
mov [rbp+88], eax
mov [rbp+96], edx
mov eax, 8
mov [rbp+104], eax
prhex_l:
mov eax, [rbp+96]
shr eax, 28
call hxdig
mov edx, [rbp+96]
shl edx, 4
mov [rbp+96], edx
mov ecx, [rbp+104]
dec ecx
mov [rbp+104], ecx
cmp ecx, 0
jnz prhex_l
mov ecx, [rbp+88]
cmp ecx, 0
jnz prhex_d
mov eax, 48
call putch
prhex_d:
ret

; eax = one nibble, 0..15.
hxdig:
cmp eax, 0
jnz hxd_p
mov ecx, [rbp+88]
cmp ecx, 0
jz hxd_r
hxd_p:
mov ecx, 1
mov [rbp+88], ecx
cmp eax, 10
jb hxd_num
mov ecx, 87             ; 'a' - 10
add eax, ecx
call putch
ret
hxd_num:
mov ecx, 48
add eax, ecx
call putch
ret
hxd_r:
ret

; ---- data -------------------------------------------------------------
; 5-byte slots, indexed by the condition code: len, letters, padding.
; The names are the ones docs/branches.tsv records, so the gate compares
; bytes with the pinned table rather than with a re-spelling of it.
cc_tab:
db 2, 106, 111, 0, 0            ; jo
db 3, 106, 110, 111, 0          ; jno
db 2, 106, 98, 0, 0             ; jb
db 3, 106, 97, 101, 0           ; jae
db 2, 106, 101, 0, 0            ; je
db 3, 106, 110, 101, 0          ; jne
db 3, 106, 98, 101, 0           ; jbe
db 2, 106, 97, 0, 0             ; ja
db 2, 106, 115, 0, 0            ; js
db 3, 106, 110, 115, 0          ; jns
db 2, 106, 112, 0, 0            ; jp
db 3, 106, 110, 112, 0          ; jnp
db 2, 106, 108, 0, 0            ; jl
db 3, 106, 103, 101, 0          ; jge
db 3, 106, 108, 101, 0          ; jle
db 2, 106, 103, 0, 0            ; jg
db 3, 106, 109, 112, 0          ; jmp
db 4, 99, 97, 108, 108          ; call
msg_pre:
db 5
db "dis: "
; reason slots: 4 site, 1 form, 2 trunc, 3 target, 4 offset, 5 input
re_tab:
db 4, 115, 105, 116, 101, 0, 0, 0               ; site
db 4, 102, 111, 114, 109, 0, 0, 0               ; form
db 5, 116, 114, 117, 110, 99, 0, 0              ; trunc
db 6, 116, 97, 114, 103, 101, 116, 0            ; target
db 6, 111, 102, 102, 115, 101, 116, 0           ; offset
db 5, 105, 110, 112, 117, 116, 0, 0             ; input
