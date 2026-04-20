#ifndef DINO_MMIO_H
#define DINO_MMIO_H

/*
 * MMIO addresses used by src/mmio_decoder.v.
 */

#define MMIO_SW_R_ADDR    0x00002000u  /* read:  bit0=jump, bit1=double jump */
#define MMIO_SW_CLR_ADDR  0x00002004u  /* write: bit0 clears jump, bit1 clears double jump */
#define MMIO_LFSR_R_ADDR  0x00002008u  /* read:  bits15:0=random LFSR value */
#define MMIO_LED_W_ADDR   0x0000200Cu  /* write: bits15:0=LED pattern */
#define MMIO_SEG_W0_ADDR  0x00002010u  /* write: packed nibbles for digits 3..0 */
#define MMIO_SEG_W1_ADDR  0x00002014u  /* write: packed nibbles for digits 7..4 */

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
#define MMIO_AUDIO_ADDR   0x00002018u  /* write: 0x1=jump, 0x2=crash, 0x3=score */

static inline void play_sound(unsigned int sound_code)
{
    mmio_write(MMIO_AUDIO_ADDR, sound_code);
}

#endif
