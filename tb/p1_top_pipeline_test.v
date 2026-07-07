`timescale 1ns / 1ps

module p1_top_pipeline_test;
    reg clk;
    reg resetn;

    integer cycle_start;
    integer cycle_end;
    integer test_passed;
    reg [31:0] result;

    // 实例化顶层模块
    p1_top dut (
        .clk(clk),
        .resetn(resetn)
    );

    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 直接访问RAM的任务
    task write_ram;
        input [31:0] addr;
        input [31:0] data;
        integer word_idx;
        begin
            word_idx = addr >> 2;
            dut.u_ram.mem[word_idx] = data;
        end
    endtask

    task read_ram;
        input [31:0] addr;
        output [31:0] data;
        integer word_idx;
        begin
            word_idx = addr >> 2;
            data = dut.u_ram.mem[word_idx];
        end
    endtask

    // 写VMAC寄存器任务（通过总线）
    task write_vmac;
        input [31:0] offset;
        input [31:0] data;
        begin
            @(posedge clk);
            force dut.u_vmac.valid = 1'b1;
            force dut.u_vmac.addr = 32'h1000 + offset;
            force dut.u_vmac.wdata = data;
            force dut.u_vmac.wstrb = 4'hF;
            @(posedge clk);
            release dut.u_vmac.valid;
            release dut.u_vmac.addr;
            release dut.u_vmac.wdata;
            release dut.u_vmac.wstrb;
        end
    endtask

    initial begin
        $dumpfile("sim/out/p1_top_pipeline_test.vcd");
        $dumpvars(0, p1_top_pipeline_test);

        // 初始化
        resetn = 0;
        test_passed = 1;

        repeat(5) @(posedge clk);
        resetn = 1;
        repeat(5) @(posedge clk);

        $display("=== Pipeline DMA Test Start ===");
        $display("Testing 4 batches of 2x2 matrices");

        // 准备测试数据：4个batch的2x2矩阵
        // Batch 0: A0=[[1,2],[3,4]], B0=[[5,6],[7,8]] -> C0=[[19,22],[43,50]]
        write_ram(32'h500, 32'd1);
        write_ram(32'h504, 32'd2);
        write_ram(32'h508, 32'd3);
        write_ram(32'h50C, 32'd4);

        write_ram(32'h600, 32'd5);
        write_ram(32'h604, 32'd6);
        write_ram(32'h608, 32'd7);
        write_ram(32'h60C, 32'd8);

        // Batch 1: A1=[[2,3],[4,5]], B1=[[6,7],[8,9]] -> C1=[[36,41],[64,73]]
        write_ram(32'h510, 32'd2);
        write_ram(32'h514, 32'd3);
        write_ram(32'h518, 32'd4);
        write_ram(32'h51C, 32'd5);

        write_ram(32'h610, 32'd6);
        write_ram(32'h614, 32'd7);
        write_ram(32'h618, 32'd8);
        write_ram(32'h61C, 32'd9);

        // Batch 2: A2=[[1,1],[1,1]], B2=[[10,10],[10,10]] -> C2=[[20,20],[20,20]]
        write_ram(32'h520, 32'd1);
        write_ram(32'h524, 32'd1);
        write_ram(32'h528, 32'd1);
        write_ram(32'h52C, 32'd1);

        write_ram(32'h620, 32'd10);
        write_ram(32'h624, 32'd10);
        write_ram(32'h628, 32'd10);
        write_ram(32'h62C, 32'd10);

        // Batch 3: A3=[[2,0],[0,2]], B3=[[3,0],[0,3]] -> C3=[[6,0],[0,6]]
        write_ram(32'h530, 32'd2);
        write_ram(32'h534, 32'd0);
        write_ram(32'h538, 32'd0);
        write_ram(32'h53C, 32'd2);

        write_ram(32'h630, 32'd3);
        write_ram(32'h634, 32'd0);
        write_ram(32'h638, 32'd0);
        write_ram(32'h63C, 32'd3);

        $display("Test data prepared in RAM");

        // 配置VMAC
        write_vmac(32'hC0, 32'h500);  // cfg_a_base
        write_vmac(32'hC4, 32'h600);  // cfg_b_base
        write_vmac(32'hC8, 32'h700);  // cfg_c_base
        write_vmac(32'hCC, 32'd2);    // cfg_m = 2
        write_vmac(32'hD0, 32'd2);    // cfg_n = 2
        write_vmac(32'hD4, 32'd2);    // cfg_k = 2
        write_vmac(32'hD8, 32'd4);    // cfg_a_stride = 4
        write_vmac(32'hDC, 32'd4);    // cfg_b_stride = 4
        write_vmac(32'hE0, 32'd4);    // cfg_c_stride = 4
        write_vmac(32'hE8, 32'd4);    // cfg_batch = 4

        $display("VMAC configured for 4 batches of 2x2 matrices");

        // 启动DMA模式
        cycle_start = $time / 10;
        write_vmac(32'hE4, 32'h2);    // ctrl_reg: bit[1]=1 (DMA mode)

        $display("DMA started at time %0t", $time);

        // 等待完成
        wait(dut.u_vmac.done == 1'b1);
        cycle_end = $time / 10;

        $display("DMA completed at time %0t", $time);
        $display("Total cycles: %0d", cycle_end - cycle_start);

        // 等待几个周期
        repeat(10) @(posedge clk);

        // 验证结果
        // Batch 0: C0[0,0] should be 19
        read_ram(32'h700, result);
        if (result == 32'd19) begin
            $display("PASS: Batch 0, C[0,0] = %0d (expected 19)", result);
        end else begin
            $display("FAIL: Batch 0, C[0,0] = %0d (expected 19)", result);
            test_passed = 0;
        end

        // Batch 1: C1[0,0] should be 36
        read_ram(32'h710, result);
        if (result == 32'd36) begin
            $display("PASS: Batch 1, C[0,0] = %0d (expected 36)", result);
        end else begin
            $display("FAIL: Batch 1, C[0,0] = %0d (expected 36)", result);
            test_passed = 0;
        end

        // Batch 2: C2[0,0] should be 20
        read_ram(32'h720, result);
        if (result == 32'd20) begin
            $display("PASS: Batch 2, C[0,0] = %0d (expected 20)", result);
        end else begin
            $display("FAIL: Batch 2, C[0,0] = %0d (expected 20)", result);
            test_passed = 0;
        end

        // Batch 3: C3[0,0] should be 6
        read_ram(32'h730, result);
        if (result == 32'd6) begin
            $display("PASS: Batch 3, C[0,0] = %0d (expected 6)", result);
        end else begin
            $display("FAIL: Batch 3, C[0,0] = %0d (expected 6)", result);
            test_passed = 0;
        end

        if (test_passed) begin
            $display("=== PASS: Pipeline test completed successfully ===");
        end else begin
            $display("=== FAIL: Pipeline test failed ===");
        end

        $finish;
    end

    // 监控关键信号
    initial begin
        @(posedge resetn);
        forever @(posedge clk) begin
            if (dut.u_vmac.dma_state == 4'd7) begin  // DMA_LOAD_A_PIPE
                $display("t=%0t Pipeline LOAD_A for next batch (batch_idx=%0d, buffer_select=%0b)",
                         $time, dut.u_vmac.dma_batch_idx, dut.u_vmac.buffer_select);
            end
            if (dut.u_vmac.dma_state == 4'd8) begin  // DMA_LOAD_B_PIPE
                $display("t=%0t Pipeline LOAD_B for next batch (batch_idx=%0d)",
                         $time, dut.u_vmac.dma_batch_idx);
            end
            if (dut.u_vmac.dma_state == 4'd3 && dut.u_vmac.compute_busy) begin  // DMA_COMPUTE
                $display("t=%0t Computing batch %0d (cycle=%0d, busy=%0b)",
                         $time, dut.u_vmac.dma_batch_idx, dut.u_vmac.compute_cycle, dut.u_vmac.compute_busy);
            end
        end
    end

endmodule
