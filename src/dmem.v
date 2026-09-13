// Memoria de dados - byte enderecavel, 8KB
// (8KB: o ART-OS usa ~4KB de text+rodata e precisa de stack folgado)
// Escrita sincrona, leitura assincrona (single cycle)
// funct3 load : 000 LB, 001 LH, 010 LW, 100 LBU, 101 LHU
// funct3 store: 000 SB, 001 SH, 010 SW
module dmem #(
    parameter DEPTH_BYTES = 8192,
    parameter INIT_FILE = "prog/program.hex"
) (
    input  wire        clk,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire [2:0]  funct3,
    output reg  [31:0] rdata,
    // debug assincrono p/ Verilator (le word LE em dbg_addr)
    input  wire [31:0] dbg_addr,
    output wire [31:0] dbg_data
);
    reg [7:0] mem [0:DEPTH_BYTES-1];

    integer k;
    reg [31:0] init_words [0:(DEPTH_BYTES/4)-1];
    integer w;
    initial begin
        for (k = 0; k < DEPTH_BYTES; k = k + 1)
            mem[k] = 8'd0;
        // Espelha o programa na DMEM: permite LW de literal pool
        // (.rodata embutido no .text) em CPU Harvard.
        // Formato: 1 word hex por linha, little-endian.
        for (w = 0; w < (DEPTH_BYTES/4); w = w + 1)
            init_words[w] = 32'h00000013; // NOP
        $readmemh(INIT_FILE, init_words);
        for (w = 0; w < (DEPTH_BYTES/4); w = w + 1) begin
            mem[w*4]   = init_words[w][7:0];
            mem[w*4+1] = init_words[w][15:8];
            mem[w*4+2] = init_words[w][23:16];
            mem[w*4+3] = init_words[w][31:24];
        end
    end

    wire [31:0] a;
    assign a = addr & 32'h00001FFF; // 8KB window (evita out-of-bounds)

    // --- escrita sincrona ---
    always @(posedge clk) begin
        if (mem_write) begin
            case (funct3[1:0])
                2'b00: begin // SB
                    mem[a] <= wdata[7:0];
                end
                2'b01: begin // SH
                    mem[a]     <= wdata[7:0];
                    mem[a + 1] <= wdata[15:8];
                end
                2'b10: begin // SW
                    mem[a]     <= wdata[7:0];
                    mem[a + 1] <= wdata[15:8];
                    mem[a + 2] <= wdata[23:16];
                    mem[a + 3] <= wdata[31:24];
                end
                default: begin end
            endcase
        end
    end

    // --- leitura assincrona ---
    wire [7:0] b0, b1, b2, b3;
    assign b0 = mem[a];
    assign b1 = mem[a + 1];
    assign b2 = mem[a + 2];
    assign b3 = mem[a + 3];

    // --- debug: word LE em dbg_addr (mascara 8KB) ---
    wire [31:0] da;
    assign da = dbg_addr & 32'h00001FFF;
    assign dbg_data = {mem[da + 3], mem[da + 2], mem[da + 1], mem[da]};

    always @(*) begin
        if (!mem_read) begin
            rdata = 32'd0;
        end else begin
            case (funct3)
                3'b000:  rdata = {{24{b0[7]}}, b0};              // LB
                3'b001:  rdata = {{16{b1[7]}}, b1, b0};          // LH
                3'b010:  rdata = {b3, b2, b1, b0};               // LW
                3'b100:  rdata = {24'd0, b0};                   // LBU
                3'b101:  rdata = {16'd0, b1, b0};               // LHU
                default: rdata = {b3, b2, b1, b0};
            endcase
        end
    end
endmodule
