`timescale 1ns / 1ps
// ============================================================================
// vga_timing.v  -  640 x 480 at 60 Hz sync generator (25 MHz pixel clock)
// Owner: Member 4 (Heng Yong Hen)
// Horizontal: 640 visible, 16 front porch, 96 sync, 48 back porch (800)
// Vertical  : 480 visible, 10 front porch,  2 sync, 33 back porch (525)
// frame_tick pulses for one clock at the start of vertical blanking; the
// game updates its state then, so the visible picture is always stable.
// ============================================================================
module vga_timing (
    input            clk,
    input            rst,
    output reg [9:0] h = 10'd0,
    output reg [9:0] v = 10'd0,
    output           hs, vs,       // active low
    output           active,
    output reg       frame_tick = 1'b0
);
    always @(posedge clk) begin
        if (rst) begin
            h <= 10'd0; v <= 10'd0; frame_tick <= 1'b0;
        end else begin
            frame_tick <= (h == 10'd799) && (v == 10'd479);
            if (h == 10'd799) begin
                h <= 10'd0;
                v <= (v == 10'd524) ? 10'd0 : v + 10'd1;
            end else
                h <= h + 10'd1;
        end
    end
    assign active = (h < 10'd640) && (v < 10'd480);
    assign hs = ~((h >= 10'd656) && (h < 10'd752));
    assign vs = ~((v >= 10'd490) && (v < 10'd492));
endmodule
