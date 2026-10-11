module crc #(
    parameter int WIDTH = 32,
    parameter int DIN_W = 2,
    parameter logic [WIDTH-1:0] POLY = 32'h04C1_1DB7,
    parameter logic [WIDTH-1:0] INIT = '1
) (
    input wire clk,
    input wire rst_n,
    input wire init,
    input wire en,
    input wire [DIN_W-1:0] din,
    output logic [WIDTH-1:0] crc_out
);

  logic [WIDTH-1:0] crc_next;
  logic apply_poly;

  always_comb begin
    crc_next = crc_out;
    for (int i = 0; i < DIN_W; i++) begin
      apply_poly = crc_next[WIDTH-1] ^ din[i];
      crc_next = (crc_next << 1) ^ (apply_poly ? POLY : '0);
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) crc_out <= '0;
    else if (init) crc_out <= INIT;
    else if (en) crc_out <= crc_next;
  end

endmodule
