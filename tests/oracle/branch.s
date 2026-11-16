; The same program as tests/golden/branch.c, written by hand in the dialect:
; five characters, a dash where x == 2. Its output is the oracle for the
; compiled one -- two sources, one behaviour, neither derived from the other.
start:
mov r12, 0
loop:
mov eax, r12d
cmp eax, 5
jb body
jmp.l done
body:
mov eax, r12d
cmp eax, 2
jz isdash
mov eax, 1
mov edi, 1
mov esi, 4194424+dot
mov edx, dotend-dot
syscall
jmp.l next
isdash:
mov eax, 1
mov edi, 1
mov esi, 4194424+dash
mov edx, dashend-dash
syscall
next:
lea r12, [r12+1]
jmp.l loop
done:
mov eax, 60
mov edi, 0
syscall
dot:
db "."
dotend:
dash:
db "-"
dashend:
