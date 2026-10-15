`default_nettype none

module frame_fifo #(
    parameter int WIDTH = 8,
    parameter int DEPTH = 2048,
    localparam int AW = $clog2(DEPTH)
) (
    // Write
    input  logic             wr_clk,
    input  logic             wr_rst_n,
    input  logic             wr_en,
    input  logic [WIDTH-1:0] wr_data,
    input  logic             wr_last,
    input  logic             wr_bad,
    output logic             full,

    // Read
    input  logic             rd_clk,
    input  logic             rd_rst_n,
    input  logic             rd_en,
    output logic [WIDTH-1:0] rd_data,
    output logic             rd_last,
    output logic             empty
);

  logic [AW:0] wr_ptr;
  logic [AW:0] wr_ptr_next;
  logic [AW:0] wr_gray;
  logic [AW:0] frame_bytes;
  logic        dropping;
  logic        accept;
  logic        rewind;
  logic        commit;
  logic [AW:0] wr_frames;
  logic [AW:0] wr_frames_gray;
  logic [AW:0] rd_gray_sync;

  logic [AW:0] rd_ptr;
  logic [AW:0] rd_ptr_next;
  logic [AW:0] rd_gray;
  logic        do_read;
  logic        read_out;
  logic [AW:0] rd_frames;
  logic [AW:0] rd_frames_now;
  logic [AW:0] wr_frames_sync;
  logic [AW:0] wr_frames_rd;

  function automatic logic [AW:0] bin2gray(input logic [AW:0] b);
    bin2gray = b ^ (b >> 1);
  endfunction

  function automatic logic [AW:0] gray2bin(input logic [AW:0] g);
    for (int i = 0; i <= AW; i++) gray2bin[i] = ^(g >> i);
  endfunction

  // Write side
  assign accept = wr_en && !full && !dropping;
  assign rewind = wr_en && !dropping && (full || (wr_last && wr_bad));
  assign commit = accept && wr_last && !wr_bad;
  assign full   = (wr_gray == {~rd_gray_sync[AW:AW-1], rd_gray_sync[AW-2:0]});

  always_comb begin
    wr_ptr_next = wr_ptr;
    if (rewind) begin
      wr_ptr_next = wr_ptr - frame_bytes;
    end else if (accept) begin
      wr_ptr_next = wr_ptr + 1'b1;
    end
  end

  always_ff @(posedge wr_clk) begin
    if (!wr_rst_n) begin
      wr_ptr <= '0;
      wr_gray <= '0;
      frame_bytes <= '0;
      dropping <= 1'b0;
      wr_frames <= '0;
      wr_frames_gray <= '0;
    end else begin
      wr_ptr  <= wr_ptr_next;
      wr_gray <= bin2gray(wr_ptr_next);
      if (rewind || commit) begin
        frame_bytes <= '0;
      end else if (accept) begin
        frame_bytes <= frame_bytes + 1'b1;
      end
      if (wr_en && wr_last) begin
        dropping <= 1'b0;
      end else if (rewind) begin
        dropping <= 1'b1;
      end
      if (commit) begin
        wr_frames <= wr_frames + 1'b1;
        wr_frames_gray <= bin2gray(wr_frames + 1'b1);
      end
    end
  end

  // rd_gray into write domain
  synchronizer #(
      .WIDTH(AW + 1)
  ) u_rd_gray_sync (
      .clk(wr_clk),
      .rst_n(wr_rst_n),
      .d(rd_gray),
      .q(rd_gray_sync)
  );

  // wr_frames_gray into read domain
  synchronizer #(
      .WIDTH(AW + 1)
  ) u_frames_sync (
      .clk(rd_clk),
      .rst_n(rd_rst_n),
      .d(wr_frames_gray),
      .q(wr_frames_sync)
  );

  // Read side
  assign wr_frames_rd = gray2bin(wr_frames_sync);
  assign rd_frames_now = rd_frames + (read_out && rd_last);
  assign empty = (wr_frames_rd == rd_frames_now);
  assign do_read = rd_en && !empty;
  assign rd_ptr_next = rd_ptr + do_read;

  always_ff @(posedge rd_clk) begin
    if (!rd_rst_n) begin
      rd_ptr <= '0;
      rd_gray <= '0;
      rd_frames <= '0;
      read_out <= 1'b0;
    end else begin
      rd_ptr <= rd_ptr_next;
      rd_gray <= bin2gray(rd_ptr_next);
      rd_frames <= rd_frames_now;
      read_out <= do_read;
    end
  end

  fifomem #(
      .WIDTH(WIDTH + 1),
      .DEPTH(DEPTH)
  ) u_mem (
      .wr_clk(wr_clk),
      .wr_en(accept),
      .full(full),
      .wr_addr(wr_ptr[AW-1:0]),
      .wr_data({wr_last, wr_data}),
      .rd_clk(rd_clk),
      .rd_en(rd_en),
      .empty(empty),
      .rd_addr(rd_ptr[AW-1:0]),
      .rd_data({rd_last, rd_data})
  );

endmodule

`default_nettype wire
