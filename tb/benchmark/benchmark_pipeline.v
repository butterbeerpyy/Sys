`timescale 1ns / 1ps

// benchmark_pipeline.v
// 测试 VMAC 流水线版本的性能提升
// 对比：原始 DMA 模式 vs 流水线 DMA 模式

module benchmark_pipeline;

    reg clk, resetn;
    wire trap, pass;
    wire [31:0] pass_value, vmac_result;
    wire vmac_done;
    wire mem_valid, mem_instr, mem_ready;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire [3:0] mem_wstrb;

    // 实例化流水线版本的顶层
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

    localparam [31:0] VMAC_BASE     = 32'h0000_1000;
    localparam [31:0] VMAC_CTRL     = VMAC_BASE + 32'h200;
    localparam [31:0] VMAC_STATUS   = VMAC_BASE + 32'h204;
    localparam [31:0] VMAC_CFG_M    = VMAC_BASE + 32'h20C;
    localparam [31:0] VMAC_CFG_N    = VMAC_BASE + 32'h210;
    localparam [31:0] VMAC_CFG_K    = VMAC_BASE + 32'h214;
    localparam [31:0] VMAC_DMA_A    = VMAC_BASE + 32'h218;
    localparam [31:0] VMAC_DMA_B    = VMAC_BASE + 32'h21C;
    localparam [31:0] VMAC_DMA_C    = VMAC_BASE + 32'h220;
    localparam [31:0] VMAC_BATCH    = VMAC_BASE + 32'h230;
    localparam [31:0] RAM_MAT_BASE  = 32'h0000_0400;

    integer fd;
    integer cycles_start, cycles_end, cycles_elapsed;
    integer i;

    initial begin
        $dumpfile("sim/out/benchmark_pipeline.vcd");
        $dumpvars(0, benchmark_pipeline);

        fd = $fopen("tb/benchmark/pipeline_results.csv", "w");
        $fwrite(fd, "test_id,workload,mode,cycles\n");

        $display("========================================");
        $display("  VMAC Pipeline Performance Test");
        $display("========================================\n");

        // 复位
        resetn = 0;
        repeat(4) @(posedge clk);
        resetn = 1;
        repeat(2) @(posedge clk);

        // 准备矩阵数据
        for (i = 0; i < 256; i = i + 1) begin
            dut.u_ram.mem[(RAM_MAT_BASE >> 2) + i] = i + 1;
            dut.u_ram.mem[(RAM_MAT_BASE >> 2) + 256 + i] = 256 - i;
        end

        // =========================================
        // 测试 1: 8x8 单batch - 非流水线 DMA
        // =========================================
        $display("[Test 1] 8x8 Single Batch - Non-Pipeline DMA");
        configure_vmac(8, 8, 8, RAM_MAT_BASE, 1);
        cycles_start = $time / 10;
        trigger_dma(0);  // bit[2]=0: 非流水线
        wait_vmac_done();
        cycles_end = $time / 10;
        cycles_elapsed = cycles_end - cycles_start;
        $fwrite(fd, "0,VMAC_8x8_batch1,NonPipeline,%0d\n", cycles_elapsed);
        $display("    Non-Pipeline: %0d cycles", cycles_elapsed);

        // =========================================
        // 测试 2: 8x8 单batch - 流水线 DMA
        // =========================================
        $display("[Test 2] 8x8 Single Batch - Pipeline DMA");
        configure_vmac(8, 8, 8, RAM_MAT_BASE, 1);
        cycles_start = $time / 10;
        trigger_dma(1);  // bit[2]=1: 流水线
        wait_vmac_done();
        cycles_end = $time / 10;
        cycles_elapsed = cycles_end - cycles_start;
        $fwrite(fd, "1,VMAC_8x8_batch1,Pipeline,%0d\n", cycles_elapsed);
        $display("    Pipeline: %0d cycles", cycles_elapsed);

        // =========================================
        // 测试 3: 8x8 batch=4 - 非流水线 DMA
        // =========================================
        $display("\n[Test 3] 8x8 Batch=4 - Non-Pipeline DMA");
        configure_vmac(8, 8, 8, RAM_MAT_BASE, 4);
        cycles_start = $time / 10;
        trigger_dma(0);
        wait_vmac_done();
        cycles_end = $time / 10;
        cycles_elapsed = cycles_end - cycles_start;
        $fwrite(fd, "2,VMAC_8x8_batch4,NonPipeline,%0d\n", cycles_elapsed);
        $display("    Non-Pipeline: %0d cycles", cycles_elapsed);

        // =========================================
        // 测试 4: 8x8 batch=4 - 流水线 DMA
        // =========================================
        $display("[Test 4] 8x8 Batch=4 - Pipeline DMA");
        configure_vmac(8, 8, 8, RAM_MAT_BASE, 4);
        cycles_start = $time / 10;
        trigger_dma(1);
        wait_vmac_done();
        cycles_end = $time / 10;
        cycles_elapsed = cycles_end - cycles_start;
        $fwrite(fd, "3,VMAC_8x8_batch4,Pipeline,%0d\n", cycles_elapsed);
        $display("    Pipeline: %0d cycles", cycles_elapsed);

        // =========================================
        // 测试 5: 8x8 batch=8 - 非流水线 DMA
        // =========================================
        $display("\n[Test 5] 8x8 Batch=8 - Non-Pipeline DMA");
        configure_vmac(8, 8, 8, RAM_MAT_BASE, 8);
        cycles_start = $time / 10;
        trigger_dma(0);
        wait_vmac_done();
        cycles_end = $time / 10;
        cycles_elapsed = cycles_end - cycles_start;
        $fwrite(fd, "4,VMAC_8x8_batch8,NonPipeline,%0d\n", cycles_elapsed);
        $display("    Non-Pipeline: %0d cycles", cycles_elapsed);

        // =========================================
        // 测试 6: 8x8 batch=8 - 流水线 DMA
        // =========================================
        $display("[Test 6] 8x8 Batch=8 - Pipeline DMA");
        configure_vmac(8, 8, 8, RAM_MAT_BASE, 8);
        cycles_start = $time / 10;
        trigger_dma(1);
        wait_vmac_done();
        cycles_end = $time / 10;
        cycles_elapsed = cycles_end - cycles_start;
        $fwrite(fd, "5,VMAC_8x8_batch8,Pipeline,%0d\n", cycles_elapsed);
        $display("    Pipeline: %0d cycles", cycles_elapsed);

        $fclose(fd);
        $display("\n========================================");
        $display("  Pipeline Benchmark Complete!");
        $display("  Results: tb/benchmark/pipeline_results.csv");
        $display("========================================");
        $finish;
    end

    task configure_vmac;
        input integer m, n, k;
        input [31:0] base_addr;
        input integer batch;
        begin
            dut.u_vmac.cfg_m = m;
            dut.u_vmac.cfg_n = n;
            dut.u_vmac.cfg_k = k;
            dut.u_vmac.cfg_a_base = base_addr;
            dut.u_vmac.cfg_b_base = base_addr + 256;
            dut.u_vmac.cfg_c_base = base_addr + 512;
            dut.u_vmac.cfg_batch = batch;
            dut.u_vmac.cfg_a_stride = 0;
            dut.u_vmac.cfg_b_stride = 0;
            dut.u_vmac.cfg_c_stride = 0;
        end
    endtask

    task trigger_dma;
        input pipeline;
        begin
            if (pipeline) begin
                dut.u_vmac.ctrl_reg = 32'h6;  // bit[2:1] = 11 (DMA + Pipeline)
            end else begin
                dut.u_vmac.ctrl_reg = 32'h2;  // bit[1] = 1 (DMA only)
            end
            @(posedge clk);
            dut.u_vmac.ctrl_reg = 32'h0;
        end
    endtask

    task wait_vmac_done;
        integer timeout;
        begin
            timeout = 0;
            while (!vmac_done && timeout < 200000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 200000) begin
                $display("ERROR: Timeout waiting for VMAC done");
                $finish;
            end
        end
    endtask

    initial begin
        #200000000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
