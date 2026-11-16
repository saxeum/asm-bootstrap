/* src/cc.c -- the compiler, written in the subset it compiles.
 *
 * This is the port: a C program that compiles the same C subset the dialect
 * cc (src/cc.s) compiles, to the same dialect TEXT. It is compiled by cc and
 * asm1, and the binary it becomes must compile this file to identical text
 * (make test-d2). Every emitted byte comes from emc/ems/emn, so the two
 * implementations can be compared with cmp on every golden.
 *
 * One buffer holds everything:
 *
 *   SRC   0      200000   input bytes, read once
 *   SYM   200000  512     32 symbol names, 16 bytes each
 *   SOFF  200512  128     32 array offsets, 32 bits each
 *   SKND  200640  32      32 kinds: 0 scalar, 1 char array, 8 int array
 *   LIT   200676  4000    999 literals, offset16 + length16
 *   ST    204700  512     scalar state (see the state offsets below)
 *   NAME  205216  16      the name being scanned
 *
 * Everything is addressed through one int pointer, so a subscript is a byte
 * subscript in every routine. Values wider than a byte are stored as two
 * bytes, little endian, by gw/pw.
 *
 * Refusal is exit(1) with nothing on stdout. The subset has no other way out
 * of a program from inside a routine; exit is a builtin in cc.s for exactly
 * this reason, and this file implements the same builtin when it compiles.
 */

/* state offsets inside ST (base 204700):
 * CU 0, SZ 2, LC 4, NC 6, NA 7, BI 9, CK 11, CB 12, CV 14,
 * LO 16, LL 18, IM 20, SR 21, AR 22, IA 24, IS 25, ES 26, AD 27-28, EM 29 */

int gb(int m, int o)
{
	return m[204700 + o];
}

int pb(int m, int o, int v)
{
	m[204700 + o] = v % 256;
	return 0;
}

int gw(int m, int o)
{
	return m[204700 + o] + m[204700 + o + 1] * 256;
}

int pw(int m, int o, int v)
{
	m[204700 + o] = v % 256;
	m[204700 + o + 1] = v / 256;
	return 0;
}

int gd(int m, int o)
{
	return m[204700 + o] + m[204700 + o + 1] * 256 + m[204700 + o + 2] * 256 * 256 + m[204700 + o + 3] * 256 * 256 * 256;
}

int pd(int m, int o, int v)
{
	m[204700 + o] = v % 256;
	m[204700 + o + 1] = v / 256 % 256;
	m[204700 + o + 2] = v / 256 / 256 % 256;
	m[204700 + o + 3] = v / 256 / 256 / 256 % 256;
	return 0;
}

/* absolute 16-bit words: tables live at fixed offsets in mem, not inside ST */
int gwa(int m, int o)
{
	return m[o] + m[o + 1] * 256;
}

int pwa(int m, int o, int v)
{
	m[o] = v % 256;
	m[o + 1] = v / 256;
	return 0;
}

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

/* ---- input ---- */
int gcur(int m)
{
	int c = gw(m, 0);
	int s = gw(m, 2);
	if (c < s) {
		return m[c];
	}
	return 0;
}

int bump(int m, int n)
{
	int t = gw(m, 0) + n;
	pw(m, 0, t);
	return 0;
}

int idchar(int c)
{
	if (c == 95) { return 1; }
	if (c >= 48) { if (c <= 57) { return 1; } }
	if (c >= 65) { if (c <= 90) { return 1; } }
	if (c >= 97) { if (c <= 122) { return 1; } }
	return 0;
}

int delim(int c)
{
	if (c == 0) { return 1; }
	if (c == 32) { return 1; }
	if (c == 9) { return 1; }
	if (c == 10) { return 1; }
	if (c == 40) { return 1; }
	if (c == 41) { return 1; }
	if (c == 61) { return 1; }
	if (c == 59) { return 1; }
	if (c == 123) { return 1; }
	if (c == 125) { return 1; }
	return 0;
}

int fail(int m)
{
	int z = exit(1);
	return z;
}

/* whitespace, block comments and line comments */
int skipws(int m)
{
	int go = 1;
	while (go != 0) {
		int c = gcur(m);
		int sp = 0;
		if (c == 32) { sp = 1; }
		if (c == 9) { sp = 1; }
		if (c == 10) { sp = 1; }
		if (c == 13) { sp = 1; }
		if (sp != 0) {
			bump(m, 1);
		}
		else {
			if (c == 47) {
				bump(m, 1);
				int c2 = gcur(m);
				if (c2 == 42) {
					bump(m, 1);
					int fin = 0;
					while (fin == 0) {
						int c3 = gcur(m);
						if (c3 == 0) { fail(m); }
						if (c3 == 42) {
							bump(m, 1);
							if (gcur(m) == 47) {
								bump(m, 1);
								fin = 1;
							}
						}
						else {
							bump(m, 1);
						}
					}
				}
				else {
					if (c2 == 47) {
						bump(m, 1);
						int fin2 = 0;
						while (fin2 == 0) {
							int c4 = gcur(m);
							if (c4 == 0) { fail(m); }
							if (c4 == 10) { fin2 = 1; }
							else { bump(m, 1); }
						}
					}
					else {
						int bk = gw(m, 0) - 1;
						pw(m, 0, bk);
						go = 0;
					}
				}
			}
			else {
				go = 0;
			}
		}
	}
	return 0;
}

