; cc.s -- the compiler, stage 0: a C subset to this dialect, as TEXT.
;
;     ./cc < program.c > program.s
;     ./asm1 < program.s > program
;
; It emits dialect source, not machine code. That is the design: the output is
; a reviewable file, the assembler stays the only thing that produces bytes, and
; every gate the assembler already has applies to what the compiler writes.
;
; The subset, exactly (docs/cc.md has the grammar and the reasons):
;
;     int main(void) { write("..."); ... return N; }
;
;   * `int main(void)` is the only function, and `(void)` is required
;   * `write("literal");` is a STATEMENT, not a call: there is no calling
;     convention yet, so it cannot be one. Up to nine of them.
;   * `return N;` is optional and must be last; the exit code is one byte, so
;     N above 255 truncates exactly as exit(300) does
;   * whitespace, /* */ and // comments anywhere between tokens
;
; Anything else is REFUSED: exit 1, a reason on stderr, not one byte on stdout.
; The output is built in a buffer and written once at the end, which is what
; makes that guarantee cheap -- a compiler emitting a prefix of a program has
; the same defect as an assembler emitting a prefix of a binary.
;
; FRAME. rbp = rsp after the pops that discard argv. Slots:
;   [rbp+8] input size   [rbp+12] input cursor  [rbp+16] output length
;   [rbp+20] literals    [rbp+24] saw return    [rbp+28] scratch
;   [rbp+32] lit offset  [rbp+36] lit length    [rbp+40] scratch
;   [rbp+44] scratch     [rbp+48] exit value    [rbp+52] scratch
;   [rbp+56] emit byte   [rbp+60] emit pointer  [rbp+64] number
;   [rbp+68] scratch     [rbp+72] want pointer  [rbp+76] want byte
;   [rbp+80] number      [rbp+84] digits
; Buffers, all below rsp: input rbp-40000 (8192), output rbp-30000 (8192),
; literal table rbp-20000 (9 entries of offset+length).

start:
pop rax
pop rax                 ; argv[0], discarded: cc takes no arguments
lea rbp, [rsp]
mov ecx, 320
sub rsp, rcx            ; reserve: every call pushes at rbp-8, -16, ... and the
                        ; state slots live at -100..-264. Without this, a call
                        ; chain deeper than twelve overwrites them.
mov eax, 0
mov [rbp+12], eax
mov [rbp+8], eax
mov [rbp+16], eax
mov [rbp+20], eax
mov [rbp+24], eax
mov [rbp+48], eax
mov eax, 0
mov [rbp+96], eax
mov [rbp-108], eax      ; no variables declared yet
mov [rbp-208], eax      ; not inside an argument list
mov [rbp-236], eax      ; not inside a subscript
mov eax, 264
mov [rbp-320], eax      ; the first free byte above the scalar slots
mov eax, 0
mov eax, 1
mov [rbp-292], eax      ; a call at depth 0 evaluates its arguments at depth 1
mov eax, 0
mov [rbp+112], eax
mov [rbp+116], eax

; ---- read the whole input -----------------------------------------------
lea rsi, [rbp+1]
mov ecx, 40001
sub rsi, rcx            ; rsi = input base
rdloop:
mov eax, 0
mov edi, 0
mov edx, 120
syscall
cmp eax, 120
jb rddone
jz rdmore
jmp.l fail              ; a read error is not a prefix to guess at
rdmore:
mov ecx, [rbp+8]
mov edx, 120
add ecx, edx
mov [rbp+8], ecx
mov edx, 8000
cmp ecx, edx
jb rdnext
jmp.l fail              ; larger than the buffer: refuse, never truncate
rdnext:
lea rsi, [rsi+120]
jmp rdloop
rddone:
mov ecx, [rbp+8]
add ecx, eax
mov [rbp+8], ecx

; ---- function definitions, one after another ----------------------------
; Calling convention, and this is all of it:
;   * arguments in rdi, rsi, rdx, rcx -- four, left to right
;   * the return value in eax
;   * the callee copies each argument into a local at entry, so the argument
;     registers are dead after the prologue and a syscall in the body cannot
;     corrupt them (syscall destroys rcx)
;   * every function owns rbp: push rbp / mov rbp, rsp / sub rsp, 64, restored
;     before ret. 64 bytes is eight variables of eight: the symbol table's whole
;     capacity, so the frame cannot be too small
;   * nothing is callee-saved, because nothing is live across a call: the
;     expression temporaries are eax, ecx, r8d, r9d, r10d, r11d and no argument
;     register is among them
;   * `main` exits, every other function returns, and `entry main` tells the
;     assembler where execution starts when main is not the first function
mov esi, 4194424+f_hdr
call emitstr
fnloop:
call skipws
call gcur
cmp al, 0
jz.l fndone
mov esi, 4194424+f_int
call want
call ident
call emitname
mov esi, 4194424+f_dcol
call emitstr
mov eax, 0
mov [rbp-164], eax      ; 1 when this function is main
mov eax, 0
mov [rbp+24], eax       ; no return seen in this function yet
mov eax, 0
mov [rbp-108], eax      ; a fresh symbol table for this function
lea rdx, [rbp-16064]
mov eax, [rdx]
mov ecx, 1852399981     ; "main", four bytes little-endian
cmp eax, ecx
jnz fnnm
mov eax, 1
mov [rbp-164], eax
fnnm:
mov esi, 4194424+f_lpar
call want
mov esi, 4194424+f_void
call isword
cmp eax, 0
jnz fnpdone
fnparm:
mov esi, 4194424+f_int
call want
call ident
call defvar
call skipws
call gcur
cmp al, 44
jnz fnpdone
mov eax, 1
call bump
jmp fnparm
fnpdone:
mov esi, 4194424+f_rpar
call want
mov esi, 4194424+f_lbrc
call want
mov esi, 4194424+f_pro
call emitstr
mov eax, 0
mov [rbp-176], eax      ; copy the parameters in from their argument registers
argcl:
mov eax, [rbp-176]
mov ecx, [rbp-108]
cmp eax, ecx
jz argcd
call eargc
mov eax, [rbp-176]
inc eax
mov [rbp-176], eax
jmp argcl
argcd:
call body
mov eax, [rbp+24]
cmp eax, 0
jnz fnnext              ; the body returned and emitted its own exit
mov eax, 0
call emitret            ; fell off the end: return 0
fnnext:
jmp.l fnloop
fndone:
mov esi, 4194424+f_entry
call emitstr
call lits
call skipws
call gcur
cmp al, 0               ; nothing may follow the last function
jnz.l fail
call flush
mov eax, 60
mov edi, 0
syscall

; eargc: copy the parameter whose index is in eax from its argument register
; into its local, so the argument registers are dead after the prologue
eargc:
mov [rbp-168], eax
mov esi, 4194424+f_arg1
call emitstr
mov eax, [rbp-168]
call varoff
call emitnum
mov esi, 4194424+f_arg2
call emitstr
mov eax, [rbp-168]
call emitarg
mov esi, 4194424+f_nl
call emitstr
ret

; emitarg: the name of argument register eax
emitarg:
cmp eax, 4
jb eargok
jmp.l fail              ; more than four arguments
eargok:
add eax, eax
add eax, eax
mov ecx, 4194424+argnames
add eax, ecx
mov [rbp-144], eax
mov eax, 0
mov [rbp-148], eax
eagl:
mov eax, [rbp-148]
mov ecx, 3
cmp eax, ecx
jz eagd
mov eax, [rbp-144]
mov ecx, [rbp-148]
add eax, ecx
movzx eax, byte [rax]
call emitc
mov eax, [rbp-148]
inc eax
mov [rbp-148], eax
jmp eagl
eagd:
ret

