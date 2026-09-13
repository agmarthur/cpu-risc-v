# Makefile RISC-V RV32I - roda dentro do WSL (Ubuntu + Verilator 5.x)
TOP = cpu
SRC = src/cpu.v src/alu.v src/regfile.v src/imm_gen.v src/branch_unit.v src/control.v src/imem.v src/dmem.v src/uart_tx.v src/uart_rx.v src/artvx.v
TB  = tb/tb_cpu.v
SIM = sim/sim_main.cpp
SIM_CPP = sim/sim_cpp.cpp
SIM_TERM = sim/sim_term.cpp
HEX = prog/program.hex
HEX_ASM = prog/program_asm.hex

all: lint sim

lint:
	verilator --lint-only -Wall --top-module $(TOP) $(SRC)

# Teste ASM original (restaura program_asm.hex antes)
sim-asm: $(HEX_ASM)
	cp $(HEX_ASM) $(HEX)
	verilator --cc --exe --build --trace -j 0 --top-module $(TOP) $(SRC) $(SIM) --Mdir obj_dir
	./obj_dir/Vcpu

sim: $(HEX)
	verilator --cc --exe --build --trace -j 0 --top-module $(TOP) $(SRC) $(SIM) --Mdir obj_dir
	./obj_dir/Vcpu

# Teste firmware C++ (fw/main.cpp -> prog/program.hex)
sim-cpp: $(HEX)
	verilator --cc --exe --build --trace -j 0 --top-module $(TOP) $(SRC) $(SIM_CPP) --Mdir obj_dir_cpp --prefix Vcpu
	./obj_dir_cpp/Vcpu

# Terminal ART-OS (fw/shell.cpp -> prog/program.hex).
# Interativo: make sim-term | Com script: make sim-term ARGS=+script=tests/shell_smoke.txt
sim-term-build: $(HEX)
	verilator --cc --exe --build --trace -j 0 --top-module $(TOP) $(SRC) $(SIM_TERM) --Mdir obj_dir_term --prefix Vcpu

sim-term: sim-term-build
	./obj_dir_term/Vcpu $(ARGS)

# Prepara tudo do ART-OS: firmware shell + simulador (sem rodar)
artos:
	$(MAKE) -C fw shell
	$(MAKE) sim-term-build

iverilog: $(HEX)
	iverilog -g2001 -o tb_cpu.vvp -I src $(SRC) $(TB)
	vvp tb_cpu.vvp

clean:
	rm -rf obj_dir obj_dir_cpp obj_dir_term sim.vcd sim_cpp.vcd sim_term.vcd tb_cpu.vcd tb_cpu.vvp

.PHONY: all lint sim sim-asm sim-cpp sim-term sim-term-build artos iverilog clean
