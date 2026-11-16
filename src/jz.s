mov eax, 60
mov edi, 5
mov ecx, 1
top:
dec ecx
jz done
mov edi, 99
done:
syscall
