`timescale 1ns / 1ps

// benchmark_pipeline_debug.v
// 带调试信息的流水线测试

module benchmark_pipeline_debug;

    reg clk, resetn;
    wire trap, pass;
    wire [31:0] pass_value, vmac_result;
    wire vmac_done;
    wire mem_valid, mem_instr, mem_ready;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire [3:0] mem_wstrb;

    p1_top_pipeline dut (
        .clk(clk), .resetn(resetn),
        .trap(trap), .pass(pass), .pass_value(pass_value),
        .vmac_done(vmac_done), .vmac_result(vmac_result),
        .mem_valid(mem_valid), .mem_instr(mem_instr),
        .mem_ready(mem_ready), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end

    localparam [31:0] RAM_MAT_BASE = 32'h0000_0400;
    integer i, cycles;

    initial begin
        $dumpfile("sim/out/benchmark_pipeline_debug.vcd");
        $dumpvars(0, benchmark_pipeline_debug);

        $display("=== Pipeline Debug Test: Batch=4 ===\n");

        // 复位
        resetn = 0;
        repeat(4) @(posedge clk);
        resetn = 1;
        repeat(2) @(posedge clk);

        // 准备数据
        for (i = 0; i < 256; i = i + 1) begin
            dut.u_ram.mem[(RAM_MAT_BASE >> 2) + i] = i + 1;
            dut.u_ram.mem[(RAM_MAT_BASE >> 2) + 256 + i] = 256 - i;
        end

        // 配置 VMAC
        dut.u_vmac.cfg_m = 8;
        dut.u_vmac.cfg_n = 8;
        dut.u_vmac.cfg_k = 8;
        dut.u_vmac.cfg_a_base = RAM_MAT_BASE;
        dut.u_vmac.cfg_b_base = RAM_MAT_BASE + 256;
        dut.u_vmac.cfg_c_base = RAM_MAT_BASE + 512;
        dut.u_vmac.cfg_batch = 4;
        dut.u_vmac.cfg_a_stride = 0;
        dut.u_vmac.cfg_b_stride = 0;
        dut.u_vmac.cfg_c_stride = 0;

        // 触发流水线 DMA
        dut.u_vmac.ctrl_reg = 32'h6;  // bit[2:1] = 11
        @(posedge clk);
        dut.u_vmac.ctrl_reg = 32'h0;

        $display("Started pipeline DMA with batch=4\n");

        // 监控状态
        cycles = 0;
        while (!vmac_done && cycles < 5000) begin
            if (cycles % 500 == 0) begin
                $display("Cycle %0d:", cycles);
                $display("  pipe_state=%0d issued=%0d completed=%0d",
                         dut.u_vmac.pipe_state,
                         dut.u_vmac.pipe_batches_issued,
                         dut.u_vmac.pipe_batches_completed);
                $display("  load_valid=%0d compute_valid=%0d store_valid=%0d",
                         dut.u_vmac.pipe_load_valid,
                         dut.u_vmac.pipe_compute_valid,
                         dut.u_vmac.pipe_store_valid);
                $display("  dma_valid=%0d dma_we=%0d dma_ready=%0d",
                         dut.u_vmac.dma_valid,
                         dut.u_vmac.dma_we,
                         dut.u_vmac.dma_ready);
                $display("");
            end
            @(posedge clk);
            cycles = cycles + 1;
        end

        if (vmac_done) begin
            $display("✓ PASS: Completed in %0d cycles", cycles);
        end else begin
            $display("✗ FAIL: Timeout after %0d cycles", cycles);
            $display("  Final state: pipe_state=%0d issued=%0d completed=%0d",
                     dut.u_vmac.pipe_state,
                     dut.u_vmac.pipe_batches_issued,
                     dut.u_vmac.pipe_batches_completed);
        end

        $finish;
    end

    initial begin
        #100000000;
        $display("Global timeout");
        $finish;
    end

endmodule