; callargs: the cursor is at '(' ; emits the arguments, then "call <name>".
; The name is saved across the arguments because an argument may itself be a
; call, and every ident reuses the same name buffer.
callargs:
lea rdx, [rbp-16064]
mov eax, [rdx]
mov [rbp-200], eax
mov eax, [rdx+4]
mov [rbp-204], eax
mov eax, [rdx+8]
mov [rbp-216], eax
mov eax, [rdx+12]
mov [rbp-220], eax
mov eax, 1
call bump
mov eax, 0
mov [rbp-168], eax
call skipws
call gcur
cmp al, 41              ; no arguments
jz cardskip
mov eax, 1
mov [rbp-208], eax
cargloop:
mov eax, [rbp-292]     ; the argument's depth: one deeper than the call's
call exprd
mov esi, 4194424+f_mov
call emitstr
mov eax, [rbp-168]
call emitarg
mov esi, 4194424+f_sep
call emitstr
mov eax, [rbp-292]
call emitreg
mov esi, 4194424+f_nl
call emitstr
mov eax, [rbp-168]
inc eax
mov [rbp-168], eax
call skipws
call gcur
cmp al, 44
jnz cardskip
mov eax, 1
call bump
jmp cargloop
cardskip:
mov esi, 4194424+f_rpar
call want
lea rdx, [rbp-16064]
mov eax, [rbp-200]
mov [rdx], eax
mov eax, [rbp-204]
mov [rdx+4], eax
mov eax, [rbp-216]
mov [rdx+8], eax
mov eax, [rbp-220]
mov [rdx+12], eax
mov eax, 0
mov [rbp-208], eax
mov esi, 4194424+f_callk
call emitstr
call emitname
mov esi, 4194424+f_nl
call emitstr
ret

; emitret: the value is in eax; main exits, everything else returns
emitret:
mov eax, [rbp-164]
cmp eax, 0
jz erret
mov esi, 4194424+f_edi
call emitstr
ret
erret:
mov esi, 4194424+f_epi
call emitstr
ret

; emitname: the current name, from the buffer. The address lives in a 64-bit
; slot because emitc clobbers rdx and a truncated pointer would be fatal.
emitname:
lea rax, [rbp-16064]
mov [rbp-192], rax
emnl:
mov rax, [rbp-192]
movzx eax, byte [rax]
cmp eax, 0
jz emnd
call emitc
mov rax, [rbp-192]
inc rax
mov [rbp-192], rax
jmp emnl
emnd:
ret

; ---- statements until '}' -----------------------------------------------
; ---- statements until '}', which is consumed on the way out --------------
; `body` is recursive: a `while` block calls it, so nesting needs no special
; case and the closing brace is consumed by whoever opened the block.
body:
mov eax, [rbp+112]
inc eax
mov [rbp+112], eax
bodloop:
call skipws
call gcur
cmp al, 125
jz.l bodend
; dispatch on the whole word, because `write` and `while` share a first letter
mov esi, 4194424+f_while
call isword
cmp eax, 0
jnz.l stwhile
mov esi, 4194424+f_write
call isword
cmp eax, 0
jnz.l stwrite
mov esi, 4194424+f_ret
call isword
cmp eax, 0
jnz.l streto
mov esi, 4194424+f_if
call isword
cmp eax, 0
jnz.l stif

mov esi, 4194424+f_char
call isword
cmp eax, 0
jnz.l stchar
mov esi, 4194424+f_int
call isword
cmp eax, 0
jnz.l stint
jmp.l stasg
bodend:
mov eax, 1
call bump
mov eax, [rbp+112]
dec eax
mov [rbp+112], eax
ret
stwrite:
mov esi, 4194424+f_lpar
call want
mov esi, 4194424+f_quote
call want
call litgo
mov esi, 4194424+f_quote
call want
mov esi, 4194424+f_rpar
call want
mov esi, 4194424+f_semi
call want
call wblock
jmp.l bodloop
stint:
mov eax, 8
mov [rbp-304], eax      ; eight bytes per element (unused for a scalar)
call ident
call skipws
call gcur
cmp al, 91
jz.l stintarr           ; `int a[N];` instead of `int x = ...;`
call defvar
mov [rbp-116], eax
mov esi, 4194424+f_eq
call want
call expr
mov eax, [rbp-116]
call emit_ls
mov esi, 4194424+f_semi
call want
jmp.l bodloop

stchar:
; `char a[N];` -- N bytes packed into ceil(N/8) slots. A char *scalar* is
; refused: there is no type system to say what `char x;` would mean, and a
; byte variable is not needed for a symbol table -- a byte buffer is.
call ident
call skipws
call gcur
cmp al, 91
jz stcharok
jmp.l fail              ; `char x` is not in the subset
stcharok:
mov eax, 1
mov [rbp-304], eax      ; one byte per element: a char array
mov eax, 1
call bump               ; '['
call numval
mov [rbp-256], eax
mov esi, 4194424+f_rbrk
call want
mov esi, 4194424+f_semi
call want
mov eax, [rbp-256]
call defarr
jmp.l bodloop

stintarr:
mov eax, 8
mov [rbp-304], eax      ; eight bytes per element
; `int a[N];` -- a count, then `]` and `;`, no initialiser
mov eax, 1
call bump
call numval
mov [rbp-256], eax
mov esi, 4194424+f_rbrk
call want
mov esi, 4194424+f_semi
call want
mov eax, [rbp-256]
call defarr
jmp.l bodloop

stasg:
call skipws
call gcur
cmp al, 42
jz.l stptr
call ident
call skipws
call gcur
cmp al, 91
jz.l stsub
call skipws
call gcur
cmp al, 40
jz stcall
call findvar
mov [rbp-112], eax      ; -112: this check is immediate
call isarr
cmp eax, 0
jz stbare
jmp.l fail              ; a bare array name is refused
stbare:
mov eax, [rbp-112]
mov [rbp-116], eax
mov esi, 4194424+f_eq
call want
call expr
mov eax, [rbp-116]
call emit_ls
mov esi, 4194424+f_semi
call want
jmp.l bodloop
stcall:
mov eax, 1
mov [rbp-292], eax      ; a statement call takes its arguments at depth 1
call callargs
mov esi, 4194424+f_semi
call want
jmp.l bodloop

stsub:
; `a[i] = v;` -- the scaled index is parked at -284 because `want` and `expr`
; own every register; the address is built after the value is in rax. A char
; element takes no stride and stores one byte.
mov eax, 1
call bump               ; '['
call findvar
mov [rbp-268], eax
call isarr
mov [rbp-308], eax
cmp eax, 0
jnz stsok
stsok:
mov eax, [rbp-236]
cmp eax, 0
jz stsgo
jmp.l fail              ; a subscript inside a subscript: refused
stsgo:
mov eax, 1
mov [rbp-236], eax
mov eax, 1
call exprd              ; the index into depth 1
mov eax, [rbp-308]
cmp eax, 8              ; only an int element strides
jnz stsnosc
mov eax, 3
mov [rbp-280], eax
stscl:
mov esi, 4194424+f_add
call emitstr
mov eax, 1
call emitreg
mov esi, 4194424+f_sep
call emitstr
mov eax, 1
call emitreg
mov esi, 4194424+f_nl
call emitstr
mov eax, [rbp-280]
dec eax
mov [rbp-280], eax
cmp eax, 0
jnz stscl
stsnosc:
mov esi, 4194424+f_isav
call emitstr
mov eax, 1
call emitreg
mov esi, 4194424+f_nl
call emitstr
mov esi, 4194424+f_rbrk
call want
mov esi, 4194424+f_eq
call want
call expr               ; the value into rax
mov eax, [rbp-308]
cmp eax, 0
jz stsbp
mov esi, 4194424+f_lea1
jmp stsbb
stsbp:
mov esi, 4194424+f_mov  ; a pointer: the base is the variable's value
stsbb:
call emitstr
mov eax, 1
call emitreg
mov esi, 4194424+f_cev
call emitstr
mov eax, [rbp-268]
call varoff
call emitnum
mov esi, 4194424+f_le2
call emitstr
mov esi, 4194424+f_mov
call emitstr
mov eax, 2
call emitreg
mov esi, 4194424+f_cev
call emitstr
mov eax, 284
call emitnum
mov esi, 4194424+f_le2
call emitstr
mov esi, 4194424+f_add
call emitstr
mov eax, 1
call emitreg
mov esi, 4194424+f_sep
call emitstr
mov eax, 2
call emitreg
mov esi, 4194424+f_nl
call emitstr
mov eax, [rbp-308]
cmp eax, 8              ; only an int element stores 64 bits
jnz stsbyte
mov esi, 4194424+f_lst1
call emitstr
mov esi, 4194424+f_rax
call emitstr
mov esi, 4194424+f_nl
call emitstr
jmp stsfin
stsbyte:
mov esi, 4194424+f_lstb
call emitstr
stsfin:
mov esi, 4194424+f_semi
call want
mov eax, 0
mov [rbp-236], eax
jmp.l bodloop

