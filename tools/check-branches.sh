#!/usr/bin/env bash
# check-branches.sh — pin every branch site in the artifact and prove the pin still holds.
#
#   tools/check-branches.sh [binary] [table]   check every pinned site; exit 1 on any mismatch
#   tools/check-branches.sh --selftest         prove the checker can fail
#
# Each table line:   SITE  INTENDED_TARGET  MNEMONIC
#
# The intended target is what that branch pointed at when the artifact was verified. A later
# patch that lands one byte off, or that shifts a neighbour, changes either the decoded mnemonic
# or the decoded target — and is caught here rather than by a segfault three waves later. Ten of
# this project's defects were exactly that class.
set -uo pipefail

decode() {  # decode <binary> <site> -> "mnemonic operands"
    objdump -D -b binary -m i386:x86-64 \
            --start-address="$2" --stop-address=$(( $2 + 9 )) "$1" 2>/dev/null \
      | awk -F'\t' '$3 != "" { print $3; exit }'
}

check_table() {  # check_table <binary> <table> -> failures in $?
    local bin=$1 table=$2 site want mnem text got_t got_m bad=0
    while read -r site want mnem; do
        [ -z "${site:-}" ] && continue
        text=$(decode "$bin" "$site")
        got_m=$(printf '%s\n' "$text" | awk '{print $1}')
        got_t=$(printf '%s\n' "$text" | grep -o '0x[0-9a-f]\+' | tail -1)
        if [ "$got_t" = "$want" ] && [ "$got_m" = "$mnem" ]; then
            printf '  ok   %-7s %-6s -> %-7s  %s\n' "$site" "$mnem" "$want" "$text"
        else
            printf '  FAIL %-7s want %-6s %-7s got %-7s  %s\n' \
                   "$site" "$mnem" "$want" "${got_t:-none}" "${text:-<undecodable>}"
            bad=$(( bad + 1 ))
        fi
    done < "$table"
    return "$bad"
}

if [ "${1:-}" = "--selftest" ]; then
    # Three sites that were genuinely wrong in waves 2d-5, 2d-6 and 2d-7: each was patched at
    # opcode+1 instead of opcode+2, so the instruction there is not what was intended. The
    # checker MUST reject all three. If it passes, it is a format check pretending to be a gate.
    bin=${2:-asm0a}
    tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
    printf '0x15e 0x110 je\n0x5c5 0x5de je\n0x1b6 0xa9b jne\n' > "$tmp"
    echo "selftest: three known-bad sites from the log ($bin) — all must FAIL"
    if check_table "$bin" "$tmp" >/dev/null; then
        echo 'selftest FAILED: the checker accepted known-bad sites' >&2
        exit 1
    fi
    echo 'selftest ok: the checker rejects known-bad sites'
    exit 0
fi

bin=${1:-asm0a}
table=${2:-docs/branches.tsv}
echo "checking $(wc -l < "$table") pinned branch sites in $bin"
if check_table "$bin" "$table"; then
    echo "all pinned branches hold"
else
    echo "PINNED BRANCHES CHANGED" >&2
    exit 1
fi
