/*
 * Chrome Dino game workload for the CS224 RISC-V pipeline.
 * ARCADE MULTIPLAYER EDITION (Perfect Sync, Original Score Logic)
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
#define SCORE_MAX           9999u
#define SCORE_TICK_FRAMES   4u /* Original simple tick rate */
#define LED_GAME_OVER       0xFFFFu

/* state machine */
#define STATE_PLAYING       0u
#define STATE_GAME_OVER     1u
#define STATE_SHOW_SCORE    2u
#define GAME_OVER_HOLD_FRAMES 60u

/* Direct MMIO Addresses */
#define MMIO_SEG_LOW  (*(volatile unsigned int*)0x00002010u)
#define MMIO_SEG_HIGH (*(volatile unsigned int*)0x00002014u)

/* Pulse Protocol Definitions */
#define PULSE_SINGLE_CACTUS  1u   /* HIGH for 1 frame */
#define PULSE_PAIR_CACTUS    2u   /* HIGH for 2 frames */
#define PULSE_DEATH_SIGNAL   10u  /* HIGH for 10+ frames = Game Over */

/* Result text nibbles (digits 7..4) using custom hardware mappings */
#define SEG_CH_U             0x0u
#define SEG_CH_I             0x1u
#define SEG_CH_N             0xCu
#define SEG_CH_L             0xEu
#define SEG_CH_O             0x0u
#define SEG_CH_S             0x5u
#define SEG_CH_E             0xFu

/* Result text nibbles utilizing the Bit-31 Bank Switch */
/* 0x80000000 triggers text mode. 1=U, 2=I, 3=n, 4=L, 5=O, 6=S, 7=E */
#define RESULT_WORD_WIN  0x80001123u /* U U I n */
#define RESULT_WORD_LOSE 0x80004567u /* L O S E */