streto:
; `return` is allowed anywhere a statement is: the epilogue (or the exit)
; is emitted in place, so control leaves the function here and any code
; after it is simply unreachable
call expr
mov esi, 4194424+f_semi
call want
call emitret
mov eax, 1
mov [rbp+24], eax
call skipws
call gcur
cmp al, 125             ; and it must be the last statement
jnz.l fail
mov eax, 1
call bump
mov eax, [rbp+112]
dec eax
mov [rbp+112], eax
ret
; ---- expressions ---------------------------------------------------------
; One register per nesting depth: eax, ecx, edx, esi, edi, r8d. The left
; operand is computed at depth d, the right at d+1, and one instruction
; combines them -- no stack in the generated code, and `x + 1` still emits the
; same three lines it always did. Precedence: `*` binds tighter than `+`/`-`,
; left associative.
;   [rbp-128] current depth   [rbp-132] the operator being combined
;   [rbp-140] value/offset    [rbp-144..148] emitreg scratch
expr:
; A statement's expression starts at depth 0. Nesting is allowed: a call's
; argument is a whole expression too, and the parse state that used to be
; corrupted by nesting was a *state slot overwritten by a call's return
; address*, because cc never reserved stack (docs/cc.md). The guard that
; refused nesting, and `argexpr` that existed to avoid it, are both gone.
mov eax, 0
jmp.l exprd
exprd:
; eax is the caller's depth: an expression at depth d leaves its value in reg d
; and leaves reg 0..d-1 alone. That is what a subscript needs -- the base stays
; in reg d while the index is computed at d+1.
mov [rbp-128], eax
call ex1
ret
ex1:
call ex2
ex1l:
call skipws
call gcur
cmp al, 43
jz ex1op
cmp al, 45
jnz ex1d
ex1op:
push rax                ; the operator, across the recursive parse
mov eax, 1
call bump
mov eax, [rbp-128]
inc eax
call chkdep
mov [rbp-128], eax
call ex2
mov eax, [rbp-128]
dec eax
mov [rbp-128], eax
pop rax
mov [rbp-132], eax
call emitop
jmp ex1l
ex1d:
ret

ex2:
call ex3
ex2l:
call skipws
call gcur
cmp al, 42
jz ex2mul
cmp al, 47
jz.l ex2div
cmp al, 37
jz.l ex2rem
jmp.l ex2d
ex2mul:
push rax
mov eax, 1
call bump
mov eax, [rbp-128]
inc eax
call chkdep
mov [rbp-128], eax
call ex3
mov eax, [rbp-128]
dec eax
mov [rbp-128], eax
pop rax
mov [rbp-132], eax
call emitop
jmp ex2l

ex2div:
mov eax, 1
mov [rbp-312], eax      ; keep the quotient
jmp.l ex2dv
ex2rem:
mov eax, 0
mov [rbp-312], eax      ; keep the remainder
ex2dv:
; `/` and `%` bind like `*`. div divides rdx:rax, so the left operand is moved
; into rax and rdx is zeroed; the right operand is at d+1, harmlessly, because
; nothing else is live between the zeroing and the division.
mov eax, 1
call bump
mov eax, [rbp-128]
inc eax
call chkdep
mov [rbp-128], eax
call ex3
mov eax, [rbp-128]
dec eax
mov [rbp-128], eax
mov esi, 4194424+f_mov
call emitstr
mov esi, 4194424+f_rax
call emitstr
mov esi, 4194424+f_sep
call emitstr
mov eax, [rbp-128]
call emitreg             ; mov rax, <reg d>
mov esi, 4194424+f_nl
call emitstr
mov esi, 4194424+f_xor
call emitstr
mov esi, 4194424+f_rdx
call emitstr
mov esi, 4194424+f_sep
call emitstr
mov esi, 4194424+f_rdx
call emitstr
mov esi, 4194424+f_nl
call emitstr
mov esi, 4194424+f_div
call emitstr
mov eax, [rbp-128]
inc eax
call emitreg             ; div <reg d+1>
mov esi, 4194424+f_nl
call emitstr
mov esi, 4194424+f_mov
call emitstr
mov eax, [rbp-128]
call emitreg
mov eax, [rbp-312]
cmp eax, 0
jz ex2dvr
mov esi, 4194424+f_rax2
jmp ex2dvg
ex2dvr:
mov esi, 4194424+f_mrdx
ex2dvg:
call emitstr
jmp.l ex2l
ex2d:
ret
ex3:
call skipws
call gcur
cmp al, 38
jz.l ex3addr
cmp al, 42
jz.l ex3deref
cmp al, 48
jb.l ex3var
cmp al, 58
jb.l ex3num
ex3var:
call ident
call skipws
call gcur
cmp al, 40
jz ex3call
cmp al, 91
jz.l ex3sub
call findvar
mov [rbp-112], eax      ; -112: this check is immediate
call isarr
cmp eax, 0
jz ex3bare
jmp.l fail              ; a bare array name is no value
ex3bare:
mov eax, [rbp-112]
call varoff
mov [rbp-140], eax
mov esi, 4194424+f_mov
call emitstr
mov eax, [rbp-128]
call emitreg
mov esi, 4194424+f_cev
call emitstr
mov eax, [rbp-140]
call emitnum
mov esi, 4194424+f_brk
call emitstr
mov esi, 4194424+f_nl
call emitstr
ret
ex3call:
; A call may appear anywhere in an expression now. Two things make that safe:
;
; 1. Its value comes back in rax -- depth 0's register -- so a call at depth d
;    moves it to reg d afterwards.
; 2. The *call itself* destroys rax, rcx, rdx and rsi, and reg 0..d-1 hold the
;    operands of enclosing expressions. They are pushed before the call and
;    popped after it, in reverse. At depth 0 there is nothing live, so the
;    usual case emits no push at all.
;
; Arguments are evaluated at d+1 so they cannot touch reg 0..d. A call inside
; an *argument list* is still refused: it would overwrite the argument
; registers, which is a different resource from the depth registers.
mov eax, [rbp-16064]
cmp eax, 1684104562      ; "read", four bytes little-endian
jz ex3rdgo
cmp eax, 1953067639      ; "writ", four bytes little-endian
jz ex3wrgo
jmp ex3cgo
ex3wrgo:
lea rdx, [rbp-16064]
movzx eax, byte [rdx+4]
cmp eax, 101             ; 'e'
jnz.l fail
movzx eax, byte [rdx+5]
cmp eax, 0               ; "write" is five bytes
jz.l ex3wr
jmp.l fail
ex3rdgo:
lea rdx, [rbp-16064]
mov eax, [rdx+4]
cmp eax, 0               ; the name must be exactly four bytes
jz.l ex3read
jmp.l fail
ex3cgo:
mov eax, [rbp-208]
cmp eax, 0
jz ex3fin
jmp.l fail
ex3fin:
mov eax, [rbp-128]
mov [rbp-296], eax      ; d, kept across the arguments
mov eax, 0
mov [rbp-300], eax
ex3cps:
mov eax, [rbp-300]
mov ecx, [rbp-296]
cmp eax, ecx
jz ex3cpe
mov esi, 4194424+f_push
call emitstr
mov eax, [rbp-300]
call emitreg
mov esi, 4194424+f_nl
call emitstr
mov eax, [rbp-300]
inc eax
mov [rbp-300], eax
jmp ex3cps
ex3cpe:
mov eax, [rbp-296]
inc eax
cmp eax, 6
jb ex3cdep
jmp.l fail              ; arguments one depth deeper would leave the register table
ex3cdep:
mov [rbp-292], eax
call callargs
mov eax, [rbp-296]
mov [rbp-128], eax      ; exprd left the arguments' depth behind
cmp eax, 0
jz ex3cpop
mov esi, 4194424+f_mov
call emitstr
mov eax, [rbp-296]
call emitreg
mov esi, 4194424+f_sep
call emitstr
mov esi, 4194424+f_rax
call emitstr
mov esi, 4194424+f_nl
call emitstr
ex3cpop:
mov eax, [rbp-296]
mov [rbp-300], eax
ex3cpl:
mov eax, [rbp-300]
cmp eax, 0
jz ex3cdone
dec eax
mov [rbp-300], eax
mov esi, 4194424+f_pop
call emitstr
mov eax, [rbp-300]
call emitreg
mov esi, 4194424+f_nl
call emitstr
jmp ex3cpl
ex3cdone:
ret
ex3read:
; `read(a, N)` -- SYS_read from stdin into the char array `a`, up to N bytes,
; with the count in rax. The first argument is a *name*, because a buffer has no
; value: cc has no pointer type, so the address is taken here rather than
; written by the programmer.
mov eax, 1
call bump               ; '(' -- already consumed by the caller
call ident
mov [rbp-112], eax
call findvar
mov [rbp-268], eax
mov eax, [rbp-268]
call isarr
cmp eax, 0
jnz ex3rdok
jmp.l fail              ; read into something that is not an array
ex3rdok:
mov esi, 4194424+f_comma
call want
call numval
mov [rbp-272], eax      ; the byte count
mov esi, 4194424+f_rpar
call want
mov esi, 4194424+f_rd1
call emitstr
mov eax, [rbp-268]
call varoff
call emitnum
mov esi, 4194424+f_rd2
call emitstr
mov eax, [rbp-272]
call emitnum
mov esi, 4194424+f_rd3
call emitstr
ret

