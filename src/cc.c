/* src/cc.c -- the compiler, written in the subset it compiles.
 *
 * Slice 1: emitstr, emitc, putn, line, and one program emitted line by line.
 * Slice 2: the same output, emitted from *tables* rather than by hand -- two
 *          arrays of literal addresses walked by loops, which is the shape the
 *          real prologue and epilogue emitters take.
 *
 * The pipeline that judges it:
 *
 *     cc < src/cc.c > .work/cc1.s ; asm1 < .work/cc1.s > .work/cc1
 *     ./.work/cc1 | cmp - tests/selfhost/slice1.expected
 *
 * The expected bytes were written before this file and have not changed: slice 2
 * must produce exactly what slice 1 did.  Not here yet: the literal section, the
 * symbol table, statements, expressions.
 *
 * Two things this file has to work around, both recorded in docs/cc.md:
 *   - **the loop must be in the caller.** A pointer subscript is char-indexed by
 *     design, so a function cannot index an `int` array that is passed to it;
 *     the tables stay in main and only their elements cross the call.
 *   - no globals: the buffer and its length are locals of main, passed as
 *     pointers, and a function returns the length it reached.
 *   - `\n` is not expressible in a character literal, so 10 is written out.
 */

/* the characters of s, at position len; return the new length */
int emitstr(int p, int len, int s)
{
	int i = 0;
	while (s[i] != 0) {
		p[len] = s[i];
		len = len + 1;
		i = i + 1;
	}
	return len;
}

/* one character */
int emitc(int p, int len, int c)
{
	p[len] = c;
	return len + 1;
}

/* a decimal number 0..65535, no leading zeros; return the new length */
int putn(int p, int len, int n)
{
	int place = 10000;
	int started = 0;
	int d = 0;
	while (place > 0) {
		d = (n / place) - ((n / place) / 10) * 10;
		if (d > 0) { started = 1; }
		if (started == 1) {
			p[len] = '0' + d;
			len = len + 1;
		}
		place = place / 10;
	}
	if (started == 0) { p[len] = '0'; len = len + 1; }
	return len;
}

/* one line of text, then a newline */
int line(int p, int len, int s)
{
	len = emitstr(p, len, s);
	len = emitc(p, len, 10);
	return len;
}

int main(void)
{
	char obuf[8000];
	int pro[5];
	int epi[4];
	int p = &obuf;
	int len = 0;
	pro[0] = "main:";
	pro[1] = "push rbp";
	pro[2] = "mov rbp, rsp";
	pro[3] = "mov rcx, 16500";
	pro[4] = "sub rsp, rcx";
	epi[0] = "mov rsp, rbp";
	epi[1] = "pop rbp";
	epi[2] = "ret";
	epi[3] = "entry main";
	int i = 0;
	while (i < 5) {
		len = line(p, len, pro[i]);
		i = i + 1;
	}
	len = emitstr(p, len, "mov rax, ");
	len = putn(p, len, 42);
	len = emitc(p, len, 10);
	i = 0;
	while (i < 4) {
		len = line(p, len, epi[i]);
		i = i + 1;
	}
	int k = write(obuf, len);
	return 0;
}
