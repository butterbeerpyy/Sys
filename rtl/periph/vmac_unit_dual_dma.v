`timescale 1ns / 1ps

// vmac_unit_dual_dma.v
// 支持双 DMA 通道的 VMAC
//
// 改进：Read 和 Write 使用独立的 DMA 接口，可以并行执行

module vmac_unit_dual_dma #(
    parameter [31:0] BASE_ADDR = 32'h0000_1000
) (
    input wire clk,
    input wire resetn,

    // CPU 寄存器接口
    input wire valid,
    input wire [31:0] addr,
    input wire [31:0] wdata,
    input wire [3:0] wstrb,
    output wire ready,
    output reg [31:0] rdata,
    output wire selected,

    // PCPI 接口
    input wire pcpi_valid,
    input wire [31:0] pcpi_insn,
    input wire [31:0] pcpi_rs1,
    input wire [31:0] pcpi_rs2,
    output wire pcpi_wr,
    output wire [31:0] pcpi_rd,
    output wire pcpi_wait,
    output wire pcpi_ready,

    output reg done_pulse,
    output reg [31:0] result_value,

    // DMA Read 接口（独立）
    output reg dma_rd_valid,
    output reg [31:0] dma_rd_addr,
    input wire dma_rd_ready,
    input wire [31:0] dma_rd_rdata,
    output reg dma_rd_active,

    // DMA Write 接口（独立）
    output reg dma_wr_valid,
    output reg [31:0] dma_wr_addr,
    output reg [31:0] dma_wr_wdata,
    output reg [3:0] dma_wr_wstrb,
    input wire dma_wr_ready,
    output reg dma_wr_active
);

    localparam integer MATRIX_DIM = 8;
    localparam integer A_WORDS = MATRIX_DIM * MATRIX_DIM;
    localparam integer B_WORDS = MATRIX_DIM * MATRIX_DIM;
    localparam integer C_WORDS = MATRIX_DIM * MATRIX_DIM;

    localparam [6:0] PCPI_OPCODE = 7'b0001011;
    localparam [6:0] PCPI_FUNCT7 = 7'b0000001;

    // 双 DMA 状态
    localparam [2:0] DMA_IDLE = 3'd0;
    localparam [2:0] DMA_LOAD_A = 3'd1;
    localparam [2:0] DMA_LOAD_B = 3'd2;
    localparam [2:0] DMA_COMPUTE = 3'd3;
    localparam [2:0] DMA_STORE_C = 3'd4;
    localparam [2:0] DMA_WAIT_STORE = 3'd5;  // 新增：等待 Store 完成
    localparam [2:0] DMA_DONE = 3'd6;

    reg [31:0] reg_a [0:A_WORDS-1];
    reg [31:0] reg_b [0:B_WORDS-1];
    reg [31:0] reg_c [0:C_WORDS-1];

    reg [31:0] cfg_a_base, cfg_b_base, cfg_c_base;
    reg [31:0] cfg_m, cfg_n, cfg_k;
    reg [31:0] cfg_a_stride, cfg_b_stride, cfg_c_stride;
    reg [31:0] cfg_batch;
    reg [31:0] ctrl_reg;

    reg busy, done, pcpi_active;
    reg [1:0] busy_count;
    reg dma_mode;
    reg [2:0] dma_state;
    reg [31:0] dma_rd_index, dma_wr_index;
    reg [31:0] dma_batch_idx;
    reg [15:0] dma_timeout_cnt;
    reg dma_error;

    // Store 状态
    reg store_in_progress;
    reg [31:0] store_batch_idx;

    wire [31:0] addr_offset = addr - BASE_ADDR;
    wire [31:0] word_index = addr_offset >> 2;
    wire pcpi_match = pcpi_valid &&
        (pcpi_insn[6:0] == PCPI_OPCODE) &&
        (pcpi_insn[14:12] == 3'b000) &&
        (pcpi_insn[31:25] == PCPI_FUNCT7);

    assign selected = (addr[31:12] == BASE_ADDR[31:12]) && valid;
    assign ready = selected && !dma_rd_active && !dma_wr_active;
    assign pcpi_wr = pcpi_active && done;
    assign pcpi_rd = result_value;
    assign pcpi_wait = pcpi_match && !done;
    assign pcpi_ready = pcpi_match && done;

    wire [31:0] effective_m = (cfg_m > MATRIX_DIM) ? MATRIX_DIM : cfg_m;
    wire [31:0] effective_n = (cfg_n > MATRIX_DIM) ? MATRIX_DIM : cfg_n;
    wire [31:0] effective_k = (cfg_k > MATRIX_DIM) ? MATRIX_DIM : cfg_k;
    wire [31:0] total_a_words = effective_m * effective_k;
    wire [31:0] total_b_words = effective_k * effective_n;
    wire [31:0] total_c_words = effective_m * effective_n;
    wire [31:0] effective_a_stride = (cfg_a_stride == 0) ? total_a_words : cfg_a_stride;
    wire [31:0] effective_b_stride = (cfg_b_stride == 0) ? total_b_words : cfg_b_stride;
    wire [31:0] effective_c_stride = (cfg_c_stride == 0) ? total_c_words : cfg_c_stride;
    wire [31:0] total_batches = (cfg_batch == 0) ? 1 : cfg_batch;

    integer row, col, k_idx, a_index, b_index, c_index, i;
    reg [31:0] sum, c00_next;

    // CPU 寄存器接口（省略，与原版相同）
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            ctrl_reg <= 0;
            cfg_a_base <= 0; cfg_b_base <= 0; cfg_c_base <= 0;
            cfg_m <= MATRIX_DIM; cfg_n <= MATRIX_DIM; cfg_k <= MATRIX_DIM;
            cfg_a_stride <= 0; cfg_b_stride <= 0; cfg_c_stride <= 0;
            cfg_batch <= 0;
            rdata <= 0;
            for (i = 0; i < A_WORDS; i = i + 1) begin
                reg_a[i] <= 0; reg_b[i] <= 0; reg_c[i] <= 0;
            end
        end else begin
            if (selected && !dma_rd_active && !dma_wr_active) begin
                if (|wstrb) begin
                    if (addr_offset == 32'h200) ctrl_reg <= wdata;
                    else if (addr_offset == 32'h20C) cfg_m <= wdata;
                    else if (addr_offset == 32'h210) cfg_n <= wdata;
                    else if (addr_offset == 32'h214) cfg_k <= wdata;
                    else if (addr_offset == 32'h218) cfg_a_base <= wdata;
                    else if (addr_offset == 32'h21C) cfg_b_base <= wdata;
                    else if (addr_offset == 32'h220) cfg_c_base <= wdata;
                    else if (addr_offset == 32'h224) cfg_a_stride <= wdata;
                    else if (addr_offset == 32'h228) cfg_b_stride <= wdata;
                    else if (addr_offset == 32'h22C) cfg_c_stride <= wdata;
                    else if (addr_offset == 32'h230) cfg_batch <= wdata;
                    else if (word_index < A_WORDS) reg_a[word_index] <= wdata;
                    else if (word_index >= 32 && word_index < 32 + B_WORDS) reg_b[word_index - 32] <= wdata;
                end else begin
                    if (addr_offset == 32'h204) rdata <= {30'b0, dma_error, done};
                    else if (addr_offset == 32'h208) rdata <= dma_timeout_cnt;
                    else if (word_index < A_WORDS) rdata <= reg_a[word_index];
                    else if (word_index >= 32 && word_index < 32 + B_WORDS) rdata <= reg_b[word_index - 32];
                    else if (word_index >= 64 && word_index < 64 + C_WORDS) rdata <= reg_c[word_index - 64];
                    else rdata <= 32'b0;
                end
            end
        end
    end

    // 双 DMA 控制逻辑
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            busy <= 0; done <= 0; pcpi_active <= 0; busy_count <= 0;
            dma_mode <= 0; dma_state <= DMA_IDLE;
            dma_rd_valid <= 0; dma_rd_active <= 0; dma_rd_index <= 0;
            dma_wr_valid <= 0; dma_wr_active <= 0; dma_wr_index <= 0;
            dma_batch_idx <= 0; dma_timeout_cnt <= 0; dma_error <= 0;
            done_pulse <= 0; result_value <= 0;
            store_in_progress <= 0;
        end else begin
            done_pulse <= 0;

            // 启动检测
            if (!busy && !dma_mode && ctrl_reg[0]) begin
                busy <= 1; done <= 0; busy_count <= 0; ctrl_reg <= 0;
            end else if (!busy && !dma_mode && ctrl_reg[1]) begin
                dma_mode <= 1; busy <= 1; done <= 0;
                dma_rd_active <= 1; dma_error <= 0;
                dma_timeout_cnt <= 0; ctrl_reg <= 0;
                dma_state <= DMA_LOAD_A;
                dma_rd_index <= 0; dma_batch_idx <= 0;
                store_in_progress <= 0;
            end

            // ========== 独立的 Write 通道控制 ==========
            if (store_in_progress) begin
                dma_wr_valid <= 1;
                dma_wr_addr <= cfg_c_base + (store_batch_idx * effective_c_stride * 4) + (dma_wr_index << 2);
                dma_wr_wdata <= reg_c[dma_wr_index];
                dma_wr_wstrb <= 4'hF;
                dma_wr_active <= 1;

                if (dma_wr_ready) begin
                    if (dma_wr_index >= total_c_words - 1) begin
                        store_in_progress <= 0;
                        dma_wr_valid <= 0;
                        dma_wr_active <= 0;
                        dma_wr_index <= 0;
                    end else begin
                        dma_wr_index <= dma_wr_index + 1;
                    end
                end
            end else begin
                dma_wr_valid <= 0;
            end

            // ========== Read 通道 + 计算状态机 ==========
            if (dma_mode) begin
                dma_timeout_cnt <= dma_timeout_cnt + 1;

                if (dma_timeout_cnt >= 16'hFFFF) begin
                    dma_error <= 1; dma_state <= DMA_IDLE;
                    dma_mode <= 0; busy <= 0; done <= 1;
                    dma_rd_active <= 0; dma_wr_active <= 0;
                end else begin
                    case (dma_state)
                        DMA_LOAD_A: begin
                            dma_rd_valid <= 1;
                            dma_rd_addr <= cfg_a_base + (dma_batch_idx * effective_a_stride * 4) + (dma_rd_index << 2);

                            if (dma_rd_ready) begin
                                if (dma_rd_index > 0) reg_a[dma_rd_index - 1] <= dma_rd_rdata;

                                if (dma_rd_index >= total_a_words) begin
                                    dma_state <= DMA_LOAD_B;
                                    dma_rd_index <= 0;
                                end else begin
                                    dma_rd_index <= dma_rd_index + 1;
                                end
                            end
                        end

                        DMA_LOAD_B: begin
                            dma_rd_valid <= 1;
                            dma_rd_addr <= cfg_b_base + (dma_batch_idx * effective_b_stride * 4) + (dma_rd_index << 2);

                            if (dma_rd_ready) begin
                                if (dma_rd_index > 0) reg_b[dma_rd_index - 1] <= dma_rd_rdata;

                                if (dma_rd_index >= total_b_words) begin
                                    dma_state <= DMA_COMPUTE;
                                    dma_rd_valid <= 0;
                                end else begin
                                    dma_rd_index <= dma_rd_index + 1;
                                end
                            end
                        end

                        DMA_COMPUTE: begin
                            dma_rd_valid <= 0;

                            // 计算
                            c00_next = 0;
                            for (row = 0; row < MATRIX_DIM; row = row + 1) begin
                                if (row < effective_m) begin
                                    for (col = 0; col < MATRIX_DIM; col = col + 1) begin
                                        if (col < effective_n) begin
                                            sum = 0;
                                            for (k_idx = 0; k_idx < MATRIX_DIM; k_idx = k_idx + 1) begin
                                                if (k_idx < effective_k) begin
                                                    a_index = row * MATRIX_DIM + k_idx;
                                                    b_index = k_idx * MATRIX_DIM + col;
                                                    sum = sum + reg_a[a_index] * reg_b[b_index];
                                                end
                                            end
                                            c_index = row * MATRIX_DIM + col;
                                            reg_c[c_index] <= sum;
                                            if (row == 0 && col == 0) c00_next = sum;
                                        end
                                    end
                                end
                            end

                            // 触发 Store（在独立的 Write 通道）
                            store_in_progress <= 1;
                            store_batch_idx <= dma_batch_idx;
                            dma_wr_index <= 0;

                            // 检查是否有下一个 batch
                            if (dma_batch_idx + 1 < total_batches) begin
                                // 立即开始加载下一个 batch（关键优化！）
                                dma_batch_idx <= dma_batch_idx + 1;
                                dma_state <= DMA_LOAD_A;
                                dma_rd_index <= 0;
                            end else begin
                                // 等待 Store 完成
                                dma_state <= DMA_WAIT_STORE;
                                dma_rd_active <= 0;
                            end
                        end

                        DMA_WAIT_STORE: begin
                            // 等待所有 Store 完成
                            if (!store_in_progress) begin
                                dma_state <= DMA_DONE;
                            end
                        end

                        DMA_DONE: begin
                            dma_mode <= 0; busy <= 0; done <= 1;
                            dma_rd_active <= 0; dma_wr_active <= 0;
                            done_pulse <= 1; result_value <= reg_c[0];
                            dma_state <= DMA_IDLE;
                        end

                        default: dma_state <= DMA_IDLE;
                    endcase
                end
            end

            // CPU 直写模式（保持不变）
            else if (busy && !dma_mode) begin
                if (busy_count == 0) begin
                    c00_next = 0;
                    for (row = 0; row < MATRIX_DIM; row = row + 1) begin
                        for (col = 0; col < MATRIX_DIM; col = col + 1) begin
                            sum = 0;
                            for (k_idx = 0; k_idx < MATRIX_DIM; k_idx = k_idx + 1) begin
                                a_index = row * MATRIX_DIM + k_idx;
                                b_index = k_idx * MATRIX_DIM + col;
                                sum = sum + reg_a[a_index] * reg_b[b_index];
                            end
                            c_index = row * MATRIX_DIM + col;
                            reg_c[c_index] <= sum;
                            if (row == 0 && col == 0) c00_next = sum;
                        end
                    end
                    busy_count <= busy_count + 1;
                end else if (busy_count == 1) begin
                    busy_count <= busy_count + 1;
                end else begin
                    busy <= 0; done <= 1; done_pulse <= 1; result_value <= c00_next;
                end
            end

            // PCPI 接口
            if (pcpi_match && !busy) begin
                pcpi_active <= 1; busy <= 1; done <= 0; busy_count <= 0;
            end else if (done) begin
                pcpi_active <= 0;
            end
        end
    end

endmodule