/* 100% Division-Free BCD Converter */
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
    for (delay = 0u; delay < FRAME_DELAY_CYCLES; delay = delay + 1u) {}
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
    unsigned int trailing_active = 0u; 
    unsigned int score = 0u;
    unsigned int score_tick_timer = SCORE_TICK_FRAMES;
    unsigned int crash = 0u;
    unsigned int game_state = STATE_PLAYING;
    unsigned int phase_timer = 0u;
    unsigned int final_score = 0u;
    unsigned int last_jump_type = 0u;
    
    /* Networking Variables */
    unsigned int is_host = 0u;
    unsigned int tx_pulse_remaining = 0u; 
    unsigned int rx_pulse_counter = 0u;
    unsigned int rx_current_state = 0u;
    unsigned int rx_prev_state = 0u;
    unsigned int opponent_game_over = 0u;
    unsigned int result_is_win = 0u;

    /* Initialize role at boot */
    is_host = is_board_host();

    for (;;) {
        wait_for_next_frame();
        frame_count = frame_count + 1u;
        
        /* 1. ALWAYS consume and clear inputs */
        switch_state = read_switches();
        clear_mask = switch_state & (SW_JUMP_MASK | SW_DOUBLE_JUMP_MASK);
        if (clear_mask != 0u) {
            clear_switch_sticky_bits(clear_mask);
        }

        /* --- A. READ RX PULSE (Global Listener) --- */
        rx_prev_state = rx_current_state;
        rx_current_state = read_network_rx();

        if (rx_current_state != 0u) {
            rx_pulse_counter = rx_pulse_counter + 1u;
            
            /* INSTANT DEATH DETECTION: Do not wait for falling edge! */
            if (rx_pulse_counter >= PULSE_DEATH_SIGNAL) {
                opponent_game_over = 1u;
            }
        } else {
            /* Falling edge: decode complete pulse length for cacti only. */
            if (rx_prev_state != 0u) {
                if (is_host == 0u) {
                    if (rx_pulse_counter == PULSE_SINGLE_CACTUS) {
                        obstacle_active = 1u; obstacle_type = CACTUS_SINGLE; obstacle_x = OBSTACLE_START_X;
                    } else if (rx_pulse_counter == PULSE_PAIR_CACTUS) {
                        obstacle_active = 1u; obstacle_type = CACTUS_PAIR; obstacle_x = OBSTACLE_START_X;
                    }
                }
            }
            rx_pulse_counter = 0u;
        }

        if (game_state == STATE_PLAYING) {

            /* 2. Jump Input */
            if (player_state == PLAYER_GROUNDED) {
                if ((switch_state & SW_DOUBLE_JUMP_MASK) != 0u) {
                    player_state = PLAYER_JUMPING; air_time_remaining = DOUBLE_JUMP_FRAMES; last_jump_type = 2u; play_sound(1);
                } else if ((switch_state & SW_JUMP_MASK) != 0u) {
                    player_state = PLAYER_JUMPING; air_time_remaining = SINGLE_JUMP_FRAMES; last_jump_type = 1u; play_sound(1);
                }
            }

            /* --- 3. SPAWNING LOGIC (Host Only) --- */
            if (spawn_check_timer > 0u) {
                spawn_check_timer = spawn_check_timer - 1u;
            } else {
                spawn_check_timer = SPAWN_CHECK_FRAMES;
                if (obstacle_active == 0u && trailing_active == 0u) {
                    if (is_host != 0u) {
                        random_value = read_lfsr();
                        if ((random_value & SPAWN_CHANCE_MASK) == 0u) {
                            obstacle_active = 1u;
                            obstacle_type = ((random_value >> CACTUS_TYPE_BIT) & 0x1u) ? CACTUS_PAIR : CACTUS_SINGLE;
                            obstacle_x = OBSTACLE_START_X;
                            tx_pulse_remaining = (obstacle_type == CACTUS_PAIR) ? PULSE_PAIR_CACTUS : PULSE_SINGLE_CACTUS;
                        }
                    }
                }
            }

            /* --- 4. COLLISION & DEATH CHECK --- */
            if (obstacle_active != 0u && obstacle_x == OBSTACLE_HIT_X) {
                if (player_state == PLAYER_GROUNDED) { crash = 1u; } 
                else if (obstacle_type == CACTUS_PAIR && last_jump_type == 1u) { crash = 1u; }
            } else if (trailing_active != 0u) {
                if (player_state == PLAYER_GROUNDED) { crash = 1u; } 
                else if (last_jump_type == 1u) { crash = 1u; }
            }

            /* --- 5. JUMP DECAY --- */
            if (player_state == PLAYER_JUMPING) {
                if (air_time_remaining > 0u) { air_time_remaining = air_time_remaining - 1u; }
                if (air_time_remaining == 0u) { player_state = PLAYER_GROUNDED; }
            }

            /* --- 6. MOVE THE OBSTACLE --- */
            if (obstacle_active != 0u) {
                if (obstacle_x < OBSTACLE_HIT_X) { obstacle_x = obstacle_x + 1u; } 
                else {
                    if (obstacle_type == CACTUS_PAIR) { trailing_active = 1u; }
                    obstacle_active = 0u; obstacle_type = CACTUS_NONE;
                }
            } else if (trailing_active != 0u) {
                trailing_active = 0u;
            }

            /* --- 7. ORIGINAL SCORE TICK LOGIC --- */
            if (score_tick_timer > 0u) {
                score_tick_timer = score_tick_timer - 1u;
            } else {
                score_tick_timer = SCORE_TICK_FRAMES;
                if (score < SCORE_MAX) {
                    score = score + 1u;
                    if (score > 0 && (score % 100 == 0)) { play_sound(3); }
                } else {
                    score = SCORE_MAX;
                }
            }

            /* --- 8. RESOLVE GAME STATE & RENDER --- */
            if (opponent_game_over != 0u || crash != 0u) {
                final_score = score;
                result_is_win = (opponent_game_over != 0u && crash == 0u) ? 1u : 0u;
                game_state = STATE_GAME_OVER;
                phase_timer = 0u;
                write_leds(LED_GAME_OVER);
                play_sound(2);
                MMIO_SEG_LOW  = 0xAAAAAAAAu;
                MMIO_SEG_HIGH = 0xAAAAAAAAu;

                /* Any side crashing sends the death pulse instantly! */
                if (crash != 0u) {
                    tx_pulse_remaining = PULSE_DEATH_SIGNAL;
                }
            } else {
                /* ALIVE: Render normally */
                if (trailing_active != 0u) { render_game_display(player_state, OBSTACLE_HIT_X, CACTUS_SINGLE, score, 0u); } 
                else { render_game_display(player_state, obstacle_x, obstacle_type, score, 0u); }
            }

        } else if (game_state == STATE_GAME_OVER) {
            phase_timer = phase_timer + 1u;
            
            /* --- CINEMATIC CRASH ANIMATION --- */
            unsigned int is_blink_on = 0u;
            if (phase_timer < 10u || (phase_timer >= 20u && phase_timer < 30u) || (phase_timer >= 40u && phase_timer < 50u)) {
                is_blink_on = 1u;
            }

            if (is_blink_on != 0u) {
                write_leds(0xFFFFu); 
                MMIO_SEG_HIGH = 0x8888u; MMIO_SEG_LOW  = 0x8888u; 
            } else {
                write_leds(0x0000u); 
                MMIO_SEG_HIGH = 0xAAAAu; MMIO_SEG_LOW  = 0xAAAAu; 
            }

            if (phase_timer >= GAME_OVER_HOLD_FRAMES) {
                game_state  = STATE_SHOW_SCORE;
                phase_timer = 0u;
                write_leds(0x0000u); 
            }

        } else {
            /* STATE_SHOW_SCORE: [7..4]=result word, [3..0]=score */
            unsigned int score_4d = final_score;
            while (score_4d >= 10000u) { score_4d = score_4d - 10000u; }

            MMIO_SEG_LOW  = division_free_bcd(score_4d);
            MMIO_SEG_HIGH = (result_is_win != 0u) ? RESULT_WORD_WIN : RESULT_WORD_LOSE;
            
            /* GAME STOPS HERE FOREVER. Must press hardware BTNC reset to play again. */
        }

        /* --- GLOBAL TX DRIVER --- 
         * Fires in every state, guaranteeing the death pulse sends perfectly on time. */
        if (tx_pulse_remaining > 0u) {
            write_network_tx(1u);
            tx_pulse_remaining = tx_pulse_remaining - 1u;
        } else {
            write_network_tx(0u);
        }

        game_debug_sink = frame_count + player_state + air_time_remaining
                        + obstacle_active + obstacle_type + obstacle_x + score
                        + crash + trailing_active;
    }
}