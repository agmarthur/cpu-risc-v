// ALU RV32I - operacoes base
// alu_ctrl:
//  0000 ADD, 0001 SUB, 0010 SLL, 0011 SLT, 0100 SLTU,
//  0101 XOR, 0110 SRL, 0111 SRA, 1000 OR, 1001 AND
module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  alu_ctrl,
    output reg  [31:0] result
);
    wire [4:0] shamt;
    assign shamt = b[4:0];

    always @(*) begin
        case (alu_ctrl)
            4'b0000: result = a + b;                              // ADD
            4'b0001: result = a - b;                              // SUB
            4'b0010: result = a << shamt;                         // SLL
            4'b0011: result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0; // SLT
            4'b0100: result = (a < b) ? 32'd1 : 32'd0;            // SLTU
            4'b0101: result = a ^ b;                              // XOR
            4'b0110: result = a >> shamt;                         // SRL
            4'b0111: result = $signed(a) >>> shamt;               // SRA
            4'b1000: result = a | b;                              // OR
            4'b1001: result = a & b;                              // AND
            default: result = 32'd0;
        endcase
    end
endmodule
