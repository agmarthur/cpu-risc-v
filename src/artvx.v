// ART-VX custom SIMD 2x16 - opera em 2 meias-words empacotadas em 32 bits
// Formato: rs = {hi[31:16], lo[15:0]}, rd = {hi, lo} (wrap 16 bits, sem carry entre halves)
// Codificacao R-type, opcode custom-0 (0001011 = 0x0B), funct7 = 0000001:
//   funct3=000 artvx.add : rd.hi=rs1.hi+rs2.hi, rd.lo=rs1.lo+rs2.lo
//   funct3=001 artvx.sub : rd.hi=rs1.hi-rs2.hi, rd.lo=rs1.lo-rs2.lo
//   funct3=010 artvx.mul : rd.hi=low16(rs1.hi*rs2.hi), rd.lo=low16(rs1.lo*rs2.lo) signed
module artvx (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [1:0]  ctrl,   // 00=ADD, 01=SUB, 10=MUL
    output reg  [31:0] result
);
    wire [15:0] a_hi, a_lo, b_hi, b_lo;
    assign a_hi = a[31:16];
    assign a_lo = a[15:0];
    assign b_hi = b[31:16];
    assign b_lo = b[15:0];

    wire [15:0] add_hi, add_lo, sub_hi, sub_lo, mul_hi, mul_lo;
    assign add_hi = a_hi + b_hi;
    assign add_lo = a_lo + b_lo;
    assign sub_hi = a_hi - b_hi;
    assign sub_lo = a_lo - b_lo;
    // low16 de 16x16 signed (igual p/ unsigned nos 16 baixos)
    assign mul_hi = $signed(a_hi) * $signed(b_hi);
    assign mul_lo = $signed(a_lo) * $signed(b_lo);

    always @(*) begin
        case (ctrl)
            2'b00:   result = {add_hi, add_lo};
            2'b01:   result = {sub_hi, sub_lo};
            2'b10:   result = {mul_hi, mul_lo};
            default: result = 32'd0;
        endcase
    end
endmodule
