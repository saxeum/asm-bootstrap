int fill(int n)
{
	char b[900];
	int i = 0;
	while (i < 900) {
		b[i] = 65;
		i = i + 1;
	}
	return b[899] + n;
}

int main(void)
{
	int x = 7;
	int y = fill(0);
	return x + y;
}
