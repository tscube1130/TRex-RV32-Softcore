# Project T-Rex — Hardware-Accelerated Chrome Dino
**Group 13 | CS224**

A fully playable Chrome Dino-style game running on a custom 3-stage RV32IM processor on the Nexys A7 FPGA.

---

## Repository Structure

```
CS224-Project/
├── src/
│   ├── 3-stage-pipeline/
│   │   ├── pipeline.v
│   │   ├── IF_ID.v
│   │   ├── execute.v
│   │   ├── memory.v
│   │   ├── wb.v
│   │   ├── opcode.vh
│   │   └── top_fpga.v          # FPGA top-level (all peripherals wired)
│   ├── math_coproc.v           # RV32M: MUL / DIV / MAC unit
│   ├── mmio_decoder.v          # Memory-mapped I/O address decoder
│   ├── seg7_mux.v              # 8-digit 7-segment display multiplexer
│   ├── lfsr16.v                # 16-bit LFSR (random cactus generation)
│   ├── debouncer.v             # Sticky button debouncer
│   └── led_ctrl.v              # LED crash animation controller
├── tb/
│   ├── tb_math_coproc.v
│   ├── tb_div.v
│   ├── tb_pipeline_math.v
│   ├── tb_pipeline_div.v
│   ├── tb_mmio_decoder.v
│   ├── tb_seg7_mux.v
│   ├── tb_lfsr16.v
│   ├── tb_debouncer.v
│   ├── tb_led_ctrl.v
│   └── tb_top_fpga.v           # Top-level integration smoke test
├── constraints/
│   └── nexys_a7.xdc            # Nexys A7 pin mapping and timing constraints
├── software/
│   └── mem_generator/
│       ├── Makefile
│       ├── c_workloads/
│       └── imem_dmem/
│           └── bin2hex.py
└── docs/
    └── CS224_Group-13_Project_Abstract.pdf
```

---

## MMIO Address Map

| Address  | R/W | Name        | Description                                            |
|----------|-----|-------------|--------------------------------------------------------|
| `0x2000` | R   | MMIO_SW_R   | bit[0] = jump sticky, bit[1] = double jump sticky      |
| `0x2004` | W   | MMIO_SW_CLR | Write 1 = clear jump, 2 = clear double jump, 3 = both  |
| `0x2008` | R   | MMIO_LFSR_R | 16-bit LFSR value (bit[0] = cactus type)               |
| `0x200C` | W   | MMIO_LED_W  | 16-bit LED pattern (crash animation)                   |
| `0x2010` | W   | MMIO_SEG_W0 | 7-seg digits 3-0 (nibble-packed)                       |
| `0x2014` | W   | MMIO_SEG_W1 | 7-seg digits 7-4 (nibble-packed)                       |

---

## Building and Flashing (Vivado)

### Prerequisites
- Vivado 2020.2 or later
- RISC-V toolchain: riscv32-unknown-elf-gcc with -march=rv32im
- Python 3 (for bin2hex.py)

### Step 1 — Compile C Game Code

```bash
cd software/mem_generator
make TARGET=code_game
```

### Step 2 — Vivado Project Setup

1. Create new project targeting Nexys A7-100T (xc7a100tcsg324-1)
2. Add all .v and .vh files from src/ as design sources
3. Set top_fpga.v as the top module
4. Add constraints/nexys_a7.xdc as constraint file
5. Load imem.hex and dmem.hex into BRAM initialization

### Step 3 — Synthesize and Implement

```
Flow → Run Synthesis → Run Implementation → Generate Bitstream
```

Expected resource utilization (Nexys A7-100T):

| Resource | Available | Estimated | Utilization |
|----------|-----------|-----------|-------------|
| BRAM     | 135       | ~8        | ~6%         |
| DSP      | 240       | ~4        | ~2%         |
| LUT      | 63,400    | ~3,800    | ~6%         |
| FF       | 126,800   | ~4,500    | ~4%         |

### Step 4 — Program Board

```
Hardware Manager → Open Target → Auto Connect → Program Device
```

---

## Clock Configuration

CPU pipeline runs on a divided clock (inline in top_fpga.v). Change DIV_COUNT to adjust speed:

| DIV_COUNT    | CPU Clock | Use Case              |
|--------------|-----------|-----------------------|
| 50_000_000   | 1 Hz      | Visible debug (slow)  |
| 500_000      | 100 Hz    | Fast debug            |
| 5_000        | 10 kHz    | Functional test       |
| 50           | 1 MHz     | Near-real performance |

---



---

## GitHub

https://github.com/sanjeebani14/CS224-Project

