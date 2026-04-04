#include <stdio.h>

int main(void) {
    int checksum = 0;
    int x = 13;
    int y = -7;

    for (int i = 0; i < 40; i++) {
        if ((i & 1) == 0) {
            checksum += i;
        } else {
            checksum -= i;
        }

        if (x > y) {
            if ((x - y) > 10) {
                checksum ^= (x + i);
            } else {
                checksum ^= (y - i);
            }
        } else if (x == y) {
            checksum += 111;
        } else {
            checksum -= 111;
        }

        switch (i % 5) {
            case 0:
                checksum += (x & 3);
                break;
            case 1:
                checksum -= (y & 3);
                break;
            case 2:
                checksum ^= (x ^ y);
                break;
            case 3:
                checksum += (i * 2);
                break;
            default:
                checksum -= (i / 2);
                break;
        }

        if (i == 9 || i == 21) {
            continue;
        }

        if (i == 33) {
            break;
        }

        if ((checksum & 1) == 0) {
            x = x + 3;
        } else {
            y = y - 2;
        }
    }

    return checksum;
}
