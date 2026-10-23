`timescale 1ns / 1ps
// ============================================================================
// orders.v  -  Order list, deadlines and scoring
// Owner: Member 3 (Chan Chee Heng)
//
// Up to 3 active orders, each for SOUP (0) or SALAD (1), chosen by an 8-bit
// LFSR (taps 8,6,5,4). Each order lasts ORDER_T ticks (64 s). A new order
// arrives every SPAWN_T ticks (12 s), or at once if the list is empty.
// Serving a matching dish removes the order with the least time left:
//   +20 points, +10 more if more than half of its time was left.
// An expired order costs 10 points. The score stays within 0..999.
// ============================================================================
module orders (
    input             clk,
    input             rst,
    input             tick,          // 60 Hz tick, only while playing
    input             round_reset,
    input             serve_valid,
    input             serve_recipe,  // 0 soup, 1 salad
    output            has_soup,      // an active order wants soup
    output            has_salad,
    output     [2:0]  ord_valid,
    output     [2:0]  ord_recipe,
    output     [35:0] ord_time_flat, // 3 x 12-bit ticks left
    output reg [9:0]  score,
    output reg [6:0]  served
);
    localparam [11:0] ORDER_T = 12'd3840;
    localparam [9:0]  SPAWN_T = 10'd720;
    localparam [9:0]  MAX_SCORE = 10'd999;

    reg        v   [0:2];
    reg        r   [0:2];
    reg [11:0] t   [0:2];
    reg [7:0]  lfsr;
    reg [9:0]  spawn_cnt;

    genvar gi;
    generate
        for (gi = 0; gi < 3; gi = gi + 1) begin : om
            assign ord_valid[gi]  = v[gi];
            assign ord_recipe[gi] = r[gi];
            assign ord_time_flat[gi*12 +: 12] = t[gi];
        end
    endgenerate

    assign has_soup  = (v[0] && !r[0]) || (v[1] && !r[1]) || (v[2] && !r[2]);
    assign has_salad = (v[0] &&  r[0]) || (v[1] &&  r[1]) || (v[2] &&  r[2]);

    // best order to serve: matching recipe with the least time left
    reg       m_found;
    reg [1:0] m_idx;
    integer i;
    always @* begin
        m_found = 1'b0; m_idx = 2'd0;
        for (i = 0; i < 3; i = i + 1) begin
            if (v[i] && r[i] == serve_recipe &&
                (!m_found || t[i] < t[m_idx])) begin
                m_found = 1'b1; m_idx = i[1:0];
            end
        end
    end

    // first free slot
    reg       f_found;
    reg [1:0] f_idx;
    always @* begin
        f_found = 1'b0; f_idx = 2'd0;
        for (i = 2; i >= 0; i = i - 1)
            if (!v[i]) begin f_found = 1'b1; f_idx = i[1:0]; end
    end

    wire any_active = v[0] | v[1] | v[2];
    // points for the order being served (11 bits so the sum cannot wrap)
    wire [10:0] gain = (t[m_idx] > (ORDER_T >> 1)) ? 11'd30 : 11'd20;

    // expiry penalty this tick
    reg [1:0] n_exp;
    always @* begin
        n_exp = 2'd0;
        for (i = 0; i < 3; i = i + 1)
            if (v[i] && t[i] == 12'd1) n_exp = n_exp + 2'd1;
    end
    wire [5:0] penalty = {n_exp, 3'b000} + {3'b000, n_exp, 1'b0};  // 10 x n_exp

    always @(posedge clk) begin
        if (rst || round_reset) begin
            for (i = 0; i < 3; i = i + 1) begin
                v[i] <= 1'b0; r[i] <= 1'b0; t[i] <= 12'd0;
            end
            if (rst) lfsr <= 8'hA5;            // keep randomness across rounds
            spawn_cnt <= 10'd0;
            score <= 10'd0; served <= 7'd0;
        end
        else if (serve_valid) begin
            if (m_found) begin
                v[m_idx] <= 1'b0;
                served <= (served == 7'd127) ? served : served + 7'd1;
                if ({1'b0, score} + gain > {1'b0, MAX_SCORE}) score <= MAX_SCORE;
                else score <= score + gain[9:0];
            end
        end
        else if (tick) begin
            lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
            // count down, expire
            for (i = 0; i < 3; i = i + 1)
                if (v[i]) begin
                    if (t[i] == 12'd1) v[i] <= 1'b0;
                    t[i] <= t[i] - 12'd1;
                end
            score <= (score > {4'd0, penalty}) ? score - {4'd0, penalty} : 10'd0;
            // spawn
            if (!any_active || spawn_cnt >= SPAWN_T - 10'd1) begin
                spawn_cnt <= 10'd0;
                if (f_found) begin
                    v[f_idx] <= 1'b1;
                    r[f_idx] <= lfsr[0];
                    t[f_idx] <= ORDER_T;
                end
            end else
                spawn_cnt <= spawn_cnt + 10'd1;
        end
    end
endmodule
