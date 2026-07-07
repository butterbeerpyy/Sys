`timescale 1ns / 1ps

// p1_top_vlm_test.v
// 端到端测试：直接驱动 vlm_periph 的接口，验证 VLM 预处理集成
// 不走 CPU，直接用 testbench 模拟内存访问

module p1_top_vlm_test;

    localparam integer IMAGE_SIZE   = 112;
    localparam integer IMAGE_PIXELS = IMAGE_SIZE * IMAGE_SIZE;
    localparam integer TOP_K        = 16;
    localparam integer TIMEOUT      = 300000;

    localparam [31:0] VLM_BASE   = 32'h0000_2000;
    localparam [31:0] VLM_CTRL   = VLM_BASE + 32'h000;
    localparam [31:0] VLM_PIXEL  = VLM_BASE + 32'h008;
    localparam [31:0] VLM_RESULT = VLM_BASE + 32'h100;

    reg clk, resetn;

    // 直接驱动顶层信号
    reg        tb_mem_valid;
    reg [31:0] tb_mem_addr;
    reg [31:0] tb_mem_wdata;
    reg [3:0]  tb_mem_wstrb;

    // DUT 信号
    wire trap, pass;
    wire [31:0] pass_value, vmac_result;
    wire vmac_done;
    wire mem_valid_cpu, mem_instr, mem_ready;
    wire [31:0] mem_addr_cpu, mem_wdata_cpu, mem_rdata;
    wire [3:0] mem_wstrb_cpu;

    // 合并 CPU 和 testbench 的内存访问
    wire mem_valid_mux = tb_mem_valid | mem_valid_cpu;
    wire [31:0] mem_addr_mux  = tb_mem_valid ? tb_mem_addr  : mem_addr_cpu;
    wire [31:0] mem_wdata_mux = tb_mem_valid ? tb_mem_wdata : mem_wdata_cpu;
    wire [3:0]  mem_wstrb_mux = tb_mem_valid ? tb_mem_wstrb : mem_wstrb_cpu;

    p1_top dut (
        .clk(clk), .resetn(resetn),
        .trap(trap), .pass(pass), .pass_value(pass_value),
        .vmac_done(vmac_done), .vmac_result(vmac_result),
        .mem_valid(mem_valid_mux),
        .mem_instr(1'b0),
        .mem_ready(mem_ready),
        .mem_addr(mem_addr_mux),
        .mem_wdata(mem_wdata_mux),
        .mem_wstrb(mem_wstrb_mux),
        .mem_rdata(mem_rdata)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end

    initial begin
        $dumpfile("sim/out/p1_top_vlm_test.vcd");
        $dumpvars(0, p1_top_vlm_test);
    end

    reg [7:0] test_image [0:IMAGE_PIXELS-1];
    integer i, cycles;

    // 向 VLM 外设写一个字
    task vlm_write;
        input [31:0] target_addr;
        input [31:0] data;
        begin
            tb_mem_valid = 1;
            tb_mem_addr  = target_addr;
            tb_mem_wdata = data;
            tb_mem_wstrb = 4'hF;
            @(posedge clk);
            tb_mem_valid = 0;
            tb_mem_wstrb = 4'h0;
            @(posedge clk);
        end
    endtask

    initial begin
        $display("=== VLM Integration Test ===");

        // 生成测试图案：中心亮，边缘暗
        for (i = 0; i < IMAGE_PIXELS; i = i + 1) begin
            if ((i / IMAGE_SIZE >= 40 && i / IMAGE_SIZE <= 70) &&
                (i % IMAGE_SIZE >= 40 && i % IMAGE_SIZE <= 70))
                test_image[i] = 8'hE0;
            else
                test_image[i] = 8'h20;
        end
        $display("[OK] Test pattern generated (bright center 30x30)");

        // 复位
        resetn = 0;
        tb_mem_valid = 0;
        tb_mem_addr  = 0;
        tb_mem_wdata = 0;
        tb_mem_wstrb = 0;
        repeat(4) @(posedge clk);
        resetn = 1;
        repeat(2) @(posedge clk);

        // Step 1: 触发 start
        $display("[1] Sending start...");
        vlm_write(VLM_CTRL, 32'h1);
        $display("    [OK]");

        // Step 2: 逐像素写入
        $display("[2] Writing %0d pixels...", IMAGE_PIXELS);
        for (i = 0; i < IMAGE_PIXELS; i = i + 1) begin
            vlm_write(VLM_PIXEL, {24'b0, test_image[i]});
        end
        $display("    [OK] all pixels written");

        // Step 3: 等待 done
        $display("[3] Waiting for VLM done...");
        cycles = 0;
        while (!dut.u_vlm.vlm_done && cycles < TIMEOUT) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        if (cycles >= TIMEOUT) begin
            $display("FAIL: timeout after %0d cycles", TIMEOUT);
            $finish;
        end
        $display("    [OK] done in %0d extra cycles", cycles);

        // Step 4: 读出索引并验证
        $display("[4] Reading Top-%0d indices:", TOP_K);
        begin
            reg nonzero;
            nonzero = 0;
            for (i = 0; i < TOP_K; i = i + 1) begin
                $display("    [%02d] = %0d", i, dut.u_vlm.vlm_indices[i]);
                if (dut.u_vlm.vlm_indices[i] != 0) nonzero = 1;
            end

            if (!nonzero) begin
                $display("FAIL: all indices are zero");
                $finish;
            end
        end

        $display("\n=== PASS: VLM Integration Test Completed ===");
        $finish;
    end

    initial begin
        #100000000;
        $display("FAIL: global timeout");
        $finish;
    end

endmodule
