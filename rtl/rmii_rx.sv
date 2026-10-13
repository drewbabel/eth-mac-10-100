module rmii_rx #(
    parameter int MIN_FRAME_BYTES = 64,
    parameter int MAX_FRAME_BYTES = 1518,
    parameter int MAX_TAGGED_FRAME_BYTES = 1522
) (
    input wire clk,
    input wire rst_n,
    input wire tick,
    input wire phy_crs_dv,
    input wire [1:0] phy_rxd,
    output logic [7:0] rx_data,
    output logic rx_valid,
    output logic rx_last,
    output logic rx_bad
);

  // Ethernet spec
  localparam logic [7:0] StartByte = 8'hD5;
  localparam logic [15:0] TagType = 16'h8100;
  localparam int TagIndex = 12;  // First type byte
  localparam logic [31:0] CrcResidue = 32'hC704_DD7B;  // Good frame result

  localparam int PairsPerByte = $bits(rx_data) / $bits(phy_rxd);
  localparam int CrcBytes = 4;
  localparam int HoldBytes = CrcBytes + 1;  // Checksum plus last

  logic crs_dv;
  logic crs_dv_last;
  logic pair_valid;
  logic line_end;
  logic [$bits(phy_rxd)-1:0] rxd;
  logic [$bits(phy_rxd)-1:0] rxd_last;
  logic frame_start;
  logic in_frame;
  logic [$clog2(PairsPerByte)-1:0] pair_cnt;  // Increments on each pair
  logic byte_done;
  logic [$clog2(MAX_TAGGED_FRAME_BYTES + 2)-1:0] byte_cnt;
  logic [$bits(rx_data)-1:0] new_byte;
  logic [$bits(rx_data)-1:0] next_data;
  logic [HoldBytes*$bits(rx_data)-1:0] held_bytes;
  logic hold_full;
  logic has_tag;
  logic crc_init;
  logic crc_en;
  logic [$bits(phy_rxd)-1:0] crc_din;
  logic [31:0] crc_out;
  logic crc_good;
  logic crc_match;
  logic frame_bad;

  synchronizer #(
      .WIDTH($bits({phy_crs_dv, phy_rxd}))
  ) u_sync (
      .clk(clk),
      .d  ({phy_crs_dv, phy_rxd}),
      .q  ({crs_dv, rxd})
  );

  crc #(
      .DIN_W($bits(phy_rxd))
  ) u_crc (
      .clk(clk),
      .rst_n(rst_n),
      .init(crc_init),
      .en(crc_en),
      .din(crc_din),
      .crc_out(crc_out)
  );

  assign pair_valid = crs_dv_last || crs_dv;
  assign line_end = !crs_dv_last && !crs_dv;

  assign next_data = {rxd_last, new_byte[$bits(new_byte)-1:$bits(rxd_last)]};
  assign byte_done = in_frame && (pair_cnt == $bits(pair_cnt)'(PairsPerByte - 1));
  assign hold_full = (byte_cnt >= $bits(byte_cnt)'(HoldBytes));
  assign frame_start = tick && pair_valid && !in_frame && (next_data == StartByte);

  assign crc_init = frame_start;
  assign crc_en = tick && pair_valid && in_frame;
  assign crc_din = rxd_last;
  assign crc_match = (pair_cnt == '0) ? (crc_out == CrcResidue) : crc_good;

  assign frame_bad = !crc_match || (byte_cnt < $bits(
      byte_cnt
  )'(MIN_FRAME_BYTES)) || (byte_cnt > $bits(
      byte_cnt
  )'(has_tag ? MAX_TAGGED_FRAME_BYTES : MAX_FRAME_BYTES));

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rx_valid <= 1'b0;
      rx_last <= 1'b0;
      rx_bad <= 1'b0;
      crs_dv_last <= 1'b0;
      rxd_last <= '0;
      in_frame <= 1'b0;
      pair_cnt <= '0;
      byte_cnt <= '0;
      has_tag <= 1'b0;
    end else begin
      rx_valid <= 1'b0;
      rx_last  <= 1'b0;
      rx_bad   <= 1'b0;

      if (tick) begin
        crs_dv_last <= crs_dv;
        rxd_last <= rxd;

        if (pair_valid) begin
          new_byte <= next_data;
          if (in_frame) pair_cnt <= pair_cnt + 1;
          if (in_frame && pair_cnt == '0) crc_good <= (crc_out == CrcResidue);
          if (byte_done) begin
            held_bytes <= {next_data, held_bytes[$bits(held_bytes)-1:$bits(rx_data)]};
            if (byte_cnt != '1) byte_cnt <= byte_cnt + 1;
            if (hold_full) begin
              rx_valid <= 1'b1;
              rx_data  <= held_bytes[$bits(rx_data)-1:0];
            end
            if (byte_cnt == $bits(byte_cnt)'(TagIndex + 1)) begin
              has_tag <= (held_bytes[$bits(held_bytes)-1-:$bits(rx_data)] == TagType[15:8]) &&
                  (next_data == TagType[7:0]);
            end
          end
        end

        // Start of frame
        if (frame_start) begin
          in_frame <= 1'b1;
          pair_cnt <= '0;
          byte_cnt <= '0;
          has_tag  <= 1'b0;
        end

        // End of frame
        if (line_end && in_frame) begin
          in_frame <= 1'b0;
          pair_cnt <= '0;
          if (hold_full) begin
            rx_valid <= 1'b1;
            rx_last  <= 1'b1;
            rx_bad   <= frame_bad;
            rx_data  <= held_bytes[$bits(rx_data)-1:0];
          end
        end
      end
    end
  end

endmodule
