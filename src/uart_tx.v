// UART TX simples - polling, 8N1, sem FIFO
// MMIO (via cpu.v):
//   TXDATA @ +0x0 : escrita SW/SB (byte baixo) inicia transmissao
//   STATUS @ +0x4 : leitura bit0 = READY (1=idle, pode escrever)
// TX idle = 1. Frame = start(0) + 8 data LSB-first + stop(1).
// Parametro CLKS_PER_BIT: sim=10 (rapido), FPGA 50MHz/115200 = 434.
module uart_tx #(
    parameter CLKS_PER_BIT = 10
) (
    input  wire       clk,
    input  wire       rst,        // sincrono, ativo alto
    input  wire       wr,         // strobe 1 ciclo p/ transmitir data_in
    input  wire [7:0] data_in,
    output reg        ready,      // 1 = idle
    output reg        tx_o        // serial, idle 1
);
    localparam [1:0] S_IDLE = 2'b00;
    localparam [1:0] S_TX   = 2'b01;

    reg [1:0]  state;
    /* verilator lint_off UNUSEDSIGNAL */
    reg [9:0]  shift;      // [0]=bit atual (start), [1]=prox; [0] espelha tx_o
    /* verilator lint_on UNUSEDSIGNAL */
    reg [3:0]  bit_cnt;    // 0..9
    reg [31:0] clk_cnt;    // 0..CLKS_PER_BIT-1

    always @(posedge clk) begin
        if (rst) begin
            state   <= S_IDLE;
            ready   <= 1'b1;
            tx_o    <= 1'b1;
            shift   <= 10'b1111111111;
            bit_cnt <= 4'd0;
            clk_cnt <= 32'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    tx_o <= 1'b1;
                    if (wr && ready) begin
                        // carrega {stop=1, data, start=0}, transmite LSB primeiro
                        shift   <= {1'b1, data_in, 1'b0};
                        bit_cnt <= 4'd0;
                        clk_cnt <= 32'd0;
                        ready   <= 1'b0;
                        state   <= S_TX;
                        tx_o    <= 1'b0; // start bit imediato
                    end else begin
                        ready <= 1'b1;
                    end
                end
                S_TX: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 32'd0;
                        if (bit_cnt == 4'd9) begin
                            // ultimo bit (stop) ja ficou 1 por CLKS_PER_BIT
                            state <= S_IDLE;
                            ready <= 1'b1;
                            tx_o  <= 1'b1;
                        end else begin
                            bit_cnt <= bit_cnt + 4'd1;
                            shift   <= {1'b1, shift[9:1]};
                            tx_o    <= shift[1];
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 32'd1;
                    end
                end
                default: begin
                    state <= S_IDLE;
                    ready <= 1'b1;
                    tx_o  <= 1'b1;
                end
            endcase
        end
    end
endmodule
