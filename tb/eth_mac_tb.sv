`default_nettype none

module eth_mac_tb ();

  localparam int NumFrames = 36;
  localparam int NumBytes = 14348;
  localparam int NumOut = 11527;
  localparam int WireNumOut = 8076;
  localparam int TimeoutClks = 2_000_000;

  int checks;
  int errors;
  int max_errors;

  eth_mac_bench #(
      .LOOPBACK  (1'b1),
      .FIFO_DEPTH(2048),
      .NUM_FRAMES(NumFrames),
      .NUM_BYTES (NumBytes),
      .NUM_OUT   (NumOut),
      .EXPECT_FILE("tb/eth_mac_expect.hex")
  ) loop_bench ();

  eth_mac_bench #(
      .LOOPBACK  (1'b0),
      .FIFO_DEPTH(2048),
      .NUM_FRAMES(NumFrames),
      .NUM_BYTES (NumBytes),
      .NUM_OUT   (WireNumOut),
      .EXPECT_FILE("tb/eth_mac_expect_wire.hex")
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
    $dumpvars(0, eth_mac_tb);
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

module eth_mac_bench #(
    parameter logic LOOPBACK = 1'b1,
    parameter int FIFO_DEPTH = 2048,
    parameter int NUM_FRAMES = 1,
    parameter int NUM_BYTES = 1,
    parameter int NUM_OUT = 1,
    parameter string EXPECT_FILE = "tb/eth_mac_expect.hex"
) ();

  int checks = 0;
  int errors = 0;

  localparam int SettleClks = 400;
  localparam int LongPauseClks = 2000;

  logic clk = 0;
  logic hclk = 0;
  logic rst_n;
  logic hrst_n;
  logic speed_100;
  logic wen;
  logic ren;
  logic [31:0] addr;
  logic [31:0] wdata;
  logic [3:0] strobe;
  logic [31:0] rdata;
  logic error;
  logic request_stall;
  logic tx_valid;
  logic tx_ready;
  logic [7:0] tx_data;
  logic tx_last;
  logic rx_valid;
  logic rx_ready = 1'b0;
  logic [7:0] rx_data;
  logic rx_last;
  logic phy_tx_en;
  logic [1:0] phy_txd;
  logic phy_crs_dv;
  logic [1:0] phy_rxd;

  logic [7:0] data_mem[NUM_BYTES];
  logic [55:0] frame_mem[NUM_FRAMES];
  logic [8:0] expect_mem[NUM_OUT];
  int byte_offset[NUM_FRAMES];

  int div = 1;
  int taken = 0;
  int mon_out = 0;
  int pin_frame = 0;
  int pin_pair = 0;
  logic en_seen = 1'b0;
  logic flip_now;
  logic done = 1'b0;
  logic rx_more = 1'b0;
  logic tx_more = 1'b0;

  always #5 clk = ~clk;
  always #7 hclk = ~hclk;

  eth_mac #(
      .FIFO_DEPTH(FIFO_DEPTH)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .hclk(hclk),
      .hrst_n(hrst_n),
      .wen(wen),
      .ren(ren),
      .addr(addr),
      .wdata(wdata),
      .strobe(strobe),
      .rdata(rdata),
      .error(error),
      .request_stall(request_stall),
      .tx_valid(tx_valid),
      .tx_ready(tx_ready),
      .tx_data(tx_data),
      .tx_last(tx_last),
      .rx_valid(rx_valid),
      .rx_ready(rx_ready),
      .rx_data(rx_data),
      .rx_last(rx_last),
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
    hrst_n = 1'b0;
    speed_100 = 1'b1;
    wen = 1'b0;
    ren = 1'b0;
    addr = '0;
    wdata = '0;
    strobe = '0;
    tx_valid = 1'b0;
    tx_data = '0;
    tx_last = 1'b0;
    repeat (5) @(posedge clk);
    repeat (5) @(posedge hclk);
    #1 rst_n = 1'b1;
    hrst_n = 1'b1;
  endtask  // Automatic

  task automatic write_ctrl();
    @(posedge hclk);
    #1 wen = 1'b1;
    addr   = '0;
    wdata  = 32'({LOOPBACK, speed_100});
    strobe = 4'hF;
    @(posedge hclk);
    #1 wen = 1'b0;
    ren = 1'b1;
    #1 check("ctrl readback", rdata, 32'({LOOPBACK, speed_100}));
    check("no stall", 32'({error, request_stall}), 32'(0));
    @(posedge hclk);
    #1 ren = 1'b0;
    repeat (4) @(posedge clk);
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
    int frame_div = int'(frame_mem[f][55:48]);
    int len = int'(frame_mem[f][31:16]);
    if (frame_div != div) begin
      wait (pin_frame == f);
      repeat (SettleClks) @(posedge clk);
      div = frame_div;
      speed_100 = (div == 1);
      write_ctrl();
    end
    repeat (int'(frame_mem[f][47:32])) @(posedge hclk);
    for (int i = 0; i < len; i++) begin
      if (3'($urandom) == 3'd0) begin
        #1 tx_valid = 1'b0;
        repeat (1 + int'(6'($urandom))) @(posedge hclk);
      end
      if (8'($urandom) == 8'd0) begin
        #1 tx_valid = 1'b0;
        repeat (LongPauseClks) @(posedge hclk);
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
    $readmemh("tb/eth_mac_data.hex", data_mem);
    $readmemh("tb/eth_mac_frames.hex", frame_mem);
    $readmemh(EXPECT_FILE, expect_mem);
    byte_offset[0] = 0;
    for (int f = 1; f < NUM_FRAMES; f++) begin
      byte_offset[f] = byte_offset[f-1] + int'(frame_mem[f-1][31:16]);
    end
    do_reset();
    write_ctrl();

    for (int f = 0; f < NUM_FRAMES; f++) send_frame(f);

    wait (pin_frame == NUM_FRAMES);
    wait (mon_out == NUM_OUT);
    repeat (SettleClks) @(posedge clk);
    check("outputs", 32'(mon_out), 32'(NUM_OUT));
    done = 1'b1;
  end

  always @(posedge hclk) begin
    if (tx_valid && tx_ready) taken <= taken + 1;
    rx_ready <= 2'($urandom) != 2'b00;
  end

  always begin
    @(posedge clk);
    if (dut.u_line.tick) begin
      #1;
      if (phy_tx_en) pin_pair = en_seen ? pin_pair + 1 : 0;
      else if (en_seen) pin_frame++;
      en_seen = phy_tx_en;
    end
  end

  always @(posedge hclk) begin
    if (rx_more) check("rx back to back", 32'(rx_valid), 32'(1));
    rx_more <= rx_valid && rx_ready && !dut.rx_empty;
  end

  always @(posedge clk) begin
    if (tx_more) check("tx back to back", 32'(dut.line_tx_valid), 32'(1));
    tx_more <= dut.line_tx_valid && dut.line_tx_ready && !dut.tx_empty;
  end

  always @(posedge hclk) begin
    if (rx_valid && rx_ready) begin
      check("byte", 32'({rx_last, rx_data}), 32'(expect_mem[mon_out]));
      mon_out <= mon_out + 1;
    end
  end

endmodule

`default_nettype wire
