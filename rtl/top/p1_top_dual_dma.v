`timescale 1ns / 1ps

module p1_top_dual_dma (
    input wire clk,
    input wire resetn,
    output wire trap,
    output wire pass,
    output wire [31:0] pass_value,
    output wire vmac_done,
    output wire [31:0] vmac_result,
    output wire mem_valid,
    output wire mem_instr,
    output wire mem_ready,
    output wire [31:0] mem_addr,
    output wire [31:0] mem_wdata,
    output wire [3:0] mem_wstrb,
    output wire [31:0] mem_rdata
);
    wire ram_ready;
    wire [31:0] ram_rdata;
    wire ram_pass;
    wire [31:0] ram_pass_value;

    wire vmac_ready;
    wire [31:0] vmac_rdata;
    wire vmac_selected;

    wire vlm_ready;
    wire [31:0] vlm_rdata;
    wire vlm_selected;
    wire vlm_dma_valid;
    wire vlm_dma_we;
    wire [31:0] vlm_dma_addr;
    wire [31:0] vlm_dma_wdata;
    wire [3:0] vlm_dma_wstrb;
    wire vlm_dma_ready;
    wire [31:0] vlm_dma_rdata;
    wire vlm_dma_active;

    // VMAC 双 DMA 接口
    wire vmac_dma_rd_valid;
    wire [31:0] vmac_dma_rd_addr;
    wire vmac_dma_rd_ready;
    wire [31:0] vmac_dma_rd_rdata;
    wire vmac_dma_rd_active;

    wire vmac_dma_wr_valid;
    wire [31:0] vmac_dma_wr_addr;
    wire [31:0] vmac_dma_wr_wdata;
    wire [3:0] vmac_dma_wr_wstrb;
    wire vmac_dma_wr_ready;
    wire vmac_dma_wr_active;

    // RAM 双端口接口
    wire ram_porta_valid;
    wire ram_porta_we;
    wire [31:0] ram_porta_addr;
    wire [31:0] ram_porta_wdata;
    wire [3:0] ram_porta_wstrb;
    wire ram_porta_ready;
    wire [31:0] ram_porta_rdata;

    wire ram_portb_valid;
    wire [31:0] ram_portb_addr;
    wire [31:0] ram_portb_wdata;
    wire [3:0] ram_portb_wstrb;
    wire ram_portb_ready;

    wire pcpi_valid;
    wire [31:0] pcpi_insn;
    wire [31:0] pcpi_rs1;
    wire [31:0] pcpi_rs2;
    wire pcpi_wr;
    wire [31:0] pcpi_rd;
    wire pcpi_wait;
    wire pcpi_ready;

    // CPU 访问 RAM 的信号（将通过仲裁器）
    wire cpu_ram_valid = mem_valid && !vmac_selected && !vlm_selected && !vmac_dma_rd_active && !vmac_dma_wr_active && !vlm_dma_active;
    wire cpu_ram_we = |mem_wstrb;
    wire [11:0] cpu_ram_addr = mem_addr[13:2];  // word address
    wire [31:0] cpu_ram_wdata = mem_wdata;
    wire [3:0] cpu_ram_wstrb = mem_wstrb;
    wire cpu_ram_ready;
    wire [31:0] cpu_ram_rdata;

    assign mem_ready = vmac_selected ? vmac_ready :
                       vlm_selected  ? vlm_ready  :
                       ((vmac_dma_rd_active || vmac_dma_wr_active || vlm_dma_active) ? 1'b0 : cpu_ram_ready);
    assign mem_rdata = vmac_selected ? vmac_rdata :
                       vlm_selected  ? vlm_rdata  : cpu_ram_rdata;
    assign pass = 1'b0;  // dual port RAM 不支持 pass 信号
    assign pass_value = 32'b0;

    picorv32 #(
        .ENABLE_COUNTERS(0),
        .ENABLE_COUNTERS64(0),
        .ENABLE_REGS_16_31(1),
        .ENABLE_REGS_DUALPORT(1),
        .LATCHED_MEM_RDATA(0),
        .TWO_STAGE_SHIFT(1),
        .BARREL_SHIFTER(0),
        .TWO_CYCLE_COMPARE(0),
        .TWO_CYCLE_ALU(0),
        .COMPRESSED_ISA(0),
        .CATCH_MISALIGN(1),
        .CATCH_ILLINSN(1),
        .ENABLE_PCPI(1),
        .ENABLE_MUL(0),
        .ENABLE_FAST_MUL(0),
        .ENABLE_DIV(0),
        .ENABLE_IRQ(0),
        .ENABLE_TRACE(0),
        .REGS_INIT_ZERO(1),
        .PROGADDR_RESET(32'h0000_0000),
        .STACKADDR(32'h0000_0200)
    ) u_cpu (
        .clk(clk),
        .resetn(resetn),
        .trap(trap),
        .mem_valid(mem_valid),
        .mem_instr(mem_instr),
        .mem_ready(mem_ready),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata),
        .mem_la_read(),
        .mem_la_write(),
        .mem_la_addr(),
        .mem_la_wdata(),
        .mem_la_wstrb(),
        .pcpi_valid(pcpi_valid),
        .pcpi_insn(pcpi_insn),
        .pcpi_rs1(pcpi_rs1),
        .pcpi_rs2(pcpi_rs2),
        .pcpi_wr(pcpi_wr),
        .pcpi_rd(pcpi_rd),
        .pcpi_wait(pcpi_wait),
        .pcpi_ready(pcpi_ready),
        .irq(32'b0),
        .eoi()
    );

    dual_port_ram #(
        .ADDR_WIDTH(12),
        .DATA_WIDTH(32),
        .MEM_SIZE(512)
    ) u_ram (
        .clk(clk),
        // Port A: CPU + DMA Read
        .porta_valid(ram_porta_valid),
        .porta_we(ram_porta_we),
        .porta_addr(ram_porta_addr),
        .porta_wdata(ram_porta_wdata),
        .porta_wstrb(ram_porta_wstrb),
        .porta_ready(ram_porta_ready),
        .porta_rdata(ram_porta_rdata),
        // Port B: DMA Write
        .portb_valid(ram_portb_valid),
        .portb_addr(ram_portb_addr),
        .portb_wdata(ram_portb_wdata),
        .portb_wstrb(ram_portb_wstrb),
        .portb_ready(ram_portb_ready)
    );

    dual_dma_arbiter u_dma_arb (
        .clk(clk),
        .resetn(resetn),
        // CPU 请求
        .cpu_valid(cpu_ram_valid),
        .cpu_we(cpu_ram_we),
        .cpu_addr(cpu_ram_addr),
        .cpu_wdata(cpu_ram_wdata),
        .cpu_wstrb(cpu_ram_wstrb),
        .cpu_ready(cpu_ram_ready),
        .cpu_rdata(cpu_ram_rdata),
        // VMAC Read
        .vmac_rd_valid(vmac_dma_rd_valid),
        .vmac_rd_addr(vmac_dma_rd_addr[13:2]),  // word address
        .vmac_rd_ready(vmac_dma_rd_ready),
        .vmac_rd_rdata(vmac_dma_rd_rdata),
        // VMAC Write
        .vmac_wr_valid(vmac_dma_wr_valid),
        .vmac_wr_addr(vmac_dma_wr_addr[13:2]),  // word address
        .vmac_wr_wdata(vmac_dma_wr_wdata),
        .vmac_wr_wstrb(vmac_dma_wr_wstrb),
        .vmac_wr_ready(vmac_dma_wr_ready),
        // VLM Read
        .vlm_rd_valid(vlm_dma_valid && !vlm_dma_we),
        .vlm_rd_addr(vlm_dma_addr[13:2]),  // word address
        .vlm_rd_ready(vlm_dma_ready),
        .vlm_rd_rdata(vlm_dma_rdata),
        // RAM Port A (Read + CPU)
        .ram_porta_valid(ram_porta_valid),
        .ram_porta_we(ram_porta_we),
        .ram_porta_addr(ram_porta_addr),
        .ram_porta_wdata(ram_porta_wdata),
        .ram_porta_wstrb(ram_porta_wstrb),
        .ram_porta_ready(ram_porta_ready),
        .ram_porta_rdata(ram_porta_rdata),
        // RAM Port B (Write)
        .ram_portb_valid(ram_portb_valid),
        .ram_portb_addr(ram_portb_addr),
        .ram_portb_wdata(ram_portb_wdata),
        .ram_portb_wstrb(ram_portb_wstrb),
        .ram_portb_ready(ram_portb_ready)
    );

    vmac_unit_dual_dma #(
        .BASE_ADDR(32'h0000_1000)
    ) u_vmac (
        .clk(clk),
        .resetn(resetn),
        .valid(mem_valid),
        .addr(mem_addr),
        .wdata(mem_wdata),
        .wstrb(mem_wstrb),
        .ready(vmac_ready),
        .rdata(vmac_rdata),
        .selected(vmac_selected),
        .pcpi_valid(pcpi_valid),
        .pcpi_insn(pcpi_insn),
        .pcpi_rs1(pcpi_rs1),
        .pcpi_rs2(pcpi_rs2),
        .pcpi_wr(pcpi_wr),
        .pcpi_rd(pcpi_rd),
        .pcpi_wait(pcpi_wait),
        .pcpi_ready(pcpi_ready),
        .done_pulse(vmac_done),
        .result_value(vmac_result),
        // DMA Read 接口
        .dma_rd_valid(vmac_dma_rd_valid),
        .dma_rd_addr(vmac_dma_rd_addr),
        .dma_rd_ready(vmac_dma_rd_ready),
        .dma_rd_rdata(vmac_dma_rd_rdata),
        .dma_rd_active(vmac_dma_rd_active),
        // DMA Write 接口
        .dma_wr_valid(vmac_dma_wr_valid),
        .dma_wr_addr(vmac_dma_wr_addr),
        .dma_wr_wdata(vmac_dma_wr_wdata),
        .dma_wr_wstrb(vmac_dma_wr_wstrb),
        .dma_wr_ready(vmac_dma_wr_ready),
        .dma_wr_active(vmac_dma_wr_active)
    );

    vlm_periph #(
        .BASE_ADDR(32'h0000_2000)
    ) u_vlm (
        .clk(clk),
        .resetn(resetn),
        .valid(mem_valid),
        .addr(mem_addr),
        .wdata(mem_wdata),
        .wstrb(mem_wstrb),
        .ready(vlm_ready),
        .rdata(vlm_rdata),
        .selected(vlm_selected),
        .dma_valid(vlm_dma_valid),
        .dma_we(vlm_dma_we),
        .dma_addr(vlm_dma_addr),
        .dma_wdata(vlm_dma_wdata),
        .dma_wstrb(vlm_dma_wstrb),
        .dma_ready(vlm_dma_ready),
        .dma_rdata(vlm_dma_rdata),
        .dma_active(vlm_dma_active)
    );
endmodule
