# shape.awk -- normalise assembly source lines to "<mnemonic> <operand-class>...".
#
# This is how coverage is measured: two lines have the same shape when they reach
# the same encoder path, so registers of a class are interchangeable, and a
# memory operand is classified by what the encoder actually branches on -- its
# base (rbp and rsp encode differently from everything else), whether a SIB is
# present, and whether a displacement is present, negative, or absent.
#
#   mov eax, [rbp]        -> mov r32 mem:rbp:noindex:disp0
#   mov eax, [rbx+8]      -> mov r32 mem:other:noindex:disp
#   mov eax, [rbx+rcx]    -> mov r32 mem:other:index:nodisp
#   mov byte [rbx], 1     -> mov byte mem:other:noindex:nodisp imm
#   and eax, ecx          -> and r32 r32
#
# `disp0` with an rbp base is the case that encodes as mod 01 with a zero byte,
# which is why it is a class of its own (see docs/encodings.md).

function regclass(t) {
	if (t ~ /^(rax|rbx|rcx|rdx|rsi|rdi|rbp|rsp)$/) return "r64"
	if (t ~ /^(eax|ebx|ecx|edx|esi|edi|ebp|esp)$/) return "r32"
	if (t ~ /^(al|bl|cl|dl|ah|bh|ch|dh|sil|dil|bpl|spl)$/) return "r8"
	if (t ~ /^r(8|9|1[0-5])d$/) return "r32"
	if (t ~ /^r(8|9|1[0-5])$/) return "r64"
	return ""
}

function baseclass(b) {
	if (b == "rbp" || b == "ebp") return "rbp"
	if (b == "rsp" || b == "esp") return "rsp"
	return "other"
}

function memclass(m,   base, rest, sign, tok, idx, disp) {
	base = m
	sub(/[+-].*/, "", base)
	rest = substr(m, length(base) + 1)
	idx = "noindex"
	disp = "nodisp"
	while (rest != "") {
		sign = substr(rest, 1, 1)
		rest = substr(rest, 2)
		tok = rest
		sub(/[+-].*/, "", tok)
		rest = substr(rest, length(tok) + 1)
		if (regclass(tok) != "") idx = "index"
		else if (sign == "-") disp = "negdisp"
		else disp = "disp"
	}
	if (baseclass(base) == "rbp" && disp == "nodisp") disp = "disp0"
	return "mem:" baseclass(base) ":" idx ":" disp
}

function operand(t) {
	if (t ~ /^\[/) { t = substr(t, 2); sub(/\]$/, "", t); return memclass(t) }
	if (regclass(t) != "") return regclass(t)
	if (t ~ /^[-0-9]/) return "imm"
	if (t ~ /^'.'$/) return "imm"
	if (t ~ /^"/) return "str"
	if (t ~ /^[a-z_0-9]+$/) return "sym"
	return t
}

{
	line = $0
	sub(/;.*/, "", line)
	gsub(/^[ \t]+|[ \t]+$/, "", line)
	while (line ~ /^[a-z_0-9]+:[ \t]*/) sub(/^[a-z_0-9]+:[ \t]*/, "", line)
	if (line == "") next
	if (line ~ /^db[ \t]+"/) { print "db str"; next }
	n = split(line, a, /[ \t,]+/)
	if (n == 0) next
	out = a[1]
	for (i = 2; i <= n; i++) {
		if (a[i] == "") continue
		out = out " " operand(a[i])
	}
	print out
}
