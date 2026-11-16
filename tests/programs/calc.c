/* calc.c -- a recursive-descent integer calculator.
 *
 * One expression per line:
 *
 *     expr  := term (('+'|'-') term)*
 *     term  := factor (('*'|'/'|'%') factor)*
 *     factor:= number | '-' factor | '(' expr ')'
 *
 * Values are signed, but the subset's comparisons are unsigned, so the sign is
 * carried by magnitude: every value is kept in -1000000..1000000, and a negative
 * value is the 64-bit two's complement of its magnitude. `v > 1000000` therefore
 * means "negative". Division and remainder are done on magnitudes and the sign is
 * applied after; no signed comparison is needed anywhere.
 *
 *     1+2*3        -> 7
 *     (1+2)*3      -> 9
 *     -5+2         -> -3
 *     3-10         -> -7
 *     -3*-4        -> 12
 *
 * Bad syntax, division by zero, and a magnitude above 1000000 exit 1 with
 * "calc: error" on stderr. Input is read once, 4096 bytes; a full buffer is
 * refused rather than truncated.
 */

int gwa(int m, int o)
{
	return m[o] + m[o + 1] * 256;
}

int pwa(int m, int o, int v)
{
	m[o] = v % 256;
	m[o + 1] = v / 256 % 256;
	return 0;
}

int die(void)
{
	char e[16];
	e[0] = 99;
	e[1] = 97;
	e[2] = 108;
	e[3] = 99;
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

int isneg(int v)
{
	if (v > 1000000) { return 1; }
	return 0;
}

int absv(int v)
{
	if (isneg(v) != 0) { return 0 - v; }
	return v;
}

int addv(int a, int b)
{
	int sa = isneg(a);
	int sb = isneg(b);
	if (sa == sb) {
		int z = absv(a) + absv(b);
		if (z > 1000000) { die(); }
		if (sa != 0) { return 0 - z; }
		return z;
	}
	if (sa != 0) {
		int ma = absv(a);
		if (ma > b) { return 0 - (ma - b); }
		return b - ma;
	}
	int mb = absv(b);
	if (a > mb) { return a - mb; }
	return 0 - (mb - a);
}

int subv(int a, int b)
{
	return addv(a, 0 - b);
}

int mulv(int a, int b)
{
	int sa = isneg(a);
	int sb = isneg(b);
	int z = absv(a) * absv(b);
	if (z > 1000000) { die(); }
	if (sa != sb) { return 0 - z; }
	return z;
}

int divv(int a, int b)
{
	if (b == 0) { die(); }
	int sa = isneg(a);
	int sb = isneg(b);
	int z = absv(a) / absv(b);
	if (sa != sb) { return 0 - z; }
	return z;
}

int modv(int a, int b)
{
	if (b == 0) { die(); }
	int sa = isneg(a);
	int z = absv(a) % absv(b);
	if (sa != 0) { return 0 - z; }
	return z;
}

int getc1(int m)
{
	int p = gwa(m, 4096);
	int e = gwa(m, 4098);
	if (p < e) { return m[p]; }
	return 0;
}

int bump(int m)
{
	int p = gwa(m, 4096) + 1;
	pwa(m, 4096, p);
	return 0;
}

int skipws(int m)
{
	int go = 1;
	while (go != 0) {
		int c = getc1(m);
		if (c == 32) { bump(m); }
		else {
			if (c == 9) { bump(m); }
			else {
				if (c == 13) { bump(m); }
				else { go = 0; }
			}
		}
	}
	return 0;
}


int factor(int m)
{
	skipws(m);
	int c = getc1(m);
	int v = 0;
	if (c == 40) {
		bump(m);
		v = expr(m);
		skipws(m);
		if (getc1(m) != 41) { die(); }
		bump(m);
		return v;
	}
	if (c == 45) {
		bump(m);
		v = factor(m);
		return 0 - v;
	}
	if (c >= 48) {
		if (c < 58) {
			v = 0;
			int go = 1;
			while (go != 0) {
				c = getc1(m);
				if (c >= 48) {
					if (c < 58) {
						v = v * 10 + (c - 48);
						if (v > 1000000) { die(); }
						bump(m);
					}
					else { go = 0; }
				}
				else { go = 0; }
			}
			return v;
		}
	}
	die();
	return 0;
}

int term(int m)
{
	int v = factor(m);
	int go = 1;
	while (go != 0) {
		skipws(m);
		int c = getc1(m);
		int op = 0;
		if (c == 42) { op = 1; }
		if (c == 47) { op = 2; }
		if (c == 37) { op = 3; }
		if (op == 0) { go = 0; }
		else {
			bump(m);
			int r = factor(m);
			if (op == 1) { v = mulv(v, r); }
			if (op == 2) { v = divv(v, r); }
			if (op == 3) { v = modv(v, r); }
		}
	}
	return v;
}

int expr(int m)
{
	int v = term(m);
	int go = 1;
	while (go != 0) {
		skipws(m);
		int c = getc1(m);
		int op = 0;
		if (c == 43) { op = 1; }
		if (c == 45) { op = 2; }
		if (op == 0) { go = 0; }
		else {
			bump(m);
			int r = term(m);
			if (op == 1) { v = addv(v, r); }
			if (op == 2) { v = subv(v, r); }
		}
	}
	return v;
}

int putn(int p, int len, int n)
{
	int place = 1000000;
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

int emit(int v)
{
	char out[32];
	int p = &out;
	int len = 0;
	if (isneg(v) != 0) {
		out[0] = 45;
		len = 1;
		v = 0 - v;
	}
	len = putn(p, len, v);
	out[len] = 10;
	len = len + 1;
	int z = write(out, len);
	return 0;
}

int main(void)
{
	char mem[4200];
	int n = read(mem, 4096);
	if (n < 0) { die(); }
	if (n >= 4096) { die(); }
	pwa(&mem, 4096, 0);
	pwa(&mem, 4098, n);
	int go = 1;
	while (go != 0) {
		skipws(&mem);
		int c = getc1(&mem);
		if (c == 0) { go = 0; }
		else {
			if (c == 10) {
				bump(&mem);
			}
			else {
				int v = expr(&mem);
				skipws(&mem);
				c = getc1(&mem);
				if (c != 0) {
					if (c != 10) { die(); }
				}
				if (c == 10) {
					bump(&mem);
				}
				emit(v);
			}
		}
	}
	return 0;
}
