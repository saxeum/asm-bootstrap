int ll(int p, int len, int s) { int i = 0; while (s[i] != 0) { p[len] = s[i]; len = len + 1; i = i + 1; } return len; }
int main(void) { char b[64]; int t[2]; t[0] = "ab"; t[1] = "cd"; int p = &b; int len = 0; int i = 0; while (i < 2) { len = ll(p, len, t[i]); i = i + 1; } int k = write(b, len); return 0; }
