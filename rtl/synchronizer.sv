module synchronizer #(
    parameter int WIDTH = 1
) (
    input  logic             clk,
    input  logic [WIDTH-1:0] d,
    output logic [WIDTH-1:0] q
);

  logic [WIDTH-1:0] ff;

  always_ff @(posedge clk) begin
    ff <= d;
    q  <= ff;
  end

endmodule
