`timescale 1ns / 1ps
// ============================================================================
// object_physics.v  -  Motion of thrown and sliding ingredients
// Owner: Member 2 (Ian Lee)
//
// Holds position, height and velocity of the 8 ingredient objects while the
// kitchen (Member 3) marks them as MOVING. Member 3 keeps identity, ownership
// and preparation state; this module only moves objects and reports events.
//
// Commands from the kitchen (single-cycle pulses, one object per pulse)
//   launch : load start position and horizontal velocity, start airborne
//   reject : landing refused, return to the last floor position and slide back
// Status to the kitchen (levels, per object)
//   air     : object is in the air
//   waiting : object landed on a non-floor tile, waiting for accept / reject
//   stopped : object finished sliding on the floor
//   near_pN : object centre is within 5 px of chef N (used for catching)
// ============================================================================
module object_physics (
    input             clk,
    input             rst,
    input             tick,          // 60 Hz play tick
    input      [7:0]  moving,        // from kitchen: location == MOVING
    input             launch_valid,
    input      [2:0]  launch_idx,
    input      [11:0] launch_x, launch_y,     // Q8.4
    input signed [7:0] launch_vx, launch_vy,  // Q4.4
    input             reject_valid,
    input      [2:0]  reject_idx,
    input      [7:0]  p1_x, input [6:0] p1_y, // chef centres (integer px)
    input      [7:0]  p2_x, input [6:0] p2_y,
    output     [95:0] obj_x_flat,    // 8 x 12-bit Q8.4
    output     [95:0] obj_y_flat,
    output     [71:0] obj_z_flat,    // 8 x 9-bit Q5.4
    output     [31:0] wait_tile_flat,// 8 x 4-bit tile type where it landed
    output     [7:0]  air,
    output     [7:0]  waiting,
    output     [7:0]  stopped,
    output     [7:0]  near_p1,
    output     [7:0]  near_p2
);
    localparam [8:0]        Z_LAUNCH  = 9'd64;   // 4 px above the floor
    localparam signed [7:0] VZ_LAUNCH = 8'sd20;  // 1.25 px per tick upward
    localparam [3:0]        T_FLOOR   = 4'd0;
    localparam [7:0]        CATCH_R   = 8'd5;    // catch radius in px

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : obj
            reg [11:0] x, y, lfx, lfy;      // position and last floor position
            reg [8:0]  z;
            reg signed [7:0] vx, vy, vz;
            reg        a, w, s;             // air, waiting, stopped
            reg [3:0]  wt;                  // tile type where it is waiting

            wire [11:0] nx, ny;
            wire [8:0]  nz;
            wire signed [7:0] nvx, nvy, nvz;
            wire nair, landed, stop_now;
            wire [3:0] cur_tile;

            physics_step step (
                .x(x), .y(y), .z(z), .vx(vx), .vy(vy), .vz(vz), .air(a),
                .nx(nx), .ny(ny), .nz(nz), .nvx(nvx), .nvy(nvy), .nvz(nvz),
                .nair(nair), .landed(landed), .cur_tile(cur_tile),
                .stopped(stop_now));

            always @(posedge clk) begin
                if (rst) begin
                    a <= 1'b0; w <= 1'b0; s <= 1'b0;
                    x <= 12'd0; y <= 12'd0; z <= 9'd0;
                    vx <= 8'sd0; vy <= 8'sd0; vz <= 8'sd0;
                    lfx <= 12'd0; lfy <= 12'd0; wt <= 4'd0;
                end
                else if (launch_valid && launch_idx == i) begin
                    x <= launch_x;  y <= launch_y;  z <= Z_LAUNCH;
                    vx <= launch_vx; vy <= launch_vy; vz <= VZ_LAUNCH;
                    lfx <= launch_x; lfy <= launch_y;
                    a <= 1'b1; w <= 1'b0; s <= 1'b0;
                end
                else if (!moving[i]) begin
                    a <= 1'b0; w <= 1'b0; s <= 1'b0;   // kitchen owns it again
                end
                else if (reject_valid && reject_idx == i) begin
                    x <= lfx; y <= lfy; z <= 9'd0; vz <= 8'sd0;
                    vx <= -(vx >>> 1); vy <= -(vy >>> 1);
                    a <= 1'b0; w <= 1'b0; s <= 1'b0;
                end
                else if (tick && !w && !s) begin
                    x <= nx; y <= ny; z <= nz;
                    vx <= nvx; vy <= nvy; vz <= nvz;
                    a <= nair;
                    if (cur_tile == T_FLOOR) begin
                        lfx <= nx; lfy <= ny;          // remember safe spot
                    end
                    if (a && landed && cur_tile != T_FLOOR) begin
                        w  <= 1'b1;                    // ask the kitchen
                        wt <= cur_tile;
                    end
                    if (!a && stop_now) s <= 1'b1;
                end
            end

            // catch proximity (integer pixel distance on both axes)
            wire [7:0] xi = x[11:4];
            wire [6:0] yi = y[10:4];
            wire [7:0] d1x = (xi > p1_x) ? (xi - p1_x) : (p1_x - xi);
            wire [6:0] d1y = (yi > p1_y) ? (yi - p1_y) : (p1_y - yi);
            wire [7:0] d2x = (xi > p2_x) ? (xi - p2_x) : (p2_x - xi);
            wire [6:0] d2y = (yi > p2_y) ? (yi - p2_y) : (p2_y - yi);

            assign near_p1[i] = (d1x <= CATCH_R) && ({1'b0, d1y} <= CATCH_R);
            assign near_p2[i] = (d2x <= CATCH_R) && ({1'b0, d2y} <= CATCH_R);
            assign obj_x_flat[i*12 +: 12] = x;
            assign obj_y_flat[i*12 +: 12] = y;
            assign obj_z_flat[i*9 +: 9]   = z;
            assign wait_tile_flat[i*4 +: 4] = wt;
            assign air[i]     = a;
            assign waiting[i] = w;
            assign stopped[i] = s;
        end
    endgenerate
endmodule
