#!/bin/sh
# SUSPENDED.
#
# This checker decoded asm0a with objdump, and objdump is forbidden: a disassembler
# is the tool this project exists to replace, so it cannot be the thing that
# verifies us. The check has been removed rather than left running, because a gate
# that runs a forbidden tool and reports green is worse than no gate at all.
#
# What it did, and what src/dis.s must do instead: given a binary and a byte offset,
# return the mnemonic and the branch target for
#
#     EB  jmp rel8        E9  jmp rel32       E8  call rel32
#     70-7F  jcc rel8     0F 80-0F 8F  jcc rel32
#
#     target = site + instruction length + displacement
#
# docs/branches.tsv — the 290 pinned sites — stays in the tree: it is hand-recorded
# evidence, and src/dis.s should be validated against it. Until then it is unverified.
#
# This script exits 2 and never reports success.

echo "  branch pins: SUSPENDED -- the decoder must be written in the dialect (src/dis.s)"
echo "               docs/branches.tsv holds 290 recorded sites, currently unverified"
exit 2
