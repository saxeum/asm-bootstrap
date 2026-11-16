int a(int n) { int i = 0; while (i < n) { i = i + 1; } return i; }
int b(int n) { int i = 0; while (i < n) { i = i + 2; } return i; }
int main(void) { int x = a(3); int y = b(2); return x + y; }