ex3wr:
; `write(a, n)` -- SYS_write of n bytes from the array (or pointer) `a` to
; stdout. The mirror of `read`, except that the count is an *expression*: a
; compiler writes what it computed.
;
; The count is evaluated first and moved to rdx, because taking the address
; needs rsi and the syscall needs eax and edi -- so the order is fixed by which
; register each value has to be in.
mov eax, 1
call bump               ; '(' -- already consumed by the caller
call ident
call findvar
mov [rbp-268], eax
call isarr
mov [rbp-308], eax
cmp eax, 0
jnz ex3wrok
jmp.l fail              ; write from something that is not an array
ex3wrok:
mov esi, 4194424+f_comma
call want
call expr               ; the count, at depth 0
mov esi, 4194424+f_mov
call emitstr
mov esi, 4194424+f_rdx
call emitstr
mov esi, 4194424+f_sep
call emitstr
mov esi, 4194424+f_rax
call emitstr
mov esi, 4194424+f_nl
call emitstr
mov eax, [rbp-308]
cmp eax, 0
jz ex3wrp
mov esi, 4194424+f_lea1
jmp ex3wrb
ex3wrp:
mov esi, 4194424+f_mov  ; a pointer: the buffer's address is its value
ex3wrb:
call emitstr
mov esi, 4194424+f_rsi
call emitstr
mov esi, 4194424+f_cev
call emitstr
mov eax, [rbp-268]
call varoff
call emitnum
mov esi, 4194424+f_le2
call emitstr
mov esi, 4194424+f_wr1
call emitstr
mov esi, 4194424+f_rpar
call want
ret

ex3sub:
; `a[i]` -- the base goes into reg d and the index is computed at d+1, so the
; base survives: that is what the depth mechanism is for. d is saved in -288
; because exprd overwrites [rbp-128] with its own depth; the element kind is
; saved in -308 because isarr's answer is consumed by the refusal test.
mov eax, 1
call bump               ; '['
call findvar
mov [rbp-268], eax      ; the array's index: must survive the index parse
call isarr
mov [rbp-308], eax      ; 1 = int array, 2 = char array
cmp eax, 0
jnz ex3sok
ex3sok:
mov eax, [rbp-236]
cmp eax, 0
jz ex3sgo
jmp.l fail              ; a subscript inside a subscript: refused, docs/cc.md
ex3sgo:
mov eax, 1
mov [rbp-236], eax
mov eax, [rbp-128]
mov [rbp-288], eax      ; d, the base's register
mov eax, [rbp-268]
call varoff
mov [rbp-272], eax
mov eax, [rbp-308]
cmp eax, 0
jz ex3sbp
mov esi, 4194424+f_lea1
jmp ex3sbb
ex3sbp:
mov esi, 4194424+f_mov  ; a pointer: the base is the variable's value
ex3sbb:
call emitstr
mov eax, [rbp-288]
call emitreg
mov esi, 4194424+f_cev
call emitstr
mov eax, [rbp-272]
call emitnum
mov esi, 4194424+f_le2
call emitstr
mov eax, [rbp-288]
inc eax
mov [rbp-276], eax      ; d+1: the index's register
call exprd
mov eax, [rbp-288]
mov [rbp-128], eax      ; exprd left its own depth behind: restore d
mov eax, [rbp-308]
cmp eax, 8              ; an int element is eight bytes
jnz ex3snosc             ; only an eight-byte element strides
mov eax, 3
mov [rbp-280], eax
ex3scl:
mov esi, 4194424+f_add
call emitstr
mov eax, [rbp-276]
call emitreg
mov esi, 4194424+f_sep
call emitstr
mov eax, [rbp-276]
call emitreg
mov esi, 4194424+f_nl
call emitstr
mov eax, [rbp-280]
dec eax
mov [rbp-280], eax
cmp eax, 0
jnz ex3scl
ex3snosc:
mov esi, 4194424+f_add
call emitstr
mov eax, [rbp-288]
call emitreg
mov esi, 4194424+f_sep
call emitstr
mov eax, [rbp-276]
call emitreg
mov esi, 4194424+f_nl
call emitstr
mov eax, [rbp-308]
cmp eax, 8              ; only an int element loads 64 bits
jnz ex3sbyte
mov esi, 4194424+f_mov
call emitstr
mov eax, [rbp-288]
call emitreg
mov esi, 4194424+f_dref1
call emitstr
mov eax, [rbp-288]
call emitreg
mov esi, 4194424+f_le2
call emitstr
jmp ex3sfin
ex3sbyte:
mov esi, 4194424+f_movzx
call emitstr
mov eax, [rbp-288]
call emitreg
mov esi, 4194424+f_drefb
call emitstr
mov eax, [rbp-288]
call emitreg
mov esi, 4194424+f_le2
call emitstr
ex3sfin:
mov esi, 4194424+f_rbrk
call want
mov eax, 0
mov [rbp-236], eax
ret

ex3addr:
; `&name`: the address of a variable, 64-bit because an address is
mov eax, 1
call bump
call ident
call findvar
call varoff
mov [rbp-140], eax
mov esi, 4194424+f_lea1
call emitstr
mov eax, [rbp-128]
call emitreg
mov esi, 4194424+f_cev
call emitstr
mov eax, [rbp-140]
call emitnum
mov esi, 4194424+f_le2
call emitstr
ret

ex3deref:
; `*name`: load the pointer, then load through it
mov eax, 1
call bump
call ident
call findvar
call varoff
mov [rbp-140], eax
mov esi, 4194424+f_mov
call emitstr
mov eax, [rbp-128]
call emitreg
mov esi, 4194424+f_cev
call emitstr
mov eax, [rbp-140]
call emitnum
mov esi, 4194424+f_le2
call emitstr
mov esi, 4194424+f_mov
call emitstr
mov eax, [rbp-128]
call emitreg
mov esi, 4194424+f_dref1
call emitstr
mov eax, [rbp-128]
call emitreg
mov esi, 4194424+f_le2
call emitstr
ret

stptr:
; `*name = expr;` -- the value is computed FIRST and the pointer loaded after
; it, so nothing is parked. The slot offset lives at -244 because expr owns
; -140 (the shared term scratch) and `want`/`skipws` clobber rax.
mov eax, 1
call bump
call ident
call findvar
call varoff
mov [rbp-244], eax
mov esi, 4194424+f_eq
call want
call expr
mov esi, 4194424+f_mov
call emitstr
mov eax, 1
call emitreg
mov esi, 4194424+f_cev
call emitstr
mov eax, [rbp-244]
call emitnum
mov esi, 4194424+f_le2
call emitstr
mov esi, 4194424+f_lst1
call emitstr
mov esi, 4194424+f_rax
call emitstr
mov esi, 4194424+f_nl
call emitstr
mov esi, 4194424+f_semi
call want
jmp.l bodloop

ex3num:
call numval
mov [rbp-140], eax
mov esi, 4194424+f_mov
call emitstr
mov eax, [rbp-128]
call emitreg
mov esi, 4194424+f_sep
call emitstr
mov eax, [rbp-140]
call emitnum
mov esi, 4194424+f_nl
call emitstr
ret

; chkdep: refuse nesting deeper than the register table
chkdep:
mov ecx, 6
cmp eax, ecx
jb chkok2
jmp.l fail
chkok2:
ret

