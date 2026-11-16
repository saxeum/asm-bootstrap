; wave 2d-15: call rel32 and ret
jmp.l main
foo:
mov eax, 60
mov edi, 9
ret
main:
call foo
mov eax, 60
mov edi, 7
syscall