int isword(int m, int s)
{
	int save = gw(m, 0);
	int i = 0;
	int w = 1;
	while (w == 1) {
		int c = s[i];
		if (c == 0) {
			w = 2;
		}
		else {
			if (gcur(m) == c) {
				bump(m, 1);
				i = i + 1;
			}
			else {
				w = 0;
			}
		}
	}
	if (w == 2) {
		int d = gcur(m);
		if (delim(d) != 0) {
			return 1;
		}
	}
	pw(m, 0, save);
	return 0;
}

int same(int m, int s)
{
	int i = 0;
	while (s[i] != 0) {
		int a = m[205216 + i];
		int b = s[i];
		if (a != b) { return 0; }
		i = i + 1;
	}
	if (m[205216 + i] == 0) { return 1; }
	return 0;
}

int want(int m, int s)
{
	skipws(m);
	int i = 0;
	while (s[i] != 0) {
		int c = s[i];
		if (gcur(m) != c) { fail(m); }
		bump(m, 1);
		i = i + 1;
	}
	return 0;
}

int wantc(int m, int c)
{
	skipws(m);
	if (gcur(m) != c) { fail(m); }
	bump(m, 1);
	return 0;
}

int ident(int m)
{
	int k = 0;
	while (k < 16) {
		m[205216 + k] = 0;
		k = k + 1;
	}
	skipws(m);
	int n = 0;
	int go = 1;
	while (go != 0) {
		int c = gcur(m);
		if (idchar(c) != 0) {
			if (n == 0) {
				if (c >= 48) { if (c <= 57) { fail(m); } }
			}
			if (n >= 16) { fail(m); }
			m[205216 + n] = c;
			n = n + 1;
			bump(m, 1);
		}
		else {
			go = 0;
		}
	}
	if (n == 0) { fail(m); }
	return n;
}

int idfind(int m)
{
	int i = 0;
	int nc = gb(m, 6);
	while (i < nc) {
		int k = 0;
		int same1 = 1;
		while (k < 16) {
			int a = m[200000 + i * 16 + k];
			int b = m[205216 + k];
			if (a != b) { same1 = 0; }
			k = k + 1;
		}
		if (same1 != 0) { return i; }
		i = i + 1;
	}
	return 65535;
}

int findvar(int m)
{
	int i = idfind(m);
	if (i == 65535) { fail(m); }
	return i;
}

int defvar(int m)
{
	if (idfind(m) != 65535) { fail(m); }
	int n = gb(m, 6);
	if (n >= 32) { fail(m); }
	int k = 0;
	while (k < 16) {
		int c = m[205216 + k];
		m[200000 + n * 16 + k] = c;
		k = k + 1;
	}
	m[200640 + n] = 0;
	pb(m, 6, n + 1);
	return n;
}

int defarr(int m, int cnt)
{
	int es = gb(m, 26);
	int bytes = cnt * es;
	bytes = ((bytes + 7) / 8) * 8;
	if (idfind(m) != 65535) { fail(m); }
	int n = gb(m, 6);
	if (n >= 32) { fail(m); }
	int off = gd(m, 76);
	if (off + bytes >= 255000) { fail(m); }
	pd(m, 76, off + bytes);
	int k = 0;
	while (k < 16) {
		int c = m[205216 + k];
		m[200000 + n * 16 + k] = c;
		k = k + 1;
	}
	pda(m, 200512 + n * 4, off + bytes);
	m[200640 + n] = es;
	pb(m, 6, n + 1);
	return n;
}

int isarr(int m, int i)
{
	return m[200640 + i];
}

int varoff(int m, int i)
{
	if (m[200640 + i] != 0) {
		return gda(m, 200512 + i * 4);
	}
	return (i + 1) * 8;
}

/* ---- output ---- */
int emc(int m, int c)
{
	if (gb(m, 29) != 0) {
		char b[8];
		b[0] = c;
		int z = write(b, 1);
	}
	return 0;
}

int nl(int m)
{
	return emc(m, 10);
}

