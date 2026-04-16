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

### 1. Build the workload
From repository root in PowerShell:

```powershell
cd D:\CS224\CS224-Project\software\mem_generator
make WORKLOAD=code_lfsr_demo
```

This generates:
- `software/mem_generator/imem_dmem/imem.hex`
- `software/mem_generator/imem_dmem/dmem.hex`

### 2. Copy memory files to Vivado project folder

```powershell
Copy-Item "D:\CS224\CS224-Project\software\mem_generator\imem_dmem\imem.hex" "D:\CS224\cs224proj\" -Force
Copy-Item "D:\CS224\CS224-Project\software\mem_generator\imem_dmem\dmem.hex" "D:\CS224\cs224proj\" -Force
```

### 3. Rebuild in Vivado
In Vivado:
1. Reset `synth_1`
2. Reset `impl_1`
3. Run Synthesis
4. Run Implementation
5. Generate Bitstream

### 4. Program board
Use Hardware Manager, then press `BTNC` once (about 1 second).

Expected behavior:
- Dino stays on the left side.
- Cactus appears and moves across game digits.
- Score updates on the rightmost 4 digits.

---

## Notes For Team (Safe Integration)
- Keep this CPU-driven path as the final mode.
- Avoid committing temporary hardware-only display bypass logic.
- Keep only source changes needed for display packing and workload behavior.

---

## Next Steps
1. Merge this 4-game / 4-score layout with full gameplay state (jump + collision).
2. Add a compile-time switch for display layout (`4+4` now, `8+0` later if needed).
3. Add a short hardware validation checklist to PR (build, program, expected display sequence).
4. Finalize one team-approved workload (`code_lfsr_demo` or full game) for demo day.
