#!/bin/sh
# sort-check.sh <cc> <asm> <work> -- build tests/programs/sort.c and check
# ordering, duplicates, empty input, a missing final newline, the near-cap line,
# and the full-line-count and full-buffer refusals.

cc=$1
as=$2
w=$3
mkdir -p "$w"

"$cc" < tests/programs/sort.c > "$w/sort.s" || { echo '  sort: compiler refused sort.c'; exit 1; }
"$as" < "$w/sort.s" > "$w/sort" || { echo '  sort: assembler refused sort.s'; exit 1; }
chmod +x "$w/sort"
fail=0

case1()
{
	"$w/sort" < "$w/s.in" > "$w/s.got" 2> "$w/s.err"
	rc=$?
	if [ $rc -ne 0 ] || ! cmp -s "$w/s.got" "$w/s.want"; then
		echo "  sort: case $1 failed (rc=$rc)"
		fail=1
	fi
}

printf 'a\nb\nc\n' > "$w/s.in"
printf 'a\nb\nc\n' > "$w/s.want"
case1 sorted

printf 'd\nc\nb\na\n' > "$w/s.in"
printf 'a\nb\nc\nd\n' > "$w/s.want"
case1 reversed

printf 'b\na\nb\n' > "$w/s.in"
printf 'a\nb\nb\n' > "$w/s.want"
case1 duplicates

printf '' > "$w/s.in"
printf '' > "$w/s.want"
case1 empty

printf 'b\na' > "$w/s.in"
printf 'a\nb\n' > "$w/s.want"
case1 "no-final-newline"

head -c 150000 /dev/zero | tr '\0' 'a' > "$w/s.in"
printf '\n' >> "$w/s.in"
cp "$w/s.in" "$w/s.want"
case1 "near-cap-line"

seq 1 5000 > "$w/s.in"
"$w/sort" < "$w/s.in" > "$w/s.got" 2> "$w/s.err"
rc=$?
if [ $rc -eq 0 ] || [ -s "$w/s.got" ] || [ "$(cat "$w/s.err")" != "sort: error" ]; then
	echo "  sort: the 5000-line file was not refused"
	fail=1
fi

head -c 200000 /dev/zero | tr '\0' 'a' > "$w/s.in"
"$w/sort" < "$w/s.in" > "$w/s.got" 2> "$w/s.err"
rc=$?
if [ $rc -eq 0 ] || [ -s "$w/s.got" ] || [ "$(cat "$w/s.err")" != "sort: error" ]; then
	echo "  sort: a full buffer was not refused"
	fail=1
fi

[ $fail -eq 0 ] && printf '  sort: 6/6 inputs ordered and 2/2 refusals\n'
exit $fail
