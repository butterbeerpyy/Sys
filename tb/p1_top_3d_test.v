`timescale 1ns / 1ps

module p1_top_3d_test;
    localparam integer TIMEOUT_CYCLES = 10000;
    localparam [31:0] VMAC_BASE_ADDR = 32'h0000_1000;
    localparam integer MATRIX_DIM = 2;
    localparam integer MATRIX_WORDS = MATRIX_DIM * MATRIX_DIM;
    localparam integer BATCH_SIZE = 2;

    // DMA addresses in RAM
    localparam [31:0] DMA_A_BASE = 32'h0000_0500;
    localparam [31:0] DMA_B_BASE = 32'h0000_0520;
    localparam [31:0] DMA_C_BASE = 32'h0000_0540;

    // VMAC register offsets
    localparam integer CFG_A_BASE_OFFSET = (64 * 3) * 4;
    localparam integer CFG_B_BASE_OFFSET = CFG_A_BASE_OFFSET + 4;
    localparam integer CFG_C_BASE_OFFSET = CFG_A_BASE_OFFSET + 8;
    localparam integer CFG_M_OFFSET = CFG_A_BASE_OFFSET + 12;
    localparam integer CFG_N_OFFSET = CFG_A_BASE_OFFSET + 16;
    localparam integer CFG_K_OFFSET = CFG_A_BASE_OFFSET + 20;
    localparam integer CFG_BATCH_OFFSET = CFG_A_BASE_OFFSET + 44;
    localparam integer CTRL_OFFSET = CFG_A_BASE_OFFSET + 36;

    reg clk;
    reg resetn;
    wire trap;
    wire pass;
    wire [31:0] pass_value;
    wire vmac_done;
    wire [31:0] vmac_result;
    wire mem_valid;
    wire mem_instr;
    wire mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0] mem_wstrb;
    wire [31:0] mem_rdata;

    integer idx;
    integer batch;
    integer row;
    integer col;
    integer k;
    integer sum;
    integer cycles;
    integer p;
    reg vmac_done_seen;
    reg [31:0] expected [0:7];  // 2 batches × 2x2 matrices

    p1_top dut (
        .clk(clk),
        .resetn(resetn),
        .trap(trap),
        .pass(pass),
        .pass_value(pass_value),
        .vmac_done(vmac_done),
        .vmac_result(vmac_result),
        .mem_valid(mem_valid),
        .mem_instr(mem_instr),
        .mem_ready(mem_ready),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata)
    );

    function [31:0] enc_lui;
        input [4:0] rd;
        input [19:0] imm;
        begin
            enc_lui = {imm, rd, 7'b0110111};
        end
    endfunction

    function [31:0] enc_addi;
        input [4:0] rd;
        input [4:0] rs1;
        input [11:0] imm;
        begin
            enc_addi = {{20{imm[11]}}, imm, rs1, 3'b000, rd, 7'b0010011};
        end
    endfunction

    function [31:0] enc_sw;
        input [4:0] rs2;
        input [4:0] rs1;
        input [11:0] imm;
        begin
            enc_sw = {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011};
        end
    endfunction

    function [31:0] enc_custom0;
        input [4:0] rd;
        input [4:0] rs1;
        input [4:0] rs2;
        input [6:0] funct7;
        begin
            enc_custom0 = {funct7, rs2, rs1, 3'b000, rd, 7'b0001011};
        end
    endfunction

    task build_test_case;
        begin
            // Batch 0: A0 = [[1,2],[3,4]], B0 = [[5,6],[7,8]]
            // Expected C0 = [[19,22],[43,50]]
            dut.u_ram.mem[(DMA_A_BASE >> 2) + 0] = 32'd1;
            dut.u_ram.mem[(DMA_A_BASE >> 2) + 1] = 32'd2;
            dut.u_ram.mem[(DMA_A_BASE >> 2) + 2] = 32'd3;
            dut.u_ram.mem[(DMA_A_BASE >> 2) + 3] = 32'd4;

            dut.u_ram.mem[(DMA_B_BASE >> 2) + 0] = 32'd5;
            dut.u_ram.mem[(DMA_B_BASE >> 2) + 1] = 32'd6;
            dut.u_ram.mem[(DMA_B_BASE >> 2) + 2] = 32'd7;
            dut.u_ram.mem[(DMA_B_BASE >> 2) + 3] = 32'd8;

            expected[0] = 32'd19;  // 1*5 + 2*7
            expected[1] = 32'd22;  // 1*6 + 2*8
            expected[2] = 32'd43;  // 3*5 + 4*7
            expected[3] = 32'd50;  // 3*6 + 4*8

            // Batch 1: A1 = [[2,3],[4,5]], B1 = [[6,7],[8,9]]
            // Expected C1 = [[36,41],[64,73]]
            dut.u_ram.mem[(DMA_A_BASE >> 2) + 4] = 32'd2;
            dut.u_ram.mem[(DMA_A_BASE >> 2) + 5] = 32'd3;
            dut.u_ram.mem[(DMA_A_BASE >> 2) + 6] = 32'd4;
            dut.u_ram.mem[(DMA_A_BASE >> 2) + 7] = 32'd5;

            dut.u_ram.mem[(DMA_B_BASE >> 2) + 4] = 32'd6;
            dut.u_ram.mem[(DMA_B_BASE >> 2) + 5] = 32'd7;
            dut.u_ram.mem[(DMA_B_BASE >> 2) + 6] = 32'd8;
            dut.u_ram.mem[(DMA_B_BASE >> 2) + 7] = 32'd9;

            expected[4] = 32'd36;  // 2*6 + 3*8
            expected[5] = 32'd41;  // 2*7 + 3*9
            expected[6] = 32'd64;  // 4*6 + 5*8
            expected[7] = 32'd73;  // 4*7 + 5*9
        end
    endtask

    task load_program;
        begin
            for (idx = 0; idx < 512; idx = idx + 1)
                dut.u_ram.mem[idx] = 32'b0;

            build_test_case();

            // Build CPU program
            p = 0;

            // x10 = VMAC_BASE (0x1000)
            dut.u_ram.mem[p] = enc_lui(5'd10, 20'h00001); p = p + 1;

            // Configure DMA base addresses
            dut.u_ram.mem[p] = enc_addi(5'd5, 5'd0, 12'h500); p = p + 1;
            dut.u_ram.mem[p] = enc_sw(5'd5, 5'd10, CFG_A_BASE_OFFSET[11:0]); p = p + 1;

            dut.u_ram.mem[p] = enc_addi(5'd5, 5'd0, 12'h520); p = p + 1;
            dut.u_ram.mem[p] = enc_sw(5'd5, 5'd10, CFG_B_BASE_OFFSET[11:0]); p = p + 1;

            dut.u_ram.mem[p] = enc_addi(5'd5, 5'd0, 12'h540); p = p + 1;
            dut.u_ram.mem[p] = enc_sw(5'd5, 5'd10, CFG_C_BASE_OFFSET[11:0]); p = p + 1;

            // Configure matrix dimensions (2x2x2)
            dut.u_ram.mem[p] = enc_addi(5'd5, 5'd0, MATRIX_DIM); p = p + 1;
            dut.u_ram.mem[p] = enc_sw(5'd5, 5'd10, CFG_M_OFFSET[11:0]); p = p + 1;
            dut.u_ram.mem[p] = enc_sw(5'd5, 5'd10, CFG_N_OFFSET[11:0]); p = p + 1;
            dut.u_ram.mem[p] = enc_sw(5'd5, 5'd10, CFG_K_OFFSET[11:0]); p = p + 1;

            // Configure batch size
            dut.u_ram.mem[p] = enc_addi(5'd5, 5'd0, BATCH_SIZE); p = p + 1;
            dut.u_ram.mem[p] = enc_sw(5'd5, 5'd10, CFG_BATCH_OFFSET[11:0]); p = p + 1;

            // Set control register: enable DMA mode (bit[1] = 1)
            dut.u_ram.mem[p] = enc_addi(5'd5, 5'd0, 12'd2); p = p + 1;
            dut.u_ram.mem[p] = enc_sw(5'd5, 5'd10, CTRL_OFFSET[11:0]); p = p + 1;

            // Trigger VMAC via PCPI custom instruction
            dut.u_ram.mem[p] = enc_custom0(5'd6, 5'd0, 5'd0, 7'b0000001); p = p + 1;

            // Write pass signature
            dut.u_ram.mem[p] = enc_addi(5'd15, 5'd0, 12'd512); p = p + 1;
            dut.u_ram.mem[p] = enc_addi(5'd5, 5'd0, 12'd85); p = p + 1;
            dut.u_ram.mem[p] = enc_sw(5'd5, 5'd15, 12'd0); p = p + 1;

            // Infinite loop
            dut.u_ram.mem[p] = 32'h0000_006f; p = p + 1;
        end
    endtask

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("sim/out/p1_top_3d_test.vcd");
        $dumpvars(0, p1_top_3d_test);
    end

    initial begin
        $display("=== 3D Batch Mode Test Start ===");
        $display("Testing %0d batches of %0dx%0d matrices", BATCH_SIZE, MATRIX_DIM, MATRIX_DIM);
        resetn = 1'b0;
        vmac_done_seen = 1'b0;

        repeat (2) @(posedge clk);

        load_program();

        repeat (2) @(posedge clk);
        resetn = 1'b1;

        cycles = 0;
        while (!pass && !trap && (cycles < TIMEOUT_CYCLES)) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        if (trap) begin
            $display("FAIL: CPU trap asserted");
            $finish;
        end

        if (!pass) begin
            $display("FAIL: timeout after %0d cycles", cycles);
            $finish;
        end

        if (!vmac_done_seen) begin
            $display("FAIL: reached pass before VMAC done");
            $finish;
        end

        // Verify all batch results in RAM
        for (batch = 0; batch < BATCH_SIZE; batch = batch + 1) begin
            for (idx = 0; idx < MATRIX_WORDS; idx = idx + 1) begin
                if (dut.u_ram.mem[(DMA_C_BASE >> 2) + batch * MATRIX_WORDS + idx] !== expected[batch * MATRIX_WORDS + idx]) begin
                    $display("FAIL: Batch %0d C[%0d] = %0d, expected %0d",
                        batch, idx,
                        dut.u_ram.mem[(DMA_C_BASE >> 2) + batch * MATRIX_WORDS + idx],
                        expected[batch * MATRIX_WORDS + idx]);
                    $finish;
                end
            end
            $display("Batch %0d verified: C[0]=%0d (expected %0d)",
                batch,
                dut.u_ram.mem[(DMA_C_BASE >> 2) + batch * MATRIX_WORDS],
                expected[batch * MATRIX_WORDS]);
        end

        $display("PASS: 3D batch test completed successfully");
        $display("      Computed in %0d cycles", cycles);
        $finish;
    end

    always @(posedge vmac_done) begin
        vmac_done_seen = 1'b1;
        $display("VMAC done: final c00=0x%08x", vmac_result);
    end

    // Monitor DMA batch progress
    always @(posedge clk) begin
        if (resetn && dut.u_vmac.dma_active && dut.u_vmac.dma_valid && dut.u_vmac.dma_ready) begin
            if (dut.u_vmac.dma_state == 3'd1 && dut.u_vmac.dma_index == 0) begin
                $display("DMA: Loading batch %0d matrix A", dut.u_vmac.dma_batch_idx);
            end else if (dut.u_vmac.dma_state == 3'd2 && dut.u_vmac.dma_index == 0) begin
                $display("DMA: Loading batch %0d matrix B", dut.u_vmac.dma_batch_idx);
            end else if (dut.u_vmac.dma_state == 3'd4 && dut.u_vmac.dma_index == 0) begin
                $display("DMA: Storing batch %0d matrix C", dut.u_vmac.dma_batch_idx);
            end
        end
    end
endmodule
