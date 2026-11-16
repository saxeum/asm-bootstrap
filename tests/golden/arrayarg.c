int f(int v) { return v + 1; }
int main(void)
{
	int a[3];
	int i = 1;
	a[i] = 41;
	return f(a[i]);
}
