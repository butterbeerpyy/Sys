`timescale 1ns / 1ps

// benchmark_single_vs_dual.v
// 单 DMA vs 双 DMA 完整对比测试

module benchmark_single_vs_dual;

    reg clk, resetn;

    // 单 DMA 系统
    wire trap_single, pass_single;
    wire [31:0] pass_value_single, vmac_result_single;
    wire vmac_done_single;
    wire mem_valid_single, mem_instr_single, mem_ready_single;
    wire [31:0] mem_addr_single, mem_wdata_single, mem_rdata_single;
    wire [3:0] mem_wstrb_single;

    p1_top dut_single (
        .clk(clk), .resetn(resetn),
        .trap(trap_single), .pass(pass_single), .pass_value(pass_value_single),
        .vmac_done(vmac_done_single), .vmac_result(vmac_result_single),
        .mem_valid(mem_valid_single), .mem_instr(mem_instr_single),
        .mem_ready(mem_ready_single), .mem_addr(mem_addr_single),
        .mem_wdata(mem_wdata_single), .mem_wstrb(mem_wstrb_single),
        .mem_rdata(mem_rdata_single)
    );

    // 双 DMA 系统
    wire trap_dual, pass_dual;
    wire [31:0] pass_value_dual, vmac_result_dual;
    wire vmac_done_dual;
    wire mem_valid_dual, mem_instr_dual, mem_ready_dual;
    wire [31:0] mem_addr_dual, mem_wdata_dual, mem_rdata_dual;
    wire [3:0] mem_wstrb_dual;

    p1_top_dual_dma dut_dual (
        .clk(clk), .resetn(resetn),
        .trap(trap_dual), .pass(pass_dual), .pass_value(pass_value_dual),
        .vmac_done(vmac_done_dual), .vmac_result(vmac_result_dual),
        .mem_valid(mem_valid_dual), .mem_instr(mem_instr_dual),
        .mem_ready(mem_ready_dual), .mem_addr(mem_addr_dual),
        .mem_wdata(mem_wdata_dual), .mem_wstrb(mem_wstrb_dual),
        .mem_rdata(mem_rdata_dual)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end

    localparam [31:0] RAM_MAT_BASE = 32'h0000_0400;

    integer fd;
    integer i, test_id;
    integer single_cycles, dual_cycles;

    initial begin
        $dumpfile("sim/out/benchmark_single_vs_dual.vcd");
        $dumpvars(0, benchmark_single_vs_dual);

        fd = $fopen("tb/benchmark/single_vs_dual_results.csv", "w");
        $fwrite(fd, "test_id,batch,single_cycles,dual_cycles,speedup,improvement_pct\n");

        $display("========================================");
        $display("  Single DMA vs Dual DMA Comparison");
        $display("========================================\n");

        test_id = 0;

        // 测试各种 batch 配置
        for (i = 1; i <= 8; i = i * 2) begin
            $display("[Test %0d] Batch=%0d", test_id, i);

            // 单 DMA 测试
            run_test_single(i, single_cycles);
            $display("    Single DMA: %0d cycles", single_cycles);

            // 双 DMA 测试
            run_test_dual(i, dual_cycles);
            $display("    Dual DMA:   %0d cycles", dual_cycles);

            // 计算加速比
            if (dual_cycles > 0) begin
                real speedup, improvement;
                speedup = single_cycles * 1.0 / dual_cycles;
                improvement = ((single_cycles - dual_cycles) * 100.0) / single_cycles;

                $display("    Speedup:    %.3fx", speedup);
                $display("    Improved:   %.1f%%\n", improvement);

                $fwrite(fd, "%0d,%0d,%0d,%0d,%.3f,%.2f\n",
                        test_id, i, single_cycles, dual_cycles, speedup, improvement);
            end

            test_id = test_id + 1;
        end

        $fclose(fd);
        $display("\n========================================");
        $display("  测试完成！");
        $display("  结果: tb/benchmark/single_vs_dual_results.csv");
        $display("========================================");
        $finish;
    end

    task run_test_single;
        input integer batch;
        output integer cycles;
        integer start_time, end_time, timeout;
        begin
            // 复位单 DMA 系统
            resetn = 0;
            repeat(4) @(posedge clk);
            resetn = 1;
            repeat(2) @(posedge clk);

            // 准备数据
            for (i = 0; i < 512; i = i + 1) begin
                dut_single.u_ram.mem[i] = i + 1;
            end

            // 配置 VMAC
            dut_single.u_vmac.cfg_m = 8;
            dut_single.u_vmac.cfg_n = 8;
            dut_single.u_vmac.cfg_k = 8;
            dut_single.u_vmac.cfg_a_base = RAM_MAT_BASE;
            dut_single.u_vmac.cfg_b_base = RAM_MAT_BASE + 256;
            dut_single.u_vmac.cfg_c_base = RAM_MAT_BASE + 512;
            dut_single.u_vmac.cfg_batch = batch;
            dut_single.u_vmac.cfg_a_stride = 0;
            dut_single.u_vmac.cfg_b_stride = 0;
            dut_single.u_vmac.cfg_c_stride = 0;

            // 触发 DMA
            start_time = $time / 10;
            dut_single.u_vmac.ctrl_reg = 32'h2;
            @(posedge clk);
            dut_single.u_vmac.ctrl_reg = 32'h0;

            // 等待完成
            timeout = 0;
            while (!vmac_done_single && timeout < 100000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            end_time = $time / 10;
            cycles = end_time - start_time;

            if (timeout >= 100000) begin
                $display("ERROR: Single DMA timeout!");
                cycles = -1;
            end

            // 等待一段时间
            repeat(10) @(posedge clk);
        end
    endtask

    task run_test_dual;
        input integer batch;
        output integer cycles;
        integer start_time, end_time, timeout;
        begin
            // 复位双 DMA 系统
            resetn = 0;
            repeat(4) @(posedge clk);
            resetn = 1;
            repeat(2) @(posedge clk);

            // 准备数据
            for (i = 0; i < 512; i = i + 1) begin
                dut_dual.u_ram.mem[i] = i + 1;
            end

            // 配置 VMAC
            dut_dual.u_vmac.cfg_m = 8;
            dut_dual.u_vmac.cfg_n = 8;
            dut_dual.u_vmac.cfg_k = 8;
            dut_dual.u_vmac.cfg_a_base = RAM_MAT_BASE;
            dut_dual.u_vmac.cfg_b_base = RAM_MAT_BASE + 256;
            dut_dual.u_vmac.cfg_c_base = RAM_MAT_BASE + 512;
            dut_dual.u_vmac.cfg_batch = batch;
            dut_dual.u_vmac.cfg_a_stride = 0;
            dut_dual.u_vmac.cfg_b_stride = 0;
            dut_dual.u_vmac.cfg_c_stride = 0;

            // 触发 DMA
            start_time = $time / 10;
            dut_dual.u_vmac.ctrl_reg = 32'h2;
            @(posedge clk);
            dut_dual.u_vmac.ctrl_reg = 32'h0;

            // 等待完成
            timeout = 0;
            while (!vmac_done_dual && timeout < 100000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            end_time = $time / 10;
            cycles = end_time - start_time;

            if (timeout >= 100000) begin
                $display("ERROR: Dual DMA timeout!");
                cycles = -1;
            end

            // 等待一段时间
            repeat(10) @(posedge clk);
        end
    endtask

    initial begin
        #1000000000;
        $display("GLOBAL TIMEOUT");
        $finish;
    end

endmodule
