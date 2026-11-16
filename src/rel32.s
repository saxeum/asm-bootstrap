mov eax, 60
jmp.l start
mov edi, 99
start:
mov bl, 3
mov cl, 0
top:
inc cl
dec bl
jnz.l top
movzx edi, cl
syscall
