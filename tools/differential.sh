#!/bin/sh
# differential.sh [cc] [asm] -- compare our compiled programs with gcc -O0.
#
# This is the fourth oracle rung: a second opinion from an implementation that
# did not grow up here. gcc is used ONLY to build the comparison binary; it
# never produces an artifact in the repository. That is why this one file is a
# named exemption in `make test-tools`, and why this script is run by hand, not
# from `make check`:
#
#     tools/differential.sh              # canonical cc + asm1
#     tools/differential.sh seed/cc ./asm1 # the pre-signed dialect compiler
#
# The prelude maps the subset's two-argument read/write builtins to POSIX
# read(0,...)/write(1,...); the programs themselves avoid pointer-typed ints, so
# they are valid C under gcc too. -funsigned-char matches this dialect's char.

set -u
cc=${1:-./cc}
asm=${2:-./asm1}
d=.work/differential.$$
mkdir -p "$d"
trap 'rm -rf "$d"' EXIT

cat > "$d/prelude.c" <<'EOF'
#include <unistd.h>
static int read2(void *b, int n) { return read(0, b, n); }
static int write2(void *b, int n) { return write(1, b, n); }
#define read(b, n) read2(b, n)
#define write(b, n) write2(b, n)
EOF

ok=0
bad=0
n=0
for src in tests/differential/*.c; do
	n=$((n + 1))
	if ! "$cc" < "$src" > "$d/p.s" 2> "$d/cc.err"; then
		echo "  differential: $cc refuses $src"
		bad=$((bad + 1))
		continue
	fi
	if ! "$asm" < "$d/p.s" > "$d/p" 2> "$d/asm.err"; then
		echo "  differential: $asm refuses the text for $src"
		bad=$((bad + 1))
		continue
	fi
	chmod +x "$d/p"
	{ cat "$d/prelude.c"; cat "$src"; } > "$d/p.gcc.c"
	if ! gcc -O0 -funsigned-char -o "$d/p.gcc" "$d/p.gcc.c" 2> "$d/gcc.err"; then
		echo "  differential: gcc refuses $src (prelude problem?)"
		head -3 "$d/gcc.err"
		bad=$((bad + 1))
		continue
	fi
	"$d/p" > "$d/out.ours" 2> /dev/null
	r1=$?
	"$d/p.gcc" > "$d/out.gcc" 2> /dev/null
	r2=$?
	if cmp -s "$d/out.ours" "$d/out.gcc" && [ "$r1" -eq "$r2" ]; then
		printf '  differential: %s AGREE (stdout bytes, exit %s)\n' "$src" "$r1"
		ok=$((ok + 1))
	else
		printf '  differential: %s DIFFERS (exit %s vs %s, stdout %s vs %s bytes)\n' \
			"$src" "$r1" "$r2" "$(wc -c < "$d/out.ours")" "$(wc -c < "$d/out.gcc")"
		bad=$((bad + 1))
	fi
done
printf '  differential: %s/%s programs agree with gcc -O0\n' "$ok" "$n"
[ "$bad" -eq 0 ]
