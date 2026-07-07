`timescale 1ns / 1ps

// dual_dma_arbiter.v
// 双 DMA 通道仲裁器
//
// Read Channel:  仲裁 CPU、VMAC Read 和 VLM Read
// Write Channel: 仅 VMAC Write（VLM 只读）

module dual_dma_arbiter (
    input wire clk,
    input wire resetn,

    // CPU 请求（通过 Port A）
    input wire        cpu_valid,
    input wire        cpu_we,
    input wire [31:0] cpu_addr,
    input wire [31:0] cpu_wdata,
    input wire [3:0]  cpu_wstrb,
    output reg        cpu_ready,
    output reg [31:0] cpu_rdata,

    // VMAC Read 请求
    input wire        vmac_rd_valid,
    input wire [31:0] vmac_rd_addr,
    output reg        vmac_rd_ready,
    output reg [31:0] vmac_rd_rdata,

    // VMAC Write 请求
    input wire        vmac_wr_valid,
    input wire [31:0] vmac_wr_addr,
    input wire [31:0] vmac_wr_wdata,
    input wire [3:0]  vmac_wr_wstrb,
    output reg        vmac_wr_ready,

    // VLM Read 请求
    input wire        vlm_rd_valid,
    input wire [31:0] vlm_rd_addr,
    output reg        vlm_rd_ready,
    output reg [31:0] vlm_rd_rdata,

    // RAM Port A (Read + CPU)
    output reg        ram_porta_valid,
    output reg        ram_porta_we,
    output reg [31:0] ram_porta_addr,
    output reg [31:0] ram_porta_wdata,
    output reg [3:0]  ram_porta_wstrb,
    input wire        ram_porta_ready,
    input wire [31:0] ram_porta_rdata,

    // RAM Port B (Write)
    output reg        ram_portb_valid,
    output reg [31:0] ram_portb_addr,
    output reg [31:0] ram_portb_wdata,
    output reg [3:0]  ram_portb_wstrb,
    input wire        ram_portb_ready
);

    // ========== Read Channel 仲裁 ==========
    // 优先级：VMAC > VLM > CPU
    always @(*) begin
        // 默认值
        ram_porta_valid = 0;
        ram_porta_we = 0;
        ram_porta_addr = 0;
        ram_porta_wdata = 0;
        ram_porta_wstrb = 0;
        vmac_rd_ready = 0;
        vmac_rd_rdata = 0;
        vlm_rd_ready = 0;
        vlm_rd_rdata = 0;
        cpu_ready = 0;
        cpu_rdata = 0;

        if (vmac_rd_valid) begin
            // VMAC Read 最高优先级
            ram_porta_valid = 1;
            ram_porta_we = 0;
            ram_porta_addr = vmac_rd_addr;
            vmac_rd_ready = ram_porta_ready;
            vmac_rd_rdata = ram_porta_rdata;
        end else if (vlm_rd_valid) begin
            // VLM Read 第二优先级
            ram_porta_valid = 1;
            ram_porta_we = 0;
            ram_porta_addr = vlm_rd_addr;
            vlm_rd_ready = ram_porta_ready;
            vlm_rd_rdata = ram_porta_rdata;
        end else if (cpu_valid) begin
            // CPU 访问（读或写）
            ram_porta_valid = 1;
            ram_porta_we = cpu_we;
            ram_porta_addr = cpu_addr;
            ram_porta_wdata = cpu_wdata;
            ram_porta_wstrb = cpu_wstrb;
            cpu_ready = ram_porta_ready;
            cpu_rdata = ram_porta_rdata;
        end
    end

    // ========== Write Channel (独立) ==========
    // 仅 VMAC 使用
    always @(*) begin
        ram_portb_valid = vmac_wr_valid;
        ram_portb_addr = vmac_wr_addr;
        ram_portb_wdata = vmac_wr_wdata;
        ram_portb_wstrb = vmac_wr_wstrb;
        vmac_wr_ready = ram_portb_ready;
    end

endmodule
