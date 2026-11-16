int main(void)
{
	char b[100];
	int n = read(b, 100);
	while (n > 0) {
		int i = 0;
		while (i < n) {
			if (b[i] == 'a') { b[i] = 'A'; }
			if (b[i] == 'b') { b[i] = 'B'; }
			i = i + 1;
		}
		int k = write(b, n);
		n = read(b, 100);
	}
	return 0;
}
