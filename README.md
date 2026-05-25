# 🦕 T-Rex RV32IM Softcore

> **A custom 3-stage RISC-V CPU built from RTL, running a Chrome Dino-style game on a Nexys A7 FPGA.**
> Not a simulator. Not a pre-built core. Every pipeline stage, every peripheral, every stall — *written from scratch*.

![Board](https://img.shields.io/badge/Board-Nexys%20A7--100T-blue)
![ISA](https://img.shields.io/badge/ISA-RV32IM%20%2B%20custom%20MAC-brightgreen)
![Language](https://img.shields.io/badge/RTL-Verilog-orange)
![Software](https://img.shields.io/badge/Software-Bare--metal%20C-yellow)
![Course](https://img.shields.io/badge/Course-CS224%20Hardware%20Lab-red)
![Status](https://img.shields.io/badge/Status-Working%20on%20Hardware-success)

▶️ **[Watch the Full Hardware Demo Video](https://drive.google.com/file/d/17m9wm5FIrqAU7nTJ8lChxJ3AP9USiL5a/view?usp=sharing)**

---

## 💡 What Is This?

Project T-Rex is a full hardware-software co-design on a **Nexys A7-100T FPGA**. The CPU is a 3-stage RV32IM pipeline built entirely in Verilog, extended with a custom math coprocessor (featuring a single-cycle DSP multiply, a 33-cycle-stall iterative divider, and a MAC accumulator). 

Running natively on top of this is a bare-metal C game:
* 🌵 Obstacles spawn via a hardware **LFSR**.
* 💯 Score tracks on an **8-digit 7-segment display**.
* 🔊 Audio feedback plays on jump and crash events.
* ⚔️ **Multiplayer mode** links two FPGA boards over PMOD GPIO.

Two clock domains, five custom MMIO peripherals, one instruction rescue buffer, and **zero operating system.**

---

## 🚀 Build and Run

### Prerequisites
* **Vivado** 2020.2 or later (tested on 2025.2)
* `riscv64-unknown-elf-gcc` (ships with Vivado at `C:/AMDDesignTools/<ver>/gnu/riscv/nt/bin/`)
* **Python 3**

### Step 1 — Compile the Game

```bash
cd mem_generator

# Build singleplayer (default)
make 

# OR Build multiplayer variant
make VARIANT=multiplayer
```

*(Outputs `imem.hex` and `dmem.hex` to `mem_generator/imem_dmem/`)*

### Step 2 — Build the Bitstream

Run this from the **repository root**:

```bash
# Linux / Mac
vivado -mode batch -source scripts/build_nexys_a7.tcl

# Windows
C:/AMDDesignTools/2025.2/Vivado/bin/vivado.bat -mode batch -source scripts/build_nexys_a7.tcl
```

*(Bitstream lands at `build/vivado_singleplayer/trex_dino_nexys_a7.runs/impl_1/top_fpga.bit`. Build time: ~5–10 minutes.)*

### Step 3 — Program the Board

```bash
C:/AMDDesignTools/2025.2/Vivado/bin/vivado.bat -mode batch -source scripts/program_nexys_a7.tcl
```

### 🎮 Game Controls

| Button | Action |
| --- | --- |
| **BTNU** | Jump |
| **BTNL** | Double jump |
| **BTNC** | Reset Game |

---

## 🏗️ System Architecture

```text
                    100 MHz Board Clock (clk)
                                │
          ┌─────────────────────┴─────────────────────┐
          │            Clock Divider ÷100             │
          │             slow_clk ≈ 1 MHz              │
          └─────────────────────┬─────────────────────┘
                                │
        ┌───────────────────────┴───────────────────────┐
        │              RISC-V Pipeline (slow_clk)       │
        │                                               │
        │  ┌─────────────────────────────────────────┐  │
        │  │          IF/ID  →  EX  →  WB            │  │
        │  │               math_coproc               │  │
        │  │        MUL(1)   DIV(34)   MAC(1)        │  │
        │  └────────────────────┬────────────────────┘  │
        │        │              │              │        │
        │      IMEM             │            DMEM       │
        │     (BRAM)            │           (BRAM)      │
        │                       │                       │
        │                 MMIO Decoder                  │
        │               (0x2000 – 0x201C)               │
        └───────────────────────┬───────────────────────┘
                                │
        ┌───────────────────────┴───────────────────────┐
        │             Fast Peripherals (100 MHz)        │
        │                                               │
        │ [seg7_mux]  [lfsr16]  [debouncer] [audio_drv] │
        └───────────────────────────────────────────────┘
```

> [!NOTE] 
> **Why two clock domains?** The 7-segment mux needs a fast switching rate (125 Hz per digit) to appear flicker-free. The LFSR needs to look random. The debouncer needs a 10 ms settle window. All of that requires 100 MHz. The pipeline runs at 1 MHz to keep MMIO debugging deterministic and to match the game timing. The clock crossing is safely handled by registered latches and sticky flags.

---

## 📂 Repository Structure

```text
TRex-RV32-Softcore/
├── src/
│   ├── core/                   ← RV32IM pipeline RTL (IF/ID, EX, MEM, WB, Math)
│   └── peripherals/            ← MMIO peripheral RTL (Audio, Debouncer, LED, LFSR)
├── variants/
│   ├── singleplayer/           ← Standard game (Audio enabled, standard constraints)
│   └── multiplayer/            ← 2-Player mode (PMOD networking, WIN/LOSE text)
├── mem_generator/              ← Bare-metal C toolchain, Makefile, & linker scripts
├── scripts/                    ← TCL automation for Vivado building & flashing
├── tb/                         ← Verilog testbenches & simulation waveforms
└── docs/                       ← Final report & project abstract
```

---

## ⏱️ Pipeline Mechanics

### Stages
Three stages: **Instruction Fetch + Decode** ➡️ **Execute** (ALU + Math Coprocessor) ➡️ **Writeback**. Register forwarding handles data hazards. Branch outcomes resolve in EX — one bubble on taken branches.

### Stall and Freeze Logic
`DIV` is the only multi-cycle instruction. When a `DIV`/`DIVU`/`REM`/`REMU` enters the Execute stage:
1. `math_coproc.v` raises `math_stall` combinationally.
2. `pipeline.v` computes `pipeline_freeze = stall_read | div_stall_w`.
3. The freeze gates the PC advance, IF/ID register, EX stage, WB stage, and regfile write enable.

### The Instruction Rescue Buffer
BRAM instruction fetch has a 1-cycle registered latency. When the pipeline freezes mid-fetch, the BRAM output for the *next* instruction is already on the wire — but the IF/ID register is frozen and will drop it. 

**The fix:** A rescue buffer in `pipeline.v` snatches `inst_mem_read_data` the moment the stall hits and safely holds it. When the pipeline unfreezes, it reads from the rescue buffer for exactly one cycle before switching back to BRAM. *Zero instruction corruption.*

| Instruction Class | EX Cycles | Stall Cycles |
| --- | --- | --- |
| **All RV32I** (ADD, LW, BEQ…) | 1 | 0 |
| **MUL / MULH / MULHU / MULHSU** | 1 | 0 |
| **MAC** (custom) | 1 | 0 |
| **DIV / DIVU / REM / REMU** | 34 | 33 |

*(The game loop calls DIV exactly once per frame, so the 34-cycle occupancy has no visible impact on gameplay).*

---

## 🧮 Math Coprocessor (`math_coproc.v`)

### MUL (1-Cycle)
Sign-extends operands to 33 bits to handle all four variants seamlessly. The 66-bit product is computed in a single cycle, explicitly mapped to DSP slices via `(* use_dsp = "yes" *)`.

### DIV — Iterative Shift-Subtract FSM (34-Cycle)

```text
       div_start=0                  div_start=1
  ┌──────────────────┐         ┌──────────────────┐
  │                  │────────▶│                  │
  │     DIV_IDLE     │         │   DIV_RUNNING    │
  │  math_stall = 0  │         │  math_stall = 1  │
  │                  │         │   (×32 cycles)   │
  └──────────────────┘         └────────┬─────────┘
           ▲                            │ count == 31
           │                            │
           │                   ┌────────▼─────────┐
           └───────────────────│     DIV_DONE     │
                               │  math_stall = 0  │
                               └──────────────────┘
```

*(Edge cases like divide-by-zero or `INT_MIN / -1` bypass the FSM and resolve combinationally without stalling).*

### MAC — Custom Instruction
Fuses `MUL` + `ADD` into one opcode (`funct7 = 7'b0000010`). A hidden 32-bit accumulator register holds the running sum, which can be read back via the custom `MVACC` instruction.

---

## 🔌 MMIO Peripheral Map

Both variants share `0x2000–0x2014`. Singleplayer adds audio at `0x2018`; multiplayer replaces it with the PMOD network interface.

| Address | R/W | Name | Description |
| --- | --- | --- | --- |
| `0x2000` | **R** | `MMIO_SW_R` | `bit[0]`=jump sticky, `bit[1]`=dbl-jump sticky |
| `0x2004` | **W** | `MMIO_SW_CLR`| Write `1`/`2`/`3` to clear jump / dbl-jump / both |
| `0x2008` | **R** | `MMIO_LFSR_R`| 16-bit LFSR value (`bit[0]`=cactus type) |
| `0x200C` | **W** | `MMIO_LED_W` | 16-bit LED pattern (crash animation) |
| `0x2010` | **W** | `MMIO_SEG_W0`| 7-seg digits 3–0 (nibble-packed BCD) |
| `0x2014` | **W** | `MMIO_SEG_W1`| 7-seg digits 7–4 (nibble-packed BCD) |
| `0x2018` | **W** | `MMIO_AUDIO` | **(SP only)** — `bit[0]`=jump tone, `bit[1]`=crash tone |
| `0x2018` | **W** | `MMIO_NET_TX`| **(MP only)** — `bit[0]`=PMOD TX pin (pulse protocol) |
| `0x201C` | **R** | `MMIO_NET_RX`| **(MP only)** — `bit[0]`=PMOD RX pin, `bit[1]`=role SW[15] |

> [!IMPORTANT]
> **The Sticky Debouncer:** Because the CPU cannot read MMIO during a 33-cycle math freeze, a pure software polling approach would silently drop button inputs. Our debouncer latches button presses in hardware and holds them until the CPU explicitly clears them via `MMIO_SW_CLR`, guaranteeing zero lost inputs.

---

## ⚔️ Multiplayer Mode

Two Nexys A7 boards linked via PMOD GPIO. Each board runs an independent game instance; a bit-bang pulse protocol synchronises game events in real time. Role (host/client) is determined by `SW[15]`. 

---

## 📊 Resource Utilization (Singleplayer)

*Post-Place metrics on Nexys A7-100T (xc7a100tcsg324-1)*

| Resource | Used | Available | Utilization |
| --- | --- | --- | --- |
| **Slice LUTs** | 3,325 | 63,400 | 5.24% |
| **Slice Registers** | 1,722 | 126,800 | 1.36% |
| **Block RAM** | 1 | 135 | 0.74% |
| **DSP48E1** | 5 | 240 | 2.08% |

*(The register file is correctly inferred as Distributed RAM, and DSP slicing is highly effective for the Math Coprocessor).*

---

## 👥 Contributors

| GitHub | Key Contributions |
| --- | --- |
| [@tscube1130](https://github.com/tscube1130) | 3-stage pipeline, Math Coprocessor (MUL/MAC/DIV FSM), Rescue buffer, Pipeline stall logic, Multiplayer PMOD protocol |
| [@ajcoder13](https://github.com/ajcoder13) | All 5 MMIO peripherals RTL (Debouncer, LFSR, seg7_mux, LED ctrl, Audio driver) & Testbenches |
| [@sanjeebani14](https://github.com/sanjeebani14) | Bare-metal C game loop, Software build toolchain (Makefile, bin2hex, crt0.S) |
| [@b-ananya241](https://github.com/b-ananya241) | Audio integration, top_fpga wiring, seg7 game glyph encoding, mmio_decoder wstrb fixes |
| [@surbhi-24](https://github.com/surbhi-24) | XDC constraints, Vivado setup, Top-level integration testbench, FPGA board validation |

---

## 🎓 Course Details

**CS224 — Hardware Lab** Department of Computer Science and Engineering · Indian Institute of Technology Guwahati  
*Certified by Prof. Lokesh Siddhu · [Certificate](docs/certificate.pdf)*

***Built from RTL up. No shortcuts.***