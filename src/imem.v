// Memoria de instrucoes - leitura assincrona (single cycle)
// DEPTH = numero de words de 32 bits
module imem #(
    parameter DEPTH = 1024,
    parameter INIT_FILE = "prog/program.hex"
) (
    input  wire [31:0] addr,
    output wire [31:0] instr
);
    reg [31:0] mem [0:DEPTH-1];

    integer k;
    initial begin
        for (k = 0; k < DEPTH; k = k + 1)
            mem[k] = 32'h00000013; // NOP (addi x0,x0,0)
        $readmemh(INIT_FILE, mem);
    end

    wire [31:0] waddr;
    assign waddr = addr >> 2;
    assign instr = (waddr < DEPTH) ? mem[waddr] : 32'h00000013;
endmodule
