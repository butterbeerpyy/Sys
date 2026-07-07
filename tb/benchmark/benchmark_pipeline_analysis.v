`timescale 1ns / 1ps

// benchmark_pipeline_analysis.v
// 详细分析流水线性能，包括各阶段时间分解

module benchmark_pipeline_analysis;

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

    integer fd;
    integer i, test_id;
    integer cycles_start, cycles_end, cycles_total;
    integer load_cycles, compute_cycles, store_cycles;
    integer overhead;  // 移到这里

    // 用于跟踪各阶段
    integer stage_load_start, stage_compute_start, stage_store_start;
    reg [2:0] prev_state;
    reg counting_load, counting_compute, counting_store;

    initial begin
        $dumpfile("sim/out/benchmark_pipeline_analysis.vcd");
        $dumpvars(0, benchmark_pipeline_analysis);

        fd = $fopen("tb/benchmark/pipeline_analysis.csv", "w");
        $fwrite(fd, "test_id,batch_count,mode,total_cycles,load_cycles,compute_cycles,store_cycles,overhead_cycles\n");

        $display("========================================");
        $display("  Pipeline Performance Analysis");
        $display("========================================\n");

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

        test_id = 0;

        // ========================================
        // 测试 1-3: 非流水线模式（不同 batch 数）
        // ========================================
        run_test(1, 0, test_id); test_id = test_id + 1;
        run_test(2, 0, test_id); test_id = test_id + 1;
        run_test(4, 0, test_id); test_id = test_id + 1;
        run_test(8, 0, test_id); test_id = test_id + 1;

        // ========================================
        // 测试 4-6: 流水线模式（不同 batch 数）
        // ========================================
        run_test(1, 1, test_id); test_id = test_id + 1;
        run_test(2, 1, test_id); test_id = test_id + 1;
        run_test(4, 1, test_id); test_id = test_id + 1;
        run_test(8, 1, test_id); test_id = test_id + 1;

        $fclose(fd);
        $display("\n========================================");
        $display("  Analysis Complete!");
        $display("  Results: tb/benchmark/pipeline_analysis.csv");
        $display("========================================");
        $finish;
    end

    task run_test;
        input integer batch;
        input integer pipeline;
        input integer tid;
        integer cycles;
        begin
            $display("[Test %0d] Batch=%0d, %s", tid, batch, pipeline ? "Pipeline" : "Non-Pipeline");

            // 配置
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

            // 重置计数器
            load_cycles = 0;
            compute_cycles = 0;
            store_cycles = 0;
            counting_load = 0;
            counting_compute = 0;
            counting_store = 0;
            prev_state = 0;

            // 触发
            cycles_start = $time / 10;
            if (pipeline) begin
                dut.u_vmac.ctrl_reg = 32'h6;  // DMA + Pipeline
            end else begin
                dut.u_vmac.ctrl_reg = 32'h2;  // DMA only
            end
            @(posedge clk);
            dut.u_vmac.ctrl_reg = 32'h0;

            // 等待完成并统计
            cycles = 0;
            while (!vmac_done && cycles < 50000) begin
                // 跟踪状态变化（非流水线模式）
                if (!pipeline && dut.u_vmac.dma_mode) begin
                    if (dut.u_vmac.dma_state == 3'd1 || dut.u_vmac.dma_state == 3'd2) begin
                        // LOAD_A or LOAD_B
                        if (!counting_load) begin
                            counting_load = 1;
                            counting_compute = 0;
                            counting_store = 0;
                        end
                        load_cycles = load_cycles + 1;
                    end else if (dut.u_vmac.dma_state == 3'd3) begin
                        // COMPUTE
                        if (!counting_compute) begin
                            counting_compute = 1;
                            counting_load = 0;
                            counting_store = 0;
                        end
                        compute_cycles = compute_cycles + 1;
                    end else if (dut.u_vmac.dma_state == 3'd4) begin
                        // STORE_C
                        if (!counting_store) begin
                            counting_store = 1;
                            counting_load = 0;
                            counting_compute = 0;
                        end
                        store_cycles = store_cycles + 1;
                    end
                end
                // 流水线模式类似跟踪
                else if (pipeline && dut.u_vmac.dma_mode) begin
                    if (dut.u_vmac.pipe_state == 3'd1) begin  // PIPE_LOAD
                        if (!counting_load) begin
                            counting_load = 1;
                            counting_compute = 0;
                            counting_store = 0;
                        end
                        load_cycles = load_cycles + 1;
                    end else if (dut.u_vmac.pipe_state == 3'd3) begin  // PIPE_STORE
                        if (!counting_store) begin
                            counting_store = 1;
                            counting_load = 0;
                            counting_compute = 0;
                        end
                        store_cycles = store_cycles + 1;
                    end
                    // Compute 在数据流水线中，难以精确统计
                end

                @(posedge clk);
                cycles = cycles + 1;
            end

            cycles_end = $time / 10;
            cycles_total = cycles_end - cycles_start;

            // 计算开销
            overhead = cycles_total - load_cycles - compute_cycles - store_cycles;
            if (overhead < 0) overhead = 0;

            $fwrite(fd, "%0d,%0d,%s,%0d,%0d,%0d,%0d,%0d\n",
                    tid, batch, pipeline ? "Pipeline" : "NonPipeline",
                    cycles_total, load_cycles, compute_cycles, store_cycles, overhead);

            $display("    Total: %0d cycles (Load:%0d Compute:%0d Store:%0d Overhead:%0d)",
                     cycles_total, load_cycles, compute_cycles, store_cycles, overhead);
        end
    endtask

    initial begin
        #500000000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
