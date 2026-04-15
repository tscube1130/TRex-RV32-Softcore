#ifndef DINO_DISPLAY_H
#define DINO_DISPLAY_H

#include "dino_mmio.h"

/*
 * 7-SEGMENT DISPLAY ENCODING
 * ===========================
 * Nibble values (4-bit) for each character on 8-digit 7-segment display:
 *
 * Score digits:
 *   0x0-0x9 → decimal digits 0-9
 *
 * Game characters:
 *   0xA → BLANK        (empty track position)
 *   0xB → DINO GROUND  (player standing: "||" shape)
 *   0xC → DINO AIR     (player jumping: "⊓" bracket shape)
 *   0xD → CACTUS       (obstacle: T-shaped)
 *   0xE, 0xF → BLANK  (spare)
 */

static unsigned int pack_bcd_digits(unsigned int value, unsigned int first_digit)
{
    unsigned int packed_digits = 0u;
    unsigned int digit_index = 0u;
    unsigned int digit = 0u;

    while (first_digit > 0u)
    {
        value = value / 10u;
        first_digit = first_digit - 1u;
    }

    while (digit_index < 4u)
    {
        digit = value % 10u;
        packed_digits = packed_digits | (digit << (digit_index * 4u));
        value = value / 10u;
        digit_index = digit_index + 1u;
    }

    return packed_digits;
}

/*
 * render_game_display() — Main game rendering function
 *
 * Renders game state across all 8 digits of 7-segment display.
 *
 * Parameters:
 *   player_state   : 0=GROUNDED, 1=JUMPING
 *   obstacle_x     : obstacle horizontal position (0-16+)
 *   obstacle_type  : 0=NONE, 1=CACTUS_SINGLE, 2=CACTUS_PAIR
 *   score          : current score (0-99999999)
 *   show_score     : if non-zero, display score in low digits
 *
 * Display layout:
 *   Digit 7: DINO (leftmost, player position)
 *   Digits 6-4: Game area (cactus moves here)
 *   Digits 3-0: Score (BCD encoded)
 */
static void render_game_display(unsigned int player_state,
                                unsigned int obstacle_x,
                                unsigned int obstacle_type,
                                unsigned int score,
                                unsigned int show_score)
{
    unsigned int seg_data0 = 0u; /* Digits 3, 2, 1, 0 */
    unsigned int seg_data1 = 0u; /* Digits 7, 6, 5, 4 */
    unsigned int dino_char, cactus_digit;

    /* Dino character selection: 0xB=ground, 0xC=air */
    dino_char = (player_state == 0u) ? 0xBu : 0xCu;

    /* Place DINO at digit 7 (leftmost position) */
    seg_data1 |= (dino_char << 12); /* Digit 7 = bits[15:12] of seg_data1 */

    /* Place CACTUS based on position */
    if (obstacle_type != 0u)
    { /* obstacle_type != NONE */
        /* Map obstacle_x (0-16+) to digit position (6 down to 4) */
        cactus_digit = 6u - (obstacle_x / 3u);

        if (cactus_digit >= 4u && cactus_digit <= 6u)
        {
            /* Cactus fits in digits 6-4 (seg_data1) */
            seg_data1 |= (0xDu << ((cactus_digit - 4u) * 4u));

            /* For PAIR cactus, place second cactus one digit to the left */
            if (obstacle_type == 2u && cactus_digit > 4u)
            {
                seg_data1 |= (0xDu << ((cactus_digit - 4u - 1u) * 4u));
            }
        }
    }

    /* Fill unused digits with BLANK (0xA) */
    if ((seg_data1 & 0x00000F00u) == 0u)
        seg_data1 |= (0xAu << 8); /* Digit 6 */
    if ((seg_data1 & 0x000000F0u) == 0u)
        seg_data1 |= (0xAu << 4); /* Digit 5 */
    if ((seg_data1 & 0x0000000Fu) == 0u)
        seg_data1 |= (0xAu << 0); /* Digit 4 */

    /* Score display (digits 3-0) */
    if (show_score != 0u)
    {
        seg_data0 = pack_bcd_digits(score, 0u);
    }
    else
    {
        /* All blanks if not showing score */
        seg_data0 = 0xAAAAAAAAu;
    }

    /* Write to hardware */
    write_score_digits_low(seg_data0);
    write_score_digits_high(seg_data1);
}

#endif
