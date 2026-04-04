#include <stdio.h>

int main(void) {
    int a[] = {1, 2, 3, 4};
    int b[] = {5, 6, 7, 8};
    int n = 4;
    int sum = 0;

    for (int i = 0; i < n; i++) {
        sum = sum + (a[i] * b[i]);
    }

    return sum;
}
