`timescale 1ns / 1ps

// VLM 预处理外设（支持 DMA）
// 基址: 0x0000_2000
//
// 寄存器映射:
//   0x2000: ctrl        - bit[0]=start_cpu (CPU直写模式), bit[1]=start_dma (DMA模式)
//   0x2004: status      - bit[0]=done, bit[1]=busy
//   0x2008: pixel       - CPU直写：写入一个像素
//   0x200C: src_addr    - DMA模式：源地址（RAM中图像数据起始地址）
//   0x2100~0x213C: result[0..15] - Top-K索引 (只读)
//
// 两种模式:
//   1. CPU直写模式: CPU逐像素写0x2008，共12544次
//   2. DMA模式: 配置0x200C，写ctrl[1]=1，DMA自动从RAM读取

module vlm_periph #(
    parameter BASE_ADDR = 32'h0000_2000,
    parameter IMAGE_PIXELS = 12544  // 112*112
)(
    input  wire        clk,
    input  wire        resetn,

    // CPU 内存接口
    input  wire        valid,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,
    output reg         ready,
    output reg  [31:0] rdata,
    output wire        selected,

    // DMA 接口（主模式，读取图像数据）
    output reg         dma_valid,
    output reg         dma_we,
    output reg  [31:0] dma_addr,
    output reg  [31:0] dma_wdata,
    output reg  [3:0]  dma_wstrb,
    input  wire        dma_ready,
    input  wire [31:0] dma_rdata,
    output reg         dma_active
);

    localparam CTRL_OFFSET   = 12'h000;
    localparam STATUS_OFFSET = 12'h004;
    localparam PIXEL_OFFSET  = 12'h008;
    localparam SRC_OFFSET    = 12'h00C;
    localparam RESULT_BASE   = 12'h100;

    // DMA 状态
    localparam DMA_IDLE        = 2'd0;
    localparam DMA_LOAD_PIXELS = 2'd1;
    localparam DMA_WAIT_DONE   = 2'd2;

    wire addr_hit = (addr[31:12] == BASE_ADDR[31:12]);
    assign selected = addr_hit && valid;
    wire [11:0] offset = addr[11:0];

    // VLM 核心信号
    reg        vlm_start_cpu;
    reg        vlm_start_dma;
    wire       vlm_start = vlm_start_cpu | vlm_start_dma;
    reg  [7:0] vlm_pixel_in_cpu;
    reg  [7:0] vlm_pixel_in_dma;
    wire [7:0] vlm_pixel_in = dma_mode_active ? vlm_pixel_in_dma : vlm_pixel_in_cpu;
    reg        vlm_pixel_valid_cpu;
    reg        vlm_pixel_valid_dma;
    wire       vlm_pixel_valid = vlm_pixel_valid_cpu | vlm_pixel_valid_dma;
    wire       vlm_done;
    wire [5:0] vlm_indices [0:15];

    // DMA 控制
    reg [1:0]  dma_state;
    reg [31:0] dma_src_addr;
    reg [31:0] dma_pixel_cnt;
    reg        dma_mode_active;

    vlm_preprocessing_top #(
        .IMAGE_SIZE(112),
        .GRID_SIZE(8),
        .TOP_K(16)
    ) u_vlm (
        .clk(clk),
        .rst_n(resetn),
        .start(vlm_start),
        .pixel_in(vlm_pixel_in),
        .pixel_valid(vlm_pixel_valid),
        .selected_indices(vlm_indices),
        .done(vlm_done)
    );

    // CPU 寄存器读写
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            ready              <= 0;
            rdata              <= 0;
            vlm_start_cpu      <= 0;
            vlm_pixel_in_cpu   <= 0;
            vlm_pixel_valid_cpu <= 0;
            dma_src_addr       <= 0;
        end else begin
            vlm_start_cpu      <= 0;
            vlm_pixel_valid_cpu <= 0;
            ready              <= 0;

            if (valid && addr_hit && !dma_mode_active) begin
                ready <= 1;
                if (|wstrb) begin
                    // 写操作
                    case (offset)
                        CTRL_OFFSET: begin
                            if (wdata[0]) vlm_start_cpu <= 1;  // CPU 模式 start
                            // wdata[1] 由 DMA 状态机处理
                        end
                        PIXEL_OFFSET: begin
                            vlm_pixel_in_cpu    <= wdata[7:0];
                            vlm_pixel_valid_cpu <= 1;
                        end
                        SRC_OFFSET: begin
                            dma_src_addr <= wdata;
                        end
                        default: ;
                    endcase
                end else begin
                    // 读操作
                    if (offset == STATUS_OFFSET) begin
                        rdata <= {30'b0, dma_mode_active, vlm_done};
                    end else if (offset >= RESULT_BASE &&
                                 offset < RESULT_BASE + 16*4) begin
                        rdata <= {26'b0, vlm_indices[(offset - RESULT_BASE) >> 2]};
                    end else begin
                        rdata <= 32'b0;
                    end
                end
            end
        end
    end

    // DMA 状态机
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            dma_state           <= DMA_IDLE;
            dma_valid           <= 0;
            dma_we              <= 0;
            dma_addr            <= 0;
            dma_wdata           <= 0;
            dma_wstrb           <= 0;
            dma_active          <= 0;
            dma_pixel_cnt       <= 0;
            dma_mode_active     <= 0;
            vlm_start_dma       <= 0;
            vlm_pixel_in_dma    <= 0;
            vlm_pixel_valid_dma <= 0;
        end else begin
            vlm_start_dma       <= 0;  // 默认清零
            vlm_pixel_valid_dma <= 0;  // 默认清零

            case (dma_state)
                DMA_IDLE: begin
                    dma_valid  <= 0;
                    dma_active <= 0;

                    // 检测 DMA 启动（CPU 写 ctrl[1]=1）
                    if (valid && addr_hit && |wstrb &&
                        offset == CTRL_OFFSET && wdata[1]) begin
                        dma_state       <= DMA_LOAD_PIXELS;
                        dma_pixel_cnt   <= 0;
                        dma_mode_active <= 1;
                        vlm_start_dma   <= 1;  // 触发 VLM scanner
                    end
                end

                DMA_LOAD_PIXELS: begin
                    dma_active <= 1;
                    dma_valid  <= 1;
                    dma_we     <= 0;
                    dma_addr   <= dma_src_addr + dma_pixel_cnt;  // 字节地址
                    dma_wstrb  <= 0;

                    if (dma_ready) begin
                        // 取低8位作为像素值
                        vlm_pixel_in_dma    <= dma_rdata[7:0];
                        vlm_pixel_valid_dma <= 1;

                        if (dma_pixel_cnt >= IMAGE_PIXELS - 1) begin
                            dma_state <= DMA_WAIT_DONE;
                            dma_valid <= 0;
                        end else begin
                            dma_pixel_cnt <= dma_pixel_cnt + 1;
                        end
                    end
                end

                DMA_WAIT_DONE: begin
                    dma_valid  <= 0;
                    dma_active <= 0;

                    if (vlm_done) begin
                        dma_state       <= DMA_IDLE;
                        dma_mode_active <= 0;
                    end
                end

                default: dma_state <= DMA_IDLE;
            endcase
        end
    end

endmodule
