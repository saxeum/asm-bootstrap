; wave 2b fixture: a FORWARD jump, i.e. a reference to a label not yet defined.
; This is the smallest program that forces two passes. Exits 7.
; If the jump is not emitted, control falls into `mov edi, 99` and exits 99.
        mov eax, 60
        jmp skip
        mov edi, 99
skip:
        mov edi, 7
        syscall
