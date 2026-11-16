; asm1 — step 2: line awareness.  Copies input to output with ';' comments
; removed.  Spaces, blank lines and newlines pass through unchanged.
;
; Registers: rbx = input pointer, ebp = bytes remaining, rsi = write buffer,
; rax/rdx/rdi = scratch.  rcx is NOT used for anything that must survive: the
; kernel puts the return address in rcx, so syscall destroys it.
;
; rbx, not rbp, is the pointer on purpose: the encoder emits mod=00/rm=101
; (RIP-relative) for a zero displacement off rbp.  rbx has no such case.

mov eax, 0              ; SYS_read
mov edi, 0
lea rsi, [rsp+120]
mov edx, 4000
syscall
mov ebp, eax            ; bytes remaining
lea rbx, [rsp+120]      ; input pointer

line:
cmp ebp, 0
jz.l done
movzx eax, byte [rbx]
cmp al, 10              ; newline: pass it through
jz eol
cmp al, 59              ; ';' starts a comment
jz toend

lea rsi, [rbx]          ; ordinary byte: write it straight from the buffer
mov eax, 1
mov edi, 1
mov edx, 1
syscall
lea rbx, [rbx+1]
dec ebp
jmp line

eol:
mov byte [rsp], 10
lea rsi, [rsp]
mov eax, 1
mov edi, 1
mov edx, 1
syscall
lea rbx, [rbx+1]
dec ebp
jmp line

toend:
cmp ebp, 0
jz.l done
movzx eax, byte [rbx]
cmp al, 10              ; stop AT the newline, so eol emits it
jz eol
lea rbx, [rbx+1]
dec ebp
jmp toend

done:
mov eax, 60
xor edi, edi
syscall