; emitreg: the name of the register for depth eax
emitreg:
add eax, eax
add eax, eax
mov ecx, 4194424+regnames
add eax, ecx
mov [rbp-144], eax
mov eax, 0
mov [rbp-148], eax
ergl:
mov eax, [rbp-144]
mov ecx, [rbp-148]
add eax, ecx
movzx eax, byte [rax]
cmp eax, 0              ; names are null-terminated: r8 is two characters
jz ergd
mov eax, [rbp-144]
mov ecx, [rbp-148]
add eax, ecx
movzx eax, byte [rax]
call emitc
mov eax, [rbp-148]
inc eax
mov [rbp-148], eax
jmp ergl
ergd:
ret

; emitop: combine, left at the depth in [rbp-128], right at depth+1
emitop:
mov eax, [rbp-132]
cmp eax, 43
jz eopadd
cmp eax, 45
jz eopsub
mov esi, 4194424+f_imul
jmp eopgo
eopadd:
mov esi, 4194424+f_add
jmp eopgo
eopsub:
mov esi, 4194424+f_sub
eopgo:
call emitstr
mov eax, [rbp-128]
call emitreg
mov esi, 4194424+f_sep
call emitstr
mov eax, [rbp-128]
inc eax
call emitreg
mov esi, 4194424+f_nl
call emitstr
ret

; ---- the symbol table -----------------------------------------------------
; Eight variables, eight bytes of name each, at rbp-16000. A variable's slot is
; [rbp-8*(index+1)]. The name being scanned lives at rbp-16064.
;   [rbp-100] length of the current name   [rbp-104] scan index
;   [rbp-108] variable count               [rbp-112] scratch
;   [rbp-116] [rbp-120] saved indices
ident:
; scan a name: letters, digits and '_', at most fifteen characters, not starting
; with a digit. Leaves the padded name at rbp-16064 and its length in [rbp-100].
mov eax, 0
mov [rbp-16064], eax
mov [rbp-16060], eax
mov [rbp-16056], eax
mov [rbp-16052], eax
mov [rbp-100], eax
call skipws
idloop:
call gcur
cmp al, 95
jz idok
cmp al, 48
jb iddone
cmp al, 58
jb iddig
cmp al, 65
jb iddone
cmp al, 91
jb idok
cmp al, 97
jb iddone
cmp al, 123
jb idok
jmp iddone
iddig:
mov ecx, [rbp-100]
cmp ecx, 0
jz.l fail               ; an identifier cannot start with a digit
idok:
mov ecx, [rbp-100]
cmp ecx, 16
jb idstore
jmp.l fail              ; longer than fifteen characters
idstore:
lea rdx, [rbp-16064]
add rdx, rcx
mov [rdx], al
mov ecx, [rbp-100]
inc ecx
mov [rbp-100], ecx
mov eax, 1
call bump
jmp idloop
iddone:
mov ecx, [rbp-100]
cmp ecx, 0
jz.l fail               ; no name at all
ret

idfind:
mov eax, 0
mov [rbp-104], eax
idfl:
mov eax, [rbp-104]
mov ecx, [rbp-108]
cmp eax, ecx
jz idfnone
mov edx, eax
add eax, eax
add eax, eax
add eax, eax
add eax, eax            ; 16i
lea rcx, [rbp-16000]
add rcx, rax
mov eax, [rcx]
mov edx, [rbp-16064]
cmp eax, edx
jnz idfn
mov eax, [rcx+4]
mov edx, [rbp-16060]
cmp eax, edx
jnz idfn
mov eax, [rcx+8]
mov edx, [rbp-16056]
cmp eax, edx
jnz idfn
mov eax, [rcx+12]
mov edx, [rbp-16052]
cmp eax, edx
jnz idfn
mov eax, [rbp-104]
ret
idfn:
mov eax, [rbp-104]
inc eax
mov [rbp-104], eax
jmp idfl
idfnone:
mov eax, -1
ret

; findvar: index of the current name, or refuse -- an undeclared variable
findvar:
call idfind
cmp eax, -1
jz.l fail
ret

; defvar: declare the current name, refusing a repeat or one past the last slot
defvar:
call idfind
cmp eax, -1
jnz.l fail              ; already declared
mov eax, [rbp-108]
cmp eax, 32
jb defok
jmp.l fail              ; no free slot
defok:
mov edx, eax
add eax, eax
add eax, eax
add eax, eax
add eax, eax            ; 16i
lea rcx, [rbp-16000]
add rcx, rax
mov eax, [rbp-16064]
mov [rcx], eax
mov eax, [rbp-16060]
mov [rcx+4], eax
mov eax, [rbp-16056]
mov [rcx+8], eax
mov eax, [rbp-16052]
mov [rcx+12], eax
mov eax, [rbp-108]
inc eax
mov [rbp-108], eax
dec eax                 ; the new variable's index
mov edx, eax
lea rcx, [rbp-14000]
add rcx, rdx
mov edx, 0
mov [rcx], dl           ; a scalar is not an array: its subscript is a pointer
ret

; ---- arrays ---------------------------------------------------------------
; `int a[N];` and `char a[N];` are allocated from a byte counter that starts
; above the scalar slots, so an array no longer competes with them: a function
; can have thirty-two scalars *and* a four-kilobyte buffer. The frame is
; FRAME bytes (see f_pro), the counter starts at 264 -- the scalar area -- and
; an array that does not fit is refused rather than overrunning the frame.
;   [rbp-320] next free byte   [-13800 + 4i] an array's offset   [-14000 + i] its kind
defarr:
; eax is a count of *elements*; the element size is in [rbp-304]. Bytes, then
; round up to eight so that every object starts on a slot boundary.
mov ecx, eax
mov edx, [rbp-304]
imul ecx, edx
add ecx, 7
and ecx, -8             ; an eight-byte multiple
mov [rbp-256], ecx      ; the byte count
call idfind
cmp eax, -1
jnz.l fail              ; already declared
mov eax, [rbp-108]
cmp eax, 32
jb defafit
jmp.l fail              ; no free symbol slot
defafit:
mov eax, [rbp-320]
mov [rbp-260], eax      ; this array's offset from rbp
mov edx, [rbp-256]
add eax, edx
cmp eax, 8000
jb defabfit
jmp.l fail              ; does not fit in the frame
defabfit:
mov [rbp-320], eax
mov eax, [rbp-260]
mov [rbp-272], eax
mov eax, [rbp-108]
mov [rbp-268], eax
mov edx, eax
add eax, eax
add eax, eax
add eax, eax
add eax, eax            ; 16i
lea rcx, [rbp-16000]
add rcx, rax
mov eax, [rbp-16064]
mov [rcx], eax
mov eax, [rbp-16060]
mov [rcx+4], eax
mov eax, [rbp-16056]
mov [rcx+8], eax
mov eax, [rbp-16052]
mov [rcx+12], eax
mov eax, [rbp-268]
mov edx, eax
add eax, eax
add eax, eax
lea rcx, [rbp-13800]
add rcx, rax
mov eax, [rbp-272]
mov [rcx], eax          ; the array's offset
mov eax, [rbp-268]
lea rcx, [rbp-14000]
add rcx, rax
mov eax, [rbp-304]
mov [rcx], al           ; the element size is the kind
mov eax, [rbp-108]
inc eax
mov [rbp-108], eax
dec eax
ret

; isarr: eax = index, result eax = 1 if that slot is an array
isarr:
lea rcx, [rbp-14000]
add rcx, rax
movzx eax, byte [rcx]
ret

; varoff: eax = index, result eax = the byte offset 8*(index+1)
varoff:
; eax = a variable index, result = its byte offset from rbp. A scalar sits at
; 8*(i+1); an array's offset is in the table at -13800 because it comes from the
; byte counter, not from the index.
mov ecx, eax
mov edx, eax
add edx, edx
add edx, edx
lea rsi, [rbp-14000]
add rsi, rcx
movzx edx, byte [rsi]
cmp edx, 0
jz varoffsc
mov edx, eax
add edx, edx
add edx, edx
lea rsi, [rbp-13800]
add rsi, rdx
mov eax, [rsi]
ret
varoffsc:
inc ecx
add ecx, ecx
add ecx, ecx
add ecx, ecx
mov eax, ecx
ret
; emit_le: "mov eax, [rbp-<8*(i+1)>]"     emit_ls: "mov [rbp-<..>], eax"
emit_le:
call varoff
mov [rbp-112], eax
mov esi, 4194424+f_le1
call emitstr
mov eax, [rbp-112]
call emitnum
mov esi, 4194424+f_le2
call emitstr
ret
emit_ls:
call varoff
mov [rbp-112], eax
mov esi, 4194424+f_ls1
call emitstr
mov eax, [rbp-112]
call emitnum
mov esi, 4194424+f_ls2
call emitstr
ret

