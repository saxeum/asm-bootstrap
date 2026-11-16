/* src/asm1.c -- the assembler, written in the subset cc compiles.
	int w = 0;
	int rr = 0;
	int bb = 0;
	int t = 0;
	int op = 0;
	int s = 0;
	int w = 0;
	int rr = 0;
	int bb = 0;
	int t = 0;
	int op = 0;
	int s = 0;
 *
 * This is the D3 port. `cc < src/asm1.c > asm1.c.s` and `asm1 < asm1.c.s >
 * asm2` must produce a binary that assembles the whole corpus byte-identically
 * to `asm1`. It is a three-pass assembler like asm1: pass 0 defines labels and
 * counts body bytes, pass 1 counts again with the labels known, pass 2 writes
 * the 120-byte ELF header and the body.
 *
 * One buffer holds the world:
 *
 *   SRC    0      20000   input bytes, read once
 *   LBLN   20000  8192    512 labels, 16 bytes each
 *   LBLV   28200  2048    512 label values, 4 bytes each
 *   ST     30300  256     scalar state
 *   NAME   30560  16      the word being scanned
 *
 * Arrays now store their END (see src/cc.s), so mem's base is rbp-(end) and
 * its indices stay below rbp. Values wider than a byte are stored little
 * endian with gd/pd.
 */

/* state offsets inside ST (base 30300):
 * CU 0(4) LN 4(4) PS 8 CNT 9(4) NL 13(2) ENT 15(4) HENT 19 FS 20(4)
 * O1 24: K +0 S +1 R +2 V +4(4) B +8 X +9 D +10(4)
 * O2 40: same; OP 56; T0 60(4); T1 64(4); T2 68(4)
 * K: 0 register, 1 memory, 2 immediate, 3 relative  S: 0 unknown, 1, 4, 8
 */

int gb(int m, int o)
{
	return m[30300 + o];
}

int pb(int m, int o, int v)
{
	m[30300 + o] = v % 256;
	return 0;
}

int gw(int m, int o)
{
	return m[30300 + o] + m[30300 + o + 1] * 256;
}

int pw(int m, int o, int v)
{
	m[30300 + o] = v % 256;
	m[30300 + o + 1] = v / 256 % 256;
	return 0;
}

int gd(int m, int o)
{
	return m[30300 + o] + m[30300 + o + 1] * 256 + m[30300 + o + 2] * 256 * 256 + m[30300 + o + 3] * 256 * 256 * 256;
}

int pd(int m, int o, int v)
{
	m[30300 + o] = v % 256;
	m[30300 + o + 1] = v / 256 % 256;
	m[30300 + o + 2] = v / 256 / 256 % 256;
	m[30300 + o + 3] = v / 256 / 256 / 256 % 256;
	return 0;
}

int fail(int m)
{
	int z = exit(1);
	return z;
}

/* ---- input ---- */
int gcur(int m)
{
	int c = gd(m, 0);
	int n = gd(m, 61);
	if (c < n) {
		return m[c];
	}
	return 0;
}

int adv(int m, int n)
{
	int t = gd(m, 0) + n;
	pd(m, 0, t);
	return 0;
}

int skipsp(int m)
{
	int go = 1;
	while (go != 0) {
		int c = gcur(m);
		if (c == 32) { adv(m, 1); }
		else {
			if (c == 9) { adv(m, 1); }
			else { go = 0; }
		}
	}
	return 0;
}

int eol(int m)
{
	int c = gcur(m);
	if (c == 59) {
		int go = 1;
		while (go != 0) {
			c = gcur(m);
			if (c == 0) { go = 0; }
			else {
				if (c == 10) { go = 0; }
				else { adv(m, 1); }
			}
		}
	}
	c = gcur(m);
	if (c == 10) {
		adv(m, 1);
		int t = gd(m, 4) + 1;
		pd(m, 4, t);
		return 1;
	}
	if (c == 0) { return 1; }
	return 0;
}

int idchar(int c)
{
	if (c == 95) { return 1; }
	if (c == 46) { return 1; }
	if (c >= 48) { if (c < 58) { return 1; } }
	if (c >= 65) { if (c < 91) { return 1; } }
	if (c >= 97) { if (c < 123) { return 1; } }
	return 0;
}

int word(int m)
{
	int k = 0;
	while (k < 16) {
		m[30560 + k] = 0;
		k = k + 1;
	}
	k = 0;
	int go = 1;
	while (go != 0) {
		int c = gcur(m);
		if (idchar(c) != 0) {
			if (k < 16) { m[30560 + k] = c; }
			k = k + 1;
			adv(m, 1);
		}
		else {
			go = 0;
		}
	}
	return k;
}

