`timescale 1ns / 1ps
// ============================================================================
// map_rom.v  -  Kitchen tile map (20 x 15 tiles, each tile 8 x 8 logical px)
// Owner: Member 2 (Ian Lee) - obstacle geometry for movement and physics
//
// Tile codes (shared by every module, keep identical everywhere):
//   0 FLOOR   1 WALL   2 COUNTER   3 TOMATO CRATE   4 LETTUCE CRATE
//   5 CHOPPING BOARD   6 STOVE   7 PLATE RACK   8 SERVING WINDOW
//   9 BIN   10 CONVEYOR (moves items to the right)
//
// Layout (rows 0-1 are the HUD strip and count as wall):
//   row 3 : W T C L K C K C C C C S C S C P C V B W
//   rows 4-12 : divider counters in column 9, pillar at (5,8),
//               island counters at (14,8) and (15,8)
//   row 13: W C C B C C > > > > > > > C C C C C C W
// ============================================================================
module map_rom (
    input      [4:0] tx,      // tile column 0..19
    input      [3:0] ty,      // tile row    0..14
    output reg [3:0] tile
);
    localparam [3:0] T_FLOOR = 4'd0, T_WALL = 4'd1, T_COUNTER = 4'd2,
                     T_CRATE_TOM = 4'd3, T_CRATE_LET = 4'd4, T_CHOP = 4'd5,
                     T_STOVE = 4'd6, T_PLATES = 4'd7, T_SERVE = 4'd8,
                     T_BIN = 4'd9, T_CONV = 4'd10;

    always @* begin
        tile = T_FLOOR;
        if (tx >= 5'd20 || ty >= 4'd15)
            tile = T_WALL;                                   // outside the map
        else if (ty <= 4'd2 || ty == 4'd14 || tx == 5'd0 || tx == 5'd19)
            tile = T_WALL;                                   // HUD strip and border
        else if (ty == 4'd3) begin                           // top station row
            case (tx)
                5'd1:          tile = T_CRATE_TOM;
                5'd3:          tile = T_CRATE_LET;
                5'd4, 5'd6:    tile = T_CHOP;
                5'd11, 5'd13:  tile = T_STOVE;
                5'd15:         tile = T_PLATES;
                5'd17:         tile = T_SERVE;
                5'd18:         tile = T_BIN;
                default:       tile = T_COUNTER;
            endcase
        end
        else if (ty == 4'd13) begin                          // bottom row
            if (tx >= 5'd6 && tx <= 5'd12) tile = T_CONV;
            else if (tx == 5'd3)           tile = T_BIN;
            else                           tile = T_COUNTER;
        end
        else begin                                           // kitchen floor rows 4-12
            if (tx == 5'd9)                                 tile = T_COUNTER; // divider
            else if (ty == 4'd8 && (tx == 5'd14 || tx == 5'd15)) tile = T_COUNTER; // island
            else if (ty == 4'd8 && tx == 5'd5)              tile = T_WALL;    // pillar
        end
    end
endmodule