; ---- a condition: `x`, or `x <op> number` --------------------------------
; Only `jb`, `jz` and `jnz` exist, so the six relations are expressed three
; ways: unsigned `jb` with the operands in the right order (which covers < and,
; by swapping, >), `jz`/`jnz` for equality, and `<=`/`>=` normalised to < / >
; with the bound adjusted. Exact for the 0..255 the subset allows.
; [rbp+44] = jump kind (0 jb, 1 jz, 2 jnz, 3 jb with swapped operands)
; [rbp+124] = the bound, already adjusted
cond:
mov eax, 0
mov [rbp-316], eax      ; the bound is a literal until cndbnd says otherwise
call ident
call findvar
call emit_le
mov eax, 2
mov [rbp+44], eax
mov eax, 0
mov [rbp+124], eax
call skipws
call gcur
cmp al, 60
jz.l cnd_lt
cmp al, 62
jz.l cnd_gt
cmp al, 61
jz.l cnd_eq
cmp al, 33
jz.l cnd_ne
ret
cnd_lt:
mov eax, 1
call bump
call skipws
call gcur
cmp al, 61
jnz cnd_lt2
mov eax, 1
call bump
call cndbnd
mov eax, [rbp-316]
cmp eax, 0
jz cnd_lel
mov esi, 4194424+f_incrcx
call emitstr             ; a register bound: x <= n is x < n+1
mov eax, 0
mov [rbp+44], eax
ret
cnd_lel:
mov eax, [rbp+124]
cmp eax, 255
jb cnd_le
jmp.l fail              ; `x <= 255` would need a bound of 256
cnd_le:
inc eax
mov [rbp+124], eax
mov eax, 0
mov [rbp+44], eax
ret
cnd_lt2:
call cndbnd
mov eax, 0
mov [rbp+44], eax
ret
cnd_gt:
mov eax, 1
call bump
call skipws
call gcur
cmp al, 61
jnz cnd_gt2
mov eax, 1
call bump
call cndbnd
mov eax, [rbp-316]
cmp eax, 0
jz cnd_gel
mov esi, 4194424+f_decrcx
call emitstr             ; a register bound: x >= n is n-1 < x
mov eax, 3
mov [rbp+44], eax
ret
cnd_gel:
mov eax, [rbp+124]
cmp eax, 0
jnz cnd_ge
jmp.l fail              ; `x >= 0` would need a bound of -1
cnd_ge:
dec eax
mov [rbp+124], eax
mov eax, 3
mov [rbp+44], eax
ret
cnd_gt2:
call cndbnd
mov eax, 3
mov [rbp+44], eax
ret
cnd_eq:
mov eax, 1
call bump
call skipws
call gcur
cmp al, 61
jnz.l fail
mov eax, 1
call bump
call cndbnd
mov eax, 1
mov [rbp+44], eax
ret
cnd_ne:
mov eax, 1
call bump
call skipws
call gcur
cmp al, 61
jnz.l fail
mov eax, 1
call bump
call cndbnd
mov eax, 2
mov [rbp+44], eax
ret

; condj: emit the test and a jump-if-TRUE to L<id><letter>, the letter being in
; [rbp+92] and the id in [rbp+96]
cndbnd:
; the bound of a comparison: a number, or a variable loaded into rcx. [rbp-316]
; is 1 when the bound is in rcx, which is the only thing condj needs to know --
; `<=` and `>=` with a variable bound are refused, because adjusting a register
; bound needs an inc/dec and the two normalised forms are not worth the extra
; path until something needs them.
call skipws
call gcur
cmp al, 48
jb cndbv
cmp al, 58
jb cndbn
cndbv:
call ident
call findvar
call varoff
mov [rbp-112], eax
mov eax, 1
mov [rbp-316], eax
mov esi, 4194424+f_cmov2
call emitstr
mov esi, 4194424+f_lbr2
call emitstr
mov eax, [rbp-112]
call emitnum
mov esi, 4194424+f_le2
call emitstr
mov eax, 0
mov [rbp+124], eax
ret
cndbn:
mov eax, 0
mov [rbp-316], eax
call numval
mov [rbp+124], eax
ret

condj:
mov eax, [rbp-316]
cmp eax, 0
jz cj_lit
jmp.l cj_var
cj_lit:
mov eax, [rbp+44]
cmp eax, 3
jz cj_swap
mov esi, 4194424+f_ccmp
call emitstr
mov eax, [rbp+124]
call emitnum
mov eax, [rbp+44]
cmp eax, 1
jz cj_z
cmp eax, 2
jz cj_nz
mov esi, 4194424+f_cjb
call emitstr
jmp cj_fin
cj_z:
mov esi, 4194424+f_cjz
call emitstr
jmp cj_fin
cj_nz:
mov esi, 4194424+f_cjnz
call emitstr
jmp cj_fin
cj_swap:
mov esi, 4194424+f_cmov2
call emitstr
mov eax, [rbp+124]
call emitnum
mov esi, 4194424+f_ccmp2
call emitstr
cj_fin:
mov esi, 4194424+f_L
call emitstr
mov eax, [rbp+96]
call emitnum
mov eax, [rbp+92]
call emitc
mov esi, 4194424+f_nl
call emitstr
ret
cj_var:
; a variable bound: it was loaded into rcx by cndbnd, so the compare is between
; two registers. `x > y` is `y < x`, which is the same swap the literal path
; uses; `<=` and `>=` never reach here.
mov eax, [rbp+44]
cmp eax, 3
jz cjv_sw
mov esi, 4194424+f_cmp1
call emitstr
jmp cjv_j
cjv_sw:
mov esi, 4194424+f_cmp2
call emitstr
cjv_j:
mov eax, [rbp+44]
cmp eax, 1
jz cjv_z
cmp eax, 2
jz cjv_nz
mov esi, 4194424+f_cjb
call emitstr
jmp.l cj_fin
cjv_z:
mov esi, 4194424+f_cjz
call emitstr
jmp.l cj_fin
cjv_nz:
mov esi, 4194424+f_cjnz
call emitstr
jmp.l cj_fin


; newid: the next block id, refused beyond nine (one digit per label)
newid:
mov eax, [rbp+96]
inc eax
mov [rbp+96], eax
mov ecx, 10
cmp eax, ecx
jb newidok
jmp.l fail
newidok:
ret

stwhile:
mov esi, 4194424+f_lpar
call want
; the loop label comes BEFORE the condition's load, or the load lands outside
; the loop and the variable is never re-read
call newid
mov esi, 4194424+f_L
call emitstr
mov eax, [rbp+96]
call emitnum
mov esi, 4194424+f_dcol
call emitstr
call cond
mov esi, 4194424+f_rpar
call want
mov esi, 4194424+f_lbrc
call want
mov eax, 98
mov [rbp+92], eax
call condj
mov esi, 4194424+f_jl
call emitstr
mov eax, [rbp+96]
call emitnum
mov esi, 4194424+f_nle
call emitstr
mov esi, 4194424+f_L
call emitstr
mov eax, [rbp+96]
call emitnum
mov esi, 4194424+f_dlb
call emitstr
mov eax, [rbp+96]
push rax
call body
pop rax
mov [rbp+96], rax
mov esi, 4194424+f_jl
call emitstr
mov eax, [rbp+96]
call emitnum
mov esi, 4194424+f_nl
call emitstr
mov esi, 4194424+f_L
call emitstr
mov eax, [rbp+96]
call emitnum
mov esi, 4194424+f_dle
call emitstr
jmp.l bodloop

