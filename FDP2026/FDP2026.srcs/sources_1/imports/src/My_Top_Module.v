`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
//  FILL IN THE FOLLOWING INFORMATION:
//  STUDENT A NAME: Lee Kwan Tze    (player controls, link, throw preview)
//  STUDENT B NAME: Ian Lee         (physics, collision, movement, map)
//  STUDENT C NAME: Chan Chee Heng  (kitchen simulation, orders, scoring)
//  STUDENT D NAME: Heng Yong Hen   (game flow, VGA, OLED, seven-segment)
//////////////////////////////////////////////////////////////////////////////////
//
//  Physics Kitchen - two-player cooperative cooking game
//
//  Switches
//    sw[15]   two-board mode only: ON = host (drives VGA), OFF = controller
//    sw[14]   ON = two-board mode (UART link on JB), OFF = single-board mode
//    sw[13]   pause
//    sw[12]   early exit (while paused)
//    sw[11]   seven-segment shows score instead of time
//    sw[4:0]  single-board mode, player 2: sw4 left, sw3 up, sw2 down,
//             sw1 right, sw0 action
//  LEDs
//    led[0], led[1]  player 1 / player 2 ready
//    led[4:2]        this board's player throw charge
//    led[12] paused, led[13] two-board mode, led[14] host, led[15] link up
//  Pmods
//    JC : Pmod OLED          JB1 : UART TX          JB2 : UART RX
//////////////////////////////////////////////////////////////////////////////////

module My_Top_Module (
    input         clk,
    input         btnC, btnU, btnL, btnR, btnD,
    input  [15:0] sw,
    output [15:0] led,
    output [6:0]  seg,
    output        dp,
    output [3:0]  an,
    output [7:0]  JC,
    output        jb_tx,
    input         jb_rx,
    output reg [3:0] vgaRed, vgaGreen, vgaBlue,
    output reg    Hsync, Vsync
);
    // ---------------- clocks and reset ----------------
    wire clk25, clk6p25;
    clock_gen u_clk (.clk100(clk), .clk25(clk25), .clk6p25(clk6p25));

    reg [7:0] por = 8'd0;                       // power-on reset
    always @(posedge clk25) if (por != 8'hFF) por <= por + 8'd1;
    wire rst = (por != 8'hFF);

    reg [14:0] ms_div = 15'd0;                  // 1 kHz strobe from 25 MHz
    reg        en_1khz = 1'b0;
    always @(posedge clk25) begin
        en_1khz <= (ms_div == 15'd24999);
        ms_div  <= (ms_div == 15'd24999) ? 15'd0 : ms_div + 15'd1;
    end

    // ---------------- inputs ----------------
    wire [4:0]  btn_clean;                      // {up, down, left, right, centre}
    wire [15:0] sw_clean;
    btn_conditioner #(.N(5))  u_btn (.clk(clk25), .en_1khz(en_1khz),
        .raw({btnU, btnD, btnL, btnR, btnC}), .clean(btn_clean));
    btn_conditioner #(.N(16)) u_sw  (.clk(clk25), .en_1khz(en_1khz),
        .raw(sw), .clean(sw_clean));

    wire two_board = sw_clean[14];
    wire is_host   = ~two_board | sw_clean[15];
    wire is_ctrl   = ~is_host;

    // ---------------- VGA timing (also the 60 Hz game tick) ----------------
    wire [9:0] h, v;
    wire hs, vs, active, frame_tick;
    vga_timing u_vga (.clk(clk25), .rst(rst), .h(h), .v(v), .hs(hs), .vs(vs),
        .active(active), .frame_tick(frame_tick));

    // ---------------- link ----------------
    wire [4:0]  remote_btn;
    wire [47:0] status_local, status_rx;
    wire        link_ok;
    link u_link (.clk(clk25), .rst(rst), .enable(two_board), .is_host(is_host),
        .tick(frame_tick), .en_1khz(en_1khz), .local_btn(btn_clean),
        .status_tx(status_local), .rx_pin(jb_rx), .tx_pin(jb_tx),
        .remote_btn(remote_btn), .status_rx(status_rx), .link_ok(link_ok));

    // player 2: link (two-board) or switches (single-board)
    wire [4:0] p2_sw  = {sw_clean[3], sw_clean[2], sw_clean[4], sw_clean[1], sw_clean[0]};
    wire [4:0] p1_btn = is_host ? btn_clean : 5'd0;
    wire [4:0] p2_btn = two_board ? remote_btn : p2_sw;

    // ---------------- game ----------------
    wire [2:0] flow_state; wire [1:0] ready, count_s; wire [7:0] time_s;
    wire [7:0] p1_x, p2_x; wire [6:0] p1_y, p2_y; wire [1:0] p1_face, p2_face;
    wire p1_aiming, p2_aiming; wire [1:0] p1_charge, p2_charge;
    wire [7:0] obj_used, obj_chopped, obj_holder, ph_air;
    wire [15:0] obj_kind_flat, obj_loc_flat; wire [23:0] obj_plate_flat;
    wire [39:0] obj_tx_flat; wire [31:0] obj_ty_flat;
    wire [95:0] ph_x_flat, ph_y_flat; wire [71:0] ph_z_flat;
    wire [6:0] chop0_prog, chop1_prog; wire [2:0] pot0_state, pot1_state;
    wire [8:0] pot0_timer, pot1_timer; wire [1:0] pot0_count, pot1_count;
    wire [2:0] ord_valid, ord_recipe; wire [35:0] ord_time_flat;
    wire [9:0] score; wire [6:0] served;
    wire [3:0] p1_n, p2_n; wire [63:0] p1_dx_flat, p2_dx_flat;
    wire [55:0] p1_dy_flat, p2_dy_flat; wire p1_land_v, p2_land_v;
    wire [7:0] p1_land_x, p2_land_x; wire [6:0] p1_land_y, p2_land_y;

    game_core u_game (.clk(clk25), .rst(rst), .tick(frame_tick & is_host),
        .p1_btn(p1_btn), .p2_btn(p2_btn),
        .sw_pause(sw_clean[13]), .sw_exit(sw_clean[12]),
        .flow_state(flow_state), .ready(ready), .count_s(count_s), .time_s(time_s),
        .p1_x(p1_x), .p1_y(p1_y), .p1_face(p1_face), .p2_x(p2_x), .p2_y(p2_y), .p2_face(p2_face),
        .p1_aiming(p1_aiming), .p2_aiming(p2_aiming), .p1_charge(p1_charge), .p2_charge(p2_charge),
        .obj_used(obj_used), .obj_kind_flat(obj_kind_flat), .obj_chopped(obj_chopped),
        .obj_plate_flat(obj_plate_flat), .obj_loc_flat(obj_loc_flat), .obj_holder(obj_holder),
        .obj_tx_flat(obj_tx_flat), .obj_ty_flat(obj_ty_flat),
        .ph_x_flat(ph_x_flat), .ph_y_flat(ph_y_flat), .ph_z_flat(ph_z_flat), .ph_air(ph_air),
        .chop0_prog(chop0_prog), .chop1_prog(chop1_prog),
        .pot0_state(pot0_state), .pot1_state(pot1_state),
        .pot0_timer(pot0_timer), .pot1_timer(pot1_timer),
        .pot0_count(pot0_count), .pot1_count(pot1_count),
        .ord_valid(ord_valid), .ord_recipe(ord_recipe), .ord_time_flat(ord_time_flat),
        .score(score), .served(served),
        .p1_n(p1_n), .p2_n(p2_n), .p1_dx_flat(p1_dx_flat), .p2_dx_flat(p2_dx_flat),
        .p1_dy_flat(p1_dy_flat), .p2_dy_flat(p2_dy_flat),
        .p1_land_v(p1_land_v), .p2_land_v(p2_land_v),
        .p1_land_x(p1_land_x), .p2_land_x(p2_land_x),
        .p1_land_y(p1_land_y), .p2_land_y(p2_land_y));

    // ---------------- status bus (game-status data from the host) ----------------
    // [2:0] state, [4:3] ready, [6:5] countdown, [7] spare, [15:8] time,
    // [25:16] score, [28:26] order valid, [31:29] order recipe,
    // [43:32] order time bars (3 x 4 bits), [45:44] P1 charge, [47:46] P2 charge
    assign status_local = {p2_charge, p1_charge,
                           ord_time_flat[35:32], ord_time_flat[23:20], ord_time_flat[11:8],
                           ord_recipe, ord_valid, score, time_s,
                           1'b0, count_s, ready, flow_state};
    wire [47:0] st = is_ctrl ? status_rx : status_local;

    wire [2:0]  st_state  = st[2:0];
    wire [1:0]  st_ready  = st[4:3];
    wire [1:0]  st_count  = st[6:5];
    wire [7:0]  st_time   = st[15:8];
    wire [9:0]  st_score  = st[25:16];
    wire [2:0]  st_ovalid = st[28:26];
    wire [2:0]  st_orec   = st[31:29];
    wire [11:0] st_obars  = st[43:32];
    wire [1:0]  my_charge = is_ctrl ? st[47:46] : st[45:44];

    // ---------------- VGA output ----------------
    wire [11:0] rgb;
    vga_renderer u_ren (.clk(clk25), .h(h), .v(v), .active(active), .frame_tick(frame_tick),
        .flow_state(flow_state), .ready(ready), .count_s(count_s), .time_s(time_s), .score(score),
        .p1_x(p1_x), .p1_y(p1_y), .p1_face(p1_face), .p2_x(p2_x), .p2_y(p2_y), .p2_face(p2_face),
        .p1_aiming(p1_aiming), .p2_aiming(p2_aiming), .p1_charge(p1_charge), .p2_charge(p2_charge),
        .obj_used(obj_used), .obj_kind_flat(obj_kind_flat), .obj_chopped(obj_chopped),
        .obj_plate_flat(obj_plate_flat), .obj_loc_flat(obj_loc_flat), .obj_holder(obj_holder),
        .obj_tx_flat(obj_tx_flat), .obj_ty_flat(obj_ty_flat),
        .ph_x_flat(ph_x_flat), .ph_y_flat(ph_y_flat), .ph_z_flat(ph_z_flat), .ph_air(ph_air),
        .chop0_prog(chop0_prog), .chop1_prog(chop1_prog),
        .pot0_state(pot0_state), .pot1_state(pot1_state),
        .pot0_timer(pot0_timer), .pot1_timer(pot1_timer),
        .ord_valid(ord_valid), .ord_recipe(ord_recipe), .ord_time_flat(ord_time_flat),
        .p1_n(p1_n), .p2_n(p2_n), .p1_dx_flat(p1_dx_flat), .p2_dx_flat(p2_dx_flat),
        .p1_dy_flat(p1_dy_flat), .p2_dy_flat(p2_dy_flat),
        .p1_land_v(p1_land_v), .p2_land_v(p2_land_v),
        .p1_land_x(p1_land_x), .p2_land_x(p2_land_x),
        .p1_land_y(p1_land_y), .p2_land_y(p2_land_y), .rgb(rgb));

    // syncs are delayed one clock to line up with the registered colour
    always @(posedge clk25) begin
        Hsync    <= hs;
        Vsync    <= vs;
        vgaRed   <= is_host ? rgb[11:8] : 4'd0;
        vgaGreen <= is_host ? rgb[7:4]  : 4'd0;
        vgaBlue  <= is_host ? rgb[3:0]  : 4'd0;
    end

    // ---------------- OLED (on JC) ----------------
    wire [12:0] pixel_index;
    wire [15:0] oled_data;
    wire frame_begin, sending_pixels, sample_pixel;
    wire o_cs, o_sdin, o_sclk, o_dcn, o_resn, o_vccen, o_pmoden;

    oled_renderer u_oled_ren (.pixel_index(pixel_index), .flow_state(st_state),
        .ready(st_ready), .count_s(st_count), .time_s(st_time), .score(st_score),
        .ord_valid(st_ovalid), .ord_recipe(st_orec), .ord_bar_flat(st_obars),
        .my_charge(my_charge), .oled_data(oled_data));

    // power-on reset for the OLED driver, synchronised to its 6.25 MHz clock
    reg [1:0] oled_rst_sync = 2'b11;
    always @(posedge clk6p25) oled_rst_sync <= {oled_rst_sync[0], rst};

    Oled_Display u_oled (.clk(clk6p25), .reset(oled_rst_sync[1]), .frame_begin(frame_begin),
        .sending_pixels(sending_pixels), .sample_pixel(sample_pixel),
        .pixel_index(pixel_index), .pixel_data(oled_data),
        .cs(o_cs), .sdin(o_sdin), .sclk(o_sclk), .d_cn(o_dcn), .resn(o_resn),
        .vccen(o_vccen), .pmoden(o_pmoden));

    assign JC = {o_pmoden, o_vccen, o_resn, o_dcn, o_sclk, 1'b0, o_sdin, o_cs};

    // ---------------- seven-segment and LEDs ----------------
    seven_seg u_seg (.clk(clk25), .en_1khz(en_1khz),
        .show_score(sw_clean[11] | (st_state == 3'd4)),
        .score(st_score), .time_s(st_time), .seg(seg), .dp(dp), .an(an));

    assign led[1:0]  = st_ready;
    assign led[2]    = (my_charge >= 2'd1);
    assign led[3]    = (my_charge >= 2'd2);
    assign led[4]    = (my_charge == 2'd3);
    assign led[11:5] = 7'd0;
    assign led[12]   = (st_state == 3'd3);
    assign led[13]   = two_board;
    assign led[14]   = is_host;
    assign led[15]   = link_ok;
endmodule
