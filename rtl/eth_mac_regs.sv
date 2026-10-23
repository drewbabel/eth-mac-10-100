`default_nettype none

module eth_mac_regs #(
    parameter int ADDR_WIDTH = 32
) (
    input wire hclk,
    input wire hrst_n,

    input wire wen,
    input wire ren,
    input wire [ADDR_WIDTH-1:0] addr,
    input wire [31:0] wdata,
    input wire [3:0] strobe,
    output logic [31:0] rdata,
    output logic error,
    output logic request_stall,

    output logic speed_100,
    output logic loopback
);

  localparam logic [ADDR_WIDTH-1:0] CtrlAddr = '0;
  localparam int CtrlBits = 2;

  logic [CtrlBits-1:0] ctrl_q;
  logic ctrl_hit;

  assign ctrl_hit = (addr == CtrlAddr);

  always_ff @(posedge hclk) begin
    if (!hrst_n) begin
      ctrl_q <= '0;
    end else if (wen && ctrl_hit && strobe[0]) begin
      ctrl_q <= wdata[CtrlBits-1:0];
    end
  end

  assign speed_100 = ctrl_q[0];
  assign loopback = ctrl_q[1];

  assign rdata = (ren && ctrl_hit) ? 32'(ctrl_q) : '0;
  assign error = 1'b0;
  assign request_stall = 1'b0;

`ifdef FORMAL
  logic f_past_valid = 1'b0;
  logic [CtrlBits-1:0] f_ctrl;

  always_ff @(posedge hclk) f_past_valid <= 1'b1;

  // Reset pin
  initial assume (!hrst_n);

  // Bus contract model
  always_ff @(posedge hclk) begin
    if (!hrst_n) begin
      f_ctrl <= '0;
    end else if (wen && (addr == '0) && strobe[0]) begin
      f_ctrl <= wdata[CtrlBits-1:0];
    end
  end

  always_comb begin
    if (f_past_valid) begin
      assert ({loopback, speed_100} == f_ctrl);
      assert (rdata == ((ren && (addr == '0)) ? 32'(f_ctrl) : 32'b0));
    end
    assert (!error);
    assert (!request_stall);
  end

  always_ff @(posedge hclk) begin
    if (f_past_valid && hrst_n) begin
      cover (speed_100 && loopback);
      cover ($past(wen) && $past(addr) == '0 && !$past(strobe[0]) && $past(hrst_n) && speed_100);
      cover (ren && (addr == '0) && rdata == 32'd3);
    end
  end
`endif

endmodule

`default_nettype wire