stif:
mov esi, 4194424+f_lpar
call want
call cond
mov esi, 4194424+f_rpar
call want
mov esi, 4194424+f_lbrc
call want
call newid
mov eax, 116
mov [rbp+92], eax
call condj
mov esi, 4194424+f_jl
call emitstr
mov eax, [rbp+96]
call emitnum
mov esi, 4194424+f_nle
call emitstr
mov esi, 4194424+f_L
call emitstr
mov eax, [rbp+96]
call emitnum
mov esi, 4194424+f_dlt
call emitstr
mov eax, [rbp+96]
push rax
call body
pop rax
mov [rbp+96], rax
call skipws
mov esi, 4194424+f_else
call isword
cmp eax, 0
jz stif_nel
mov esi, 4194424+f_jl
call emitstr
mov eax, [rbp+96]
call emitnum
mov esi, 4194424+f_nlx
call emitstr
mov esi, 4194424+f_L
call emitstr
mov eax, [rbp+96]
call emitnum
mov esi, 4194424+f_dle
call emitstr
mov esi, 4194424+f_lbrc
call want
mov eax, [rbp+96]
push rax
call body
pop rax
mov [rbp+96], rax
mov esi, 4194424+f_L
call emitstr
mov eax, [rbp+96]
call emitnum
mov esi, 4194424+f_dlx
call emitstr
jmp.l bodloop
stif_nel:
mov esi, 4194424+f_L
call emitstr
mov eax, [rbp+96]
call emitnum
mov esi, 4194424+f_dle
call emitstr
jmp.l bodloop

; ---- the code block for one write ---------------------------------------
wblock:
mov esi, 4194424+f_w1
call emitstr
mov eax, [rbp+20]
inc eax
call emitnum
mov esi, 4194424+f_w2
call emitstr
mov eax, [rbp+20]
inc eax
call emitnum
mov esi, 4194424+f_w3
call emitstr
mov eax, [rbp+20]
inc eax
call emitnum
mov esi, 4194424+f_w4
call emitstr
; record the literal: offset and length, at table + 8*n
mov eax, [rbp+20]
add eax, eax
add eax, eax
add eax, eax
mov [rbp+40], eax
call ldtab
mov ecx, [rbp+40]
add rax, rcx
mov edx, [rbp+32]
mov [rax], edx
mov edx, [rbp+36]
mov [rax+4], edx
mov eax, [rbp+20]
inc eax
mov [rbp+20], eax
ret

; ---- one literal, after its opening quote -------------------------------
litgo:
mov eax, [rbp+12]
mov [rbp+32], eax
mov eax, 0
mov [rbp+36], eax
litloop:
call gcur
cmp al, 34              ; closing quote
jz litdone
cmp al, 0
jz.l fail               ; a literal that never closes
mov eax, [rbp+36]
inc eax
mov [rbp+36], eax
mov eax, 1
call bump
jmp.l litloop
litdone:
mov eax, [rbp+20]
mov ecx, 9
cmp eax, ecx
jb litok
jmp.l fail              ; more than nine literals: no room in the table
litok:
ret
ret

; ---- the literal section, in order --------------------------------------
lits:
mov eax, 0
mov [rbp+40], eax
lstlp:
mov eax, [rbp+40]
mov ecx, [rbp+20]
cmp eax, ecx
jz.l lsdun
mov esi, 4194424+f_m
call emitstr
mov eax, [rbp+40]
inc eax
call emitnum
mov esi, 4194424+f_db1
call emitstr
; entry address = table + 8*n
mov eax, [rbp+40]
add eax, eax
add eax, eax
add eax, eax
mov [rbp+52], eax
call ldtab
mov ecx, [rbp+52]
add rax, rcx
mov ecx, [rax+4]
mov [rbp+52], ecx       ; length
mov ecx, [rax]
mov [rbp+28], ecx       ; offset
litcopy:
mov eax, [rbp+52]
cmp eax, 0
jz lcdone
call ldat
movzx eax, byte [rax]
call emitc
mov eax, [rbp+28]
inc eax
mov [rbp+28], eax
mov eax, [rbp+52]
dec eax
mov [rbp+52], eax
jmp.l litcopy
lcdone:
mov esi, 4194424+f_db2
call emitstr
mov esi, 4194424+f_m
call emitstr
mov eax, [rbp+40]
inc eax
call emitnum
mov esi, 4194424+f_end
call emitstr
mov eax, [rbp+40]
inc eax
mov [rbp+40], eax
jmp.l lstlp
lsdun:
ret

; ---- addresses. Each of these used to be three instructions, because the
; dialect had no disp32 and `lea rax, [rbp-40000]` could not be written. It can
; now: one instruction each, and the workaround is gone.
ldin:
lea rax, [rbp-40000]
ret
ldout:
lea rax, [rbp-30000]
ret
ldtab:
lea rax, [rbp-20000]
ret
; rax = input + cursor ; rax = input + [rbp+28]
ldcur:
call ldin
mov ecx, [rbp+12]
add rax, rcx
ret
ldat:
call ldin
mov ecx, [rbp+28]
add rax, rcx
ret

; ---- output -------------------------------------------------------------
emitc:
mov [rbp+56], al
mov eax, [rbp+16]
mov ecx, 8000
cmp eax, ecx
jb emok
emok:
mov [rbp+88], eax
call ldout
mov ecx, [rbp+88]
add rax, rcx
movzx edx, byte [rbp+56]
mov [rax], dl
mov eax, [rbp+16]
inc eax
mov [rbp+16], eax
ret
emitstr:
mov [rbp+60], esi
esloop:
mov eax, [rbp+60]
movzx eax, byte [rax]
cmp eax, 0
jz esdone
call emitc
mov eax, [rbp+60]
inc eax
mov [rbp+60], eax
jmp esloop
esdone:
ret
; emitnum: eax (0..255) in decimal, no leading zeros
emitnum:
; eax (0..65535) in decimal, no leading zeros. One digit per place value, from
; ten-thousands down to units, each emitted only if the value reaches it or a
; digit has already been printed -- `started` is what makes 100 print as 100.
mov [rbp+64], eax        ; the value being printed
mov eax, 0
mov [rbp+68], eax        ; started
mov eax, 10000
call en_dig
mov eax, 1000
call en_dig
mov eax, 100
call en_dig
mov eax, 10
call en_dig
mov eax, [rbp+64]
mov ecx, 48
add eax, ecx
call emitc               ; the units digit, always
ret

en_dig:
; eax is a place value. Prints that digit and leaves the remainder in [rbp+64].
mov ecx, eax
mov eax, [rbp+64]
cmp eax, ecx
jb en_skip               ; the value is smaller than this place
jmp en_go
en_skip:
mov eax, [rbp+68]
cmp eax, 0
jz endig                 ; nothing printed yet: a leading zero stays hidden
mov eax, 0               ; a zero digit inside the number
jmp en_put
en_go:
mov eax, [rbp+64]
mov edx, 0
div ecx
mov [rbp+64], edx        ; the remainder
en_put:
mov ecx, 48
add eax, ecx
call emitc
mov eax, 1
mov [rbp+68], eax
endig:
ret

flush:
mov eax, [rbp+16]
cmp eax, 0
jz fldone
mov [rbp+68], eax
call ldout
lea rsi, [rax]
mov eax, 1
mov edi, 1
mov edx, [rbp+68]
syscall
fldone:
ret

; ---- input --------------------------------------------------------------
; gcur: al = the current byte, 0 at end of input; does not advance
gcur:
mov eax, [rbp+12]
mov ecx, [rbp+8]
cmp eax, ecx
jb gcin
mov eax, 0
ret
gcin:
call ldcur
movzx eax, byte [rax]
ret
; bump: advance the cursor by eax
bump:
mov ecx, [rbp+12]
add ecx, eax
mov [rbp+12], ecx
ret

; skipws: whitespace, /* */ and // comments
skipws:
call gcur
cmp al, 32
jz.l sww
cmp al, 9
jz.l sww
cmp al, 10
jz.l sww
cmp al, 13
jz.l sww
cmp al, 47              ; '/'
jnz.l swdone
mov eax, 1
call bump
call gcur
cmp al, 42
jz.l swblock
cmp al, 47
jz.l swline
mov eax, [rbp+12]       ; a lone slash: step back, it is not whitespace
dec eax
mov [rbp+12], eax
ret
sww:
mov eax, 1
call bump
jmp.l skipws
swblock:
mov eax, 1
call bump
swbl:
call gcur
cmp al, 0
jz.l fail               ; unterminated comment
cmp al, 42
jz swbst
mov eax, 1
call bump
jmp.l swbl
swbst:
mov eax, 1
call bump
call gcur
cmp al, 47
jz swbend
jmp.l swbl
swbend:
mov eax, 1
call bump
jmp.l skipws
swline:
mov eax, 1
call bump
swll:
call gcur
cmp al, 0
jz.l fail               ; a line comment must end on a newline
cmp al, 10
jz swlend
mov eax, 1
call bump
jmp.l swll
swlend:
jmp.l skipws
swdone:
ret

