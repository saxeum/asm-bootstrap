/* wc.c -- lines, words and characters from stdin.
 *
 * A real filter, not a fixture: it reads in 128-byte chunks, runs a word
 * state machine, formats three decimal numbers into a small output buffer and
 * writes them. It is the program the C-only build chain has to produce and
 * run, and it is compiled by both cc and the C-built cc1.
 *
 * Output is "<lines> <words> <chars>\n".
 */

int putc1(int p, int len, int c)
{
	p[len] = c;
	return len + 1;
}

int putn(int p, int len, int n)
{
	int place = 10000;
	int started = 0;
	while (place > 0) {
		int d = n / place;
		d = d - (d / 10) * 10;
		if (d > 0) { started = 1; }
		if (started != 0) {
			p[len] = 48 + d;
			len = len + 1;
		}
		place = place / 10;
	}
	if (started == 0) {
		p[len] = 48;
		len = len + 1;
	}
	return len;
}

int main(void)
{
	char b[128];
	int lines = 0;
	int words = 0;
	int chars = 0;
	int inw = 0;
	int n = read(b, 128);
	while (n > 0) {
		int i = 0;
		while (i < n) {
			int c = b[i];
			chars = chars + 1;
			if (c == 10) { lines = lines + 1; }
			int sp = 0;
			if (c == 32) { sp = 1; }
			if (c == 9) { sp = 1; }
			if (c == 10) { sp = 1; }
			if (sp != 0) {
				inw = 0;
			}
			else {
				if (inw == 0) {
					words = words + 1;
					inw = 1;
				}
			}
			i = i + 1;
		}
		n = read(b, 128);
	}
	char out[64];
	int p = &out;
	int len = 0;
	len = putn(p, len, lines);
	len = putc1(p, len, 32);
	len = putn(p, len, words);
	len = putc1(p, len, 32);
	len = putn(p, len, chars);
	len = putc1(p, len, 10);
	int k = write(out, len);
	return 0;
}
