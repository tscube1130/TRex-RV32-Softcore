/*
 * Chrome Dino game workload for the CS224 RISC-V pipeline.
 * Define the MMIO addresses used by the Verilog mmio_decoder.
 */

#define MMIO_SW_R_ADDR    0x00002000u  /* read:  bit0=jump, bit1=double jump */
#define MMIO_SW_CLR_ADDR  0x00002004u  /* write: bit0 clears jump, bit1 clears double jump */
#define MMIO_LFSR_R_ADDR  0x00002008u  /* read:  bits15:0=random LFSR value */
#define MMIO_LED_W_ADDR   0x0000200Cu  /* write: bits15:0=LED pattern */
#define MMIO_SEG_W0_ADDR  0x00002010u  /* write: packed nibbles for digits 3..0 */
#define MMIO_SEG_W1_ADDR  0x00002014u  /* write: packed nibbles for digits 7..4 */

/*
 * Basic helper functions for memory-mapped hardware I/O.
 */

static inline unsigned int mmio_read(unsigned int address)
{
    return *(volatile unsigned int *)address;
}

static inline void mmio_write(unsigned int address, unsigned int value)
{
    *(volatile unsigned int *)address = value;
}

static inline unsigned int read_switches(void)
{
    return mmio_read(MMIO_SW_R_ADDR);
}

static inline void clear_switch_sticky_bits(unsigned int clear_mask)
{
    mmio_write(MMIO_SW_CLR_ADDR, clear_mask);
}

static inline unsigned int read_lfsr(void)
{
    return mmio_read(MMIO_LFSR_R_ADDR);
}

static inline void write_leds(unsigned int led_pattern)
{
    mmio_write(MMIO_LED_W_ADDR, led_pattern);
}

static inline void write_score_digits_low(unsigned int packed_digits)
{
    mmio_write(MMIO_SEG_W0_ADDR, packed_digits);
}

static inline void write_score_digits_high(unsigned int packed_digits)
{
    mmio_write(MMIO_SEG_W1_ADDR, packed_digits);
}

/*
 * Initialize game state and add a simple frame-rate delay.
 */

#define FRAME_DELAY_CYCLES  50000u
#define PLAYER_GROUNDED    0u
#define PLAYER_JUMPING     1u
#define SW_JUMP_MASK        0x1u
#define SW_DOUBLE_JUMP_MASK 0x2u
#define SINGLE_JUMP_FRAMES  8u
#define DOUBLE_JUMP_FRAMES  14u

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

    for (;;) {
        wait_for_next_frame();

        frame_count = frame_count + 1u;
        switch_state = read_switches();

        if (player_state == PLAYER_GROUNDED) {
            if ((switch_state & SW_DOUBLE_JUMP_MASK) != 0u) {
                player_state = PLAYER_JUMPING;
                air_time_remaining = DOUBLE_JUMP_FRAMES;
            } else if ((switch_state & SW_JUMP_MASK) != 0u) {
                player_state = PLAYER_JUMPING;
                air_time_remaining = SINGLE_JUMP_FRAMES;
            }
        }

        if (player_state == PLAYER_GROUNDED) {
            air_time_remaining = 0u;
        }

        game_debug_sink = frame_count + player_state + air_time_remaining;
    }
}
