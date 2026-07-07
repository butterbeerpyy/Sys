`timescale 1ns / 1ps

module p1_top_dma_test;
    localparam integer TIMEOUT_CYCLES = 5000;
    localparam [31:0] VMAC_BASE_ADDR = 32'h0000_1000;
    localparam integer MATRIX_DIM = 8;
    localparam integer MATRIX_WORDS = MATRIX_DIM * MATRIX_DIM;

    // DMA addresses in RAM
    localparam [31:0] DMA_A_BASE = 32'h0000_0500;
    localparam [31:0] DMA_B_BASE = 32'h0000_0600;
    localparam [31:0] DMA_C_BASE = 32'h0000_0700;

    // VMAC register offsets
    localparam integer CFG_A_BASE_OFFSET = (MATRIX_WORDS * 3) * 4;
    localparam integer CFG_B_BASE_OFFSET = CFG_A_BASE_OFFSET + 4;
    localparam integer CFG_C_BASE_OFFSET = CFG_A_BASE_OFFSET + 8;
    localparam integer CFG_M_OFFSET = CFG_A_BASE_OFFSET + 12;
    localparam integer CFG_N_OFFSET = CFG_A_BASE_OFFSET + 16;
    localparam integer CFG_K_OFFSET = CFG_A_BASE_OFFSET + 20;
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
    integer row;
    integer col;
    integer k;
    integer sum;
    integer cycles;
    integer p;
    reg vmac_done_seen;
    reg [31:0] expected [0:63];
    reg [31:0] a_vals [0:63];
    reg [31:0] b_vals [0:63];

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
            // Simple known test case for easier debugging
            // A = [[1,2,3,4,5,6,7,8], [2,3,4,5,6,7,8,9], ...]
            // B = [[8,7,6,5,4,3,2,1], [7,6,5,4,3,2,1,0], ...]
            for (row = 0; row < MATRIX_DIM; row = row + 1) begin
                for (col = 0; col < MATRIX_DIM; col = col + 1) begin
                    a_vals[row * MATRIX_DIM + col] = row + col + 1;
                    b_vals[row * MATRIX_DIM + col] = (MATRIX_DIM - row) + (MATRIX_DIM - col - 1);
                end
            end

            // Calculate expected result C = A × B
            for (row = 0; row < MATRIX_DIM; row = row + 1) begin
                for (col = 0; col < MATRIX_DIM; col = col + 1) begin
                    sum = 0;
                    for (k = 0; k < MATRIX_DIM; k = k + 1)
                        sum = sum + a_vals[row * MATRIX_DIM + k] * b_vals[k * MATRIX_DIM + col];
                    expected[row * MATRIX_DIM + col] = sum[31:0];
                end
            end
        end
    endtask

    task load_program;
        begin
            for (idx = 0; idx < 512; idx = idx + 1)
                dut.u_ram.mem[idx] = 32'b0;

            // Load matrix A into RAM at DMA_A_BASE
            for (idx = 0; idx < MATRIX_WORDS; idx = idx + 1) begin
                dut.u_ram.mem[(DMA_A_BASE >> 2) + idx] = a_vals[idx];
            end

            // Load matrix B into RAM at DMA_B_BASE
            for (idx = 0; idx < MATRIX_WORDS; idx = idx + 1) begin
                dut.u_ram.mem[(DMA_B_BASE >> 2) + idx] = b_vals[idx];
            end

            // Build CPU program to configure VMAC DMA mode
            p = 0;

            // x10 = VMAC_BASE (0x1000)
            dut.u_ram.mem[p] = enc_lui(5'd10, 20'h00001); p = p + 1;

            // Configure DMA base addresses
            // cfg_a_base = DMA_A_BASE (0x500)
            dut.u_ram.mem[p] = enc_addi(5'd5, 5'd0, 12'h500); p = p + 1;
            dut.u_ram.mem[p] = enc_sw(5'd5, 5'd10, CFG_A_BASE_OFFSET[11:0]); p = p + 1;

            // cfg_b_base = DMA_B_BASE (0x600)
            dut.u_ram.mem[p] = enc_addi(5'd5, 5'd0, 12'h600); p = p + 1;
            dut.u_ram.mem[p] = enc_sw(5'd5, 5'd10, CFG_B_BASE_OFFSET[11:0]); p = p + 1;

            // cfg_c_base = DMA_C_BASE (0x700)
            dut.u_ram.mem[p] = enc_addi(5'd5, 5'd0, 12'h700); p = p + 1;
            dut.u_ram.mem[p] = enc_sw(5'd5, 5'd10, CFG_C_BASE_OFFSET[11:0]); p = p + 1;

            // Configure matrix dimensions (8x8x8)
            dut.u_ram.mem[p] = enc_addi(5'd5, 5'd0, MATRIX_DIM); p = p + 1;
            dut.u_ram.mem[p] = enc_sw(5'd5, 5'd10, CFG_M_OFFSET[11:0]); p = p + 1;
            dut.u_ram.mem[p] = enc_sw(5'd5, 5'd10, CFG_N_OFFSET[11:0]); p = p + 1;
            dut.u_ram.mem[p] = enc_sw(5'd5, 5'd10, CFG_K_OFFSET[11:0]); p = p + 1;

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
        $dumpfile("sim/out/p1_top_dma_test.vcd");
        $dumpvars(0, p1_top_dma_test);
    end

    initial begin
        $display("=== DMA Mode Test Start ===");
        resetn = 1'b0;
        vmac_done_seen = 1'b0;

        repeat (2) @(posedge clk);

        build_test_case();
        load_program();

        $display("Expected C[0][0] = %0d", expected[0]);

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

        if (pass_value !== 32'h0000_0055) begin
            $display("FAIL: pass_value=0x%08x expected 0x00000055", pass_value);
            $finish;
        end

        if (vmac_result !== expected[0]) begin
            $display("FAIL: VMAC c00=0x%08x expected 0x%08x", vmac_result, expected[0]);
            $finish;
        end

        // Verify result matrix C in RAM at DMA_C_BASE
        for (idx = 0; idx < MATRIX_WORDS; idx = idx + 1) begin
            if (dut.u_ram.mem[(DMA_C_BASE >> 2) + idx] !== expected[idx]) begin
                $display("FAIL: RAM[0x%08x] = 0x%08x, expected 0x%08x",
                    DMA_C_BASE + (idx * 4),
                    dut.u_ram.mem[(DMA_C_BASE >> 2) + idx],
                    expected[idx]);
                $finish;
            end
        end

        $display("PASS: DMA mode test completed successfully");
        $display("      Computed %0d cycles", cycles);
        $finish;
    end

    always @(posedge clk) begin
        if (resetn && mem_valid && mem_ready) begin
            $display("t=%0t instr=%0d addr=0x%08x wstrb=0x%0x wdata=0x%08x rdata=0x%08x",
                $time, mem_instr, mem_addr, mem_wstrb, mem_wdata, mem_rdata);
        end
    end

    always @(posedge vmac_done) begin
        vmac_done_seen = 1'b1;
        $display("VMAC done: c00=0x%08x", vmac_result);
        $display("DEBUG: reg_a[0:7] = %0d %0d %0d %0d %0d %0d %0d %0d",
            dut.u_vmac.reg_a[0], dut.u_vmac.reg_a[1], dut.u_vmac.reg_a[2], dut.u_vmac.reg_a[3],
            dut.u_vmac.reg_a[4], dut.u_vmac.reg_a[5], dut.u_vmac.reg_a[6], dut.u_vmac.reg_a[7]);
        $display("DEBUG: reg_b[0,8,16,24,32,40,48,56] = %0d %0d %0d %0d %0d %0d %0d %0d",
            dut.u_vmac.reg_b[0], dut.u_vmac.reg_b[8], dut.u_vmac.reg_b[16], dut.u_vmac.reg_b[24],
            dut.u_vmac.reg_b[32], dut.u_vmac.reg_b[40], dut.u_vmac.reg_b[48], dut.u_vmac.reg_b[56]);
        $display("DEBUG: cfg_m=%0d cfg_n=%0d cfg_k=%0d", dut.u_vmac.cfg_m, dut.u_vmac.cfg_n, dut.u_vmac.cfg_k);
    end

    // Monitor DMA state transitions
    always @(posedge clk) begin
        if (resetn && dut.u_vmac.dma_active) begin
            $display("DMA: state=%0d idx=%0d addr=0x%08x valid=%0d we=%0d ready=%0d",
                dut.u_vmac.dma_state,
                dut.u_vmac.dma_index,
                dut.u_vmac.dma_addr,
                dut.u_vmac.dma_valid,
                dut.u_vmac.dma_we,
                dut.u_vmac.dma_ready);
        end
    end
endmodule
