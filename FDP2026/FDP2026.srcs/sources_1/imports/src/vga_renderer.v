`timescale 1ns / 1ps
// ============================================================================
// vga_renderer.v  -  Draws the kitchen, chefs, items and HUD on VGA
// Owner: Member 4 (Heng Yong Hen)
//
// The 640 x 480 picture is a 160 x 120 logical image scaled by 4. Each
// logical pixel is computed from the game state (tile-and-sprite rendering,
// no frame buffer). The game state only changes during vertical blanking,
// so every frame is drawn from a stable snapshot.
// Layer order (front to back):
//   HUD strip > state banner > airborne items > throw preview > charge bar
//   > held items > chefs > resting / sliding items > shadows > tiles
// ============================================================================
module vga_renderer (
    input             clk,
    input      [9:0]  h, v,
    input             active,
    input             frame_tick,
    // flow
    input      [2:0]  flow_state,
    input      [1:0]  ready,
    input      [1:0]  count_s,
    input      [7:0]  time_s,
    input      [9:0]  score,
    // chefs
    input      [7:0]  p1_x, input [6:0] p1_y, input [1:0] p1_face,
    input      [7:0]  p2_x, input [6:0] p2_y, input [1:0] p2_face,
    input             p1_aiming, p2_aiming,
    input      [1:0]  p1_charge, p2_charge,
    // objects
    input      [7:0]  obj_used,
    input      [15:0] obj_kind_flat,
    input      [7:0]  obj_chopped,
    input      [23:0] obj_plate_flat,
    input      [15:0] obj_loc_flat,
    input      [7:0]  obj_holder,
    input      [39:0] obj_tx_flat,
    input      [31:0] obj_ty_flat,
    input      [95:0] ph_x_flat, ph_y_flat,
    input      [71:0] ph_z_flat,
    input      [7:0]  ph_air,
    // stations
    input      [6:0]  chop0_prog, chop1_prog,
    input      [2:0]  pot0_state, pot1_state,
    input      [8:0]  pot0_timer, pot1_timer,
    // orders
    input      [2:0]  ord_valid, ord_recipe,
    input      [35:0] ord_time_flat,
    // throw preview
    input      [3:0]  p1_n, p2_n,
    input      [63:0] p1_dx_flat, p2_dx_flat,
    input      [55:0] p1_dy_flat, p2_dy_flat,
    input             p1_land_v, p2_land_v,
    input      [7:0]  p1_land_x, p2_land_x,
    input      [6:0]  p1_land_y, p2_land_y,
    output reg [11:0] rgb
);
    // ---------------- constants ----------------
    localparam [3:0] T_FLOOR = 4'd0, T_WALL = 4'd1, T_COUNTER = 4'd2,
                     T_CRATE_TOM = 4'd3, T_CRATE_LET = 4'd4, T_CHOP = 4'd5,
                     T_STOVE = 4'd6, T_PLATES = 4'd7, T_SERVE = 4'd8,
                     T_BIN = 4'd9, T_CONV = 4'd10;
    localparam [1:0] L_TILE = 2'd0, L_HELD = 2'd1, L_MOVING = 2'd2;
    localparam [2:0] POT_FILL = 3'd1, POT_COOK = 3'd2, POT_DONE = 3'd3, POT_BURNT = 3'd4;
    localparam [2:0] F_READY = 3'd0, F_COUNT = 3'd1, F_PLAY = 3'd2,
                     F_PAUSE = 3'd3, F_RESULTS = 3'd4;
    localparam [11:0] C_P1 = 12'h37E, C_P2 = 12'hE53;

    // ---------------- animation counter ----------------
    reg [5:0] anim = 6'd0;
    always @(posedge clk) if (frame_tick) anim <= anim + 6'd1;

    // ---------------- logical pixel ----------------
    wire [7:0] lx = h[9:2];
    wire [6:0] ly = v[8:2];
    wire [4:0] tx = lx[7:3];
    wire [3:0] ty = ly[6:3];
    wire [2:0] ox = lx[2:0];
    wire [2:0] oy = ly[2:0];

    function [6:0] sq;             // (2*o - 7)^2
        input [2:0] o;
        case (o)
            3'd0, 3'd7: sq = 7'd49;
            3'd1, 3'd6: sq = 7'd25;
            3'd2, 3'd5: sq = 7'd9;
            default:    sq = 7'd1;
        endcase
    endfunction
    wire [7:0] r2 = sq(ox) + sq(oy);

    // ================================================================
    // TILES
    // ================================================================
    wire [3:0] tile;
    map_rom m_px (.tx(tx), .ty(ty), .tile(tile));

    // crate icon
    wire        crate_op;
    wire [11:0] crate_col;
    item_sprite crate_icon (.kind(tile == T_CRATE_LET ? 2'd1 : 2'd0), .chopped(1'b0),
        .plate(3'd0), .ox(ox), .oy(oy), .opaque(crate_op), .color(crate_col));

    // station status at this tile
    wire        is_chop1  = (tx == 5'd6);
    wire [6:0]  cprog     = is_chop1 ? chop1_prog : chop0_prog;
    wire [3:0]  cbar      = (cprog == 7'd0) ? 4'd0 : ({1'b0, cprog[6:4]} + 4'd1);
    wire        is_stove1 = (tx == 5'd13);
    wire [2:0]  pst       = is_stove1 ? pot1_state : pot0_state;
    wire [8:0]  ptm       = is_stove1 ? pot1_timer : pot0_timer;
    wire [3:0]  pbar      = (pst == POT_COOK) ? ({1'b0, ptm[8:6]} + 4'd1) :
                            (pst == POT_DONE) ? ({1'b0, ptm[7:5]} + 4'd1) : 4'd8;

    reg [11:0] tile_rgb;
    always @* begin
        case (tile)
            T_FLOOR: begin
                tile_rgb = (tx[0] ^ ty[0]) ? 12'hDCA : 12'hCB9;
                if (ox == 3'd0 || oy == 3'd0) tile_rgb = 12'hA98;
            end
            T_WALL: begin
                tile_rgb = 12'h556;
                if (oy == 3'd3 || oy == 3'd7 || ox == (oy < 3'd4 ? 3'd1 : 3'd5)) tile_rgb = 12'h334;
            end
            T_CRATE_TOM, T_CRATE_LET: begin
                tile_rgb = 12'h853;
                if (ox == 3'd0 || ox == 3'd7 || oy == 3'd0 || oy == 3'd7) tile_rgb = 12'h531;
                if (crate_op) tile_rgb = crate_col;
            end
            T_CHOP: begin
                tile_rgb = (oy == 3'd0) ? 12'hB84 : 12'h962;
                if (ox >= 3'd1 && ox <= 3'd6 && oy >= 3'd1 && oy <= 3'd5) tile_rgb = 12'hECA;
                if (oy == 3'd7) tile_rgb = ({1'b0, ox} < cbar) ? 12'h2D2 : 12'h641;
            end
            T_STOVE: begin
                tile_rgb = 12'h444;
                if (r2 >= 8'd26 && r2 <= 8'd44)
                    tile_rgb = (pst == POT_COOK || pst == POT_DONE) ?
                               (anim[2] ? 12'hF52 : 12'hD31) : 12'h733;
                if (r2 <= 8'd18) begin
                    tile_rgb = 12'h999;                                  // pot
                    if (r2 <= 8'd10) case (pst)
                        POT_FILL:  tile_rgb = 12'hD21;
                        POT_COOK:  tile_rgb = 12'hE73;
                        POT_DONE:  tile_rgb = 12'hF94;
                        POT_BURNT: tile_rgb = anim[3] ? 12'h111 : 12'h400;
                        default:   tile_rgb = 12'h777;
                    endcase
                end
                if (oy == 3'd7 && (pst == POT_COOK || pst == POT_DONE || pst == POT_BURNT)) begin
                    if ({1'b0, ox} < pbar)
                        tile_rgb = (pst == POT_COOK) ? 12'h2D2 : (anim[3] ? 12'hF22 : 12'hA11);
                end
            end
            T_PLATES: begin
                tile_rgb = (oy == 3'd0) ? 12'hB84 : 12'h962;
                if (ox >= 3'd1 && ox <= 3'd6 && (oy == 3'd2 || oy == 3'd5)) tile_rgb = 12'hFFF;
                if (ox >= 3'd1 && ox <= 3'd6 && (oy == 3'd3 || oy == 3'd6)) tile_rgb = 12'hAAB;
            end
            T_SERVE: begin
                tile_rgb = (((ox + oy + anim[4:2]) & 3'd2) != 3'd0) ? 12'hFC2 : 12'h332;
                if (ox == 3'd0 || ox == 3'd7) tile_rgb = 12'h222;
            end
            T_BIN: begin
                tile_rgb = (oy == 3'd0) ? 12'hB84 : 12'h962;
                if (ox >= 3'd2 && ox <= 3'd5 && oy >= 3'd2 && oy <= 3'd6) tile_rgb = 12'h667;
                if (ox >= 3'd1 && ox <= 3'd6 && oy == 3'd1) tile_rgb = 12'h889;
            end
            T_CONV: begin
                tile_rgb = (((ox - anim[4:2]) & 3'd3) == 3'd0 && oy >= 3'd2 && oy <= 3'd5) ? 12'h888 : 12'h444;
                if (oy == 3'd0 || oy == 3'd7) tile_rgb = 12'h222;
            end
            default: begin                                               // counter
                tile_rgb = 12'h962;
                if (oy == 3'd0) tile_rgb = 12'hB84;
                if (oy == 3'd7) tile_rgb = 12'h641;
            end
        endcase
    end

    // ================================================================
    // OBJECTS (8)
    // ================================================================
    reg  [7:0]  o_hit;
    reg  [15:0] o_layer;                   // 2 bits each: 0 ground, 2 held, 3 air
    wire [7:0]  o_op;
    wire [95:0] o_col;
    reg  [7:0]  sh_hit;                    // shadows of airborne items

    genvar gi;
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : objs
            wire [1:0]  kd  = obj_kind_flat[gi*2 +: 2];
            wire [1:0]  lc  = obj_loc_flat[gi*2 +: 2];
            wire [7:0]  pxi = ph_x_flat[gi*12+4 +: 8];
            wire [6:0]  pyi = ph_y_flat[gi*12+4 +: 7];
            wire [4:0]  pzi = ph_z_flat[gi*9+4 +: 5];
            wire [7:0]  hx  = obj_holder[gi] ? p2_x : p1_x;
            wire [6:0]  hy  = obj_holder[gi] ? p2_y : p1_y;
            reg  signed [9:0] sx, sy;
            always @* begin
                case (lc)
                    L_TILE: begin
                        sx = {2'b00, obj_tx_flat[gi*5 +: 5], 3'b000};
                        sy = {3'b000, obj_ty_flat[gi*4 +: 4], 3'b000};
                    end
                    L_HELD: begin
                        sx = $signed({2'b00, hx}) - 10'sd4;
                        sy = $signed({3'b000, hy}) - 10'sd11;
                    end
                    default: begin
                        sx = $signed({2'b00, pxi}) - 10'sd4;
                        sy = $signed({3'b000, pyi}) - (ph_air[gi] ? $signed({5'b0, pzi}) : 10'sd0) - 10'sd4;
                    end
                endcase
            end
            wire signed [9:0] dx = $signed({2'b00, lx}) - sx;
            wire signed [9:0] dy = $signed({3'b000, ly}) - sy;
            wire in_box = (dx >= 0) && (dx < 8) && (dy >= 0) && (dy < 8);
            item_sprite spr (.kind(kd), .chopped(obj_chopped[gi]),
                .plate(obj_plate_flat[gi*3 +: 3]), .ox(dx[2:0]), .oy(dy[2:0]),
                .opaque(o_op[gi]), .color(o_col[gi*12 +: 12]));
            always @* begin
                o_hit[gi]          = obj_used[gi] && in_box;
                o_layer[gi*2 +: 2] = (lc == L_HELD) ? 2'd2 :
                                     (lc == L_MOVING && ph_air[gi]) ? 2'd3 : 2'd0;
                sh_hit[gi] = obj_used[gi] && lc == L_MOVING && ph_air[gi] &&
                             (lx + 8'd2 >= pxi) && (lx <= pxi + 8'd2) &&
                             (ly + 7'd1 >= pyi) && (ly <= pyi + 7'd1);
            end
        end
    endgenerate

    // pick the front-most opaque object pixel for each layer
    reg        air_on, held_on, gnd_on;
    reg [11:0] air_c, held_c, gnd_c;
    integer i;
    always @* begin
        air_on = 1'b0; held_on = 1'b0; gnd_on = 1'b0;
        air_c = 12'h000; held_c = 12'h000; gnd_c = 12'h000;
        for (i = 7; i >= 0; i = i - 1) begin
            if (o_hit[i] && o_op[i]) begin
                case (o_layer[i*2 +: 2])
                    2'd3:    begin air_on  = 1'b1; air_c  = o_col[i*12 +: 12]; end
                    2'd2:    begin held_on = 1'b1; held_c = o_col[i*12 +: 12]; end
                    default: begin gnd_on  = 1'b1; gnd_c  = o_col[i*12 +: 12]; end
                endcase
            end
        end
    end
    wire shadow_on = |sh_hit;

    // ================================================================
    // CHEFS
    // ================================================================
    function [12:0] chef_px;       // {opaque, colour}
        input [2:0] cx, cy;
        input [1:0] face;
        input [11:0] body;
        begin
            chef_px = 13'd0;
            case (cy)
                3'd0, 3'd2: if (cx >= 3'd2 && cx <= 3'd5) chef_px = {1'b1, (cy == 3'd2) ? 12'hCCD : 12'hFFF};
                3'd1:       if (cx >= 3'd1 && cx <= 3'd6) chef_px = {1'b1, 12'hFFF};
                3'd3:       if (cx >= 3'd2 && cx <= 3'd5) chef_px = {1'b1, 12'hFCA};
                3'd4: if (cx >= 3'd2 && cx <= 3'd5) begin
                    chef_px = {1'b1, 12'hFCA};
                    if ((face == 2'd1 && (cx == 3'd3 || cx == 3'd4)) ||
                        (face == 2'd2 && cx == 3'd2) || (face == 2'd3 && cx == 3'd5))
                        chef_px = {1'b1, 12'h222};
                end
                3'd5, 3'd6: if (cx >= 3'd1 && cx <= 3'd6)
                    chef_px = {1'b1, (cx == 3'd3 || cx == 3'd4) ? 12'hEEE : body};
                default:    if (cx == 3'd2 || cx == 3'd5) chef_px = {1'b1, 12'h333};
            endcase
        end
    endfunction

    wire [8:0] c1dx = {1'b0, lx} - {1'b0, p1_x} + 9'd4;
    wire [7:0] c1dy = {1'b0, ly} - {1'b0, p1_y} + 8'd4;
    wire [8:0] c2dx = {1'b0, lx} - {1'b0, p2_x} + 9'd4;
    wire [7:0] c2dy = {1'b0, ly} - {1'b0, p2_y} + 8'd4;
    wire [12:0] ch1 = (c1dx < 9'd8 && c1dy < 8'd8) ? chef_px(c1dx[2:0], c1dy[2:0], p1_face, C_P1) : 13'd0;
    wire [12:0] ch2 = (c2dx < 9'd8 && c2dy < 8'd8) ? chef_px(c2dx[2:0], c2dy[2:0], p2_face, C_P2) : 13'd0;

    // charge bar 13 px above the chef centre: three 2-px segments.
    // c*dy = ly - chef_y + 4, so the bar row (chef_y - 13) gives -9 = 8'd247.
    localparam [7:0] CB_ROW = 8'd247;
    function [12:0] charge_px;
        input [8:0] dxv; input [7:0] dyv; input aiming; input [1:0] lvl;
        reg [1:0] seg;
        begin
            charge_px = 13'd0;
            if (aiming && dyv == CB_ROW && dxv < 9'd8) begin
                seg = (dxv < 9'd3) ? 2'd1 : (dxv < 9'd6) ? 2'd2 : 2'd3;
                if (dxv != 9'd2 && dxv != 9'd5)
                    charge_px = {1'b1, (seg <= lvl) ? 12'hFD2 : 12'h444};
            end
        end
    endfunction
    wire [12:0] cb1 = charge_px(c1dx, c1dy, p1_aiming, p1_charge);
    wire [12:0] cb2 = charge_px(c2dx, c2dy, p2_aiming, p2_charge);

    // ================================================================
    // THROW PREVIEW
    // ================================================================
    reg dot_on, land_on;
    always @* begin
        dot_on = 1'b0; land_on = 1'b0;
        for (i = 0; i < 8; i = i + 1) begin
            if (p1_aiming && i < p1_n && lx == p1_dx_flat[i*8 +: 8] && ly == p1_dy_flat[i*7 +: 7]) dot_on = 1'b1;
            if (p2_aiming && i < p2_n && lx == p2_dx_flat[i*8 +: 8] && ly == p2_dy_flat[i*7 +: 7]) dot_on = 1'b1;
        end
        if (p1_aiming && p1_land_v &&
            ((lx == p1_land_x && (ly + 7'd1 >= p1_land_y) && (ly <= p1_land_y + 7'd1)) ||
             (ly == p1_land_y && (lx + 8'd1 >= p1_land_x) && (lx <= p1_land_x + 8'd1)))) land_on = 1'b1;
        if (p2_aiming && p2_land_v &&
            ((lx == p2_land_x && (ly + 7'd1 >= p2_land_y) && (ly <= p2_land_y + 7'd1)) ||
             (ly == p2_land_y && (lx + 8'd1 >= p2_land_x) && (lx <= p2_land_x + 8'd1)))) land_on = 1'b1;
    end

    // ================================================================
    // HUD (top 16 logical rows)
    // ================================================================
    wire [3:0] sc_h, sc_t, sc_o, tm_m, tm_t, tm_o;
    digits dg (.score(score), .time_s(time_s), .sc_h(sc_h), .sc_t(sc_t), .sc_o(sc_o),
               .tm_m(tm_m), .tm_t(tm_t), .tm_o(tm_o));

    wire score_on, time_on;
    text_field #(.X0(100), .Y0(4), .N(3), .SHIFT(0)) t_score (.px(lx), .py(ly),
        .codes({1'b0, sc_o, 1'b0, sc_t, 1'b0, sc_h}), .on(score_on));
    text_field #(.X0(128), .Y0(4), .N(4), .SHIFT(0)) t_time (.px(lx), .py(ly),
        .codes({1'b0, tm_o, 1'b0, tm_t, 5'd10, 1'b0, tm_m}), .on(time_on));

    // order tickets at x = 2, 34, 66 (30 px wide)
    reg  [1:0] card;
    reg        in_card;
    reg  [7:0] cx0;
    always @* begin
        in_card = 1'b1; card = 2'd0; cx0 = 8'd2;
        if      (lx >= 8'd2  && lx < 8'd32)  begin card = 2'd0; cx0 = 8'd2;  end
        else if (lx >= 8'd34 && lx < 8'd64)  begin card = 2'd1; cx0 = 8'd34; end
        else if (lx >= 8'd66 && lx < 8'd96)  begin card = 2'd2; cx0 = 8'd66; end
        else in_card = 1'b0;
        if (ly < 7'd1 || ly > 7'd14) in_card = 1'b0;
    end
    wire [7:0]  crx    = lx - cx0;
    wire        c_val  = ord_valid[card];
    wire        c_rec  = ord_recipe[card];
    wire [3:0]  c_bar  = ord_time_flat[card*12 + 8 +: 4];
    wire [6:0]  icy    = ly - 7'd4;
    wire        ic_in  = (crx >= 8'd2) && (crx < 8'd10) && (ly >= 7'd4) && (ly < 7'd12);
    wire        ic_op;
    wire [11:0] ic_col;
    item_sprite card_icon (.kind(2'd2), .chopped(1'b0), .plate(c_rec ? 3'b011 : 3'b100),
        .ox(crx[2:0] - 3'd2), .oy(icy[2:0]), .opaque(ic_op), .color(ic_col));

    reg [11:0] hud_rgb;
    always @* begin
        hud_rgb = 12'h223;
        if (in_card) begin
            if (c_val) begin
                hud_rgb = (crx == 8'd0 || crx == 8'd29 || ly == 7'd1 || ly == 7'd14) ? 12'h998 : 12'hEED;
                if (ic_in && ic_op) hud_rgb = ic_col;
                if (crx >= 8'd12 && crx < 8'd28 && ly >= 7'd7 && ly <= 7'd9)
                    hud_rgb = ((crx - 8'd12) < {4'd0, c_bar}) ?
                              ((c_bar > 4'd4) ? 12'h2B2 : 12'hD22) : 12'h666;
            end else
                hud_rgb = 12'h334;
        end
        if (score_on) hud_rgb = 12'hFE4;
        if (time_on)  hud_rgb = (time_s < 8'd30) ? 12'hF44 : 12'hFFF;
    end

    // ================================================================
    // STATE BANNER (centre of the kitchen)
    // ================================================================
    wire show_banner = (flow_state != F_PLAY);
    wire in_banner = (lx >= 8'd24) && (lx < 8'd136) && (ly >= 7'd40) && (ly < 7'd80);
    wire box_edge = (lx == 8'd24) || (lx == 8'd135) || (ly == 7'd40) || (ly == 7'd79);

    // "READY" or "SCORE" (2x)
    wire ban1_on;
    wire [24:0] ban1_codes = (flow_state == F_RESULTS) ?
        {5'd14, 5'd17, 5'd15, 5'd12, 5'd18} :            // S C O R E (reversed order)
        {5'd20, 5'd13, 5'd11, 5'd14, 5'd17};             // R E A D Y
    text_field #(.X0(40), .Y0(46), .N(5), .SHIFT(1)) t_ban1 (.px(lx), .py(ly),
        .codes(ban1_codes), .on(ban1_on));
    // "PAUSED" (2x)
    wire paused_on;
    text_field #(.X0(32), .Y0(46), .N(6), .SHIFT(1)) t_paused (.px(lx), .py(ly),
        .codes({5'd13, 5'd14, 5'd18, 5'd19, 5'd11, 5'd16}), .on(paused_on));
    // countdown digit (2x)
    wire count_on;
    text_field #(.X0(72), .Y0(46), .N(1), .SHIFT(1)) t_count (.px(lx), .py(ly),
        .codes({3'd0, count_s}), .on(count_on));
    // "P1  P2" (1x)
    wire pp_on;
    text_field #(.X0(56), .Y0(66), .N(6), .SHIFT(0)) t_pp (.px(lx), .py(ly),
        .codes({5'd2, 5'd16, 5'd31, 5'd31, 5'd1, 5'd16}), .on(pp_on));
    // final score (2x)
    wire fs_on;
    text_field #(.X0(56), .Y0(62), .N(3), .SHIFT(1)) t_fs (.px(lx), .py(ly),
        .codes({1'b0, sc_o, 1'b0, sc_t, 1'b0, sc_h}), .on(fs_on));

    reg [11:0] ban_rgb;
    always @* begin
        ban_rgb = box_edge ? 12'hFD2 : 12'h112;
        case (flow_state)
            F_READY: begin
                if (ban1_on) ban_rgb = 12'hFFF;
                if (pp_on)   ban_rgb = (lx < 8'd72) ? (ready[0] ? 12'h4E4 : 12'h777)
                                                    : (ready[1] ? 12'h4E4 : 12'h777);
            end
            F_COUNT:   if (count_on)  ban_rgb = 12'hFD2;
            F_PAUSE:   if (paused_on) ban_rgb = 12'hFFF;
            default: begin                                   // results
                if (ban1_on) ban_rgb = 12'hFFF;
                if (fs_on)   ban_rgb = 12'hFE4;
            end
        endcase
    end

    // ================================================================
    // COMPOSE
    // ================================================================
    reg [11:0] pix;
    always @* begin
        if (ty < 4'd2)                       pix = hud_rgb;
        else if (show_banner && in_banner)   pix = ban_rgb;
        else if (air_on)                     pix = air_c;
        else if (land_on)                    pix = 12'hF33;
        else if (dot_on)                     pix = 12'hFFF;
        else if (cb1[12])                    pix = cb1[11:0];
        else if (cb2[12])                    pix = cb2[11:0];
        else if (held_on)                    pix = held_c;
        else if (ch1[12])                    pix = ch1[11:0];
        else if (ch2[12])                    pix = ch2[11:0];
        else if (gnd_on)                     pix = gnd_c;
        else if (shadow_on)                  pix = 12'h543;
        else                                 pix = tile_rgb;
    end

    always @(posedge clk) rgb <= active ? pix : 12'h000;
endmodule
