int main(void)
{
	int x = 7;
	int p = &x;
	int y = *p;
	*p = 33;
	return x + y;
}
