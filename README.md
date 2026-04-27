# Project T-Rex — Hardware-Accelerated Chrome Dino

**Group 13 | CS224**

A fully playable Chrome Dino-style game running on a custom 3-stage RV32IM processor on the Nexys A7 FPGA.

What This Is?
Project T-Rex extends a baseline 3-stage RV32I pipeline with:
RV32M arithmetic — MUL (1-cycle DSP), DIV (32-cycle iterative FSM), custom MAC accumulator
5 custom MMIO peripherals — sticky debouncer, 16-bit LFSR, 8-digit 7-segment mux, LED controller, audio PWM driver
Bare-metal C game loop — collision detection, LFSR obstacle spawn, BCD scoring, audio events
Multiplayer — two Nexys A7 boards linked via PMOD GPIO (pulse protocol)

---

## Repository Structure

```CS224-Project/
├── README.md
├── dfx_runtime.txt
├── vivado.jou
├── build/
│   └── vivado_vga/
│       └── trex_dino_nexys_a7_vga.xpr
├── constraints/
│   ├── nexys_a7.xdc
│   └── nexys_a7_vga_template.xdc
├── docs/
│   └── LFSR_DISPLAY_RUN.md
├── Multiplayer/
│   ├── constraints/
│   │   └── nexys_a7.xdc
│   ├── software/
│   │   └── mem_generator/
│   │       ├── crt0.S
│   │       ├── Makefile
│   │       ├── c_workloads/
│   │       └── imem_dmem/
│   └── src/
│       ├── 3-stage-pipeline/
│       │   ├── execute.v
│       │   ├── IF_ID.v
│       │   ├── memory.v
│       │   ├── opcode.vh
│       │   ├── pipeline.v
│       │   ├── top_fpga.v
│       │   └── wb.v
│       ├── audio_driver.v
│       ├── debouncer.v
│       ├── led_ctrl.v
│       ├── lfsr16.v
│       ├── math_coproc.v
│       ├── mmio_decoder.v
│       └── seg7_mux.v
├── scripts/
│   ├── build_nexys_a7.tcl
│   ├── build_nexys_a7_noclean.tcl
│   ├── build_nexys_a7_with_vga.tcl
│   ├── debug_topfpga_synth.tcl
│   ├── program_nexys_a7.tcl
│   └── program_nexys_a7_with_vga.tcl
├── software/
│   └── mem_generator/
│       ├── crt0.S
│       ├── Makefile
│       ├── c_workloads/
│       └── imem_dmem/
│           └── bin2hex.py
├── src/
│   ├── 3-stage-pipeline/
│   │   ├── execute.v
│   │   ├── IF_ID.v
│   │   ├── memory.v
│   │   ├── opcode.vh
│   │   ├── pipeline.v
│   │   ├── top_fpga.v
│   │   └── wb.v
│   ├── audio_driver.v
│   ├── debouncer.v
│   ├── led_ctrl.v
│   ├── lfsr16.v
│   ├── math_coproc.v
│   ├── mmio_decoder.v
│   ├── seg7_mux.v
│   ├── top_fpga_with_vga.v
│   └── vga_trex/
│       ├── BackGroundDelegate.v
│       ├── ClockDivider.v
│       ├── DinoFSM.v
│       ├── ObstaclesDelegate.v
│       ├── ScoreBoardDelegate.v
│       ├── TRexDelegate.v
│       ├── TRex_top.v
│       ├── VGA.v
│       ├── debouncer.v
│       ├── drawBackGround.v
│       ├── drawDino.v
│       ├── drawNumber.v
│       ├── drawObstacle.v
│       ├── gameDelegate.v
│       ├── vgaClk.v
│       └── vga_score_cpu_side.v
└── tb/
    ├── tb_debouncer.v
    ├── tb_div.v
    ├── tb_led_ctrl.v
    ├── tb_lfsr16.v
    ├── tb_math_coproc.v
    ├── tb_mmio_decoder.v
    ├── tb_pipeline_div.v
    ├── tb_pipeline_math.v
    ├── tb_seg7_mux.v
    ├── tb_top_fpga.v
    └── tb_vga_trex_top.v
```

---

## MMIO Address Map

