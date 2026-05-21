#  AXI-Stream Padded Image Stream Processor

A parameterized RTL/SystemVerilog implementation of a **padded image preprocessing pipeline** for convolution-style sliding window generation, designed for FPGA and ASIC image processing workloads.

## Overview

This project implements a complete **padded image stream preprocessing pipeline** in synthesizable SystemVerilog. It accepts a raw image pixel stream via **AXI-Stream**, applies configurable zero/constant padding around the frame boundaries, delays rows using **BRAM-backed line buffers**, and produces overlapping **sliding windows** via chained shift registers — feeding a **7 × 3 DSP MAC array** for one convolution output per clock cycle.

The design is modular, parameterized, and intended for integration into larger FPGA/ASIC SoC image processing subsystems such as CNN accelerators or hardware image filters.

---

## Architecture

The pipeline processes three simultaneous rows (N, N−1, N−2) to produce a 7-column × 3-row convolution window at every clock cycle.

```
  AXI-Stream In (padded)
         │
         ├──────────────────────────────────────────────────────────────────┐
         │                                                                   │
         ▼   Row N — 7-stage shift register (DSP taps)                       │
    ┌────────────────────────────────────────────────┐                       │
    │  SR0_N → SR1_N → SR2_N → SR3_N → SR4_N → SR5_N → SR6_N               │
    └────────────────────────────────────────────────┘                       │
         │                                                                   │
         ▼                                                                   │
  ┌──────────────────────────────────────┐                                   │
  │  Line Buffer 1  (RAM — image width)  │  Stores row N → outputs row N−1  │
  └──────────────────────┬───────────────┘                                   │
                         │ LB1 out                                           │
                         ▼   Row N−1 — 7-stage shift register                │
                    ┌────────────────────────────────────────────────┐        │
                    │  SR0_N-1 → SR1_N-1 → ... → SR6_N-1            │        │
                    └────────────────────────────────────────────────┘        │
                         │                                                    │
                         ▼                                                    │
                  ┌──────────────────────────────────────┐                   │
                  │  Line Buffer 2  (RAM — image width)  │  row N−1 → N−2   │
                  └──────────────────────┬───────────────┘                   │
                                         │ LB2 out                           │
                                         ▼   Row N−2 — 7-stage shift register│
                                    ┌────────────────────────────────┐        │
                                    │  SR0_N-2 → ... → SR6_N-2      │        │
                                    └────────────────────────────────┘        │
                                                                              │
  ◄─────────────────── DSP tap outputs (dashed) from all 21 taps ────────────┘
         │
         ▼
  ┌─────────────────────────────────────────┐
  │   DSP Block — MAC Array  (7 cols × 3 rows) │
  │   Σ kernel × pixel window → 1 output/clk   │
  └───────────────────────┬─────────────────┘
                          ▼
                   Conv Output
```

> **See the block diagram for the full annotated architecture diagram.**
<img width="600" height="800" alt="ew" src="https://github.com/user-attachments/assets/ed4419ab-c52d-4741-830e-b8b261500288" />


---

##  Features

- **AXI-Stream compliant** input interface with valid/ready handshake and `tlast` frame boundary signaling
- **Configurable padding** — independently set top, bottom, left, and right padding widths; supports constant fill value
- **Dual BRAM line buffers** — LB1 delays row N → N−1; LB2 chains to deliver row N−2; enables 3-row context
- **Three parallel 7-stage shift register arrays** — one per row (N, N−1, N−2), producing 21 simultaneous DSP tap outputs
- **7 × 3 MAC array feed** — all 21 tap values presented to the DSP accumulator block each clock for one convolution result per cycle
- **Fully parameterized** — image width, height, pixel bit-width, padding, kernel length, and stride are top-level parameters
- **Synthesizable RTL** — no behavioral-only constructs; targets both FPGA (Xilinx) and ASIC (12LPP) flows
- **Modular architecture** — each stage (pad, line buffer, shift register) independently reusable in other pipelines

---

##  Module Descriptions

### `top_pad_stride.sv` — Top-Level Integration
The root integration module that stitches together the full pipeline.

| Port | Direction | Description |
|------|-----------|-------------|
| `s_axis_tdata` | Input | Raw pixel stream |
| `s_axis_tvalid` | Input | AXI-Stream valid |
| `s_axis_tready` | Output | AXI-Stream ready (backpressure) |
| `s_axis_tlast` | Input | End-of-row/frame marker |
| `pad_top/bot/left/right` | Input | Padding widths per side |
| `img_height/width` | Input | Input image dimensions |
| `pad_fill_val` | Input | Constant fill value for padding pixels |
| `kernel_len` | Input | Convolution kernel length |
| `stride` | Input | Sliding window stride |

**Connectivity (matches architecture diagram):**
- `axis_stream_pad_rf` → **SR array row N** (7 stages: SR0_N … SR6_N) — direct, no delay
- `axis_stream_pad_rf` → **LB1** → **SR array row N−1** (SR0_N-1 … SR6_N-1)
- **LB1** → **LB2** → **SR array row N−2** (SR0_N-2 … SR6_N-2)
- All 21 DSP tap outputs → **MAC array (7 × 3)** → `conv_output`

---

### `axis_stream_pad_rf.sv` — AXI-Stream Padding Module
Generates configurable top/bottom/left/right padding around the input image frame.

- Maintains full AXI-Stream valid/ready handshake
- Inserts `pad_fill_val` bytes at frame borders
- Asserts `m_axis_tlast` at the end of each padded frame
- Supports asymmetric padding (different widths per side)

---

### `line_buffer_delay.sv` — One-Row Delay Buffer
Delays the padded pixel stream by exactly one full row.

