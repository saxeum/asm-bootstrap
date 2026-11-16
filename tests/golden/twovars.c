int main(void)
{
	int a = 0;
	int b = 5;
	while (a < 3) {
		write(".");
		a = a + 1;
		b = b - 1;
	}
	if (b == 2) { write("!"); } else { write("?"); }
	return 0;
}