| Address  | R/W | Name        | Description                                           |
| -------- | --- | ----------- | ----------------------------------------------------- |
| `0x2000` | R   | MMIO_SW_R   | bit[0] = jump sticky, bit[1] = double jump sticky     |
| `0x2004` | W   | MMIO_SW_CLR | Write 1 = clear jump, 2 = clear double jump, 3 = both |
| `0x2008` | R   | MMIO_LFSR_R | 16-bit LFSR value (bit[0] = cactus type)              |
| `0x200C` | W   | MMIO_LED_W  | 16-bit LED pattern (crash animation)                  |
| `0x2010` | W   | MMIO_SEG_W0 | 7-seg digits 3-0 (nibble-packed)                      |
| `0x2014` | W   | MMIO_SEG_W1 | 7-seg digits 7-4 (nibble-packed)                      |
| `0x2018` | W   | MMIO_AUDIO  | Audio trigger: bit[0]=jump sound, bit[1]=crash sound  |

---

## Build and Run

### Prerequisites

- Vivado 2020.2 or later
- RISC-V toolchain providing `riscv64-unknown-elf-gcc`
- Python 3 for `bin2hex.py`

### 1. Compile the game workload

The software lives under `software/mem_generator`. The default workload is `code_dino_game`.

```bash
cd software/mem_generator
make
```

To build a different workload, pass `WORKLOAD` explicitly:

```bash
make WORKLOAD=code_factorial
```

This generates `imem_dmem/imem.hex` and `imem_dmem/dmem.hex`, which Vivado loads into BRAM during synthesis.

### 2. Build the FPGA bitstream

From the repository root, run the Vivado batch script for the target you want:

```bash
C:/AMDDesignTools/2025.2/Vivado/bin/vivado.bat -mode batch -source scripts/build_nexys_a7.tcl
```

Use the VGA build if you want the dual-output top level instead:

```bash
C:/AMDDesignTools/2025.2/Vivado/bin/vivado.bat -mode batch -source scripts/build_nexys_a7_with_vga.tcl
```

The non-VGA flow writes its project under `build/vivado/`, and the VGA flow writes under `build/vivado_vga/`.

### 3. Program the Nexys A7

After the bitstream is generated, program the board with the matching script:

```bash
C:/AMDDesignTools/2025.2/Vivado/bin/vivado.bat -mode batch -source scripts/program_nexys_a7.tcl
```

For the VGA build, use:

```bash
C:/AMDDesignTools/2025.2/Vivado/bin/vivado.bat -mode batch -source scripts/program_nexys_a7_with_vga.tcl
```

If you prefer the Vivado GUI, you can also open the generated project in `build/` or `build/vivado_vga/`, run Synthesis, run Implementation, and then Generate Bitstream before programming the device through Hardware Manager.

### Notes

- Target board: Nexys A7-100T (`xc7a100tcsg324-1`)
- The CPU game path uses `src/top_fpga.v`; the VGA build uses `src/top_fpga_with_vga.v`
- If you change the C workload, rebuild `imem.hex` and `dmem.hex` before rerunning Vivado
- The multiplayer hardware variant lives under `Multiplayer/`; use `Multiplayer/src/3-stage-pipeline/top_fpga.v` as the top module and `Multiplayer/constraints/nexys_a7.xdc` as the board constraints
- The multiplayer software flow still starts with `cd Multiplayer/software/mem_generator && make`, which produces the same `imem.hex` and `dmem.hex` files for BRAM initialization

Expected resource utilization (Nexys A7-100T):

| Resource | Available | Estimated | Utilization |
| -------- | --------- | --------- | ----------- |
| BRAM     | 135       | ~8        | ~6%         |
| DSP      | 240       | ~4        | ~2%         |
| LUT      | 63,400    | ~3,800    | ~6%         |
| FF       | 126,800   | ~4,500    | ~4%         |

---

## Clock Configuration

CPU pipeline runs on a divided clock (inline in top_fpga.v). Change DIV_COUNT to adjust speed:

| DIV_COUNT  | CPU Clock | Use Case              |
| ---------- | --------- | --------------------- |
| 50_000_000 | 1 Hz      | Visible debug (slow)  |
| 500_000    | 100 Hz    | Fast debug            |
| 5_000      | 10 kHz    | Functional test       |
| 50         | 1 MHz     | Near-real performance |

---
