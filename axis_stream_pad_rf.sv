`timescale 1ns / 1ps
`ifndef AXIS_STREAM_PAD_RF_SV
`define AXIS_STREAM_PAD_RF_SV
//=============================================================================
// axis_stream_pad_rf.sv
//
// AXI-Stream padding pre-processor — "registered-fill" variant.
//
// Key change vs. the original axis_stream_pad.sv:
//   • Pad pixels are filled with padding_ff (a registered flip-flop value)
//     instead of the hard-coded 8'hFF.
//   • padding_ff is driven from the top-level input pad_fill_val so any
//     known test pattern (0x00, 0xAA, 0xFF …) can be injected at runtime.
//   • All other logic (FSM, counters, skid buffer, handshake) is unchanged.
//
// Port additions vs. original:
//   + input  logic [7:0]  pad_fill_val  — desired pad byte (sampled at reset
//                                         release and at S_IDLE→active edge)
//
// Coding style: SystemVerilog, always_ff / always_comb, synchronous reset.
//=============================================================================

module axis_stream_pad_rf (
    input  logic        clk,
    input  logic        rstn,

    // ── Slave AXI-Stream (input) ──────────────────────────────────────────
    input  logic        s_axis_tvalid,
    input  logic [7:0]  s_axis_tdata,
    input  logic        s_axis_tlast,
    output logic        s_axis_tready,

    // ── Master AXI-Stream (output) ────────────────────────────────────────
    output logic        m_axis_tvalid,
    output logic [7:0]  m_axis_tdata,
    output logic        m_axis_tlast,
    input  logic        m_axis_tready,

    // ── Configuration (hold stable for the duration of a frame) ───────────
    input  logic [7:0]  padding_reg,    // [2:0] = pad size 0-3
    input  logic [3:0]  height,         // input rows  1-16
    input  logic [3:0]  width,          // input cols  1-16

    // ── Registered pad-fill value ─────────────────────────────────────────
    // Sampled into padding_ff every time the FSM returns to S_IDLE so that
    // the pad byte is frozen for the whole frame.  Drive to 8'hAA (or any
    // known value) from the testbench / control path for easy verification.
    input  logic [7:0]  pad_fill_val
);

// ============================================================
// 1. DERIVED GEOMETRY  (5-bit arithmetic; max 16+2×3 = 22)
// ============================================================
logic [2:0] pad;
assign pad = padding_reg[2:0];

logic [4:0] out_rows, out_cols;
assign out_rows = {1'b0, height} + {2'b0, pad} + {2'b0, pad};
assign out_cols = {1'b0, width}  + {2'b0, pad} + {2'b0, pad};

logic [4:0] data_row_first, data_row_last;
logic [4:0] data_col_first, data_col_last;
assign data_row_first = {2'b0, pad};
assign data_row_last  = {1'b0, height} + {2'b0, pad} - 5'd1;
assign data_col_first = {2'b0, pad};
assign data_col_last  = {1'b0, width}  + {2'b0, pad} - 5'd1;

// ============================================================
// 2. FSM STATES  (declared first — used by padding_ff block below)
// ============================================================
typedef enum logic [1:0] {
    S_IDLE          = 2'd0,
    S_TOP_PAD       = 2'd1,
    S_DATA_SIDE_PAD = 2'd2,
    S_BOT_PAD       = 2'd3
} state_t;

state_t state;

// ============================================================
// 3. REGISTERED PAD-FILL FLIP-FLOP
//    Declared after state_t so S_IDLE is already in scope.
//    Captured whenever FSM is idle — frozen for the whole frame.
// ============================================================
logic [7:0] padding_ff;

always_ff @(posedge clk) begin
    if (!rstn)
        padding_ff <= 8'h00;
    else if (state == S_IDLE)
        padding_ff <= pad_fill_val;
end

// ============================================================
// 4. COUNTERS
// ============================================================
logic [4:0] row_cnt, col_cnt;

// ============================================================
// 5. PIXEL CLASSIFICATION  (combinational)
// ============================================================
logic is_pad_pixel;
assign is_pad_pixel = (row_cnt < data_row_first) ||
                      (row_cnt > data_row_last)   ||
                      (col_cnt < data_col_first)  ||
                      (col_cnt > data_col_last);

logic frame_last, last_col, bypass;
assign frame_last = (row_cnt == out_rows - 5'd1) && (col_cnt == out_cols - 5'd1);
assign last_col   = (col_cnt == out_cols - 5'd1);
assign bypass     = (pad == 3'd0);

// ============================================================
// 6. SKID BUFFER
// ============================================================
logic       skid_valid;
logic [7:0] skid_data;
logic       skid_last;

logic       src_valid;
logic [7:0] src_data;
logic       src_last;
assign src_valid = skid_valid ? 1'b1      : s_axis_tvalid;
assign src_data  = skid_valid ? skid_data : s_axis_tdata;
assign src_last  = skid_valid ? skid_last : s_axis_tlast;

// ============================================================
// 7. HANDSHAKE HELPERS
// ============================================================
logic can_emit, out_fire;
assign can_emit = is_pad_pixel | (!is_pad_pixel & src_valid);
assign out_fire = can_emit & m_axis_tready & (state != S_IDLE);

// ============================================================
// 8. FSM  (synchronous reset)
// ============================================================
always_ff @(posedge clk) begin
    if (!rstn) begin
        state <= S_IDLE;
    end else begin
        case (state)
            S_IDLE: begin
                if (s_axis_tvalid)
                    state <= (pad != 3'd0) ? S_TOP_PAD : S_DATA_SIDE_PAD;
            end
            S_TOP_PAD: begin
                if      (out_fire && frame_last)                                          state <= S_IDLE;
                else if (out_fire && last_col && (row_cnt == data_row_first - 5'd1))      state <= S_DATA_SIDE_PAD;
            end
            S_DATA_SIDE_PAD: begin
                if      (out_fire && frame_last)                                          state <= S_IDLE;
                else if (out_fire && last_col && (row_cnt == data_row_last) && (pad != 3'd0))
                                                                                          state <= S_BOT_PAD;
            end
            S_BOT_PAD: begin
                if (out_fire && frame_last)
                    state <= S_IDLE;
            end
            default: state <= S_IDLE;
        endcase
    end
end

// ============================================================
// 9. COUNTER UPDATE
// ============================================================
always_ff @(posedge clk) begin
    if (!rstn) begin
        row_cnt <= 5'd0;
        col_cnt <= 5'd0;
    end else if (out_fire) begin
        if (last_col) begin
            col_cnt <= 5'd0;
            row_cnt <= (row_cnt == out_rows - 5'd1) ? 5'd0 : row_cnt + 5'd1;
        end else begin
            col_cnt <= col_cnt + 5'd1;
        end
    end
end

// ============================================================
// 10. SKID BUFFER UPDATE
// ============================================================
always_ff @(posedge clk) begin
    if (!rstn) begin
        skid_valid <= 1'b0;
        skid_data  <= 8'd0;
        skid_last  <= 1'b0;
    end else begin
        if (skid_valid && !is_pad_pixel && out_fire)
            skid_valid <= 1'b0;
        if (!skid_valid && s_axis_tvalid && !is_pad_pixel &&
            !m_axis_tready && m_axis_tvalid) begin
            skid_valid <= 1'b1;
            skid_data  <= s_axis_tdata;
            skid_last  <= s_axis_tlast;
        end
    end
end

// ============================================================
// 11. OUTPUT REGISTER
//     pad pixels use padding_ff (the registered fill byte)
// ============================================================
always_ff @(posedge clk) begin
    if (!rstn) begin
        m_axis_tvalid <= 1'b0;
        m_axis_tdata  <= 8'd0;
        m_axis_tlast  <= 8'd0;
    end else begin
        if (bypass) begin
            if (s_axis_tvalid && (m_axis_tready || !m_axis_tvalid)) begin
                m_axis_tvalid <= 1'b1;
                m_axis_tdata  <= s_axis_tdata;
                m_axis_tlast  <= s_axis_tlast;
            end else if (m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
            end
        end else begin
            if (state == S_IDLE) begin
                m_axis_tvalid <= 1'b0;
            end else if (can_emit && (m_axis_tready || !m_axis_tvalid)) begin
                m_axis_tvalid <= 1'b1;
                m_axis_tdata  <= is_pad_pixel ? padding_ff : src_data;
                m_axis_tlast  <= frame_last;
            end else if (m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
            end
        end
    end
end

// ============================================================
// 12. s_axis_tready  (combinational)
// ============================================================
always_comb begin
    if (!rstn)
        s_axis_tready = 1'b0;
    else if (bypass)
        s_axis_tready = m_axis_tready;
    else
        s_axis_tready = (state != S_IDLE) & !is_pad_pixel & !skid_valid
                      & (m_axis_tready | !m_axis_tvalid);
end

// ============================================================
// 13. SIMULATION MONITOR  (excluded from synthesis)
// ============================================================
// pragma translate_off
logic m_valid_d1, m_ready_d1;
always_ff @(posedge clk) begin
    m_valid_d1 <= m_axis_tvalid;
    m_ready_d1 <= m_axis_tready;
end
always_ff @(posedge clk) begin
    if (rstn && m_valid_d1 && !m_ready_d1 && !m_axis_tvalid)
        $display("ERROR [axis_stream_pad_rf] tvalid dropped without tready! t=%0t", $time);
    if (rstn && skid_valid && s_axis_tvalid && !is_pad_pixel && !m_axis_tready)
        $display("WARNING [axis_stream_pad_rf] skid contention row=%0d col=%0d t=%0t",
                  row_cnt, col_cnt, $time);
end
// pragma translate_on

endmodule
`endif // AXIS_STREAM_PAD_RF_SV
