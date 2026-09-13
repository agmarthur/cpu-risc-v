// Controle principal RV32I - single cycle
// Opcodes suportados: LUI, AUIPC, JAL, JALR, BRANCH, LOAD, STORE,
// OP-IMM, OP, FENCE (NOP), SYSTEM (NOP, halt tratado no top)
module control (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire       funct7_5,   // instr[30]
    input  wire [6:0] funct7,     // instr[31:25] (para debug/lint)
    output reg        reg_write,
    output reg        mem_read,
    output reg        mem_write,
    output reg  [1:0] mem_to_reg, // 00=ALU, 01=MEM, 10=PC+4
    output reg        alu_src,    // 0=rs2, 1=imm
    output reg        branch,
    output reg        jump,       // JAL
    output reg        jalr,
    output reg  [1:0] alu_a_sel,  // 00=rs1, 01=PC, 10=0
    output reg  [2:0] imm_src,    // 000=I,001=S,010=B,011=U,100=J
    output reg  [3:0] alu_ctrl,
    output reg        is_artvx,   // 1 = instrucao ART-VX custom
    output reg  [1:0] artvx_ctrl  // 00=ADD16, 01=SUB16, 10=MUL16
);
    // Opcodes RV32I
    localparam [6:0] OP_LUI   = 7'b0110111;
    localparam [6:0] OP_AUIPC = 7'b0010111;
    localparam [6:0] OP_JAL   = 7'b1101111;
    localparam [6:0] OP_JALR  = 7'b1100111;
    localparam [6:0] OP_BR    = 7'b1100011;
    localparam [6:0] OP_LOAD  = 7'b0000011;
    localparam [6:0] OP_STORE = 7'b0100011;
    localparam [6:0] OP_IMM   = 7'b0010011;
    localparam [6:0] OP_REG   = 7'b0110011;
    localparam [6:0] OP_FENCE = 7'b0001111;
    localparam [6:0] OP_SYS   = 7'b1110011;
    localparam [6:0] OP_ARTVX = 7'b0001011; // custom-0 (ART-VX 16-bit)
    localparam [6:0] ART_F7   = 7'b0000001; // marca o grupo ART-VX

    // ALU ops (igual alu.v)
    localparam [3:0] A_ADD  = 4'b0000;
    localparam [3:0] A_SUB  = 4'b0001;
    localparam [3:0] A_SLL  = 4'b0010;
    localparam [3:0] A_SLT  = 4'b0011;
    localparam [3:0] A_SLTU = 4'b0100;
    localparam [3:0] A_XOR  = 4'b0101;
    localparam [3:0] A_SRL  = 4'b0110;
    localparam [3:0] A_SRA  = 4'b0111;
    localparam [3:0] A_OR   = 4'b1000;
    localparam [3:0] A_AND  = 4'b1001;

    // Uso de funct7 apenas para evitar warning de bit nao usado no lint.
    // A distincao ADD/SUB e SRL/SRA usa funct7_5 (instr[30]).
    wire _unused_funct7;
    assign _unused_funct7 = ^funct7;

    always @(*) begin
        // Defaults = NOP (evita latch)
        reg_write  = 1'b0;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        mem_to_reg = 2'b00;
        alu_src    = 1'b0;
        branch     = 1'b0;
        jump       = 1'b0;
        jalr       = 1'b0;
        alu_a_sel  = 2'b00;
        imm_src    = 3'b000;
        alu_ctrl   = A_ADD;
        is_artvx   = 1'b0;
        artvx_ctrl = 2'b00;

        case (opcode)
            OP_LUI: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;
                alu_a_sel  = 2'b10; // 0 + imm
                imm_src    = 3'b011; // U
                alu_ctrl   = A_ADD;
                mem_to_reg = 2'b00;
            end
            OP_AUIPC: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;
                alu_a_sel  = 2'b01; // PC + imm
                imm_src    = 3'b011; // U
                alu_ctrl   = A_ADD;
            end
            OP_JAL: begin
                reg_write  = 1'b1;
                jump       = 1'b1;
                imm_src    = 3'b100; // J
                mem_to_reg = 2'b10;  // PC+4
            end
            OP_JALR: begin
                reg_write  = 1'b1;
                jalr       = 1'b1;
                alu_src    = 1'b1;
                imm_src    = 3'b000; // I
                alu_ctrl   = A_ADD;
                mem_to_reg = 2'b10;  // PC+4
            end
            OP_BR: begin
                branch     = 1'b1;
                alu_src    = 1'b0;
                imm_src    = 3'b010; // B
                alu_ctrl   = A_SUB; // nao usado, mantem definido
            end
            OP_LOAD: begin
                reg_write  = 1'b1;
                mem_read   = 1'b1;
                alu_src    = 1'b1;
                imm_src    = 3'b000; // I
                alu_ctrl   = A_ADD;
                mem_to_reg = 2'b01;  // MEM
            end
            OP_STORE: begin
                mem_write  = 1'b1;
                alu_src    = 1'b1;
                imm_src    = 3'b001; // S
                alu_ctrl   = A_ADD;
            end
            OP_IMM: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;
                imm_src    = 3'b000; // I
                case (funct3)
                    3'b000:  alu_ctrl = A_ADD;  // ADDI
                    3'b010:  alu_ctrl = A_SLT;  // SLTI
                    3'b011:  alu_ctrl = A_SLTU; // SLTIU
                    3'b100:  alu_ctrl = A_XOR;  // XORI
                    3'b110:  alu_ctrl = A_OR;   // ORI
                    3'b111:  alu_ctrl = A_AND;  // ANDI
                    3'b001:  alu_ctrl = A_SLL;  // SLLI
                    3'b101:  alu_ctrl = funct7_5 ? A_SRA : A_SRL; // SRAI/SRLI
                    default: alu_ctrl = A_ADD;
                endcase
            end
            OP_REG: begin
                reg_write  = 1'b1;
                alu_src    = 1'b0;
                case (funct3)
                    3'b000:  alu_ctrl = funct7_5 ? A_SUB : A_ADD; // SUB/ADD
                    3'b001:  alu_ctrl = A_SLL; // SLL
                    3'b010:  alu_ctrl = A_SLT; // SLT
                    3'b011:  alu_ctrl = A_SLTU;// SLTU
                    3'b100:  alu_ctrl = A_XOR; // XOR
                    3'b101:  alu_ctrl = funct7_5 ? A_SRA : A_SRL; // SRA/SRL
                    3'b110:  alu_ctrl = A_OR;  // OR
                    3'b111:  alu_ctrl = A_AND; // AND
                    default: alu_ctrl = A_ADD;
                endcase
            end
            OP_FENCE: begin
                // NOP
            end
            OP_ARTVX: begin
                // ART-VX custom 16-bit: R-type, funct7 deve ser 0000001
                if (funct7 == ART_F7) begin
                    reg_write  = 1'b1;
                    alu_src    = 1'b0;
                    mem_to_reg = 2'b00;
                    is_artvx   = 1'b1;
                    case (funct3)
                        3'b000:  artvx_ctrl = 2'b00; // artvx.add
                        3'b001:  artvx_ctrl = 2'b01; // artvx.sub
                        3'b010:  artvx_ctrl = 2'b10; // artvx.mul
                        default: begin
                            is_artvx = 1'b0;
                            reg_write = 1'b0;
                        end
                    endcase
                end
            end
            OP_SYS: begin
                // ECALL/EBREAK = halt tratado no top, sem escrita
            end
            default: begin
                // Instrucao invalida = NOP
            end
        endcase

        // Evita warning de bit nao usado (mistura dummy sem efeito)
        if (_unused_funct7 === 1'bx)
            alu_ctrl = A_ADD;
    end
endmodule
