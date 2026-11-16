; The same program as tests/golden/loop.c, written by hand in the dialect.
; Its output is the oracle for the compiled one: two sources, one behaviour.
; Nothing here is produced by cc -- that is the point.
start:
mov r12, 10
loop:
cmp r12, 0
jz.l loopend
mov eax, 1
mov edi, 1
mov esi, 4194424+dot
mov edx, dotend-dot
syscall
mov ecx, 1
sub r12, rcx
jmp.l loop
loopend:
mov eax, 60
mov edi, 0
syscall
dot:
db "."
dotend:
