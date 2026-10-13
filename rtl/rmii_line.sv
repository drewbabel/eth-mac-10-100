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

endmodule
