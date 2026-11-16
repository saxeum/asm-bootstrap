main:
mov eax, 1
mov edi, 1
mov esi, 4194424+m1
mov edx, m1end-m1
syscall
mov eax, 60
mov edi, 0
syscall
m1:
db "Hello, World!\n"
m1end:
