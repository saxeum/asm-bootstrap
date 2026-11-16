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
;   * `return N;` is optional and must be last; N is 0..255
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
mov [rbp-212], eax      ; not inside an expression
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

; argexpr: an argument expression -- terms joined by + and -, left to right.
; Deliberately not the full expression parser: calling `expr` from inside an
; expression broke the symbol-name buffer (docs/cc.md), so this walks terms at
; the two registers eax/ecx without recursion. `*` is not accepted here.
argexpr:
mov eax, 0
mov [rbp-128], eax
call ex3                ; the first term, into eax
argxl:
call skipws
call gcur
cmp al, 43
jz argxo
cmp al, 45
jnz argxd
argxo:
mov [rbp-132], eax      ; the operator
mov eax, 1
call bump
mov eax, 1
mov [rbp-128], eax      ; the right term goes into ecx
call ex3
mov eax, 0
mov [rbp-128], eax
mov eax, [rbp-132]
cmp eax, 43
jz argxa
mov esi, 4194424+f_asub
call emitstr
jmp argxl
argxa:
mov esi, 4194424+f_aadd
call emitstr
jmp argxl
argxd:
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
mov eax, 0
mov [rbp-128], eax     ; an argument is one term, not an expression
call argexpr           ; an argument: terms joined by + and -
mov esi, 4194424+f_mov
call emitstr
mov eax, [rbp-168]
call emitarg
mov esi, 4194424+f_mveax
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

stintarr:
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
call callargs
mov esi, 4194424+f_semi
call want
jmp.l bodloop

stsub:
; `a[i] = v;` -- the scaled index is parked at -284 because `want` and `expr`
; own every register; the address is built after the value is in rax
mov eax, 1
call bump               ; '['
call findvar
mov [rbp-268], eax
call isarr
cmp eax, 0
jnz stsok
jmp.l fail
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
mov esi, 4194424+f_lea1
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
mov esi, 4194424+f_lst1
call emitstr
mov esi, 4194424+f_rax
call emitstr
mov esi, 4194424+f_nl
call emitstr
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
; An expression inside an expression is REFUSED, not attempted. Nesting the
; parser corrupted the symbol-name buffer in a way that is still unexplained
; (docs/cc.md): the value 1 appeared where a variable's name should have been,
; and no amount of reading found the writer. A call argument therefore uses
; argexpr (terms at eax/ecx, no recursion), and if anything ever nests expr
; again this refuses with a line number instead of corrupting silently.
mov eax, [rbp-212]
cmp eax, 0
jz exprok
jmp.l failnest
exprok:
mov eax, 1
mov [rbp-212], eax
mov eax, 0
call exprd
mov eax, 0
mov [rbp-212], eax
ret

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
jnz ex2d
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
; a call is allowed only as a whole expression: its arguments would clobber the
; temporaries of an enclosing one
mov eax, [rbp-128]
cmp eax, 0
jz ex3cok
jmp.l fail
ex3cok:
mov eax, [rbp-208]
cmp eax, 0
jz ex3fin
jmp.l fail              ; a call inside an argument list would clobber the arg registers
ex3fin:
call callargs
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
; it, so nothing is parked; the slot offset lives at -244 because expr owns -140
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


ex3sub:
; `a[i]` -- the base goes into reg d and the index is computed at d+1, so the
; base survives: that is what the depth mechanism is for. d is saved in -288
; because exprd overwrites [rbp-128] with its own depth.
mov eax, 1
call bump               ; '['
call findvar
mov [rbp-268], eax      ; the array's index: must survive the index parse
call isarr
cmp eax, 0
jnz ex3sok
jmp.l fail              ; `x[i]` where x is not an array
ex3sok:
mov eax, [rbp-236]
cmp eax, 0
jz ex3sgo
jmp.l fail              ; a subscript inside a subscript: refused, docs/cc.md
ex3sgo:
mov eax, 1
mov [rbp-236], eax
mov eax, [rbp-128]
mov [rbp-288], eax      ; d: the base's register
mov eax, [rbp-268]
call varoff
mov [rbp-272], eax
mov esi, 4194424+f_lea1
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
mov esi, 4194424+f_rbrk
call want
mov eax, 0
mov [rbp-236], eax
ret

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
; scan a name: letters, digits and '_', at most seven characters, not starting
; with a digit. Leaves the padded name at rbp-16064 and its length in [rbp-100].
mov eax, 0
mov [rbp-16064], eax
mov [rbp-16060], eax
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
cmp ecx, 7
jb idstore
jmp.l fail              ; longer than seven characters
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
add eax, eax            ; 8i
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

; defvar: declare the current name, refusing a repeat or a ninth variable
defvar:
call idfind
cmp eax, -1
jnz.l fail              ; already declared
mov eax, [rbp-108]
cmp eax, 8
jb defok
jmp.l fail              ; ninth variable
defok:
mov edx, eax
add eax, eax
add eax, eax
add eax, eax            ; 8i
lea rcx, [rbp-16000]
add rcx, rax
mov eax, [rbp-16064]
mov [rcx], eax
mov eax, [rbp-16060]
mov [rcx+4], eax
mov eax, [rbp-108]
inc eax
mov [rbp-108], eax
dec eax                 ; the new variable's index
ret

