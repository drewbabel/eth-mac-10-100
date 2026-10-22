`default_nettype none

module eth_mac_regs_tb ();

  localparam int NumOps = 20000;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic hclk = 0;
  logic hrst_n;
  logic wen;
  logic ren;
  logic [31:0] addr;
  logic [31:0] wdata;
  logic [3:0] strobe;
  logic [31:0] rdata;
  logic error;
  logic request_stall;
  logic speed_100;
  logic loopback;

  logic [1:0] model;

  always #5 hclk = ~hclk;

  eth_mac_regs dut (
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
      .speed_100(speed_100),
      .loopback(loopback)
  );

  task automatic check(input string name, input logic [31:0] got, input logic [31:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $error("t=%0t %s mismatch: got=%h, exp=%h", $time, name, got, exp);
    end
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < NumOps) begin
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, NumOps);
    end else if (errors == 0) begin
      $display("PASS: %0d checks, %0d mismatches", checks, errors);
    end else begin
      $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    end
    $finish;
  endtask  // Automatic

  task automatic do_reset();
    hrst_n = 1'b0;
    wen = 1'b0;
    ren = 1'b0;
    addr = '0;
    wdata = '0;
    strobe = '0;
    model = '0;
    repeat (3) @(posedge hclk);
    #1 hrst_n = 1'b1;
  endtask  // Automatic

  task automatic bus_op();
    logic is_write = 1'($urandom);
    logic is_read = !is_write && (2'($urandom) != 2'b00);
    #1 wen = is_write;
    ren = is_read;
    addr = (2'($urandom) == 2'b00) ? 32'($urandom) & 32'hFC : '0;
    wdata = $urandom;
    strobe = 4'($urandom);
    #1;
    check("rdata", rdata, (ren && addr == '0) ? 32'(model) : 32'(0));
    check("error", 32'(error), 32'(0));
    check("stall", 32'(request_stall), 32'(0));
    @(posedge hclk);
    if (wen && addr == '0 && strobe[0]) model = wdata[1:0];
    #1;
    check("speed_100", 32'(speed_100), 32'(model[0]));
    check("loopback", 32'(loopback), 32'(model[1]));
  endtask  // Automatic

  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, eth_mac_regs_tb);
    do_reset();
    check("reset", 32'({loopback, speed_100}), 32'(0));
    for (int i = 0; i < NumOps; i++) begin
      bus_op();
      if (12'($urandom) == 12'd0) do_reset();
    end
    do_verdict();
  end

  initial begin
    if ($value$plusargs("max_errors=%d", max_errors) && max_errors > 0) begin
      wait (errors >= max_errors);
      $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  end

endmodule

`default_nettype wire
