#!/bin/sh
# Coverage: every form this assembler claims to support must be exercised by at
# least one test input.
#
# The claim is tests/coverage/forms.tsv -- one probe line per form. For each row:
#
#   1. asm1 must accept it, so the inventory cannot describe a form that was
#      removed or renamed without saying so;
#   2. its *shape* (tools/shape.awk) must appear in the census of every test
#      input, so a form nobody tests is a red gate rather than a paragraph in a
#      doc.
#
# And the other direction: every mnemonic the corpus uses must be in the
# inventory, so adding a case to a test cannot quietly widen what is supported
# without a claim being recorded.
#
# What this cannot do: prove the inventory complete. Shape is coarser than the
# encoder's branches in places (two disp values share one path) and finer in
# others. It is a lower bound on coverage and an upper bound on the claim, and
# both halves are stated rather than implied.

set -u
cd "$(dirname "$0")/.."

ASM1=./asm1
FORMS=tests/coverage/forms.tsv
CORPUS="src/*.s tests/capability/*.s tests/reject/*.s tests/superior/*.s"
# the sources of the corpus that are supposed to assemble: tests/reject exists to
# be refused, so a mnemonic appearing only there may be deliberately unknown
VALID="src/*.s tests/capability/*.s tests/superior/*.s"

[ -x "$ASM1" ] || { echo "  coverage: no ./asm1 -- run make"; exit 1; }
[ -f "$FORMS" ] || { echo "  coverage: no $FORMS"; exit 1; }
[ -f tools/shape.awk ] || { echo "  coverage: no tools/shape.awk"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# census of the corpus, and of a file of probes
census() { cat $1 | awk -f tools/shape.awk | sort -u; }

census "$CORPUS" > "$tmp/corpus"
[ -s "$tmp/corpus" ] || { echo "  coverage: the corpus produced no shapes"; exit 1; }

grep -v '^[[:space:]]*#' "$FORMS" | sed '/^[[:space:]]*$/d' > "$tmp/rows"
n=$(wc -l < "$tmp/rows" | tr -d ' ')
[ "$n" -ge 40 ] || { echo "  coverage: only $n forms in $FORMS -- the inventory has been emptied"; exit 1; }

# the inventory's own shapes, for the second direction
census "$tmp/rows" > "$tmp/forms"

fail=0
ok=0

# the coverage predicate, used by the loop and by the self-test below
covered() { awk -f tools/shape.awk < "$1" > "$tmp/sh"; grep -qxF "$(cat "$tmp/sh")" "$tmp/corpus"; }

while IFS= read -r probe; do
	printf '%s\n' "$probe" > "$tmp/one.s"
	if ! "$ASM1" < "$tmp/one.s" > /dev/null 2>&1; then
		echo "  INVENTORY: asm1 refuses '$probe' -- the claim is stale"
		fail=1
		continue
	fi
	if covered "$tmp/one.s"; then
		ok=$((ok + 1))
	else
		echo "  UNTESTED: '$probe'  ($(cat "$tmp/sh")) appears in no test input"
		fail=1
	fi
done < "$tmp/rows"

# every mnemonic the corpus uses must be claimed in the inventory. The reject
# suite is excluded here: `frobnicate` is a mnemonic a test uses in order to have
# it refused, and demanding a claim for it would be demanding a lie.
census "$VALID" > "$tmp/valid"
awk '{ print $1 }' "$tmp/valid" | sort -u > "$tmp/cm"
awk '{ print $1 }' "$tmp/forms" | sort -u > "$tmp/fm"
while IFS= read -r m; do
	if ! grep -qxF "$m" "$tmp/fm"; then
		echo "  UNCLAIMED: '$m' is used by a test but is not a row in $FORMS"
		fail=1
	fi
done < "$tmp/cm"

# The check must be able to fail: a probe whose shape is in no test input has to
# be reported as untested. Same predicate as the loop above, so a broken check
# fails here rather than passing quietly.
printf 'lea eax, [rcx+rdx]\n' > "$tmp/absent.s"
if covered "$tmp/absent.s"; then
	echo "  the coverage check cannot fail: it accepted a shape no test reaches"
	fail=1
fi

if [ "$fail" -ne 0 ]; then
	exit 1
fi
printf '  coverage %s/%s forms exercised by a test, every corpus mnemonic claimed\n' "$ok" "$n"
