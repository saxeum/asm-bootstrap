int main(void)
{
	char b[100];
	int n = read(b, 100);
	while (n > 0) {
		int i = 0;
		while (i < n) {
			int c = b[i];
			if (c == 97) { b[i] = 65; }
			if (c == 98) { b[i] = 66; }
			i = i + 1;
		}
		int k = write(b, n);
		n = read(b, 100);
	}
	return 0;
}
