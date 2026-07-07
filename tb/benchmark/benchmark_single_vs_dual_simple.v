`timescale 1ns / 1ps

// benchmark_single_vs_dual_simple.v
// 简化版：分别测试单 DMA 和双 DMA

module benchmark_single_vs_dual_simple;

    reg clk, resetn;
    wire trap, pass;
    wire [31:0] pass_value, vmac_result;
    wire vmac_done;
    wire mem_valid, mem_instr, mem_ready;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire [3:0] mem_wstrb;

    // 使用参数选择测试哪个系统
`ifdef TEST_SINGLE
    p1_top dut (
        .clk(clk), .resetn(resetn),
        .trap(trap), .pass(pass), .pass_value(pass_value),
        .vmac_done(vmac_done), .vmac_result(vmac_result),
        .mem_valid(mem_valid), .mem_instr(mem_instr),
        .mem_ready(mem_ready), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata)
    );
`else
    p1_top_dual_dma dut (
        .clk(clk), .resetn(resetn),
        .trap(trap), .pass(pass), .pass_value(pass_value),
        .vmac_done(vmac_done), .vmac_result(vmac_result),
        .mem_valid(mem_valid), .mem_instr(mem_instr),
        .mem_ready(mem_ready), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata)
    );
`endif

    initial begin clk = 0; forever #5 clk = ~clk; end

    localparam [31:0] RAM_MAT_BASE = 32'h0000_0400;

    integer fd;
    integer i, test_id;
    integer cycles_start, cycles_end, cycles_elapsed;

    initial begin
        $dumpfile("sim/out/benchmark_single_vs_dual_simple.vcd");
        $dumpvars(0, benchmark_single_vs_dual_simple);

`ifdef TEST_SINGLE
        fd = $fopen("tb/benchmark/single_dma_only.csv", "w");
        $display("========================================");
        $display("  Testing: Single DMA");
        $display("========================================\n");
`else
        fd = $fopen("tb/benchmark/dual_dma_only.csv", "w");
        $display("========================================");
        $display("  Testing: Dual DMA");
        $display("========================================\n");
`endif

        $fwrite(fd, "batch,cycles\n");

        // 复位
        resetn = 0;
        repeat(4) @(posedge clk);
        resetn = 1;
        repeat(2) @(posedge clk);

        test_id = 0;

        // 测试各种 batch 配置
        for (i = 1; i <= 8; i = i * 2) begin
            $display("[Test %0d] Batch=%0d", test_id, i);
            run_test(i);
            test_id = test_id + 1;
        end

        $fclose(fd);
        $display("\n========================================");
        $display("  测试完成！");
        $display("========================================");
        $finish;
    end

    task run_test;
        input integer batch;
        integer timeout;
        begin
            // 准备数据
            for (i = 0; i < 512; i = i + 1) begin
                dut.u_ram.mem[i] = i + 1;
            end

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
            dut.u_vmac.ctrl_reg = 32'h2;
            @(posedge clk);
            dut.u_vmac.ctrl_reg = 32'h0;

            // 等待完成
            timeout = 0;
            while (!vmac_done && timeout < 50000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            cycles_end = $time / 10;
            cycles_elapsed = cycles_end - cycles_start;

            if (vmac_done) begin
                $fwrite(fd, "%0d,%0d\n", batch, cycles_elapsed);
                $display("    Cycles: %0d", cycles_elapsed);
            end else begin
                $display("    ERROR: Timeout after %0d cycles", timeout);
                $fwrite(fd, "%0d,TIMEOUT\n", batch);
            end

            // 等待一段时间
            repeat(10) @(posedge clk);
        end
    endtask

    initial begin
        #500000000;
        $display("GLOBAL TIMEOUT");
        $finish;
    end

endmodule
