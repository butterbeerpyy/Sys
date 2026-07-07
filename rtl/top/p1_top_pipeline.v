`timescale 1ns / 1ps

module p1_top_pipeline (
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

    wire vmac_dma_valid;
    wire vmac_dma_we;
    wire [31:0] vmac_dma_addr;
    wire [31:0] vmac_dma_wdata;
    wire [3:0] vmac_dma_wstrb;
    wire vmac_dma_ready;
    wire [31:0] vmac_dma_rdata;
    wire vmac_dma_active;

    wire pcpi_valid;
    wire [31:0] pcpi_insn;
    wire [31:0] pcpi_rs1;
    wire [31:0] pcpi_rs2;
    wire pcpi_wr;
    wire [31:0] pcpi_rd;
    wire pcpi_wait;
    wire pcpi_ready;

    wire ram_cpu_valid = mem_valid && !vmac_selected && !vlm_selected && !vmac_dma_active && !vlm_dma_active;
    wire ram_dma_valid = vmac_dma_valid || vlm_dma_valid;
    wire ram_valid = ram_cpu_valid || ram_dma_valid;

    // DMA 请求仲裁：VMAC 优先
    wire dma_arb_vmac = vmac_dma_valid;
    wire dma_arb_vlm  = vlm_dma_valid && !vmac_dma_valid;

    wire ram_we   = dma_arb_vmac ? vmac_dma_we   : (dma_arb_vlm ? vlm_dma_we   : 1'b0);
    wire [31:0] ram_addr_dma  = dma_arb_vmac ? vmac_dma_addr : (dma_arb_vlm ? vlm_dma_addr : 32'b0);
    wire [31:0] ram_wdata_dma = dma_arb_vmac ? vmac_dma_wdata : (dma_arb_vlm ? vlm_dma_wdata : 32'b0);
    wire [3:0]  ram_wstrb_dma = dma_arb_vmac ? vmac_dma_wstrb : (dma_arb_vlm ? vlm_dma_wstrb : 4'b0);

    assign vmac_dma_ready = dma_arb_vmac && ram_ready;
    assign vmac_dma_rdata = ram_rdata;
    assign vlm_dma_ready  = dma_arb_vlm  && ram_ready;
    assign vlm_dma_rdata  = ram_rdata;

    assign mem_ready = vmac_selected ? vmac_ready :
                       vlm_selected  ? vlm_ready  :
                       ((vmac_dma_active || vlm_dma_active) ? 1'b0 : ram_ready);
    assign mem_rdata = vmac_selected ? vmac_rdata :
                       vlm_selected  ? vlm_rdata  : ram_rdata;
    assign pass = ram_pass;
    assign pass_value = ram_pass_value;

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

    simple_ram #(
        .MEM_WORDS(512),
        .PASS_ADDR(32'h0000_0200),
        .PASS_DATA(32'h0000_0055)
    ) u_ram (
        .clk(clk),
        .resetn(resetn),
        .valid(ram_valid),
        .instr(mem_instr && !ram_dma_valid),
        .addr(ram_dma_valid ? ram_addr_dma : mem_addr),
        .wdata(ram_dma_valid ? ram_wdata_dma : mem_wdata),
        .wstrb(ram_dma_valid ? ram_wstrb_dma : mem_wstrb),
        .ready(ram_ready),
        .rdata(ram_rdata),
        .pass(ram_pass),
        .pass_value(ram_pass_value)
    );

    vmac_unit_pipeline #(
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
        .dma_valid(vmac_dma_valid),
        .dma_we(vmac_dma_we),
        .dma_addr(vmac_dma_addr),
        .dma_wdata(vmac_dma_wdata),
        .dma_wstrb(vmac_dma_wstrb),
        .dma_ready(vmac_dma_ready),
        .dma_rdata(vmac_dma_rdata),
        .dma_active(vmac_dma_active)
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
