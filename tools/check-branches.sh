#!/bin/sh
# The branch-pin gate: docs/branches.tsv checked against asm0a by OUR decoder.
#
# It used to shell out to objdump, which is forbidden -- a disassembler is the
# tool this project exists to replace, so it cannot be the thing that verifies
# us. src/dis.s is that check now, assembled by asm1, and every line below is
# compared with cmp rather than with a status.
#
# The pins are hand-recorded evidence (290 sites, recorded before dis.s existed)
# and this gate is the first time they have been checked by something in the
# project. It validates the recording, not the encoder: a site that dis agrees
# with is a site whose bytes and recorded target agree.
#
# Three ways this gate refuses to be quietly green:
#   1. no decoder, no subject, or a table shorter than the 290 recorded pins;
#   2. a deliberate mismatch it must report (the gate can fail);
#   3. any pin whose line does not match byte for byte.

set -u
cd "$(dirname "$0")/.."

DIS=./dis
BIN=asm0a
TSV=docs/branches.tsv
MIN=290

short() { sha256sum "$1" | cut -c1-16; }

[ -x "$DIS" ] || { echo "  branch pins: NO DECODER -- run make dis"; exit 1; }
[ -f "$BIN" ] || { echo "  branch pins: NO SUBJECT $BIN"; exit 1; }
[ -f "$TSV" ] || { echo "  branch pins: NO TABLE $TSV"; exit 1; }

n=$(grep -c . "$TSV")
if [ "$n" -lt "$MIN" ]; then
	echo "  branch pins: $TSV holds $n sites, was $MIN -- pins were lost"
	exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A gate that cannot fail is a format check wearing a gate's clothes. Take the
# first pin and require the decoder NOT to produce a line with a wrong target.
site=$(head -1 "$TSV" | cut -d' ' -f1)
"$DIS" "$site" < "$BIN" > "$tmp/got" 2>/dev/null
printf '%s\n' "$site 0xdead add" > "$tmp/want"
if cmp -s "$tmp/got" "$tmp/want"; then
	echo "  branch pins: the gate cannot fail -- a wrong line compared equal"
	exit 1
fi

ok=0
bad=0
while read -r site target mnem; do
	[ -n "$site" ] || continue
	printf '%s\n' "$site $target $mnem" > "$tmp/want"
	if "$DIS" "$site" < "$BIN" > "$tmp/got" 2>/dev/null && cmp -s "$tmp/got" "$tmp/want"; then
		ok=$((ok + 1))
	else
		bad=$((bad + 1))
		echo "  pin $site: got '$(cat "$tmp/got")', recorded '$site $target $mnem'"
	fi
done < "$TSV"

if [ "$bad" -ne 0 ]; then
	echo "  branch pins: $ok/$n agree, $bad DISAGREE"
	exit 1
fi

printf '  branch pins: %s/%s decoded by src/dis.s -- %s sha %s, dis sha %s\n' \
	"$ok" "$n" "$BIN" "$(short "$BIN")" "$(short "$DIS")"
