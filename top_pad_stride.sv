module top_pad_stride #(
    parameter int DATA_W    = 8,
    parameter int STAGES    = 7,
    parameter int IDX_W     = $clog2(STAGES),
    parameter int MAX_IMG_W = 640
) (
    input  logic                clk,
    input  logic                rstn,

    input  logic                s_axis_tvalid,
    input  logic [DATA_W-1:0]   s_axis_tdata,
    input  logic                s_axis_tlast,
    output logic                s_axis_tready,

    input  logic [7:0]          padding_reg,
    input  logic [3:0]          height,
    input  logic [3:0]          width,
    input  logic [DATA_W-1:0]   pad_fill_val,
    input  logic [2:0]          kernel_len,
    input  logic [2:0]          stride
);

    logic [2:0] pad = padding_reg[2:0];
    logic [$clog2(MAX_IMG_W)-1:0] out_cols;
    assign out_cols = {1'b0, width} + {2'b0, pad} + {2'b0, pad};

    logic               mid_tvalid;
    logic [DATA_W-1:0]  mid_tdata;
    logic               mid_tlast;
    logic               mid_tready;

    logic               win0_valid;
    logic [STAGES*DATA_W-1:0]  win0_data;
    logic               win0_last;

    logic               win1_valid;
    logic [STAGES*DATA_W-1:0]  win1_data;
    logic               win1_last;

    logic               win2_valid;
    logic [STAGES*DATA_W-1:0]  win2_data;
    logic               win2_last;

    logic               lb1_valid;
    logic [DATA_W-1:0]  lb1_data;
    logic               lb1_last;

    logic               lb2_valid;
    logic [DATA_W-1:0]  lb2_data;
    logic               lb2_last;

    assign mid_tready = 1'b1;

    axis_stream_pad_rf u_pad (
        .clk(clk), .rstn(rstn),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tready(s_axis_tready),
        .m_axis_tvalid(mid_tvalid),
        .m_axis_tdata(mid_tdata),
        .m_axis_tlast(mid_tlast),
        .m_axis_tready(mid_tready),
        .padding_reg(padding_reg),
        .height(height),
        .width(width),
        .pad_fill_val(pad_fill_val)
    );

    line_buffer_delay #(
        .DATA_W(DATA_W),
        .MAX_DEPTH(MAX_IMG_W)
    ) u_lb1 (
        .clk(clk), .rstn(rstn),
        .in_valid(mid_tvalid),
        .in_data(mid_tdata),
        .in_last(mid_tlast),
        .img_width(out_cols),
        .out_valid(lb1_valid),
        .out_data(lb1_data),
        .out_last(lb1_last)
    );

    line_buffer_delay #(
        .DATA_W(DATA_W),
        .MAX_DEPTH(MAX_IMG_W)
    ) u_lb2 (
        .clk(clk), .rstn(rstn),
        .in_valid(lb1_valid),
        .in_data(lb1_data),
        .in_last(lb1_last),
        .img_width(out_cols),
        .out_valid(lb2_valid),
        .out_data(lb2_data),
        .out_last(lb2_last)
    );

    shift_reg_stride #(.DATA_W(DATA_W), .STAGES(STAGES)) u_sr0 (
        .clk(clk), .rstn(rstn),
        .s_axis_tvalid(mid_tvalid),
        .s_axis_tdata(mid_tdata),
        .s_axis_tlast(mid_tlast),
        .s_axis_tready(),
        .padding_reg(padding_reg),
        .height(height),
        .width(width),
        .pad_fill_val(pad_fill_val),
        .kernel_len(kernel_len),
        .stride(stride),
        .out_valid(win0_valid),
        .window_out(win0_data),
        .out_last(win0_last)
    );

    shift_reg_stride #(.DATA_W(DATA_W), .STAGES(STAGES)) u_sr1 (
        .clk(clk), .rstn(rstn),
        .s_axis_tvalid(lb1_valid),
        .s_axis_tdata(lb1_data),
        .s_axis_tlast(lb1_last),
        .s_axis_tready(),
        .padding_reg(padding_reg),
        .height(height),
        .width(width),
        .pad_fill_val(pad_fill_val),
        .kernel_len(kernel_len),
        .stride(stride),
        .out_valid(win1_valid),
        .window_out(win1_data),
        .out_last(win1_last)
    );

    shift_reg_stride #(.DATA_W(DATA_W), .STAGES(STAGES)) u_sr2 (
        .clk(clk), .rstn(rstn),
        .s_axis_tvalid(lb2_valid),
        .s_axis_tdata(lb2_data),
        .s_axis_tlast(lb2_last),
        .s_axis_tready(),
        .padding_reg(padding_reg),
        .height(height),
        .width(width),
        .pad_fill_val(pad_fill_val),
        .kernel_len(kernel_len),
        .stride(stride),
        .out_valid(win2_valid),
        .window_out(win2_data),
        .out_last(win2_last)
    );


endmodule