- Stores one padded row into an internal RAM buffer
- Reads back the stored row on the next row cycle
- Enables multi-row context for 2D convolution kernels

---

### `bram_fifo_var.sv` — Parameterized BRAM FIFO / Delay Line
A generic RAM-based FIFO used as the underlying storage for `line_buffer_delay`.

| Parameter | Description |
|-----------|-------------|
| `DATA_WIDTH` | Bit-width of each stored entry |
| `MAX_DEPTH` | Maximum number of entries |

- Delay-line mode: write each pixel, begin read-back after one full row
- Status outputs: `full`, `empty`, `discarded`

---

### `shift_reg_stride.sv` — 7-Stage Sliding Window Generator
Builds a 7-stage serial shift register from the incoming pixel stream and exposes each stage as a **DSP tap** for the MAC accumulator.

- **7 stages per row** (SR0 through SR6), instantiated three times — once per row (N, N−1, N−2)
- Each stage register holds one pixel; all 7 tap values are valid simultaneously after pipeline fill
- `window_out` contains the concatenated tap values (7 × DATA_WIDTH bits)
- `out_valid` asserts when the shift register is fully loaded and a complete window is available
- Configurable stride: a `case` statement selects the appropriate multi-pixel shift amount, advancing the window by N pixels before re-asserting `out_valid` — **stride > 1 is implemented and verified**
- Together, the three SR arrays present **21 DSP tap inputs** (7 cols × 3 rows) to the MAC array each clock

---

### `tb_top_pad_stride_linebuffer.sv` — Verification Testbench
Top-level testbench driving `top_pad_stride` with a small synthetic image stream.

- Drives a parameterized image over AXI-Stream
- Monitors internal DUT signals via hierarchical references:
  - Checks `dut.lb1_data == dut.u_sr1.s_axis_tdata`
  - Checks `dut.lb2_data == dut.u_sr2.s_axis_tdata`
- Reports PASS/FAIL per check with cycle count

---


##  Simulation & Verification

### Prerequisites

- ModelSim / QuestaSim **or** Synopsys VCS
- SystemVerilog-2012 compatible simulator

### Running with ModelSim

```bash
# Step 1: Compile DUT sources
vlog -sv rtl/top_pad_stride.sv \
         rtl/axis_stream_pad_rf.sv \
         rtl/line_buffer_delay.sv \
         rtl/bram_fifo_var.sv \
         rtl/shift_reg_stride.sv

# Step 2: Compile testbench
vlog -sv tb/tb_top_pad_stride_linebuffer.sv

# Step 3: Launch simulation (GUI)
vsim -gui work.tb_top_pad_stride_linebuffer

# Step 4: In ModelSim console — add all signals and run
add wave -r /*
run -all
```

### Running with VCS

```bash
vcs -sverilog \
    rtl/top_pad_stride.sv \
    rtl/axis_stream_pad_rf.sv \
    rtl/line_buffer_delay.sv \
    rtl/bram_fifo_var.sv \
    rtl/shift_reg_stride.sv \
    tb/tb_top_pad_stride_linebuffer.sv \
    -o simv +v2k -debug_all

./simv
```

### Verification Status

| Test | Description | Status |
|------|-------------|--------|
| LB1 → SR1 routing check | `lb1_data == u_sr1.s_axis_tdata` | ✅ PASS |
| LB2 → SR2 routing check | `lb2_data == u_sr2.s_axis_tdata` | ✅ PASS |
| Pad → SR0 direct routing | Padded stream reaches SR0 | ✅ PASS |
| `window_out` correctness | End-to-end convolution window values | 🔲 Planned |
| Stride > 1 window output | Multi-stride window via switch-case shift selection | ✅ PASS |
| Back-pressure stress test | Ready de-assertion handling | 🔲 Planned |

---


##  Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DATA_WIDTH` | `8` | Pixel bit-width |
| `IMG_WIDTH` | `64` | Input image width (pixels) |
| `IMG_HEIGHT` | `64` | Input image height (pixels) |
| `PAD_WIDTH` | `1` | Padding size (applied to all sides unless overridden) |
| `KERNEL_COLS` | `7` | Shift register length — number of column taps per row |
| `KERNEL_ROWS` | `3` | Number of row contexts (= number of SR arrays + line buffers) |
| `STRIDE` | `1` | Sliding window stride |
| `FIFO_DEPTH` | `128` | BRAM FIFO maximum depth (must be ≥ padded image width) |

---

##  Technologies Used

| Category | Tool / Standard |
|----------|----------------|
| HDL | SystemVerilog (IEEE 1800-2012) |
| Interface | AXI4-Stream (ARM AMBA) |
| Memory | BRAM / RAM inference |
| Simulation | ModelSim / Synopsys VCS |
| Waveform Debug | Verdi / GTKWave |
| Linting | SpyGlass / Verilator |
| Target Platform | Xilinx FPGA / ASIC (12LPP) |
| Version Control | Git / GitHub |

---

##  Future Improvements

- [ ] **End-to-end window verification** — scoreboard comparing `window_out` against a Python/C reference model
- [ ] **2D window assembly** — combine all 3 row SR outputs into a full `7 × 3` window tensor output
- [ ] **AXI-Stream backpressure testing** — randomized `ready` de-assertion stress test
- [ ] **Synthesis reports** — add Vivado / DC area and timing reports under `synth/`
- [ ] **UVM testbench** — upgrade to UVM agent/scoreboard framework for reusability
- [ ] **Python reference model** — `scripts/ref_model.py` for golden output generation
- [ ] **Coverage closure** — functional coverage for padding edge cases and kernel boundary conditions

