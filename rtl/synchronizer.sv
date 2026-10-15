`default_nettype none

module synchronizer #(
    parameter int WIDTH = 1
) (
`ifdef FORMAL
    output logic [WIDTH-1:0] mid,  // Stage-1 flop
`endif
    input logic clk,
    input logic rst_n,
    input logic [WIDTH-1:0] d,
    output logic [WIDTH-1:0] q
);

  logic [WIDTH-1:0] ff;
`ifdef FORMAL
  assign mid = ff;
  initial begin
    assume (ff == '0);
    assume (q == '0);
  end
`endif

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      ff <= '0;
      q  <= '0;
    end else begin
      ff <= d;
      q  <= ff;
    end
  end

endmodule

`default_nettype wire