int ems(int m, int s)
{
	int i = 0;
	while (s[i] != 0) {
		emc(m, s[i]);
		i = i + 1;
	}
	return 0;
}

int emn(int m, int v)
{
	int place = 10000000;
	int started = 0;
	while (place > 0) {
		int d = v / place;
		d = d - (d / 10) * 10;
		if (d > 0) { started = 1; }
		if (started != 0) { emc(m, 48 + d); }
		place = place / 10;
	}
	if (started == 0) { emc(m, 48); }
	return 0;
}

int emreg(int m, int d)
{
	if (d == 0) { ems(m, "rax"); }
	else {
		if (d == 1) { ems(m, "rcx"); }
		else {
			if (d == 2) { ems(m, "rdx"); }
			else {
				if (d == 3) { ems(m, "rsi"); }
				else {
					if (d == 4) { ems(m, "rdi"); }
					else { ems(m, "r8"); }
				}
			}
		}
	}
	return 0;
}

int emarg(int m, int k)
{
	if (k >= 4) { fail(m); }
	if (k == 0) { ems(m, "rdi"); }
	else {
		if (k == 1) { ems(m, "rsi"); }
		else {
			if (k == 2) { ems(m, "rdx"); }
			else { ems(m, "rcx"); }
		}
	}
	return 0;
}

int emname(int m)
{
	int i = 0;
	while (m[205216 + i] != 0) {
		emc(m, m[205216 + i]);
		i = i + 1;
	}
	return 0;
}

int emop(int m, int d, int op)
{
	if (op == 43) { ems(m, "add "); }
	if (op == 45) { ems(m, "sub "); }
	if (op == 42) { ems(m, "imul "); }
	emreg(m, d);
	ems(m, ", ");
	emreg(m, d + 1);
	nl(m);
	return 0;
}

int emitret(int m)
{
	if (gb(m, 20) != 0) {
		ems(m, "mov rdi, rax");
		nl(m);
		ems(m, "mov eax, 60");
		nl(m);
		ems(m, "syscall");
		nl(m);
	}
	else {
		ems(m, "mov rsp, rbp");
		nl(m);
		ems(m, "pop rbp");
		nl(m);
		ems(m, "ret");
		nl(m);
	}
	return 0;
}

int emls(int m, int i)
{
	ems(m, "mov [rbp-");
	int o = varoff(m, i);
	emn(m, o);
	ems(m, "], rax");
	nl(m);
	return 0;
}

/* ---- literals ---- */
int litgo(int m)
{
	int so = gw(m, 0);
	pw(m, 16, so);
	pw(m, 18, 0);
	int go = 1;
	while (go != 0) {
		int c = gcur(m);
		if (c == 34) {
			go = 0;
		}
		else {
			if (c == 0) { fail(m); }
			int ln = gw(m, 18) + 1;
			pw(m, 18, ln);
			bump(m, 1);
		}
	}
	if (gb(m, 4) >= 999) { fail(m); }
	return 0;
}

int litent(int m, int i)
{
	int o = gw(m, 16);
	int l = gw(m, 18);
	pwa(m, 200676 + i * 4, o);
	pwa(m, 200676 + i * 4 + 2, l);
	return 0;
}

int wblock(int m)
{
	int a = gb(m, 4);
	ems(m, "mov eax, 1");
	nl(m);
	ems(m, "mov edi, 1");
	nl(m);
	ems(m, "mov esi, 4194424+m");
	emn(m, a + 1);
	nl(m);
	ems(m, "mov edx, m");
	emn(m, a + 1);
	ems(m, "end-m");
	emn(m, a + 1);
	nl(m);
	ems(m, "syscall");
	nl(m);
	litent(m, a);
	pb(m, 4, a + 1);
	return 0;
}

int lits(int m)
{
	int i = 0;
	int n = gb(m, 4);
	while (i < n) {
		ems(m, "m");
		emn(m, i + 1);
		ems(m, ":");
		nl(m);
		ems(m, "db ");
		emc(m, 34);
		int off = gwa(m, 200676 + i * 4);
		int len = gwa(m, 200676 + i * 4 + 2);
		int k = 0;
		while (k < len) {
			emc(m, m[off + k]);
			k = k + 1;
		}
		emc(m, 34);
		nl(m);
		ems(m, "m");
		emn(m, i + 1);
		ems(m, "end:");
		nl(m);
		ems(m, "db 0");
		nl(m);
		i = i + 1;
	}
	return 0;
}

/* ---- expressions ---- */
int chkdep(int m, int d)
{
	if (d >= 6) { fail(m); }
	return 0;
}

