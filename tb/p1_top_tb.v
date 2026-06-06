`timescale 1ns / 1ps

module p1_top_tb;
    localparam integer TRIALS = 8;
    localparam integer TIMEOUT_CYCLES = 5000;
    localparam integer DATA_BASE_WORD = 320;
    localparam integer DATA_BASE_ADDR = DATA_BASE_WORD * 4;
    localparam [31:0] VMAC_BASE_ADDR = 32'h0000_1000;
    localparam integer VMAC_A_WORDS = 64;
    localparam integer VMAC_B_WORDS = 64;
    localparam integer VMAC_C_WORDS = 64;
    localparam integer DATA_B_BASE_WORD = DATA_BASE_WORD + VMAC_A_WORDS;
    localparam integer DATA_B_BASE_ADDR = DATA_B_BASE_WORD * 4;
    localparam integer VMAC_B_OFFSET = VMAC_A_WORDS * 4;
    localparam integer VMAC_CTRL_OFFSET = (VMAC_A_WORDS + VMAC_B_WORDS + VMAC_C_WORDS) * 4;
    localparam integer MATRIX_DIM = 8;
    localparam integer MATRIX_WORDS = MATRIX_DIM * MATRIX_DIM;

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
    integer trial;
    integer row;
    integer col;
    integer k;
    integer slice;
    integer base;
    integer sum;
    integer cycles;
    integer p;
    integer word;
    reg [31:0] seed;
    reg vmac_done_seen;
    reg [31:0] expected [0:63];
    reg [31:0] a_vals [0:63];
    reg [31:0] b_vals [0:63];
    reg [31:0] data_mem [0:128];

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

    function [31:0] enc_lw;
        input [4:0] rd;
        input [4:0] rs1;
        input [11:0] imm;
        begin
            enc_lw = {{20{imm[11]}}, imm, rs1, 3'b010, rd, 7'b0000011};
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

    function [31:0] next_rand;
        input [31:0] state;
        reg [31:0] x;
        begin
            x = state;
            x = x ^ (x << 13);
            x = x ^ (x >> 17);
            x = x ^ (x << 5);
            next_rand = x;
        end
    endfunction

    task build_case;
        begin
            for (idx = 0; idx < 128; idx = idx + 1) begin
                seed = next_rand(seed);
                data_mem[idx] = {24'b0, (seed[7:0] & 8'h0f) + 8'd1};
            end

            for (idx = 0; idx < MATRIX_WORDS; idx = idx + 1) begin
                a_vals[idx] = data_mem[idx];
                b_vals[idx] = data_mem[MATRIX_WORDS + idx];
                expected[idx] = 32'b0;
            end

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
            for (idx = 0; idx < 256; idx = idx + 1)
                dut.u_ram.mem[idx] = 32'b0;

            for (idx = 0; idx < MATRIX_WORDS; idx = idx + 1) begin
                dut.u_ram.mem[DATA_BASE_WORD + idx] = a_vals[idx];
                dut.u_ram.mem[DATA_B_BASE_WORD + idx] = b_vals[idx];
            end

            p = 0;
            dut.u_ram.mem[p] = enc_lui(5'd10, 20'h00001); p = p + 1;
            dut.u_ram.mem[p] = enc_addi(5'd11, 5'd0, DATA_BASE_ADDR); p = p + 1;
            dut.u_ram.mem[p] = enc_addi(5'd12, 5'd0, MATRIX_DIM); p = p + 1;
            dut.u_ram.mem[p] = enc_addi(5'd13, 5'd0, MATRIX_DIM); p = p + 1;
            dut.u_ram.mem[p] = enc_addi(5'd14, 5'd0, MATRIX_DIM); p = p + 1;
            dut.u_ram.mem[p] = enc_sw(5'd12, 5'd10, 12'd256); p = p + 1;
            dut.u_ram.mem[p] = enc_sw(5'd13, 5'd10, 12'd260); p = p + 1;
            dut.u_ram.mem[p] = enc_sw(5'd14, 5'd10, 12'd264); p = p + 1;

            for (idx = 0; idx < MATRIX_WORDS; idx = idx + 1) begin
                dut.u_ram.mem[p] = enc_lw(5'd5, 5'd11, idx * 4); p = p + 1;
                dut.u_ram.mem[p] = enc_sw(5'd5, 5'd10, idx * 4); p = p + 1;
            end

            dut.u_ram.mem[p] = enc_addi(5'd11, 5'd0, DATA_B_BASE_ADDR); p = p + 1;
            for (idx = 0; idx < MATRIX_WORDS; idx = idx + 1) begin
                dut.u_ram.mem[p] = enc_lw(5'd5, 5'd11, idx * 4); p = p + 1;
                dut.u_ram.mem[p] = enc_sw(5'd5, 5'd10, VMAC_B_OFFSET + idx * 4); p = p + 1;
            end

            dut.u_ram.mem[p] = enc_addi(5'd5, 5'd0, 12'd85); p = p + 1;
            dut.u_ram.mem[p] = enc_sw(5'd5, 5'd10, VMAC_CTRL_OFFSET); p = p + 1;
            dut.u_ram.mem[p] = enc_custom0(5'd6, 5'd0, 5'd0, 7'b0000001); p = p + 1;
            dut.u_ram.mem[p] = enc_addi(5'd15, 5'd0, 12'd512); p = p + 1;
            dut.u_ram.mem[p] = enc_sw(5'd5, 5'd15, 12'd0); p = p + 1;
            dut.u_ram.mem[p] = 32'h0000_006f;
        end
    endtask

    task run_trial;
        input integer t;
        begin
            resetn = 1'b0;
            vmac_done_seen = 1'b0;
            repeat (2) @(posedge clk);

            build_case();
            load_program();

            repeat (2) @(posedge clk);
            resetn = 1'b1;

            cycles = 0;
            while (!pass && !trap && (cycles < TIMEOUT_CYCLES)) begin
                @(posedge clk);
                cycles = cycles + 1;
            end

            if (trap) begin
                $display("FAIL: trial %0d asserted CPU trap", t);
                $finish;
            end

            if (!pass) begin
                $display("FAIL: trial %0d timed out after %0d cycles", t, cycles);
                $finish;
            end

            if (!vmac_done_seen) begin
                $display("FAIL: trial %0d reached pass before VMAC done", t);
                $finish;
            end

            if (pass_value !== 32'h0000_0055) begin
                $display("FAIL: trial %0d pass_value=0x%08x expected 0x00000055", t, pass_value);
                $finish;
            end

            if (vmac_result !== expected[0]) begin
                $display("FAIL: trial %0d final VMAC c00=0x%08x expected 0x%08x", t, vmac_result, expected[0]);
                $finish;
            end

            for (idx = 0; idx < MATRIX_WORDS; idx = idx + 1) begin
                if (dut.u_vmac.reg_c[idx] !== expected[idx]) begin
                    $display("FAIL: trial %0d C[%0d]=0x%08x expected 0x%08x", t, idx, dut.u_vmac.reg_c[idx], expected[idx]);
                    $finish;
                end
            end

            for (idx = MATRIX_WORDS; idx < VMAC_C_WORDS; idx = idx + 1) begin
                if (dut.u_vmac.reg_c[idx] !== 32'b0) begin
                    $display("FAIL: trial %0d C[%0d]=0x%08x expected 0x00000000", t, idx, dut.u_vmac.reg_c[idx]);
                    $finish;
                end
            end

            for (idx = 0; idx < MATRIX_WORDS; idx = idx + 1) begin
                if (dut.u_vmac.reg_b[idx] !== b_vals[idx]) begin
                    $display("FAIL: trial %0d B[%0d]=0x%08x expected 0x%08x", t, idx, dut.u_vmac.reg_b[idx], b_vals[idx]);
                    $finish;
                end
            end

            $display("PASS: trial %0d validated randomized 8x8 matrix", t);
        end
    endtask

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("sim/out/p1_top_tb.vcd");
        $dumpvars(0, p1_top_tb);
    end

    initial begin
        resetn = 1'b0;
        vmac_done_seen = 1'b0;
        seed = 32'h1a2b_3c4d;

        for (trial = 0; trial < TRIALS; trial = trial + 1)
            run_trial(trial);

        $display("PASS: randomized 8x8 regression completed for %0d trials", TRIALS);
        $finish;
    end

    always @(posedge clk) begin
        if (resetn && mem_valid && mem_ready) begin
            $display("t=%0t instr=%0d addr=0x%08x wstrb=0x%0x wdata=0x%08x rdata=0x%08x trap=%0d",
                $time, mem_instr, mem_addr, mem_wstrb, mem_wdata, mem_rdata, trap);
        end
    end

    always @(posedge vmac_done) begin
        vmac_done_seen = 1'b1;
        $display("VMAC done: final c00=0x%08x", vmac_result);
    end
endmodule
