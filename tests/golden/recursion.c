int f(int n, int acc)
{
	if (n == 0) { return acc; }
	return f(n - 1, acc + 1);
}
int main(void) { return f(10, 0); }