int ex1(int m, int d)
{
	ex2(m, d);
	int go = 1;
	while (go != 0) {
		skipws(m);
		int c = gcur(m);
		int o = 0;
		if (c == 43) { o = 43; }
		if (c == 45) { o = 45; }
		if (o == 0) {
			go = 0;
		}
		else {
			bump(m, 1);
			chkdep(m, d + 1);
			ex2(m, d + 1);
			emop(m, d, o);
		}
	}
	return 0;
}

int ex2(int m, int d)
{
	ex3(m, d);
	int go = 1;
	while (go != 0) {
		skipws(m);
		int c = gcur(m);
		int o = 0;
		if (c == 42) { o = 42; }
		if (c == 47) { o = 47; }
		if (c == 37) { o = 37; }
		if (o == 0) {
			go = 0;
		}
		else {
			bump(m, 1);
			chkdep(m, d + 1);
			ex3(m, d + 1);
			if (o == 42) {
				emop(m, d, o);
			}
			else {
				ems(m, "mov r9, ");
				emreg(m, d + 1);
				nl(m);
				int k = 0;
				while (k < d) {
					ems(m, "push ");
					emreg(m, k);
					nl(m);
					k = k + 1;
				}
				ems(m, "mov rax, ");
				emreg(m, d);
				nl(m);
				ems(m, "xor rdx, rdx");
				nl(m);
				ems(m, "div r9");
				nl(m);
				ems(m, "mov ");
				emreg(m, d);
				if (o == 47) { ems(m, ", rax"); }
				else { ems(m, ", rdx"); }
				nl(m);
				k = d;
				while (k > 0) {
					k = k - 1;
					ems(m, "pop ");
					emreg(m, k);
					nl(m);
				}
			}
		}
	}
	return 0;
}

int ex3lit(int m, int d)
{
	bump(m, 1);
	litgo(m);
	wantc(m, 34);
	int a = gb(m, 4);
	litent(m, a);
	ems(m, "mov ");
	emreg(m, d);
	ems(m, ", 4194424+m");
	emn(m, a + 1);
	nl(m);
	pb(m, 4, a + 1);
	return 0;
}

int ex3chr(int m, int d)
{
	bump(m, 1);
	int c = gcur(m);
	bump(m, 1);
	if (gcur(m) != 39) { fail(m); }
	bump(m, 1);
	ems(m, "mov ");
	emreg(m, d);
	ems(m, ", ");
	emn(m, c);
	nl(m);
	return 0;
}

int ex3paren(int m, int d)
{
	bump(m, 1);
	chkdep(m, d + 1);
	exprd(m, d + 1);
	ems(m, "mov ");
	emreg(m, d);
	ems(m, ", ");
	emreg(m, d + 1);
	nl(m);
	want(m, ")");
	return 0;
}

int ex3addr(int m, int d)
{
	bump(m, 1);
	ident(m);
	int i = findvar(m);
	int off = varoff(m, i);
	ems(m, "lea ");
	emreg(m, d);
	ems(m, ", [rbp-");
	emn(m, off);
	ems(m, "]");
	nl(m);
	return 0;
}

int ex3deref(int m, int d)
{
	bump(m, 1);
	ident(m);
	int i = findvar(m);
	int off = varoff(m, i);
	ems(m, "mov ");
	emreg(m, d);
	ems(m, ", [rbp-");
	emn(m, off);
	ems(m, "]");
	nl(m);
	ems(m, "mov ");
	emreg(m, d);
	ems(m, ", [");
	emreg(m, d);
	ems(m, "]");
	nl(m);
	return 0;
}

int ex3num(int m, int d)
{
	int v = numval(m);
	ems(m, "mov ");
	emreg(m, d);
	ems(m, ", ");
	emn(m, v);
	nl(m);
	return 0;
}

int ex3var(int m, int d)
{
	ident(m);
	skipws(m);
	int c = gcur(m);
	if (c == 40) {
		ex3call(m, d);
	}
	else {
		if (c == 91) {
			ex3sub(m, d);
		}
		else {
			int i = findvar(m);
			if (isarr(m, i) != 0) { fail(m); }
			int off = varoff(m, i);
			ems(m, "mov ");
			emreg(m, d);
			ems(m, ", [rbp-");
			emn(m, off);
			ems(m, "]");
			nl(m);
		}
	}
	return 0;
}

