mov eax, 60
mov bl, 3
mov cl, 0
top:
inc cl
dec bl
jnz top
movzx edi, cl
syscall
