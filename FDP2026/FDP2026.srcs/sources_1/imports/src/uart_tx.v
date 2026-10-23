`timescale 1ns / 1ps
// ============================================================================
// uart_tx.v  -  UART transmitter, 8 data bits, no parity, 1 stop bit
// Owner: Member 1 (Lee Kwan Tze)
// CPB = clock cycles per bit (25 MHz / 115200 = 217).
// ============================================================================
module uart_tx #(parameter CPB = 217) (
    input        clk,
    input        rst,
    input        start,      // pulse: send data (ignored while busy)
    input  [7:0] data,
    output reg   tx = 1'b1,
    output       busy
);
    reg [1:0] state = 2'd0;               // 0 idle, 1 start, 2 data, 3 stop
    reg [7:0] cnt = 8'd0;
    reg [2:0] bitn = 3'd0;
    reg [7:0] sh = 8'd0;
    assign busy = (state != 2'd0);

    always @(posedge clk) begin
        if (rst) begin
            state <= 2'd0; tx <= 1'b1; cnt <= 8'd0; bitn <= 3'd0;
        end else case (state)
            2'd0: if (start) begin
                sh <= data; state <= 2'd1; cnt <= 8'd0; tx <= 1'b0;   // start bit
            end
            2'd1: if (cnt == CPB - 1) begin
                cnt <= 8'd0; state <= 2'd2; bitn <= 3'd0; tx <= sh[0];
            end else cnt <= cnt + 8'd1;
            2'd2: if (cnt == CPB - 1) begin
                cnt <= 8'd0;
                if (bitn == 3'd7) begin state <= 2'd3; tx <= 1'b1; end   // stop bit
                else begin bitn <= bitn + 3'd1; sh <= {1'b0, sh[7:1]}; tx <= sh[1]; end
            end else cnt <= cnt + 8'd1;
            default: if (cnt == CPB - 1) begin
                cnt <= 8'd0; state <= 2'd0;
            end else cnt <= cnt + 8'd1;
        endcase
    end
endmodule