int ex3sub(int m, int d)
{
	bump(m, 1);
	int i = findvar(m);
	int kind = isarr(m, i);
	if (gb(m, 25) != 0) { fail(m); }
	pb(m, 25, 1);
	int off = varoff(m, i);
	if (kind != 0) {
		ems(m, "lea ");
		emreg(m, d);
		ems(m, ", [rbp-");
		emn(m, off);
		ems(m, "]");
		nl(m);
	}
	else {
		ems(m, "mov ");
		emreg(m, d);
		ems(m, ", [rbp-");
		emn(m, off);
		ems(m, "]");
		nl(m);
	}
	exprd(m, d + 1);
	if (kind == 8) {
		int k = 0;
		while (k < 3) {
			ems(m, "add ");
			emreg(m, d + 1);
			ems(m, ", ");
			emreg(m, d + 1);
			nl(m);
			k = k + 1;
		}
	}
	ems(m, "add ");
	emreg(m, d);
	ems(m, ", ");
	emreg(m, d + 1);
	nl(m);
	if (kind == 8) {
		ems(m, "mov ");
		emreg(m, d);
		ems(m, ", [");
		emreg(m, d);
		ems(m, "]");
		nl(m);
	}
	else {
		ems(m, "movzx ");
		emreg(m, d);
		ems(m, ", byte [");
		emreg(m, d);
		ems(m, "]");
		nl(m);
	}
	want(m, "]");
	pb(m, 25, 0);
	return 0;
}

int numval(int m)
{
	skipws(m);
	int v = 0;
	int d = 0;
	int go = 1;
	while (go != 0) {
		int c = gcur(m);
		if (c >= 48) {
			if (c <= 57) {
				d = d + 1;
				v = v * 10 + (c - 48);
				bump(m, 1);
			}
			else { go = 0; }
		}
		else { go = 0; }
	}
	if (d == 0) { fail(m); }
	if (d > 8) { fail(m); }
	if (v > 16777215) { fail(m); }
	return v;
}

/* ---- calls ---- */
int callargs(int m)
{
	char nm[16];
	int k = 0;
	while (k < 16) {
		int c1 = m[205216 + k];
		nm[k] = c1;
		k = k + 1;
	}
	bump(m, 1);
	pb(m, 22, 0);
	skipws(m);
	if (gcur(m) != 41) {
		pb(m, 24, 1);
		int go = 1;
		while (go != 0) {
			int ad = gb(m, 27);
			exprd(m, ad);
			ems(m, "mov [rbp-");
			int off = 259900 - gb(m, 22) * 8;
			emn(m, off);
			ems(m, "], ");
			emreg(m, ad);
			nl(m);
			int ac = gb(m, 22) + 1;
			pb(m, 22, ac);
			skipws(m);
			if (gcur(m) == 44) {
				bump(m, 1);
			}
			else {
				go = 0;
			}
		}
		pb(m, 24, 0);
	}
	want(m, ")");
	int j = gb(m, 22);
	while (j > 0) {
		j = j - 1;
		ems(m, "mov ");
		emarg(m, j);
		ems(m, ", [rbp-");
		emn(m, 259900 - j * 8);
		ems(m, "]");
		nl(m);
	}
	ems(m, "call ");
	ems(m, &nm);
	nl(m);
	k = 0;
	while (k < 16) {
		int c2 = nm[k];
		m[205216 + k] = c2;
		k = k + 1;
	}
	return 0;
}

int ex3read(int m, int d)
{
	bump(m, 1);
	ident(m);
	int i = findvar(m);
	if (isarr(m, i) == 0) { fail(m); }
	int off = varoff(m, i);
	want(m, ",");
	int n = numval(m);
	want(m, ")");
	ems(m, "mov eax, 0");
	nl(m);
	ems(m, "mov edi, 0");
	nl(m);
	ems(m, "lea rsi, [rbp-");
	emn(m, off);
	ems(m, "]");
	nl(m);
	ems(m, "mov edx, ");
	emn(m, n);
	nl(m);
	ems(m, "syscall");
	nl(m);
	return 0;
}

int ex3wr(int m, int d, int fd)
{
	bump(m, 1);
	ident(m);
	int i = findvar(m);
	int kind = isarr(m, i);
	int off = varoff(m, i);
	want(m, ",");
	expr(m);
	ems(m, "mov rdx, rax");
	nl(m);
	if (kind != 0) {
		ems(m, "lea rsi, [rbp-");
	}
	else {
		ems(m, "mov rsi, [rbp-");
	}
	emn(m, off);
	ems(m, "]");
	nl(m);
	ems(m, "mov eax, 1");
	nl(m);
	ems(m, "mov edi, ");
	emn(m, fd);
	nl(m);
	ems(m, "syscall");
	nl(m);
	want(m, ")");
	return 0;
}

int ex3exit(int m, int d)
{
	bump(m, 1);
	expr(m);
	ems(m, "mov rdi, rax");
	nl(m);
	ems(m, "mov eax, 60");
	nl(m);
	ems(m, "syscall");
	nl(m);
	want(m, ")");
	return 0;
}

