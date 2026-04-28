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

---

## Multiplayer Build and Run

The multiplayer variant enables two Nexys A7 boards to compete in Chrome Dino simultaneously, communicating via PMOD GPIO over a pulse protocol. Each board runs the same game logic but with real-time opponent state updates.

### Prerequisites for Multiplayer

- Two Nexys A7-100T boards
- PMOD connector cable (connects GPIO between boards, implements hand-shake protocol)
- All single-player prerequisites (Vivado, RISC-V toolchain, Python 3)

### 1. Compile the multiplayer game workload

The multiplayer software lives under `Multiplayer/software/mem_generator`. The build process is identical to single-player:

```bash
cd Multiplayer/software/mem_generator
make
```

Or specify a workload explicitly:

```bash
make WORKLOAD=code_dino_game
```

This generates `imem_dmem/imem.hex` and `imem_dmem/dmem.hex` for BRAM initialization.

### 2. Build the multiplayer FPGA bitstream

The multiplayer hardware variant uses:
- Top module: `Multiplayer/src/3-stage-pipeline/top_fpga.v`
- Board constraints: `Multiplayer/constraints/nexys_a7.xdc`
- Peripheral modules: `Multiplayer/src/*.v`

**Option A: Using Vivado GUI** (recommended for first-time multiplayer setup)

1. Open Vivado
2. Create a new project:
   - Project name: `trex_dino_nexys_a7_mp`
   - Location: `<repo>/build/vivado_multiplayer/`
   - Part: `xc7a100tcsg324-1`
3. Add source files:
   - Add all Verilog files from `Multiplayer/src/3-stage-pipeline/` and `Multiplayer/src/`
   - Add constraint file: `Multiplayer/constraints/nexys_a7.xdc`
   - Add memory files: `Multiplayer/software/mem_generator/imem_dmem/imem.hex` and `dmem.hex`
4. Set `Multiplayer/src/3-stage-pipeline/top_fpga.v` as the top module
5. Run Synthesis → Implementation → Generate Bitstream

**Option B: Using Vivado batch mode**

Create a Vivado TCL script `scripts/build_nexys_a7_multiplayer.tcl` (template provided below), then run:

```bash
C:/AMDDesignTools/2025.2/Vivado/bin/vivado.bat -mode batch -source scripts/build_nexys_a7_multiplayer.tcl
```

**TCL Script Template** (`scripts/build_nexys_a7_multiplayer.tcl`):

```tcl
# Build the Project T-Rex Multiplayer bitstream for Nexys A7-100T.
#
# Run from the repository root:
#   C:/AMDDesignTools/2025.2/Vivado/bin/vivado.bat -mode batch -source scripts/build_nexys_a7_multiplayer.tcl

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir ".."]]
set build_dir  [file join $repo_root "build" "vivado_multiplayer"]
set proj_name  "trex_dino_nexys_a7_mp"
set part_name  "xc7a100tcsg324-1"

cd $repo_root
file mkdir $build_dir

create_project -force $proj_name $build_dir -part $part_name
set_property target_language Verilog [current_project]
set_property simulator_language Verilog [current_project]
set_property source_mgmt_mode None [current_project]

set mp_src_dir [file join $repo_root "Multiplayer" "src"]
set mp_pipe_dir [file join $mp_src_dir "3-stage-pipeline"]

add_files -fileset sources_1 -norecurse [list \
    [file join $mp_pipe_dir "top_fpga.v"] \
    [file join $mp_pipe_dir "pipeline.v"] \
    [file join $mp_pipe_dir "memory.v"] \
    [file join $mp_src_dir "audio_driver.v"] \
    [file join $mp_src_dir "math_coproc.v"] \
    [file join $mp_src_dir "mmio_decoder.v"] \
    [file join $mp_src_dir "debouncer.v"] \
    [file join $mp_src_dir "lfsr16.v"] \
    [file join $mp_src_dir "led_ctrl.v"] \
    [file join $mp_src_dir "seg7_mux.v"] \
]

set_property include_dirs [list $mp_pipe_dir] [get_filesets sources_1]

set imem_hex [file join $repo_root "Multiplayer" "software" "mem_generator" "imem_dmem" "imem.hex"]
set dmem_hex [file join $repo_root "Multiplayer" "software" "mem_generator" "imem_dmem" "dmem.hex"]
add_files -fileset sources_1 -norecurse [list $imem_hex $dmem_hex]

# Copy BRAM init files to synthesis directory
set synth_dir [file join $build_dir "$proj_name.runs" "synth_1"]
file mkdir $synth_dir
file copy -force $imem_hex [file join $synth_dir "imem.hex"]
file copy -force $dmem_hex [file join $synth_dir "dmem.hex"]

add_files -fileset constrs_1 -norecurse [list [file join $repo_root "Multiplayer" "constraints" "nexys_a7.xdc"]]

set_property target_language Verilog [current_project]
set_property simulator_language Verilog [current_project]
set_property source_mgmt_mode None [current_project]

update_compile_order -fileset sources_1
update_compile_order -fileset constrs_1

synth_design -top top_fpga -part $part_name

opt_design
place_design
route_design

report_utilization -file [file join $build_dir "utilization.txt"]
write_bitstream -force [file join $build_dir "$proj_name.bit"]

puts "Bitstream generated: [file join $build_dir "$proj_name.bit"]"
```

### 3. Program both Nexys A7 boards

After generating the bitstream, program both boards using Vivado Hardware Manager:

1. Connect the first Nexys A7 to your computer via USB
2. Open Vivado → Hardware Manager → Open Target → Auto Connect
3. Select the connected board → Program Device → Select `trex_dino_nexys_a7_mp.bit`
4. Repeat for the second board (may need to use a USB hub or program sequentially)

Alternatively, create a programming script `scripts/program_nexys_a7_multiplayer.tcl` following the same pattern as the single-player version in `scripts/program_nexys_a7.tcl`.

### 4. Connect the boards via PMOD GPIO

- Use a PMOD connector cable to link GPIO pins between the two boards
- Consult `Multiplayer/constraints/nexys_a7.xdc` to identify which PMOD pins implement the pulse protocol
- The boards will auto-detect each other and begin synchronization once both are powered on and programmed

### Troubleshooting Multiplayer

- **Boards not synchronizing**: Check PMOD cable connections and verify both boards are programmed with the same bitstream
- **Score or position misalignment**: Pulse protocol timing may be off; verify clock divider settings match between both boards (see Clock Configuration section below)
- **One board crashing**: Check MMIO collision detection logic; obstacles may spawn at incompatible positions on different boards

### Notes

- Target board: Nexys A7-100T (`xc7a100tcsg324-1`)
- The CPU game path uses `src/top_fpga.v`; the VGA build uses `src/top_fpga_with_vga.v`
- If you change the C workload, rebuild `imem.hex` and `dmem.hex` before rerunning Vivado
- For single-player builds: use `src/` and `constraints/` (standard paths)
- For multiplayer builds: use `Multiplayer/src/` and `Multiplayer/constraints/` with `Multiplayer/software/mem_generator/` for hex files

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
