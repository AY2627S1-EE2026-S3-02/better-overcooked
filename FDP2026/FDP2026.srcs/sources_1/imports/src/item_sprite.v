`timescale 1ns / 1ps
// ============================================================================
// item_sprite.v  -  8 x 8 pixel art for ingredients and plates (combinational)
// Owner: Member 4 (Heng Yong Hen)
//
// Shapes are drawn from the squared distance to the sprite centre, using a
// 1-D lookup of (2*o - 7)^2, so no multipliers are needed. Shared by the VGA
// renderer, the OLED renderer, the crate icons and the order tickets.
// kind: 0 tomato, 1 lettuce, 2 plate. plate bits: {soup, lettuce, tomato}.
// Colours are 12-bit RGB (4 bits per channel).
// ============================================================================
module item_sprite (
    input      [1:0]  kind,
    input             chopped,
    input      [2:0]  plate,
    input      [2:0]  ox, oy,      // pixel within the 8 x 8 sprite
    output reg        opaque,
    output reg [11:0] color
);
    localparam [11:0] C_TOM = 12'hD21, C_TOM_HI = 12'hF87, C_STEM = 12'h2A2,
                      C_LET = 12'h3A3, C_LET_HI = 12'h9E6, C_SOUP = 12'hE71,
                      C_RIM = 12'hAAB, C_PLATE = 12'hFFF;

    function [6:0] sq;             // (2*o - 7)^2 for o = 0..7
        input [2:0] o;
        case (o)
            3'd0, 3'd7: sq = 7'd49;
            3'd1, 3'd6: sq = 7'd25;
            3'd2, 3'd5: sq = 7'd9;
            default:    sq = 7'd1;
        endcase
    endfunction

    wire [7:0] r2 = sq(ox) + sq(oy);   // 2 .. 98

    // three chopped pieces
    wire piece = ((ox == 3'd1 || ox == 3'd2) && (oy == 3'd1 || oy == 3'd2)) ||
                 ((ox == 3'd4 || ox == 3'd5) && (oy == 3'd2 || oy == 3'd3)) ||
                 ((ox == 3'd2 || ox == 3'd3) && (oy == 3'd4 || oy == 3'd5));

    always @* begin
        opaque = 1'b0;
        color  = 12'h000;
        case (kind)
            2'd0: begin                                   // tomato
                if (chopped) begin
                    if (piece) begin opaque = 1'b1; color = C_TOM; end
                end else if (oy == 3'd0 && (ox == 3'd3 || ox == 3'd4)) begin
                    opaque = 1'b1; color = C_STEM;
                end else if (r2 <= 8'd36) begin
                    opaque = 1'b1;
                    color  = (ox == 3'd2 && oy == 3'd2) ? C_TOM_HI : C_TOM;
                end
            end
            2'd1: begin                                   // lettuce
                if (chopped) begin
                    if (piece) begin opaque = 1'b1; color = C_LET; end
                end else if (r2 <= 8'd36) begin
                    opaque = 1'b1;
                    color  = (r2 <= 8'd10) ? C_LET_HI : C_LET;
                end
            end
            2'd2: begin                                   // plate and contents
                if (r2 <= 8'd44) begin
                    opaque = 1'b1;
                    color  = (r2 <= 8'd26) ? C_PLATE : C_RIM;
                    if (plate[2] && r2 <= 8'd18) color = C_SOUP;
                    else if (!plate[2]) begin
                        if (plate[1] && (ox == 3'd2 || ox == 3'd3) && (oy == 3'd3 || oy == 3'd4))
                            color = C_LET;
                        if (plate[0] && (ox == 3'd4 || ox == 3'd5) && (oy == 3'd3 || oy == 3'd4))
                            color = C_TOM;
                    end
                end
            end
            default: ;
        endcase
    end
endmodule
