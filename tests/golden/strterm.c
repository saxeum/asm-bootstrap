int es(int p, int l, int s) { int i = 0; while (s[i] != 0) { p[l] = s[i]; l = l + 1; i = i + 1; } return l; }
int ec(int p, int l) { p[l] = 10; return l + 1; }
int line(int p, int l, int s) { l = es(p, l, s); l = ec(p, l); return l; }
int main(void)
{
	char b[8000];
	int p = &b;
	int l = 0;
	l = line(p, l, "ab");
	l = line(p, l, "cd");
	int k = write(b, l);
	return 0;
}
