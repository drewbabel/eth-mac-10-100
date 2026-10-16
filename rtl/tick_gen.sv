`default_nettype none

module tick_gen #(
    parameter int DIVISOR = 4
) (
`ifdef FORMAL
    output logic [7:0] f_cnt,
`endif
    input  logic clk,
    input  logic rst_n,
    input  logic clr,
    output logic tick
);

  logic [$clog2(DIVISOR-1):0] cnt;

  always_ff @(posedge clk) begin
    if (!rst_n) cnt <= '0;
    else if (clr) cnt <= '0;
    else cnt <= (cnt == $bits(cnt)'(DIVISOR - 1)) ? '0 : cnt + 1'b1;
  end

`ifdef FORMAL
  assign f_cnt = 8'(cnt);
`endif

  assign tick = (cnt == $bits(cnt)'(DIVISOR - 1));

endmodule

`default_nettype wire
