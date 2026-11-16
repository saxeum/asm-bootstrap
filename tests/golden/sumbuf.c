int sumbuf(int p, int n)
{
	int t = 0;
	int i = 0;
	while (i < n) {
		t = t + p[i];
		i = i + 1;
	}
	return t;
}
int main(void)
{
	char s[4];
	s[0] = 65;
	s[1] = 66;
	s[2] = 67;
	return sumbuf(&s, 3);
}
