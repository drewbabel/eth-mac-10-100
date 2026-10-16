`default_nettype none

module frame_fifo_tb ();

  localparam int Width = 8;
  localparam int Depth = 16;
  localparam int NumFrames = 2000;
  localparam int MaxLen = 12;
  localparam int StallEvery = 600;
  localparam int StallClks = 120;
  localparam int SettleClks = 200;
  localparam int TimeoutClks = 2_000_000;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic wr_clk = 0;
  logic rd_clk = 0;
  logic wr_rst_n;
  logic rd_rst_n;
  logic wr_en;
  logic [Width-1:0] wr_data;
  logic wr_last;
  logic wr_bad;
  logic full;
  logic rd_en = 1'b0;
  logic [Width-1:0] rd_data;
  logic rd_last;
  logic empty;

  logic [Width-1:0] expect_data[$];
  logic expect_last[$];
  int full_hits = 0;
  int kept = 0;
  int bad_drops = 0;
  int full_drops = 0;
  int rd_clks = 0;
  logic read_out = 1'b0;
  logic [Width-1:0] exp_data;
  logic exp_last;
  logic stalled;

  always #5 wr_clk = ~wr_clk;
  always #7 rd_clk = ~rd_clk;

  frame_fifo #(
      .WIDTH(Width),
      .DEPTH(Depth)
  ) dut (
      .wr_clk(wr_clk),
      .wr_rst_n(wr_rst_n),
      .wr_en(wr_en),
      .wr_data(wr_data),
      .wr_last(wr_last),
      .wr_bad(wr_bad),
      .full(full),
      .rd_clk(rd_clk),
      .rd_rst_n(rd_rst_n),
      .rd_en(rd_en),
      .rd_data(rd_data),
      .rd_last(rd_last),
      .empty(empty)
  );

  task automatic do_reset();
    wr_rst_n = 1'b0;
    rd_rst_n = 1'b0;
    wr_en = 1'b0;
    wr_data = '0;
    wr_last = 1'b0;
    wr_bad = 1'b0;
    repeat (5) @(posedge wr_clk);
    repeat (5) @(posedge rd_clk);
    #1 wr_rst_n = 1'b1;
    rd_rst_n = 1'b1;
  endtask  // Automatic

  task automatic check(input string name, input logic [31:0] got, input logic [31:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $error("t=%0t %s mismatch: got=%h, exp=%h", $time, name, got, exp);
    end
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < NumFrames) begin
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, NumFrames);
    end else if (errors == 0) begin
      $display("PASS: %0d checks, %0d mismatches", checks, errors);
    end else begin
      $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    end
    $finish;
  endtask  // Automatic

  task automatic send_frame();
    int len = 1 + $urandom_range(MaxLen - 1);
    logic bad = 2'($urandom) == 2'b00;
    int hits0 = full_hits;
    logic [Width-1:0] bytes[$];
    for (int i = 0; i < len; i++) begin
      if (2'($urandom) == 2'b00) begin
        #1 wr_en = 1'b0;
        repeat (1 + int'(2'($urandom))) @(posedge wr_clk);
      end
      #1 wr_en = 1'b1;
      wr_data = Width'($urandom);
      wr_last = (i == len - 1);
      wr_bad  = bad && (i == len - 1);
      bytes.push_back(wr_data);
      @(posedge wr_clk);
    end
    #1 wr_en = 1'b0;
    wr_last = 1'b0;
    wr_bad  = 1'b0;
    if (bad) begin
      bad_drops++;
    end else if (full_hits != hits0) begin
      full_drops++;
    end else begin
      kept++;
      for (int i = 0; i < len; i++) begin
        expect_data.push_back(bytes[i]);
        expect_last.push_back(i == len - 1);
      end
    end
    repeat (int'(3'($urandom))) @(posedge wr_clk);
  endtask  // Automatic

  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, frame_fifo_tb);
    do_reset();

    for (int f = 0; f < NumFrames; f++) send_frame();

    while (expect_data.size() != 0) @(posedge rd_clk);
    repeat (SettleClks) @(posedge rd_clk);
    check("empty at end", 32'(empty), 32'(1));
    check("frames kept", 32'(kept > 0), 32'(1));
    check("bad frames seen", 32'(bad_drops > 0), 32'(1));
    check("full drops seen", 32'(full_drops > 0), 32'(1));
    do_verdict();
  end

  initial begin
    repeat (TimeoutClks) @(posedge wr_clk);
    $fatal(1, "TB TIMEOUT: %0d bytes still expected", expect_data.size());
  end

  initial begin
    if ($value$plusargs("max_errors=%d", max_errors) && max_errors > 0) begin
      wait (errors >= max_errors);
      $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  end

  always @(posedge wr_clk) begin
    if (wr_en && full) full_hits <= full_hits + 1;
  end

  assign stalled = (rd_clks % StallEvery) < StallClks;

  always @(posedge rd_clk) begin
    rd_clks <= rd_clks + 1;
    rd_en   <= !stalled && (2'($urandom) != 2'b00);
  end

  always @(posedge rd_clk) begin
    if (read_out) begin
      if (expect_data.size() == 0) begin
        check("byte past the last frame", 32'(1), 32'(0));
      end else begin
        exp_data = expect_data.pop_front();
        exp_last = expect_last.pop_front();
        check("byte", 32'({rd_last, rd_data}), 32'({exp_last, exp_data}));
      end
    end
    read_out <= rd_en && !empty;
  end

endmodule

`default_nettype wire
