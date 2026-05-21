`timescale 1ns / 1ps

module tb_top_pad_stride;
    parameter int DATA_W = 8;
    parameter int STAGES = 7;

    logic                     clk;
    logic                     rstn;
    logic                     s_axis_tvalid;
    logic [DATA_W-1:0]        s_axis_tdata;
    logic                     s_axis_tlast;
    logic                     s_axis_tready;
    logic [7:0]               padding_reg;
    logic [3:0]               height;
    logic [3:0]               width;
    logic [DATA_W-1:0]        pad_fill_val;
    logic [2:0]               kernel_len;
    logic [2:0]               stride;
    logic                     m_axis_tvalid;
    logic [DATA_W-1:0]        m_axis_tdata;
    logic [1:0]               m_axis_tid;
    logic                     m_axis_tlast;
    logic                     m_axis_tready;

    top_pad_stride #(
        .DATA_W(DATA_W),
        .STAGES(STAGES)
    ) dut (
        .clk(clk),
        .rstn(rstn),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tready(s_axis_tready),
        .padding_reg(padding_reg),
        .height(height),
        .width(width),
        .pad_fill_val(pad_fill_val),
        .kernel_len(kernel_len),
        .stride(stride),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tid(m_axis_tid),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tready(m_axis_tready)
    );

    int out_count = 0;
    int last_count = 0;
    int errors = 0;

    // 2x2 image with 1-pixel padding; padded output becomes 4x4
    logic [DATA_W-1:0] image_data [0:3];

    initial begin
        image_data[0] = 8'h11;
        image_data[1] = 8'h22;
        image_data[2] = 8'h33;
        image_data[3] = 8'h44;
    end

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("tb_top_pad_stride.vcd");
        $dumpvars(0, tb_top_pad_stride);
    end

    task automatic send_input(input logic [DATA_W-1:0] data, input logic last_flag);
        begin
            @(posedge clk);
            s_axis_tvalid = 1'b1;
            s_axis_tdata  = data;
            s_axis_tlast  = last_flag;
            while (!s_axis_tready) @(posedge clk);
            @(posedge clk);
            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;
            s_axis_tdata  = '0;
        end
    endtask

    function automatic string fmt_byte(input logic [DATA_W-1:0] data);
        return $sformatf("%02h", data);
    endfunction

    always_ff @(posedge clk) begin
        if (m_axis_tvalid) begin
            out_count <= out_count + 1;
            if (m_axis_tlast) last_count <= last_count + 1;
            $display("[TB] m_axis @%0t valid tid=%0d last=%0d data=%s",
                     $time, m_axis_tid, m_axis_tlast, fmt_byte(m_axis_tdata));
        end
    end

    initial begin
        rstn = 1'b0;
        s_axis_tvalid = 1'b0;
        s_axis_tdata  = '0;
        s_axis_tlast  = 1'b0;
        padding_reg   = 8'd1;
        height        = 4'd2;
        width         = 4'd2;
        pad_fill_val  = 8'hAA;
        kernel_len    = 3'd3;
        stride        = 3'd1;
        m_axis_tready = 1'b1;

        @(posedge clk);
        @(posedge clk);
        rstn = 1'b1;

        @(posedge clk);
        $display("[TB] Starting top_pad_stride_2d stimulus...");

        send_input(image_data[0], 1'b0);
        send_input(image_data[1], 1'b0);
        send_input(image_data[2], 1'b0);
        send_input(image_data[3], 1'b1);

        // allow pipeline to drain through the pad + line buffers + serializer
        repeat (50) @(posedge clk);

        $display("[TB] m_axis count = %0d", out_count);
        $display("[TB] m_axis last count = %0d", last_count);

        if (out_count == 0) begin
            $error("Expected at least one m_axis output, got 0");
            errors = errors + 1;
        end
        if (last_count == 0) begin
            $error("Expected at least one m_axis last pulse, got 0");
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("[TB] PASS: top_pad_stride_2d produced a valid serialized stream.");
        end else begin
            $display("[TB] FAIL: %0d simulation errors detected.", errors);
        end

        $finish;
    end
endmodule
