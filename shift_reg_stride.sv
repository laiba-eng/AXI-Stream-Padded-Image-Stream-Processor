`timescale 1ns / 1ps

module shift_reg_stride #(
    parameter int DATA_W = 8,
    parameter int STAGES = 7
) (
    input  logic                     clk,
    input  logic                     rstn,
    input  logic                     s_axis_tvalid,
    input  logic [DATA_W-1:0]        s_axis_tdata,
    input  logic                     s_axis_tlast,
    output logic                     s_axis_tready,
    input  logic [7:0]               padding_reg,
    input  logic [3:0]               height,
    input  logic [3:0]               width,
    input  logic [DATA_W-1:0]        pad_fill_val,
    input  logic [2:0]               kernel_len,
    input  logic [2:0]               stride,
    output logic                     out_valid,
    output logic [STAGES*DATA_W-1:0] window_out,
    output logic                     out_last
);

logic [DATA_W-1:0] stages        [0:STAGES-1];
logic [DATA_W-1:0] stages_n      [0:STAGES-1];
logic [DATA_W-1:0] pending_buf   [0:STAGES-1];
logic [DATA_W-1:0] pending_buf_n [0:STAGES-1];

logic [STAGES*DATA_W-1:0] window_out_n;
logic [2:0]               stride_q, stride_q_n;
logic [3:0]               fill_count, fill_count_n;
logic [3:0]               pending_count, pending_count_n;
logic                     out_valid_n, out_last_n;

// shift-reg only version: always ready, direct input path
assign s_axis_tready = 1'b1;

// unused in this stripped version
wire _unused_ok = &{1'b0, padding_reg[0], height[0], width[0], pad_fill_val[0]};

always_comb begin
    integer i;
    integer j;
    integer idx;
    integer collected;
    integer fill_after;

    for (i = 0; i < STAGES; i = i + 1) begin
        stages_n[i]      = stages[i];
        pending_buf_n[i] = pending_buf[i];
    end

    stride_q_n      = stride_q;
    fill_count_n    = fill_count;
    pending_count_n = pending_count;
    out_valid_n     = 1'b0;
    out_last_n      = 1'b0;

    if (stride != stride_q) begin
        stride_q_n      = stride;
        pending_count_n = 4'd0;
        for (i = 0; i < STAGES; i = i + 1)
            pending_buf_n[i] = '0;
    end

    if (s_axis_tvalid) begin
        if (stride != 3'd0) begin
            idx = (stride != stride_q) ? 0 : pending_count;

            if (idx < STAGES)
                pending_buf_n[idx] = s_axis_tdata;

            collected       = idx + 1;
            pending_count_n = collected[3:0];

            if (collected >= stride) begin
                case (stride)
                    3'd1: begin
                        stages_n[0] = pending_buf_n[0];
                        for (j = 1; j < STAGES; j = j + 1)
                            stages_n[j] = stages[j-1];
                    end

                    3'd2: begin
                        stages_n[0] = pending_buf_n[1];
                        stages_n[1] = pending_buf_n[0];
                        for (j = 2; j < STAGES; j = j + 1)
                            stages_n[j] = stages[j-2];
                    end

                    3'd3: begin
                        stages_n[0] = pending_buf_n[2];
                        stages_n[1] = pending_buf_n[1];
                        stages_n[2] = pending_buf_n[0];
                        for (j = 3; j < STAGES; j = j + 1)
                            stages_n[j] = stages[j-3];
                    end

                    3'd4: begin
                        stages_n[0] = pending_buf_n[3];
                        stages_n[1] = pending_buf_n[2];
                        stages_n[2] = pending_buf_n[1];
                        stages_n[3] = pending_buf_n[0];
                        for (j = 4; j < STAGES; j = j + 1)
                            stages_n[j] = stages[j-4];
                    end

                    3'd5: begin
                        stages_n[0] = pending_buf_n[4];
                        stages_n[1] = pending_buf_n[3];
                        stages_n[2] = pending_buf_n[2];
                        stages_n[3] = pending_buf_n[1];
                        stages_n[4] = pending_buf_n[0];
                        for (j = 5; j < STAGES; j = j + 1)
                            stages_n[j] = stages[j-5];
                    end

                    3'd6: begin
                        stages_n[0] = pending_buf_n[5];
                        stages_n[1] = pending_buf_n[4];
                        stages_n[2] = pending_buf_n[3];
                        stages_n[3] = pending_buf_n[2];
                        stages_n[4] = pending_buf_n[1];
                        stages_n[5] = pending_buf_n[0];
                        for (j = 6; j < STAGES; j = j + 1)
                            stages_n[j] = stages[j-6];
                    end

                    3'd7: begin
                        stages_n[0] = pending_buf_n[6];
                        stages_n[1] = pending_buf_n[5];
                        stages_n[2] = pending_buf_n[4];
                        stages_n[3] = pending_buf_n[3];
                        stages_n[4] = pending_buf_n[2];
                        stages_n[5] = pending_buf_n[1];
                        stages_n[6] = pending_buf_n[0];
                    end

                    default: begin
                    end
                endcase

                fill_after = fill_count + stride;
                if (fill_after > STAGES)
                    fill_count_n = STAGES;
                else
                    fill_count_n = fill_after[3:0];

                pending_count_n = 4'd0;
                for (j = 0; j < STAGES; j = j + 1)
                    pending_buf_n[j] = '0;

                out_valid_n = (fill_after >= kernel_len);
                out_last_n  = s_axis_tlast;

                if (s_axis_tlast) begin
                    pending_count_n = 4'd0;
                    fill_count_n    = 4'd0;
                end
            end else if (s_axis_tlast) begin
                pending_count_n = 4'd0;
            end
        end else if (s_axis_tlast) begin
            pending_count_n = 4'd0;
            fill_count_n    = 4'd0;
        end
    end

    for (j = 0; j < STAGES; j = j + 1)
        window_out_n[j*DATA_W +: DATA_W] = stages_n[j];
end

always_ff @(posedge clk) begin
    integer i;

    if (!rstn) begin
        stride_q      <= 3'd1;
        fill_count    <= 4'd0;
        pending_count <= 4'd0;
        out_valid     <= 1'b0;
        out_last      <= 1'b0;
        window_out    <= '0;
        for (i = 0; i < STAGES; i = i + 1) begin
            stages[i]      <= '0;
            pending_buf[i] <= '0;
        end
    end else begin
        stride_q      <= stride_q_n;
        fill_count    <= fill_count_n;
        pending_count <= pending_count_n;
        out_valid     <= out_valid_n;
        out_last      <= out_last_n;
        window_out    <= window_out_n;
        for (i = 0; i < STAGES; i = i + 1) begin
            stages[i]      <= stages_n[i];
            pending_buf[i] <= pending_buf_n[i];
        end
    end
end

endmodule