int ex3call(int m, int d)
{
	if (same(m, "read") != 0) {
		ex3read(m, d);
	}
	else {
		if (same(m, "write") != 0) {
			ex3wr(m, d, 1);
		}
		else {
			if (same(m, "werr") != 0) {
				ex3wr(m, d, 2);
			}
			else {
				if (same(m, "exit") != 0) {
					ex3exit(m, d);
				}
				else {
				if (gb(m, 24) != 0) { fail(m); }
				int k = 0;
				while (k < d) {
					ems(m, "push ");
					emreg(m, k);
					nl(m);
					k = k + 1;
				}
				chkdep(m, d + 1);
				pw(m, 27, d + 1);
				callargs(m);
				if (d != 0) {
					ems(m, "mov ");
					emreg(m, d);
					ems(m, ", rax");
					nl(m);
				}
				k = d;
				while (k > 0) {
					k = k - 1;
					ems(m, "pop ");
					emreg(m, k);
					nl(m);
				}
			}
		}
	}
	}
	return 0;
}

int ex3(int m, int d)
{
	skipws(m);
	int c = gcur(m);
	if (c == 34) {
		ex3lit(m, d);
	}
	else {
		if (c == 39) {
			ex3chr(m, d);
		}
		else {
			if (c == 40) {
				ex3paren(m, d);
			}
			else {
				if (c == 38) {
					ex3addr(m, d);
				}
				else {
					if (c == 42) {
						ex3deref(m, d);
					}
					else {
						if (c >= 48) {
							if (c <= 57) {
								ex3num(m, d);
							}
							else {
								ex3var(m, d);
							}
						}
						else {
							ex3var(m, d);
						}
					}
				}
			}
		}
	}
	return 0;
}

int exprd(int m, int d)
{
	ex1(m, d);
	return 0;
}

int expr(int m)
{
	return exprd(m, 0);
}

/* ---- conditions ---- */
int condjump(int m, int k)
{
	nl(m);
	if (k == 1) { ems(m, "jz.l "); }
	else {
		if (k == 2) { ems(m, "jnz.l "); }
		else { ems(m, "jb.l "); }
	}
	return 0;
}

int cndbnd(int m)
{
	int v = 0;
	skipws(m);
	int c = gcur(m);
	if (c == 39) {
		bump(m, 1);
		v = gcur(m);
		bump(m, 1);
		if (gcur(m) != 39) { fail(m); }
		bump(m, 1);
		pd(m, 72, v);
		pb(m, 14, 0);
	}
	else {
		if (c >= 48) {
			if (c <= 57) {
				v = numval(m);
				pd(m, 72, v);
				pb(m, 14, 0);
			}
			else {
				cndvar(m);
			}
		}
		else {
			cndvar(m);
		}
	}
	return 0;
}

int cndvar(int m)
{
	ident(m);
	int i = findvar(m);
	int off = varoff(m, i);
	ems(m, "mov rcx, [rbp-");
	emn(m, off);
	ems(m, "]");
	nl(m);
	pb(m, 14, 1);
	pd(m, 72, 0);
	return 0;
}

int cond(int m)
{
	int b = 0;
	expr(m);
	pb(m, 11, 2);
	pd(m, 72, 0);
	pb(m, 14, 0);
	skipws(m);
	int c = gcur(m);
	if (c == 60) {
		bump(m, 1);
		skipws(m);
		if (gcur(m) == 61) {
			bump(m, 1);
			cndbnd(m);
			if (gb(m, 14) != 0) {
				nl(m);
				ems(m, "inc rcx");
				nl(m);
				pb(m, 11, 0);
			}
			else {
				b = gd(m, 72);
				if (b >= 255) { fail(m); }
				pd(m, 72, b + 1);
				pb(m, 11, 0);
			}
		}
		else {
			cndbnd(m);
			pb(m, 11, 0);
		}
	}
	else {
		if (c == 62) {
			bump(m, 1);
			skipws(m);
			if (gcur(m) == 61) {
				bump(m, 1);
				cndbnd(m);
				if (gb(m, 14) != 0) {
					nl(m);
					ems(m, "dec rcx");
					nl(m);
					pb(m, 11, 3);
				}
				else {
					b = gd(m, 72);
					if (b == 0) { fail(m); }
					pd(m, 72, b - 1);
					pb(m, 11, 3);
				}
			}
			else {
				cndbnd(m);
				pb(m, 11, 3);
			}
		}
		else {
			if (c == 61) {
				bump(m, 1);
				if (gcur(m) != 61) { fail(m); }
				bump(m, 1);
				cndbnd(m);
				pb(m, 11, 1);
			}
			else {
				if (c == 33) {
					bump(m, 1);
					if (gcur(m) != 61) { fail(m); }
					bump(m, 1);
					cndbnd(m);
					pb(m, 11, 2);
				}
			}
		}
	}
	return 0;
}

