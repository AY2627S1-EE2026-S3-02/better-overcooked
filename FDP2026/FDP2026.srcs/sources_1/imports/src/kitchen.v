`timescale 1ns / 1ps
// ============================================================================
// kitchen.v  -  Kitchen simulation and game-state management
// Owner: Member 3 (Chan Chee Heng)
//
// Owns ingredient identities, preparation states, player inventories,
// station contents and recipes. Every object is in exactly ONE location:
//   L_TILE   resting on a tile (floor, counter, board, conveyor)
//   L_HELD   in a player's hands (holder 0 = P1, 1 = P2)
//   L_MOVING thrown or sliding (Member 2's physics moves it)
// A player's inventory is derived from the object records, so an object can
// never be in two places and ingredients are conserved by construction.
//
// Sequencer (runs once per 60 Hz play tick, a few clock cycles long):
//   S_OBJ x8 : physics events of object k (landing accept/reject, stop,
//              catch) and conveyor movement
//   S_PA     : actions of the player with priority this tick
//   S_GAP    : lets the order list settle after a serve
//   S_PB     : actions of the other player
//   S_STATION: stove timers, conveyor timer, swap priority
// Handling one request per cycle resolves all competing requests.
// ============================================================================
module kitchen (
    input             clk,
    input             rst,
    input             tick,          // 60 Hz tick, only while playing
    input             round_reset,
    // player requests (from Member 1), each valid for one tick
    input             p1_tap, p1_hold, p1_release,
    input signed [7:0] p1_vx, p1_vy,
    input             p2_tap, p2_hold, p2_release,
    input signed [7:0] p2_vx, p2_vy,
    // chef positions (from Member 2)
    input      [7:0]  p1_x, input [6:0] p1_y, input [1:0] p1_face,
    input      [7:0]  p2_x, input [6:0] p2_y, input [1:0] p2_face,
    // physics status (from Member 2)
    input      [95:0] ph_x_flat, ph_y_flat,
    input      [7:0]  ph_air, ph_wait, ph_stop, ph_near1, ph_near2,
    // order list (from orders)
    input             has_soup, has_salad,
    output reg        serve_valid,
    output reg        serve_recipe,  // 0 soup, 1 salad
    // physics commands (to Member 2)
    output     [7:0]  moving,
    output reg        launch_valid,
    output reg [2:0]  launch_idx,
    output reg [11:0] launch_x, launch_y,
    output reg signed [7:0] launch_vx, launch_vy,
    output reg        reject_valid,
    output reg [2:0]  reject_idx,
    // player state
    output            p1_holding, p2_holding,
    output            p1_aiming,  p2_aiming,
    // object records (for displays)
    output     [7:0]  obj_used,
    output     [15:0] obj_kind_flat,   // 2 bits each: 0 tomato, 1 lettuce, 2 plate
    output     [7:0]  obj_chopped,
    output     [23:0] obj_plate_flat,  // 3 bits each: {soup, lettuce, tomato}
    output     [15:0] obj_loc_flat,    // 2 bits each: 0 tile, 1 held, 2 moving
    output     [7:0]  obj_holder,
    output     [39:0] obj_tx_flat,     // 5 bits each
    output     [31:0] obj_ty_flat,     // 4 bits each
    // station status (for displays)
    output reg [6:0]  chop0_prog, chop1_prog,
    output     [2:0]  pot0_state, pot1_state,
    output     [8:0]  pot0_timer, pot1_timer,
    output     [1:0]  pot0_count, pot1_count
);
    // ---------------- constants ----------------
    localparam [3:0] T_FLOOR = 4'd0, T_WALL = 4'd1, T_COUNTER = 4'd2,
                     T_CRATE_TOM = 4'd3, T_CRATE_LET = 4'd4, T_CHOP = 4'd5,
                     T_STOVE = 4'd6, T_PLATES = 4'd7, T_SERVE = 4'd8,
                     T_BIN = 4'd9, T_CONV = 4'd10;
    localparam [1:0] K_TOMATO = 2'd0, K_LETTUCE = 2'd1, K_PLATE = 2'd2;
    localparam [1:0] L_TILE = 2'd0, L_HELD = 2'd1, L_MOVING = 2'd2;
    localparam [2:0] POT_EMPTY = 3'd0, POT_FILL = 3'd1, POT_COOK = 3'd2,
                     POT_DONE = 3'd3, POT_BURNT = 3'd4;
    localparam [6:0] CHOP_T  = 7'd96;    // 1.6 s of chopping
    localparam [8:0] COOK_T  = 9'd384;   // 6.4 s to cook soup
    localparam [8:0] BURN_T  = 9'd256;   // 4.3 s more and it burns
    localparam [3:0] CONV_P  = 4'd15;    // conveyor step every 0.25 s
    localparam [4:0] CHOP0_X = 5'd4, CHOP1_X = 5'd6;
    localparam [4:0] STOVE0_X = 5'd11, STOVE1_X = 5'd13;
    localparam [3:0] STATION_Y = 4'd3;

    localparam [2:0] S_IDLE = 3'd0, S_OBJ = 3'd1, S_PA = 3'd2, S_GAP = 3'd3,
                     S_PB = 3'd4, S_STATION = 3'd5;

    // ---------------- object records ----------------
    reg        used    [0:7];
    reg [1:0]  kind    [0:7];
    reg        chopped [0:7];
    reg [6:0]  chop    [0:7];
    reg [2:0]  plate   [0:7];
    reg [1:0]  loc     [0:7];
    reg        holder  [0:7];
    reg        thrower [0:7];
    reg [4:0]  otx     [0:7];
    reg [3:0]  oty     [0:7];

    // ---------------- stations ----------------
    reg [2:0]  pot_state [0:1];
    reg [1:0]  pot_count [0:1];
    reg [8:0]  pot_timer [0:1];

    reg [2:0]  st;
    reg [2:0]  k;
    reg        prio;      // 0: P1 acts first this tick
    reg [3:0]  conv_cnt;

    // ---------------- outputs of the records ----------------
    genvar gi;
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : out_map
            assign obj_used[gi]              = used[gi];
            assign obj_kind_flat[gi*2 +: 2]  = kind[gi];
            assign obj_chopped[gi]           = chopped[gi];
            assign obj_plate_flat[gi*3 +: 3] = plate[gi];
            assign obj_loc_flat[gi*2 +: 2]   = loc[gi];
            assign obj_holder[gi]            = holder[gi];
            assign obj_tx_flat[gi*5 +: 5]    = otx[gi];
            assign obj_ty_flat[gi*4 +: 4]    = oty[gi];
            assign moving[gi] = used[gi] && (loc[gi] == L_MOVING);
        end
    endgenerate
    assign pot0_state = pot_state[0]; assign pot1_state = pot_state[1];
    assign pot0_timer = pot_timer[0]; assign pot1_timer = pot_timer[1];
    assign pot0_count = pot_count[0]; assign pot1_count = pot_count[1];

    // ---------------- helper functions ----------------
    // can this chopped ingredient go onto this plate?
    function plate_accepts;
        input [2:0] pl; input [1:0] kd; input ch;
        begin
            plate_accepts = ch && !pl[2] &&
                            ((kd == K_TOMATO  && !pl[0]) ||
                             (kd == K_LETTUCE && !pl[1]));
        end
    endfunction

    function [2:0] plate_bit;
        input [1:0] kd;
        plate_bit = (kd == K_TOMATO) ? 3'b001 : 3'b010;
    endfunction

    // ---------------- inventories (derived) ----------------
    reg       h1, h2;
    reg [2:0] h1_idx, h2_idx;
    integer i;
    always @* begin
        h1 = 1'b0; h2 = 1'b0; h1_idx = 3'd0; h2_idx = 3'd0;
        for (i = 7; i >= 0; i = i - 1) begin
            if (used[i] && loc[i] == L_HELD && holder[i] == 1'b0) begin
                h1 = 1'b1; h1_idx = i[2:0];
            end
            if (used[i] && loc[i] == L_HELD && holder[i] == 1'b1) begin
                h2 = 1'b1; h2_idx = i[2:0];
            end
        end
    end
    assign p1_holding = h1;
    assign p2_holding = h2;
    assign p1_aiming  = p1_hold && h1 && (kind[h1_idx] != K_PLATE);
    assign p2_aiming  = p2_hold && h2 && (kind[h2_idx] != K_PLATE);

    // ---------------- current player (player phases) ----------------
    wire cp = (st == S_PB) ? ~prio : prio;           // 0 = P1, 1 = P2
    wire        c_tap     = cp ? p2_tap     : p1_tap;
    wire        c_hold    = cp ? p2_hold    : p1_hold;
    wire        c_release = cp ? p2_release : p1_release;
    wire signed [7:0] c_vx = cp ? p2_vx : p1_vx;
    wire signed [7:0] c_vy = cp ? p2_vy : p1_vy;
    wire [7:0]  c_x    = cp ? p2_x    : p1_x;
    wire [6:0]  c_y    = cp ? p2_y    : p1_y;
    wire [1:0]  c_face = cp ? p2_face : p1_face;
    wire        c_has  = cp ? h2      : h1;
    wire [2:0]  c_hi   = cp ? h2_idx  : h1_idx;

    // facing point: 6 px from the centre in the facing direction
    reg [7:0] fpx; reg [6:0] fpy;
    always @* begin
        fpx = c_x; fpy = c_y;
        case (c_face)
            2'd0: fpy = c_y - 7'd6;
            2'd1: fpy = c_y + 7'd6;
            2'd2: fpx = c_x - 8'd6;
            default: fpx = c_x + 8'd6;
        endcase
    end
    wire [4:0] ftx = fpx[7:3];
    wire [3:0] fty = fpy[6:3];
    wire [3:0] f_tile;
    map_rom m_face (.tx(ftx), .ty(fty), .tile(f_tile));

    // ---------------- object phase query tile ----------------
    wire [11:0] kx = ph_x_flat[k*12 +: 12];
    wire [11:0] ky = ph_y_flat[k*12 +: 12];
    wire        k_moving = used[k] && (loc[k] == L_MOVING);
    wire [4:0]  q_tx = k_moving ? kx[11:7] : (otx[k] + 5'd1);  // landing tile or conveyor target
    wire [3:0]  q_ty = k_moving ? ky[10:7] : oty[k];
    wire [3:0]  q_tile, k_tile;
    map_rom m_q (.tx(q_tx), .ty(q_ty), .tile(q_tile));
    map_rom m_k (.tx(otx[k]), .ty(oty[k]), .tile(k_tile));

    // ---------------- searches ----------------
    reg       f_found, q_found, free_found;
    reg [2:0] f_idx, q_idx, free_idx;
    always @* begin
        f_found = 1'b0; q_found = 1'b0; free_found = 1'b0;
        f_idx = 3'd0; q_idx = 3'd0; free_idx = 3'd0;
        for (i = 7; i >= 0; i = i - 1) begin
            if (used[i] && loc[i] == L_TILE && otx[i] == ftx && oty[i] == fty) begin
                f_found = 1'b1; f_idx = i[2:0];
            end
            if (used[i] && loc[i] == L_TILE && otx[i] == q_tx && oty[i] == q_ty) begin
                q_found = 1'b1; q_idx = i[2:0];
            end
            if (!used[i]) begin
                free_found = 1'b1; free_idx = i[2:0];
            end
        end
    end

    // stove addressed by a tile column (only valid on stove tiles)
    wire f_stove = (ftx == STOVE1_X);
    wire q_stove = (q_tx == STOVE1_X);

    // ---------------- chopping board progress (for displays) ----------------
    always @* begin
        chop0_prog = 7'd0; chop1_prog = 7'd0;
        for (i = 0; i < 8; i = i + 1) begin
            if (used[i] && loc[i] == L_TILE && !chopped[i] && oty[i] == STATION_Y) begin
                if (otx[i] == CHOP0_X) chop0_prog = chop[i];
                if (otx[i] == CHOP1_X) chop1_prog = chop[i];
            end
        end
    end

    // ---------------- sequencer ----------------
    integer s;
    always @(posedge clk) begin
        // single-cycle command pulses
        launch_valid <= 1'b0;
        reject_valid <= 1'b0;
        serve_valid  <= 1'b0;

        if (rst || round_reset) begin
            for (i = 0; i < 8; i = i + 1) begin
                used[i] <= 1'b0; kind[i] <= K_TOMATO; chopped[i] <= 1'b0;
                chop[i] <= 7'd0; plate[i] <= 3'd0; loc[i] <= L_TILE;
                holder[i] <= 1'b0; thrower[i] <= 1'b0;
                otx[i] <= 5'd0; oty[i] <= 4'd0;
            end
            for (s = 0; s < 2; s = s + 1) begin
                pot_state[s] <= POT_EMPTY; pot_count[s] <= 2'd0; pot_timer[s] <= 9'd0;
            end
            st <= S_IDLE; k <= 3'd0; prio <= 1'b0; conv_cnt <= 4'd0;
            launch_idx <= 3'd0; launch_x <= 12'd0; launch_y <= 12'd0;
            launch_vx <= 8'sd0; launch_vy <= 8'sd0;
            reject_idx <= 3'd0; serve_recipe <= 1'b0;
        end
        else begin
            case (st)
            // ------------------------------------------------------------
            S_IDLE: begin
                if (tick) begin
                    st <= S_OBJ;
                    k  <= 3'd0;
                end
            end
            // ------------------------------------------------------------
            S_OBJ: begin
                if (k_moving) begin
                    if (ph_wait[k]) begin
                        // landed on a non-floor tile: accept or reject
                        case (q_tile)
                            T_COUNTER, T_CONV: begin
                                if (!q_found) begin
                                    loc[k] <= L_TILE; otx[k] <= q_tx; oty[k] <= q_ty;
                                end else if (kind[q_idx] == K_PLATE && kind[k] != K_PLATE &&
                                             plate_accepts(plate[q_idx], kind[k], chopped[k])) begin
                                    plate[q_idx] <= plate[q_idx] | plate_bit(kind[k]);
                                    used[k] <= 1'b0; loc[k] <= L_TILE;
                                end else begin
                                    reject_valid <= 1'b1; reject_idx <= k;
                                end
                            end
                            T_CHOP: begin
                                if (!q_found && kind[k] != K_PLATE) begin
                                    loc[k] <= L_TILE; otx[k] <= q_tx; oty[k] <= q_ty;
                                end else begin
                                    reject_valid <= 1'b1; reject_idx <= k;
                                end
                            end
                            T_STOVE: begin
                                if (kind[k] == K_TOMATO && chopped[k] &&
                                    (pot_state[q_stove] == POT_EMPTY || pot_state[q_stove] == POT_FILL)) begin
                                    used[k] <= 1'b0; loc[k] <= L_TILE;
                                    if (pot_count[q_stove] == 2'd1) begin
                                        pot_state[q_stove] <= POT_COOK; pot_count[q_stove] <= 2'd2;
                                        pot_timer[q_stove] <= 9'd0;
                                    end else begin
                                        pot_state[q_stove] <= POT_FILL; pot_count[q_stove] <= 2'd1;
                                    end
                                end else begin
                                    reject_valid <= 1'b1; reject_idx <= k;
                                end
                            end
                            T_BIN: begin
                                used[k] <= 1'b0; loc[k] <= L_TILE;   // thrown into the bin
                            end
                            default: begin
                                reject_valid <= 1'b1; reject_idx <= k;
                            end
                        endcase
                    end
                    else if (ph_stop[k]) begin
                        // finished sliding: rest on the floor tile
                        loc[k] <= L_TILE; otx[k] <= q_tx; oty[k] <= q_ty;
                    end
                    else if (ph_air[k]) begin
                        // automatic catch by an empty-handed teammate
                        if (ph_near1[k] && !h1 && thrower[k] != 1'b0) begin
                            loc[k] <= L_HELD; holder[k] <= 1'b0;
                        end else if (ph_near2[k] && !h2 && thrower[k] != 1'b1) begin
                            loc[k] <= L_HELD; holder[k] <= 1'b1;
                        end
                    end
                end
                else if (used[k] && loc[k] == L_TILE && k_tile == T_CONV && conv_cnt == 4'd0) begin
                    // conveyor: move one tile to the right if the next tile is free
                    if ((q_tile == T_CONV || q_tile == T_COUNTER) && !q_found)
                        otx[k] <= q_tx;
                end

                if (k == 3'd7) st <= S_PA;
                else           k  <= k + 3'd1;
            end
            // ------------------------------------------------------------
            S_PA, S_PB: begin
                if (c_tap) begin
                    if (c_has) begin
                        // ----- carrying something -----
                        case (f_tile)
                            T_FLOOR: if (!f_found) begin
                                loc[c_hi] <= L_TILE; otx[c_hi] <= ftx; oty[c_hi] <= fty;
                            end
                            T_COUNTER, T_CONV: begin
                                if (!f_found) begin
                                    loc[c_hi] <= L_TILE; otx[c_hi] <= ftx; oty[c_hi] <= fty;
                                end else if (kind[f_idx] == K_PLATE && kind[c_hi] != K_PLATE &&
                                             plate_accepts(plate[f_idx], kind[c_hi], chopped[c_hi])) begin
                                    plate[f_idx] <= plate[f_idx] | plate_bit(kind[c_hi]);
                                    used[c_hi] <= 1'b0; loc[c_hi] <= L_TILE;
                                end else if (kind[c_hi] == K_PLATE && kind[f_idx] != K_PLATE &&
                                             plate_accepts(plate[c_hi], kind[f_idx], chopped[f_idx])) begin
                                    plate[c_hi] <= plate[c_hi] | plate_bit(kind[f_idx]);
                                    used[f_idx] <= 1'b0; loc[f_idx] <= L_TILE;
                                end
                            end
                            T_CHOP: if (!f_found && kind[c_hi] != K_PLATE) begin
                                loc[c_hi] <= L_TILE; otx[c_hi] <= ftx; oty[c_hi] <= fty;
                            end
                            T_STOVE: begin
                                if (kind[c_hi] == K_TOMATO && chopped[c_hi] &&
                                    (pot_state[f_stove] == POT_EMPTY || pot_state[f_stove] == POT_FILL)) begin
                                    used[c_hi] <= 1'b0; loc[c_hi] <= L_TILE;
                                    if (pot_count[f_stove] == 2'd1) begin
                                        pot_state[f_stove] <= POT_COOK; pot_count[f_stove] <= 2'd2;
                                        pot_timer[f_stove] <= 9'd0;
                                    end else begin
                                        pot_state[f_stove] <= POT_FILL; pot_count[f_stove] <= 2'd1;
                                    end
                                end else if (kind[c_hi] == K_PLATE && plate[c_hi] == 3'd0 &&
                                             pot_state[f_stove] == POT_DONE) begin
                                    plate[c_hi] <= 3'b100;                     // soup on the plate
                                    pot_state[f_stove] <= POT_EMPTY;
                                    pot_count[f_stove] <= 2'd0;
                                    pot_timer[f_stove] <= 9'd0;
                                end
                            end
                            T_SERVE: begin
                                if (kind[c_hi] == K_PLATE) begin
                                    if (plate[c_hi][2] && has_soup) begin
                                        used[c_hi] <= 1'b0; loc[c_hi] <= L_TILE;
                                        serve_valid <= 1'b1; serve_recipe <= 1'b0;
                                    end else if (!plate[c_hi][2] && plate[c_hi][1:0] == 2'b11 && has_salad) begin
                                        used[c_hi] <= 1'b0; loc[c_hi] <= L_TILE;
                                        serve_valid <= 1'b1; serve_recipe <= 1'b1;
                                    end
                                end
                            end
                            T_BIN: begin
                                used[c_hi] <= 1'b0; loc[c_hi] <= L_TILE;
                            end
                            default: ;
                        endcase
                    end else begin
                        // ----- empty-handed -----
                        case (f_tile)
                            T_FLOOR, T_COUNTER, T_CONV, T_CHOP: if (f_found) begin
                                loc[f_idx] <= L_HELD; holder[f_idx] <= cp;
                            end
                            T_CRATE_TOM, T_CRATE_LET, T_PLATES: if (free_found) begin
                                used[free_idx]    <= 1'b1;
                                kind[free_idx]    <= (f_tile == T_CRATE_TOM) ? K_TOMATO :
                                                     (f_tile == T_CRATE_LET) ? K_LETTUCE : K_PLATE;
                                chopped[free_idx] <= 1'b0;
                                chop[free_idx]    <= 7'd0;
                                plate[free_idx]   <= 3'd0;
                                loc[free_idx]     <= L_HELD;
                                holder[free_idx]  <= cp;
                                thrower[free_idx] <= cp;
                            end
                            T_STOVE: if (pot_state[f_stove] == POT_BURNT) begin
                                pot_state[f_stove] <= POT_EMPTY;          // scrape the pot
                                pot_count[f_stove] <= 2'd0;
                                pot_timer[f_stove] <= 9'd0;
                            end
                            default: ;
                        endcase
                    end
                end
                else if (c_hold && !c_has) begin
                    // chopping while holding the centre button at a board
                    if (f_tile == T_CHOP && f_found && kind[f_idx] != K_PLATE && !chopped[f_idx]) begin
                        if (chop[f_idx] >= CHOP_T - 7'd1) begin
                            chopped[f_idx] <= 1'b1;
                            chop[f_idx]    <= 7'd0;
                        end else
                            chop[f_idx] <= chop[f_idx] + 7'd1;
                    end
                end
                else if (c_release && c_has && kind[c_hi] != K_PLATE) begin
                    // throw the held ingredient
                    loc[c_hi]     <= L_MOVING;
                    thrower[c_hi] <= cp;
                    launch_valid  <= 1'b1;
                    launch_idx    <= c_hi;
                    launch_x      <= {c_x, 4'd0};
                    launch_y      <= {1'b0, c_y, 4'd0};
                    launch_vx     <= c_vx;
                    launch_vy     <= c_vy;
                end

                st <= (st == S_PA) ? S_GAP : S_STATION;
            end
            // ------------------------------------------------------------
            S_GAP: st <= S_PB;
            // ------------------------------------------------------------
            S_STATION: begin
                for (s = 0; s < 2; s = s + 1) begin
                    if (pot_state[s] == POT_COOK) begin
                        if (pot_timer[s] >= COOK_T - 9'd1) begin
                            pot_state[s] <= POT_DONE; pot_timer[s] <= 9'd0;
                        end else pot_timer[s] <= pot_timer[s] + 9'd1;
                    end else if (pot_state[s] == POT_DONE) begin
                        if (pot_timer[s] >= BURN_T - 9'd1) begin
                            pot_state[s] <= POT_BURNT; pot_timer[s] <= 9'd0;
                        end else pot_timer[s] <= pot_timer[s] + 9'd1;
                    end
                end
                conv_cnt <= (conv_cnt == CONV_P - 4'd1) ? 4'd0 : conv_cnt + 4'd1;
                prio <= ~prio;
                st   <= S_IDLE;
            end
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule
