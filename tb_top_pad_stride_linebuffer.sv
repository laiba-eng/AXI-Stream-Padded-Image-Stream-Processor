`timescale 1ns / 1ps

module tb_top_pad_stride_linebuffer;
    parameter int DATA_W = 8;
    parameter int STAGES = 7;
    parameter int CLK_PER = 10;

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
        .stride(stride)
    );

    logic [DATA_W-1:0] row0 [0:2];
    logic [DATA_W-1:0] row1 [0:2];
    logic [DATA_W-1:0] row2 [0:2];

    initial begin
        row0[0] = 8'h11; row0[1] = 8'h12; row0[2] = 8'h13;
        row1[0] = 8'h21; row1[1] = 8'h22; row1[2] = 8'h23;
        row2[0] = 8'h31; row2[1] = 8'h32; row2[2] = 8'h33;
    end

    initial clk = 1'b0;
    always #(CLK_PER/2) clk = ~clk;

    initial begin
        $dumpfile("tb_top_pad_stride_linebuffer.vcd");
        $dumpvars(0, tb_top_pad_stride_linebuffer);
    end

    task automatic reset_dut;
        begin
            rstn          = 1'b0;
            s_axis_tvalid = 1'b0;
            s_axis_tdata  = '0;
            s_axis_tlast  = 1'b0;
            padding_reg   = 8'd0;
            height        = 4'd3;
            width         = 4'd3;
            pad_fill_val  = 8'h00;
            kernel_len    = 3'd3;
            stride        = 3'd1;
            repeat (4) @(posedge clk);
            rstn = 1'b1;
            @(posedge clk);
        end
    endtask

    task automatic send_pixel(input logic [DATA_W-1:0] data, input logic last_flag);
        begin
            @(posedge clk);
            s_axis_tdata  = data;
            s_axis_tlast  = last_flag;
            s_axis_tvalid = 1'b1;
            wait (s_axis_tready == 1'b1);
            @(posedge clk);
            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;
            s_axis_tdata  = '0;
        end
    endtask

    function automatic string fmt_byte(input logic [DATA_W-1:0] data);
        return $sformatf("%02h", data);
    endfunction

    integer errors;

    always_ff @(posedge clk) begin
        if (rstn && dut.lb1_valid) begin
            $display("[TB] LB1 out @%0t data=%s last=%0d", $time, fmt_byte(dut.lb1_data), dut.lb1_last);
            if (dut.u_sr1.s_axis_tdata !== dut.lb1_data) begin
                $error("LB1->SR1 connection mismatch at time %0t: sr1=%s lb1=%s", $time, fmt_byte(dut.u_sr1.s_axis_tdata), fmt_byte(dut.lb1_data));
                errors = errors + 1;
            end
        end
        if (rstn && dut.lb2_valid) begin
            $display("[TB] LB2 out @%0t data=%s last=%0d", $time, fmt_byte(dut.lb2_data), dut.lb2_last);
            if (dut.u_sr2.s_axis_tdata !== dut.lb2_data) begin
                $error("LB2->SR2 connection mismatch at time %0t: sr2=%s lb2=%s", $time, fmt_byte(dut.u_sr2.s_axis_tdata), fmt_byte(dut.lb2_data));
                errors = errors + 1;
            end
        end
    end

    initial begin
        errors = 0;
        reset_dut();
        $display("[TB] Starting line-buffer connectivity test");

        send_pixel(row0[0], 1'b0);
        send_pixel(row0[1], 1'b0);
        send_pixel(row0[2], 1'b1);

        send_pixel(row1[0], 1'b0);
        send_pixel(row1[1], 1'b0);
        send_pixel(row1[2], 1'b1);

        send_pixel(row2[0], 1'b0);
        send_pixel(row2[1], 1'b0);
        send_pixel(row2[2], 1'b1);

        repeat (10) @(posedge clk);

        if (errors == 0) begin
            $display("[TB] PASS: line buffer outputs are connected into shift regs.");
        end else begin
            $display("[TB] FAIL: %0d connectivity errors detected", errors);
        end

        $finish;
    end
endmodule
