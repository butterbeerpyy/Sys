`timescale 1ns / 1ps

module simple_ram #(
    parameter integer MEM_WORDS = 256,
    parameter [31:0] PASS_ADDR = 32'h0000_0100,
    parameter [31:0] PASS_DATA = 32'h1234_5678
) (
    input wire clk,
    input wire resetn,
    input wire valid,
    input wire instr,
    input wire [31:0] addr,
    input wire [31:0] wdata,
    input wire [3:0] wstrb,
    output wire ready,
    output reg [31:0] rdata,
    output reg pass,
    output reg [31:0] pass_value
);
    reg [31:0] mem [0:MEM_WORDS-1];
    integer i;
    integer p;
    integer m;
    integer n;
    integer k;
    integer row;
    integer col;
    integer idx;
    reg [31:0] sum;

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

    wire mem_selected;
    wire [31:0] word_index;

    assign ready = valid;
    assign mem_selected = (addr[31:2] < MEM_WORDS);
    assign word_index = addr[31:2];

    initial begin
        pass = 1'b0;
        pass_value = 32'b0;

        for (i = 0; i < MEM_WORDS; i = i + 1) begin
            mem[i] = 32'b0;
        end

        p = 0;
        m = 4;
        n = 4;

        mem[p] = enc_lui(5'd10, 20'h00001); p = p + 1;
        mem[p] = enc_addi(5'd11, 5'd0, 12'h100); p = p + 1;
        mem[p] = enc_addi(5'd12, 5'd0, m); p = p + 1;
        mem[p] = enc_addi(5'd13, 5'd0, 4); p = p + 1;
        mem[p] = enc_addi(5'd14, 5'd0, n); p = p + 1;
        mem[p] = enc_sw(5'd12, 5'd10, 12'd256); p = p + 1;
        mem[p] = enc_sw(5'd13, 5'd10, 12'd260); p = p + 1;
        mem[p] = enc_sw(5'd14, 5'd10, 12'd264); p = p + 1;

        for (row = 0; row < 4; row = row + 1) begin
            for (k = 0; k < 4; k = k + 1) begin
                idx = row * 4 + k;
                mem[p] = enc_lw(5'd5, 5'd11, idx * 4); p = p + 1;
                mem[p] = enc_sw(5'd5, 5'd10, idx * 4); p = p + 1;
            end
        end

        for (row = 0; row < 4; row = row + 1) begin
            for (col = 0; col < 4; col = col + 1) begin
                idx = row * 4 + col;
                mem[p] = enc_lw(5'd5, 5'd11, 64 + idx * 4); p = p + 1;
                mem[p] = enc_sw(5'd5, 5'd10, 64 + idx * 4); p = p + 1;
            end
        end

        mem[p] = enc_custom0(5'd6, 5'd0, 5'd0, 7'b0000001); p = p + 1;
        mem[p] = enc_addi(5'd10, 5'd0, 12'd512); p = p + 1;
        mem[p] = enc_addi(5'd5, 5'd0, 12'd85); p = p + 1;
        mem[p] = enc_sw(5'd5, 5'd10, 12'd0); p = p + 1;
        mem[p] = 32'h0000_006f;
    end

    always @(*) begin
        rdata = 32'b0;
        if (valid && mem_selected) begin
            rdata = mem[word_index];
        end
    end

    always @(posedge clk) begin
        if (!resetn) begin
            pass <= 1'b0;
            pass_value <= 32'b0;
        end else if (valid && |wstrb) begin
            if (mem_selected) begin
                if (wstrb[0]) mem[word_index][7:0] <= wdata[7:0];
                if (wstrb[1]) mem[word_index][15:8] <= wdata[15:8];
                if (wstrb[2]) mem[word_index][23:16] <= wdata[23:16];
                if (wstrb[3]) mem[word_index][31:24] <= wdata[31:24];
            end

            if (addr == PASS_ADDR && wdata == PASS_DATA) begin
                pass <= 1'b1;
                pass_value <= wdata;
            end
        end
    end
endmodule
