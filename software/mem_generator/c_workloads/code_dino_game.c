/*
 * Chrome Dino game workload for the CS224 RISC-V pipeline.
 */

#include "dino_display.h"

/* Adjusted for smooth FPS based on 1 MHz effective clock */
#define FRAME_DELAY_CYCLES  15000u
#define PLAYER_GROUNDED     0u
#define PLAYER_JUMPING      1u
#define SW_JUMP_MASK        0x1u
#define SW_DOUBLE_JUMP_MASK 0x2u

/* Snappy jump physics */
#define SINGLE_JUMP_FRAMES  2u
#define DOUBLE_JUMP_FRAMES  3u

#define CACTUS_NONE         0u
#define CACTUS_SINGLE       1u
#define CACTUS_PAIR         2u
#define SPAWN_CHECK_FRAMES  6u
#define SPAWN_CHANCE_MASK   0x3u
#define CACTUS_TYPE_BIT     3u
#define OBSTACLE_START_X    0u
#define OBSTACLE_HIT_X      6u
#define SCORE_MAX         99999999u
#define SCORE_TICK_FRAMES   4u
#define LED_GAME_OVER       0xFFFFu

/* state machine: replaces infinite halt after crash */
#define STATE_PLAYING       0u
#define STATE_GAME_OVER     1u
#define STATE_SHOW_SCORE    2u
#define GAME_OVER_HOLD_FRAMES 60u

/* Direct MMIO Addresses to bypass any header mapping issues */
#define MMIO_SEG_LOW  (*(volatile unsigned int*)0x00002010u)
#define MMIO_SEG_HIGH (*(volatile unsigned int*)0x00002014u)

