`timescale 1ns / 1ps

// benchmark_cpu_vs_dma.v
// 性能对比测试：CPU 直写模式 vs DMA 模式
//
// 测试场景：
//   1. VMAC: 2D 矩阵乘法 (不同规模: 4x4, 8x8)
//   2. VMAC: 3D Batch 矩阵乘法 (batch=2,4,8)
//   3. VLM: 图像预处理 (112x112 = 12544 像素)
//
// 输出: benchmark_results.csv (cycles, mode, workload)

module benchmark_cpu_vs_dma;

    reg clk, resetn;
    wire trap, pass;
    wire [31:0] pass_value, vmac_result;
    wire vmac_done;
    wire mem_valid, mem_instr, mem_ready;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire [3:0] mem_wstrb;

    p1_top dut (
        .clk(clk), .resetn(resetn),
        .trap(trap), .pass(pass), .pass_value(pass_value),
        .vmac_done(vmac_done), .vmac_result(vmac_result),
        .mem_valid(mem_valid), .mem_instr(mem_instr),
        .mem_ready(mem_ready), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end

    integer fd;
    integer cycles_start, cycles_end, cycles_elapsed;
    integer test_id;
    integer i, j, k;

    // VMAC 配置
    localparam [31:0] VMAC_BASE     = 32'h0000_1000;
    localparam [31:0] VMAC_CTRL     = VMAC_BASE + 32'h200;
    localparam [31:0] VMAC_STATUS   = VMAC_BASE + 32'h204;
    localparam [31:0] VMAC_CFG_M    = VMAC_BASE + 32'h20C;
    localparam [31:0] VMAC_CFG_N    = VMAC_BASE + 32'h210;
    localparam [31:0] VMAC_CFG_K    = VMAC_BASE + 32'h214;
    localparam [31:0] VMAC_A_BASE   = VMAC_BASE + 32'h000;
    localparam [31:0] VMAC_B_BASE   = VMAC_BASE + 32'h080;
    localparam [31:0] VMAC_C_BASE   = VMAC_BASE + 32'h100;
    localparam [31:0] VMAC_DMA_A    = VMAC_BASE + 32'h218;
    localparam [31:0] VMAC_DMA_B    = VMAC_BASE + 32'h21C;
    localparam [31:0] VMAC_DMA_C    = VMAC_BASE + 32'h220;
    localparam [31:0] VMAC_BATCH    = VMAC_BASE + 32'h230;

    // VLM 配置
    localparam [31:0] VLM_BASE      = 32'h0000_2000;
    localparam [31:0] VLM_CTRL      = VLM_BASE + 32'h000;
    localparam [31:0] VLM_STATUS    = VLM_BASE + 32'h004;
    localparam [31:0] VLM_PIXEL     = VLM_BASE + 32'h008;
    localparam [31:0] VLM_SRC_ADDR  = VLM_BASE + 32'h00C;

    localparam [31:0] RAM_MAT_BASE  = 32'h0000_0400;
    localparam [31:0] RAM_IMG_BASE  = 32'h0000_0800;

    initial begin
        $dumpfile("sim/out/benchmark_cpu_vs_dma.vcd");
        $dumpvars(0, benchmark_cpu_vs_dma);

        fd = $fopen("tb/benchmark/benchmark_results.csv", "w");
        $fwrite(fd, "test_id,workload,mode,cycles\n");

        $display("========================================");
        $display("  CPU vs DMA Performance Benchmark");
        $display("========================================\n");

        // 复位
        resetn = 0;
        repeat(4) @(posedge clk);
        resetn = 1;
        repeat(2) @(posedge clk);

        test_id = 0;

        // =========================================
        // 测试 1: VMAC 2D 矩阵乘法 4x4
        // =========================================
        $display("[Test 1] VMAC 2D 4x4 Matrix Multiplication");

        // 1a. CPU 模式
        $display("  [1a] CPU mode...");
        cycles_start = $time / 10;
        vmac_cpu_mode(4, 4, 4);
        wait_vmac_done();
        cycles_end = $time / 10;
        cycles_elapsed = cycles_end - cycles_start;
        $fwrite(fd, "%0d,VMAC_2D_4x4,CPU,%0d\n", test_id++, cycles_elapsed);
        $display("      Cycles: %0d", cycles_elapsed);

        // 1b. DMA 模式
        $display("  [1b] DMA mode...");
        prepare_matrices_in_ram(4, 4, 4, RAM_MAT_BASE);
        cycles_start = $time / 10;
        vmac_dma_mode(4, 4, 4, RAM_MAT_BASE, 1);
        wait_vmac_done();
        cycles_end = $time / 10;
        cycles_elapsed = cycles_end - cycles_start;
        $fwrite(fd, "%0d,VMAC_2D_4x4,DMA,%0d\n", test_id++, cycles_elapsed);
        $display("      Cycles: %0d", cycles_elapsed);

        // =========================================
        // 测试 2: VMAC 2D 矩阵乘法 8x8
        // =========================================
        $display("\n[Test 2] VMAC 2D 8x8 Matrix Multiplication");

        // 2a. CPU 模式
        $display("  [2a] CPU mode...");
        cycles_start = $time / 10;
        vmac_cpu_mode(8, 8, 8);
        wait_vmac_done();
        cycles_end = $time / 10;
        cycles_elapsed = cycles_end - cycles_start;
        $fwrite(fd, "%0d,VMAC_2D_8x8,CPU,%0d\n", test_id++, cycles_elapsed);
        $display("      Cycles: %0d", cycles_elapsed);

        // 2b. DMA 模式
        $display("  [2b] DMA mode...");
        prepare_matrices_in_ram(8, 8, 8, RAM_MAT_BASE);
        cycles_start = $time / 10;
        vmac_dma_mode(8, 8, 8, RAM_MAT_BASE, 1);
        wait_vmac_done();
        cycles_end = $time / 10;
        cycles_elapsed = cycles_end - cycles_start;
        $fwrite(fd, "%0d,VMAC_2D_8x8,DMA,%0d\n", test_id++, cycles_elapsed);
        $display("      Cycles: %0d", cycles_elapsed);

        // =========================================
        // 测试 3: VMAC 3D Batch (batch=2, 4x4)
        // =========================================
        $display("\n[Test 3] VMAC 3D Batch=2 4x4");

        // 3a. CPU 模式
        $display("  [3a] CPU mode...");
        cycles_start = $time / 10;
        vmac_cpu_mode(4, 4, 4);
        wait_vmac_done();
        vmac_cpu_mode(4, 4, 4);
        wait_vmac_done();
        cycles_end = $time / 10;
        cycles_elapsed = cycles_end - cycles_start;
        $fwrite(fd, "%0d,VMAC_3D_batch2_4x4,CPU,%0d\n", test_id++, cycles_elapsed);
        $display("      Cycles: %0d", cycles_elapsed);

        // 3b. DMA 模式
        $display("  [3b] DMA mode...");
        prepare_matrices_in_ram(4, 4, 4, RAM_MAT_BASE);
        cycles_start = $time / 10;
        vmac_dma_mode(4, 4, 4, RAM_MAT_BASE, 2);
        wait_vmac_done();
        cycles_end = $time / 10;
        cycles_elapsed = cycles_end - cycles_start;
        $fwrite(fd, "%0d,VMAC_3D_batch2_4x4,DMA,%0d\n", test_id++, cycles_elapsed);
        $display("      Cycles: %0d", cycles_elapsed);

        // =========================================
        // 测试 4: VMAC 3D Batch (batch=4, 8x8)
        // =========================================
        $display("\n[Test 4] VMAC 3D Batch=4 8x8");

        // 4a. CPU 模式
        $display("  [4a] CPU mode...");
        cycles_start = $time / 10;
        for (i = 0; i < 4; i = i + 1) begin
            vmac_cpu_mode(8, 8, 8);
            wait_vmac_done();
        end
        cycles_end = $time / 10;
        cycles_elapsed = cycles_end - cycles_start;
        $fwrite(fd, "%0d,VMAC_3D_batch4_8x8,CPU,%0d\n", test_id++, cycles_elapsed);
        $display("      Cycles: %0d", cycles_elapsed);

        // 4b. DMA 模式
        $display("  [4b] DMA mode...");
        prepare_matrices_in_ram(8, 8, 8, RAM_MAT_BASE);
        cycles_start = $time / 10;
        vmac_dma_mode(8, 8, 8, RAM_MAT_BASE, 4);
        wait_vmac_done();
        cycles_end = $time / 10;
        cycles_elapsed = cycles_end - cycles_start;
        $fwrite(fd, "%0d,VMAC_3D_batch4_8x8,DMA,%0d\n", test_id++, cycles_elapsed);
        $display("      Cycles: %0d", cycles_elapsed);

        // =========================================
        // 测试 5: VLM 图像预处理 (112x112)
        // =========================================
        $display("\n[Test 5] VLM Image Preprocessing 112x112");

        // 5a. CPU 模式
        $display("  [5a] CPU mode...");
        cycles_start = $time / 10;
        vlm_cpu_mode();
        wait_vlm_done();
        cycles_end = $time / 10;
        cycles_elapsed = cycles_end - cycles_start;
        $fwrite(fd, "%0d,VLM_112x112,CPU,%0d\n", test_id++, cycles_elapsed);
        $display("      Cycles: %0d", cycles_elapsed);

        // 5b. DMA 模式
        $display("  [5b] DMA mode...");
        prepare_image_in_ram(RAM_IMG_BASE);
        cycles_start = $time / 10;
        vlm_dma_mode(RAM_IMG_BASE);
        wait_vlm_done();
        cycles_end = $time / 10;
        cycles_elapsed = cycles_end - cycles_start;
        $fwrite(fd, "%0d,VLM_112x112,DMA,%0d\n", test_id++, cycles_elapsed);
        $display("      Cycles: %0d", cycles_elapsed);

        $fclose(fd);
        $display("\n========================================");
        $display("  Benchmark Complete!");
        $display("  Results: tb/benchmark/benchmark_results.csv");
        $display("========================================");
        $finish;
    end

    // ========== VMAC Tasks ==========

    task vmac_cpu_mode;
        input integer m, n, k;
        integer i;
        begin
            // 配置
            dut.u_vmac.cfg_m = m;
            dut.u_vmac.cfg_n = n;
            dut.u_vmac.cfg_k = k;

            // 填充矩阵
            for (i = 0; i < 64; i = i + 1) begin
                dut.u_vmac.reg_a[i] = i + 1;
                dut.u_vmac.reg_b[i] = 64 - i;
            end

            // 触发
            dut.u_vmac.ctrl_reg = 32'h1;
            @(posedge clk);
            dut.u_vmac.ctrl_reg = 32'h0;
        end
    endtask

    task vmac_dma_mode;
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
            dut.u_vmac.ctrl_reg = 32'h2;  // DMA mode
            @(posedge clk);
            dut.u_vmac.ctrl_reg = 32'h0;
        end
    endtask

    task wait_vmac_done;
        integer timeout;
        begin
            timeout = 0;
            while (!vmac_done && timeout < 100000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
        end
    endtask

    task prepare_matrices_in_ram;
        input integer m, n, k;
        input [31:0] base_addr;
        integer i;
        begin
            for (i = 0; i < 64; i = i + 1) begin
                dut.u_ram.mem[(base_addr >> 2) + i] = i + 1;
                dut.u_ram.mem[(base_addr >> 2) + 64 + i] = 64 - i;
            end
        end
    endtask

    // ========== VLM Tasks ==========

    task vlm_cpu_mode;
        integer i;
        begin
            dut.u_vlm.vlm_start_cpu = 1;
            @(posedge clk);
            dut.u_vlm.vlm_start_cpu = 0;

            for (i = 0; i < 12544; i = i + 1) begin
                dut.u_vlm.vlm_pixel_in_cpu = (i % 256);
                dut.u_vlm.vlm_pixel_valid_cpu = 1;
                @(posedge clk);
                dut.u_vlm.vlm_pixel_valid_cpu = 0;
            end
        end
    endtask

    task vlm_dma_mode;
        input [31:0] img_addr;
        begin
            dut.u_vlm.dma_src_addr = img_addr;
            dut.u_vlm.dma_state = 1;
            dut.u_vlm.dma_mode_active = 1;
            dut.u_vlm.vlm_start_dma = 1;
            dut.u_vlm.dma_pixel_cnt = 0;
            @(posedge clk);
            dut.u_vlm.vlm_start_dma = 0;
        end
    endtask

    task wait_vlm_done;
        integer timeout;
        begin
            timeout = 0;
            while (!dut.u_vlm.vlm_done && timeout < 300000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
        end
    endtask

    task prepare_image_in_ram;
        input [31:0] base_addr;
        integer i;
        begin
            for (i = 0; i < 12544; i = i + 1) begin
                dut.u_ram.mem[(base_addr >> 2) + i] = (i % 256);
            end
        end
    endtask

    initial begin
        #500000000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
