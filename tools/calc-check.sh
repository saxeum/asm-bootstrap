#!/bin/sh
# calc-check.sh <cc> <asm> <work> -- build tests/programs/calc.c and check its
# arithmetic, signed results, and error paths.

cc=$1
as=$2
w=$3
mkdir -p "$w"

"$cc" < tests/programs/calc.c > "$w/calc.s" || { echo '  calc: compiler refused calc.c'; exit 1; }
"$as" < "$w/calc.s" > "$w/calc" || { echo '  calc: assembler refused calc.s'; exit 1; }
chmod +x "$w/calc"
fail=0

printf '1+2*3\n(1+2)*3\n-5+2\n3-10\n-3*-4\n100/7\n100%%7\n0-5\n(3-10)/2\n(3-10)%%3\n' > "$w/calc.in"
printf '7\n9\n-3\n-7\n12\n14\n2\n-5\n-3\n-1\n' > "$w/calc.want"
"$w/calc" < "$w/calc.in" > "$w/calc.got"
if ! cmp -s "$w/calc.got" "$w/calc.want"; then
	echo "  calc: arithmetic wrote [$(cat "$w/calc.got" | tr '\n' ' ')]"
	fail=1
fi

printf '1/0\n' > "$w/calc.bad1"
"$w/calc" < "$w/calc.bad1" > "$w/calc.bad1.out" 2> "$w/calc.bad1.err"
rc=$?
if [ $rc -eq 0 ] || [ -s "$w/calc.bad1.out" ] || [ "$(cat "$w/calc.bad1.err")" != "calc: error" ]; then
	echo "  calc: division by zero was not refused with the fixed message"
	fail=1
fi

printf '1+\n' > "$w/calc.bad2"
"$w/calc" < "$w/calc.bad2" > "$w/calc.bad2.out" 2> "$w/calc.bad2.err"
rc=$?
if [ $rc -eq 0 ] || [ -s "$w/calc.bad2.out" ] || [ "$(cat "$w/calc.bad2.err")" != "calc: error" ]; then
	echo "  calc: a syntax error was not refused with the fixed message"
	fail=1
fi

[ $fail -eq 0 ] && printf '  calc: 10/10 results and 2/2 refusals, signed values included\n'
exit $fail
