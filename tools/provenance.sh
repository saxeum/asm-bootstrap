#!/bin/sh
# Provenance for this project: which assembler binary produced which artifact.
#
# asm0a is frozen; all development happens in src/asm1.s, so asm1 changes and
# any artifact it produces has to be attributable to a specific asm1. Every
# record here is a sha256 pair -- the assembler and the artifact -- because a
# name like "asm1" identifies nothing once asm1 has been rebuilt.
#
#   tools/provenance.sh record          rebuild and write the ledger
#   tools/provenance.sh verify          rebuild and compare to the ledger
#   tools/provenance.sh which FILE...   which assembler(s) produced FILE
#
# The ledger is written only by `record`, never by `verify`: recording is an
# assertion that a change is intended, and a build step that silently absorbed
# drift would be exactly how a stale record goes unnoticed.

set -e
cd "$(dirname "$0")/.."

LEDGER=docs/provenance.tsv
ASM1_SHA=docs/asm1.sha

# fixtures whose oracle is ref/<name>
PAIRS="addr32 callret cmp32 cmp8 count10 dbnum inc8 jmp jz load loop movrr r8 rel32 stack store"
# src/hello_num.s has the hand-written ref/hello as its oracle
HELLO=hello_num
# artifacts with no independent oracle: a program assembled by asm1, whose check
# is that asm1 reproduces the built file byte for byte. asm0a cannot assemble
# these -- that is the point of them -- so they are recorded for asm1 only.
NOORACLE="dis"

sha() { sha256sum "$1" | cut -d' ' -f1; }

# assemble every fixture with each given assembler, printing ledger lines
emit() {
	for a in "$@"; do
		[ -x "./$a" ] || { echo "provenance: ./$a is not executable" >&2; exit 1; }
		asha=$(sha "./$a")
		for f in $PAIRS $HELLO; do
			ref=ref/$f
			[ "$f" = "$HELLO" ] && ref=ref/hello
			"./$a" < "src/$f.s" > "$TMP/$f" || {
				echo "provenance: $a cannot assemble $f.s" >&2; exit 1; }
			if ! cmp -s "$TMP/$f" "$ref"; then
				echo "provenance: $a does not reproduce $ref -- not recording" >&2
				exit 1
			fi
			printf '%s\t%s\t%s\t%s\n' "$f" "$(sha "$TMP/$f")" "$a" "$asha"
		done
	done
}

TMP=$(mkdir -p "$(dirname "$0")/../.work" && mktemp -d "$(dirname "$0")/../.work/XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# the no-oracle artifacts, assembled by asm1 and compared with the built file
emit_no() {
	[ -x ./asm1 ] || { echo "provenance: ./asm1 is not executable" >&2; exit 1; }
	asha=$(sha ./asm1)
	for f in $NOORACLE; do
		./asm1 < "src/$f.s" > "$TMP/$f" || {
			echo "provenance: asm1 cannot assemble $f.s" >&2; exit 1; }
		if [ -f "./$f" ] && ! cmp -s "$TMP/$f" "./$f"; then
			echo "provenance: asm1 does not reproduce ./$f from src/$f.s" >&2
			exit 1
		fi
		printf '%s\t%s\t%s\t%s\n' "$f" "$(sha "$TMP/$f")" asm1 "$asha"
	done
}

# cc is built from src/cc.c: seed/cc makes the text, asm1 assembles it. The
# ledger names the assembler that produced the bytes; the compiler that made
# the text is recorded by seed/cc's own sha and by docs/toolchain.tsv.
emit_cc() {
	[ -x ./cc ] || { echo "provenance: ./cc is not executable" >&2; exit 1; }
	printf 'cc\t%s\tasm1\t%s\n' "$(sha ./cc)" "$(sha ./asm1)"
}
case "$1" in
record)
	[ -x ./asm1 ] || { echo "provenance: build asm1 first (make asm1)" >&2; exit 1; }
	sha256sum ./asm1 > "$ASM1_SHA.tmp"
	printf '  %s\n' "$(cat "$ASM1_SHA.tmp")" | sed 's/^  /asm1 sha256 /'
	mv "$ASM1_SHA.tmp" "$ASM1_SHA"
	{ emit asm0a asm1; emit_no; emit_cc; } | sort > "$LEDGER.tmp"
	mv "$LEDGER.tmp" "$LEDGER"
	echo "  recorded $LEDGER ($(wc -l < "$LEDGER" | tr -d ' ') lines) and $ASM1_SHA"
	;;
verify)
	[ -f "$LEDGER" ] || { echo "provenance: $LEDGER missing; run make record" >&2; exit 1; }
	{ emit asm0a asm1; emit_no; emit_cc; } | sort > "$TMP/now.tsv"
	if cmp -s "$TMP/now.tsv" "$LEDGER"; then
		echo "  provenance: $(wc -l < "$LEDGER" | tr -d ' ') records reproduced exactly"
	else
		echo "  PROVENANCE CHANGED:"
		diff -u "$LEDGER" "$TMP/now.tsv" | sed -n '3,$p' | head -20
		echo "  if this is intended, run: make record"
		exit 1
	fi
	;;
which)
	shift
	[ $# -gt 0 ] || { echo "usage: $0 which FILE..." >&2; exit 2; }
	[ -f "$LEDGER" ] || { echo "provenance: $LEDGER missing" >&2; exit 1; }
	rc=0
	for f in "$@"; do
		[ -f "$f" ] || { echo "provenance: no such file: $f" >&2; rc=1; continue; }
		want=$(sha "$f")
		hits=$(awk -F'\t' -v s="$want" '$2 == s { printf "    built by %s (sha256 %s) as %s\n", $3, substr($4,1,16), $1 }' "$LEDGER")
		if [ -n "$hits" ]; then
			echo "  $f  sha256 ${want%"${want#????????????????}"}..."
			echo "$hits"
		else
			echo "  $f  sha256 ${want%"${want#????????????????}"}..."
			echo "    no assembler in $LEDGER produced this content"
			rc=1
		fi
	done
	exit $rc
	;;
*)
	echo "usage: $0 record|verify|which FILE..." >&2
	exit 2
	;;
esac
