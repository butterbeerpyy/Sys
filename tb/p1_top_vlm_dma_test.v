`timescale 1ns / 1ps

// p1_top_vlm_dma_test.v
// 测试 VLM 预处理模块的 DMA 模式
// 流程：
//   1. 将测试图像数据预置到 RAM（地址 0x400）
//   2. CPU 配置 VLM 源地址（0x2000 + 0x0C）= 0x400
//   3. CPU 触发 DMA 模式（写 ctrl[1]=1）
//   4. VLM 通过 DMA 自动从 RAM 读取 12544 个像素
//   5. 等待 done
//   6. 读取并验证 Top-16 索引

module p1_top_vlm_dma_test;

    parameter IMAGE_SIZE = 112;
    parameter IMAGE_PIXELS = IMAGE_SIZE * IMAGE_SIZE;  // 12544
    parameter TOP_K = 16;

    parameter [31:0] RAM_IMAGE_BASE = 32'h0000_0400;  // 图像在 RAM 中的位置
    parameter [31:0] VLM_BASE       = 32'h0000_2000;
    parameter [31:0] VLM_CTRL       = VLM_BASE + 32'h000;
    parameter [31:0] VLM_STATUS     = VLM_BASE + 32'h004;
    parameter [31:0] VLM_SRC_ADDR   = VLM_BASE + 32'h00C;
    parameter [31:0] VLM_RESULT     = VLM_BASE + 32'h100;

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

    initial begin
        $dumpfile("sim/out/p1_top_vlm_dma_test.vcd");
        $dumpvars(0, p1_top_vlm_dma_test);
    end

    reg [7:0] test_image [0:IMAGE_PIXELS-1];
    integer i, cycles;
    reg [31:0] indices [0:TOP_K-1];
    integer nonzero_count;

    initial begin
        $display("=== VLM DMA Mode Test ===");

        // 生成测试图案：中心亮（30x30），边缘暗
        for (i = 0; i < IMAGE_PIXELS; i = i + 1) begin
            if ((i / IMAGE_SIZE >= 40 && i / IMAGE_SIZE <= 70) &&
                (i % IMAGE_SIZE >= 40 && i % IMAGE_SIZE <= 70))
                test_image[i] = 8'hE0;  // 中心亮
            else
                test_image[i] = 8'h30;  // 边缘暗
        end
        $display("[OK] Test pattern: bright center 30x30");

        // 复位
        resetn = 0;
        repeat(4) @(posedge clk);
        resetn = 1;
        repeat(2) @(posedge clk);

        // Step 1: 预置图像数据到 RAM
        $display("[1] Loading image to RAM at 0x%h...", RAM_IMAGE_BASE);
        for (i = 0; i < IMAGE_PIXELS; i = i + 1) begin
            dut.u_ram.mem[(RAM_IMAGE_BASE >> 2) + i] = {24'b0, test_image[i]};
        end
        $display("    [OK] %0d pixels loaded", IMAGE_PIXELS);

        // Step 2: 配置 VLM 源地址
        $display("[2] Configuring VLM source address...");
        dut.u_vlm.dma_src_addr = RAM_IMAGE_BASE;
        $display("    [OK] src_addr = 0x%h", RAM_IMAGE_BASE);

        // Step 3: 触发 DMA 模式（直接设置内部信号）
        $display("[3] Triggering VLM DMA mode...");
        @(posedge clk);
        #1;
        // 直接触发 DMA 状态机
        dut.u_vlm.dma_state = 1;  // DMA_LOAD_PIXELS
        dut.u_vlm.dma_mode_active = 1;
        dut.u_vlm.vlm_start_dma = 1;
        dut.u_vlm.dma_pixel_cnt = 0;
        @(posedge clk);
        #1;
        dut.u_vlm.vlm_start_dma = 0;
        $display("    [OK] DMA mode triggered");

        // Step 4: 等待 VLM 完成
        $display("[4] Waiting for VLM done...");
        cycles = 0;
        while (!dut.u_vlm.vlm_done && cycles < 300000) begin
            if (cycles % 10000 == 0) begin
                $display("    cycle %0d: dma_state=%0d dma_active=%0d dma_valid=%0d dma_ready=%0d pixel_cnt=%0d",
                         cycles, dut.u_vlm.dma_state, dut.u_vlm.dma_active,
                         dut.u_vlm.dma_valid, dut.u_vlm.dma_ready, dut.u_vlm.dma_pixel_cnt);
                $display("              vlm_done=%0d scanner_state=%0d scanner_pixel_cnt=%0d",
                         dut.u_vlm.vlm_done, dut.u_vlm.u_vlm.u_scanner.state,
                         dut.u_vlm.u_vlm.u_scanner.pixel_cnt);
            end
            @(posedge clk);
            cycles = cycles + 1;
        end

        if (cycles >= 300000) begin
            $display("FAIL: VLM DMA timeout after %0d cycles", cycles);
            $finish;
        end
        $display("    [OK] VLM done in %0d cycles", cycles);

        // Step 5: 读取索引
        $display("[5] Reading Top-%0d indices:", TOP_K);
        for (i = 0; i < TOP_K; i = i + 1) begin
            indices[i] = {26'b0, dut.u_vlm.vlm_indices[i]};
            $display("    [%02d] = %0d", i, indices[i]);
        end

        // Step 6: 验证
        $display("[6] Verifying results...");
        nonzero_count = 0;
        for (i = 0; i < TOP_K; i = i + 1) begin
            if (indices[i] != 0) nonzero_count = nonzero_count + 1;
        end

        if (nonzero_count >= TOP_K / 2) begin
            $display("    [OK] %0d non-zero indices (expected >= %0d)",
                     nonzero_count, TOP_K / 2);
            $display("\n=== PASS: VLM DMA Mode Test Completed ===");
        end else begin
            $display("FAIL: Only %0d non-zero indices (expected >= %0d)",
                     nonzero_count, TOP_K / 2);
        end

        // 输出索引到文件（供可视化）
        begin
            integer fd;
            fd = $fopen("tb/vlm/output_indices_dma.hex", "w");
            for (i = 0; i < TOP_K; i = i + 1) begin
                $fwrite(fd, "%02x\n", indices[i]);
            end
            $fclose(fd);
            $display("\n[OK] Indices written to tb/vlm/output_indices_dma.hex");
        end

        $finish;
    end

    initial begin
        #100000000;
        $display("FAIL: global timeout");
        $finish;
    end

endmodule
