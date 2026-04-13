#ifndef DINO_DISPLAY_H
#define DINO_DISPLAY_H

#include "dino_mmio.h"

static unsigned int pack_bcd_digits(unsigned int value, unsigned int first_digit)
{
    unsigned int packed_digits = 0u;
    unsigned int digit_index = 0u;
    unsigned int digit = 0u;

    while (first_digit > 0u) {
        value = value / 10u;
        first_digit = first_digit - 1u;
    }

    while (digit_index < 4u) {
        digit = value % 10u;
        packed_digits = packed_digits | (digit << (digit_index * 4u));
        value = value / 10u;
        digit_index = digit_index + 1u;
    }

    return packed_digits;
}

static void write_score(unsigned int score)
{
    write_score_digits_low(pack_bcd_digits(score, 0u));
    write_score_digits_high(pack_bcd_digits(score, 4u));
}

#endif
