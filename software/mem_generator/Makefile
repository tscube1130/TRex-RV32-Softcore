# RISC-V workload build helper for mem_generator
# Usage:
#   make list
#   make WORKLOAD=code_factorial
#   make WORKLOAD=code_dot_product

TOOLCHAIN ?= riscv64-unknown-elf-
CC       := $(TOOLCHAIN)gcc
OBJCOPY  := $(TOOLCHAIN)objcopy
PYTHON   ?= python

WORKLOAD ?= code_addition
C_DIR    := c_workloads
OUT_DIR  := imem_dmem

SRC      := $(C_DIR)/$(WORKLOAD).c
ELF      := $(OUT_DIR)/$(WORKLOAD).elf
IMEM_BIN := $(OUT_DIR)/imem.bin
DMEM_BIN := $(OUT_DIR)/dmem.bin
IMEM_HEX := $(OUT_DIR)/imem.hex
DMEM_HEX := $(OUT_DIR)/dmem.hex

CFLAGS   := -O0 -Wall -Wextra -march=rv32im -mabi=ilp32 -ffreestanding -fno-builtin
LDFLAGS  := -nostdlib -nostartfiles -Wl,-e,main -Wl,-Ttext=0x00000000 -Wl,--no-relax

.PHONY: all list compile bins hex clean

all: hex

list:
	@echo "Available workloads:"
	@ls $(C_DIR)/*.c | sed -e 's|$(C_DIR)/||' -e 's|\.c$$||'

compile: $(ELF)

$(ELF): $(SRC)
	@mkdir -p $(OUT_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) $< -o $@

bins: compile
	$(OBJCOPY) -O binary --only-section=.text --only-section=.text.startup --only-section=.init $(ELF) $(IMEM_BIN)
	$(OBJCOPY) -O binary --only-section=.data --only-section=.sdata --only-section=.rodata --only-section=.bss --only-section=.sbss $(ELF) $(DMEM_BIN) || true
	@test -f $(DMEM_BIN) || : > $(DMEM_BIN)

hex: bins
	@cd $(OUT_DIR) && $(PYTHON) bin2hex.py
	@echo "Built $(WORKLOAD)"
	@echo "  ELF : $(ELF)"
	@echo "  IMEM: $(IMEM_HEX)"
	@echo "  DMEM: $(DMEM_HEX)"

clean:
	rm -f $(OUT_DIR)/*.elf $(OUT_DIR)/*.bin $(OUT_DIR)/*.hex
