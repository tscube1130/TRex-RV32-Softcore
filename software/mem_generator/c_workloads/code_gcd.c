#include <stdio.h>

int main(void) {
    int a = 48;
    int b = 18;

    while (b != 0) {
        int r = a % b;
        a = b;
        b = r;
    }

    return a;
}
