`timescale 1ns / 1ps
// ============================================================================
// game_core.v  -  All game logic, without display or link hardware
// Owner: Group integration
//
// Inputs are clean (debounced) buttons for both players. Outputs are the
// game state that the VGA, OLED, seven-segment and link modules display.
// Kept separate from the top module so it can be simulated quickly.
// ============================================================================
module game_core (
    input             clk,
    input             rst,
    input             tick,                 // 60 Hz (start of VGA blanking)
    input      [4:0]  p1_btn, p2_btn,       // {up, down, left, right, centre}
    input             sw_pause, sw_exit,
    // flow
    output     [2:0]  flow_state,
    output     [1:0]  ready,
    output     [1:0]  count_s,
    output     [7:0]  time_s,
    // chefs
    output     [7:0]  p1_x, output [6:0] p1_y, output [1:0] p1_face,
    output     [7:0]  p2_x, output [6:0] p2_y, output [1:0] p2_face,
    output            p1_aiming, p2_aiming,
    output     [1:0]  p1_charge, p2_charge,
    // objects
    output     [7:0]  obj_used,
    output     [15:0] obj_kind_flat,
    output     [7:0]  obj_chopped,
    output     [23:0] obj_plate_flat,
    output     [15:0] obj_loc_flat,
    output     [7:0]  obj_holder,
    output     [39:0] obj_tx_flat,
    output     [31:0] obj_ty_flat,
    output     [95:0] ph_x_flat, ph_y_flat,
    output     [71:0] ph_z_flat,
    output     [7:0]  ph_air,
    // stations
    output     [6:0]  chop0_prog, chop1_prog,
    output     [2:0]  pot0_state, pot1_state,
    output     [8:0]  pot0_timer, pot1_timer,
    output     [1:0]  pot0_count, pot1_count,
    // orders
    output     [2:0]  ord_valid, ord_recipe,
    output     [35:0] ord_time_flat,
    output     [9:0]  score,
    output     [6:0]  served,
    // preview
    output     [3:0]  p1_n, p2_n,
    output     [63:0] p1_dx_flat, p2_dx_flat,
    output     [55:0] p1_dy_flat, p2_dy_flat,
    output            p1_land_v, p2_land_v,
    output     [7:0]  p1_land_x, p2_land_x,
    output     [6:0]  p1_land_y, p2_land_y
);
    wire play_tick, round_reset;

    // ---------------- Member 1: input interpretation ----------------
    wire [3:0] p1_dir, p2_dir;
    wire p1_tap, p1_hold, p1_rel, p2_tap, p2_hold, p2_rel;
    wire [2:0] p1_aim, p2_aim;
    wire signed [7:0] p1_tvx, p1_tvy, p2_tvx, p2_tvy;

    player_input u_in1 (.clk(clk), .rst(rst), .tick(tick), .btn(p1_btn), .face(p1_face),
        .dir(p1_dir), .tap(p1_tap), .hold(p1_hold), .release_hold(p1_rel),
        .aim(p1_aim), .charge(p1_charge), .throw_vx(p1_tvx), .throw_vy(p1_tvy));
    player_input u_in2 (.clk(clk), .rst(rst), .tick(tick), .btn(p2_btn), .face(p2_face),
        .dir(p2_dir), .tap(p2_tap), .hold(p2_hold), .release_hold(p2_rel),
        .aim(p2_aim), .charge(p2_charge), .throw_vx(p2_tvx), .throw_vy(p2_tvy));

    // ---------------- Member 4: game flow ----------------
    game_flow u_flow (.clk(clk), .rst(rst), .tick(tick), .p1_tap(p1_tap), .p2_tap(p2_tap),
        .sw_pause(sw_pause), .sw_exit(sw_exit), .state(flow_state), .play_tick(play_tick),
        .round_reset(round_reset), .ready(ready), .count_s(count_s), .time_s(time_s));

    // ---------------- Member 2: chef movement ----------------
    chef_motion u_chefs (.clk(clk), .rst(rst), .tick(play_tick), .round_reset(round_reset),
        .p1_dir(p1_dir), .p2_dir(p2_dir), .p1_freeze(p1_aiming), .p2_freeze(p2_aiming),
        .p1_x(p1_x), .p1_y(p1_y), .p1_face(p1_face),
        .p2_x(p2_x), .p2_y(p2_y), .p2_face(p2_face));

    // ---------------- Member 2: object physics ----------------
    wire [7:0] moving, ph_wait, ph_stop, near1, near2;
    wire launch_valid, reject_valid;
    wire [2:0] launch_idx, reject_idx;
    wire [11:0] launch_x, launch_y;
    wire signed [7:0] launch_vx, launch_vy;
    wire [31:0] ph_wtile_flat;

    object_physics u_phys (.clk(clk), .rst(rst | round_reset), .tick(play_tick),
        .moving(moving),
        .launch_valid(launch_valid), .launch_idx(launch_idx),
        .launch_x(launch_x), .launch_y(launch_y), .launch_vx(launch_vx), .launch_vy(launch_vy),
        .reject_valid(reject_valid), .reject_idx(reject_idx),
        .p1_x(p1_x), .p1_y(p1_y), .p2_x(p2_x), .p2_y(p2_y),
        .obj_x_flat(ph_x_flat), .obj_y_flat(ph_y_flat), .obj_z_flat(ph_z_flat),
        .wait_tile_flat(ph_wtile_flat), .air(ph_air), .waiting(ph_wait), .stopped(ph_stop),
        .near_p1(near1), .near_p2(near2));

    // ---------------- Member 3: kitchen and orders ----------------
    wire has_soup, has_salad, serve_valid, serve_recipe;
    wire p1_holding, p2_holding;

    kitchen u_kitchen (.clk(clk), .rst(rst), .tick(play_tick), .round_reset(round_reset),
        .p1_tap(p1_tap), .p1_hold(p1_hold), .p1_release(p1_rel), .p1_vx(p1_tvx), .p1_vy(p1_tvy),
        .p2_tap(p2_tap), .p2_hold(p2_hold), .p2_release(p2_rel), .p2_vx(p2_tvx), .p2_vy(p2_tvy),
        .p1_x(p1_x), .p1_y(p1_y), .p1_face(p1_face),
        .p2_x(p2_x), .p2_y(p2_y), .p2_face(p2_face),
        .ph_x_flat(ph_x_flat), .ph_y_flat(ph_y_flat),
        .ph_air(ph_air), .ph_wait(ph_wait), .ph_stop(ph_stop), .ph_near1(near1), .ph_near2(near2),
        .has_soup(has_soup), .has_salad(has_salad),
        .serve_valid(serve_valid), .serve_recipe(serve_recipe),
        .moving(moving), .launch_valid(launch_valid), .launch_idx(launch_idx),
        .launch_x(launch_x), .launch_y(launch_y), .launch_vx(launch_vx), .launch_vy(launch_vy),
        .reject_valid(reject_valid), .reject_idx(reject_idx),
        .p1_holding(p1_holding), .p2_holding(p2_holding),
        .p1_aiming(p1_aiming), .p2_aiming(p2_aiming),
        .obj_used(obj_used), .obj_kind_flat(obj_kind_flat), .obj_chopped(obj_chopped),
        .obj_plate_flat(obj_plate_flat), .obj_loc_flat(obj_loc_flat), .obj_holder(obj_holder),
        .obj_tx_flat(obj_tx_flat), .obj_ty_flat(obj_ty_flat),
        .chop0_prog(chop0_prog), .chop1_prog(chop1_prog),
        .pot0_state(pot0_state), .pot1_state(pot1_state),
        .pot0_timer(pot0_timer), .pot1_timer(pot1_timer),
        .pot0_count(pot0_count), .pot1_count(pot1_count));

    orders u_orders (.clk(clk), .rst(rst), .tick(play_tick), .round_reset(round_reset),
        .serve_valid(serve_valid), .serve_recipe(serve_recipe),
        .has_soup(has_soup), .has_salad(has_salad),
        .ord_valid(ord_valid), .ord_recipe(ord_recipe), .ord_time_flat(ord_time_flat),
        .score(score), .served(served));

    // ---------------- Member 1: throw preview ----------------
    predictor u_pred (.clk(clk), .rst(rst), .tick(play_tick),
        .p1_aiming(p1_aiming), .p2_aiming(p2_aiming),
        .p1_x(p1_x), .p1_y(p1_y), .p2_x(p2_x), .p2_y(p2_y),
        .p1_vx(p1_tvx), .p1_vy(p1_tvy), .p2_vx(p2_tvx), .p2_vy(p2_tvy),
        .p1_n(p1_n), .p2_n(p2_n), .p1_dx_flat(p1_dx_flat), .p2_dx_flat(p2_dx_flat),
        .p1_dy_flat(p1_dy_flat), .p2_dy_flat(p2_dy_flat),
        .p1_land_v(p1_land_v), .p2_land_v(p2_land_v),
        .p1_land_x(p1_land_x), .p2_land_x(p2_land_x),
        .p1_land_y(p1_land_y), .p2_land_y(p2_land_y));
endmodule
