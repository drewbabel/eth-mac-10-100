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

`ifdef FORMAL
  logic [AW:0] rd_gray_mid;
  logic [AW:0] frames_mid;
  logic [DEPTH-1:0][WIDTH:0] f_mem;
`endif

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
`ifdef FORMAL,
      .mid(rd_gray_mid)
`endif
  );

  // wr_frames_gray into read domain
  synchronizer #(
      .WIDTH(AW + 1)
  ) u_frames_sync (
      .clk(rd_clk),
      .rst_n(rd_rst_n),
      .d(wr_frames_gray),
      .q(wr_frames_sync)
`ifdef FORMAL,
      .mid(frames_mid)
`endif
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
`ifdef FORMAL,
      .mem_q(f_mem)
`endif
  );


`ifdef FORMAL
  logic [  AW:0] f_start;
  logic [  AW:0] f_rptr_wr;
  logic [  AW:0] o_rdmid;
  logic [  AW:0] o_rptr;
  logic [  AW:0] o_start;
  logic [  AW:0] o_wptr;
  logic [  AW:0] o_sync;
  logic [  AW:0] o_mid;
  logic [  AW:0] o_wrf;
  logic [  AW:0] f_fill;
  logic [  AW:0] f_used;
  logic [  AW:0] f_ends;
  logic [AW-1:0] f_idx;

  assign f_start = wr_ptr - frame_bytes;
  assign f_fill = wr_ptr - rd_ptr;
  assign f_used = f_start - rd_ptr;
  assign f_rptr_wr = gray2bin(rd_gray_sync);

  // Offsets from the oldest view
  assign o_rdmid = gray2bin(rd_gray_mid) - f_rptr_wr;
  assign o_rptr = rd_ptr - f_rptr_wr;
  assign o_start = f_start - f_rptr_wr;
  assign o_wptr = wr_ptr - f_rptr_wr;
  assign o_sync = wr_frames_rd - rd_frames_now;
  assign o_mid = gray2bin(frames_mid) - rd_frames_now;
  assign o_wrf = wr_frames - rd_frames_now;

  // Flops start at zero
  initial begin
    assume (wr_ptr == '0);
    assume (wr_gray == '0);
    assume (frame_bytes == '0);
    assume (!dropping);
    assume (wr_frames == '0);
    assume (wr_frames_gray == '0);
    assume (rd_ptr == '0);
    assume (rd_gray == '0);
    assume (rd_frames == '0);
    assume (!read_out);
  end

  always_comb begin
    assume (wr_rst_n);
    assume (rd_rst_n);

    // Gray copies
    assert (wr_gray == bin2gray(wr_ptr));
    assert (rd_gray == bin2gray(rd_ptr));
    assert (wr_frames_gray == bin2gray(wr_frames));

    // Ring order
    assert (o_rdmid <= o_rptr);
    assert (o_rptr <= o_start);
    assert (o_start <= o_wptr);
    assert (o_wptr <= DEPTH);
    assert (o_sync <= o_mid);
    assert (o_mid <= o_wrf);
    assert (o_wrf <= DEPTH);

    // Depth
    assert (f_fill <= DEPTH);
    if (f_fill == DEPTH) assert (full);

    // Frames
    assert ((rd_ptr == f_start) == (wr_frames == rd_frames_now));
    if (do_read) assert (rd_ptr != f_start);
    if (rewind) assert (wr_ptr_next == f_start);
    if (rewind || dropping) assert (!commit);
    if (read_out && !rd_last) assert (rd_ptr != f_start);

    // Last flags in memory
    f_ends = '0;
    for (int i = 0; i < DEPTH; i++) begin
      f_idx = AW'(i) - rd_ptr[AW-1:0];
      if (f_idx < f_used) f_ends = f_ends + f_mem[i][WIDTH];
      f_idx = AW'(i) - f_start[AW-1:0];
      if (f_idx < frame_bytes) assert (!f_mem[i][WIDTH]);
      if (f_used != 0 && AW'(i) == f_start[AW-1:0] - 1'b1) assert (f_mem[i][WIDTH]);
    end
    assert (f_ends == o_wrf);
  end

  always @(posedge wr_clk) begin
    cover (full);
    cover (rewind && full);
    cover (rewind && wr_bad);
    cover (commit);
  end

  always @(posedge rd_clk) begin
    cover (read_out && rd_last);
    cover (o_wrf == 2);
  end
`endif

endmodule

`default_nettype wire
