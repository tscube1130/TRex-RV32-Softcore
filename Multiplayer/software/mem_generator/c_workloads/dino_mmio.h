#ifndef DINO_MMIO_H
#define DINO_MMIO_H

/* MMIO Address Map */
#define MMIO_SW_R_ADDR    0x00002000u  
#define MMIO_SW_CLR_ADDR  0x00002004u  
#define MMIO_LFSR_R_ADDR  0x00002008u  
#define MMIO_LED_W_ADDR   0x0000200Cu  
#define MMIO_SEG_W0_ADDR  0x00002010u  
#define MMIO_SEG_W1_ADDR  0x00002014u  
#define MMIO_NET_TX_ADDR  0x00002018u  /* Network TX */
#define MMIO_NET_RX_ADDR  0x0000201Cu  /* Network RX / Role */
#define MMIO_AUDIO_ADDR   0x00002020u  /* Bumped to 2020 to prevent collision! */

/* 1. CORE READ/WRITE MUST BE DEFINED FIRST */
static inline unsigned int mmio_read(unsigned int address) {
    return *(volatile unsigned int *)address;
}

static inline void mmio_write(unsigned int address, unsigned int value) {
    *(volatile unsigned int *)address = value;
}

/* 2. ALL OTHER HELPERS CAN NOW SAFELY USE THEM */
static inline void write_network_tx(unsigned int value) {
    mmio_write(MMIO_NET_TX_ADDR, value & 0x1u);
}

static inline unsigned int read_network_rx(void) {
    return (mmio_read(MMIO_NET_RX_ADDR) & 0x1u);
}

static inline unsigned int is_board_host(void) {
    return ((mmio_read(MMIO_NET_RX_ADDR) >> 1u) & 0x1u);
}

static inline unsigned int read_switches(void) {
    return mmio_read(MMIO_SW_R_ADDR);
}

static inline void clear_switch_sticky_bits(unsigned int clear_mask) 
{
    mmio_write(MMIO_SW_CLR_ADDR, clear_mask);
}

static inline unsigned int read_lfsr(void) {
    return mmio_read(MMIO_LFSR_R_ADDR);
}

static inline void write_leds(unsigned int led_pattern) {
    mmio_write(MMIO_LED_W_ADDR, led_pattern);
}

static inline void write_score_digits_low(unsigned int packed_digits) {
    mmio_write(MMIO_SEG_W0_ADDR, packed_digits);
}

static inline void write_score_digits_high(unsigned int packed_digits) {
    mmio_write(MMIO_SEG_W1_ADDR, packed_digits);
}

static inline void play_sound(unsigned int sound_code) {
    mmio_write(MMIO_AUDIO_ADDR, sound_code);
}

#endif