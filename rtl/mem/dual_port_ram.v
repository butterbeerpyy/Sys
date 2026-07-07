`timescale 1ns / 1ps

// dual_port_ram.v
// 真双端口 RAM：支持同时读写
//
// Port A: 读/写（用于 CPU 和 DMA Read）
// Port B: 只写（用于 DMA Write）

module dual_port_ram #(
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 32,
    parameter MEM_SIZE = 2048  // 2KB
) (
    input wire clk,

    // Port A: 读/写端口（CPU + DMA Read）
    input wire                    porta_valid,
    input wire                    porta_we,
    input wire [ADDR_WIDTH-1:0]   porta_addr,
    input wire [DATA_WIDTH-1:0]   porta_wdata,
    input wire [3:0]              porta_wstrb,
    output reg                    porta_ready,
    output reg [DATA_WIDTH-1:0]   porta_rdata,

    // Port B: 只写端口（DMA Write）
    input wire                    portb_valid,
    input wire [ADDR_WIDTH-1:0]   portb_addr,
    input wire [DATA_WIDTH-1:0]   portb_wdata,
    input wire [3:0]              portb_wstrb,
    output reg                    portb_ready
);

    reg [DATA_WIDTH-1:0] mem [0:MEM_SIZE-1];

    // Port A: 读/写
    always @(posedge clk) begin
        porta_ready <= 0;

        if (porta_valid) begin
            porta_ready <= 1;

            if (porta_we) begin
                // 写操作
                if (porta_wstrb[0]) mem[porta_addr][7:0]   <= porta_wdata[7:0];
                if (porta_wstrb[1]) mem[porta_addr][15:8]  <= porta_wdata[15:8];
                if (porta_wstrb[2]) mem[porta_addr][23:16] <= porta_wdata[23:16];
                if (porta_wstrb[3]) mem[porta_addr][31:24] <= porta_wdata[31:24];
            end else begin
                // 读操作
                porta_rdata <= mem[porta_addr];
            end
        end
    end

    // Port B: 只写
    always @(posedge clk) begin
        portb_ready <= 0;

        if (portb_valid) begin
            portb_ready <= 1;

            if (portb_wstrb[0]) mem[portb_addr][7:0]   <= portb_wdata[7:0];
            if (portb_wstrb[1]) mem[portb_addr][15:8]  <= portb_wdata[15:8];
            if (portb_wstrb[2]) mem[portb_addr][23:16] <= portb_wdata[23:16];
            if (portb_wstrb[3]) mem[portb_addr][31:24] <= portb_wdata[31:24];
        end
    end

endmodule
