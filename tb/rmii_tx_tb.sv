`default_nettype none

module rmii_tx_tb ();

  localparam int PreambleBytes = 7;
  localparam int PadToBytes = 60;
  localparam int GapBytes = 12;
  localparam int AltPreambleBytes = 10;
  localparam int AltPadToBytes = 30;
  localparam int AltGapBytes = 70;
  localparam int NumFrames = 52;
  localparam int NumBytes = 23365;
  localparam int NumPairs = 97440;
  localparam int AltNumPairs = 96624;
  localparam int TimeoutClks = 2_000_000;

  int checks;
  int errors;
  int max_errors;

  rmii_tx_bench #(
      .PREAMBLE_BYTES(PreambleBytes),
      .PAD_TO_BYTES(PadToBytes),
      .GAP_BYTES(GapBytes),
      .NUM_FRAMES(NumFrames),
      .NUM_BYTES(NumBytes),
      .NUM_PAIRS(NumPairs),
      .FRAMES_FILE("tb/rmii_tx_frames.hex"),
      .EXPECT_FILE("tb/rmii_tx_expect.hex")
  ) std_bench ();

  rmii_tx_bench #(
      .PREAMBLE_BYTES(AltPreambleBytes),
      .PAD_TO_BYTES(AltPadToBytes),
      .GAP_BYTES(AltGapBytes),
      .NUM_FRAMES(NumFrames),
      .NUM_BYTES(NumBytes),
      .NUM_PAIRS(AltNumPairs),
      .FRAMES_FILE("tb/rmii_tx_frames_alt.hex"),
      .EXPECT_FILE("tb/rmii_tx_expect_alt.hex")
  ) alt_bench ();

  task automatic do_verdict();
    checks = std_bench.checks + alt_bench.checks;
    errors = std_bench.errors + alt_bench.errors;
    if (checks < 2 * NumFrames) begin
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, 2 * NumFrames);
    end else if (errors == 0) begin
      $display("PASS: %0d checks, %0d mismatches", checks, errors);
    end else begin
      $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    end
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, rmii_tx_tb);
    wait (std_bench.done && alt_bench.done);
    do_verdict();
  end

  initial begin
    repeat (TimeoutClks) @(posedge std_bench.clk);
    $fatal(1, "TB TIMEOUT: %0d and %0d of %0d frames out", std_bench.mon_frame,
           alt_bench.mon_frame, NumFrames);
  end

  initial begin
    if ($value$plusargs("max_errors=%d", max_errors) && max_errors > 0) begin
      wait (std_bench.errors + alt_bench.errors >= max_errors);
      $fatal(1, "TB STOPPED: %0d mismatches", std_bench.errors + alt_bench.errors);
    end
  end

endmodule

module rmii_tx_bench #(
    parameter int PREAMBLE_BYTES = 7,
    parameter int PAD_TO_BYTES = 60,
    parameter int GAP_BYTES = 12,
    parameter int NUM_FRAMES = 1,
    parameter int NUM_BYTES = 1,
    parameter int NUM_PAIRS = 1,
    parameter string FRAMES_FILE = "tb/rmii_tx_frames.hex",
    parameter string EXPECT_FILE = "tb/rmii_tx_expect.hex"
) ();

  int checks = 0;
  int errors = 0;

  localparam int PairsPerByte = 4;
  localparam int StallTicks   = 20;

  logic clk = 0;
  logic rst_n;
  logic tick;
  logic tx_valid;
  logic tx_ready;
  logic [7:0] tx_data;
  logic tx_last;
  logic phy_tx_en;
  logic [1:0] phy_txd;

  logic [7:0] data_mem[NUM_BYTES];
  logic [103:0] frame_mem[NUM_FRAMES];
  logic [1:0] expect_mem[NUM_PAIRS];
  int byte_offset[NUM_FRAMES];
  int pair_offset[NUM_FRAMES];

  int div = 1;
  int tick_cnt = 0;
  int taken = 0;
  logic tick_q = 1'b0;
  logic aborting = 1'b0;
  logic done = 1'b0;

  int mon_frame = 0;
  int mon_pair = 0;
  int mon_cnt = 0;
  int gap_ticks = 0;
  logic en_q = 1'b0;
  logic after_abort = 1'b1;

  always #5 clk = ~clk;

  assign tick = (tick_cnt == div - 1);

  rmii_tx #(
      .PREAMBLE_BYTES(PREAMBLE_BYTES),
      .PAD_TO_BYTES(PAD_TO_BYTES),
      .GAP_BYTES(GAP_BYTES)
  ) dut (
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

  task automatic do_reset();
    rst_n = 1'b0;
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
    int len = int'(frame_mem[f][79:64]);
    int stall = int'(frame_mem[f][63:48]);
    int rst_at = int'(frame_mem[f][47:32]);
    div = int'(frame_mem[f][103:96]);
    repeat (int'(frame_mem[f][95:80])) @(posedge clk);
    for (int i = 0; i < len; i++) begin
      if (stall != 0 && i == stall) begin
        #1 tx_valid = 1'b0;
        repeat (StallTicks * div) @(posedge clk);
      end
      if (rst_at != 0 && i == rst_at) begin
        aborting = 1'b1;
        do_reset();
        check("reset quiet", 32'(phy_tx_en), 32'd0);
        return;
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
    $readmemh("tb/rmii_tx_data.hex", data_mem);
    $readmemh(FRAMES_FILE, frame_mem);
    $readmemh(EXPECT_FILE, expect_mem);
    byte_offset[0] = 0;
    pair_offset[0] = 0;
    for (int f = 1; f < NUM_FRAMES; f++) begin
      byte_offset[f] = byte_offset[f-1] + int'(frame_mem[f-1][79:64]);
      pair_offset[f] = pair_offset[f-1] + int'(frame_mem[f-1][31:0]);
    end
    do_reset();

    for (int f = 0; f < NUM_FRAMES; f++) send_frame(f);

    wait (mon_frame == NUM_FRAMES);
    done = 1'b1;
  end

  always @(posedge clk) begin
    tick_cnt <= (tick_cnt >= div - 1) ? 0 : tick_cnt + 1;
    tick_q   <= tick;
    if (tx_valid && tx_ready) taken <= taken + 1;
  end

  always @(posedge clk) begin
    if (tick_q) begin
      en_q <= phy_tx_en;
      if (phy_tx_en) begin
        if (!en_q) begin
          if (!after_abort) check("gap", 32'(gap_ticks >= GAP_BYTES * PairsPerByte), 32'd1);
          mon_pair <= pair_offset[mon_frame] + 1;
          mon_cnt  <= 1;
          check("pair", 32'(phy_txd), 32'(expect_mem[pair_offset[mon_frame]]));
        end else begin
          mon_pair <= mon_pair + 1;
          mon_cnt  <= mon_cnt + 1;
          check("pair", 32'(phy_txd), 32'(expect_mem[mon_pair]));
        end
      end else begin
        gap_ticks <= en_q ? 1 : gap_ticks + 1;
        if (en_q) begin
          if (aborting) aborting <= 1'b0;
          else check("frame pairs", 32'(mon_cnt), frame_mem[mon_frame][31:0]);
          after_abort <= aborting;
          mon_frame   <= mon_frame + 1;
        end
      end
    end
  end

endmodule

`default_nettype wire
