# 🦕 T-Rex RV32IM Softcore

> A custom 3-stage RISC-V CPU built from RTL, running a Chrome Dino-style game on a Nexys A7 FPGA.
> Not a simulator. Not a pre-built core. Every pipeline stage, every peripheral, every stall — written from scratch.

![Board](https://img.shields.io/badge/Board-Nexys%20A7--100T-blue)
![ISA](https://img.shields.io/badge/ISA-RV32IM%20%2B%20custom%20MAC-brightgreen)
![Language](https://img.shields.io/badge/RTL-Verilog-orange)
![Software](https://img.shields.io/badge/Software-Bare--metal%20C-yellow)
![Course](https://img.shields.io/badge/Course-CS224%20HARDWARE%LAB-red)
![Status](https://img.shields.io/badge/Status-Working%20on%20Hardware-success)

---

## What Is This

Project T-Rex is a full hardware-software co-design on a Nexys A7-100T FPGA. The CPU is a
3-stage RV32IM pipeline built entirely in Verilog, extended with a custom math coprocessor
(single-cycle DSP multiply, 34-cycle iterative divider, MAC accumulator). Running on top of
it is a bare-metal C game — obstacles spawn via a hardware LFSR, score tracks on an 8-digit
7-segment display, audio plays on jump and crash events, and a multiplayer mode links two
boards over PMOD GPIO.

Two clock domains, five custom MMIO peripherals, one instruction rescue buffer, and zero
operating system.

---

## System Architecture

```
                    100 MHz Board Clock (clk)
                           │
              ┌────────────┴────────────┐
              │ Clock Divider ÷100      │
              │ slow_clk ≈ 1 MHz        │
              └────────────┬────────────┘
                           │
        ┌──────────────────┼──────────────────────┐
        │  RISC-V Pipeline (slow_clk)             │
        │  ┌──────────────────────────────────┐   │
        │  │  IF/ID  →  EX  →  WB            │   │
        │  │         math_coproc              │   │
        │  │         MUL(1) DIV(34) MAC(1)    │   │
        │  └──────────────────────────────────┘   │
        │         │                │              │
        │       IMEM             DMEM             │
        │      (BRAM)           (BRAM)            │
        │                         │              │
        │                  MMIO Decoder          │
        │                  0x2000 – 0x201C        │
        └─────────────────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────────┐
        │  Fast Peripherals (100 MHz)             │
        │  seg7_mux  lfsr16  debouncer  audio_drv │
        └──────────────────────────────────────────┘
```

**Why two clock domains?** The 7-segment mux needs a fast switching rate (125 Hz per digit)
to appear flicker-free. The LFSR needs to look random. The debouncer needs a 10 ms settle
window. All of that requires 100 MHz. The pipeline runs at 1 MHz to keep MMIO debugging
deterministic and to match the game's timing. Fast peripherals are read/written by the CPU
through memory-mapped registers — the clock crossing is handled by registered latches and
sticky flags.

---

## Pipeline

### Stages

```
Cycle N:    [ IF/ID ]
Cycle N+1:          [ EX ]
Cycle N+2:                  [ WB ]
```

Three stages: Instruction Fetch + Decode, Execute (ALU + math_coproc), Writeback.
Register forwarding handles data hazards. Branch outcomes resolve in EX — one bubble on taken branches.

### Stall and Freeze Logic

DIV is the only multi-cycle instruction. When a `DIV`/`DIVU`/`REM`/`REMU` enters EX:

1. `math_coproc.v` raises `math_stall`
2. `pipeline.v` converts this to `pipeline_freeze`
3. `pipeline_freeze` gates: PC advance, IF/ID register, EX stage, WB stage, regfile write enable — everything freezes

The freeze lasts 32 running cycles + 1 DONE cycle = **34 slow-clock cycles total**.

### Instruction Rescue Buffer

Here is the subtle problem: the pipeline's BRAM instruction fetch is registered (1-cycle
latency). When `pipeline_freeze` asserts mid-fetch, the BRAM output for the *next*
instruction is already on the wire — but the IF/ID register is frozen and will not capture
it. On resume, that instruction would be silently lost.

The fix: an **instruction rescue buffer** in `pipeline.v` captures the BRAM read data at
the moment freeze asserts and holds it. On the first cycle after freeze releases, the
pipeline reads from the rescue buffer instead of BRAM. No instruction corruption.

### Latency Table

| Instruction Class          | Cycles | Stall? |
|---------------------------|--------|--------|
| All RV32I (ADD, LW, BEQ…) | 1      | No     |
| MUL / MULH / MULHU / MULHSU | 1    | No     |
| MAC (custom)              | 1      | No     |
| DIV / DIVU / REM / REMU   | 34     | Yes    |

Effective IPC ≈ 1.0 for non-divide workloads. The game loop calls DIV exactly once per
frame (speed scaling), so the 34-cycle penalty has no visible impact on gameplay.

---

## Math Coprocessor (`math_coproc.v`)

All RV32M instructions plus one custom extension, sharing a single result mux.

### MUL
Sign-extends operands to 33 bits to handle all four variants (signed×signed, signed×unsigned,
unsigned×unsigned). The 66-bit product is computed in a single cycle, mapped to DSP slices
via `(* use_dsp = "yes" *)`. `MUL` takes the lower 32 bits; `MULH`/`MULHU`/`MULHSU` take
the upper 32.

### DIV — Iterative Shift-Subtract FSM

```
        div_start=0          div_start=1
   ┌──────────────┐      ┌──────────────────┐
   │  DIV_IDLE    │─────▶│  DIV_RUNNING     │
   │              │      │  (×32 cycles)    │
   └──────────────┘      └────────┬─────────┘
           ▲                      │ count==31
           │              ┌───────▼─────────┐
           └──────────────│   DIV_DONE      │
                          │ math_stall = 0  │
                          └─────────────────┘
```

Edge cases resolved combinationally (no stall needed):
- Divide by zero → quotient = `0xFFFF_FFFF`, remainder = dividend
- `INT_MIN / -1` signed overflow → quotient = `INT_MIN`, remainder = 0

### MAC — Custom Instruction
Fuses `MUL` + `ADD` into a single opcode (`funct7 = 0b0100000`). A hidden 32-bit
accumulator register holds the running sum. `MVACC` reads it back into the register file.
The accumulator update is gated on `!pipeline_stall` to prevent double-counting during
freeze cycles.

---

## MMIO Peripheral Map

Both variants share `0x2000–0x2014`. Singleplayer adds audio at `0x2018`; multiplayer
replaces it with the PMOD net interface.

| Address  | R/W | Name          | Description                                        |
|----------|-----|---------------|----------------------------------------------------|
| `0x2000` | R   | `MMIO_SW_R`   | `bit[0]` = jump sticky, `bit[1]` = dbl-jump sticky |
| `0x2004` | W   | `MMIO_SW_CLR` | Write `1`/`2`/`3` to clear jump/dbl/both           |
| `0x2008` | R   | `MMIO_LFSR_R` | 16-bit LFSR value (`bit[0]` = cactus type)         |
| `0x200C` | W   | `MMIO_LED_W`  | 16-bit LED pattern (crash animation)               |
| `0x2010` | W   | `MMIO_SEG_W0` | 7-seg digits 3–0 (nibble-packed BCD)               |
| `0x2014` | W   | `MMIO_SEG_W1` | 7-seg digits 7–4 (nibble-packed BCD)               |
| `0x2018` | W   | `MMIO_AUDIO`  | **SP only** — `bit[0]`=jump, `bit[1]`=crash tone   |
| `0x2018` | W   | `MMIO_NET_TX` | **MP only** — PMOD TX bit (pulse protocol)         |
| `0x201C` | R   | `MMIO_NET_RX` | **MP only** — PMOD RX + role switch input          |

### Sticky Debouncer Design
The debouncer doesn't just clean up bounce — it latches a press in hardware and holds it
until the CPU explicitly writes to `MMIO_SW_CLR`. This matters because during the 34-cycle
DIV freeze, the pipeline cannot execute any MMIO reads. A pure polling approach would
silently drop any button press that arrived in that window. The sticky latch guarantees
zero lost inputs regardless of pipeline state.

---

## Multiplayer

Two Nexys A7 boards linked via PMOD GPIO. Each board runs an independent game instance;
a bit-bang pulse protocol synchronises game events (opponent death, LFSR seed) in real time.
Role (host/client) is determined by a board switch. The multiplayer variant swaps the audio
peripheral at `0x2018` for the net TX register and adds `0x201C` for RX.

---

## Resource Utilization (Singleplayer, Nexys A7-100T)

| Resource | Used    | Available | Utilization |
|----------|---------|-----------|-------------|
| LUT      | ~3,164  | 63,400    | 4.99%       |
| FF       | ~1,499  | 126,800   | 1.18%       |
| BRAM     | ~0.5    | 135       | 0.37%       |
| DSP      | ~5      | 240       | 2.08%       |

---

## Repository Structure

```
TRex-RV32-Softcore/
├── src/
│   ├── core/                   ← RV32IM pipeline RTL
│   │   ├── pipeline.v          ← 3-stage top, hazard unit, rescue buffer
│   │   ├── IF_ID.v             ← IF/ID pipeline register + decode
│   │   ├── execute.v           ← EX stage, ALU, math_coproc interface
│   │   ├── memory.v            ← MEM stage, instr_mem, data_mem BRAMs
│   │   ├── wb.v                ← WB stage, regfile write
│   │   ├── math_coproc.v       ← MUL (DSP) / DIV (FSM) / MAC accumulator
│   │   └── opcode.vh           ← ISA defines
│   └── peripherals/            ← MMIO peripheral RTL
│       ├── audio_driver.v      ← PWM square-wave tone generator
│       ├── debouncer.v         ← 2-flop sync + settle counter + sticky latch
│       ├── led_ctrl.v          ← 16-bit MMIO-writable LED register
│       └── lfsr16.v            ← 16-bit Galois LFSR (free-running at 100 MHz)
├── variants/
│   ├── singleplayer/
│   │   ├── top_fpga.v          ← SP top: pipeline + all peripherals wired up
│   │   ├── mmio_decoder.v      ← SP: routes 0x2000–0x2018 (audio at 0x2018)
│   │   ├── seg7_mux.v          ← SP: 8-digit TDM mux + game glyph dictionary
│   │   ├── constraints/
│   │   │   └── nexys_a7.xdc
│   │   └── game_loop/
│   │       ├── code_dino_game.c
│   │       ├── dino_display.h
│   │       └── dino_mmio.h
│   └── multiplayer/
│       ├── top_fpga.v          ← MP top: adds sw_role, pmod_tx, pmod_rx
│       ├── mmio_decoder.v      ← MP: NET_TX(0x2018) NET_RX(0x201C), no audio
│       ├── seg7_mux_mp.v       ← MP: adds WIN/LOSE text bank
│       ├── constraints/
│       │   └── nexys_a7.xdc    ← MP: adds PMOD JA pin mappings
│       └── game_loop/
│           ├── code_dino_game.c
│           ├── dino_display.h
│           └── dino_mmio.h
├── mem_generator/              ← Software build toolchain
│   ├── crt0.S                  ← Bare-metal startup: sets SP, jumps to main
│   ├── Makefile
│   └── imem_dmem/
│       ├── bin2hex.py          ← ELF binary → Verilog $readmemh hex
│       └── .gitkeep
├── scripts/
│   ├── build_nexys_a7.tcl      ← Full Vivado build (synth + impl + bitstream)
│   └── program_nexys_a7.tcl    ← Flash bitstream to connected board
├── tb/                         ← Testbenches
│   ├── waveforms/              ← Simulation screenshots
│   └── tb_*.v
└── docs/
    └── final_report.pdf
```

---

## Build and Run

### Prerequisites

- Vivado 2020.2 or later (tested on 2025.2)
- `riscv64-unknown-elf-gcc` — ships with Vivado at `C:/AMDDesignTools/<ver>/gnu/riscv/nt/bin/`
- Python 3

### Step 1 — Compile the game

```bash
cd mem_generator
make                          # auto-detects toolchain if on PATH

# Windows PowerShell (explicit toolchain path)
make TOOLCHAIN=C:/AMDDesignTools/2025.2/gnu/riscv/nt/bin/riscv64-unknown-elf-

# Multiplayer variant
make VARIANT=multiplayer
```

Outputs: `mem_generator/imem_dmem/imem.hex` and `dmem.hex`

### Step 2 — Build the bitstream

Run from the **repository root**:

```bash
# Linux / Mac
vivado -mode batch -source scripts/build_nexys_a7.tcl

# Windows
C:/AMDDesignTools/2025.2/Vivado/bin/vivado.bat -mode batch -source scripts/build_nexys_a7.tcl
```

Bitstream lands at `build/vivado/trex_dino_nexys_a7.runs/impl_1/top_fpga.bit`.
Build time: ~5–10 minutes.

### Step 3 — Program the board

Connect the Nexys A7 via USB-JTAG, then:

```bash
vivado -mode batch -source scripts/program_nexys_a7.tcl
```

### Controls

| Button | Action        |
|--------|---------------|
| BTNU   | Jump          |
| BTNL   | Double jump   |
| BTNC   | Reset         |

Score displays on the 7-segment display. LEDs animate on crash. Audio plays on jump, crash, and score milestones.

---

## Contributors

| GitHub | Contributions |
|--------|---------------|
| [@tscube1130](https://github.com/tscube1130) | 3-stage pipeline, math_coproc (MUL/MAC/DIV FSM), instruction rescue buffer, pipeline freeze logic, gameplay fixes, multiplayer PMOD protocol, MP top + mmio_decoder, repo restructure |
| [@ajcoder13](https://github.com/ajcoder13) | All 5 MMIO peripherals RTL (debouncer, LFSR, seg7_mux, LED ctrl, audio driver) + testbenches |
| [@sanjeebani14](https://github.com/sanjeebani14) | Bare-metal C game loop, software build toolchain (Makefile, bin2hex, crt0.S), VGA hardware |
| [@ananya](https://github.com/ananya) | Audio driver integration, top_fpga wiring, seg7 game glyph encoding, mmio_decoder wstrb fixes |
| [@surbhi](https://github.com/surbhi) | XDC constraints, Vivado project setup, top-level integration testbench, FPGA board validation |

---

## Course

**CS224 — Computer Architecture**
Nexys A7-100T (`xc7a100tcsg324-1`) · Xilinx Artix-7

---

*Built from RTL up. No shortcuts.*