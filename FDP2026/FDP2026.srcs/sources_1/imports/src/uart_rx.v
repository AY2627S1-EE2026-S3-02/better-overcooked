`timescale 1ns / 1ps
// ============================================================================
// uart_rx.v  -  UART receiver, 8N1, samples each bit in its centre
// Owner: Member 1 (Lee Kwan Tze)
// ============================================================================
module uart_rx #(parameter CPB = 217) (
    input            clk,
    input            rst,
    input            rx,
    output reg       valid = 1'b0,    // one-cycle pulse with a new byte
    output reg [7:0] data = 8'd0
);
    reg s1 = 1'b1, s2 = 1'b1;          // synchroniser (line idles high)
    always @(posedge clk) begin s1 <= rx; s2 <= s1; end

    reg [1:0] state = 2'd0;           // 0 idle, 1 start, 2 data, 3 stop
    reg [7:0] cnt = 8'd0;
    reg [2:0] bitn = 3'd0;
    reg [7:0] sh = 8'd0;

    always @(posedge clk) begin
        valid <= 1'b0;
        if (rst) begin
            state <= 2'd0; cnt <= 8'd0; bitn <= 3'd0;
        end else case (state)
            2'd0: if (!s2) begin state <= 2'd1; cnt <= 8'd0; end
            2'd1: if (cnt == (CPB - 1) / 2) begin             // middle of start bit
                if (!s2) begin state <= 2'd2; cnt <= 8'd0; bitn <= 3'd0; end
                else state <= 2'd0;                           // glitch, not a start bit
            end else cnt <= cnt + 8'd1;
            2'd2: if (cnt == CPB - 1) begin
                cnt <= 8'd0;
                sh  <= {s2, sh[7:1]};                         // LSB first
                if (bitn == 3'd7) state <= 2'd3;
                else bitn <= bitn + 3'd1;
            end else cnt <= cnt + 8'd1;
            default: if (cnt == CPB - 1) begin
                state <= 2'd0;
                if (s2) begin valid <= 1'b1; data <= sh; end  // good stop bit
            end else cnt <= cnt + 8'd1;
        endcase
    end
endmodule
