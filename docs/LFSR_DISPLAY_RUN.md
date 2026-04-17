# LFSR Display Guide (RISC-V CPU Driven)

## What This Demo Shows
This demo runs on the RISC-V pipeline and writes to the 8-digit 7-segment display through MMIO.

Current layout:
- Digit 7 to Digit 4: game area (4 digits)
- Digit 3 to Digit 0: score (4 digits)

Character encoding used by the display logic:
- `0x0` to `0x9`: decimal digits
- `0xA`: blank
- `0xB`: dino (ground)
- `0xC`: dino (jump)
- `0xD`: cactus

MMIO used:
- `0x2010` (`MMIO_SEG_W0`): digits 3..0 packed as nibbles
- `0x2014` (`MMIO_SEG_W1`): digits 7..4 packed as nibbles
- `0x2008` (`MMIO_LFSR_R`): LFSR random value

---

## How To Run

Use this exact flow so the bitstream always embeds the latest `imem.hex` / `dmem.hex`.

### 1. Build the workload (Git Bash)

```bash
cd "/c/Users/SANJEEBANI PARIDA/CS224-Project/software/mem_generator"
make WORKLOAD=code_lfsr_demo
```

Notes:
- The Makefile now auto-detects the AMD RISC-V toolchain at
	`/c/AMDDesignTools/2025.2/gnu/riscv/nt/bin/` if it is not on `PATH`.
- Output files are generated at:
	- `software/mem_generator/imem_dmem/imem.hex`
	- `software/mem_generator/imem_dmem/dmem.hex`

### 2. Build bitstream (batch Vivado)

From repo root:

```bash
cd "/c/Users/SANJEEBANI PARIDA/CS224-Project"
/c/AMDDesignTools/2025.2/Vivado/bin/vivado.bat -mode batch -source scripts/build_nexys_a7.tcl
```

This script creates/updates the project in `build/vivado/` and copies BRAM init files into the synthesis run directory so `$readmemh` resolves correctly.

### 3. Program board (batch Vivado)

```bash
cd "/c/Users/SANJEEBANI PARIDA/CS224-Project"
/c/AMDDesignTools/2025.2/Vivado/bin/vivado.bat -mode batch -source scripts/program_nexys_a7.tcl
```

After programming, tap `BTNC` once to restart the game loop.

Expected behavior:
- Dino stays on the left side.
- Cactus appears and moves across game digits.
- Score updates on the rightmost 4 digits.

---

## Notes For Team (Safe Integration)
- Keep this CPU-driven path as the final mode.
- Avoid committing temporary hardware-only display bypass logic.
- Keep only source changes needed for display packing and workload behavior.
- If display is fully blank, first rebuild workload + bitstream using the script flow above. A stale or missing BRAM init file is the most common cause.

---

## Next Steps
1. Merge this 4-game / 4-score layout with full gameplay state (jump + collision).
2. Add a compile-time switch for display layout (`4+4` now, `8+0` later if needed).
3. Add a short hardware validation checklist to PR (build, program, expected display sequence).
4. Finalize one team-approved workload (`code_lfsr_demo` or full game) for demo day.
