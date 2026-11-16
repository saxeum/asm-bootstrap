# Frozen oracles

These three binaries were written **by hand**, byte by byte, before any assembler existed.
They are the standard every later wave is measured against: an assembler is correct when its
output for the same source is byte-identical to one of these.

| file | size | sha256 |
|---|---|---|
| `hello`   | 165 B | `4f386903…6552e1` |
| `count10` | 188 B | `e61a23c9…94ec5bd9a` |
| `fib`     | 334 B | `f61cea2c…2e10098` |
| `jmp`     | 139 B | `f1efca3a…b0fd1de` |  wave 2b: a forward jump, exits 7 not 99
| `loop`    | 140 B | `5ca623d6…` |  wave 2c: inc/dec/jnz, exits 10 (iteration count)
| `store`   | 138 B | `5129e1e0…` |  wave 2d-8: `mov [mem],r32` + load, exits 7 |
| `load`    | 138 B | `24e4f4c8…` |  wave 2d-7: `mov r32,[mem]`, exits 7 |
| `dbnum`   | 154 B | `902aa1d8…` |  wave 2d-6: numeric `db`, prints `Hi\n` |
| `stack`   | 160 B | `f0a494b0…` |  wave 2d-4: memory operands + lea, prints `H\n` |
| `cmp8`    | 146 B | `72925399…` |  wave 2d-3: cmp/add/jb on 8-bit regs, exits 12 |
| `inc8`    | 140 B | `34ad16b7…` |  wave 2d-2: inc/dec on 8-bit regs, exits 3 |
| `r8`      | 132 B | `9fdbe699…` |  wave 2d-1: 8-bit mov plus movzx, exits 7 |
| `jz`      | 146 B | `8cb07cc9…` |  wave 2c: dec/jz, exits 5 not 99

Rules:

- **Never regenerate them casually.** A binary whose bytes you did not write by hand cannot
  judge an assembler. If one must be rebuilt, it is rebuilt from the recorded `printf` byte
  emitters and checked against the sha above — anything else is a rewrite, not a repair.
- They are checked by `sha256sum -c docs/SHAS`, run from the repository root.
- `count10` and `fib` are oracles for waves that do not exist yet; they stay here unexamined
  until the assembler can express them.
