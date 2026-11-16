/* src/cc.c -- the compiler, written in the subset it compiles.
 *
 * Slice 1: the output side.  Not a compiler yet: this emits the dialect text
 * for one fixed program (`int main(void) { return 42; }`) into a buffer and
 * writes the buffer out, so that the machinery every later slice needs -- a byte
 * buffer, a length in a local, one function per emission step -- is exercised
 * end to end by the real pipeline:
 *
 *     cc < src/cc.c > cc1.s ; asm1 < cc1.s > cc1 ; ./cc1 | cmp - expected
 *
 * The expected bytes are in tests/selfhost/slice1.expected and were written
 * before this file.  What is not here yet: the front end, the symbol table, the
 * literal section.  What is here: emitc, emitstr and putn -- putn being the
 * character-by-character equivalent of the assembler's emitnum.
 *
 * Conventions of the subset this is written in (docs/cc.md):
 *   - no globals: the buffer and its length are locals of main, passed as
 *     pointers, and a function returns the length it reached.
 *   - declarations may appear anywhere in a block, but a name may not be reused
 *     in another block.
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
	int p = &obuf;
	int len = 0;
	len = line(p, len, "main:");
	len = line(p, len, "push rbp");
	len = line(p, len, "mov rbp, rsp");
	len = line(p, len, "mov rcx, 16500");
	len = line(p, len, "sub rsp, rcx");
	len = emitstr(p, len, "mov rax, ");
	len = putn(p, len, 42);
	len = emitc(p, len, 10);
	len = line(p, len, "mov rsp, rbp");
	len = line(p, len, "pop rbp");
	len = line(p, len, "ret");
	len = line(p, len, "entry main");
	int k = write(obuf, len);
	return 0;
}
