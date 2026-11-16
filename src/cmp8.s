mov eax, 60
mov bl, 0
mov cl, 5
top:
add bl, 3
dec cl
cmp cl, 2
jb done
jmp top
done:
movzx edi, bl
syscall
