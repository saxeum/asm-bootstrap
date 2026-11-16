# `asm1.s` — the implementation plan

Goal: an assembler written in this dialect, assembled by `asm0a`, which then assembles **itself**:

```
X  = asm0a(asm1.s)      must be a working assembler
X' = X(asm1.s)          must equal X
```

`X == asm0a` is *not* required. `asm1.s` is a new program, not a transcription of `asm0a`'s bytes.

The I/O skeleton is already written and verified (`src/cat.s`): read all of stdin into the stack,
loop over it with a moving pointer, emit one byte per iteration, exit. That is the shape of an
assembler with the parsing removed, and it runs.

## CORRECTION: text scanning is not currently expressible

The first draft of this plan claimed "nothing in the design needs a form this assembler cannot
emit". **That is false**, and step 2 of the build order exposed it.

Finding a `'\n'`, or testing whether a byte is `';'`, needs to read **one byte**. Probed against
`asm0a` directly:

```
mov al, [rsi]                rejected
movzx eax, byte [rsi]        rejected        <- the form that is missing
shr eax, 8                   rejected
and eax, 255                 rejected
cmp al, 10                   accepted, but al can only arrive from a register
mov eax, [rsi]               accepted, 4-byte window only
```

A 4-byte window cannot substitute: `cmp eax, 10` matches only when the whole dword is
`0x0000000a`, which real text is not. Without a byte load or a shift/mask, **no byte can be
isolated from memory**, and therefore no text can be scanned. The mnemonic-matching trick from
`src/window.s` works because it compares four *known* characters at a known position; it cannot
search for an unknown one.

### The fix, and why it is small

Add one form to `asm0a`: **`movzx r32, byte [mem]`** (`0F B6 /r` with a memory operand). Everything
it needs already exists — `do_movzx` resolves `r32 <- r8`, and `memop2` + `emit_mem` already turn
`[base]` / `[base+disp8]` into `modrm`+`SIB`+`disp`, exactly as `mov r32,[mem]` uses. The change is
a branch after the comma: if the operand begins with `[`, call `memop2`, emit `0F B6`, call
`emit_mem`. Roughly 25 bytes, using two helpers that are already verified.

Then byte scanning is expressible as `movzx eax, byte [rsi]` + `cmp al, 10` — and `cmp r8,imm8`
already exists.

**So the ordering is:** add `movzx [mem]` to `asm0a`, verify it (fixture: a program that finds the
end of the first line and exits with its length), and only then write step 2 of `asm1.s`.

## The three dialect constraints the design is built around

1. **No `movzx r32, byte [mem]`.** Read four bytes with `mov r32,[mem]` and compare the whole word
   against a packed literal with `cmp r32,imm32`. Verified in `src/window.s`
   (`"mov "` → `0x20766f6d`).
2. **No displacement beyond ±127.** Never index a buffer; carry a moving pointer and access
   `[rsi]` at displacement zero. Advance with `lea rsi,[rsi+1]`.
3. **No `mov r64,r64`.** `lea rdi,[rsi]` is the move; `lea rsi,[rsp+N]` is how a buffer address is
   taken.

## Memory layout — everything reachable with `disp8`

| range | use |
|---|---|
| `[rsp+0]` | output scratch: the byte being emitted |
| `[rsp+4]` | saved input pointer (see "the rsi conflict") |
| `[rsp+8]` .. `[rsp+103]` | label table: 8 entries × 12 bytes (8-byte name, 4-byte offset) |
| `[rsp+104]` | pass flag (0 = first pass, 1 = second) |
| `[rsp+108]` | saved label count |
| `[rsp+120]` .. | input buffer, `read` up to 4000 bytes |

`disp8` is signed, so the largest safe offset here is 120. That number, not 127, is what sets the
layout: input starts at `rsp+120` and the table has to fit below it.

## Register allocation

| register | holds | why it cannot hold anything else |
|---|---|---|
| `rsi` | input pointer | it moves, and it must be a full 64-bit pointer |
| `rbp` | label-table base | **not** a syscall argument |
| `rbx` | label count | not a syscall argument |
| `rax` `rcx` `rdx` `rdi` | scratch | they are all syscall arguments |

**The `rdi` conflict.** `write` needs `rdi` = fd, so `rdi` cannot hold the table base; that is why
the table base lives in `rbp`. **The `rsi` conflict.** `write` needs `rsi` = buffer, but `rsi` is
the input pointer. Every emitted byte therefore costs:

```
mov [rsp+4], rsi        ; save the input pointer
lea rsi, [rsp]          ; buffer = the scratch byte
mov eax, 1
mov edi, 1
mov edx, 1
syscall
mov rsi, [rsp+4]        ; restore it
```

One syscall per byte is slower than buffering, and deliberate: it removes the second buffer, its
fill and flush logic, and the off-by-one at flush. Speed is not a goal here.

## Parsing, per line

```
skip spaces
if byte == 0        -> end of buffer: pass boundary
if byte == ';'      -> skip to '\n', next line
load 4-byte window at rsi
compare against packed mnemonics, in order, longest first:
    "sysc" "mov " "movz" "xor " "lea " "cmp " "jmp " "jz  " "jnz " "jb  " "inc " "dec "
    "add " "sub " "div " "db  " "test" "imul"
on match: parse operands, emit, skip the mnemonic
no match: is it a label? scan forward: a ':' before any space means a definition
          else error: exit 2
skip to '\n', next line
```

Label detection has to happen when no mnemonic matched, not before: `jmp` and `jz` both begin with
`j`, and `skip:` begins with `s`, which is also `syscall`'s first letter — `asm0a` learned this the
hard way in wave 2b-1.

## Two passes

Pass 1 records `label -> byte offset` and emits nothing but keeps a *virtual* offset (a counter,
not `r15`). Pass 2 emits with the table filled. The counter is what the pass-2 jump displacement is
computed against:

```
rel8 = label_offset - (current_offset + 2)      ; jmp/jcc short
       label_offset - (current_offset + 5)      ; jmp.l
       label_offset - (current_offset + 6)      ; jcc.l
```

**A branch whose label is not yet known in pass 1 must still advance the offset by the width the
final encoding will have.** That is the finding from wave 2d-12, where a 2-byte placeholder against
a 5-byte final jump made every later label disagree between passes. With a counter instead of a
byte buffer this cannot happen — the counter advances by the encoded width, which is known from the
mnemonic alone.

## Estimate and order of work

About 600–800 instructions. Build it in the order that keeps it runnable at every step:

1. **cat** — done (`src/cat.s`).
2. **cat with line awareness**: skip `;` comments and blank lines. Testable by round-trip.
3. **emit one hard-coded instruction per matched mnemonic**: recognise `syscall`, `mov r32,imm`,
   `db` and emit them. Testable: assemble a 3-line source and compare with `asm0a`'s output.
4. **labels + pass 2**: assemble something with a forward jump.
5. **the rest of the mnemonic set**, one at a time, each verified against `asm0a` on the same
   source.
6. **fixpoint**: `X = asm0a(asm1.s)`, then `X(asm1.s) == X`.

Step 5 is the point where the oracle changes: from then on, each new form is verified by
`asm0a` and `asm1` agreeing byte for byte on the same source, which is a *differential test between
two independent implementations* rather than against a hand-emitted fixture.
