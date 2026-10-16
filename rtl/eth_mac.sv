`default_nettype none

module eth_mac #(
    parameter int FIFO_DEPTH = 2048
) (
    input wire clk,
    input wire rst_n,
    input wire hclk,
    input wire hrst_n,

    // Convert to registers
    input wire speed_100,
    input wire loopback,

    input wire tx_valid,
    output logic tx_ready,
    input wire [7:0] tx_data,
    input wire tx_last,

    output logic rx_valid,
    input wire rx_ready,
    output logic [7:0] rx_data,
    output logic rx_last,

    output logic phy_tx_en,
    output logic [1:0] phy_txd,
    input wire phy_crs_dv,
    input wire [1:0] phy_rxd
);

  logic tx_full;
  logic tx_empty;
  logic tx_rd_en;
  logic [7:0] tx_rd_data;
  logic tx_rd_last;

  logic line_tx_valid;
  logic line_tx_ready;
  logic [7:0] line_rx_data;
  logic line_rx_valid;
  logic line_rx_last;
  logic line_rx_bad;

  logic rx_empty;
  logic rx_rd_en;

  // Bus to line
  frame_fifo #(
      .WIDTH($bits(tx_data)),
      .DEPTH(FIFO_DEPTH)
  ) u_tx_fifo (
      .wr_clk(hclk),
      .wr_rst_n(hrst_n),
      .wr_en(tx_valid && tx_ready),
      .wr_data(tx_data),
      .wr_last(tx_last),
      .wr_bad(1'b0),
      .full(tx_full),
      .rd_clk(clk),
      .rd_rst_n(rst_n),
      .rd_en(tx_rd_en),
      .rd_data(tx_rd_data),
      .rd_last(tx_rd_last),
      .empty(tx_empty)
  );

  assign tx_ready = !tx_full;

  // Read ahead
  assign tx_rd_en = !tx_empty && (!line_tx_valid || line_tx_ready);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      line_tx_valid <= 1'b0;
    end else if (tx_rd_en) begin
      line_tx_valid <= 1'b1;
    end else if (line_tx_ready) begin
      line_tx_valid <= 1'b0;
    end
  end

  rmii_line u_line (
      .clk(clk),
      .rst_n(rst_n),
      .speed_100(speed_100),
      .loopback(loopback),
      .tx_valid(line_tx_valid),
      .tx_ready(line_tx_ready),
      .tx_data(tx_rd_data),
      .tx_last(tx_rd_last),
      .rx_data(line_rx_data),
      .rx_valid(line_rx_valid),
      .rx_last(line_rx_last),
      .rx_bad(line_rx_bad),
      .phy_tx_en(phy_tx_en),
      .phy_txd(phy_txd),
      .phy_crs_dv(phy_crs_dv),
      .phy_rxd(phy_rxd)
  );

  // Line to bus
  frame_fifo #(
      .WIDTH($bits(rx_data)),
      .DEPTH(FIFO_DEPTH)
  ) u_rx_fifo (
      .wr_clk(clk),
      .wr_rst_n(rst_n),
      .wr_en(line_rx_valid),
      .wr_data(line_rx_data),
      .wr_last(line_rx_last),
      .wr_bad(line_rx_bad),
      .full(),
      .rd_clk(hclk),
      .rd_rst_n(hrst_n),
      .rd_en(rx_rd_en),
      .rd_data(rx_data),
      .rd_last(rx_last),
      .empty(rx_empty)
  );

  // Read ahead
  assign rx_rd_en = !rx_empty && (!rx_valid || rx_ready);

  always_ff @(posedge hclk) begin
    if (!hrst_n) begin
      rx_valid <= 1'b0;
    end else if (rx_rd_en) begin
      rx_valid <= 1'b1;
    end else if (rx_ready) begin
      rx_valid <= 1'b0;
    end
  end

endmodule

`default_nettype wire
