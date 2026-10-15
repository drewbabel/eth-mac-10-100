`default_nettype none

module synchronizer_tb ();

  int errors = 0;
  int max_errors = 0;
  int checks = 0;

  localparam int Width = 4;

  logic clk = 0;
  logic rst_n;
  logic [Width-1:0] d;
  logic [Width-1:0] q;

  always #5 clk = ~clk;

  synchronizer #(
      .WIDTH(Width)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .d(d),
      .q(q)
  );

  logic [Width-1:0] d1;
  logic [Width-1:0] d2;

  task automatic check(input string name, input logic [Width-1:0] got, input logic [Width-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $error("t=%0t %s mismatch: got=%b  exp=%b", $time, name, got, exp);
    end
  endtask  // Automatic

  initial begin
    if ($value$plusargs("max_errors=%d", max_errors) && max_errors > 0) begin
      wait (errors >= max_errors);
      $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  end

  task automatic verdict();
    if (errors == 0) begin
      $display("PASS: %0d checks, %0d mismatches", checks, errors);
    end else begin
      $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    end
    $finish;
  endtask  // Automatic

  // Stimulus
  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, synchronizer_tb);

    rst_n = 1'b0;
    d = '1;
    @(posedge clk);
    @(posedge clk);
    #1 rst_n = 1'b1;

    repeat (100) begin
      #1 d = (Width)'($urandom);
      @(posedge clk);
    end

    @(posedge clk);

    verdict();
  end

  // Reference model
  always @(posedge clk) begin
    if (!rst_n) begin
      d1 <= '0;
      d2 <= '0;
    end else begin
      d1 <= d;
      d2 <= d1;
    end
  end

  // Comparison to DUT
  always @(negedge clk) begin
    check("ff2", q, d2);
  end

endmodule

`default_nettype wire
