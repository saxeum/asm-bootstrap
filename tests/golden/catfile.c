int main(void)
{
	char b[100];
	int n = read(b, 100);
	while (n > 0) {
		int k = write(b, n);
		n = read(b, 100);
	}
	return 0;
}
