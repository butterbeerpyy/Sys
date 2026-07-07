`timescale 1ns / 1ps

// benchmark_dual_dma.v
// 双 DMA 性能测试
// 对比：单 DMA vs 双 DMA

module benchmark_dual_dma;

    reg clk, resetn;
    wire trap, pass;
    wire [31:0] pass_value, vmac_result;
    wire vmac_done;
    wire mem_valid, mem_instr, mem_ready;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire [3:0] mem_wstrb;

    p1_top_dual_dma dut (
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
    integer i, test_id;

    initial begin
        $dumpfile("sim/out/benchmark_dual_dma.vcd");
        $dumpvars(0, benchmark_dual_dma);

        fd = $fopen("tb/benchmark/dual_dma_results.csv", "w");
        $fwrite(fd, "test_id,batch_count,mode,cycles\n");

        $display("========================================");
        $display("  Dual DMA Performance Test");
        $display("========================================\n");

        // 复位
        resetn = 0;
        repeat(4) @(posedge clk);
        resetn = 1;
        repeat(2) @(posedge clk);

        // 准备矩阵数据
        for (i = 0; i < 512; i = i + 1) begin
            dut.u_ram.mem[i] = i + 1;
        end

        test_id = 0;

        $display("测试说明:");
        $display("  - 单 DMA: 原始架构，Read/Write 串行");
        $display("  - 双 DMA: 新架构，Read/Write 可并行\n");

        // =========================================
        // 测试组 1: Batch=1（无重叠机会）
        // =========================================
        $display("[Test %0d] Batch=1 (Baseline)", test_id);
        run_test(1, test_id);
        test_id = test_id + 1;

        // =========================================
        // 测试组 2: Batch=2（开始体现优势）
        // =========================================
        $display("\n[Test %0d] Batch=2", test_id);
        run_test(2, test_id);
        test_id = test_id + 1;

        // =========================================
        // 测试组 3: Batch=4（明显优势）
        // =========================================
        $display("\n[Test %0d] Batch=4", test_id);
        run_test(4, test_id);
        test_id = test_id + 1;

        // =========================================
        // 测试组 4: Batch=8（稳定状态）
        // =========================================
        $display("\n[Test %0d] Batch=8", test_id);
        run_test(8, test_id);
        test_id = test_id + 1;

        $fclose(fd);
        $display("\n========================================");
        $display("  测试完成！");
        $display("  结果: tb/benchmark/dual_dma_results.csv");
        $display("========================================");
        $finish;
    end

    task run_test;
        input integer batch;
        input integer tid;
        integer cycles;
        begin
            // 配置 VMAC
            dut.u_vmac.cfg_m = 8;
            dut.u_vmac.cfg_n = 8;
            dut.u_vmac.cfg_k = 8;
            dut.u_vmac.cfg_a_base = RAM_MAT_BASE;
            dut.u_vmac.cfg_b_base = RAM_MAT_BASE + 256;
            dut.u_vmac.cfg_c_base = RAM_MAT_BASE + 512;
            dut.u_vmac.cfg_batch = batch;
            dut.u_vmac.cfg_a_stride = 0;
            dut.u_vmac.cfg_b_stride = 0;
            dut.u_vmac.cfg_c_stride = 0;

            // 触发 DMA
            cycles_start = $time / 10;
            dut.u_vmac.ctrl_reg = 32'h2;  // DMA mode
            @(posedge clk);
            dut.u_vmac.ctrl_reg = 32'h0;

            // 等待完成
            cycles = 0;
            while (!vmac_done && cycles < 50000) begin
                @(posedge clk);
                cycles = cycles + 1;
            end

            cycles_end = $time / 10;
            cycles_elapsed = cycles_end - cycles_start;

            if (vmac_done) begin
                $fwrite(fd, "%0d,%0d,DualDMA,%0d\n", tid, batch, cycles_elapsed);
                $display("    Batch=%0d: %0d cycles", batch, cycles_elapsed);
            end else begin
                $display("    ERROR: Timeout after %0d cycles", cycles);
                $fwrite(fd, "%0d,%0d,DualDMA,TIMEOUT\n", tid, batch);
            end

            // 等待一段时间再开始下一个测试
            repeat(10) @(posedge clk);
        end
    endtask

    initial begin
        #500000000;
        $display("GLOBAL TIMEOUT");
        $finish;
    end

endmodule
