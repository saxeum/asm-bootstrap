#!/bin/sh
# asm2-check.sh -- the D3 gate: asm2 must reproduce asm1 on the whole corpus.
#
# usage: tools/asm2-check.sh <asm1> <asm2> <asm1.c.s>
#
# The last argument is the dialect text cc made from src/asm1.c; asm2 must
# assemble it to itself. Everything is compared with cmp, never an exit status.

a1=$1
a2=$2
self=$3
d=.work/asm2-check.$$
mkdir -p "$d"
trap 'rm -rf "$d"' EXIT
ok=0
bad=0

ck()
{
	if cmp -s "$1" "$2"; then
		ok=$((ok + 1))
	else
		echo "  asm2: $3 differs"
		bad=$((bad + 1))
	fi
}

# 17 hand-emitted references
for f in addr32 callret cmp32 cmp8 count10 dbnum inc8 jmp jz load loop movrr r8 rel32 stack store; do
	"$a2" < "src/$f.s" > "$d/a" 2>/dev/null
	ck "$d/a" "ref/$f" "ref/$f"
done
"$a2" < src/hello_num.s > "$d/a" 2>/dev/null
ck "$d/a" ref/hello "ref/hello"

# capability pairs and superiority cases: byte-identical to asm1
for f in $(find tests/capability tests/superior -name '*.s'); do
	"$a1" < "$f" > "$d/a" 2>/dev/null
	"$a2" < "$f" > "$d/b" 2>/dev/null
	ck "$d/b" "$d/a" "$f"
done

# every coverage form
grep -v '^#' tests/coverage/forms.tsv | grep -v '^$' > "$d/forms"
while IFS= read -r line; do
	printf '%s\n' "$line" > "$d/f.s"
	"$a1" < "$d/f.s" > "$d/a" 2>/dev/null
	"$a2" < "$d/f.s" > "$d/b" 2>/dev/null
	ck "$d/b" "$d/a" "coverage [$line]"
done < "$d/forms"

# refusals: nonzero, nothing on stdout
for f in tests/reject/*.s; do
	"$a2" < "$f" > "$d/o" 2>/dev/null
	rc=$?
	if [ $rc -ne 0 ] && [ ! -s "$d/o" ]; then
		ok=$((ok + 1))
	else
		echo "  asm2: $f was not refused"
		bad=$((bad + 1))
	fi
done

# the exact messages
cm()
{
	printf '%b\n' "$2" > "$d/m.s"
	got=$("$a2" < "$d/m.s" 2>&1 >/dev/null)
	if [ "$got" = "$1" ]; then
		ok=$((ok + 1))
	else
		echo "  asm2: message for [$2] is '$got', wanted '$1'"
		bad=$((bad + 1))
	fi
}
cm "line 1: range" "mov bl, 300"
cm "line 1: range" "cmp bl, 200"
cm "line 1: label" "db nosuch"
cm "line 1: label" "jmp nosuch"
cm "line 2: rejected" "mov eax, 1\nfrobnicate 1"
cm "line 1: rejected" "jbe x"
cm "line 1: rejected" "jnb x"
cm "line 3: duplicate" "x:\nret\nx:"

# the sources that live in the tree
for f in src/dis.s src/cc.s src/asm1.s; do
	"$a1" < "$f" > "$d/a" 2>/dev/null
	"$a2" < "$f" > "$d/b" 2>/dev/null
	ck "$d/b" "$d/a" "$f"
done

# the 99 KB source, and it must still run
{ seq 1 9000 | sed 's/.*/mov eax, 1/'; printf 'mov eax, 60\nmov edi, 42\nsyscall\n'; } > "$d/big.s"
"$a1" < "$d/big.s" > "$d/a" 2>/dev/null
"$a2" < "$d/big.s" > "$d/b" 2>/dev/null
ck "$d/b" "$d/a" "the 99032-byte source"
chmod +x "$d/b"
"$d/b"
rc=$?
if [ $rc -eq 42 ]; then ok=$((ok + 1)); else echo "  asm2: the big binary exited $rc, wanted 42"; bad=$((bad + 1)); fi

# asm2 assembling its own compiler text
"$a2" < "$self" > "$d/self" 2>/dev/null
ck "$d/self" "$a2" "asm2(asm1.c.s) == asm2"

printf '  asm2: %s checks, %s failures -- corpus and self-assembly\n' "$ok" "$bad"
[ $bad -eq 0 ]
