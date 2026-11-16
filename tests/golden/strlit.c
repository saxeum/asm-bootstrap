int f(int p, int l, int s)
{
	int i = 0;
	while (s[i] != 0) {
		p[l] = s[i];
		l = l + 1;
		i = i + 1;
	}
	return l;
}
int main(void)
{
	char b[8];
	int l = f(&b, 0, "hi");
	return l;
}
