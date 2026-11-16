mov eax, 1
mov edi, 1
mov esi, 4194455
mov edx, 14
syscall
mov eax, 60
xor edi, edi
syscall
db "Hello, World!\n"
