#include <stdio.h>

int main(void) {
    int n = 7;      // We will calculate the 7th Fibonacci number
    int a = 0;
    int b = 1;
    int c = 0;
    // base cases
    if (n == 0) return a;
    if (n == 1) return b;
    for (int i = 2; i <= n; i++) {
        c = a + b;
        a = b;
        b = c;
    }
    return c; 
}

// #include <stdio.h>

// // Recursive function to find the nth Fibonacci number
// int fibonacci(int n) {
//     if (n <= 1) 
//         return n;
//     return fibonacci(n - 1) + fibonacci(n - 2);
// }

// int main(void) {
//     int result = fibonacci(7);
//     return result;
// }
// doesn't work well
// For the custom workload, a recursive Fibonacci program was compiled and executed. However, the program failed to complete
// because the pipeline lacks hazard detection and stalling logic. When the recursive function attempted to return, the lw ra, 
// offset(sp) instruction suffered a load-use hazard with the immediately following jalr ra instruction. Because the return 
// address was not forwarded in time, the jalr instruction read a stale 0 from the register file, causing the Program Counter 
// to incorrectly jump back to 0x00000000 and restart the program indefinitely.