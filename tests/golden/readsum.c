int main(void)
{
	char buf[8];
	int total = 0;
	int n = read(buf, 8);
	while (n > 0) {
		int i = 0;
		while (n > 0) {
			total = total + buf[i];
			i = i + 1;
			n = n - 1;
		}
		n = read(buf, 8);
	}
	return total % 251;
}