; ---- arrays ---------------------------------------------------------------
; `int a[N];` allocates N consecutive slots and marks the name an array in a
; byte-per-slot table at rbp-14000. The slots after the first have their name
; zeroed, because ident never produces an empty name -- so they can never be
; found, and a bare `a` is refused rather than quietly reading a[0].
;   [rbp-256] count   [rbp-260] base index   [rbp-264] loop index
defarr:
mov [rbp-256], eax
call idfind
cmp eax, -1
jnz.l fail              ; already declared
mov eax, [rbp-108]
mov edx, [rbp-256]      ; the dialect has no `add r32, [mem]`
add eax, edx
cmp eax, 8
jb defafit
jmp.l fail              ; does not fit in the eight slots
defafit:
mov eax, [rbp-108]
mov [rbp-260], eax
mov [rbp-264], eax
defazl:
mov eax, [rbp-264]
mov ecx, [rbp-108]
mov edx, [rbp-256]
add ecx, edx
cmp eax, ecx
jz defazd
mov edx, eax
add eax, eax
add eax, eax
add eax, eax
lea rcx, [rbp-16000]
add rcx, rax
mov eax, 0
mov [rcx], eax
mov [rcx+4], eax        ; no name: this slot cannot be found
mov eax, [rbp-264]
lea rcx, [rbp-14000]
add rcx, rax
mov eax, 0
mov [rcx], al           ; and not an array itself
mov eax, [rbp-264]
inc eax
mov [rbp-264], eax
jmp defazl
defazd:
mov eax, [rbp-260]
add eax, eax
add eax, eax
add eax, eax
lea rcx, [rbp-16000]
add rcx, rax
mov eax, [rbp-16064]
mov [rcx], eax
mov eax, [rbp-16060]
mov [rcx+4], eax
mov eax, [rbp-260]
lea rcx, [rbp-14000]
add rcx, rax
mov eax, 1
mov [rcx], al
mov eax, [rbp-108]
mov edx, [rbp-256]
add eax, edx
mov [rbp-108], eax
mov eax, [rbp-260]
ret

; isarr: eax = index, result eax = 1 if that slot is an array
isarr:
lea rcx, [rbp-14000]
add rcx, rax
movzx eax, byte [rcx]
ret

; varoff: eax = index, result eax = the byte offset 8*(index+1)
varoff:
mov ecx, eax
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
call numval
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
call numval
mov [rbp+124], eax
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
call numval
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
call numval
mov [rbp+124], eax
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
call numval
mov [rbp+124], eax
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
call numval
mov [rbp+124], eax
mov eax, 2
mov [rbp+44], eax
ret

; condj: emit the test and a jump-if-TRUE to L<id><letter>, the letter being in
; [rbp+92] and the id in [rbp+96]
condj:
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
; decimal, no leading zeros: the hundreds and tens digits are emitted only if
; something has already been emitted or they are non-zero, and the ones digit is
; always emitted. `started` is what makes 100 print as 100 and not as 10.
mov [rbp+64], eax
mov eax, 0
mov [rbp+68], eax
mov eax, [rbp+64]
cmp eax, 100
jb en_ten
mov eax, [rbp+64]
mov edx, 0
mov ebx, 100
div bl
movzx ecx, ah           ; the remainder, before anything else clobbers rax
mov [rbp+64], ecx
movzx eax, al
mov ecx, 48
add eax, ecx
call emitc
mov eax, 1
mov [rbp+68], eax
en_ten:
mov eax, [rbp+64]
cmp eax, 10
jb en_maybe
mov eax, [rbp+64]
mov edx, 0
mov ebx, 10
div bl
movzx ecx, ah
mov [rbp+64], ecx
movzx eax, al
mov ecx, 48
add eax, ecx
call emitc
jmp en_one
en_maybe:
mov eax, [rbp+68]
cmp eax, 0
jz en_one
mov eax, 48
call emitc
en_one:
mov eax, [rbp+64]
mov ecx, 48
add eax, ecx
call emitc
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
mov ecx, 4
cmp eax, ecx
jb num3ok
jmp.l fail              ; more than three digits cannot be 0..255
num3ok:
mov eax, [rbp+80]
mov ecx, 256
cmp eax, ecx
jb num2ok
jmp.l fail              ; a value above 255
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

failnest:
mov eax, 1
mov edi, 2
mov esi, 4194424+f_nest
mov edx, 32
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
db "mov rcx, 64"
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
f_mveax:
db ", rax"
db 10
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
f_aadd:
db 10
db "add rax, rcx"
db 10
db 0
f_asub:
db 10
db "sub rax, rcx"
db 10
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
f_nest:
db "cc: internal: nested expression"
db 10
db 0
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