/* 100% Division-Free BCD Converter (Immune to compiler optimization bugs) */
static unsigned int division_free_bcd(unsigned int val) {
    unsigned int thousands = 0u, hundreds = 0u, tens = 0u, ones = 0u;
    
    while (val >= 1000u) { val = val - 1000u; thousands = thousands + 1u; }
    while (val >= 100u)  { val = val - 100u;  hundreds = hundreds + 1u; }
    while (val >= 10u)   { val = val - 10u;   tens = tens + 1u; }
    ones = val;
    
    return (thousands << 12u) | (hundreds << 8u) | (tens << 4u) | ones;
}

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
    unsigned int trailing_active = 0u;   /* NEW: Tracks the tail of a double cactus */
    unsigned int score = 0u;
    unsigned int score_tick_timer = SCORE_TICK_FRAMES;
    unsigned int crash = 0u;
    unsigned int game_state = STATE_PLAYING;
    unsigned int phase_timer = 0u;
    unsigned int final_score = 0u;
    unsigned int last_jump_type = 0u;

    for (;;) {
        wait_for_next_frame();

        frame_count = frame_count + 1u;
        
        /* 1. ALWAYS consume and clear inputs so sticky bits don't pile up */
        switch_state = read_switches();
        clear_mask = switch_state & (SW_JUMP_MASK | SW_DOUBLE_JUMP_MASK);
        if (clear_mask != 0u) {
            clear_switch_sticky_bits(clear_mask);
        }

        if (game_state == STATE_PLAYING) {

            /* 2. Only ACT on the inputs if the player is safely on the ground */
            if (player_state == PLAYER_GROUNDED) {
                if ((switch_state & SW_DOUBLE_JUMP_MASK) != 0u) {
                    player_state = PLAYER_JUMPING;
                    air_time_remaining = DOUBLE_JUMP_FRAMES;
                    last_jump_type = 2u;
                    play_sound(1);
                } else if ((switch_state & SW_JUMP_MASK) != 0u) {
                    player_state = PLAYER_JUMPING;
                    air_time_remaining = SINGLE_JUMP_FRAMES;
                    last_jump_type = 1u;
                    play_sound(1);
                }
            }

            /* 3. Spawning Logic */
            if (spawn_check_timer > 0u) {
                spawn_check_timer = spawn_check_timer - 1u;
            } else {
                spawn_check_timer = SPAWN_CHECK_FRAMES;
                if (obstacle_active == 0u && trailing_active == 0u) {
                    random_value = read_lfsr();
                    if ((random_value & SPAWN_CHANCE_MASK) == 0u) {
                        obstacle_active = 1u;
                        obstacle_type = ((random_value >> CACTUS_TYPE_BIT) & 0x1u)
                                          ? CACTUS_PAIR : CACTUS_SINGLE;
                        obstacle_x = OBSTACLE_START_X;
                    }
                }
            }

            /* 4. Collision check BEFORE movement AND BEFORE jump decay */
            /* UPDATED: Checks both the main obstacle head AND the lingering tail */
            if (obstacle_active != 0u && obstacle_x == OBSTACLE_HIT_X) {
                if (player_state == PLAYER_GROUNDED) {
                    crash = 1u;
                } else if (obstacle_type == CACTUS_PAIR && last_jump_type == 1u) {
                    /* Hit head of double cactus with a single jump */
                    crash = 1u; 
                }
            } else if (trailing_active != 0u) {
                if (player_state == PLAYER_GROUNDED) {
                    crash = 1u;
                } else if (last_jump_type == 1u) {
                    /* Hit tail of double cactus with a single jump */
                    crash = 1u; 
                }
            }

            /* 5. Jump decay (happens AFTER collision check so you survive the hit zone) */
            if (player_state == PLAYER_JUMPING) {
                if (air_time_remaining > 0u) {
                    air_time_remaining = air_time_remaining - 1u;
                }
                if (air_time_remaining == 0u) {
                    player_state = PLAYER_GROUNDED;
                }
            }

            /* 6. Move the obstacle */
            if (obstacle_active != 0u) {
                if (obstacle_x < OBSTACLE_HIT_X) {
                    obstacle_x = obstacle_x + 1u;
                } else {
                    /* If it was a pair, activate the tail for the next frame */
                    if (obstacle_type == CACTUS_PAIR) {
                        trailing_active = 1u;
                    }
                    obstacle_active = 0u;
                    obstacle_type = CACTUS_NONE;
                }
            } else if (trailing_active != 0u) {
                /* Tail has passed through the hit zone, clear it */
                trailing_active = 0u;
            }

            /* 7. Score tick */
            if (score_tick_timer > 0u) {
                score_tick_timer = score_tick_timer - 1u;
            } else {
                score_tick_timer = SCORE_TICK_FRAMES;
                if (score < SCORE_MAX) {
                    score = score + 1u;
                    // Play a short beep every 100 points
                    if (score > 0 && (score % 100 == 0)) {
                        play_sound(3); 
                    }
                } else {
                    score = 0u;
                }
            }

            if (crash != 0u) {
                /* latch score AFTER tick so final score is accurate */
                final_score = score;
                game_state  = STATE_GAME_OVER;
                phase_timer = 0u;
                write_leds(LED_GAME_OVER);

                play_sound(2);
                
                /* Instantly blank the display on crash using direct MMIO */
                MMIO_SEG_LOW  = 0xAAAAAAAAu;
                MMIO_SEG_HIGH = 0xAAAAAAAAu;
            } else {
                /* UPDATED: Render the lingering tail smoothly */
                if (trailing_active != 0u) {
                    render_game_display(player_state, OBSTACLE_HIT_X, CACTUS_SINGLE, score, 0u);
                } else {
                    render_game_display(player_state, obstacle_x, obstacle_type, score, 0u);
                }
            }

        } else if (game_state == STATE_GAME_OVER) {

            phase_timer = phase_timer + 1u;
            
            /* --- CINEMATIC CRASH ANIMATION --- */
            /* Division-free blink check (flips every 10 frames from 0 to 59) */
            unsigned int is_blink_on = 0u;
            if (phase_timer < 10u || (phase_timer >= 20u && phase_timer < 30u) || (phase_timer >= 40u && phase_timer < 50u)) {
                is_blink_on = 1u;
            }

            if (is_blink_on != 0u) {
                write_leds(0xFFFFu);         /* Turn ALL 16 LEDs ON */
                /* Flash all 8s (all 7-segments ON) to simulate a crash/static effect */
                MMIO_SEG_HIGH = 0x8888u; 
                MMIO_SEG_LOW  = 0x8888u; 
            } else {
                write_leds(0x0000u);         /* Turn ALL 16 LEDs OFF */
                /* Flash blanks to complete the strobe effect */
                MMIO_SEG_HIGH = 0xAAAAu; 
                MMIO_SEG_LOW  = 0xAAAAu; 
            }

            if (phase_timer >= GAME_OVER_HOLD_FRAMES) {
                game_state  = STATE_SHOW_SCORE;
                phase_timer = 0u;
                write_leds(0x0000u); /* Ensure LEDs are off for the score reveal */
            }

        } else {
            /* STATE_SHOW_SCORE: keep writing score every frame */
            unsigned int low_part = final_score;
            unsigned int high_part = 0u;
            
            /* Extract the upper 4 digits without using division */
            while (low_part >= 10000u) {
                low_part = low_part - 10000u;
                high_part = high_part + 1u;
            }
            
            /* Write BCD directly to hardware to guarantee correct placement */
            MMIO_SEG_LOW  = division_free_bcd(low_part);
            MMIO_SEG_HIGH = division_free_bcd(high_part);
        }

        game_debug_sink = frame_count + player_state + air_time_remaining
                        + obstacle_active + obstacle_type + obstacle_x + score
                        + crash + trailing_active;
    }
}