int same(int m, int s)
{
	int i = 0;
	int eq = 1;
	while (s[i] != 0) {
		int a = m[30560 + i];
		int b = s[i];
		if (a != b) { eq = 0; }
		i = i + 1;
	}
	if (m[30560 + i] != 0) { eq = 0; }
	return eq;
}

/* ---- labels ---- */
int lfind(int m)
{
	int i = 0;
	int r = 65535;
	int n = gw(m, 13);
	while (i < n) {
		int k = 0;
		int eq = 1;
		while (k < 16) {
			int a = m[20000 + i * 16 + k];
			int b = m[30560 + k];
			if (a != b) { eq = 0; }
			k = k + 1;
		}
		if (eq != 0) { r = i; i = n; }
		else { i = i + 1; }
	}
	return r;
}

int ldef(int m)
{
	int i = lfind(m);
	if (i != 65535) { fail(m); }
	int n = gw(m, 13);
	if (n >= 512) { fail(m); }
	int k = 0;
	while (k < 16) {
		int c = m[30560 + k];
		m[20000 + n * 16 + k] = c;
		k = k + 1;
	}
	int v = gd(m, 9);
	pd(m, 28200 + n * 4, v);
	pw(m, 13, n + 1);
	return 0;
}

/* ---- expressions ---- */
int term(int m)
{
	int v = 0;
	skipsp(m);
	int c = gcur(m);
	if (c == 45) {
		adv(m, 1);
		v = term(m);
		return 0 - v;
	}
	if (c == 39) {
		adv(m, 1);
		v = gcur(m);
		adv(m, 1);
		if (gcur(m) != 39) { fail(m); }
		adv(m, 1);
		return v;
	}
	if (c >= 48) {
		if (c < 58) {
			return numval(m);
		}
	}
	word(m);
	int i = lfind(m);
	if (i != 65535) {
		return gd(m, 28200 + i * 4);
	}
	if (gb(m, 8) == 0) { return 0; }
	fail(m);
	return 0;
}

int numval(int m)
{
	int v = 0;
	int c = gcur(m);
	int go = 1;
	if (c == 48) {
		adv(m, 1);
		c = gcur(m);
		if (c == 120) {
			adv(m, 1);
			go = 1;
			while (go != 0) {
				c = gcur(m);
				int d = 99;
				if (c >= 48) { if (c < 58) { d = c - 48; } }
				if (c >= 97) { if (c < 103) { d = c - 87; } }
				if (c >= 65) { if (c < 71) { d = c - 55; } }
				if (d == 99) { go = 0; }
				else {
					v = v * 16 + d;
					adv(m, 1);
				}
			}
			return v;
		}
		return 0;
	}
	go = 1;
	while (go != 0) {
		c = gcur(m);
		if (c >= 48) {
			if (c < 58) {
				v = v * 10 + (c - 48);
				adv(m, 1);
			}
			else { go = 0; }
		}
		else { go = 0; }
	}
	return v;
}

int expr(int m)
{
	int v = term(m);
	int go = 1;
	int t = 0;
	while (go != 0) {
		skipsp(m);
		int c = gcur(m);
		if (c == 43) {
			adv(m, 1);
			t = term(m);
			v = v + t;
		}
		else {
			if (c == 45) {
				adv(m, 1);
				t = term(m);
				v = v - t;
			}
			else { go = 0; }
		}
	}
	return v;
}

