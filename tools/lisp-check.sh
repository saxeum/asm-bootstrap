#!/bin/sh
# lisp-check.sh <cc> <asm> <work> -- build tests/programs/lisp.c and run its
# reader/eval table, the refusal table, an arena-full input and a full buffer.

cc=$1
as=$2
w=$3
mkdir -p "$w"

"$cc" < tests/programs/lisp.c > "$w/lisp.s" || { echo '  lisp: compiler refused lisp.c'; exit 1; }
"$as" < "$w/lisp.s" > "$w/lisp" || { echo '  lisp: assembler refused lisp.s'; exit 1; }
chmod +x "$w/lisp"
fail=0
ok=0
n=0

run_case()
{
	n=$((n + 1))
	printf '%b' "$1" > "$w/l.in"
	printf '%b\n' "$2" > "$w/l.want"
	"$w/lisp" < "$w/l.in" > "$w/l.got" 2> "$w/l.err"
	rc=$?
	if [ $rc -ne 0 ] || ! cmp -s "$w/l.got" "$w/l.want"; then
		echo "  lisp: case $n failed (rc=$rc, input [$1])"
		fail=1
	else
		ok=$((ok + 1))
	fi
}

while IFS='|' read -r input expected; do
	case "$input" in
	''|'#'*) continue ;;
	esac
	run_case "$input" "$expected"
done < tests/programs/lisp.table

rn=0
rok=0
while IFS='|' read -r input reason; do
	case "$input" in
	''|'#'*) continue ;;
	esac
	rn=$((rn + 1))
	printf '%b' "$input" > "$w/l.in"
	"$w/lisp" < "$w/l.in" > "$w/l.got" 2> "$w/l.err"
	rc=$?
	if [ $rc -eq 0 ] || [ -s "$w/l.got" ] || [ "$(cat "$w/l.err")" != "lisp: error" ]; then
		echo "  lisp: refusal $rn ($reason) was not refused with the fixed message"
		fail=1
	else
		rok=$((rok + 1))
	fi
done < tests/programs/lisp-reject.table

# The arena is 4096 nodes. Each (define a 1) line allocates a symbol,
# a number and their cons cells; 1500 lines exceed the arena without deep
# recursion. Earlier complete lines have been printed, so only the failing
# expression must leave no partial value; the single-expression refusals above
# already check that stdout is empty.
i=0
: > "$w/l.arena"
while [ $i -lt 1500 ]; do
	printf '(define a 1)\n' >> "$w/l.arena"
	i=$((i + 1))
done
"$w/lisp" < "$w/l.arena" > "$w/l.got" 2> "$w/l.err"
rc=$?
if [ $rc -eq 0 ] || [ "$(cat "$w/l.err")" != "lisp: error" ]; then
	echo '  lisp: the arena-full input was not refused with the fixed message'
	fail=1
else
	rok=$((rok + 1))
	rn=$((rn + 1))
fi

# A full 60000-byte input is refused, not truncated.
head -c 60000 /dev/zero | tr '\0' ' ' > "$w/l.full"
"$w/lisp" < "$w/l.full" > "$w/l.got" 2> "$w/l.err"
rc=$?
if [ $rc -eq 0 ] || [ -s "$w/l.got" ] || [ "$(cat "$w/l.err")" != "lisp: error" ]; then
	echo '  lisp: a full input buffer was not refused'
	fail=1
else
	rok=$((rok + 1))
	rn=$((rn + 1))
fi

[ $fail -eq 0 ] && printf '  lisp: %s/%s values and %s/%s refusals, arena and buffer limits included\n' "$ok" "$n" "$rok" "$rn"
exit $fail
