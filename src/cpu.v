// CPU RISC-V RV32I 32 bits - single cycle + UART full-duplex (MMIO)
// Suporta: LUI, AUIPC, JAL, JALR, BEQ/BNE/BLT/BGE/BLTU/BGEU,
// LB/LH/LW/LBU/LHU, SB/SH/SW, OP-IMM, OP (ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND)
// ECALL/EBREAK (0x00000073 / 0x00100073) -> halt
// MMIO UART (base 0x10000000):
//   0x10000000 TXDATA (W): SW/SB byte baixo transmite
//   0x10000004 STATUS (R): bit0 TX_READY (1=idle), bit1 RX_VALID (1=tem byte)
//   0x10000008 RXDATA (R): LW/LB retorna byte recebido e consome (limpa VALID)
module cpu #(
    parameter IMEM_DEPTH = 1024,
    parameter INIT_FILE = "prog/program.hex",
    parameter UART_CLKS_PER_BIT = 10
) (
    input  wire        clk,
    input  wire        rst,          // sincrono, ativo alto
    input  wire [4:0]  dbg_rs,       // porta debug p/ Verilator (leitura x0-x31)
    input  wire [31:0] dbg_mem_addr, // debug DMEM (byte addr)
    input  wire        rx_i,         // UART RX serial, idle 1
    output wire        tx_o,         // UART TX serial, idle 1
    output wire [31:0] pc_o,
    output wire [31:0] instr_o,
    output wire [31:0] alu_result_o,
    output wire [31:0] wd_o,
    output wire [31:0] dbg_data,
    output wire [31:0] dbg_mem_data,
    output wire        halted_o
);
    // ---------- PC ----------
    reg [31:0] pc;
    reg        halted;
    wire [31:0] pc_plus4;
    wire [31:0] pc_next;
    assign pc_plus4 = pc + 32'd4;
    assign pc_o = pc;
    assign halted_o = halted;

    // ---------- IF ----------
    wire [31:0] instr;
    imem #(
        .DEPTH(IMEM_DEPTH),
        .INIT_FILE(INIT_FILE)
    ) u_imem (
        .addr(pc),
        .instr(instr)
    );
    assign instr_o = instr;

    // ---------- decode fields ----------
    wire [6:0] opcode;
    wire [4:0] rd, rs1, rs2;
    wire [2:0] funct3;
    wire [6:0] funct7;
    wire       funct7_5;
    assign opcode   = instr[6:0];
    assign rd       = instr[11:7];
    assign funct3   = instr[14:12];
    assign rs1      = instr[19:15];
    assign rs2      = instr[24:20];
    assign funct7   = instr[31:25];
    assign funct7_5 = instr[30];

    // ---------- controle ----------
    wire       reg_write, mem_read, mem_write;
    wire [1:0] mem_to_reg;
    wire       alu_src, branch, jump, jalr;
    wire [1:0] alu_a_sel;
    wire [2:0] imm_src;
    wire [3:0] alu_ctrl;
    wire       is_artvx;
    wire [1:0] artvx_ctrl;

    control u_ctrl (
        .opcode(opcode),
        .funct3(funct3),
        .funct7_5(funct7_5),
        .funct7(funct7),
        .reg_write(reg_write),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .mem_to_reg(mem_to_reg),
        .alu_src(alu_src),
        .branch(branch),
        .jump(jump),
        .jalr(jalr),
        .alu_a_sel(alu_a_sel),
        .imm_src(imm_src),
        .alu_ctrl(alu_ctrl),
        .is_artvx(is_artvx),
        .artvx_ctrl(artvx_ctrl)
    );

    // ---------- imediato ----------
    wire [31:0] imm;
    imm_gen u_imm (
        .instr(instr),
        .imm_src(imm_src),
        .imm(imm)
    );

    // ---------- regfile ----------
    wire [31:0] rs1_data, rs2_data;
    wire [31:0] wd;
    regfile u_regfile (
        .clk(clk),
        .rst(rst),
        .we(reg_write & ~halted),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .wd(wd),
        .rd1(rs1_data),
        .rd2(rs2_data)
    );

    // ---------- ALU ----------
    wire [31:0] alu_a, alu_b, alu_result;
    assign alu_a = (alu_a_sel == 2'b01) ? pc
                 : (alu_a_sel == 2'b10) ? 32'd0
                 : rs1_data;
    assign alu_b = alu_src ? imm : rs2_data;

    alu u_alu (
        .a(alu_a),
        .b(alu_b),
        .alu_ctrl(alu_ctrl),
        .result(alu_result)
    );
    assign alu_result_o = alu_result;

    // ---------- branch ----------
    wire branch_taken;
    branch_unit u_branch (
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .funct3(funct3),
        .branch(branch),
        .taken(branch_taken)
    );

    // ---------- DMEM + UART (MMIO) ----------
    // UART_BASE 0x10000000, 16 bytes: TXDATA+0x0 (W), STATUS+0x4 (R), RXDATA+0x8 (R)
    wire is_uart;
    wire is_uart_tx;
    wire is_uart_status;
    wire is_uart_rxdata;
    assign is_uart         = (alu_result[31:4] == 28'h1000000);
    assign is_uart_tx      = is_uart && (alu_result[3:0] == 4'h0);
    assign is_uart_status  = is_uart && (alu_result[3:0] == 4'h4);
    assign is_uart_rxdata  = is_uart && (alu_result[3:0] == 4'h8);

    wire [31:0] mem_rdata;
    wire [31:0] dmem_rdata;
    wire [31:0] uart_rdata;
    dmem #(
        .DEPTH_BYTES(8192),
        .INIT_FILE(INIT_FILE)
    ) u_dmem (
        .clk(clk),
        // DMEM nao responde em MMIO (evita alias com wrap 0xFFF)
        .mem_read(mem_read & ~is_uart),
        .mem_write(mem_write & ~halted & ~is_uart),
        .addr(alu_result),
        .wdata(rs2_data),
        .funct3(funct3),
        .rdata(dmem_rdata),
        .dbg_addr(dbg_mem_addr),
        .dbg_data(dbg_mem_data)
    );

    // UART TX: aceita SW/SB (byte baixo). Leitura STATUS via LW.
    // UART RX: leitura LW/LB em RXDATA retorna byte e consome (pulso rd).
    wire uart_wr;
    wire uart_ready;
    wire [7:0] uart_tx_byte;
    assign uart_wr      = mem_write & ~halted & is_uart_tx;
    assign uart_tx_byte = rs2_data[7:0];

    uart_tx #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT)
    ) u_uart (
        .clk(clk),
        .rst(rst),
        .wr(uart_wr),
        .data_in(uart_tx_byte),
        .ready(uart_ready),
        .tx_o(tx_o)
    );

    wire uart_rx_rd;
    wire uart_rx_valid;
    wire [7:0] uart_rx_byte;
    // LOAD em RXDATA consome o byte (strobe de 1 ciclo, single-cycle)
    assign uart_rx_rd = mem_read & ~halted & is_uart_rxdata;

    uart_rx #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT)
    ) u_uart_rx (
        .clk(clk),
        .rst(rst),
        .rx_i(rx_i),
        .rd(uart_rx_rd),
        .data_o(uart_rx_byte),
        .valid(uart_rx_valid)
    );

    // Leitura MMIO:
    //   STATUS bit0=TX_READY, bit1=RX_VALID
    //   TXDATA retorna ultimo byte (debug, sem efeito colateral)
    //   RXDATA retorna byte recebido e consome (limpa VALID)
    reg [31:0] uart_rdata_r;
    always @(*) begin
        if (is_uart_status)
            uart_rdata_r = {30'd0, uart_rx_valid, uart_ready};
        else if (is_uart_rxdata)
            uart_rdata_r = {24'd0, uart_rx_byte};
        else if (is_uart_tx)
            uart_rdata_r = {24'd0, uart_tx_byte};
        else
            uart_rdata_r = 32'd0;
    end
    assign uart_rdata = uart_rdata_r;
    assign mem_rdata = is_uart ? uart_rdata : dmem_rdata;

    // ---------- ART-VX (SIMD 2x16 custom) ----------
    // Opera direto em rs1/rs2 (empacotados), resultado vai p/ writeback.
    wire [31:0] artvx_result;
    artvx u_artvx (
        .a(rs1_data),
        .b(rs2_data),
        .ctrl(artvx_ctrl),
        .result(artvx_result)
    );

    // ---------- writeback ----------
    // is_artvx tem prioridade sobre ALU (mas perde p/ MEM e PC+4,
    // que nao ocorrem junto com ART-VX pelo decode).
    wire [31:0] alu_or_vec;
    assign alu_or_vec = is_artvx ? artvx_result : alu_result;
    assign wd = (mem_to_reg == 2'b01) ? mem_rdata
              : (mem_to_reg == 2'b10) ? pc_plus4
              : alu_or_vec;
    assign wd_o = wd;

    // ---------- debug (leitura de x0-x31 sem hierarquia no C++) ----------
    // Sintetizavel: apenas um mux a mais; amarre dbg_rs=0 se nao usar.
    assign dbg_data = (dbg_rs == 5'd0) ? 32'd0 : u_regfile.regs[dbg_rs];

    // ---------- proximo PC ----------
    wire [31:0] jalr_target;
    assign jalr_target = (rs1_data + imm) & 32'hFFFFFFFE;

    wire [31:0] branch_jump_target;
    assign branch_jump_target = pc + imm;

    assign pc_next = halted ? pc
                   : jalr ? jalr_target
                   : (jump || branch_taken) ? branch_jump_target
                   : pc_plus4;

    // ---------- ECALL/EBREAK -> halt ----------
    wire is_ecall;
    assign is_ecall = (instr == 32'h00000073) || (instr == 32'h00100073);

    always @(posedge clk) begin
        if (rst) begin
            pc <= 32'd0;
            halted <= 1'b0;
        end else begin
            if (is_ecall)
                halted <= 1'b1;
            if (!halted)
                pc <= pc_next;
        end
    end
endmodule