/* ---- operand parsing ---- */
int regno(int m)
{
	if (same(m, "rax")) { pb(m, 57, 8); return 0; }
	if (same(m, "rcx")) { pb(m, 57, 8); return 1; }
	if (same(m, "rdx")) { pb(m, 57, 8); return 2; }
	if (same(m, "rbx")) { pb(m, 57, 8); return 3; }
	if (same(m, "rsp")) { pb(m, 57, 8); return 4; }
	if (same(m, "rbp")) { pb(m, 57, 8); return 5; }
	if (same(m, "rsi")) { pb(m, 57, 8); return 6; }
	if (same(m, "rdi")) { pb(m, 57, 8); return 7; }
	if (same(m, "eax")) { pb(m, 57, 4); return 0; }
	if (same(m, "ecx")) { pb(m, 57, 4); return 1; }
	if (same(m, "edx")) { pb(m, 57, 4); return 2; }
	if (same(m, "ebx")) { pb(m, 57, 4); return 3; }
	if (same(m, "esp")) { pb(m, 57, 4); return 4; }
	if (same(m, "ebp")) { pb(m, 57, 4); return 5; }
	if (same(m, "esi")) { pb(m, 57, 4); return 6; }
	if (same(m, "edi")) { pb(m, 57, 4); return 7; }
	if (same(m, "al")) { pb(m, 57, 1); return 0; }
	if (same(m, "cl")) { pb(m, 57, 1); return 1; }
	if (same(m, "dl")) { pb(m, 57, 1); return 2; }
	if (same(m, "bl")) { pb(m, 57, 1); return 3; }
	if (same(m, "ah")) { pb(m, 57, 1); return 4; }
	if (same(m, "ch")) { pb(m, 57, 1); return 5; }
	if (same(m, "dh")) { pb(m, 57, 1); return 6; }
	if (same(m, "bh")) { pb(m, 57, 1); return 7; }
	if (same(m, "r8")) { pb(m, 57, 8); return 8; }
	if (same(m, "r9")) { pb(m, 57, 8); return 9; }
	if (same(m, "r10")) { pb(m, 57, 8); return 10; }
	if (same(m, "r11")) { pb(m, 57, 8); return 11; }
	if (same(m, "r12")) { pb(m, 57, 8); return 12; }
	if (same(m, "r13")) { pb(m, 57, 8); return 13; }
	if (same(m, "r14")) { pb(m, 57, 8); return 14; }
	if (same(m, "r15")) { pb(m, 57, 8); return 15; }
	return 65535;
}

int isreg(int m)
{
	word(m);
	int r = regno(m);
	if (r != 65535) { return 1; }
	return 0;
}

int parseop(int m, int o)
{
	skipsp(m);
	int c = gcur(m);
	if (c == 91) {
		pb(m, o, 1);
		pb(m, o + 1, 0);
		return memop(m, o);
	}
	int save = gd(m, 0);
	word(m);
	int sz = 0;
	if (same(m, "byte")) { sz = 1; }
	if (same(m, "dword")) { sz = 4; }
	if (same(m, "qword")) { sz = 8; }
	if (sz != 0) {
		pb(m, o, 1);
		pb(m, o + 1, sz);
		return memop(m, o);
	}
	int r = regno(m);
	if (r != 65535) {
		int s2 = gb(m, 57);
		pb(m, o, 0);
		pb(m, o + 1, s2);
		pb(m, o + 2, r);
		return 0;
	}
	pd(m, 0, save);
	pb(m, o, 2);
	pb(m, o + 1, 0);
	int v = expr(m);
	pd(m, o + 4, v);
	return 0;
}

int memop(int m, int o)
{
	int t = 0;
	skipsp(m);
	if (gcur(m) != 91) { fail(m); }
	adv(m, 1);
	word(m);
	int b = regno(m);
	if (b == 65535) { fail(m); }
	pb(m, o + 8, b);
	pb(m, o + 9, 0);
	pd(m, o + 10, 0);
	skipsp(m);
	int c = gcur(m);
	if (c == 93) { adv(m, 1); return 0; }
	if (c == 45) {
		adv(m, 1);
		int v = expr(m);
		pd(m, o + 10, 0 - v);
	}
	else {
		if (c == 43) {
			adv(m, 1);
			skipsp(m);
			int s = gd(m, 0);
			word(m);
			int x = regno(m);
			if (x != 65535) {
				pb(m, o + 9, x + 1);
				skipsp(m);
				c = gcur(m);
				if (c == 43) { adv(m, 1); t = expr(m); pd(m, o + 10, t); }
				else {
					if (c == 45) { adv(m, 1); t = expr(m); pd(m, o + 10, 0 - t); }
				}
			}
			else {
				pd(m, 0, s);
				t = expr(m);
				pd(m, o + 10, t);
			}
		}
		else { fail(m); }
	}
	skipsp(m);
	if (gcur(m) != 93) { fail(m); }
	adv(m, 1);
	return 0;
}

/* ---- byte output and encoding helpers ---- */
int ex(int m, int v)
{
	int p = gb(m, 8);
	if (p == 2) {
		char ob[4];
		ob[0] = v % 256;
		int z = write(ob, 1);
	}
	int t = gd(m, 9) + 1;
	pd(m, 9, t);
	return 0;
}

int ex4(int m, int v)
{
	ex(m, v % 256);
	ex(m, v / 256 % 256);
	ex(m, v / 256 / 256 % 256);
	ex(m, v / 256 / 256 / 256 % 256);
	return 0;
}

int ex8(int m, int v)
{
	ex(m, v % 256);
	ex(m, v / 256 % 256);
	ex(m, v / 256 / 256 % 256);
	ex(m, v / 256 / 256 / 256 % 256);
	ex(m, 0);
	ex(m, 0);
	ex(m, 0);
	ex(m, 0);
	return 0;
}

