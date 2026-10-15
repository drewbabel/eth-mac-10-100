`default_nettype none

module rmii_tx #(
    parameter int PREAMBLE_BYTES = 7,
    parameter int PAD_TO_BYTES = 60,
    parameter int GAP_BYTES = 12
) (
    input wire clk,
    input wire rst_n,
    input wire tick,
    input wire tx_valid,
    output logic tx_ready,
    input wire [7:0] tx_data,
    input wire tx_last,
    output logic phy_tx_en,
    output logic [1:0] phy_txd
);

  // Ethernet spec
  localparam logic [7:0] PreambleByte = 8'h55;
  localparam logic [7:0] StartByte = 8'hD5;
  localparam logic [7:0] PadByte = 8'h00;

  localparam int PairsPerByte = $bits(tx_data) / $bits(phy_txd);
  localparam int CrcBytes = 4;
  localparam logic [$clog2(PairsPerByte)-1:0] LastPair = $clog2(PairsPerByte)'(PairsPerByte - 1);

  typedef enum logic [2:0] {
    IDLE,
    PREAMBLE,  // 7 bytes
    START,  // 1 byte
    DATA,  // 14 to 1518
    PAD,  // 0 to 46
    CRC,  // 4 bytes
    GAP  // 12 bytes
  } state_t;

  state_t state, next_state;
  logic tx_xfer;
  logic take_byte;
  logic drop_byte;
  logic underrun;
  logic [$clog2(PairsPerByte)-1:0] pair_cnt;  // Increments on each pair
  logic last_pair;
  logic [$clog2(PREAMBLE_BYTES + PAD_TO_BYTES + GAP_BYTES + CrcBytes)-1:0] byte_cnt;
  logic min_len_reached;
  logic [$bits(tx_data)-1:0] data_byte;
  logic data_last;
  logic [$bits(tx_data)-1:0] byte_to_send;
  logic [$bits(phy_txd)-1:0] pair_to_send;
  logic sending;
  logic crc_init;
  logic crc_en;
  logic [$bits(phy_txd)-1:0] crc_din;
  logic [31:0] crc_out;
  logic [31:0] crc_send;

  logic preamble_done;
  logic data_done;
  logic pad_done;
  logic crc_done;
  logic gap_done;

  // Spec sends CRC reversed
  always_comb begin
    for (int i = 0; i < $bits(crc_out); i++)
    crc_send[i] = underrun ? crc_out[$bits(crc_out)-1-i] : ~crc_out[$bits(crc_out)-1-i];
  end

  assign take_byte = ((state == START) || (state == DATA && !data_last)) && last_pair;
  assign drop_byte = underrun && (state == GAP || state == IDLE);
  assign tx_ready = (take_byte || drop_byte) && tick;
  assign sending = (state == PREAMBLE) || (state == START) || (state == DATA) || (state == PAD) ||
      (state == CRC);
  assign tx_xfer = tx_valid && tx_ready;
  assign pair_to_send = byte_to_send[2*pair_cnt+:2];

  assign preamble_done = last_pair && (byte_cnt == $bits(byte_cnt)'(PREAMBLE_BYTES - 1));
  assign data_done = last_pair && (data_last || !tx_valid);
  assign pad_done = last_pair && min_len_reached;
  assign crc_done = last_pair && (byte_cnt == $bits(byte_cnt)'(CrcBytes - 1));
  assign gap_done = last_pair && (byte_cnt == $bits(byte_cnt)'(GAP_BYTES - 1));

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= IDLE;
      data_last <= 1'b0;
      underrun <= 1'b0;
      phy_tx_en <= 1'b0;
      phy_txd <= '0;
    end else if (tick) begin
      state <= next_state;
      phy_tx_en <= sending;
      phy_txd <= pair_to_send;
      if (tx_xfer) begin
        data_byte <= tx_data;
        data_last <= tx_last;
      end

      // Underrun when host missed next byte
      if (state == DATA && last_pair && !data_last && !tx_valid) underrun <= 1'b1;
      else if (drop_byte && tx_xfer && tx_last) underrun <= 1'b0;  // Clear
    end
  end

  always_comb begin
    next_state   = state;
    byte_to_send = '0;

    case (state)
      IDLE: begin
        if (tx_valid && !underrun) begin
          next_state = PREAMBLE;
        end
      end
      PREAMBLE: begin
        byte_to_send = PreambleByte;
        if (preamble_done) next_state = START;
      end
      START: begin
        byte_to_send = StartByte;
        if (last_pair) next_state = DATA;
      end
      DATA: begin
        byte_to_send = data_byte;
        if (data_done) begin
          if (min_len_reached) next_state = CRC;
          else next_state = PAD;
        end
      end
      PAD: begin
        byte_to_send = PadByte;
        if (pad_done) next_state = CRC;
      end
      CRC: begin
        byte_to_send = crc_send[8*byte_cnt[$clog2(CrcBytes)-1:0]+:8];
        if (crc_done) next_state = GAP;
      end
      GAP: begin
        if (gap_done) next_state = IDLE;
      end
      default: begin
      end
    endcase
  end

  crc #(
      .DIN_W($bits(phy_txd))
  ) u_crc (
      .clk(clk),
      .rst_n(rst_n),
      .init(crc_init),
      .en(crc_en),
      .din(crc_din),
      .crc_out(crc_out)
  );

  assign crc_init = (state == START);
  assign crc_en   = tick && (state == DATA || state == PAD);
  assign crc_din  = pair_to_send;

  // Counters
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      pair_cnt <= '0;
      byte_cnt <= '0;
    end else if (tick) begin
      if (state != IDLE) pair_cnt <= pair_cnt + 1;

      if (next_state != state && next_state != PAD) byte_cnt <= '0;
      else if (last_pair && !(state == DATA && min_len_reached)) byte_cnt <= byte_cnt + 1;
    end
  end

  assign last_pair = (pair_cnt == LastPair);
  assign min_len_reached = (byte_cnt == $bits(byte_cnt)'(PAD_TO_BYTES - 1));

`ifdef FORMAL
  localparam int GapTicks = GAP_BYTES * PairsPerByte;

  logic f_past_valid = 1'b0;
  logic f_tick_q = 1'b0;
  logic f_after_reset = 1'b1;
  logic [15:0] f_low = '0;
  logic [15:0] f_ticks = '0;

  initial assume (!rst_n);

  always @(posedge clk) begin
    f_past_valid <= 1'b1;
    f_tick_q <= tick;

    if (!rst_n) begin
      f_low <= '0;
      f_after_reset <= 1'b1;
    end else begin
      if (f_tick_q && phy_tx_en) f_low <= '0;
      else if (f_tick_q && f_low != 16'hFFFF) f_low <= f_low + 1'b1;
      if (phy_tx_en) f_after_reset <= 1'b0;
    end

    if (!rst_n) f_ticks <= '0;
    else if (tick) f_ticks <= (next_state != state) ? '0 : f_ticks + 1'b1;
  end

  always @(posedge clk) begin
    if (f_past_valid) begin
      assert (phy_tx_en || phy_txd == 2'b00);

      case (state)
        PREAMBLE: assert (f_ticks < 16'(PREAMBLE_BYTES * PairsPerByte));
        START: assert (f_ticks < 16'(PairsPerByte));
        PAD: assert (f_ticks < 16'(PAD_TO_BYTES * PairsPerByte));
        CRC: assert (f_ticks < 16'(CrcBytes * PairsPerByte));
        GAP: assert (f_ticks < 16'(GapTicks));
        default: ;
      endcase
    end

    if (f_past_valid && $past(rst_n)) begin
      if (!$past(tick)) assert (phy_tx_en == $past(phy_tx_en) && phy_txd == $past(phy_txd));
      if ($fell(phy_tx_en)) assert ($past(state) == GAP);
      if ($rose(phy_tx_en) && !f_after_reset) assert (f_low >= 16'(GapTicks));
    end

    if (f_past_valid && $past(rst_n) && rst_n) begin
      cover ($fell(phy_tx_en) && underrun);
      cover ($fell(phy_tx_en) && !underrun);
      cover ($rose(phy_tx_en) && !f_after_reset && f_low == 16'(GapTicks + 1));
    end
  end
`endif

endmodule

`default_nettype wire
