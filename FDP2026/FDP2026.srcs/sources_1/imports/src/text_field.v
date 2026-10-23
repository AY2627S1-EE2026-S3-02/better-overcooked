`timescale 1ns / 1ps
// ============================================================================
// text_field.v  -  Draws N characters at a fixed position (combinational)
// Owner: Member 4 (Heng Yong Hen)
// Each character cell is 8 x 8 pixels (5 x 7 glyph plus spacing), scaled by
// 2^SHIFT. codes[4:0] is the first (leftmost) character.
// ============================================================================
module text_field #(
    parameter X0 = 0, Y0 = 0, N = 1, SHIFT = 0
)(
    input  [7:0]     px,           // pixel x (logical)
    input  [6:0]     py,           // pixel y (logical)
    input  [5*N-1:0] codes,
    output           on
);
    localparam W = (N * 8) << SHIFT;
    localparam H = 8 << SHIFT;

    // offsets wrap to large values left of / above the field, so one
    // unsigned compare per axis checks both edges
    wire [8:0]  rx = {1'b0, px} - X0;
    wire [7:0]  ry = {1'b0, py} - Y0;
    wire        in_x = (rx < W);
    wire        in_y = (ry < H);
    wire [8:0]  sx = rx >> SHIFT;
    wire [7:0]  sy = ry >> SHIFT;
    wire [5:0]  ci = sx[8:3];
    wire [2:0]  cx = sx[2:0];
    wire [2:0]  cy = sy[2:0];

    reg  [4:0]  code;
    integer i;
    always @* begin
        code = 5'd31;
        for (i = 0; i < N; i = i + 1)
            if (ci == i[5:0]) code = codes[i*5 +: 5];
    end

    wire [4:0] bits;
    font5x7 f (.code(code), .row(cy), .bits(bits));
    assign on = in_x && in_y && (cx < 3'd5) && (cy < 3'd7) && bits[3'd4 - cx];
endmodule