int exs(int m, int s)
{
	int i = 0;
	while (s[i] != 0) {
		ex(m, s[i]);
		i = i + 1;
	}
	return 0;
}

int rex(int m, int w, int r, int xb)
{
	int v = 64 + w * 8 + r * 4 + xb;
	if (v != 64) { ex(m, v); }
	return 0;
}

int modrm(int m, int mod, int reg, int rm)
{
	ex(m, mod * 64 + (reg % 8) * 8 + rm % 8);
	return 0;
}

int chk8(int m, int v)
{
	int t = v + 128;
	if (t < 0) { fail(m); }
	if (t < 256) { return 0; }
	fail(m);
	return 0;
}

int dispform(int m, int o)
{
	int d = gd(m, o + 10);
	int x = gb(m, o + 9);
	int b = gb(m, o + 8);
	if (d == 0) {
		if (x == 0) {
			if (b % 8 != 5) { return 0; }
		}
	}
	int t = d + 128;
	if (t < 0) { t = 9999; }
	if (t < 256) { return 1; }
	return 2;
}

/* emit a memory operand; regfield is the ModRM reg/opcode field */
int emitmem(int m, int o, int regfield)
{
	int b = gb(m, o + 8);
	int x = gb(m, o + 9);
	int d = gd(m, o + 10);
	int mod = dispform(m, o);
	int rm = b;
	if (x != 0) { rm = 4; }
	else {
		if (b % 8 == 4) { rm = 4; }
	}
	modrm(m, mod, regfield, rm);
	if (rm == 4) {
		int ib = 4;
		if (x != 0) { ib = (x - 1) % 8; }
		ex(m, ib * 8 + b % 8);
	}
	if (mod == 1) {
		int t = d + 128;
		if (t < 0) { fail(m); }
		if (t < 256) { ex(m, d % 256); }
	}
	if (mod == 2) { ex4(m, d); }
	return 0;
}

int memrex(int m, int o, int regfield)
{
	int b = gb(m, o + 8);
	int x = gb(m, o + 9);
	int r = 0;
	if (regfield > 7) { r = 1; }
	int xx = 0;
	if (x > 8) { xx = 1; }
	int bb = 0;
	if (b > 7) { bb = 1; }
	return rex(m, 0, r, xx*2+bb);
}

/* ---- instruction handlers ---- */
int enc_alu(int m, int base)
{
	int w = 0;
	int rr = 0;
	int bb = 0;
	int t = 0;
	int op = 0;
	int s = 0;
	int digit = base / 8;
	int k1 = gb(m, 24);
	int k2 = gb(m, 40);
	int s1 = gb(m, 25);
	int s2 = gb(m, 41);
	int r1 = gb(m, 26);
	int r2 = gb(m, 42);
	int v2 = gd(m, 44);
	if (k1 == 0) {
		if (k2 == 0) {
			if (s1 != s2) { fail(m); }
			w = 0;
			if (s1 == 8) { w = 1; }
			rr = 0;
			if (r2 > 7) { rr = 1; }
			bb = 0;
			if (r1 > 7) { bb = 1; }
			rex(m, w, rr, 0*2+bb);
			op = base + 1;
			if (s1 == 1) { op = base; }
			ex(m, op);
			modrm(m, 3, r2, r1);
			return 0;
		}
		if (k2 == 2) {
			if (s1 == 1) {
				rex(m, 0, 0, 0*2+0);
				ex(m, 128);
				modrm(m, 3, digit, r1);
				ex(m, v2 % 256);
				return 0;
			}
			w = 0;
			if (s1 == 8) { w = 1; }
			bb = 0;
			if (r1 > 7) { bb = 1; }
			t = v2 + 128;
			if (t < 0) { t = 9999; }
			if (t < 256) {
				rex(m, w, 0, 0*2+bb);
				ex(m, 131);
				modrm(m, 3, digit, r1);
				ex(m, v2 % 256);
			}
			else {
				rex(m, w, 0, 0*2+bb);
				ex(m, 129);
				modrm(m, 3, digit, r1);
				ex4(m, v2);
			}
			return 0;
		}
		if (k2 == 1) {
			w = 0;
			if (s1 == 8) { w = 1; }
			rr = 0;
			if (r1 > 7) { rr = 1; }
			bb = 0;
			if (gb(m, 48) > 7) { bb = 1; }
			rex(m, w, rr, 0*2+bb);
			op = base + 3;
			if (s1 == 1) { op = base + 2; }
			ex(m, op);
			emitmem(m, 40, r1);
			return 0;
		}
	}
	if (k1 == 1) {
		if (k2 == 0) {
			w = 0;
			if (s2 == 8) { w = 1; }
			bb = 0;
			if (gb(m, 32) > 7) { bb = 1; }
			rex(m, w, 0, 0*2+bb);
			op = base + 1;
			if (s2 == 1) { op = base; }
			ex(m, op);
			emitmem(m, 24, r2);
			return 0;
		}
		if (k2 == 2) {
			s = s1;
			if (s == 0) { s = 4; }
			w = 0;
			if (s == 8) { w = 1; }
			bb = 0;
			if (gb(m, 32) > 7) { bb = 1; }
			if (s == 1) {
				rex(m, 0, 0, 0*2+bb);
				ex(m, 128);
				emitmem(m, 24, digit);
				ex(m, v2 % 256);
				return 0;
			}
			t = v2 + 128;
			if (t < 0) { t = 9999; }
			rex(m, w, 0, 0*2+bb);
			if (t < 256) {
				ex(m, 131);
				emitmem(m, 24, digit);
				ex(m, v2 % 256);
			}
			else {
				ex(m, 129);
				emitmem(m, 24, digit);
				ex4(m, v2);
			}
			return 0;
		}
	}
	fail(m);
	return 0;
}

