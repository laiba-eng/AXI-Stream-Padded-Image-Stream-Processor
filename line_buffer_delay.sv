`timescale 1ns / 1ps

module line_buffer_delay #(
    parameter int DATA_W     = 8,
    parameter int MAX_DEPTH  = 640
) (
    input  logic                   clk,
    input  logic                   rstn,

    input  logic                   in_valid,
    input  logic [DATA_W-1:0]      in_data,
    input  logic                   in_last,
    input  logic [$clog2(MAX_DEPTH)-1:0] img_width,  // padded row width

    output logic                   out_valid,
    output logic [DATA_W-1:0]      out_data,
    output logic                   out_last
);

    localparam int IMG_W_W = $clog2(MAX_DEPTH);

    logic [IMG_W_W-1:0] fill_count;
    logic [IMG_W_W-1:0] col_count;
    logic       rd_en;

    assign rd_en = in_valid && (fill_count >= img_width);

    always_ff @(posedge clk) begin
        if (!rstn)
            fill_count <= 5'd0;
        else if (in_valid && (fill_count < img_width))
            fill_count <= fill_count + 1'b1;
    end

    logic [DATA_W-1:0] rd_data_pre;

    bram_fifo_var #(
        .WIDTH(DATA_W),
        .MAX_DEPTH(MAX_DEPTH)
    ) u_linebuf (
        .clk(clk),
        .rstn(rstn),
        .img_width(img_width),
        .mode(1'b0),
        .wr_en(in_valid),
        .wr_data(in_data),
        .rd_en(rd_en),
        .rd_data(rd_data_pre),
        .full(),
        .empty(),
        .discarded()
    );

    always_ff @(posedge clk) begin
        if (!rstn) begin
            out_valid <= 1'b0;
            out_data  <= '0;
            out_last  <= 1'b0;
            col_count <= 5'd0;
        end else begin
            out_valid <= rd_en;
            out_data  <= rd_data_pre;

            if (rd_en) begin
                out_last <= (col_count == img_width - 1);
                col_count <= (col_count == img_width - 1)
                             ? 5'd0
                             : col_count + 1'b1;
            end else begin
                out_last <= 1'b0;
            end
        end
    end

endmodule
