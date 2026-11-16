; asm1's I/O skeleton: read all of stdin, then loop emitting one byte at a time.
; Uses only forms asm0a supports: mov r32,imm / mov r32,r32 / lea / cmp r32,imm32
; / jz / jmp / dec r32 / syscall / xor.  This is the shell asm1.s will grow inside.
mov eax, 0              ; SYS_read
mov edi, 0
lea rsi, [rsp]          ; buffer = stack, pointer not index
mov edx, 4096
syscall                 ; rax = n
mov ebx, eax            ; ebx = count remaining
lea rsi, [rsp]          ; rsi = input pointer
loop:
cmp ebx, 0
jz done
mov eax, 1              ; SYS_write
mov edi, 1
mov edx, 1
syscall                 ; write(1, rsi, 1)
lea rsi, [rsi+1]        ; advance the pointer
dec ebx
jmp loop
done:
mov eax, 60             ; SYS_exit
xor edi, edi
syscall
