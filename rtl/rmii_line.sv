module rmii_line #(
    parameter int PREAMBLE_BYTES = 7,
    parameter int PAD_TO_BYTES = 60,
    parameter int GAP_BYTES = 12,
    parameter int MIN_FRAME_BYTES = 64,
    parameter int MAX_FRAME_BYTES = 1518,
    parameter int MAX_TAGGED_FRAME_BYTES = 1522
) (
    input wire clk,
    input wire rst_n,
    input wire speed_100,
    input wire loopback,

    input wire tx_valid,
    output logic tx_ready,
    input wire [7:0] tx_data,
    input wire tx_last,

    output logic [7:0] rx_data,
    output logic rx_valid,
    output logic rx_last,
    output logic rx_bad,

    output logic phy_tx_en,
    output logic [1:0] phy_txd,
    input wire phy_crs_dv,
    input wire [1:0] phy_rxd
);

  localparam int SlowDivisor = 10;

  logic tick_10;
  logic tick;
  logic rx_crs_dv;
  logic [$bits(phy_rxd)-1:0] rx_rxd;

  tick_gen #(
      .DIVISOR(SlowDivisor)
  ) u_tick_gen (
      .clk  (clk),
      .rst_n(rst_n),
      .clr  (1'b0),
      .tick (tick_10)
  );

  assign tick = speed_100 ? 1'b1 : tick_10;
  assign rx_crs_dv = loopback ? phy_tx_en : phy_crs_dv;
  assign rx_rxd = loopback ? phy_txd : phy_rxd;

  rmii_tx #(
      .PREAMBLE_BYTES(PREAMBLE_BYTES),
      .PAD_TO_BYTES(PAD_TO_BYTES),
      .GAP_BYTES(GAP_BYTES)
  ) u_tx (
      .clk(clk),
      .rst_n(rst_n),
      .tick(tick),
      .tx_valid(tx_valid),
      .tx_ready(tx_ready),
      .tx_data(tx_data),
      .tx_last(tx_last),
      .phy_tx_en(phy_tx_en),
      .phy_txd(phy_txd)
  );

  rmii_rx #(
      .MIN_FRAME_BYTES(MIN_FRAME_BYTES),
      .MAX_FRAME_BYTES(MAX_FRAME_BYTES),
      .MAX_TAGGED_FRAME_BYTES(MAX_TAGGED_FRAME_BYTES)
  ) u_rx (
      .clk(clk),
      .rst_n(rst_n),
      .tick(tick),
      .phy_crs_dv(rx_crs_dv),
      .phy_rxd(rx_rxd),
      .rx_data(rx_data),
      .rx_valid(rx_valid),
      .rx_last(rx_last),
      .rx_bad(rx_bad)
  );

`ifdef FORMAL
  localparam int CrcBytes = 4;
  localparam int MaxData  = MAX_FRAME_BYTES - CrcBytes;

  (* anyconst *) logic f_pick;
  (* anyconst *) logic [$clog2(MAX_FRAME_BYTES)-1:0] f_idx;

  logic f_past_valid = 1'b0;
  logic f_in_frame = 1'b0;
  logic [$clog2(MAX_FRAME_BYTES)-1:0] f_tx_cnt = '0;
  logic [$clog2(MAX_FRAME_BYTES)-1:0] f_rx_cnt = '0;
  logic [1:0] f_tx_frame = '0;
  logic [1:0] f_rx_frame = '0;
  logic [7:0] f_byte = '0;
  logic f_have = 1'b0;
  logic f_tx_xfer;

  assign f_tx_xfer = tx_valid && tx_ready;

  initial assume (!rst_n);

  always @(posedge clk) begin
    f_past_valid <= 1'b1;

    if (f_past_valid) assume (rst_n);
    assume (loopback);
`ifdef LINE_SPEED_10
    assume (!speed_100);
`else
    assume (speed_100);
`endif
    if (f_past_valid && $past(tx_valid && !tx_ready)) begin
      assume (tx_valid && tx_data == $past(tx_data) && tx_last == $past(tx_last));
    end
    if (f_in_frame) assume (tx_valid);
    if (tx_valid && f_tx_cnt == $bits(f_tx_cnt)'(MaxData - 1)) assume (tx_last);

    if (rst_n && f_tx_xfer) begin
      f_in_frame <= !tx_last;
      f_tx_cnt   <= tx_last ? '0 : f_tx_cnt + 1'b1;
      if (tx_last && f_tx_frame != '1) f_tx_frame <= f_tx_frame + 1'b1;
      if (f_tx_frame == {1'b0, f_pick} && f_tx_cnt == f_idx) begin
        f_byte <= tx_data;
        f_have <= 1'b1;
      end
    end

    if (rst_n && rx_valid) begin
      f_rx_cnt <= rx_last ? '0 : f_rx_cnt + 1'b1;
      if (rx_last && f_rx_frame != '1) f_rx_frame <= f_rx_frame + 1'b1;
    end
  end

  always @(posedge clk) begin
    if (f_past_valid && rst_n && rx_valid) begin
      assert (!rx_bad);
      assert (f_rx_frame < f_tx_frame || f_rx_frame == '1);
      if (f_rx_frame == {1'b0, f_pick} && f_rx_cnt == f_idx && f_have) assert (rx_data == f_byte);
    end

    if (f_past_valid && rst_n) assert (f_tx_cnt < $bits(f_tx_cnt)'(MaxData));

    if (f_past_valid && rst_n) begin
      cover (rx_valid && rx_last && f_rx_frame == 2'd1);
      cover (rx_valid && f_rx_frame == {1'b0, f_pick} && f_rx_cnt == f_idx && f_have && f_idx == 1);
    end
  end
`endif

endmodule
