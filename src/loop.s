mov eax, 60
xor edi, edi
mov ecx, 10
top:
inc edi
dec ecx
jnz top
syscall
