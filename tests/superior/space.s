buf:
space 4
entry start
start:
mov ecx, 4194424+buf
movzx edi, byte [rcx]
mov eax, 60
syscall
