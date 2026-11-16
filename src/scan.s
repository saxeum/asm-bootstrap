; step 2 of asm1.s, de-risked: find the end of the first line by reading BYTES.
; This is what movzx r32,byte [mem] was added for.
mov eax, 0              ; SYS_read
mov edi, 0
lea rsi, [rsp]
mov edx, 64
syscall
lea rsi, [rsp]
xor ebx, ebx            ; length = 0
loop:
cmp ebx, 64             ; safety bound
jz done
movzx eax, byte [rsi]   ; <- one byte
cmp al, 10
jz done
inc ebx
lea rsi, [rsi+1]
jmp loop
done:
mov eax, 60
mov edi, ebx
syscall
