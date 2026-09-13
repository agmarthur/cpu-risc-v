// Banco de registradores 32x32 - x0 hardwired em 0
// Leitura assincrona, escrita sincrona, reset sincrono ativo alto
module regfile (
    input  wire        clk,
    input  wire        rst,
    input  wire        we,
    input  wire [4:0]  rs1,
    input  wire [4:0]  rs2,
    input  wire [4:0]  rd,
    input  wire [31:0] wd,
    output wire [31:0] rd1,
    output wire [31:0] rd2
);
    reg [31:0] regs [0:31];

    integer i;

    // x0 sempre zero
    assign rd1 = (rs1 == 5'd0) ? 32'd0 : regs[rs1];
    assign rd2 = (rs2 == 5'd0) ? 32'd0 : regs[rs2];

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'd0;
        end else begin
            if (we && (rd != 5'd0))
                regs[rd] <= wd;
            // garante x0 = 0 mesmo apos escrita indevida
            regs[0] <= 32'd0;
        end
    end
endmodule
