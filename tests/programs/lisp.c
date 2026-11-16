/* lisp.c -- a small Lisp interpreter: reader, fixed arena, eval.
 *
 * One expression per line; the value is printed on one line.  The reader
 * understands numbers, symbols, ( ... ), and quote ('x).  Eval understands
 * numbers, symbols, if, define, quote, + - * /, < > = <= >=, car, cdr and
 * cons.  There are no closures, no set!, no user functions and no GC; the
 * arena is 4096 nodes and its exhaustion is a refusal, not a wrapped index.
 *
 *     (+ 1 2)                  -> 3
 *     (if (< 1 2) 10 20)       -> 10
 *     (define x 41)            -> 41
 *     (+ x 1)                  -> 42
 *     (cons 1 (cons 2 ()))     -> (1 2)
 *     (car (quote (a b)))      -> a
 *
 * Errors -- unreadable input, an unbound symbol, wrong arity, division by
 * zero, arena full -- exit 1 with "lisp: error" on stderr.  A value is
 * assembled in an output buffer and written only after eval and printing
 * succeed, so a failing expression writes no partial value.
 *
 * Memory is one array passed as an int pointer:
 *     0 .. 59999       input
 *     65536 .. 131071  arena: node i at 65536 + i*16 (tag, a, b, c)
 *     131072 ..        parser/env/output state and the literal name table
 * Node 0 is nil.  Numbers are 64-bit, stored as two 32-bit words.
 */

/* 32-bit little-endian words; values here are never negative except through
 * pq(), which converts a signed number to an unsigned high word first. */
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

/* Read a sign-extended 64-bit number made of two words. */
int gq(int m, int o)
{
	int lo = gda(m, o);
	int hi = gda(m, o + 4);
	int top = 128 * 256 * 256 * 256 - 1;
	if (hi > top) {
		hi = hi - 256 * 256 * 256 * 256;
	}
	int b = 256 * 256 * 256 * 256;
	return lo + hi * b;
}
int pq(int m, int o, int v)
{
	int b = 256 * 256 * 256 * 256;
	int hi = v / b;
	int lo = v - hi * b;
	if (lo < 0) {
		lo = lo + b;
		hi = hi - 1;
	}
	if (hi < 0) {
		hi = hi + b;
	}
	pda(m, o, lo);
	pda(m, o + 4, hi);
	return 0;
}

int die(void)
{
	char e[16];
	e[0] = 108;
	e[1] = 105;
	e[2] = 115;
	e[3] = 112;
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

int getc1(int m)
{
	int p = gda(m, 131072);
	int e = gda(m, 131076);
	if (p < e) { return m[p]; }
	return 0;
}

int peek(int m, int k)
{
	int p = gda(m, 131072) + k;
	int e = gda(m, 131076);
	if (p < e) { return m[p]; }
	return 0;
}

int bump(int m)
{
	int p = gda(m, 131072) + 1;
	pda(m, 131072, p);
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
				else {
					if (c == 10) { bump(m); }
					else { go = 0; }
				}
			}
		}
	}
	return 0;
}

/* spaces at the end of an expression, but not a newline */
int skipsp(int m)
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

int tag(int m, int x)
{
	return gda(m, 65536 + x * 16);
}

int car(int m, int x)
{
	return gda(m, 65536 + x * 16 + 4);
}

int cdr(int m, int x)
{
	return gda(m, 65536 + x * 16 + 8);
}

int numv(int m, int x)
{
	return gq(m, 65536 + x * 16 + 4);
}

int symo(int m, int x)
{
	return gda(m, 65536 + x * 16 + 4);
}

int syml(int m, int x)
{
	return gda(m, 65536 + x * 16 + 8);
}

int new_node(int m, int t)
{
	int n = gda(m, 131080);
	if (n >= 4096) { die(); }
	pda(m, 131080, n + 1);
	int o = 65536 + n * 16;
	pda(m, o, t);
	pda(m, o + 4, 0);
	pda(m, o + 8, 0);
	pda(m, o + 12, 0);
	return n;
}

int new_num(int m, int v)
{
	int x = new_node(m, 1);
	int o = 65536 + x * 16;
	pq(m, o + 4, v);
	return x;
}

int new_sym(int m, int o, int l)
{
	int x = new_node(m, 2);
	int p = 65536 + x * 16;
	pda(m, p + 4, o);
	pda(m, p + 8, l);
	return x;
}

