`timescale 1ns / 1ps
// ============================================================================
// physics_step.v  -  One 60 Hz physics step for one object (combinational)
// Owner: Member 2 (Ian Lee)
//
// Shared by live motion (object_physics) and the throw preview (predictor),
// so both follow identical numerical rules.
//
// Fixed-point formats
//   x, y : unsigned Q8.4 logical pixels (16 units = 1 px)
//   z    : unsigned Q5.4 height above the floor
//   v*   : signed   Q4.4 pixels per tick (two's complement)
//
// Airborne (air = 1)
//   vz decreases by GRAVITY each tick, z += vz; z <= 0 means landed.
//   Only WALL tiles block horizontal motion (items fly over counters).
//   On a wall hit the velocity component reverses and halves (bounce).
//   On landing the horizontal velocity halves (impact).
// Sliding (air = 0)
//   Friction removes max(|v|/8, 1/16 px) per tick from each component.
//   Any non-floor tile blocks motion (bounce as above).
//   stopped = 1 once both components reach zero.
// ============================================================================
module physics_step (
    input      [11:0]       x, y,
    input      [8:0]        z,
    input  signed [7:0]     vx, vy, vz,
    input                   air,
    output reg [11:0]       nx, ny,
    output reg [8:0]        nz,
    output reg signed [7:0] nvx, nvy, nvz,
    output reg              nair,
    output reg              landed,     // touched the floor this step
    output     [3:0]        cur_tile,   // tile type under (nx, ny)
    output reg              stopped     // sliding item has come to rest
);
    localparam [3:0] T_FLOOR = 4'd0, T_WALL = 4'd1;
    localparam signed [7:0] GRAVITY = 8'sd1;          // 1/16 px per tick^2
    localparam [7:0] X_LIMIT = 8'd160, Y_LIMIT = 8'd120; // logical screen size

    // friction: move v toward zero by max(|v| >> 3, 1)
    function signed [7:0] fric;
        input signed [7:0] v;
        reg [7:0] mag, dec;
        begin
            if (v == 8'sd0) fric = 8'sd0;
            else begin
                mag = v[7] ? (~v + 8'd1) : v;
                dec = (mag[7:3] == 5'd0) ? 8'd1 : {3'b000, mag[7:3]};
                mag = mag - dec;
                fric = v[7] ? (~mag + 8'd1) : mag;
            end
        end
    endfunction

    // reverse and halve (bounce)
    function signed [7:0] bounce;
        input signed [7:0] v;
        begin
            bounce = -(v >>> 1);
        end
    endfunction

    // velocity used for this step
    wire signed [7:0] ux = air ? vx : fric(vx);
    wire signed [7:0] uy = air ? vy : fric(vy);

    // ---------------- X axis ----------------
    wire signed [12:0] x_try = $signed({1'b0, x}) + {{5{ux[7]}}, ux};
    wire x_oob = x_try[12] | (x_try[11:4] >= X_LIMIT);
    wire [11:0] x_try_u = x_try[11:0];
    wire [4:0]  xm_tx = x_try_u[11:7];
    wire [3:0]  xm_ty = y[10:7];
    wire [3:0]  tile_xm;
    map_rom m_x (.tx(xm_tx), .ty(xm_ty), .tile(tile_xm));
    wire x_block = x_oob | (air ? (tile_xm == T_WALL) : (tile_xm != T_FLOOR));
    wire [11:0] x_new = x_block ? x : x_try_u;

    // ---------------- Y axis (uses the new x) ----------------
    wire signed [12:0] y_try = $signed({1'b0, y}) + {{5{uy[7]}}, uy};
    wire y_oob = y_try[12] | (y_try[11:4] >= Y_LIMIT);
    wire [11:0] y_try_u = y_try[11:0];
    wire [4:0]  ym_tx = x_new[11:7];
    wire [3:0]  ym_ty = y_try_u[10:7];
    wire [3:0]  tile_ym;
    map_rom m_y (.tx(ym_tx), .ty(ym_ty), .tile(tile_ym));
    wire y_block = y_oob | (air ? (tile_ym == T_WALL) : (tile_ym != T_FLOOR));
    wire [11:0] y_new = y_block ? y : y_try_u;

    // tile under the final position
    wire [4:0]  c_tx = x_new[11:7];
    wire [3:0]  c_ty = y_new[10:7];
    map_rom m_c (.tx(c_tx), .ty(c_ty), .tile(cur_tile));

    // ---------------- Z axis ----------------
    wire signed [10:0] z_sum = $signed({2'b00, z}) + {{3{vz[7]}}, vz};
    wire touch = (z_sum <= 11'sd0);

    always @* begin
        nx  = x_new;
        ny  = y_new;
        nvx = x_block ? bounce(ux) : ux;
        nvy = y_block ? bounce(uy) : uy;
        nz  = 9'd0;
        nvz = 8'sd0;
        nair = 1'b0;
        landed = 1'b0;
        stopped = 1'b0;
        if (air) begin
            if (touch) begin
                landed = 1'b1;                 // reached the floor
                nvx = nvx >>> 1;               // impact halves the speed
                nvy = nvy >>> 1;
            end else begin
                nair = 1'b1;
                nz   = z_sum[8:0];
                nvz  = (vz == -8'sd64) ? vz : (vz - GRAVITY); // clamp fall speed
            end
        end else begin
            stopped = (nvx == 8'sd0) && (nvy == 8'sd0);
        end
    end
endmodule
