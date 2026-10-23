`timescale 1ns / 1ps
// ============================================================================
// game_flow.v  -  Round lifecycle and game-flow controls
// Owner: Member 4 (Heng Yong Hen)
//
// READY   : each player taps the centre button to get ready
// COUNT   : 3-2-1 countdown, the kitchen is reset when it starts
// PLAY    : round timer counts down from ROUND_S seconds
// PAUSE   : pause switch ON freezes the game; the exit switch ends the round
// RESULTS : final score shown; a tap from either player returns to READY
// ============================================================================
module game_flow (
    input            clk,
    input            rst,
    input            tick,         // 60 Hz, always running
    input            p1_tap, p2_tap,
    input            sw_pause,     // synchronised switch levels
    input            sw_exit,
    output reg [2:0] state,
    output           play_tick,    // tick that drives the game while playing
    output reg       round_reset,  // single-cycle pulse at the start of COUNT
    output reg [1:0] ready,        // {p2, p1}
    output reg [1:0] count_s,      // 3, 2, 1 during COUNT
    output reg [7:0] time_s        // seconds left in the round
);
    localparam [2:0] F_READY = 3'd0, F_COUNT = 3'd1, F_PLAY = 3'd2,
                     F_PAUSE = 3'd3, F_RESULTS = 3'd4;
    localparam [7:0] ROUND_S = 8'd150;

    reg [5:0] sub;                  // ticks within the current second

    assign play_tick = tick && (state == F_PLAY) && !sw_pause;

    always @(posedge clk) begin
        round_reset <= 1'b0;
        if (rst) begin
            state <= F_READY; ready <= 2'b00; count_s <= 2'd3;
            time_s <= ROUND_S; sub <= 6'd0;
        end else begin
            case (state)
                F_READY: if (tick) begin
                    if ((ready[0] | p1_tap) & (ready[1] | p2_tap)) begin
                        state <= F_COUNT; count_s <= 2'd3; sub <= 6'd0;
                        time_s <= ROUND_S; ready <= 2'b11;
                        round_reset <= 1'b1;
                    end else
                        ready <= ready | {p2_tap, p1_tap};
                end
                F_COUNT: if (tick) begin
                    if (sub == 6'd59) begin
                        sub <= 6'd0;
                        if (count_s == 2'd1) state <= F_PLAY;
                        else count_s <= count_s - 2'd1;
                    end else sub <= sub + 6'd1;
                end
                F_PLAY: begin
                    if (sw_pause) state <= F_PAUSE;
                    else if (tick) begin
                        if (sub == 6'd59) begin
                            sub <= 6'd0;
                            if (time_s == 8'd1) begin
                                time_s <= 8'd0; state <= F_RESULTS; ready <= 2'b00;
                            end else time_s <= time_s - 8'd1;
                        end else sub <= sub + 6'd1;
                    end
                end
                F_PAUSE: begin
                    if (sw_exit)       begin state <= F_RESULTS; ready <= 2'b00; end
                    else if (!sw_pause) state <= F_PLAY;
                end
                F_RESULTS: if (tick && (p1_tap || p2_tap)) begin
                    state <= F_READY; ready <= 2'b00;
                end
                default: state <= F_READY;
            endcase
        end
    end
endmodule