int condj(int m, int id, int lt)
{
	int k = gb(m, 11);
	int b = gd(m, 72);
	if (gb(m, 14) == 0) {
		if (k == 3) {
			ems(m, "mov rcx, ");
			emn(m, b);
			nl(m);
			ems(m, "cmp rcx, rax");
			condjump(m, 3);
		}
		else {
			ems(m, "cmp rax, ");
			emn(m, b);
			condjump(m, k);
		}
	}
	else {
		if (k == 3) { ems(m, "cmp rcx, rax"); }
		else { ems(m, "cmp rax, rcx"); }
		condjump(m, k);
	}
	ems(m, "L");
	emn(m, id);
	emc(m, lt);
	nl(m);
	return 0;
}

int newid(int m)
{
	int id = gw(m, 9) + 1;
	if (id >= 65000) { fail(m); }
	pw(m, 9, id);
	return id;
}

/* ---- statements ---- */
int st_write(int m)
{
	want(m, "(");
	wantc(m, 34);
	litgo(m);
	wantc(m, 34);
	want(m, ")");
	want(m, ";");
	wblock(m);
	return 0;
}

int st_int(int m)
{
	pb(m, 26, 8);
	ident(m);
	skipws(m);
	if (gcur(m) == 91) {
		bump(m, 1);
		int v = numval(m);
		want(m, "]");
		want(m, ";");
		defarr(m, v);
	}
	else {
		int i = defvar(m);
		want(m, "=");
		expr(m);
		emls(m, i);
		want(m, ";");
	}
	return 0;
}

int st_char(int m)
{
	ident(m);
	skipws(m);
	if (gcur(m) != 91) { fail(m); }
	bump(m, 1);
	int v = numval(m);
	want(m, "]");
	want(m, ";");
	pb(m, 26, 1);
	defarr(m, v);
	return 0;
}

int st_ret(int m)
{
	expr(m);
	want(m, ";");
	emitret(m);
	pb(m, 21, 1);
	skipws(m);
	if (gcur(m) != 125) { fail(m); }
	bump(m, 1);
	return 0;
}

int st_ptr(int m)
{
	bump(m, 1);
	ident(m);
	int i = findvar(m);
	int off = varoff(m, i);
	want(m, "=");
	expr(m);
	ems(m, "mov rcx, [rbp-");
	emn(m, off);
	ems(m, "]");
	nl(m);
	ems(m, "mov [rcx], rax");
	nl(m);
	want(m, ";");
	return 0;
}

int st_sub(int m)
{
	bump(m, 1);
	int i = findvar(m);
	int kind = isarr(m, i);
	if (gb(m, 25) != 0) { fail(m); }
	pb(m, 25, 1);
	int off = varoff(m, i);
	exprd(m, 1);
	if (kind == 8) {
		int k = 0;
		while (k < 3) {
			ems(m, "add rcx, rcx");
			nl(m);
			k = k + 1;
		}
	}
	ems(m, "mov [rbp-328], rcx");
	nl(m);
	pb(m, 25, 0);
	want(m, "]");
	want(m, "=");
	expr(m);
	if (kind != 0) {
		ems(m, "lea rcx, [rbp-");
	}
	else {
		ems(m, "mov rcx, [rbp-");
	}
	emn(m, off);
	ems(m, "]");
	nl(m);
	ems(m, "mov rdx, [rbp-328]");
	nl(m);
	ems(m, "add rcx, rdx");
	nl(m);
	if (kind == 8) {
		ems(m, "mov [rcx], rax");
		nl(m);
	}
	else {
		ems(m, "mov [rcx], al");
		nl(m);
	}
	want(m, ";");
	return 0;
}

int st_bare(int m)
{
	int i = findvar(m);
	if (isarr(m, i) != 0) { fail(m); }
	want(m, "=");
	expr(m);
	emls(m, i);
	want(m, ";");
	return 0;
}

int st_call(int m)
{
	pw(m, 27, 1);
	callargs(m);
	want(m, ";");
	return 0;
}

int st_asg(int m)
{
	skipws(m);
	if (gcur(m) == 42) {
		st_ptr(m);
	}
	else {
		ident(m);
		skipws(m);
		int c = gcur(m);
		if (c == 91) {
			st_sub(m);
		}
		else {
			if (c == 40) {
				st_call(m);
			}
			else {
				st_bare(m);
			}
		}
	}
	return 0;
}

