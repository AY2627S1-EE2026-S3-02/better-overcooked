`timescale 1ns / 1ps
// ============================================================================
// digits.v  -  Splits the score and round time into decimal digits
// Owner: Member 4 (Heng Yong Hen)
// ============================================================================
module digits (
    input  [9:0] score,            // 0..999
    input  [7:0] time_s,           // 0..255 seconds
    output [3:0] sc_h, sc_t, sc_o, // score hundreds, tens, ones
    output [3:0] tm_m, tm_t, tm_o  // minutes, seconds tens, seconds ones
);
    wire [7:0] mins = time_s / 8'd60;
    wire [7:0] secs = time_s - mins * 8'd60;
    wire [9:0] h_full = score / 10'd100;
    wire [9:0] t_full = (score / 10'd10) % 10'd10;
    wire [9:0] o_full = score % 10'd10;
    wire [7:0] st_full = secs / 8'd10;
    wire [7:0] so_full = secs % 8'd10;
    assign sc_h = h_full[3:0];
    assign sc_t = t_full[3:0];
    assign sc_o = o_full[3:0];
    assign tm_m = mins[3:0];
    assign tm_t = st_full[3:0];
    assign tm_o = so_full[3:0];
endmodule
