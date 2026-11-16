#!/bin/sh
# Which one is broken: the source you just edited, or the assembler that builds it?
#
# A bootstrap has an inherent ambiguity. When `make` fails, either
#   - the current src/asm1.s is wrong, or
#   - seed/asm1 (the previous generation) is wrong
# and a self-hosting build cannot tell you which, because the same binary is both
# the tool and the subject.
#
# Two facts settle it, and both come from the last commit, which is by definition
# a state that passed every gate at the time it was made:
#
#   1. can the COMMITTED seed build the COMMITTED source?
#         no  -> the seed is at fault; the last promote was bad
#         yes -> the seed is sound, so the difference is in what you changed
#   2. can asm0a -- frozen, hand-written, an independent implementation -- build
#      the current source, and does it agree with the seed?
#         this is the only check that is not self-referential. It is available
#         only while src/asm1.s stays inside asm0a's dialect.
#
# Usage: tools/triage.sh [source]        default: src/asm1.s

cd "$(dirname "$0")/.." || exit 1
src=${1:-src/asm1.s}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

[ -f "$src" ] || { echo "triage: no such source: $src" >&2; exit 2; }

git show HEAD:src/asm1.s > "$TMP/head.s" 2>/dev/null || {
	echo "triage: cannot read src/asm1.s from HEAD" >&2; exit 2; }
git show HEAD:seed/asm1 > "$TMP/seed" 2>/dev/null || {
	echo "triage: cannot read seed/asm1 from HEAD" >&2; exit 2; }
chmod +x "$TMP/seed"

rev=$(git rev-parse --short HEAD)
echo "triage: HEAD = $rev"

# 1. the committed seed against the committed source
if "$TMP/seed" < "$TMP/head.s" > "$TMP/o1" 2>/dev/null; then
	seed_ok=yes
else
	seed_ok=no
fi
printf '  1. committed seed builds committed source   : %s' "$seed_ok"
if [ "$seed_ok" = yes ]; then
	printf '  (%s bytes)\n' "$(wc -c < "$TMP/o1")"
	# does it reproduce the recorded sha?
	if [ -f docs/asm1.sha ]; then
		want=$(cut -d' ' -f1 docs/asm1.sha)
		got=$(sha256sum "$TMP/o1" | cut -d' ' -f1)
		if [ "$want" = "$got" ]; then
			echo "     and reproduces docs/asm1.sha exactly"
		else
			echo "     BUT does not reproduce docs/asm1.sha -- the recorded sha is stale"
		fi
	fi
else
	echo
fi

# 2. the working seed against the current source
if ./seed/asm1 < "$src" > "$TMP/o2" 2>/dev/null; then
	now_ok=yes
else
	now_ok=no
fi
printf '  2. working seed builds the current source   : %s\n' "$now_ok"

# 3. asm0a: independent implementation, if the dialect is still within its reach
if ./asm0a < "$src" > "$TMP/o3" 2>/dev/null; then
	printf '  3. asm0a builds the current source          : yes'
	if [ "$now_ok" = yes ]; then
		if cmp -s "$TMP/o2" "$TMP/o3"; then
			echo "  and agrees with the seed byte for byte"
		else
			echo "  BUT DISAGREES with the seed: one of the two is wrong"
		fi
	else
		echo "  (the seed cannot, so the seed is the suspect)"
	fi
else
	printf '  3. asm0a builds the current source          : no'
	if [ "$now_ok" = yes ]; then
		echo "  -- asm0a has been outgrown; only the seed speaks for it"
	else
		echo "  -- asm0a cannot build it either"
	fi
fi

echo
if [ "$seed_ok" = no ]; then
	echo "  VERDICT: the SEED is at fault, not your edit. The committed seed cannot"
	echo "           build the committed source, so the last promote was bad."
	echo "           Recover an earlier generation from history, e.g."
	echo "             git log --oneline -- seed/asm1"
	echo "             git show <rev>:seed/asm1 > seed/asm1 && chmod +x seed/asm1"
	exit 1
fi
if [ "$now_ok" = no ]; then
	echo "  VERDICT: the SEED is sound and your SOURCE is at fault. The committed"
	echo "           seed builds the committed source; it cannot build what you have"
	echo "           now. The difference is yours."
	exit 1
fi
echo "  VERDICT: nothing is broken. The seed builds the current source."
exit 0
