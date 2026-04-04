#include <stdio.h>
#include <limits.h>

int main(void) {
    int numerators[] = {100, -100, 100, -100, 0, 5, INT_MIN, INT_MIN};
    int denominators[] = {7, 7, -7, -7, 5, 0, -1, 1};
    int n = 8;

    int checksum = 0;

    for (int i = 0; i < n; i++) {
        int a = numerators[i];
        int b = denominators[i];
        int q;
        int r;

        if (b == 0) {
            q = 0;
            r = a;
            checksum ^= 0x5A5A;
        } else if (a == INT_MIN && b == -1) {
            q = INT_MIN;
            r = 0;
            checksum ^= 0xA5A5;
        } else {
            q = a / b;
            r = a % b;
        }

        checksum = checksum + (q ^ r) + (i * 17);
    }

    return checksum;
}
