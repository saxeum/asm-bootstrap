; The same program as tests/golden/twovars.c, written by hand in the dialect:
; two counters, dots while a < 3, then a bang because b == 2.
start:
mov r12, 0              ; a
mov r13, 5              ; b
loop:
mov eax, r12d
cmp eax, 3
jb body
jmp.l done
body:
mov eax, 1
mov edi, 1
mov esi, 4194424+dot
mov edx, dotend-dot
syscall
lea r12, [r12+1]        ; a = a + 1
mov ecx, 1
sub r13, rcx            ; b = b - 1
jmp.l loop
done:
mov eax, r13d
cmp eax, 2
jz yes
mov eax, 1
mov edi, 1
mov esi, 4194424+q
mov edx, qend-q
syscall
jmp.l out
yes:
mov eax, 1
mov edi, 1
mov esi, 4194424+bang
mov edx, bangend-bang
syscall
out:
mov eax, 60
mov edi, 0
syscall
dot:
db "."
dotend:
bang:
db "!"
bangend:
q:
db "?"
qend:
