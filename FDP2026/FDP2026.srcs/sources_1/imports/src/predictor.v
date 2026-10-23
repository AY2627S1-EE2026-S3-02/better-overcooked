`timescale 1ns / 1ps
// ============================================================================
// predictor.v  -  Throw trajectory preview for aiming players
// Owner: Member 1 (Lee Kwan Tze), using Member 2's physics_step module
//
// Once per 60 Hz tick, for each player who is aiming, the throw is simulated
// with the SAME physics_step used for real objects, one step per clock cycle
// (at most 64 cycles per player, during vertical blanking). Every 6th step
// is stored as a preview dot, plus the predicted landing point.
// Launch constants must match object_physics.v.
// ============================================================================
module predictor (
    input             clk,
    input             rst,
    input             tick,
    input             p1_aiming, p2_aiming,
    input      [7:0]  p1_x, input [6:0] p1_y,
    input      [7:0]  p2_x, input [6:0] p2_y,
    input signed [7:0] p1_vx, p1_vy, p2_vx, p2_vy,
    output reg [3:0]  p1_n, p2_n,            // number of valid dots (0..8)
    output reg [63:0] p1_dx_flat, p2_dx_flat,// 8 x 8-bit screen x
    output reg [55:0] p1_dy_flat, p2_dy_flat,// 8 x 7-bit screen y (y - z)
    output reg        p1_land_v, p2_land_v,
    output reg [7:0]  p1_land_x, p2_land_x,
    output reg [6:0]  p1_land_y, p2_land_y
);
    localparam [8:0]        Z_LAUNCH  = 9'd64;
    localparam signed [7:0] VZ_LAUNCH = 8'sd20;
    localparam [1:0] P_IDLE = 2'd0, P_INIT = 2'd1, P_RUN = 2'd2;

    reg [1:0]  ps;
    reg        who;                 // 0: player 1, 1: player 2
    reg [5:0]  step;
    reg [2:0]  phase6;              // counts 0..5 between dots
    reg [3:0]  nd;

    reg [11:0] x, y;
    reg [8:0]  z;
    reg signed [7:0] vx, vy, vz;

    wire [11:0] nx, ny;
    wire [8:0]  nz;
    wire signed [7:0] nvx, nvy, nvz;
    wire nair, landed, stopped;
    wire [3:0] cur_tile;

    physics_step sim (
        .x(x), .y(y), .z(z), .vx(vx), .vy(vy), .vz(vz), .air(1'b1),
        .nx(nx), .ny(ny), .nz(nz), .nvx(nvx), .nvy(nvy), .nvz(nvz),
        .nair(nair), .landed(landed), .cur_tile(cur_tile), .stopped(stopped));

    wire [7:0] sx = nx[11:4];
    wire [6:0] gy = ny[10:4];
    wire [4:0] zi = nz[8:4];
    wire [6:0] sy = (gy > {2'b00, zi}) ? (gy - {2'b00, zi}) : 7'd0;

    wire aiming_now = who ? p2_aiming : p1_aiming;

    always @(posedge clk) begin
        if (rst) begin
            ps <= P_IDLE; who <= 1'b0; step <= 6'd0; phase6 <= 3'd0; nd <= 4'd0;
            x <= 12'd0; y <= 12'd0; z <= 9'd0; vx <= 8'sd0; vy <= 8'sd0; vz <= 8'sd0;
            p1_n <= 4'd0; p2_n <= 4'd0; p1_land_v <= 1'b0; p2_land_v <= 1'b0;
            p1_dx_flat <= 64'd0; p2_dx_flat <= 64'd0;
            p1_dy_flat <= 56'd0; p2_dy_flat <= 56'd0;
            p1_land_x <= 8'd0; p2_land_x <= 8'd0; p1_land_y <= 7'd0; p2_land_y <= 7'd0;
        end else begin
            case (ps)
                P_IDLE: if (tick) begin who <= 1'b0; ps <= P_INIT; end

                P_INIT: begin
                    if (aiming_now) begin
                        x  <= who ? {p2_x, 4'd0} : {p1_x, 4'd0};
                        y  <= who ? {1'b0, p2_y, 4'd0} : {1'b0, p1_y, 4'd0};
                        z  <= Z_LAUNCH;
                        vx <= who ? p2_vx : p1_vx;
                        vy <= who ? p2_vy : p1_vy;
                        vz <= VZ_LAUNCH;
                        step <= 6'd0; phase6 <= 3'd0; nd <= 4'd0;
                        ps <= P_RUN;
                    end else begin
                        if (who) begin p2_n <= 4'd0; p2_land_v <= 1'b0; end
                        else     begin p1_n <= 4'd0; p1_land_v <= 1'b0; end
                        if (who) ps <= P_IDLE;
                        else begin who <= 1'b1; ps <= P_INIT; end
                    end
                end

                P_RUN: begin
                    x <= nx; y <= ny; z <= nz; vx <= nvx; vy <= nvy; vz <= nvz;
                    step <= step + 6'd1;
                    phase6 <= (phase6 == 3'd5) ? 3'd0 : phase6 + 3'd1;
                    if (phase6 == 3'd5 && nd < 4'd8 && !landed) begin
                        if (who) begin
                            p2_dx_flat[nd[2:0]*8 +: 8] <= sx;
                            p2_dy_flat[nd[2:0]*7 +: 7] <= sy;
                        end else begin
                            p1_dx_flat[nd[2:0]*8 +: 8] <= sx;
                            p1_dy_flat[nd[2:0]*7 +: 7] <= sy;
                        end
                        nd <= nd + 4'd1;
                    end
                    if (landed || step == 6'd63) begin
                        if (who) begin
                            p2_n <= nd; p2_land_v <= landed;
                            p2_land_x <= sx; p2_land_y <= gy;
                            ps <= P_IDLE;
                        end else begin
                            p1_n <= nd; p1_land_v <= landed;
                            p1_land_x <= sx; p1_land_y <= gy;
                            who <= 1'b1; ps <= P_INIT;
                        end
                    end
                end
                default: ps <= P_IDLE;
            endcase
        end
    end
endmodule
