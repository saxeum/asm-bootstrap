int putn(int n, int p)
{
	int len = 0;
	int m = n;
	int d = 0;
	if (m == 0) { p[0] = 48; return 1; }
	while (m > 0) {
		d = m / 10;
		p[len] = 48 + (m - d * 10);
		len = len + 1;
		m = d;
	}
	int i = 0;
	int j = len - 1;
	while (i < j) {
		int t = p[i];
		p[i] = p[j];
		p[j] = t;
		i = i + 1;
		j = j - 1;
	}
	return len;
}
int main(void)
{
	char out[20];
	int l = putn(1234, &out);
	int k = write(out, l);
	out[0] = 10;
	int k2 = write(out, 1);
	return 0;
}