int enc_mov(int m)
{
	int w = 0;
	int rr = 0;
	int bb = 0;
	int t = 0;
	int op = 0;
	int s = 0;
	int k1 = gb(m, 24);
	int k2 = gb(m, 40);
	int s1 = gb(m, 25);
	int s2 = gb(m, 41);
	int r1 = gb(m, 26);
	int r2 = gb(m, 42);
	int v2 = gd(m, 44);
	if (k1 == 0) {
		if (k2 == 2) {
			if (s1 == 1) {
				rex(m, 0, 0, 0*2+0);
				ex(m, 176 + r1 % 8);
				ex(m, v2 % 256);
				return 0;
			}
			if (s1 == 4) {
				bb = 0;
				if (r1 > 7) { bb = 1; }
				rex(m, 0, 0, 0*2+bb);
				ex(m, 184 + r1 % 8);
				ex4(m, v2);
				return 0;
			}
			bb = 0;
			if (r1 > 7) { bb = 1; }
			rex(m, 1, 0, 0*2+bb);
			ex(m, 199);
			modrm(m, 3, 0, r1);
			ex4(m, v2);
			return 0;
		}
		if (k2 == 0) {
			if (s1 != s2) { fail(m); }
			w = 0;
			if (s1 == 8) { w = 1; }
			rr = 0;
			if (r2 > 7) { rr = 1; }
			bb = 0;
			if (r1 > 7) { bb = 1; }
			rex(m, w, rr, 0*2+bb);
			op = 137;
			if (s1 == 1) { op = 136; }
			ex(m, op);
			modrm(m, 3, r2, r1);
			return 0;
		}
		if (k2 == 1) {
			w = 0;
			if (s1 == 8) { w = 1; }
			rr = 0;
			if (r1 > 7) { rr = 1; }
			bb = 0;
			if (gb(m, 48) > 7) { bb = 1; }
			rex(m, w, rr, 0*2+bb);
			op = 139;
			if (s1 == 1) { op = 138; }
			ex(m, op);
			emitmem(m, 40, r1);
			return 0;
		}
	}
	if (k1 == 1) {
		if (k2 == 0) {
			s = s1;
			w = 0;
			if (s2 == 8) { w = 1; }
			if (s == 0) { s = s2; }
			if (s2 == 8) { w = 1; }
			bb = 0;
			if (gb(m, 32) > 7) { bb = 1; }
			rex(m, w, 0, 0*2+bb);
			op = 137;
			if (s2 == 1) { op = 136; }
			ex(m, op);
			emitmem(m, 24, r2);
			return 0;
		}
		if (k2 == 2) {
			s = s1;
			if (s == 0) { s = 4; }
			bb = 0;
			if (gb(m, 32) > 7) { bb = 1; }
			if (s == 1) {
				rex(m, 0, 0, 0*2+bb);
				ex(m, 198);
				emitmem(m, 24, 0);
				ex(m, v2 % 256);
				return 0;
			}
			w = 0;
			if (s == 8) { w = 1; }
			rex(m, w, 0, 0*2+bb);
			ex(m, 199);
			emitmem(m, 24, 0);
			ex4(m, v2);
			return 0;
		}
	}
	fail(m);
	return 0;
}

int enc_un(int m, int digit)
{
	int w = 0;
	int bb = 0;
	int k = gb(m, 24);
	int s = gb(m, 25);
	int r = gb(m, 26);
	if (k == 0) {
		w = 0;
		if (s == 8) { w = 1; }
		bb = 0;
		if (r > 7) { bb = 1; }
		rex(m, w, 0, 0*2+bb);
		if (s == 1) { ex(m, 246); }
		else { ex(m, 247); }
		modrm(m, 3, digit, r);
		return 0;
	}
	if (k == 1) {
		int s2 = s;
		if (s2 == 0) { s2 = 4; }
		w = 0;
		if (s2 == 8) { w = 1; }
		bb = 0;
		if (gb(m, 32) > 7) { bb = 1; }
		rex(m, w, 0, 0*2+bb);
		if (s2 == 1) { ex(m, 246); }
		else { ex(m, 247); }
		emitmem(m, 24, digit);
		return 0;
	}
	fail(m);
	return 0;
}

int enc_shift(int m, int digit)
{
	int k = gb(m, 24);
	int s = gb(m, 25);
	int r = gb(m, 26);
	int k2 = gb(m, 40);
	int r2 = gb(m, 42);
	int v2 = gd(m, 44);
	if (k != 0) { fail(m); }
	int w = 0;
	if (s == 8) { w = 1; }
	int bb = 0;
	if (r > 7) { bb = 1; }
	if (k2 == 2) {
		rex(m, w, 0, 0*2+bb);
		if (s == 1) { ex(m, 192); }
		else { ex(m, 193); }
		modrm(m, 3, digit, r);
		ex(m, v2 % 256);
		return 0;
	}
	if (k2 == 0) {
		if (r2 != 1) { fail(m); }
		rex(m, w, 0, 0*2+bb);
		if (s == 1) { ex(m, 210); }
		else { ex(m, 211); }
		modrm(m, 3, digit, r);
		return 0;
	}
	fail(m);
	return 0;
}

int enc_movzx(int m)
{
	int s1 = gb(m, 25);
	int s2 = gb(m, 41);
	int r1 = gb(m, 26);
	int k2 = gb(m, 40);
	int r2 = gb(m, 42);
	int w = 0;
	if (s1 == 8) { w = 1; }
	int rr = 0;
	if (r1 > 7) { rr = 1; }
	if (k2 == 0) {
		if (s2 != 1) { fail(m); }
		rex(m, w, rr, 0*2+0);
		ex(m, 15);
		ex(m, 182);
		modrm(m, 3, r1, r2);
		return 0;
	}
	if (k2 == 1) {
		if (s2 != 1) { fail(m); }
		int bb = 0;
		if (gb(m, 48) > 7) { bb = 1; }
		rex(m, w, rr, 0*2+bb);
		ex(m, 15);
		ex(m, 182);
		emitmem(m, 40, r1);
		return 0;
	}
	fail(m);
	return 0;
}

int enc_lea(int m)
{
	int s1 = gb(m, 25);
	int r1 = gb(m, 26);
	int w = 0;
	if (s1 == 8) { w = 1; }
	int rr = 0;
	if (r1 > 7) { rr = 1; }
	int bb = 0;
	if (gb(m, 32) > 7) { bb = 1; }
	rex(m, w, rr, 0*2+bb);
	ex(m, 141);
	emitmem(m, 40, r1);
	return 0;
}

int enc_pushpop(int m, int pop)
{
	int k = gb(m, 24);
	int r = gb(m, 26);
	if (k != 0) { fail(m); }
	int bb = 0;
	if (r > 7) { bb = 1; }
	rex(m, 0, 0, 0*2+bb);
	if (pop != 0) { ex(m, 88 + r % 8); }
	else { ex(m, 80 + r % 8); }
	return 0;
}

int reloc(int m)
{
	int k = gb(m, 24);
	if (k != 2) { fail(m); }
	return gd(m, 28);
}

int enc_jmp(int m, int cc, int lng)
{
	int t = reloc(m);
	int at = gd(m, 9);
	int rel = t - at - 2;
	if (lng == 0) {
		int r8 = t - at - 2;
		int q = r8 + 128;
		if (q < 0) { lng = 1; }
		else {
			if (q < 256) {
				if (cc == 0) { ex(m, 235); }
				else { ex(m, 112 + cc); }
				ex(m, r8 % 256);
				return 0;
			}
			lng = 1;
		}
	}
	rel = t - at - 5;
	if (cc == 0) { ex(m, 233); }
	else {
		rel = t - at - 6;
		ex(m, 15);
		ex(m, 128 + cc);
	}
	ex4(m, rel);
	return 0;
}

