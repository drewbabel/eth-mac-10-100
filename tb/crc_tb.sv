module crc_tb ();

  int checks = 0;
  int errors = 0;

  localparam int Width = 32;
  localparam int DinW = 2;
  localparam int NumFrames = 33;
  localparam int NumBytes = 21338;
  localparam logic [Width-1:0] Residue = 32'hC704_DD7B;

  logic clk = 0;
  logic rst_n;
  logic init;
  logic en;
  logic [DinW-1:0] din;
  logic [Width-1:0] crc_out;

  logic [7:0] data_mem[NumBytes];
  logic [47:0] expect_mem[NumFrames];
  int offset[NumFrames];

  always #5 clk = ~clk;

  crc #(
      .WIDTH(Width),
      .DIN_W(DinW)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .init(init),
      .en(en),
      .din(din),
      .crc_out(crc_out)
  );

  task automatic do_reset();
    rst_n = 1'b0;
    init = 1'b0;
    en = 1'b0;
    din = '0;
    repeat (5) @(posedge clk);
    #1 rst_n = 1'b1;
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

  task automatic check(input string name, input logic [Width-1:0] got, input logic [Width-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $error("t=%0t %s mismatch: got=%h, exp=%h", $time, name, got, exp);
    end
  endtask  // Automatic

  task automatic send_byte(input logic [7:0] b);
    for (int k = 0; k < 4; k++) begin
      en  = 1'b0;
      din = DinW'($urandom);
      repeat ($urandom_range(9, 0)) @(posedge clk);
      #1 en = 1'b1;
      din = b[2*k+:2];
      @(posedge clk);
      #1;
    end
    en = 1'b0;
  endtask  // Automatic

  task automatic run_frame(input int f);
    logic [Width-1:0] fcs;
    init = 1'b1;
    en   = 1'b1;
    din  = DinW'($urandom);
    @(posedge clk);
    #1 init = 1'b0;
    for (int i = 0; i < int'(expect_mem[f][47:32]); i++) send_byte(data_mem[offset[f]+i]);
    check($sformatf("frame %0d", f), crc_out, expect_mem[f][Width-1:0]);

    fcs = ~crc_out;
    for (int k = 0; k < Width / 2; k++) begin
      en  = 1'b1;
      din = {fcs[Width-2-2*k], fcs[Width-1-2*k]};
      @(posedge clk);
      #1;
    end
    en = 1'b0;
    check("residue", crc_out, Residue);
  endtask  // Automatic

  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, crc_tb);
    $readmemh("tb/crc_data.hex", data_mem);
    $readmemh("tb/crc_expect.hex", expect_mem);
    offset[0] = 0;
    for (int f = 1; f < NumFrames; f++) offset[f] = offset[f-1] + int'(expect_mem[f-1][47:32]);
    do_reset();
    check("reset", crc_out, '0);

    for (int f = 0; f < NumFrames; f++) run_frame(f);

    rst_n = 1'b0;
    init  = 1'b1;
    en    = 1'b1;
    @(posedge clk);
    #1 rst_n = 1'b1;
    init = 1'b0;
    en   = 1'b0;
    check("reset over init", crc_out, '0);

    do_verdict();
  end

endmodule
