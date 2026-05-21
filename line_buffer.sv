`timescale 1ns / 1ps

module bram_fifo_var #(
    parameter WIDTH     = 8,
    parameter MAX_DEPTH = 640
)(
    input  wire                          clk,
    input  wire                          rstn,

    input  wire [$clog2(MAX_DEPTH)-1:0]  img_width,
    input  wire                          mode,      // 0=delay-line  1=FIFO

    input  wire                          wr_en,
    input  wire [WIDTH-1:0]              wr_data,

    input  wire                          rd_en,
    output reg  [WIDTH-1:0]              rd_data,

    output wire                          full,
    output wire                          empty,
    output wire                          discarded
);

    localparam ADDR_W = $clog2(MAX_DEPTH);
    localparam CNT_W  = ADDR_W + 1;

    (* ram_style = "block" *)
    reg [WIDTH-1:0] mem [0:MAX_DEPTH-1];

    reg [ADDR_W-1:0] wr_ptr     = {ADDR_W{1'b0}};
    reg [ADDR_W-1:0] rd_ptr     = {ADDR_W{1'b0}};
    reg [CNT_W-1:0]  count      = {CNT_W{1'b0}};

    // =========================================================
    //  filled_once ? sticky flag, set when buffer first reaches
    //  img_width entries, never cleared until reset.
    //  Used in delay-line mode so rd_en_eff stays valid even
    //  when wr and rd are issued on separate cycles (count dips
    //  below img_width momentarily during a pure-read cycle).
    // =========================================================
    reg filled_once = 1'b0;

    always @(posedge clk) begin
        if (!rstn)
            filled_once <= 1'b0;
        else if (count >= img_width)
            filled_once <= 1'b1;
    end

    initial rd_data = {WIDTH{1'b0}};

    // =========================================================
    //  Status flags
    // =========================================================
    wire buf_full  = (count >= img_width);
    assign full      = buf_full;
    assign empty     = (count == 0);
    assign discarded = wr_en & buf_full & mode;

    // =========================================================
    //  Effective enables
    //
    //  DELAY-LINE (mode=0):
    //    wr_en_eff : always write when wr_en=1 (no full gate)
    //    rd_en_eff : gated by filled_once (sticky) instead of
    //               buf_full (instantaneous). This means once
    //               the buffer has been filled, reads are always
    //               allowed regardless of whether a write has
    //               happened this cycle.
    //
    //  FIFO (mode=1):
    //    wr_en_eff : gated by ~full  (drop writes when full)
    //    rd_en_eff : gated by ~empty (drop reads when empty)
    // =========================================================
    wire wr_en_eff = mode ? (wr_en & ~buf_full) : wr_en;
    wire rd_en_eff = mode ? (rd_en & ~empty)
                          : (rd_en & filled_once);  // ? sticky, not buf_full

    // =========================================================
    //  Write logic
    // =========================================================
    always @(posedge clk) begin
        if (!rstn) begin
            wr_ptr <= {ADDR_W{1'b0}};
        end else if (wr_en_eff) begin
            mem[wr_ptr] <= wr_data;
            wr_ptr <= (wr_ptr == img_width - 1) ? {ADDR_W{1'b0}}
                                                 : wr_ptr + 1'b1;
        end
    end

    // =========================================================
    //  Read logic
    // =========================================================
    always @(posedge clk) begin
        if (!rstn) begin
            rd_ptr  <= {ADDR_W{1'b0}};
            rd_data <= {WIDTH{1'b0}};
        end else if (rd_en_eff) begin
            rd_data <= mem[rd_ptr];
            rd_ptr  <= (rd_ptr == img_width - 1) ? {ADDR_W{1'b0}}
                                                  : rd_ptr + 1'b1;
        end
    end

    // =========================================================
    //  Fill counter
    //
    //  DELAY-LINE (mode=0):
    //    count only increments during fill phase.
    //    Once filled_once is set, count is FROZEN ? reads and
    //    writes do not change it. This keeps buf_full stable
    //    and prevents rd_ptr / wr_ptr from going out of sync
    //    when rd and wr are issued on separate cycles.
    //
    //  FIFO (mode=1):
    //    Normal up/down counting.
    // =========================================================
    always @(posedge clk) begin
        if (!rstn) begin
            count <= {CNT_W{1'b0}};
        end else if (!mode) begin
            if (!filled_once && wr_en_eff)
                count <= count + 1'b1;
        end else begin
            case ({wr_en_eff, rd_en_eff})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule
