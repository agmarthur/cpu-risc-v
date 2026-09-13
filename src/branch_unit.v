// Unidade de desvio condicional (BRANCH)
// funct3: 000 BEQ, 001 BNE, 100 BLT, 101 BGE, 110 BLTU, 111 BGEU
module branch_unit (
    input  wire [31:0] rs1_data,
    input  wire [31:0] rs2_data,
    input  wire [2:0]  funct3,
    input  wire        branch,
    output reg         taken
);
    always @(*) begin
        if (!branch) begin
            taken = 1'b0;
        end else begin
            case (funct3)
                3'b000:  taken = (rs1_data == rs2_data);                 // BEQ
                3'b001:  taken = (rs1_data != rs2_data);                 // BNE
                3'b100:  taken = ($signed(rs1_data) < $signed(rs2_data));// BLT
                3'b101:  taken = ($signed(rs1_data) >= $signed(rs2_data));// BGE
                3'b110:  taken = (rs1_data < rs2_data);                  // BLTU
                3'b111:  taken = (rs1_data >= rs2_data);                 // BGEU
                default: taken = 1'b0;
            endcase
        end
    end
endmodule
