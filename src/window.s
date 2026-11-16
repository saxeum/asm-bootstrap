; probe: can an assembler written in this dialect read its input?
; no movzx-from-memory exists, so load 4 bytes and compare the whole word.
mov eax, 0              ; SYS_read
mov edi, 0
lea rsi, [rsp]          ; buffer = stack
mov edx, 16
syscall
lea rsi, [rsp]
mov eax, [rsi]          ; 4-byte window
cmp eax, 544632685      ; "mov "
jz ismov
cmp eax, 1953069157     ; "exit"
jz isexit
mov edi, 1
jmp done
ismov:
mov edi, 2
jmp done
isexit:
mov edi, 3
done:
mov eax, 60
syscall
