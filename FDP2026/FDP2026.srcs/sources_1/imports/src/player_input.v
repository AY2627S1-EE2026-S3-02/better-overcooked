`timescale 1ns / 1ps
// ============================================================================
// player_input.v  -  Interprets one player's five buttons
// Owner: Member 1 (Lee Kwan Tze)
//
// Centre button
//   tap  : released within HOLD_T ticks (0.2 s)   -> contextual interaction
//   hold : held for HOLD_T ticks or more           -> charge a throw (if
//          carrying) or chop (if empty-handed at a board), decided by Member 3
//   release_hold : released after a hold           -> throw request
// Charge level grows every 0.5 s of holding: 1, 2, 3.
// Aim: starts at the facing direction, then follows the direction buttons
//   (8 directions: 0 N, 1 NE, 2 E, 3 SE, 4 S, 5 SW, 6 W, 7 NW).
// Launch velocity (Q4.4 px per tick): 1.0, 1.5, 2.0 px for levels 1-3;
//   diagonals use 0.75 of the speed, v - (v >> 2), so no multiplier is needed.
// All outputs change only on the 60 Hz tick and last exactly one tick.
// ============================================================================
module player_input (
    input             clk,
    input             rst,
    input             tick,              // 60 Hz
    input      [4:0]  btn,               // {up, down, left, right, centre}
    input      [1:0]  face,              // 0 up, 1 down, 2 left, 3 right
    output     [3:0]  dir,               // {up, down, left, right}
    output reg        tap,
    output reg        hold,
    output reg        release_hold,
    output reg [2:0]  aim,
    output reg [1:0]  charge,
    output reg signed [7:0] throw_vx,
    output reg signed [7:0] throw_vy
);
    localparam [6:0] HOLD_T  = 7'd12;   // 0.2 s
    localparam [6:0] LEVEL_T = 7'd30;   // 0.5 s per charge level

    assign dir = btn[4:1];
    wire c = btn[0];

    reg       c_prev;
    reg [6:0] cnt;                      // ticks the centre button is held

    // facing (4 dirs) to aim (8 dirs)
    function [2:0] face_to_aim;
        input [1:0] f;
        case (f)
            2'd0: face_to_aim = 3'd0;   // up    -> N
            2'd1: face_to_aim = 3'd4;   // down  -> S
            2'd2: face_to_aim = 3'd6;   // left  -> W
            default: face_to_aim = 3'd2;// right -> E
        endcase
    endfunction

    // direction buttons to aim; returns {valid, aim}
    function [3:0] dir_to_aim;
        input [3:0] d;
        reg u, dn, l, r;
        begin
            u = d[3] & ~d[2]; dn = d[2] & ~d[3];
            l = d[1] & ~d[0]; r = d[0] & ~d[1];
            case ({u, dn, l, r})
                4'b1000: dir_to_aim = {1'b1, 3'd0};
                4'b1001: dir_to_aim = {1'b1, 3'd1};
                4'b0001: dir_to_aim = {1'b1, 3'd2};
                4'b0101: dir_to_aim = {1'b1, 3'd3};
                4'b0100: dir_to_aim = {1'b1, 3'd4};
                4'b0110: dir_to_aim = {1'b1, 3'd5};
                4'b0010: dir_to_aim = {1'b1, 3'd6};
                4'b1010: dir_to_aim = {1'b1, 3'd7};
                default: dir_to_aim = {1'b0, 3'd0};
            endcase
        end
    endfunction

    wire [3:0] da = dir_to_aim(btn[4:1]);

    // speed for the current charge level
    reg [7:0] s, d;
    always @* begin
        case (charge)
            2'd3:    s = 8'd32;
            2'd2:    s = 8'd24;
            default: s = 8'd16;
        endcase
        d = s - (s >> 2);
    end

    always @(posedge clk) begin
        if (rst) begin
            c_prev <= 1'b0; cnt <= 7'd0;
            tap <= 1'b0; hold <= 1'b0; release_hold <= 1'b0;
            aim <= 3'd0; charge <= 2'd0;
            throw_vx <= 8'sd0; throw_vy <= 8'sd0;
        end else if (tick) begin
            c_prev <= c;
            cnt    <= c ? ((cnt == 7'd127) ? cnt : cnt + 7'd1) : 7'd0;

            tap          <= c_prev & ~c & (cnt <  HOLD_T);
            release_hold <= c_prev & ~c & (cnt >= HOLD_T);
            hold         <= c & (cnt >= HOLD_T - 7'd1);

            // aim: initialise on hold start, then follow the d-pad
            if (c && cnt == HOLD_T - 7'd1)
                aim <= da[3] ? da[2:0] : face_to_aim(face);
            else if (c && cnt >= HOLD_T && da[3])
                aim <= da[2:0];

            // charge level while holding; kept after release for the throw
            if (c && cnt >= HOLD_T - 7'd1) begin
                if      (cnt >= HOLD_T + 2*LEVEL_T) charge <= 2'd3;
                else if (cnt >= HOLD_T + LEVEL_T)   charge <= 2'd2;
                else                                charge <= 2'd1;
            end else if (!c && !c_prev)
                charge <= 2'd0;

            // launch velocity for the current aim and charge
            case (aim)
                3'd0: begin throw_vx <= 8'sd0;      throw_vy <= -$signed(s); end
                3'd1: begin throw_vx <= $signed(d); throw_vy <= -$signed(d); end
                3'd2: begin throw_vx <= $signed(s); throw_vy <= 8'sd0;       end
                3'd3: begin throw_vx <= $signed(d); throw_vy <= $signed(d);  end
                3'd4: begin throw_vx <= 8'sd0;      throw_vy <= $signed(s);  end
                3'd5: begin throw_vx <= -$signed(d); throw_vy <= $signed(d); end
                3'd6: begin throw_vx <= -$signed(s); throw_vy <= 8'sd0;      end
                default: begin throw_vx <= -$signed(d); throw_vy <= -$signed(d); end
            endcase
        end
    end
endmodule
