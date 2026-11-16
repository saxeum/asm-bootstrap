; hello world — the wave-0 oracle program in symbolic form
; needs: labels, mov r32,<sym>, mov r32,<sym>.len, xor r32,r32, syscall, db, entry
entry _start

_start:
        mov eax, 1              ; SYS_write
        mov edi, 1              ; fd 1 = stdout
        mov esi, msg            ; buffer address, resolved from the label
        mov edx, msg.len        ; length, from the db directive
        syscall
        mov eax, 60             ; SYS_exit
        xor edi, edi            ; status 0
        syscall

msg:
        db "Hello, World!\n"
