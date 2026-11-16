#!/bin/sh
# wc-check.sh <cc> <asm> <work> -- build tests/programs/wc.c with the given
# compiler and assembler, then count four fixed inputs. No golden text: the
# point is that the pair really produces a working program.

cc=$1
as=$2
w=$3
mkdir -p "$w"

"$cc" < tests/programs/wc.c > "$w/wc.s" || { echo '  wc: compiler refused wc.c'; exit 1; }
"$as" < "$w/wc.s" > "$w/wc" || { echo '  wc: assembler refused wc.s'; exit 1; }
chmod +x "$w/wc"
fail=0

printf 'hello world\nsecond line\n' > "$w/wc.in1"
printf '2 4 24\n' > "$w/wc.want1"
printf '' > "$w/wc.in2"
printf '0 0 0\n' > "$w/wc.want2"
printf 'a b c' > "$w/wc.in3"
printf '0 3 5\n' > "$w/wc.want3"
head -c 300 /dev/zero | tr '\0' 'a' > "$w/wc.in4"
printf '0 1 300\n' > "$w/wc.want4"

i=1
while [ $i -le 4 ]; do
	"$w/wc" < "$w/wc.in$i" > "$w/wc.got$i"
	if ! cmp -s "$w/wc.got$i" "$w/wc.want$i"; then
		echo "  wc: input $i wrote [$(cat "$w/wc.got$i")]"
		fail=1
	fi
	i=$((i + 1))
done
[ $fail -eq 0 ] && printf '  wc: 4/4 inputs counted correctly -- lines, words, characters\n'
exit $fail
