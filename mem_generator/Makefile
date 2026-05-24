# RISC-V workload build helper
# Run from mem_generator/:
#   make                             # builds singleplayer (default)
#   make VARIANT=multiplayer         # builds multiplayer variant
#   make WORKLOAD=code_dino_game     # explicit workload name
#   make list                        # list available workloads for active VARIANT
#   make clean

# ── Toolchain auto-detection ──────────────────────────────────────────────────
TOOLCHAIN ?=

ifeq ($(strip $(TOOLCHAIN)),)
ifneq ($(shell command -v riscv64-unknown-elf-gcc 2>/dev/null),)
TOOLCHAIN := riscv64-unknown-elf-
else ifneq ($(wildcard C:/AMDDesignTools/2025.2/gnu/riscv/nt/bin/riscv64-unknown-elf-gcc.exe),)
TOOLCHAIN := C:/AMDDesignTools/2025.2/gnu/riscv/nt/bin/riscv64-unknown-elf-
else ifneq ($(wildcard /c/AMDDesignTools/2025.2/gnu/riscv/nt/bin/riscv64-unknown-elf-gcc.exe),)
TOOLCHAIN := /c/AMDDesignTools/2025.2/gnu/riscv/nt/bin/riscv64-unknown-elf-
else
$(error Could not find riscv64-unknown-elf-gcc. Set TOOLCHAIN=<prefix> or add it to PATH)
endif
endif

CC      := $(TOOLCHAIN)gcc.exe
OBJCOPY := $(TOOLCHAIN)objcopy.exe
PYTHON  ?= python

# ── Variant & workload selection ──────────────────────────────────────────────
VARIANT  ?= singleplayer
WORKLOAD ?= code_dino_game

# C sources live in variants/<VARIANT>/game_loop/ (relative to mem_generator/)
C_DIR   := ../variants/$(VARIANT)/game_loop
OUT_DIR := imem_dmem

SRC      := $(C_DIR)/$(WORKLOAD).c
HDRS     := $(wildcard $(C_DIR)/*.h)
CRT0     := crt0.S
ELF      := $(OUT_DIR)/$(WORKLOAD).elf
IMEM_BIN := $(OUT_DIR)/imem.bin
DMEM_BIN := $(OUT_DIR)/dmem.bin
IMEM_HEX := $(OUT_DIR)/imem.hex
DMEM_HEX := $(OUT_DIR)/dmem.hex

CFLAGS  := -O2 -Wall -Wextra -march=rv32im -mabi=ilp32 \
           -ffreestanding -fno-builtin -msmall-data-limit=0 \
           -I$(C_DIR)
LDFLAGS := -nostdlib -nostartfiles \
           -Wl,-e,_start -Wl,-Ttext=0x00000000 \
           -Wl,--defsym=__stack_top=0x00001FF0

.PHONY: all list compile bins hex clean

all: hex

list:
	@echo "Available workloads for VARIANT=$(VARIANT):"
	@ls $(C_DIR)/*.c | sed -e 's|$(C_DIR)/||' -e 's|\.c$$||'

compile: $(ELF)

$(ELF): $(SRC) $(HDRS) $(CRT0)
	@$(PYTHON) -c "from pathlib import Path; Path('$(OUT_DIR)').mkdir(exist_ok=True)"
	$(CC) $(CFLAGS) $(LDFLAGS) $(CRT0) $< -o $@

bins: compile
	$(OBJCOPY) -O binary \
	    --only-section=.text --only-section=.text.startup --only-section=.init \
	    $(ELF) $(IMEM_BIN)
	-$(OBJCOPY) -O binary \
	    --only-section=.data --only-section=.sdata \
	    --only-section=.rodata \
	    --only-section=.bss --only-section=.sbss \
	    $(ELF) $(DMEM_BIN)
	@$(PYTHON) -c "from pathlib import Path; Path('$(DMEM_BIN)').touch(exist_ok=True)"

hex: bins
	@cd $(OUT_DIR) && $(PYTHON) bin2hex.py
	@echo "Built $(VARIANT)/$(WORKLOAD)"
	@echo "  ELF : $(ELF)"
	@echo "  IMEM: $(IMEM_HEX)"
	@echo "  DMEM: $(DMEM_HEX)"

clean:
	@$(PYTHON) -c "from pathlib import Path; \
	    [p.unlink() for ext in ('*.elf','*.bin','*.hex') \
	     for p in Path('$(OUT_DIR)').glob(ext)]"