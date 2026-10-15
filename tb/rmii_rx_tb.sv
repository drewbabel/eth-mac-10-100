module rmii_rx_tb ();

  localparam int MinFrameBytes = 64;
  localparam int MaxFrameBytes = 1518;
  localparam int MaxTaggedFrameBytes = 1522;
  localparam int AltMinFrameBytes = 20;
  localparam int AltMaxFrameBytes = 200;
  localparam int AltMaxTaggedFrameBytes = 204;
  localparam int NumFrames = 86;
  localparam int NumPins = 147308;
  localparam int NumOut = 35184;
  localparam int AltNumOut = 35184;
  localparam int TimeoutClks = 5_000_000;

  int checks;
  int errors;
  int max_errors;

  rmii_rx_bench #(
      .MIN_FRAME_BYTES(MinFrameBytes),
      .MAX_FRAME_BYTES(MaxFrameBytes),
      .MAX_TAGGED_FRAME_BYTES(MaxTaggedFrameBytes),
      .NUM_FRAMES(NumFrames),
      .NUM_PINS(NumPins),
      .NUM_OUT(NumOut),
      .EXPECT_FILE("tb/rmii_rx_expect.hex")
  ) std_bench ();

  rmii_rx_bench #(
      .MIN_FRAME_BYTES(AltMinFrameBytes),
      .MAX_FRAME_BYTES(AltMaxFrameBytes),
      .MAX_TAGGED_FRAME_BYTES(AltMaxTaggedFrameBytes),
      .NUM_FRAMES(NumFrames),
      .NUM_PINS(NumPins),
      .NUM_OUT(AltNumOut),
      .EXPECT_FILE("tb/rmii_rx_expect_alt.hex")
  ) alt_bench ();

  task automatic do_verdict();
    checks = std_bench.checks + alt_bench.checks;
    errors = std_bench.errors + alt_bench.errors;
    if (checks < NumOut + AltNumOut) begin
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, NumOut + AltNumOut);
    end else if (errors == 0) begin
      $display("PASS: %0d checks, %0d mismatches", checks, errors);
    end else begin
      $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    end
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, rmii_rx_tb);
    wait (std_bench.done && alt_bench.done);
    do_verdict();
  end

  initial begin
    repeat (TimeoutClks) @(posedge std_bench.clk);
    $fatal(1, "TB TIMEOUT: %0d and %0d of %0d frames in", std_bench.frame, alt_bench.frame,
           NumFrames);
  end

  initial begin
    if ($value$plusargs("max_errors=%d", max_errors) && max_errors > 0) begin
      wait (std_bench.errors + alt_bench.errors >= max_errors);
      $fatal(1, "TB STOPPED: %0d mismatches", std_bench.errors + alt_bench.errors);
    end
  end

endmodule

module rmii_rx_bench #(
    parameter int MIN_FRAME_BYTES = 64,
    parameter int MAX_FRAME_BYTES = 1518,
    parameter int MAX_TAGGED_FRAME_BYTES = 1522,
    parameter int NUM_FRAMES = 1,
    parameter int NUM_PINS = 1,
    parameter int NUM_OUT = 1,
    parameter string EXPECT_FILE = "tb/rmii_rx_expect.hex"
) ();

  int checks = 0;
  int errors = 0;

  localparam int QuietClks = 40;

  logic clk = 0;
  logic rst_n;
  logic tick;
  logic phy_crs_dv;
  logic [1:0] phy_rxd;
  logic [7:0] rx_data;
  logic rx_valid;
  logic rx_last;
  logic rx_bad;

  logic [47:0] frame_mem[NUM_FRAMES];
  logic [2:0] pin_mem[NUM_PINS];
  logic [9:0] expect_mem[NUM_OUT];

  int div = 1;
  int tick_cnt = 0;
  int frame = 0;
  int pin = 0;
  int mon_out = 0;
  logic aborting = 1'b0;
  logic done = 1'b0;

  always #5 clk = ~clk;

  assign tick = (tick_cnt == div - 1);

  rmii_rx #(
      .MIN_FRAME_BYTES(MIN_FRAME_BYTES),
      .MAX_FRAME_BYTES(MAX_FRAME_BYTES),
      .MAX_TAGGED_FRAME_BYTES(MAX_TAGGED_FRAME_BYTES)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .tick(tick),
      .phy_crs_dv(phy_crs_dv),
      .phy_rxd(phy_rxd),
      .rx_data(rx_data),
      .rx_valid(rx_valid),
      .rx_last(rx_last),
      .rx_bad(rx_bad)
  );

  task automatic do_reset();
    rst_n = 1'b0;
    phy_crs_dv = 1'b0;
    phy_rxd = '0;
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

  task automatic drive_frame(input int f);
    int num_pins = int'(frame_mem[f][31:16]);
    int rst_at = int'(frame_mem[f][15:0]);
    div = int'(frame_mem[f][47:40]);
    aborting = (rst_at != 0);
    repeat (int'(frame_mem[f][39:32])) @(posedge clk);
    for (int i = 0; i < num_pins; i++) begin
      if (rst_at != 0 && i == rst_at) begin
        do_reset();
        repeat (QuietClks) begin
          @(posedge clk);
          check("reset quiet", 32'(rx_valid), 32'd0);
        end
        pin += num_pins;
        return;
      end
      #1 phy_crs_dv = pin_mem[pin+i][2];
      phy_rxd = pin_mem[pin+i][1:0];
      repeat (div) @(posedge clk);
    end
    pin += num_pins;
  endtask  // Automatic

  initial begin
    $readmemh("tb/rmii_rx_frames.hex", frame_mem);
    $readmemh("tb/rmii_rx_pins.hex", pin_mem);
    $readmemh(EXPECT_FILE, expect_mem);
    do_reset();

    for (frame = 0; frame < NUM_FRAMES; frame++) begin
      drive_frame(frame);
      aborting = 1'b0;
    end

    repeat (QuietClks) @(posedge clk);
    check("outputs", 32'(mon_out), 32'(NUM_OUT));
    done = 1'b1;
  end

  always @(posedge clk) begin
    tick_cnt <= (tick_cnt >= div - 1) ? 0 : tick_cnt + 1;
  end

  always @(posedge clk) begin
    if (rx_valid && !aborting) begin
      check("byte", 32'({rx_bad, rx_last, rx_data}), 32'(expect_mem[mon_out]));
      mon_out <= mon_out + 1;
    end
  end

endmodule
