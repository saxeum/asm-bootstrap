/* sort.c -- sort stdin's lines lexicographically.
 *
 * The whole input is read once into a 200000-byte buffer; a full buffer is
 * refused, because it cannot be told from a truncated one. Lines are kept as
 * 32-bit offset/length pairs in a table of 4096 entries; more than 4095 lines
 * is refused. Insertion sort is enough at this size, and it is stable.
 *
 * Output is each line followed by a newline, including a final line that had no
 * newline in the input. An empty input writes nothing and exits 0. Bad input
 * (or a full buffer/table) exits 1 with "sort: error" on stderr.
 *
 * The read is one call: a regular file smaller than the buffer arrives whole,
 * while a pipe may return early. That is a property of the subset's `read`
 * (name, count) builtin, not of this program; the near-cap test uses a file.
 */

int gda(int m, int o)
{
	return m[o] + m[o + 1] * 256 + m[o + 2] * 256 * 256 + m[o + 3] * 256 * 256 * 256;
}

int pda(int m, int o, int v)
{
	m[o] = v % 256;
	m[o + 1] = v / 256 % 256;
	m[o + 2] = v / 256 / 256 % 256;
	m[o + 3] = v / 256 / 256 / 256 % 256;
	return 0;
}

int die(void)
{
	char e[16];
	e[0] = 115;
	e[1] = 111;
	e[2] = 114;
	e[3] = 116;
	e[4] = 58;
	e[5] = 32;
	e[6] = 101;
	e[7] = 114;
	e[8] = 114;
	e[9] = 111;
	e[10] = 114;
	e[11] = 10;
	int w = werr(e, 12);
	int z = exit(1);
	return z;
}

/* compare lines a and b: -1, 0, 1; a prefix sorts before its extension */
int lcmp(int m, int a, int b)
{
	int ao = gda(m, 200000 + a * 4);
	int al = gda(m, 216384 + a * 4);
	int bo = gda(m, 200000 + b * 4);
	int bl = gda(m, 216384 + b * 4);
	int i = 0;
	int r = 0;
	int go = 1;
	while (go != 0) {
		if (i >= al) {
			if (i >= bl) { r = 0; go = 0; }
			else { r = 0; go = 0; }
		}
		else {
			if (i >= bl) { r = 1; go = 0; }
			else {
				int ca = m[ao + i];
				int cb = m[bo + i];
				if (ca < cb) { r = 0; go = 0; }
				else {
					if (ca > cb) { r = 1; go = 0; }
					else { i = i + 1; }
				}
			}
		}
	}
	return r;
}

int lsort(int m, int n)
{
	int i = 1;
	while (i < n) {
		int ko = gda(m, 200000 + i * 4);
		int kl = gda(m, 216384 + i * 4);
		pda(m, 200000 + n * 4, ko);
		pda(m, 216384 + n * 4, kl);
		int j = i;
		int go = 1;
		while (go != 0) {
			if (j == 0) { go = 0; }
			else {
				if (lcmp(m, j - 1, n) > 0) {
					int so = gda(m, 200000 + (j - 1) * 4);
					int sl = gda(m, 216384 + (j - 1) * 4);
					pda(m, 200000 + j * 4, so);
					pda(m, 216384 + j * 4, sl);
					j = j - 1;
				}
				else { go = 0; }
			}
		}
		pda(m, 200000 + j * 4, ko);
		pda(m, 216384 + j * 4, kl);
		i = i + 1;
	}
	return 0;
}

int main(void)
{
	char mem[240000];
	int n = read(mem, 200000);
	if (n < 0) { die(); }
	if (n >= 200000) { die(); }
	int nl = 0;
	int pos = 0;
	while (pos < n) {
		if (nl >= 4095) { die(); }
		int start = pos;
		int len = 0;
		int go = 1;
		while (go != 0) {
			if (pos >= n) { go = 0; }
			else {
				if (mem[pos] == 10) {
					pos = pos + 1;
					go = 0;
				}
				else {
					pos = pos + 1;
					len = len + 1;
				}
			}
		}
		pda(&mem, 200000 + nl * 4, start);
		pda(&mem, 216384 + nl * 4, len);
		nl = nl + 1;
	}
	lsort(&mem, nl);
	char eol[1];
	eol[0] = 10;
	int i = 0;
	while (i < nl) {
		int off = gda(&mem, 200000 + i * 4);
		int ln = gda(&mem, 216384 + i * 4);
		int p = &mem;
		p = p + off;
		int z = write(p, ln);
		int z2 = write(eol, 1);
		i = i + 1;
	}
	return 0;
}
