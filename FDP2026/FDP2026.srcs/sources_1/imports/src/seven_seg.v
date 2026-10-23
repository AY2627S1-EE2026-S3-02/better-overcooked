`timescale 1ns / 1ps
// ============================================================================
// seven_seg.v  -  Round time (m.ss) or score on the 4-digit display
// Owner: Member 4 (Heng Yong Hen)
// Digits are multiplexed at 1 kHz per digit. Segments and anodes are active low.
// ============================================================================
module seven_seg (
    input            clk,
    input            en_1khz,
    input            show_score,   // 1: score, 0: time
    input      [9:0] score,
    input      [7:0] time_s,
    output reg [6:0] seg,
    output reg       dp,
    output reg [3:0] an
);
    wire [3:0] sc_h, sc_t, sc_o, tm_m, tm_t, tm_o;
    digits dg (.score(score), .time_s(time_s), .sc_h(sc_h), .sc_t(sc_t), .sc_o(sc_o),
               .tm_m(tm_m), .tm_t(tm_t), .tm_o(tm_o));

    reg [1:0] sel = 2'd0;
    always @(posedge clk) if (en_1khz) sel <= sel + 2'd1;

    function [6:0] enc;            // gfedcba, active low
        input [3:0] d;
        case (d)
            4'd0: enc = 7'b1000000; 4'd1: enc = 7'b1111001; 4'd2: enc = 7'b0100100;
            4'd3: enc = 7'b0110000; 4'd4: enc = 7'b0011001; 4'd5: enc = 7'b0010010;
            4'd6: enc = 7'b0000010; 4'd7: enc = 7'b1111000; 4'd8: enc = 7'b0000000;
            4'd9: enc = 7'b0010000; default: enc = 7'b1111111;
        endcase
    endfunction

    always @(posedge clk) begin
        an  <= ~(4'b0001 << sel);
        dp  <= 1'b1;
        case (sel)
            2'd0: seg <= enc(show_score ? sc_o : tm_o);
            2'd1: seg <= enc(show_score ? sc_t : tm_t);
            2'd2: begin
                seg <= enc(show_score ? sc_h : tm_m);
                dp  <= show_score;          // decimal point after the minutes
            end
            default: seg <= 7'b1111111;     // leftmost digit blank
        endcase
    end
endmodule
