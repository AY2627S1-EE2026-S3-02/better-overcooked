`timescale 1ns / 1ps
// ============================================================================
// clock_gen.v  -  Clock divider (same method as GPT-4)
// Owner: Group integration
// 100 MHz / 4  = 25 MHz   : game logic, VGA pixel clock, UART, displays
// 100 MHz / 16 = 6.25 MHz : Oled_Display.v
// The XDC declares both as generated clocks so Vivado times them.
// ============================================================================
module clock_gen (
    input  clk100,
    output clk25,
    output clk6p25
);
    reg [3:0] cnt = 4'd0;
    always @(posedge clk100) cnt <= cnt + 4'd1;
    assign clk25   = cnt[1];
    assign clk6p25 = cnt[3];
endmodule
