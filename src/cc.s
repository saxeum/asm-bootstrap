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
mov eax, 0
mov [rbp+12], eax
mov [rbp+8], eax
mov [rbp+16], eax
mov [rbp+20], eax
mov [rbp+24], eax
mov [rbp+48], eax
mov eax, 0
mov [rbp+96], eax
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

; ---- the one function header --------------------------------------------
mov esi, 4194424+f_int
call want
mov esi, 4194424+f_main
call want
mov esi, 4194424+f_lpar
call want
mov esi, 4194424+f_void
call want
mov esi, 4194424+f_rpar
call want
mov esi, 4194424+f_lbrc
call want
mov esi, 4194424+f_hdr
call emitstr
mov esi, 4194424+f_pro
call emitstr
call body
mov esi, 4194424+f_exit
call emitstr
mov eax, [rbp+48]
call emitnum
mov esi, 4194424+f_exit2
call emitstr
call lits
call skipws
call gcur
cmp al, 0
jnz.l fail
call flush
mov eax, 60
mov edi, 0
syscall

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
call gcur
cmp al, 120             ; 'x' begins an assignment
jz.l stasg
jmp.l fail
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
mov esi, 4194424+f_x
call want
mov esi, 4194424+f_eq
call want
call numval
mov [rbp+116], eax
mov esi, 4194424+f_semi
call want
mov esi, 4194424+f_i1
call emitstr
mov eax, [rbp+116]
call emitnum
mov esi, 4194424+f_i2
call emitstr
jmp.l bodloop
stasg:
mov esi, 4194424+f_x
call want
mov esi, 4194424+f_eq
call want
mov esi, 4194424+f_x
call want
mov esi, 4194424+f_a1
call emitstr
call sign
mov [rbp+116], eax
call numval
call emitnum
mov eax, [rbp+116]
cmp eax, 43
jz stplus
mov esi, 4194424+f_s2
call emitstr
jmp stasg2
stplus:
mov esi, 4194424+f_a2
call emitstr
stasg2:
mov esi, 4194424+f_semi
call want
jmp.l bodloop
streto:
mov eax, [rbp+112]
cmp eax, 1
jnz.l fail              ; `return` is only allowed at function level
call numval
mov [rbp+48], eax
mov eax, 0
mov [rbp+96], eax
mov [rbp+112], eax
mov [rbp+116], eax
mov eax, 1
mov [rbp+24], eax
mov esi, 4194424+f_semi
call want
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
; ---- a condition: `x`, or `x <op> number` --------------------------------
; Only `jb`, `jz` and `jnz` exist, so the six relations are expressed three
; ways: unsigned `jb` with the operands in the right order (which covers < and,
; by swapping, >), `jz`/`jnz` for equality, and `<=`/`>=` normalised to < / >
; with the bound adjusted. Exact for the 0..255 the subset allows.
; [rbp+44] = jump kind (0 jb, 1 jz, 2 jnz, 3 jb with swapped operands)
; [rbp+124] = the bound, already adjusted
cond:
mov esi, 4194424+f_x
call want
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
mov esi, 4194424+f_cmov
call emitstr
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
call cond
mov esi, 4194424+f_rpar
call want
mov esi, 4194424+f_lbrc
call want
call newid
mov esi, 4194424+f_L
call emitstr
mov eax, [rbp+96]
call emitnum
mov esi, 4194424+f_dcol
call emitstr
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
mov [rbp+8], eax
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

; ---- fixed text. One db per item: a string on a db line ends that line, so a
; string and a number are never mixed. ----
f_int:
db "int"
db 0
f_main:
db "main"
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
db "main:"
db 10
db 0
f_pro:
db "push rbp"
db 10
db "mov rbp, rsp"
db 10
db 0
f_while:
db "while"
db 0
db "int"
db 0
f_x:
db "x"
db 0
f_eq:
db "="
db 0
f_L:
db "L"
db 0
f_i1:
db "mov eax, "
db 0
f_i2:
db 10
db "mov [rbp-8], eax"
db 10
db 0
f_a1:
db "mov eax, [rbp-8]"
db 10
db "mov ecx, "
db 0
f_a2:
db 10
db "add eax, ecx"
db 10
db "mov [rbp-8], eax"
db 10
db 0
f_s2:
db 10
db "sub eax, ecx"
db 10
db "mov [rbp-8], eax"
db 10
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
f_nlb:
db "b"
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
f_cmov:
db "mov eax, [rbp-8]"
db 10
db 0
f_ccmp:
db "cmp eax, "
db 0
f_cmov2:
db "mov ecx, "
db 0
f_ccmp2:
db 10
db "cmp ecx, eax"
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
f_exit:
db "mov eax, 60"
db 10
db "mov edi, "
db 0
f_exit2:
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
db 0