int cons(int m, int a, int b)
{
	int x = new_node(m, 3);
	int o = 65536 + x * 16;
	pda(m, o + 4, a);
	pda(m, o + 8, b);
	return x;
}

int slen(int m, int o)
{
	int i = 0;
	while (m[o + i] != 0) { i = i + 1; }
	return i;
}

int is_name(int m, int x, int no)
{
	if (tag(m, x) != 2) { return 0; }
	int so = symo(m, x);
	int sl = syml(m, x);
	int nl = slen(m, no);
	if (sl != nl) { return 0; }
	int i = 0;
	while (i < sl) {
		int a = m[so + i];
		int b = m[no + i];
		if (a != b) { return 0; }
		i = i + 1;
	}
	return 1;
}

int env_find(int m, int x)
{
	int n = gda(m, 131084);
	int i = n;
	int so = symo(m, x);
	int sl = syml(m, x);
	while (i > 0) {
		i = i - 1;
		int e = 132000 + i * 12;
		int o = gda(m, e);
		int l = gda(m, e + 4);
		if (l == sl) {
			int j = 0;
			int ok = 1;
			while (j < l) {
				int a = m[o + j];
				int b = m[so + j];
				if (a != b) { ok = 0; }
				j = j + 1;
			}
			if (ok != 0) { return i; }
		}
	}
	return 0 - 1;
}

int env_val(int m, int x)
{
	int i = env_find(m, x);
	if (i < 0) { die(); }
	return gda(m, 132000 + i * 12 + 8);
}

int env_set(int m, int x, int v)
{
	int i = env_find(m, x);
	if (i < 0) {
		int n = gda(m, 131084);
		if (n >= 64) { die(); }
		int e = 132000 + n * 12;
		int no = symo(m, x);
		int nl = syml(m, x);
		pda(m, e, no);
		pda(m, e + 4, nl);
		pda(m, e + 8, v);
		pda(m, 131084, n + 1);
		return v;
	}
	pda(m, 132000 + i * 12 + 8, v);
	return v;
}
int delimp(int c)
{
	if (c == 0) { return 1; }
	if (c == 32) { return 1; }
	if (c == 9) { return 1; }
	if (c == 10) { return 1; }
	if (c == 13) { return 1; }
	if (c == 40) { return 1; }
	if (c == 41) { return 1; }
	if (c == 39) { return 1; }
	return 0;
}

int read_num(int m)
{
	int neg = 0;
	int c = getc1(m);
	if (c == 45) {
		neg = 1;
		bump(m);
	}
	int v = 0;
	int go = 1;
	int cap = 900000 * 1000000 * 1000000;
	while (go != 0) {
		c = getc1(m);
		if (c >= 48) {
			if (c < 58) {
				if (v > cap) { die(); }
				v = v * 10 + (c - 48);
				bump(m);
			}
			else { go = 0; }
		}
		else { go = 0; }
	}
	if (neg != 0) { v = 0 - v; }
	return new_num(m, v);
}

int read_sym(int m)
{
	int o = gda(m, 131072);
	int l = 0;
	int go = 1;
	while (go != 0) {
		int c = getc1(m);
		if (delimp(c) != 0) { go = 0; }
		else {
			bump(m);
			l = l + 1;
		}
	}
	if (l == 0) { die(); }
	return new_sym(m, o, l);
}

int rdlist(int m)
{
	skipws(m);
	int c = getc1(m);
	if (c == 41) {
		bump(m);
		return 0;
	}
	if (c == 0) { die(); }
	int a = rd(m);
	int d = rdlist(m);
	return cons(m, a, d);
}

int rd(int m)
{
	skipws(m);
	int c = getc1(m);
	if (c == 0) { die(); }
	if (c == 41) { die(); }
	if (c == 40) {
		bump(m);
		return rdlist(m);
	}
	if (c == 39) {
		bump(m);
		int q = new_sym(m, 131112, 5);
		int x = rd(m);
		int dq = cons(m, x, 0);
		return cons(m, q, dq);
	}
	if (c >= 48) {
		if (c < 58) { return read_num(m); }
	}
	if (c == 45) {
		int d = peek(m, 1);
		if (d >= 48) {
			if (d < 58) { return read_num(m); }
		}
	}
	return read_sym(m);
}


