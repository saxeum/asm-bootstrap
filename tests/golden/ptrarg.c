int bump(int p)
{
	*p = *p + 1;
	return 0;
}
int main(void)
{
	int x = 41;
	bump(&x);
	return x;
}
