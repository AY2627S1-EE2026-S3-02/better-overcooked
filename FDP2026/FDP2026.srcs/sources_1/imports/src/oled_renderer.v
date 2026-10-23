`timescale 1ns / 1ps
// ============================================================================
// oled_renderer.v  -  Order reference and status on the 96 x 64 OLED
// Owner: Member 4 (Heng Yong Hen)
//
// Draws from the status bus only, so the controller board can draw the same
// screen from the status packet it receives over the link.
//   top    : three order tickets (2x icon, time bar)
//   bottom : score (2x), round time, this player's throw charge
//   banner : READY / countdown / PAUSED / SCORE screens
// Output is RGB565 for Oled_Display.v.
// ============================================================================
module oled_renderer (
    input      [12:0] pixel_index,
    input      [2:0]  flow_state,
    input      [1:0]  ready,
    input      [1:0]  count_s,
    input      [7:0]  time_s,
    input      [9:0]  score,
    input      [2:0]  ord_valid, ord_recipe,
    input      [11:0] ord_bar_flat,     // 3 x 4-bit time left (0..15)
    input      [1:0]  my_charge,
    output     [15:0] oled_data
);
    localparam [2:0] F_READY = 3'd0, F_COUNT = 3'd1, F_PLAY = 3'd2,
                     F_PAUSE = 3'd3, F_RESULTS = 3'd4;

    wire [12:0] x_full = pixel_index % 13'd96;
    wire [12:0] y_full = pixel_index / 13'd96;
    wire [6:0] x = x_full[6:0];
    wire [5:0] y = y_full[5:0];
    wire [7:0] px = {1'b0, x};
    wire [6:0] py = {1'b0, y};

    // ---------------- order tickets at x = 1, 33, 65 ----------------
    reg  [1:0] card; reg in_card; reg [6:0] x0;
    always @* begin
        in_card = 1'b1; card = 2'd0; x0 = 7'd1;
        if      (x >= 7'd1  && x < 7'd31) begin card = 2'd0; x0 = 7'd1;  end
        else if (x >= 7'd33 && x < 7'd63) begin card = 2'd1; x0 = 7'd33; end
        else if (x >= 7'd65 && x < 7'd95) begin card = 2'd2; x0 = 7'd65; end
        else in_card = 1'b0;
        if (y < 6'd1 || y > 6'd34) in_card = 1'b0;
    end
    wire [6:0] cx  = x - x0;
    wire       cv  = ord_valid[card];
    wire       cr  = ord_recipe[card];
    wire [3:0] cb  = ord_bar_flat[card*4 +: 4];
    wire [6:0] icx = cx - 7'd7;
    wire [5:0] icy = y - 6'd4;
    wire       ic_in = (cx >= 7'd7) && (cx < 7'd23) && (y >= 6'd4) && (y < 6'd20);
    wire        ic_op;
    wire [11:0] ic_col;
    item_sprite icon (.kind(2'd2), .chopped(1'b0), .plate(cr ? 3'b011 : 3'b100),
        .ox(icx[3:1]), .oy(icy[3:1]), .opaque(ic_op), .color(ic_col));

    // ---------------- text ----------------
    wire [3:0] sc_h, sc_t, sc_o, tm_m, tm_t, tm_o;
    digits dg (.score(score), .time_s(time_s), .sc_h(sc_h), .sc_t(sc_t), .sc_o(sc_o),
               .tm_m(tm_m), .tm_t(tm_t), .tm_o(tm_o));
    wire score_on, time_on, ban1_on, paused_on, count_on, pp_on, fs_on;
    text_field #(.X0(2),  .Y0(40), .N(3), .SHIFT(1)) t_sc (.px(px), .py(py),
        .codes({1'b0, sc_o, 1'b0, sc_t, 1'b0, sc_h}), .on(score_on));
    text_field #(.X0(60), .Y0(42), .N(4), .SHIFT(0)) t_tm (.px(px), .py(py),
        .codes({1'b0, tm_o, 1'b0, tm_t, 5'd10, 1'b0, tm_m}), .on(time_on));
    text_field #(.X0(8),  .Y0(10), .N(5), .SHIFT(1)) t_b1 (.px(px), .py(py),
        .codes((flow_state == F_RESULTS) ? {5'd14, 5'd17, 5'd15, 5'd12, 5'd18}
                                         : {5'd20, 5'd13, 5'd11, 5'd14, 5'd17}), .on(ban1_on));
    text_field #(.X0(0),  .Y0(24), .N(6), .SHIFT(1)) t_pa (.px(px), .py(py),
        .codes({5'd13, 5'd14, 5'd18, 5'd19, 5'd11, 5'd16}), .on(paused_on));
    text_field #(.X0(40), .Y0(24), .N(1), .SHIFT(1)) t_ct (.px(px), .py(py),
        .codes({3'd0, count_s}), .on(count_on));
    text_field #(.X0(24), .Y0(40), .N(6), .SHIFT(0)) t_pp (.px(px), .py(py),
        .codes({5'd2, 5'd16, 5'd31, 5'd31, 5'd1, 5'd16}), .on(pp_on));
    text_field #(.X0(24), .Y0(36), .N(3), .SHIFT(1)) t_fs (.px(px), .py(py),
        .codes({1'b0, sc_o, 1'b0, sc_t, 1'b0, sc_h}), .on(fs_on));

    // ---------------- compose (12-bit colour) ----------------
    reg [11:0] c;
    always @* begin
        c = 12'h000;
        case (flow_state)
            F_READY: begin
                if (ban1_on) c = 12'hFFF;
                if (pp_on)   c = (x < 7'd40) ? (ready[0] ? 12'h4E4 : 12'h777)
                                             : (ready[1] ? 12'h4E4 : 12'h777);
            end
            F_COUNT: if (count_on)  c = 12'hFD2;
            F_PAUSE: if (paused_on) c = 12'hFFF;
            F_RESULTS: begin
                if (ban1_on) c = 12'hFFF;
                if (fs_on)   c = 12'hFE4;
            end
            default: begin                                     // playing
                if (in_card) begin
                    if (cv) begin
                        c = (cx == 7'd0 || cx == 7'd29 || y == 6'd1 || y == 6'd34) ? 12'h998 : 12'h223;
                        if (ic_in && ic_op) c = ic_col;
                        if (y >= 6'd25 && y <= 6'd30 && cx >= 7'd1 && cx <= 7'd28)
                            c = ((cx - 7'd1) < {2'b00, cb, 1'b0}) ?
                                ((cb > 4'd4) ? 12'h2B2 : 12'hD22) : 12'h444;
                    end else if (cx == 7'd0 || cx == 7'd29 || y == 6'd1 || y == 6'd34)
                        c = 12'h333;
                end
                if (score_on) c = 12'hFE4;
                if (time_on)  c = (time_s < 8'd30) ? 12'hF44 : 12'hFFF;
                if (y >= 6'd56 && y <= 6'd59 && x >= 7'd60 && x < 7'd90) begin
                    if (x - 7'd60 < ({2'b00, my_charge, 3'b000} + {4'b0000, my_charge, 1'b0}))
                        c = 12'hFD2;                           // 10 px per charge level
                    else c = 12'h222;
                end
            end
        endcase
    end

    assign oled_data = {c[11:8], c[11], c[7:4], c[7:6], c[3:0], c[3]};
endmodule