int eval_if(int m, int x)
{
	int a = cdr(m, x);
	if (a == 0) { die(); }
	int ca = car(m, a);
	int c = eval(m, ca);
	int r = cdr(m, a);
	if (r == 0) { die(); }
	int t = car(m, r);
	int d = cdr(m, r);
	if (c != 0) { return eval(m, t); }
	if (d == 0) { return 0; }
	int e = car(m, d);
	if (cdr(m, d) != 0) { die(); }
	return eval(m, e);
}

int eval_define(int m, int x)
{
	int a = cdr(m, x);
	if (a == 0) { die(); }
	int nm = car(m, a);
	if (tag(m, nm) != 2) { die(); }
	int r = cdr(m, a);
	if (r == 0) { die(); }
	int ra = car(m, r);
	int v = eval(m, ra);
	if (cdr(m, r) != 0) { die(); }
	env_set(m, nm, v);
	return v;
}

int eval(int m, int x)
{
	int t = tag(m, x);
	if (t == 0) { return 0; }
	if (t == 1) { return x; }
	if (t == 2) {
		if (is_name(m, x, 131153) != 0) { return 0; }
		if (is_name(m, x, 131157) != 0) { return x; }
		return env_val(m, x);
	}
	if (t != 3) { die(); }
	int h = car(m, x);
	if (tag(m, h) == 2) {
		if (is_name(m, h, 131112) != 0) {
			int a = cdr(m, x);
			if (a == 0) { die(); }
			if (cdr(m, a) != 0) { die(); }
			return car(m, a);
		}
		if (is_name(m, h, 131100) != 0) { return eval_if(m, x); }
		if (is_name(m, h, 131104) != 0) { return eval_define(m, x); }
		int args = cdr(m, x);
		return apply(m, h, args);
	}
	die();
	return 0;
}

int apply(int m, int h, int args)
{
	int op = 0;
	if (is_name(m, h, 131140) != 0) { op = 1; }
	if (is_name(m, h, 131144) != 0) { op = 2; }
	if (op != 0) {
		if (args == 0) { die(); }
		int ca = car(m, args);
		int a = eval(m, ca);
		if (cdr(m, args) != 0) { die(); }
		if (tag(m, a) != 3) { die(); }
		if (op == 1) { return car(m, a); }
		return cdr(m, a);
	}
	if (is_name(m, h, 131148) != 0) {
		if (args == 0) { die(); }
		int ca2 = car(m, args);
		int a2 = eval(m, ca2);
		int r2 = cdr(m, args);
		if (r2 == 0) { die(); }
		int cb2 = car(m, r2);
		int b2 = eval(m, cb2);
		if (cdr(m, r2) != 0) { die(); }
		return cons(m, a2, b2);
	}
	if (args == 0) { die(); }
	int ca3 = car(m, args);
	int ea3 = eval(m, ca3);
	if (tag(m, ea3) != 1) { die(); }
	int a3 = numv(m, ea3);
	int r3 = cdr(m, args);
	if (r3 == 0) { die(); }
	int cb3 = car(m, r3);
	int eb3 = eval(m, cb3);
	if (tag(m, eb3) != 1) { die(); }
	int b3 = numv(m, eb3);
	if (cdr(m, r3) != 0) { die(); }
	if (is_name(m, h, 131120) != 0) { return new_num(m, a3 + b3); }
	if (is_name(m, h, 131122) != 0) { return new_num(m, a3 - b3); }
	if (is_name(m, h, 131124) != 0) { return new_num(m, a3 * b3); }
	if (is_name(m, h, 131126) != 0) {
		if (b3 == 0) { die(); }
		return new_num(m, a3 / b3);
	}
	if (is_name(m, h, 131128) != 0) {
		if (a3 < b3) { return new_num(m, 1); }
		return 0;
	}
	if (is_name(m, h, 131130) != 0) {
		if (a3 > b3) { return new_num(m, 1); }
		return 0;
	}
	if (is_name(m, h, 131132) != 0) {
		if (a3 == b3) { return new_num(m, 1); }
		return 0;
	}
	if (is_name(m, h, 131134) != 0) {
		if (a3 <= b3) { return new_num(m, 1); }
		return 0;
	}
	if (is_name(m, h, 131137) != 0) {
		if (a3 >= b3) { return new_num(m, 1); }
		return 0;
	}
	die();
	return 0;
}
int append(int m, int p, int len, int c)
{
	if (len >= 7000) { die(); }
	m[p + len] = c;
	return len + 1;
}

int print_num(int m, int p, int len, int v)
{
	if (v < 0) {
		len = append(m, p, len, 45);
		v = 0 - v;
	}
	char d[24];
	int k = 0;
	if (v == 0) {
		d[0] = 48;
		k = 1;
	}
	while (v > 0) {
		int q = v / 10;
		int r = v - q * 10;
		d[k] = 48 + r;
		k = k + 1;
		v = q;
	}
	while (k > 0) {
		k = k - 1;
		len = append(m, p, len, d[k]);
	}
	return len;
}

int print_node(int m, int p, int len, int x)
{
	int t = tag(m, x);
	if (t == 0) {
		len = append(m, p, len, 110);
		len = append(m, p, len, 105);
		len = append(m, p, len, 108);
		return len;
	}
	if (t == 1) {
		int v = numv(m, x);
		return print_num(m, p, len, v);
	}
	if (t == 2) {
		int o = symo(m, x);
		int l = syml(m, x);
		int i = 0;
		while (i < l) {
			len = append(m, p, len, m[o + i]);
			i = i + 1;
		}
		return len;
	}
	if (t == 3) {
		len = append(m, p, len, 40);
		int a = car(m, x);
		len = print_node(m, p, len, a);
		int r = cdr(m, x);
		while (r != 0) {
			if (tag(m, r) != 3) {
				len = append(m, p, len, 32);
				len = append(m, p, len, 46);
				len = append(m, p, len, 32);
				len = print_node(m, p, len, r);
				r = 0;
			}
			else {
				len = append(m, p, len, 32);
				int b = car(m, r);
				len = print_node(m, p, len, b);
				r = cdr(m, r);
			}
		}
		len = append(m, p, len, 41);
		return len;
	}
	die();
	return len;
}

int initnames(int m)
{
	m[131100] = 'i'; m[131101] = 'f'; m[131102] = 0;
	m[131104] = 'd'; m[131105] = 'e'; m[131106] = 'f';
	m[131107] = 'i'; m[131108] = 'n'; m[131109] = 'e'; m[131110] = 0;
	m[131112] = 'q'; m[131113] = 'u'; m[131114] = 'o';
	m[131115] = 't'; m[131116] = 'e'; m[131117] = 0;
	m[131120] = '+'; m[131121] = 0;
	m[131122] = '-'; m[131123] = 0;
	m[131124] = '*'; m[131125] = 0;
	m[131126] = '/'; m[131127] = 0;
	m[131128] = '<'; m[131129] = 0;
	m[131130] = '>'; m[131131] = 0;
	m[131132] = '='; m[131133] = 0;
	m[131134] = '<'; m[131135] = '='; m[131136] = 0;
	m[131137] = '>'; m[131138] = '='; m[131139] = 0;
	m[131140] = 'c'; m[131141] = 'a'; m[131142] = 'r'; m[131143] = 0;
	m[131144] = 'c'; m[131145] = 'd'; m[131146] = 'r'; m[131147] = 0;
	m[131148] = 'c'; m[131149] = 'o'; m[131150] = 'n'; m[131151] = 's'; m[131152] = 0;
	m[131153] = 'n'; m[131154] = 'i'; m[131155] = 'l'; m[131156] = 0;
	m[131157] = 't'; m[131158] = 0;
	return 0;
}

int init(int m, int n)
{
	pda(m, 131072, 0);
	pda(m, 131076, n);
	pda(m, 131080, 1);
	pda(m, 131084, 0);
	pda(m, 65536, 0);
	pda(m, 65540, 0);
	pda(m, 65544, 0);
	pda(m, 65548, 0);
	initnames(m);
	return 0;
}

int main(void)
{
	char mem[140000];
	int n = read(mem, 60000);
	if (n < 0) { die(); }
	if (n >= 60000) { die(); }
	init(&mem, n);
	int go = 1;
	while (go != 0) {
		skipws(&mem);
		int c = getc1(&mem);
		if (c == 0) { go = 0; }
		else {
			int x = rd(&mem);
			skipsp(&mem);
			c = getc1(&mem);
			if (c != 0) {
				if (c != 10) { die(); }
			}
			if (c == 10) { bump(&mem); }
			int v = eval(&mem, x);
			int len = print_node(&mem, 133000, 0, v);
			len = append(&mem, 133000, len, 10);
			int p = &mem;
			p = p + 133000;
			int z = write(p, len);
		}
	}
	return 0;
}
