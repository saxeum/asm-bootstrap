int main(void)
{
	int x = 0;
	while (x < 5) {
		if (x == 2) { write("-"); } else { write("."); }
		x = x + 1;
	}
	return 0;
}
