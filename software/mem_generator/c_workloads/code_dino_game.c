/*
 * Chrome Dino game workload for the CS224 RISC-V pipeline.
 */

#include "dino_display.h"

#define FRAME_DELAY_CYCLES  50000u
#define PLAYER_GROUNDED    0u
#define PLAYER_JUMPING     1u
#define SW_JUMP_MASK        0x1u
#define SW_DOUBLE_JUMP_MASK 0x2u
#define SINGLE_JUMP_FRAMES  16u
#define DOUBLE_JUMP_FRAMES  30u
#define CACTUS_NONE         0u
#define CACTUS_SINGLE       1u
#define CACTUS_PAIR         2u
#define SPAWN_CHECK_FRAMES  6u
#define SPAWN_CHANCE_MASK   0x3u
#define CACTUS_TYPE_BIT     3u
#define OBSTACLE_START_X    0u
#define OBSTACLE_HIT_X      6u
#define SCORE_MAX           99999999u
#define SCORE_TICK_FRAMES   4u
#define LED_GAME_OVER       0xFFFFu
/* state machine: replaces infinite halt after crash */
#define STATE_PLAYING       0u 
#define STATE_GAME_OVER     1u
#define STATE_SHOW_SCORE    2u
#define GAME_OVER_HOLD_FRAMES 60u  /* ~3s blank hold before score appears */


static volatile unsigned int game_debug_sink;

static void wait_for_next_frame(void)
{
    volatile unsigned int delay;

    for (delay = 0u; delay < FRAME_DELAY_CYCLES; delay = delay + 1u) {
        /* Busy-wait frame timer for the simple bare-metal game loop. */
    }
}

int main(void)
{
    unsigned int player_state = PLAYER_GROUNDED;
    unsigned int air_time_remaining = 0u;
    unsigned int frame_count = 0u;
    unsigned int switch_state = 0u;
    unsigned int clear_mask = 0u;
    unsigned int spawn_check_timer = 0u;
    unsigned int random_value = 0u;
    unsigned int obstacle_active = 0u;
    unsigned int obstacle_type = CACTUS_NONE;
    unsigned int obstacle_x = 0u;
    unsigned int score = 0u;
    unsigned int score_tick_timer = SCORE_TICK_FRAMES;
    unsigned int crash = 0u;
    unsigned int game_state = STATE_PLAYING;  /* tracks current phase */
unsigned int phase_timer = 0u;            /* counts frames in current phase */
unsigned int final_score = 0u;            /* latches score at crash moment */

    for (;;) {
        wait_for_next_frame();

        frame_count = frame_count + 1u;
        switch_state = read_switches();
        clear_mask = 0u;

        if (player_state == PLAYER_GROUNDED) {
            if ((switch_state & SW_DOUBLE_JUMP_MASK) != 0u) {
                player_state = PLAYER_JUMPING;
                air_time_remaining = DOUBLE_JUMP_FRAMES;
                clear_mask = switch_state & (SW_JUMP_MASK | SW_DOUBLE_JUMP_MASK);
            } else if ((switch_state & SW_JUMP_MASK) != 0u) {
                player_state = PLAYER_JUMPING;
                air_time_remaining = SINGLE_JUMP_FRAMES;
                clear_mask = SW_JUMP_MASK;
            }
        }

        if (clear_mask != 0u) {
            clear_switch_sticky_bits(clear_mask);
        }

        if (player_state == PLAYER_JUMPING) {
            if (air_time_remaining > 0u) {
                air_time_remaining = air_time_remaining - 1u;
            }

            if (air_time_remaining == 0u) {
                player_state = PLAYER_GROUNDED;
            }
        }

        if (spawn_check_timer > 0u) {
            spawn_check_timer = spawn_check_timer - 1u;
        } else {
            spawn_check_timer = SPAWN_CHECK_FRAMES;

            if (obstacle_active == 0u) {
                random_value = read_lfsr();

                if ((random_value & SPAWN_CHANCE_MASK) == 0u) {
                    obstacle_active = 1u;
                    obstacle_type = ((random_value >> CACTUS_TYPE_BIT) & 0x1u)
                                      ? CACTUS_PAIR : CACTUS_SINGLE;
                    obstacle_x = OBSTACLE_START_X;
                }
            }
        }

        /* collision BEFORE movement: original cleared obstacle_active
 * at x==6 before this check ran, so crash never fired */
if ((obstacle_active != 0u) &&
    (obstacle_x == OBSTACLE_HIT_X) &&
    (player_state == PLAYER_GROUNDED)) {
    crash = 1u;
}

if (obstacle_active != 0u) {
    if (obstacle_x < OBSTACLE_HIT_X) {
        obstacle_x = obstacle_x + 1u;
    } else {
        obstacle_active = 0u;
        obstacle_type = CACTUS_NONE;
    }
}

        if (crash != 0u) {
    /* latch score, transition to GAME OVER phase */
    final_score = score;
    game_state  = STATE_GAME_OVER;
    phase_timer = 0u;
    write_leds(LED_GAME_OVER);
    write_score_digits_low(0xAAAAAAAAu);
    write_score_digits_high(0xAAAAAAAAu);
}

        if (score_tick_timer > 0u) {
            score_tick_timer = score_tick_timer - 1u;
        } else {
            score_tick_timer = SCORE_TICK_FRAMES;

            if (score < SCORE_MAX) {
                score = score + 1u;
            } else {
                score = 0u;
            }
        }

        render_game_display(player_state, obstacle_x, obstacle_type, score, 0u);

        game_debug_sink = frame_count + player_state + air_time_remaining
                        + obstacle_active + obstacle_type + obstacle_x + score
                        + crash;
    }
}
