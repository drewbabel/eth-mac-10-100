`default_nettype none

`ifdef FORMAL
`ifndef RMII_LINE_COVER
`define RMII_LINE_LINK
`endif
`endif

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

`ifdef RMII_LINE_LINK
  logic [7:0] f_cnt;
  logic [2:0] f_txs;
  logic [1:0] f_txp;
  logic [7:0] f_txb;
  logic [7:0] f_txdb;
  logic f_txdl;
  logic f_txu;
  logic [31:0] f_txcrc;
  logic [15:0] f_txlow;
  logic f_txtq;
  logic f_txnf;
  logic [15:0] f_txticks;
  logic f_rif;
  logic [1:0] f_rxp;
  logic [7:0] f_rxb;
  logic [7:0] f_rnb;
  logic [39:0] f_rhb;
  logic [2:0] f_rmid;
  logic f_rcrs;
  logic [1:0] f_rrxd;
  logic f_rcrs_last;
  logic [1:0] f_rrxd_last;
  logic [31:0] f_rxcrc;
  logic f_rtag;
`endif

  tick_gen #(
      .DIVISOR(SlowDivisor)
  ) u_tick_gen (
`ifdef RMII_LINE_LINK
      .f_cnt(f_cnt),
`endif
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
`ifdef RMII_LINE_LINK
      .f_state(f_txs),
      .f_pair_cnt(f_txp),
      .f_byte_cnt(f_txb),
      .f_data_byte(f_txdb),
      .f_data_last(f_txdl),
      .f_underrun(f_txu),
      .f_crc_out(f_txcrc),
      .f_low_cnt(f_txlow),
      .f_tick_seen(f_txtq),
      .f_no_frame(f_txnf),
      .f_state_ticks(f_txticks),
`endif
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
`ifdef RMII_LINE_LINK
      .f_in_frame(f_rif),
      .f_pair_cnt(f_rxp),
      .f_byte_cnt(f_rxb),
      .f_new_byte(f_rnb),
      .f_held_bytes(f_rhb),
      .f_mid(f_rmid),
      .f_crs_dv(f_rcrs),
      .f_rxd(f_rrxd),
      .f_crs_dv_last(f_rcrs_last),
      .f_rxd_last(f_rrxd_last),
      .f_crc_out(f_rxcrc),
      .f_has_tag(f_rtag),
`endif
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


`ifdef RMII_LINE_LINK
  // Transmitter history
  localparam logic [2:0] SIdle = 3'd0, SPre = 3'd1, SStart = 3'd2, SData = 3'd3, SPad = 3'd4,
      SCrc = 3'd5, SGap = 3'd6;

  logic [5:0] f_kidx;
  logic [31:0] f_kval;

  assign f_kval =
      (f_kidx == 6'd0) ? 32'h00000000 :
      (f_kidx == 6'd2) ? 32'h0D4326D9 :
      (f_kidx == 6'd4) ? 32'h384FBDBD :
      (f_kidx == 6'd6) ? 32'hEC7DD02D :
      (f_kidx == 6'd8) ? 32'hB1F740B4 :
      (f_kidx == 6'd10) ? 32'hC31C1F67 :
      (f_kidx == 6'd12) ? 32'h0C707D9C :
      (f_kidx == 6'd14) ? 32'h3C82D0A9 :
      (f_kidx == 6'd16) ? 32'hFF48647D :
      (f_kidx == 6'd18) ? 32'hFD2191F4 :
      (f_kidx == 6'd20) ? 32'hF48647D0 :
      (f_kidx == 6'd22) ? 32'hD2191F40 :
      (f_kidx == 6'd24) ? 32'h48647D00 :
      (f_kidx == 6'd26) ? 32'h2813CF6E :
      (f_kidx == 6'd28) ? 32'hAD0C1B61 :
      (f_kidx == 6'd30) ? 32'hB0F17033 :
      (f_kidx == 6'd32) ? 32'hC704DD7B :
      32'h00000000;

  function automatic [1:0] f_pts(input [2:0] st, input [1:0] pr, input [3:0] bc, input [7:0] db,
                                 input [31:0] cr);
    reg [31:0] s;
    integer i;
    for (i = 0; i < 32; i = i + 1) s[i] = ~cr[31-i];
    case (st)
      SPre: f_pts = 2'b01;
      SStart: f_pts = (pr == 2'd3) ? 2'b11 : 2'b01;
      SData: f_pts = db[2*pr+:2];
      SCrc: f_pts = s[8*bc[1:0]+2*pr+:2];
      default: f_pts = 2'b00;
    endcase
  endfunction

  function automatic f_send(input [2:0] st);
    f_send = (st == SPre) || (st == SStart) || (st == SData) || (st == SPad) || (st == SCrc);
  endfunction

  function automatic [1:0] f_sat1(input [1:0] x);
    f_sat1 = (x == 2'd3) ? 2'd3 : x + 2'd1;
  endfunction

  function automatic [3:0] f_body(input [2:0] nd);
    f_body = (nd < 3'd3) ? 4'd3 : {1'b0, nd};
  endfunction

  logic [3:0] f_bpos = '0;
  logic [1:0] f_wf = '0;
  logic [2:0] f_nd = '0;
  logic [2:0] g0_st = '0;
  logic [1:0] g0_pr = '0;
  logic [3:0] g0_bc = '0;
  logic [3:0] g0_bp = '0;
  logic [1:0] g0_wf = '0;
  logic [2:0] g0_nd = '0;
  logic [31:0] g0_crc = '0;
  logic [7:0] g0_db = '0;
  logic [2:0] g1_st = '0;
  logic [1:0] g1_pr = '0;
  logic [3:0] g1_bc = '0;
  logic [3:0] g1_bp = '0;
  logic [1:0] g1_wf = '0;
  logic [2:0] g1_nd = '0;
  logic [31:0] g1_crc = '0;
  logic [7:0] g1_db = '0;
  logic [2:0] g2_st = '0;
  logic [1:0] g2_pr = '0;
  logic [3:0] g2_bc = '0;
  logic [3:0] g2_bp = '0;
  logic [1:0] g2_wf = '0;
  logic [2:0] g2_nd = '0;
  logic [31:0] g2_crc = '0;
  logic [7:0] g2_db = '0;
  logic [2:0] g3_st = '0;
  logic [1:0] g3_pr = '0;
  logic [3:0] g3_bc = '0;
  logic [3:0] g3_bp = '0;
  logic [1:0] g3_wf = '0;
  logic [2:0] g3_nd = '0;
  logic [31:0] g3_crc = '0;
  logic [7:0] g3_db = '0;

  always @(posedge clk) begin
    if (!rst_n) begin
      f_bpos <= '0;
      f_wf <= '0;
      f_nd <= '0;
      g0_st <= '0;
      g0_pr <= '0;
      g0_bc <= '0;
      g0_bp <= '0;
      g0_wf <= '0;
      g0_nd <= '0;
      g0_crc <= '0;
      g0_db <= '0;
      g1_st <= '0;
      g1_pr <= '0;
      g1_bc <= '0;
      g1_bp <= '0;
      g1_wf <= '0;
      g1_nd <= '0;
      g1_crc <= '0;
      g1_db <= '0;
      g2_st <= '0;
      g2_pr <= '0;
      g2_bc <= '0;
      g2_bp <= '0;
      g2_wf <= '0;
      g2_nd <= '0;
      g2_crc <= '0;
      g2_db <= '0;
      g3_st <= '0;
      g3_pr <= '0;
      g3_bc <= '0;
      g3_bp <= '0;
      g3_wf <= '0;
      g3_nd <= '0;
      g3_crc <= '0;
      g3_db <= '0;
    end else begin
      if (f_tx_xfer) f_nd <= f_tx_cnt + 1'b1;
      if (tick) begin
        g0_st <= f_txs;
        g0_pr <= f_txp;
        g0_bc <= f_txb[3:0];
        g0_bp <= f_bpos;
        g0_wf <= f_wf;
        g0_nd <= f_nd;
        g0_crc <= f_txcrc;
        g0_db <= f_txdb;
        g1_st <= g0_st;
        g1_pr <= g0_pr;
        g1_bc <= g0_bc;
        g1_bp <= g0_bp;
        g1_wf <= g0_wf;
        g1_nd <= g0_nd;
        g1_crc <= g0_crc;
        g1_db <= g0_db;
        g2_st <= g1_st;
        g2_pr <= g1_pr;
        g2_bc <= g1_bc;
        g2_bp <= g1_bp;
        g2_wf <= g1_wf;
        g2_nd <= g1_nd;
        g2_crc <= g1_crc;
        g2_db <= g1_db;
        g3_st <= g2_st;
        g3_pr <= g2_pr;
        g3_bc <= g2_bc;
        g3_bp <= g2_bp;
        g3_wf <= g2_wf;
        g3_nd <= g2_nd;
        g3_crc <= g2_crc;
        g3_db <= g2_db;
        if (f_txs == SStart) f_bpos <= '0;
        else if ((f_txs == SData || f_txs == SPad || f_txs == SCrc) && f_txp == 2'd3)
          f_bpos <= f_bpos + 1'b1;
        if (f_txs == SGap && f_txp == 2'd3 && f_txb == 8'(GAP_BYTES - 1)) f_wf <= f_sat1(f_wf);
      end
    end
  end

`ifdef LINE_SPEED_10
  wire [2:0] d_st = g1_st;
  wire [2:0] n_st = g0_st;
  wire [1:0] d_pr = g1_pr;
  wire [1:0] n_pr = g0_pr;
  wire [3:0] d_bc = g1_bc;
  wire [3:0] n_bc = g0_bc;
  wire [3:0] d_bp = g1_bp;
  wire [3:0] n_bp = g0_bp;
  wire [1:0] d_wf = g1_wf;
  wire [1:0] n_wf = g0_wf;
  wire [2:0] d_nd = g1_nd;
  wire [2:0] n_nd = g0_nd;
  wire [31:0] d_crc = g1_crc;
  wire [31:0] n_crc = g0_crc;
  wire [7:0] d_db = g1_db;
  wire [7:0] n_db = g0_db;
  wire f_phase0 = (f_cnt == 8'd0);
`else
  wire [2:0] d_st = g3_st;
  wire [2:0] n_st = g2_st;
  wire [1:0] d_pr = g3_pr;
  wire [1:0] n_pr = g2_pr;
  wire [3:0] d_bc = g3_bc;
  wire [3:0] n_bc = g2_bc;
  wire [3:0] d_bp = g3_bp;
  wire [3:0] n_bp = g2_bp;
  wire [1:0] d_wf = g3_wf;
  wire [1:0] n_wf = g2_wf;
  wire [2:0] d_nd = g3_nd;
  wire [2:0] n_nd = g2_nd;
  wire [31:0] d_crc = g3_crc;
  wire [31:0] n_crc = g2_crc;
  wire [7:0] d_db = g3_db;
  wire [7:0] n_db = g2_db;
  wire f_phase0 = 1'b1;
`endif

  wire [1:0] f_pk = {1'b0, f_pick};
  wire [5:0] f_dn = {2'b00, d_bc[1:0], d_pr};
  assign f_kidx = {f_dn[4:0], 1'b0};
  wire f_exp_in = (d_st == SData) || (d_st == SPad) || (d_st == SCrc) ||
      (d_st == SGap && d_bc == 4'd0 && d_pr == 2'd0);
  wire f_gap2 = (d_st == SGap) && (d_bc == 4'd0) && (d_pr == 2'd1);
  wire [3:0] f_m = {d_bc[1:0], d_pr};
  wire [3:0] f_tpos = {f_txb[1:0], f_txp};
  wire f_post = (f_txs == SData && f_txdl) || f_txs == SPad || f_txs == SCrc || f_txs == SGap;
  wire [4:0] f_bp5 = {1'b0, d_bp};
  wire [4:0] f_idx5 = {2'b00, f_idx} + 5'd5;

  always @(posedge clk) begin
    if (f_past_valid && rst_n) begin
      // Transmitter
      assert (!f_txu);
      assert (f_txs <= SGap);
      if (f_txs == SIdle) assert (f_txp == 2'd0 && f_txb == 8'd0);
      if (f_txs == SPre) assert (f_txb <= 8'd1);
      if (f_txs == SStart) assert (f_txb == 8'd0);
      if (f_txs == SGap) assert (f_txb <= 8'd1);
      if (f_txs == SPre || f_txs == SStart) assert (tx_valid);
      assert (f_in_frame == (f_txs == SData && !f_txdl));
      if (f_txs == SData && !f_txdl) assert ({1'b0, f_tx_cnt} == f_bpos + 1'b1);
      else assert (f_tx_cnt == '0);
      if (f_txs == SData) begin
        assert (f_bpos <= 4'd3);
        assert ({1'b0, f_nd} == f_bpos + 1'b1);
        assert (f_txb == ((f_bpos >= 4'd2) ? 8'd2 : {4'd0, f_bpos}));
      end
      if (f_txs == SPad) begin
        assert (f_txb == {4'd0, f_bpos});
        assert (f_bpos <= 4'd2 && f_nd >= 3'd1 && f_bpos >= {1'b0, f_nd});
      end
      if (f_txs == SCrc) begin
        assert (f_nd >= 3'd1 && f_nd <= 3'd4 && f_txb <= 8'd3);
        assert (f_bpos == f_body(f_nd) + f_txb[3:0]);
      end
      if (f_txs == SGap) begin
        assert (f_nd >= 3'd1 && f_nd <= 3'd4);
        assert (f_bpos == f_body(f_nd) + 4'd4);
      end
      assert (f_tx_frame == ((f_wf == 2'd3) ? 2'd3 : (f_post ? f_sat1(f_wf) : f_wf)));
      if (f_txs == SData && f_wf == f_pk && f_bpos == {1'b0, f_idx})
        assert (f_have && f_txdb == f_byte);
      if (f_wf == f_pk) begin
        if (f_txs == SIdle || f_txs == SPre || f_txs == SStart) assert (!f_have);
        else assert (f_have == (f_idx < f_nd));
      end
      if (f_wf < f_pk) assert (!f_have);

      // State tick counter
      if (f_txs == SPre || f_txs == SStart || f_txs == SCrc || f_txs == SGap)
        assert (f_txticks == {12'd0, f_tpos});
      if (f_txs == SPad)
        assert (f_txticks == {10'd0, f_bpos - {1'b0, f_nd}, f_txp});

      // Gap counter
      if (f_wf != 2'd0) assert (!f_txnf);
      if (f_txs == SIdle && f_wf == 2'd0) assert (f_txnf);
      if (f_txs == SPre && f_tpos == 4'd0 && f_wf == 2'd0) assert (f_txnf);
      if (f_txs == SPre && f_tpos == 4'd1 && f_wf == 2'd0 && !f_txtq) assert (!f_txnf);
      if (f_txs != SIdle && !(f_txs == SPre && f_tpos <= 4'd1)) assert (!f_txnf);
      if (!f_txnf) begin
        if (f_txs == SIdle) assert (f_txlow >= 16'(4 * GAP_BYTES - 1) + {15'd0, !f_txtq});
        if (f_txs == SPre && f_tpos == 4'd0) assert (f_txlow >= 16'(4 * GAP_BYTES) + {15'd0, !f_txtq});
        if (f_txs == SPre && f_tpos == 4'd1)
          assert (f_txtq ? f_txlow >= 16'(4 * GAP_BYTES) : f_txlow == 16'd0);
        if ((f_txs == SPre && f_tpos >= 4'd2) || f_txs == SStart || f_txs == SData ||
            f_txs == SPad || f_txs == SCrc || (f_txs == SGap && f_tpos == 4'd0))
          assert (f_txlow == 16'd0);
        if (f_txs == SGap && f_tpos != 4'd0)
          assert (f_txlow == {12'd0, f_tpos} - 16'd1 + {15'd0, !f_txtq});
      end

      // Pins and synchronizer
      assert (phy_tx_en == f_send(g0_st));
      assert (phy_txd == f_pts(g0_st, g0_pr, g0_bc, g0_db, g0_crc));
      assert (f_rcrs_last == f_send(d_st));
      assert (f_rrxd_last == f_pts(d_st, d_pr, d_bc, d_db, d_crc));
`ifdef LINE_SPEED_10
      assert (f_cnt <= 8'd9);
      if (f_cnt == 8'd0) begin
        assert (f_rmid == {f_rcrs_last, f_rrxd_last});
        assert ({f_rcrs, f_rrxd} == {f_rcrs_last, f_rrxd_last});
      end else if (f_cnt == 8'd1) begin
        assert (f_rmid == {phy_tx_en, phy_txd});
        assert ({f_rcrs, f_rrxd} == {f_rcrs_last, f_rrxd_last});
      end else begin
        assert (f_rmid == {phy_tx_en, phy_txd});
        assert ({f_rcrs, f_rrxd} == {phy_tx_en, phy_txd});
      end
      if (rx_valid) assert (f_cnt == 8'd0);
`else
      assert (f_rmid == {f_send(g1_st), f_pts(g1_st, g1_pr, g1_bc, g1_db, g1_crc)});
      assert (f_rcrs == f_send(g2_st));
      assert (f_rrxd == f_pts(g2_st, g2_pr, g2_bc, g2_db, g2_crc));
`endif

      // Receiver framing
      assert (f_rif == f_exp_in);
      if (!f_rif) assert (f_rxp == 2'd0);
      else assert (f_rxp == d_pr && f_rxb == {4'd0, d_bp});
      if (d_st == SPre) begin
        if (f_m == 4'd0) assert (f_rnb[7:6] == 2'b00);
        else if (f_m == 4'd1) assert (f_rnb[7:4] == 4'b0100);
        else if (f_m == 4'd2) assert (f_rnb[7:2] == 6'b010100);
        else if (f_m == 4'd3) assert (f_rnb == 8'h54);
        else assert (f_rnb == 8'h55);
      end
      if (d_st == SStart) assert (f_rnb == 8'h55);
      if (f_rif) assert (!f_rtag);

      // Checksum link
      if (d_st == SData || d_st == SPad) assert (f_rxcrc == d_crc);
      if (d_st == SCrc) assert (f_rxcrc == ((d_crc << f_kidx) ^ f_kval));
      if (d_st == SGap && d_bc == 4'd0 && d_pr == 2'd0) assert (f_rxcrc == 32'hC704DD7B);
      if (d_st == SGap) assert (d_bp >= 4'd7 && d_bp <= 4'd8);

      // Receiver outputs
      assert (rx_valid == (f_phase0 && ((f_exp_in && d_pr == 2'd0 && d_bp >= 4'd6) || f_gap2)));
      assert (rx_last == (f_phase0 && f_gap2));
      assert (!rx_bad);
      if (f_exp_in)
        assert ({1'b0, f_rx_cnt} == ((d_bp >= 4'd6) ? d_bp - 4'd5 - {3'd0, rx_valid} : 4'd0));
      else if (f_gap2) assert ({1'b0, f_rx_cnt} == (rx_valid ? d_bp - 4'd5 : 4'd0));
      else assert (f_rx_cnt == '0);
      if (f_exp_in || (f_gap2 && rx_valid) || d_st == SIdle || d_st == SPre || d_st == SStart)
        assert (f_rx_frame == d_wf);
      else assert (f_rx_frame == f_sat1(d_wf));

      // Picked byte path
      if (d_st == SData && d_wf == f_pk && d_bp == {1'b0, f_idx} && f_have)
        assert (d_db == f_byte);
      if (f_exp_in && d_wf == f_pk && f_have) begin
        if (f_bp5 + 5'd0 == f_idx5) assert (f_rhb[7:0] == f_byte);
        if (f_bp5 + 5'd1 == f_idx5) assert (f_rhb[15:8] == f_byte);
        if (f_bp5 + 5'd2 == f_idx5) assert (f_rhb[23:16] == f_byte);
        if (f_bp5 + 5'd3 == f_idx5) assert (f_rhb[31:24] == f_byte);
        if (f_bp5 + 5'd4 == f_idx5) assert (f_rhb[39:32] == f_byte);
        if (d_st != SGap && d_bp == {1'b0, f_idx}) begin
          if (d_pr == 2'd1) assert (f_rnb[7:6] == f_byte[1:0]);
          if (d_pr == 2'd2) assert (f_rnb[7:4] == f_byte[3:0]);
          if (d_pr == 2'd3) assert (f_rnb[7:2] == f_byte[5:0]);
        end
      end
      if (rx_valid && d_wf == f_pk && f_rx_cnt == f_idx && f_have) assert (rx_data == f_byte);
    end
  end
`endif

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

`default_nettype wire
