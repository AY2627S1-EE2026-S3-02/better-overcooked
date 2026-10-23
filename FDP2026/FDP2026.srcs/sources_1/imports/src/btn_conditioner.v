`timescale 1ns / 1ps
// ============================================================================
// btn_conditioner.v  -  Synchroniser and debouncer for N push buttons/switches
// Owner: Member 1 (Lee Kwan Tze)
//
// Each input passes through a two flip-flop synchroniser, then is sampled
// every 1 ms. The clean output only changes after STABLE consecutive samples
// agree, so contact bounce shorter than STABLE ms is ignored.
// ============================================================================
module btn_conditioner #(
    parameter N = 5,
    parameter STABLE = 5           // ms of agreement before a change is accepted
)(
    input              clk,
    input              en_1khz,    // 1 ms sample strobe
    input  [N-1:0]     raw,
    output reg [N-1:0] clean = {N{1'b0}}
);
    reg [N-1:0] s1 = {N{1'b0}}, s2 = {N{1'b0}};
    always @(posedge clk) begin
        s1 <= raw;
        s2 <= s1;
    end

    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : deb
            reg [3:0] cnt = 4'd0;
            always @(posedge clk) begin
                if (en_1khz) begin
                    if (s2[i] == clean[i])
                        cnt <= 4'd0;
                    else if (cnt == STABLE - 1) begin
                        clean[i] <= s2[i];
                        cnt <= 4'd0;
                    end else
                        cnt <= cnt + 4'd1;
                end
            end
        end
    endgenerate
endmodule