int enc_call(int m)
{
	int t = reloc(m);
	int at = gd(m, 9);
	int rel = t - at - 5;
	ex(m, 232);
	ex4(m, rel);
	return 0;
}

/* ---- header ---- */
int header(int m, int filesz, int entry)
{
	int base = 64 * 65535 + 64;
	ex(m, 127);
	ex(m, 69);
	ex(m, 76);
	ex(m, 70);
	ex(m, 2);
	ex(m, 1);
	ex(m, 1);
	ex(m, 0);
	int i = 0;
	while (i < 8) { ex(m, 0); i = i + 1; }
	ex(m, 2);
	ex(m, 0);
	ex(m, 62);
	ex(m, 0);
	ex4(m, 1);
	ex8(m, base + 120 + entry);
	ex8(m, 64);
	ex8(m, 0);
	ex4(m, 0);
	ex(m, 64);
	ex(m, 0);
	ex(m, 56);
	ex(m, 0);
	ex(m, 1);
	ex(m, 0);
	ex(m, 0);
	ex(m, 0);
	ex(m, 0);
	ex(m, 0);
	ex(m, 0);
	ex(m, 0);
	ex4(m, 1);
	ex4(m, 5);
	ex8(m, 0);
	ex8(m, base);
	ex8(m, base);
	ex8(m, filesz);
	ex8(m, filesz);
	ex8(m, 4096);
	return 0;
}

/* ---- parse ---- */
int dbstr(int m)
{
	adv(m, 1);
	int go = 1;
	while (go != 0) {
		int c = gcur(m);
		if (c == 34) {
			adv(m, 1);
			go = 0;
		}
		else {
			if (c == 92) {
				adv(m, 1);
				c = gcur(m);
				if (c == 110) { ex(m, 10); }
				else {
					if (c == 116) { ex(m, 9); }
					else { ex(m, c); }
				}
				adv(m, 1);
			}
			else {
				ex(m, c);
				adv(m, 1);
			}
		}
	}
	return 0;
}

int pdb(int m)
{
	skipsp(m);
	if (gcur(m) == 34) { return dbstr(m); }
	int v = expr(m);
	int t = v + 128;
	if (t < 0) { fail(m); }
	if (t < 384) { ex(m, v % 256); }
	else { fail(m); }
	return 0;
}

int opcode(int m)
{
	int op = 0;
	if (same(m, "syscall")) { op = 1; }
	if (same(m, "ret")) { op = 2; }
	if (same(m, "mov")) { op = 3; }
	if (same(m, "add")) { op = 4; }
	if (same(m, "or")) { op = 5; }
	if (same(m, "and")) { op = 6; }
	if (same(m, "sub")) { op = 7; }
	if (same(m, "xor")) { op = 8; }
	if (same(m, "cmp")) { op = 9; }
	if (same(m, "test")) { op = 10; }
	if (same(m, "inc")) { op = 11; }
	if (same(m, "dec")) { op = 12; }
	if (same(m, "not")) { op = 13; }
	if (same(m, "neg")) { op = 14; }
	if (same(m, "div")) { op = 15; }
	if (same(m, "shl")) { op = 16; }
	if (same(m, "shr")) { op = 17; }
	if (same(m, "sar")) { op = 18; }
	if (same(m, "movzx")) { op = 19; }
	if (same(m, "lea")) { op = 20; }
	if (same(m, "push")) { op = 21; }
	if (same(m, "pop")) { op = 22; }
	if (same(m, "call")) { op = 23; }
	if (same(m, "jmp")) { op = 24; }
	if (same(m, "jmp.l")) { op = 25; }
	if (same(m, "jz")) { op = 26; }
	if (same(m, "jz.l")) { op = 27; }
	if (same(m, "jnz")) { op = 28; }
	if (same(m, "jnz.l")) { op = 29; }
	if (same(m, "jb")) { op = 30; }
	if (same(m, "jb.l")) { op = 31; }
	if (same(m, "db")) { op = 32; }
	if (same(m, "space")) { op = 33; }
	if (same(m, "entry")) { op = 34; }
	return op;
}

int two(int m)
{
	parseop(m, 24);
	skipsp(m);
	if (gcur(m) == 44) {
		adv(m, 1);
		parseop(m, 40);
	}
	return 0;
}

int one(int m)
{
	parseop(m, 24);
	return 0;
}

