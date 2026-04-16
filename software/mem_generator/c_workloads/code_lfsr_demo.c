/*
 * LFSR Demo Workload for CS224 RISC-V Pipeline
 * ============================================
 *
 * Demonstrates:
 * 1. Random cactus spawning using LFSR (Linear Feedback Shift Register)
 * 2. Dino fixed at leftmost position (digit 7)
 * 3. Cactus approaching from right to left
 * 4. Score incrementing over time
 *
 * No jump logic or collision detection - pure animation demo
 */

#include "dino_display.h"

#define FRAME_DELAY_CYCLES 50000u
#define SPAWN_CHECK_FRAMES 6u
#define SPAWN_CHANCE_MASK 0x3u /* 1 in 4 chance each check */
#define OBSTACLE_START_X 16u   /* Cactus starts far right */
#define SCORE_TICK_FRAMES 4u
#define CACTUS_NONE 0u
#define CACTUS_SINGLE 1u
#define CACTUS_PAIR 2u

static volatile unsigned int demo_debug_sink;

static void wait_for_next_frame(void)
{
    volatile unsigned int delay;

    for (delay = 0u; delay < FRAME_DELAY_CYCLES; delay = delay + 1u)
    {
        /* Busy-wait frame timer for the simple bare-metal game loop. */
    }
}

int main(void)
{
    unsigned int frame_count = 0u;
    unsigned int spawn_check_timer = SPAWN_CHECK_FRAMES;
    unsigned int random_value = 0u;
    unsigned int obstacle_active = 0u;
    unsigned int obstacle_type = CACTUS_NONE;
    unsigned int obstacle_x = 0u;
    unsigned int score = 0u;
    unsigned int score_tick_timer = SCORE_TICK_FRAMES;

    for (;;)
    {
        wait_for_next_frame();

        frame_count = frame_count + 1u;

        /* ================================================================
         * SPAWN LOGIC: Use LFSR to randomly spawn cactus
         * ================================================================ */
        if (spawn_check_timer > 0u)
        {
            spawn_check_timer = spawn_check_timer - 1u;
        }
        else
        {
            spawn_check_timer = SPAWN_CHECK_FRAMES;

            /* Check if we should spawn a new obstacle */
            if (obstacle_active == 0u)
            {
                /* Read LFSR from MMIO_LFSR_R (0x2008) */
                random_value = read_lfsr();

                /* 1 in 4 chance to spawn (SPAWN_CHANCE_MASK = 0x3) */
                if ((random_value & SPAWN_CHANCE_MASK) == 0u)
                {
                    obstacle_active = 1u;
                    /* Use bit[0] of LFSR: 0=single cactus, 1=pair */
                    obstacle_type = (random_value & 0x1u) ? CACTUS_PAIR : CACTUS_SINGLE;
                    /* Start cactus at far right */
                    obstacle_x = OBSTACLE_START_X;
                }
            }
        }

        /* ================================================================
         * MOVEMENT LOGIC: Cactus moves left toward dino
         * ================================================================ */
        if (obstacle_active != 0u)
        {
            if (obstacle_x > 0u)
            {
                /* Move cactus one position left each frame */
                obstacle_x = obstacle_x - 1u;
            }
            else
            {
                /* Cactus exits left side, remove it */
                obstacle_active = 0u;
                obstacle_type = CACTUS_NONE;
            }
        }

        /* ================================================================
         * SCORE LOGIC: Increment score over time
         * ================================================================ */
        if (score_tick_timer > 0u)
        {
            score_tick_timer = score_tick_timer - 1u;
        }
        else
        {
            score_tick_timer = SCORE_TICK_FRAMES;
            /* Increment score */
            if (score < 99999999u)
            {
                score = score + 1u;
            }
            else
            {
                score = 0u;
            }
        }

        /* ================================================================
         * RENDERING: Display game state on 7-segment
         * ================================================================
         *
         * Layout:
         *   Digit 7 (leftmost): DINO (fixed at 0xB = ground position)
         *   Digit 6-4: Game area (cactus moving from right)
         *   Digit 3-0: Score (BCD, incrementing)
         *
         * Example display:
         *   [DINO][BLANK][BLANK][CACTUS][Score digits]
         *    Dig7  Dig6   Dig5   Dig4   Dig3-0
         */
        render_game_display(
            0u,                                   /* player_state: 0=always grounded */
            obstacle_x,                           /* obstacle_x: position (0-16) */
            obstacle_active ? obstacle_type : 0u, /* obstacle_type: NONE/SINGLE/PAIR */
            score,                                /* current score (0-99999999) */
            1u                                    /* show_score: true */
        );

        /* Debug sink: combine all state for waveform inspection */
        demo_debug_sink = frame_count + obstacle_active + obstacle_type + obstacle_x + score;
    }
}
