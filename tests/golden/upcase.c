int main(void)
{
	char b[100];
	int n = read(b, 100);
	while (n > 0) {
		int i = 0;
		while (i < n) {
			if (b[i] == 97) { b[i] = 65; }
			if (b[i] == 98) { b[i] = 66; }
			i = i + 1;
		}
		int k = write(b, n);
		n = read(b, 100);
	}
	return 0;
}