int parse(int m)
{
	int done = 0;
	while (done == 0) {
		skipsp(m);
		int c0 = gcur(m);
		if (c0 == 0) { done = 1; }
		else {
			if (eol(m) != 0) { }
			else {
				int c = gcur(m);
			if (c == 0) { done = 1; }
			else {
				int s = gd(m, 0);
				int t = s;
				int isl = 0;
				int go = 1;
				while (go != 0) {
					int ch = m[t];
					if (ch == 58) { isl = 1; go = 0; }
					else {
						int dl = 0;
						if (ch == 32) { dl = 1; }
						if (ch == 9) { dl = 1; }
						if (ch == 10) { dl = 1; }
						if (ch == 59) { dl = 1; }
						if (ch == 0) { dl = 1; }
						if (dl != 0) { go = 0; }
						else { t = t + 1; }
					}
				}
				if (isl != 0) {
					word(m);
					if (gcur(m) != 58) { fail(m); }
					adv(m, 1);
					if (gb(m, 8) == 0) { ldef(m); }
				}
				else {
					word(m);
					int op = opcode(m);
					if (op == 0) { fail(m); }
					if (op == 1) { ex(m, 15); ex(m, 5); }
					if (op == 2) { ex(m, 195); }
					if (op == 3) { two(m); enc_mov(m); }
					if (op == 4) { two(m); enc_alu(m, 0); }
					if (op == 5) { two(m); enc_alu(m, 8); }
					if (op == 6) { two(m); enc_alu(m, 32); }
					if (op == 7) { two(m); enc_alu(m, 40); }
					if (op == 8) { two(m); enc_alu(m, 48); }
					if (op == 9) { two(m); enc_alu(m, 56); }
					if (op == 10) { two(m); enc_alu(m, 64); }
					if (op == 11) { one(m); enc_un(m, 0); }
					if (op == 12) { one(m); enc_un(m, 1); }
					if (op == 13) { one(m); enc_un(m, 2); }
					if (op == 14) { one(m); enc_un(m, 3); }
					if (op == 15) { one(m); enc_un(m, 6); }
					if (op == 16) { two(m); enc_shift(m, 4); }
					if (op == 17) { two(m); enc_shift(m, 5); }
					if (op == 18) { two(m); enc_shift(m, 7); }
					if (op == 19) { two(m); enc_movzx(m); }
					if (op == 20) { two(m); enc_lea(m); }
					if (op == 21) { one(m); enc_pushpop(m, 0); }
					if (op == 22) { one(m); enc_pushpop(m, 1); }
					if (op == 23) { one(m); enc_call(m); }
					if (op == 24) { one(m); enc_jmp(m, 0, 0); }
					if (op == 25) { one(m); enc_jmp(m, 0, 1); }
					if (op == 26) { one(m); enc_jmp(m, 4, 0); }
					if (op == 27) { one(m); enc_jmp(m, 4, 1); }
					if (op == 28) { one(m); enc_jmp(m, 5, 0); }
					if (op == 29) { one(m); enc_jmp(m, 5, 1); }
					if (op == 30) { one(m); enc_jmp(m, 2, 0); }
					if (op == 31) { one(m); enc_jmp(m, 2, 1); }
					if (op == 32) {
						pdb(m);
						int g = 1;
						while (g != 0) {
							skipsp(m);
							if (gcur(m) == 44) { adv(m, 1); pdb(m); }
							else { g = 0; }
						}
					}
					if (op == 33) {
						int n = expr(m);
						int i = 0;
						while (i < n) { ex(m, 0); i = i + 1; }
					}
					if (op == 34) {
						int e = expr(m);
						pd(m, 15, e);
						pb(m, 19, 1);
					}
				}
			}
		}
	}
	}
	return 0;
}
int main(void)
{
	char mem[31000];
	int m = &mem;
	int n = read(mem, 20000);
	if (n <= 0) {
		int z = exit(1);
	}
	if (n >= 20000) {
		int z2 = exit(1);
	}
	pd(m, 61, n);
	pd(m, 0, 0);
	pd(m, 4, 1);
	pd(m, 9, 0);
	pw(m, 13, 0);
	pd(m, 15, 0);
	pb(m, 19, 0);
	pb(m, 8, 0);
	parse(m);
	pd(m, 0, 0);
	pd(m, 4, 1);
	pd(m, 9, 0);
	pb(m, 8, 1);
	parse(m);
	int fs = 120 + gd(m, 9);
	pd(m, 20, fs);
	pd(m, 0, 0);
	pd(m, 4, 1);
	pd(m, 9, 0);
	pb(m, 8, 2);
	int ev = gd(m, 15);
	header(m, fs, ev);
	parse(m);
	return 0;
}
