`timescale 1ns / 1ps

module vmac_unit #(
    parameter [31:0] BASE_ADDR = 32'h0000_1000
) (
    input wire clk,
    input wire resetn,
    input wire valid,
    input wire [31:0] addr,
    input wire [31:0] wdata,
    input wire [3:0] wstrb,
    output wire ready,
    output reg [31:0] rdata,
    output wire selected,
    input wire pcpi_valid,
    input wire [31:0] pcpi_insn,
    input wire [31:0] pcpi_rs1,
    input wire [31:0] pcpi_rs2,
    output wire pcpi_wr,
    output wire [31:0] pcpi_rd,
    output wire pcpi_wait,
    output wire pcpi_ready,
    output reg done_pulse,
    output reg [31:0] result_value
);
    localparam integer MATRIX_DIM = 8;
    localparam integer A_WORDS = MATRIX_DIM * MATRIX_DIM;
    localparam integer B_WORDS = MATRIX_DIM * MATRIX_DIM;
    localparam integer C_WORDS = MATRIX_DIM * MATRIX_DIM;
    localparam integer A_BASE_WORD = 0;
    localparam integer B_BASE_WORD = A_BASE_WORD + A_WORDS;
    localparam integer C_BASE_WORD = B_BASE_WORD + B_WORDS;
    localparam integer CTRL_WORD = C_BASE_WORD + C_WORDS;
    localparam integer STATUS_WORD = CTRL_WORD + 1;
    localparam integer WINDOW_BYTES = (STATUS_WORD + 1) * 4;
    localparam [6:0] PCPI_OPCODE = 7'b0001011;
    localparam [6:0] PCPI_FUNCT7 = 7'b0000001;

    reg [31:0] reg_a [0:A_WORDS-1];
    reg [31:0] reg_b [0:B_WORDS-1];
    reg [31:0] reg_c [0:C_WORDS-1];
    reg [31:0] ctrl_reg;

    reg busy;
    reg done;
    reg pcpi_active;
    reg [1:0] busy_count;

    wire [31:0] addr_offset = addr - BASE_ADDR;
    wire [31:0] word_index = addr_offset >> 2;
    wire pcpi_match = pcpi_valid &&
        (pcpi_insn[6:0] == PCPI_OPCODE) &&
        (pcpi_insn[14:12] == 3'b000) &&
        (pcpi_insn[31:25] == PCPI_FUNCT7);

    assign selected = valid && (addr >= BASE_ADDR) && (addr < BASE_ADDR + WINDOW_BYTES);
    assign ready = selected;
    assign pcpi_ready = pcpi_match && pcpi_active && done;
    assign pcpi_wait = pcpi_match && !(pcpi_active && done);
    assign pcpi_wr = pcpi_ready;
    assign pcpi_rd = result_value;

    integer i;
    integer row;
    integer col;
    integer k;
    integer a_index;
    integer b_index;
    integer c_index;
    reg [31:0] sum;
    reg [31:0] c00_next;

    always @(*) begin
        rdata = 32'b0;
        if (selected) begin
            if (word_index < A_WORDS) begin
                rdata = reg_a[word_index];
            end else if (word_index >= B_BASE_WORD && word_index < B_BASE_WORD + B_WORDS) begin
                rdata = reg_b[word_index - B_BASE_WORD];
            end else if (word_index >= C_BASE_WORD && word_index < C_BASE_WORD + C_WORDS) begin
                rdata = reg_c[word_index - C_BASE_WORD];
            end else if (word_index == CTRL_WORD) begin
                rdata = ctrl_reg;
            end else if (word_index == STATUS_WORD) begin
                rdata = {29'b0, pcpi_active, done, busy};
            end
        end
    end

    always @(posedge clk) begin
        if (!resetn) begin
            for (i = 0; i < A_WORDS; i = i + 1) begin
                reg_a[i] <= 32'b0;
            end
            for (i = 0; i < B_WORDS; i = i + 1) begin
                reg_b[i] <= 32'b0;
            end
            for (i = 0; i < C_WORDS; i = i + 1) begin
                reg_c[i] <= 32'b0;
            end
            ctrl_reg <= 32'b0;
            busy <= 1'b0;
            done <= 1'b0;
            pcpi_active <= 1'b0;
            done_pulse <= 1'b0;
            busy_count <= 2'b0;
            result_value <= 32'b0;
        end else begin
            done_pulse <= 1'b0;

            if (pcpi_match && !pcpi_active) begin
                pcpi_active <= 1'b1;
            end

            if (pcpi_match && !busy && !pcpi_active) begin
                busy <= 1'b1;
                done <= 1'b0;
                busy_count <= 2'd3;
            end

            if (busy) begin
                if (busy_count == 2'd0) begin
                    for (row = 0; row < 8; row = row + 1) begin
                        for (col = 0; col < 8; col = col + 1) begin
                            sum = 32'b0;
                            for (k = 0; k < 8; k = k + 1) begin
                                sum = sum + reg_a[row * 8 + k] * reg_b[k * 8 + col];
                            end
                            reg_c[row * 8 + col] <= sum;
                            if (row == 0 && col == 0) begin
                                result_value <= sum;
                            end
                        end
                    end

                    busy <= 1'b0;
                    done <= 1'b1;
                    done_pulse <= 1'b1;
                end else begin
                    busy_count <= busy_count - 2'd1;
                end
            end

            if (pcpi_active && done && !pcpi_valid) begin
                pcpi_active <= 1'b0;
            end

            if (selected && |wstrb) begin
                if (word_index < A_WORDS) begin
                    reg_a[word_index] <= wdata;
                end else if (word_index >= B_BASE_WORD && word_index < B_BASE_WORD + B_WORDS) begin
                    reg_b[word_index - B_BASE_WORD] <= wdata;
                end else if (word_index >= C_BASE_WORD && word_index < C_BASE_WORD + C_WORDS) begin
                    reg_c[word_index - C_BASE_WORD] <= wdata;
                end else if (word_index == CTRL_WORD) begin
                    ctrl_reg <= wdata;
                    done <= 1'b0;
                    if (wdata[0]) begin
                        busy <= 1'b1;
                        busy_count <= 2'd3;
                    end
                end
            end
        end
    end
endmodule
