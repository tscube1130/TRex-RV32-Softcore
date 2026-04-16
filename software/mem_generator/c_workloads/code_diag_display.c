//////////////////////////////////////////////////////////////
// DIAGNOSTIC TEST: Simple counter on 7-segment display
// Tests: clock divider, display output, MMIO writing
//////////////////////////////////////////////////////////////

#include <stdint.h>

// MMIO addresses
#define MMIO_SEG_LOW ((volatile uint32_t *)0x2010)
#define MMIO_SEG_HIGH ((volatile uint32_t *)0x2014)

// Display constants
#define BLANK 0xA

void delay(uint32_t iterations)
{
    for (uint32_t i = 0; i < iterations; i++)
    {
        asm("nop");
    }
}

int main(void)
{
    uint32_t counter = 0;

    for (;;)
    {
        // Write counter to display (only use  rightmost 4 digits)
        // Digits: 7 6 | 5 4 | 3 2 | 1 0
        // Pack: [7][6] into high, [5][4] into mid, etc.

        uint32_t d0 = counter % 10;          // ones
        uint32_t d1 = (counter / 10) % 10;   // tens
        uint32_t d2 = (counter / 100) % 10;  // hundreds
        uint32_t d3 = (counter / 1000) % 10; // thousands

        // [d1][d0] → SEG_LOW[7:0]
        uint32_t seg_low = (d1 << 4) | d0;

        // [d3][d2] → SEG_HIGH[7:0]
        uint32_t seg_high = (d3 << 4) | d2;

        *MMIO_SEG_LOW = seg_low;
        *MMIO_SEG_HIGH = seg_high;

        // Increment every ~100 cycles (fast visible update)
        delay(100);
        counter++;

        // Roll over at 10000
        if (counter >= 10000)
        {
            counter = 0;
        }
    }

    return 0;
}
