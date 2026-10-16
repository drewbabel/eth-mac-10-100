module rmii_line_tb ();

  localparam int NumFrames = 46;
  localparam int NumBytes = 17508;
  localparam int NumOut = 17730;
  localparam int WireNumOut = 17730;
  localparam int TimeoutClks = 2_000_000;

  int checks;
  int errors;
  int max_errors;

  rmii_line_bench #(
      .LOOPBACK  (1'b1),
      .NUM_FRAMES(NumFrames),
      .NUM_BYTES (NumBytes),
      .NUM_OUT   (NumOut),
      .EXPECT_FILE("tb/rmii_line_expect.hex")
  ) loop_bench ();

  rmii_line_bench #(
      .LOOPBACK  (1'b0),
      .NUM_FRAMES(NumFrames),
      .NUM_BYTES (NumBytes),
      .NUM_OUT   (WireNumOut),
      .EXPECT_FILE("tb/rmii_line_expect_wire.hex")
  ) wire_bench ();

  task automatic do_verdict();
    checks = loop_bench.checks + wire_bench.checks;
    errors = loop_bench.errors + wire_bench.errors;
    if (checks < NumOut + WireNumOut) begin
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, NumOut + WireNumOut);
    end else if (errors == 0) begin
      $display("PASS: %0d checks, %0d mismatches", checks, errors);
    end else begin
      $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    end
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, rmii_line_tb);
    wait (loop_bench.done && wire_bench.done);
    do_verdict();
  end

  initial begin
    repeat (TimeoutClks) @(posedge loop_bench.clk);
    $fatal(1, "TB TIMEOUT: %0d and %0d of %0d outputs", loop_bench.mon_out, wire_bench.mon_out,
           NumOut);
  end

  initial begin
    if ($value$plusargs("max_errors=%d", max_errors) && max_errors > 0) begin
      wait (loop_bench.errors + wire_bench.errors >= max_errors);
      $fatal(1, "TB STOPPED: %0d mismatches", loop_bench.errors + wire_bench.errors);
    end
  end

endmodule

module rmii_line_bench #(
    parameter logic LOOPBACK = 1'b1,
    parameter int NUM_FRAMES = 1,
    parameter int NUM_BYTES = 1,
    parameter int NUM_OUT = 1,
    parameter string EXPECT_FILE = "tb/rmii_line_expect.hex"
) ();

  int checks = 0;
  int errors = 0;

  localparam int StallTicks = 20;
  localparam int SettleClks = 400;

  logic clk = 0;
  logic rst_n;
  logic speed_100;
  logic tx_valid;
  logic tx_ready;
  logic [7:0] tx_data;
  logic tx_last;
  logic [7:0] rx_data;
  logic rx_valid;
  logic rx_last;
  logic rx_bad;
  logic phy_tx_en;
  logic [1:0] phy_txd;
  logic phy_crs_dv;
  logic [1:0] phy_rxd;

  logic [7:0] data_mem[NUM_BYTES];
  logic [71:0] frame_mem[NUM_FRAMES];
  logic [9:0] expect_mem[NUM_OUT];
  int byte_offset[NUM_FRAMES];

  int div = 1;
  int taken = 0;
  int mon_out = 0;
  int pin_frame = 0;
  int pin_pair = 0;
  int clk_cnt = 0;
  int pair_clk = 0;
  logic en_seen = 1'b0;
  logic flip_now;
  logic done = 1'b0;

  always #5 clk = ~clk;

  rmii_line dut (
      .clk(clk),
      .rst_n(rst_n),
      .speed_100(speed_100),
      .loopback(LOOPBACK),
      .tx_valid(tx_valid),
      .tx_ready(tx_ready),
      .tx_data(tx_data),
      .tx_last(tx_last),
      .rx_data(rx_data),
      .rx_valid(rx_valid),
      .rx_last(rx_last),
      .rx_bad(rx_bad),
      .phy_tx_en(phy_tx_en),
      .phy_txd(phy_txd),
      .phy_crs_dv(phy_crs_dv),
      .phy_rxd(phy_rxd)
  );

  assign flip_now = !LOOPBACK && phy_tx_en && pin_frame < NUM_FRAMES &&
      frame_mem[pin_frame][15:0] != '0 && pin_pair == int'(frame_mem[pin_frame][15:0]);
  assign phy_crs_dv = LOOPBACK ? 1'b0 : phy_tx_en;
  assign phy_rxd = LOOPBACK ? 2'b00 : phy_txd ^ {1'b0, flip_now};

  task automatic do_reset();
    rst_n = 1'b0;
    speed_100 = 1'b1;
    tx_valid = 1'b0;
    tx_data = '0;
    tx_last = 1'b0;
    repeat (5) @(posedge clk);
    #1 rst_n = 1'b1;
  endtask  // Automatic

  task automatic check(input string name, input logic [31:0] got, input logic [31:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $error("t=%0t %m %s mismatch: got=%h, exp=%h", $time, name, got, exp);
    end
  endtask  // Automatic

  task automatic send_frame(input int f);
    int t0 = taken;
    int frame_div = int'(frame_mem[f][71:64]);
    int len = int'(frame_mem[f][47:32]);
    int stall = int'(frame_mem[f][31:16]);
    if (frame_div != div) begin
      wait (!phy_tx_en);
      repeat (SettleClks) @(posedge clk);
      div = frame_div;
      #1 speed_100 = (div == 1);
    end
    repeat (int'(frame_mem[f][63:48])) @(posedge clk);
    for (int i = 0; i < len; i++) begin
      if (stall != 0 && i == stall) begin
        #1 tx_valid = 1'b0;
        repeat (StallTicks * div) @(posedge clk);
      end
      #1 tx_valid = 1'b1;
      tx_data = data_mem[byte_offset[f]+i];
      tx_last = (i == len - 1);
      wait (taken == t0 + i + 1);
    end
    #1 tx_valid = 1'b0;
    tx_last = 1'b0;
  endtask  // Automatic

  initial begin
    $readmemh("tb/rmii_line_data.hex", data_mem);
    $readmemh("tb/rmii_line_frames.hex", frame_mem);
    $readmemh(EXPECT_FILE, expect_mem);
    byte_offset[0] = 0;
    for (int f = 1; f < NUM_FRAMES; f++) begin
      byte_offset[f] = byte_offset[f-1] + int'(frame_mem[f-1][47:32]);
    end
    do_reset();

    for (int f = 0; f < NUM_FRAMES; f++) send_frame(f);

    wait (pin_frame == NUM_FRAMES);
    repeat (SettleClks) @(posedge clk);
    check("outputs", 32'(mon_out), 32'(NUM_OUT));
    done = 1'b1;
  end

  always @(posedge clk) begin
    if (tx_valid && tx_ready) taken <= taken + 1;
    clk_cnt <= clk_cnt + 1;
  end

  always begin
    @(posedge clk);
    if (dut.tick) begin
      #1;
      if (phy_tx_en && en_seen) check("pair clocks", 32'(clk_cnt - pair_clk), 32'(div));
      if (phy_tx_en) pin_pair = en_seen ? pin_pair + 1 : 0;
      else if (en_seen) pin_frame++;
      en_seen  = phy_tx_en;
      pair_clk = clk_cnt;
    end
  end

  always @(posedge clk) begin
    if (rx_valid) begin
      check("byte", 32'({rx_bad, rx_last, rx_data}), 32'(expect_mem[mon_out]));
      mon_out <= mon_out + 1;
    end
  end

endmodule
