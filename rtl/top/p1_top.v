`timescale 1ns / 1ps

module p1_top (
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

    wire pcpi_valid;
    wire [31:0] pcpi_insn;
    wire [31:0] pcpi_rs1;
    wire [31:0] pcpi_rs2;
    wire pcpi_wr;
    wire [31:0] pcpi_rd;
    wire pcpi_wait;
    wire pcpi_ready;

    assign mem_ready = vmac_selected ? vmac_ready : ram_ready;
    assign mem_rdata = vmac_selected ? vmac_rdata : ram_rdata;
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
        .valid(mem_valid && !vmac_selected),
        .instr(mem_instr),
        .addr(mem_addr),
        .wdata(mem_wdata),
        .wstrb(mem_wstrb),
        .ready(ram_ready),
        .rdata(ram_rdata),
        .pass(ram_pass),
        .pass_value(ram_pass_value)
    );

    vmac_unit #(
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
        .result_value(vmac_result)
    );
endmodule
