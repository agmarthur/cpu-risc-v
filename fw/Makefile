# Toolchain C++ -> RV32I bare-metal (roda dentro do WSL)
PREFIX  = riscv64-unknown-elf
CXX     = $(PREFIX)-g++
AS      = $(PREFIX)-g++
OBJCOPY = $(PREFIX)-objcopy
OBJDUMP = $(PREFIX)-objdump
SIZE    = $(PREFIX)-size

ARCH = -march=rv32i -mabi=ilp32

CXXFLAGS = $(ARCH) -O2 -std=c++17 -ffreestanding -nostdlib \
           -fno-exceptions -fno-rtti -fno-builtin -Wall -Wno-array-bounds \
           -mno-relax -msmall-data-limit=0
ASFLAGS  = $(ARCH) -mno-relax
LDFLAGS  = $(ARCH) -nostdlib -T mem.ld -Wl,--no-relax -Wl,--no-gc-sections

BUILD = build
ELF = $(BUILD)/fw.elf
BIN = $(BUILD)/fw.bin
HEX = $(BUILD)/program.hex
LST = $(BUILD)/fw.lst

# ART-OS: shell com terminal interativo (prompt art>)
SHELL_OBJ = $(BUILD)/shell.o
SHELL_ELF = $(BUILD)/shell.elf
SHELL_BIN = $(BUILD)/shell.bin
SHELL_HEX = $(BUILD)/program_shell.hex

all: $(HEX)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/start.o: start.S | $(BUILD)
	$(AS) $(ASFLAGS) -c $< -o $@

$(BUILD)/main.o: main.cpp uart.h artvx.h os.h | $(BUILD)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(ELF): $(BUILD)/start.o $(BUILD)/main.o mem.ld
	$(CXX) $(LDFLAGS) $(BUILD)/start.o $(BUILD)/main.o -lgcc -o $@
	$(SIZE) $@

$(LST): $(ELF)
	$(OBJDUMP) -d -Mnumeric $< > $@

$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@

$(HEX): $(BIN) elf2hex.py
	python3 elf2hex.py $(BIN) $(HEX)
	python3 elf2hex.py $(BIN) ../prog/program.hex
	$(MAKE) dump

dump: $(ELF)
	$(OBJDUMP) -d -Mnumeric $(ELF) > $(LST)
	@echo "--- fw.lst (primeiras 60 linhas) ---"
	@head -60 $(LST)

# Roda o firmware na CPU (build + Verilator). Use dentro de fw/.
run: $(HEX)
	$(MAKE) -C .. sim-cpp

# ART-OS: compila o shell e instala como programa da CPU
shell: $(SHELL_HEX)

$(BUILD)/shell.o: shell.cpp uart.h artvx.h os.h | $(BUILD)
	$(CXX) $(filter-out -O2,$(CXXFLAGS)) -Os -c $< -o $@

$(SHELL_ELF): $(BUILD)/start.o $(BUILD)/shell.o mem.ld
	$(CXX) $(LDFLAGS) $(BUILD)/start.o $(BUILD)/shell.o -lgcc -o $@
	$(SIZE) $@

$(SHELL_BIN): $(SHELL_ELF)
	$(OBJCOPY) -O binary $< $@

$(SHELL_HEX): $(SHELL_BIN) elf2hex.py
	python3 elf2hex.py $(SHELL_BIN) $(SHELL_HEX)
	python3 elf2hex.py $(SHELL_BIN) ../prog/program.hex
	$(OBJDUMP) -d -Mnumeric $(SHELL_ELF) > $(BUILD)/shell.lst
	@echo "--- shell.lst (primeiras 40 linhas) ---"
	@head -40 $(BUILD)/shell.lst

# Roda o ART-OS no terminal simulado (interativo ou +script=)
run-shell: shell
	$(MAKE) -C .. sim-term

clean:
	rm -rf $(BUILD)

.PHONY: all dump run shell run-shell clean
