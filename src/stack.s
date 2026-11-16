mov eax, 1
mov edi, 1
mov bl, 72
mov [rsp], bl
mov byte [rsp+1], 10
lea rsi, [rsp]
mov edx, 2
syscall
mov eax, 60
xor edi, edi
syscall