; isword: 1 if the input at the cursor is exactly the word at esi, and consume
; it; 0 otherwise, with the cursor untouched. `want` cannot do this: a mismatch
; is fatal there, and dispatch needs to try several words in turn.
isword:
mov [rbp+100], esi
mov eax, [rbp+12]
mov [rbp+104], eax
iswl:
mov eax, [rbp+100]
movzx eax, byte [rax]
cmp eax, 0
jz iswdone
mov [rbp+108], eax
call gcur
mov ecx, [rbp+108]
cmp eax, ecx
jnz.l iswfail
mov eax, 1
call bump
mov eax, [rbp+100]
inc eax
mov [rbp+100], eax
jmp iswl
iswdone:
call gcur               ; the word must end at a delimiter
cmp al, 0
jz iswok
cmp al, 32
jz iswok
cmp al, 9
jz iswok
cmp al, 10
jz iswok
cmp al, 40
jz iswok
cmp al, 41
jz iswok
cmp al, 61
jz iswok
cmp al, 59
jz iswok
cmp al, 123
jz iswok
cmp al, 125
jz iswok
jmp.l iswfail
iswok:
mov eax, 1
ret
iswfail:
mov eax, [rbp+104]
mov [rbp+12], eax
mov eax, 0
ret

; sign: consume a '+' or '-' and return it in eax; anything else is refused
sign:
call skipws
call gcur
cmp al, 43
jz sigok
cmp al, 45
jnz.l fail
sigok:
mov [rbp+120], eax
mov eax, 1
call bump
mov eax, [rbp+120]
ret

; want: the next token must be the NUL-terminated text at esi, with whitespace
; allowed before it and after it.
want:
call skipws
mov [rbp+72], esi
wantl:
mov eax, [rbp+72]
movzx eax, byte [rax]
cmp eax, 0
jz wantend
mov [rbp+76], eax
call gcur
mov ecx, [rbp+76]
cmp eax, ecx
jnz.l fail
mov eax, 1
call bump
mov eax, [rbp+72]
inc eax
mov [rbp+72], eax
jmp.l wantl
wantend:
ret

; numval: a decimal 0..255; value in eax
numval:
call skipws
mov eax, 0
mov [rbp+80], eax
mov [rbp+84], eax
numl:
call gcur
mov ecx, eax
add cl, -48
cmp cl, 10
jb numdig
jmp.l numend
numdig:
mov eax, [rbp+84]
inc eax
mov [rbp+84], eax
mov eax, [rbp+80]
mov edx, eax
add eax, eax
add eax, eax
add eax, eax          ; 8n
add eax, edx          ; 9n
add eax, edx          ; 10n
movzx ecx, cl
add eax, ecx
mov [rbp+80], eax
mov eax, 1
call bump
jmp.l numl
numend:
mov eax, [rbp+84]
cmp eax, 0
jz.l fail               ; no digits at all
mov ecx, 6
cmp eax, ecx
jb num3ok
jmp.l fail              ; more than five digits
num3ok:
mov eax, [rbp+80]
mov ecx, 65536
cmp eax, ecx
jb num2ok
jmp.l fail              ; a value above 65535
num2ok:
ret
ret

fail:
mov eax, 1
mov edi, 2
mov esi, 4194424+f_bad
mov edx, 22
syscall
mov eax, 60
mov edi, 1
syscall

; ---- fixed text. One db per item: a string on a db line ends that line, so a
; string and a number are never mixed. ----
f_int:
db "int"
db 0
f_lpar:
db "("
db 0
f_void:
db "void"
db 0
f_rpar:
db ")"
db 0
f_lbrc:
db "{"
db 0
f_write:
db "write"
db 0
f_ret:
db "return"
db 0
f_quote:
db 34
db 0
f_semi:
db ";"
db 0
f_hdr:
db "; generated by cc: dialect source, not a program. Assemble it with asm1"
db 10
db 0
f_pro:
db "push rbp"
db 10
db "mov rbp, rsp"
db 10
db "mov rcx, 8200"
db 10
db "sub rsp, rcx"
db 10
db 0
f_arg1:
db "mov [rbp-"
db 0
f_arg2:
db "], "
db 0
argnames:
db "rdi"
db 0
db "rsi"
db 0
db "rdx"
db 0
db "rcx"
db 0

f_callk:
db "call "
db 0
f_entry:
db "entry main"
db 10
db 0

f_epi:
db "mov rsp, rbp"
db 10
db "pop rbp"
db 10
db "ret"
db 10
db 0
f_while:
db "while"
db 0
db "int"
db 0
f_eq:
db "="
db 0
f_L:
db "L"
db 0
f_jl:
db "jmp.l L"
db 0
f_dcol:
db ":"
db 10
db 0
f_nl:
db 10
db 0
f_nle:
db "e"
db 10
db 0
f_nlx:
db "x"
db 10
db 0
f_dlb:
db "b:"
db 10
db 0
f_dle:
db "e:"
db 10
db 0
f_dlt:
db "t:"
db 10
db 0
f_dlx:
db "x:"
db 10
db 0
f_ccmp:
db "cmp rax, "
db 0
f_cmov2:
db "mov rcx, "
db 0
f_ccmp2:
db 10
db "cmp rcx, rax"
db 10
db "jb "
db 0
f_cjb:
db 10
db "jb "
db 0
f_cjz:
db 10
db "jz "
db 0
f_cjnz:
db 10
db "jnz "
db 0
f_if:
db "if"
db 0
f_else:
db "else"
db 0
f_ls2:
db "], rax"
db 10
db 0
f_le1:
db "mov rax, [rbp-"
db 0
f_le2:
db "]"
db 10
db 0
f_ls1:
db "mov [rbp-"
db 0
f_mov:
db "mov "
db 0
f_cev:
db ", [rbp-"
db 0
f_brk:
db "]"
db 0
f_sep:
db ", "
db 0
f_add:
db "add "
db 0
f_sub:
db "sub "
db 0
f_imul:
db "imul "
db 0
f_edi:
db "mov rdi, rax"
db 10
db "mov eax, 60"
db 10
db "syscall"
db 10
db 0
regnames:
db "rax"
db 0
db "rcx"
db 0
db "rdx"
db 0
db "rsi"
db 0
db "rdi"
db 0
db "r8"
db 0
f_w1:
db "mov eax, 1"
db 10
db "mov edi, 1"
db 10
db "mov esi, 4194424+m"
db 0
f_w2:
db 10
db "mov edx, m"
db 0
f_w3:
db "end-m"
db 0
f_w4:
db 10
db "syscall"
db 10
db 0
f_m:
db "m"
db 0
f_db1:
db ":"
db 10
db "db "
db 34
db 0
f_db2:
db 34
db 10
db 0
f_end:
db "end:"
db 10
db 0
f_bad:
db "cc: not in the subset"
db 10
f_lea1:
db "lea "
db 0
f_dref1:
db ", ["
db 0
f_lst1:
db "mov [rcx], "
db 0
f_rax:
db "rax"
db 0
f_rbrk:
db "]"
db 0
f_isav:
db "mov [rbp-284], "
db 0
f_push:
db "push "
db 0
f_pop:
db "pop "
db 0
f_char:
db "char"
db 0
f_movzx:
db "movzx "
db 0
f_drefb:
db ", byte ["
db 0
f_lstb:
db "mov [rcx], al"
db 10
db 0
f_xor:
db "xor "
db 0
f_rdx:
db "rdx"
db 0
f_div:
db "div "
db 0
f_mrdx:
db ", rdx"
db 10
db 0
f_rax2:
db ", rax"
db 10
db 0
f_rd1:
db "mov eax, 0"
db 10
db "mov edi, 0"
db 10
db "lea rsi, [rbp-"
db 0
f_rd2:
db "]"
db 10
db "mov edx, "
db 0
f_rd3:
db 10
db "syscall"
db 10
db 0
f_comma:
db ","
db 0
f_lbr2:
db "[rbp-"
db 0
f_cmp1:
db "cmp rax, rcx"
db 0
f_cmp2:
db "cmp rcx, rax"
db 0
f_incrcx:
db 10
db "inc rcx"
db 10
db 0
f_decrcx:
db 10
db "dec rcx"
db 10
db 0
f_rsi:
db "rsi"
db 0
f_wr1:
db "mov eax, 1"
db 10
db "mov edi, 1"
db 10
db "syscall"
db 10
db 0
