`timescale 1ns / 1ps
// ============================================================================
// chef_motion.v  -  Movement and collision of both chefs
// Owner: Member 2 (Ian Lee)
//
// Each chef moves 1 logical px per 60 Hz tick (60 px/s). Its collision box is
// 6 x 6 px around the centre (cx-3 .. cx+2). Every move is tested per axis:
// the two leading corners are looked up in the tile map and any non-floor
// tile blocks the move, so a chef pressing diagonally into a wall slides
// along it. Chef 2 is tested against chef 1's NEW position, so the chefs can
// never overlap. Facing: 0 up, 1 down, 2 left, 3 right.
// ============================================================================
module chef_mover (
    input  [7:0] cx, input [6:0] cy,     // current centre
    input  [3:0] dir,                    // {up, down, left, right}
    input        freeze,
    input  [7:0] ox, input [6:0] oy,     // other chef centre
    output [7:0] nx, output [6:0] ny
);
    localparam [3:0] T_FLOOR = 4'd0;

    wire up = dir[3] & ~dir[2], dn = dir[2] & ~dir[3];
    wire lf = dir[1] & ~dir[0], rt = dir[0] & ~dir[1];
    wire move_x = ~freeze & (lf | rt);
    wire move_y = ~freeze & (up | dn);

    // ---- X move ----
    wire [8:0] tx_c  = rt ? ({1'b0, cx} + 9'd1) : ({1'b0, cx} - 9'd1);
    wire [8:0] edge_x = rt ? (tx_c + 9'd2) : (tx_c - 9'd3);   // leading edge column
    wire [3:0] t_x0, t_x1;
    // corner rows of the collision box: cy-3 and cy+2
    wire [7:0] row_a = {1'b0, cy} - 8'd3;
    wire [7:0] row_b = {1'b0, cy} + 8'd2;
    map_rom mxa (.tx(edge_x[7:3]), .ty(row_a[6:3]), .tile(t_x0));
    map_rom mxb (.tx(edge_x[7:3]), .ty(row_b[6:3]), .tile(t_x1));
    wire [7:0] dxo = (tx_c[7:0] > ox) ? (tx_c[7:0] - ox) : (ox - tx_c[7:0]);
    wire [6:0] dyo = (cy > oy) ? (cy - oy) : (oy - cy);
    wire hit_chef_x = (dxo < 8'd6) && (dyo < 7'd6);
    wire ok_x = move_x && (t_x0 == T_FLOOR) && (t_x1 == T_FLOOR) && !hit_chef_x;
    wire [7:0] cx1 = ok_x ? tx_c[7:0] : cx;

    // ---- Y move (uses the new x) ----
    wire [7:0] ty_c  = dn ? ({1'b0, cy} + 8'd1) : ({1'b0, cy} - 8'd1);
    wire [7:0] edge_y = dn ? (ty_c + 8'd2) : (ty_c - 8'd3);
    wire [8:0] col_a = {1'b0, cx1} - 9'd3;
    wire [8:0] col_b = {1'b0, cx1} + 9'd2;
    wire [3:0] t_y0, t_y1;
    map_rom mya (.tx(col_a[7:3]), .ty(edge_y[6:3]), .tile(t_y0));
    map_rom myb (.tx(col_b[7:3]), .ty(edge_y[6:3]), .tile(t_y1));
    wire [7:0] dxo2 = (cx1 > ox) ? (cx1 - ox) : (ox - cx1);
    wire [6:0] dyo2 = (ty_c[6:0] > oy) ? (ty_c[6:0] - oy) : (oy - ty_c[6:0]);
    wire hit_chef_y = (dxo2 < 8'd6) && (dyo2 < 7'd6);
    wire ok_y = move_y && (t_y0 == T_FLOOR) && (t_y1 == T_FLOOR) && !hit_chef_y;

    assign nx = cx1;
    assign ny = ok_y ? ty_c[6:0] : cy;
endmodule

module chef_motion (
    input            clk,
    input            rst,
    input            tick,          // 60 Hz play tick
    input            round_reset,   // return to spawn points
    input      [3:0] p1_dir, p2_dir,   // {up, down, left, right}
    input            p1_freeze, p2_freeze,
    output reg [7:0] p1_x, output reg [6:0] p1_y, output reg [1:0] p1_face,
    output reg [7:0] p2_x, output reg [6:0] p2_y, output reg [1:0] p2_face
);
    localparam [7:0] P1_X0 = 8'd36,  P2_X0 = 8'd116;   // tile (4,6) and (14,6)
    localparam [6:0] P_Y0  = 7'd52;
    localparam [1:0] F_UP = 2'd0, F_DOWN = 2'd1, F_LEFT = 2'd2, F_RIGHT = 2'd3;

    wire [7:0] n1x, n2x;
    wire [6:0] n1y, n2y;

    chef_mover m1 (.cx(p1_x), .cy(p1_y), .dir(p1_dir), .freeze(p1_freeze),
                   .ox(p2_x), .oy(p2_y), .nx(n1x), .ny(n1y));
    chef_mover m2 (.cx(p2_x), .cy(p2_y), .dir(p2_dir), .freeze(p2_freeze),
                   .ox(n1x), .oy(n1y), .nx(n2x), .ny(n2y));

    // facing follows the pressed direction, horizontal has priority
    function [1:0] new_face;
        input [3:0] d; input [1:0] f;
        begin
            if      (d[0] & ~d[1]) new_face = F_RIGHT;
            else if (d[1] & ~d[0]) new_face = F_LEFT;
            else if (d[2] & ~d[3]) new_face = F_DOWN;
            else if (d[3] & ~d[2]) new_face = F_UP;
            else                   new_face = f;
        end
    endfunction

    always @(posedge clk) begin
        if (rst || round_reset) begin
            p1_x <= P1_X0; p1_y <= P_Y0; p1_face <= F_UP;
            p2_x <= P2_X0; p2_y <= P_Y0; p2_face <= F_UP;
        end else if (tick) begin
            p1_x <= n1x; p1_y <= n1y;
            p2_x <= n2x; p2_y <= n2y;
            if (!p1_freeze) p1_face <= new_face(p1_dir, p1_face);
            if (!p2_freeze) p2_face <= new_face(p2_dir, p2_face);
        end
    end
endmodule
