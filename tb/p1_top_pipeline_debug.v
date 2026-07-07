`timescale 1ns / 1ps

module p1_top_pipeline_debug;
    reg clk;
    reg resetn;
    integer cycle_count;

    p1_top dut (
        .clk(clk),
        .resetn(resetn)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("sim/out/p1_top_pipeline_debug.vcd");
        $dumpvars(0, p1_top_pipeline_debug);

        resetn = 0;
        cycle_count = 0;

        repeat(5) @(posedge clk);
        resetn = 1;
        repeat(5) @(posedge clk);

        $display("=== Simple Pipeline Debug Test ===");

        // 准备2个batch的2x2矩阵
        // Batch 0
        dut.u_ram.mem[128'h140] = 32'd1;  // 0x500 / 4 = 320 = 0x140
        dut.u_ram.mem[128'h141] = 32'd2;
        dut.u_ram.mem[128'h142] = 32'd3;
        dut.u_ram.mem[128'h143] = 32'd4;

        dut.u_ram.mem[128'h180] = 32'd5;  // 0x600 / 4 = 384 = 0x180
        dut.u_ram.mem[128'h181] = 32'd6;
        dut.u_ram.mem[128'h182] = 32'd7;
        dut.u_ram.mem[128'h183] = 32'd8;

        // Batch 1
        dut.u_ram.mem[128'h144] = 32'd2;  // 0x510 / 4
        dut.u_ram.mem[128'h145] = 32'd3;
        dut.u_ram.mem[128'h146] = 32'd4;
        dut.u_ram.mem[128'h147] = 32'd5;

        dut.u_ram.mem[128'h184] = 32'd6;  // 0x610 / 4
        dut.u_ram.mem[128'h185] = 32'd7;
        dut.u_ram.mem[128'h186] = 32'd8;
        dut.u_ram.mem[128'h187] = 32'd9;

        // Batch 2
        dut.u_ram.mem[128'h148] = 32'd1;
        dut.u_ram.mem[128'h149] = 32'd1;
        dut.u_ram.mem[128'h14A] = 32'd1;
        dut.u_ram.mem[128'h14B] = 32'd1;

        dut.u_ram.mem[128'h188] = 32'd10;
        dut.u_ram.mem[128'h189] = 32'd10;
        dut.u_ram.mem[128'h18A] = 32'd10;
        dut.u_ram.mem[128'h18B] = 32'd10;

        // Batch 3
        dut.u_ram.mem[128'h14C] = 32'd2;
        dut.u_ram.mem[128'h14D] = 32'd0;
        dut.u_ram.mem[128'h14E] = 32'd0;
        dut.u_ram.mem[128'h14F] = 32'd2;

        dut.u_ram.mem[128'h18C] = 32'd3;
        dut.u_ram.mem[128'h18D] = 32'd0;
        dut.u_ram.mem[128'h18E] = 32'd0;
        dut.u_ram.mem[128'h18F] = 32'd3;

        $display("Test data prepared (4 batches)");

        // 配置VMAC (通过直接写寄存器)
        @(posedge clk);
        force dut.u_vmac.cfg_a_base = 32'h500;
        force dut.u_vmac.cfg_b_base = 32'h600;
        force dut.u_vmac.cfg_c_base = 32'h700;
        force dut.u_vmac.cfg_m = 32'd2;
        force dut.u_vmac.cfg_n = 32'd2;
        force dut.u_vmac.cfg_k = 32'd2;
        force dut.u_vmac.cfg_a_stride = 32'd4;
        force dut.u_vmac.cfg_b_stride = 32'd4;
        force dut.u_vmac.cfg_c_stride = 32'd4;
        force dut.u_vmac.cfg_batch = 32'd4;  // 测试4个batch
        @(posedge clk);
        release dut.u_vmac.cfg_a_base;
        release dut.u_vmac.cfg_b_base;
        release dut.u_vmac.cfg_c_base;
        release dut.u_vmac.cfg_m;
        release dut.u_vmac.cfg_n;
        release dut.u_vmac.cfg_k;
        release dut.u_vmac.cfg_a_stride;
        release dut.u_vmac.cfg_b_stride;
        release dut.u_vmac.cfg_c_stride;
        release dut.u_vmac.cfg_batch;

        $display("VMAC configured");

        // 启动DMA
        @(posedge clk);
        force dut.u_vmac.ctrl_reg = 32'h2;
        @(posedge clk);
        release dut.u_vmac.ctrl_reg;

        $display("DMA started at time %0t", $time);
        cycle_count = 0;

        // 等待完成（最多1000个周期）
        repeat(1000) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;

            if (dut.u_vmac.done == 1'b1) begin
                $display("DMA completed at time %0t (cycles=%0d)", $time, cycle_count);

                // 验证结果
                if (dut.u_ram.mem[128'h1C0] == 32'd19) begin  // Batch 0
                    $display("PASS: Batch 0, C[0,0] = 19");
                end else begin
                    $display("FAIL: Batch 0, C[0,0] = %0d (expected 19)", dut.u_ram.mem[128'h1C0]);
                end

                if (dut.u_ram.mem[128'h1C4] == 32'd36) begin  // Batch 1
                    $display("PASS: Batch 1, C[0,0] = 36");
                end else begin
                    $display("FAIL: Batch 1, C[0,0] = %0d (expected 36)", dut.u_ram.mem[128'h1C4]);
                end

                if (dut.u_ram.mem[128'h1C8] == 32'd20) begin  // Batch 2
                    $display("PASS: Batch 2, C[0,0] = 20");
                end else begin
                    $display("FAIL: Batch 2, C[0,0] = %0d (expected 20)", dut.u_ram.mem[128'h1C8]);
                end

                if (dut.u_ram.mem[128'h1CC] == 32'd6) begin  // Batch 3
                    $display("PASS: Batch 3, C[0,0] = 6");
                end else begin
                    $display("FAIL: Batch 3, C[0,0] = %0d (expected 6)", dut.u_ram.mem[128'h1CC]);
                end

                $finish;
            end

            // 超时检测
            if (cycle_count >= 1000) begin
                $display("TIMEOUT after 1000 cycles");
                $display("Current state: dma_state=%0d, batch_idx=%0d",
                         dut.u_vmac.dma_state, dut.u_vmac.dma_batch_idx);
                $finish;
            end
        end
    end

    // 状态监控
    always @(posedge clk) begin
        if (resetn && dut.u_vmac.dma_mode) begin
            case (dut.u_vmac.dma_state)
                4'd1: if (dut.u_vmac.dma_index == 0) $display("t=%0t LOAD_A", $time);
                4'd2: if (dut.u_vmac.dma_index == 0) $display("t=%0t LOAD_B", $time);
                4'd3: $display("t=%0t COMPUTE (batch=%0d)", $time, dut.u_vmac.dma_batch_idx);
                4'd4: if (dut.u_vmac.dma_index == 0) $display("t=%0t STORE_C", $time);
                4'd5: $display("t=%0t DONE", $time);
                4'd7: if (dut.u_vmac.dma_index == 0) $display("t=%0t LOAD_A_PIPE", $time);
                4'd8: if (dut.u_vmac.dma_index == 0) $display("t=%0t LOAD_B_PIPE", $time);
            endcase
        end
    end

endmodule
