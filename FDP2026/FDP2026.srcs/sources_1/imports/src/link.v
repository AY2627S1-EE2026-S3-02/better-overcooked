`timescale 1ns / 1ps
// ============================================================================
// link.v  -  Board-to-board packets over UART (two-board mode)
// Owner: Member 1 (Lee Kwan Tze)
//
// Controller -> host, every 2 ms : 2 bytes  {3'b101, buttons[4:0]}, ~byte0
// Host -> controller, every frame: 8 bytes  8'h5A, status[47:0] (6 bytes,
//                                  LSB byte first), XOR of the 6 status bytes
// A packet that fails its check is dropped. If no valid packet arrives for
// 100 ms the link is reported down and the remote buttons read as released.
// ============================================================================
module link (
    input             clk,
    input             rst,
    input             enable,          // two-board mode selected
    input             is_host,
    input             tick,            // 60 Hz frame tick
    input             en_1khz,
    input      [4:0]  local_btn,       // controller: buttons to send
    input      [47:0] status_tx,       // host: status to send
    input             rx_pin,
    output            tx_pin,
    output reg [4:0]  remote_btn,      // host: player 2 buttons
    output reg [47:0] status_rx,       // controller: last good status
    output            link_ok
);
    localparam [7:0] HDR = 8'h5A;
    localparam [6:0] TIMEOUT_MS = 7'd100;

    // ---------------- transmit ----------------
    reg  [7:0] q [0:7];                 // bytes of the packet being sent
    reg  [3:0] q_len, q_pos;
    reg        tx_start;
    reg  [7:0] tx_byte;
    wire       tx_busy;
    reg  [1:0] ms_cnt;                  // controller sends every 2 ms
    wire [7:0] ctl_b0 = {3'b101, local_btn};
    wire [7:0] st_xor = status_tx[7:0] ^ status_tx[15:8] ^ status_tx[23:16] ^
                        status_tx[31:24] ^ status_tx[39:32] ^ status_tx[47:40];

    uart_tx #(.CPB(217)) u_tx (.clk(clk), .rst(rst), .start(tx_start), .data(tx_byte),
        .tx(tx_pin), .busy(tx_busy));

    always @(posedge clk) begin
        tx_start <= 1'b0;
        if (rst || !enable) begin
            q_len <= 4'd0; q_pos <= 4'd0; ms_cnt <= 2'd0; tx_byte <= 8'd0;
        end else begin
            if (q_pos == q_len) begin                    // nothing queued: load a packet
                if (is_host && tick) begin
                    q[0] <= HDR;
                    q[1] <= status_tx[7:0];   q[2] <= status_tx[15:8];
                    q[3] <= status_tx[23:16]; q[4] <= status_tx[31:24];
                    q[5] <= status_tx[39:32]; q[6] <= status_tx[47:40];
                    q[7] <= st_xor;
                    q_len <= 4'd8; q_pos <= 4'd0;
                end else if (!is_host && en_1khz) begin
                    ms_cnt <= ms_cnt + 2'd1;
                    if (ms_cnt[0]) begin
                        q[0] <= ctl_b0; q[1] <= ~ctl_b0;
                        q_len <= 4'd2; q_pos <= 4'd0;
                    end
                end
            end else if (!tx_busy && !tx_start) begin    // send the next byte
                tx_byte  <= q[q_pos[2:0]];
                tx_start <= 1'b1;
                q_pos    <= q_pos + 4'd1;
            end
        end
    end

    // ---------------- receive ----------------
    wire       rx_valid;
    wire [7:0] rx_data;
    uart_rx #(.CPB(217)) u_rx (.clk(clk), .rst(rst), .rx(rx_pin), .valid(rx_valid), .data(rx_data));

    reg [3:0]  p_state;                 // bytes received of the current packet
    reg [7:0]  b0;
    reg [47:0] p_buf;
    reg [7:0]  p_xor;
    reg [6:0]  idle_ms;                 // ms since the last good packet

    assign link_ok = enable && (idle_ms < TIMEOUT_MS);

    always @(posedge clk) begin
        if (rst || !enable) begin
            p_state <= 4'd0; b0 <= 8'd0; p_buf <= 48'd0; p_xor <= 8'd0;
            idle_ms <= TIMEOUT_MS; remote_btn <= 5'd0; status_rx <= 48'd0;
        end else begin
            if (en_1khz && idle_ms != TIMEOUT_MS) idle_ms <= idle_ms + 7'd1;
            if (idle_ms == TIMEOUT_MS) remote_btn <= 5'd0;   // link lost: release all

            if (rx_valid) begin
                if (is_host) begin
                    // expect {101, buttons}, then its complement
                    if (p_state == 4'd1 && rx_data == ~b0) begin
                        remote_btn <= b0[4:0]; idle_ms <= 7'd0; p_state <= 4'd0;
                    end else if (rx_data[7:5] == 3'b101) begin
                        b0 <= rx_data; p_state <= 4'd1;
                    end else
                        p_state <= 4'd0;
                end else begin
                    // expect header, 6 status bytes, XOR check
                    if (p_state == 4'd0) begin
                        if (rx_data == HDR) begin p_state <= 4'd1; p_xor <= 8'd0; end
                    end else if (p_state <= 4'd6) begin
                        p_buf   <= {rx_data, p_buf[47:8]};      // first byte ends up lowest
                        p_xor   <= p_xor ^ rx_data;
                        p_state <= p_state + 4'd1;
                    end else begin
                        if (rx_data == p_xor) begin status_rx <= p_buf; idle_ms <= 7'd0; end
                        p_state <= 4'd0;
                    end
                end
            end
        end
    end
endmodule