int stmt(int m)
{
	int r = 0;
	if (isword(m, "while") != 0) {
		st_while(m);
	}
	else {
		if (isword(m, "write") != 0) {
			st_write(m);
		}
		else {
			if (isword(m, "return") != 0) {
				st_ret(m);
				r = 1;
			}
			else {
				if (isword(m, "if") != 0) {
					st_if(m);
				}
				else {
					if (isword(m, "char") != 0) {
						st_char(m);
					}
					else {
						if (isword(m, "int") != 0) {
							st_int(m);
						}
						else {
							st_asg(m);
						}
					}
				}
			}
		}
	}
	return r;
}

int body(int m)
{
	int done = 0;
	while (done == 0) {
		skipws(m);
		if (gcur(m) == 125) {
			bump(m, 1);
			done = 1;
		}
		else {
			if (stmt(m) != 0) { done = 1; }
		}
	}
	return 0;
}

int st_while(int m)
{
	want(m, "(");
	int id = newid(m);
	ems(m, "L");
	emn(m, id);
	ems(m, ":");
	nl(m);
	cond(m);
	want(m, ")");
	want(m, "{");
	condj(m, id, 98);
	ems(m, "jmp.l L");
	emn(m, id);
	ems(m, "e");
	nl(m);
	ems(m, "L");
	emn(m, id);
	ems(m, "b:");
	nl(m);
	body(m);
	ems(m, "jmp.l L");
	emn(m, id);
	nl(m);
	ems(m, "L");
	emn(m, id);
	ems(m, "e:");
	nl(m);
	return 0;
}

int st_if(int m)
{
	want(m, "(");
	cond(m);
	want(m, ")");
	want(m, "{");
	int id = newid(m);
	condj(m, id, 116);
	ems(m, "jmp.l L");
	emn(m, id);
	ems(m, "e");
	nl(m);
	ems(m, "L");
	emn(m, id);
	ems(m, "t:");
	nl(m);
	body(m);
	skipws(m);
	if (isword(m, "else") != 0) {
		ems(m, "jmp.l L");
		emn(m, id);
		ems(m, "x");
		nl(m);
		ems(m, "L");
		emn(m, id);
		ems(m, "e:");
		nl(m);
		want(m, "{");
		body(m);
		ems(m, "L");
		emn(m, id);
		ems(m, "x:");
		nl(m);
	}
	else {
		ems(m, "L");
		emn(m, id);
		ems(m, "e:");
		nl(m);
	}
	return 0;
}

int func(int m)
{
	want(m, "int");
	ident(m);
	emname(m);
	ems(m, ":");
	nl(m);
	pb(m, 20, 0);
	pb(m, 21, 0);
	pb(m, 6, 0);
	if (same(m, "main") != 0) { pb(m, 20, 1); }
	want(m, "(");
	if (isword(m, "void") != 0) {
	}
	else {
		int go = 1;
		while (go != 0) {
			want(m, "int");
			ident(m);
			defvar(m);
			skipws(m);
			if (gcur(m) == 44) {
				bump(m, 1);
			}
			else {
				go = 0;
			}
		}
	}
	want(m, ")");
	want(m, "{");
	ems(m, "push rbp");
	nl(m);
	ems(m, "mov rbp, rsp");
	nl(m);
	ems(m, "mov r10, 260000");
	nl(m);
	ems(m, "sub rsp, r10");
	nl(m);
	int i = 0;
	int np = gb(m, 6);
	while (i < np) {
		int o = varoff(m, i);
		ems(m, "mov [rbp-");
		emn(m, o);
		ems(m, "], ");
		emarg(m, i);
		nl(m);
		i = i + 1;
	}
	body(m);
	if (gb(m, 21) == 0) {
		ems(m, "mov rax, 0");
		nl(m);
		emitret(m);
	}
	return 0;
}

int parse(int m)
{
	ems(m, "; generated by cc: dialect source, not a program. Assemble it with asm1");
	nl(m);
	int done = 0;
	while (done == 0) {
		skipws(m);
		if (gcur(m) == 0) { done = 1; }
		else { func(m); }
	}
	ems(m, "entry main");
	nl(m);
	lits(m);
	skipws(m);
	if (gcur(m) != 0) { fail(m); }
	return 0;
}

int main(void)
{
	char mem[210000];
	int m = &mem;
	int n = read(mem, 200000);
	if (n <= 0) {
		int z = exit(1);
	}
	if (n >= 200000) {
		/* a full buffer cannot be told from a truncated one: refuse it, as
		 * the assembler refuses an input that fills its read buffer. */
		int z2 = exit(1);
	}
	pw(m, 2, n);
	pw(m, 0, 0);
	pb(m, 4, 0);
	pw(m, 9, 0);
	pd(m, 76, 400);
	pb(m, 29, 0);
	parse(m);
	pw(m, 0, 0);
	pb(m, 4, 0);
	pw(m, 9, 0);
	pd(m, 76, 400);
	pb(m, 29, 1);
	parse(m);
	return 0;
}
