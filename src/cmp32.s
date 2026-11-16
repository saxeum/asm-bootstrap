mov eax, 60
mov ebx, 7
cmp ebx, 7
jz ok
mov edi, 99
ok:
mov edi, ebx
syscall
