mov edi, 1
mov bl, 1
top:
movzx eax, bl
mov cl, 10
div cl
movzx ecx, al
add al, 48
add ah, 48
mov [rsp], al
mov [rsp+1], ah
mov byte [rsp+2], 10
lea rsi, [rsp+1]
sub rsi, rcx
lea edx, [ecx+2]
mov eax, 1
syscall
inc bl
cmp bl, 11
jb top
mov eax, 60
xor edi, edi
syscall
