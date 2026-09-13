// UART RX simples - polling, 8N1, FIFO de 16 bytes
// MMIO (via cpu.v):
//   RXDATA @ +0x8 : leitura LW/LB (byte baixo) retorna o mais antigo e consome
//   STATUS @ +0x4 : leitura bit1 = VALID (1=ha byte disponivel)
// RX idle = 1. Frame = start(0) + 8 data LSB-first + stop(1).
// Se a FIFO encher, novos bytes sao descartados (overrun) ate ler.
// Parametro CLKS_PER_BIT: sim=10 (rapido), FPGA 50MHz/115200 = 434.
// Deve ser igual ao do uart_tx para o link funcionar.
module uart_rx #(
    parameter CLKS_PER_BIT = 10
) (
    input  wire       clk,
    input  wire       rst,        // sincrono, ativo alto
    input  wire       rx_i,       // serial, idle 1
    input  wire       rd,         // strobe 1 ciclo: consome 1 byte da FIFO
    output wire [7:0] data_o,     // byte mais antigo (combinacional)
    output wire       valid       // 1 = ha byte disponivel
);
    localparam [1:0] S_IDLE  = 2'b00;
    localparam [1:0] S_START = 2'b01;
    localparam [1:0] S_DATA  = 2'b10;
    localparam [1:0] S_STOP  = 2'b11;

    reg [1:0]  state;
    reg [7:0]  shift;
    reg [2:0]  bit_idx;     // 0..7
    reg [31:0] clk_cnt;

    // FIFO circular 16x8 (indices 4 bits, count 0..16)
    reg [7:0] fifo [0:15];
    reg [3:0] head;          // proxima escrita
    reg [3:0] tail;          // proxima leitura
    reg [4:0] count;

    assign valid  = (count != 5'd0);
    assign data_o = fifo[tail];

    // Frame que termina neste ciclo
    wire stop_done;
    assign stop_done = (state == S_STOP) && (clk_cnt == CLKS_PER_BIT - 1);

    // Consumo e escrita podem ocorrer no mesmo ciclo
    wire do_rd;
    wire do_wr;
    assign do_rd = rd && (count != 5'd0);
    assign do_wr = stop_done && ((count != 5'd16) || do_rd);

    always @(posedge clk) begin
        if (rst) begin
            state   <= S_IDLE;
            shift   <= 8'd0;
            bit_idx <= 3'd0;
            clk_cnt <= 32'd0;
            head    <= 4'd0;
            tail    <= 4'd0;
            count   <= 5'd0;
        end else begin
            if (do_wr)
                fifo[head] <= shift;
            head  <= head + {3'd0, do_wr};
            tail  <= tail + {3'd0, do_rd};
            count <= count + {4'd0, do_wr} - {4'd0, do_rd};
            case (state)
                S_IDLE: begin
                    if (rx_i == 1'b0) begin
                        state   <= S_START;
                        clk_cnt <= 32'd0;
                    end
                end
                S_START: begin
                    // amostra no meio do start bit
                    if (clk_cnt == (CLKS_PER_BIT >> 1)) begin
                        clk_cnt <= 32'd0;
                        if (rx_i == 1'b0) begin
                            state   <= S_DATA;
                            bit_idx <= 3'd0;
                        end else begin
                            state <= S_IDLE; // glitch, volta
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 32'd1;
                    end
                end
                S_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 32'd0;
                        shift[bit_idx] <= rx_i; // LSB primeiro
                        if (bit_idx == 3'd7)
                            state <= S_STOP;
                        else
                            bit_idx <= bit_idx + 3'd1;
                    end else begin
                        clk_cnt <= clk_cnt + 32'd1;
                    end
                end
                S_STOP: begin
                    if (stop_done) begin
                        state   <= S_IDLE;
                        clk_cnt <= 32'd0;
                    end else begin
                        clk_cnt <= clk_cnt + 32'd1;
                    end
                end
                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end
endmodule
