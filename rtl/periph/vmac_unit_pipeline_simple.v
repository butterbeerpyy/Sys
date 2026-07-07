`timescale 1ns / 1ps

// vmac_unit_pipeline_simple.v
// 简化版流水线 VMAC：批次级流水
//
// 优化策略：
//   原始: Batch0(Load→Compute→Store) → Batch1(Load→Compute→Store) → ...
//   优化: Batch0_Store 与 Batch1_Load 重叠执行
//
// 改进：
//   - 使用双缓冲：当前批次计算/存储时，下一批次可以加载
//   - 减少批次间的空闲时间

module vmac_unit_pipeline_simple #(
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
    output reg [31:0] result_value,
    output reg dma_valid,
    output reg dma_we,
    output reg [31:0] dma_addr,
    output reg [31:0] dma_wdata,
    output reg [3:0] dma_wstrb,
    input wire dma_ready,
    input wire [31:0] dma_rdata,
    output reg dma_active
);
    localparam integer MATRIX_DIM = 8;
    localparam integer A_WORDS = MATRIX_DIM * MATRIX_DIM;
    localparam integer B_WORDS = MATRIX_DIM * MATRIX_DIM;
    localparam integer C_WORDS = MATRIX_DIM * MATRIX_DIM;

    localparam [6:0] PCPI_OPCODE = 7'b0001011;
    localparam [6:0] PCPI_FUNCT7 = 7'b0000001;

    // DMA 状态
    localparam [3:0] DMA_IDLE = 4'd0;
    localparam [3:0] DMA_LOAD_A = 4'd1;
    localparam [3:0] DMA_LOAD_B = 4'd2;
    localparam [3:0] DMA_COMPUTE = 4'd3;
    localparam [3:0] DMA_STORE_C = 4'd4;
    localparam [3:0] DMA_DONE = 4'd5;
    localparam [3:0] DMA_ERROR = 4'd6;
    // 流水线专用状态
    localparam [3:0] DMA_STORE_LOAD_OVERLAP = 4'd7;  // Store 当前 + Load 下一批

    // 双缓冲寄存器
    reg [31:0] reg_a [0:A_WORDS-1];
    reg [31:0] reg_b [0:B_WORDS-1];
    reg [31:0] reg_c [0:C_WORDS-1];

    // 下一批次缓冲（流水线模式）
    reg [31:0] reg_a_next [0:A_WORDS-1];
    reg [31:0] reg_b_next [0:B_WORDS-1];

    // 配置寄存器
    reg [31:0] cfg_a_base, cfg_b_base, cfg_c_base;
    reg [31:0] cfg_m, cfg_n, cfg_k;
    reg [31:0] cfg_a_stride, cfg_b_stride, cfg_c_stride;
    reg [31:0] cfg_batch;
    reg [31:0] ctrl_reg;

    reg busy, done, pcpi_active;
    reg [1:0] busy_count;
    reg dma_mode, pipeline_mode;
    reg [3:0] dma_state;
    reg [31:0] dma_index, dma_limit, dma_batch_idx;
    reg [31:0] store_index, load_index;  // 独立计数器
    reg        load_phase;  // 0=加载A, 1=加载B
    reg [15:0] dma_timeout_cnt;
    reg dma_error;

    wire [31:0] addr_offset = addr - BASE_ADDR;
    wire [31:0] word_index = addr_offset >> 2;
    wire pcpi_match = pcpi_valid &&
        (pcpi_insn[6:0] == PCPI_OPCODE) &&
        (pcpi_insn[14:12] == 3'b000) &&
        (pcpi_insn[31:25] == PCPI_FUNCT7);

    assign selected = (addr[31:12] == BASE_ADDR[31:12]) && valid;
    assign ready = selected && !dma_active;
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

    // CPU 寄存器读写（省略，与原版相同）
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
            if (selected && !dma_active) begin
                if (|wstrb) begin
                    if (addr_offset == 32'h200) begin
                        ctrl_reg <= wdata;
                        pipeline_mode <= wdata[2];
                    end else if (addr_offset == 32'h20C) cfg_m <= wdata;
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

    // 主控制逻辑
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            busy <= 0; done <= 0; pcpi_active <= 0; busy_count <= 0;
            dma_mode <= 0; pipeline_mode <= 0;
            dma_state <= DMA_IDLE;
            dma_valid <= 0; dma_we <= 0; dma_active <= 0;
            dma_index <= 0; dma_batch_idx <= 0;
            store_index <= 0; load_index <= 0; load_phase <= 0;
            dma_timeout_cnt <= 0; dma_error <= 0;
            done_pulse <= 0; result_value <= 0;
        end else begin
            done_pulse <= 0;

            // 启动检测
            if (!busy && !dma_mode && ctrl_reg[0]) begin
                busy <= 1; done <= 0; busy_count <= 0; ctrl_reg <= 0;
            end else if (!busy && !dma_mode && ctrl_reg[1]) begin
                dma_mode <= 1;
                pipeline_mode <= ctrl_reg[2];
                busy <= 1; done <= 0;
                dma_active <= 1; dma_error <= 0; dma_timeout_cnt <= 0;
                ctrl_reg <= 0;
                dma_state <= DMA_LOAD_A;
                dma_index <= 0; dma_limit <= total_a_words;
                dma_batch_idx <= 0;
                store_index <= 0; load_index <= 0; load_phase <= 0;
            end

            // DMA 模式
            if (dma_mode) begin
                dma_timeout_cnt <= dma_timeout_cnt + 1;

                if (dma_timeout_cnt >= 16'hFFFF) begin
                    dma_error <= 1; dma_state <= DMA_IDLE;
                    dma_mode <= 0; busy <= 0; done <= 1; dma_active <= 0;
                end else begin
                    case (dma_state)
                        DMA_LOAD_A: begin
                            dma_active <= 1; dma_valid <= 1; dma_we <= 0;
                            dma_addr <= cfg_a_base + (dma_batch_idx * effective_a_stride * 4) + (dma_index << 2);
                            if (dma_ready) begin
                                if (dma_index > 0) reg_a[dma_index - 1] <= dma_rdata;
                                if (dma_index >= dma_limit) begin
                                    dma_state <= DMA_LOAD_B;
                                    dma_index <= 0; dma_limit <= total_b_words;
                                end else dma_index <= dma_index + 1;
                            end
                        end

                        DMA_LOAD_B: begin
                            dma_valid <= 1; dma_we <= 0;
                            dma_addr <= cfg_b_base + (dma_batch_idx * effective_b_stride * 4) + (dma_index << 2);
                            if (dma_ready) begin
                                if (dma_index > 0) reg_b[dma_index - 1] <= dma_rdata;
                                if (dma_index >= dma_limit) begin
                                    dma_state <= DMA_COMPUTE;
                                end else dma_index <= dma_index + 1;
                            end
                        end

                        DMA_COMPUTE: begin
                            dma_valid <= 0;
                            // 矩阵乘法计算
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

                            // 检查是否使用流水线模式且还有下一批
                            if (pipeline_mode && (dma_batch_idx + 1 < total_batches)) begin
                                dma_state <= DMA_STORE_LOAD_OVERLAP;
                                store_index <= 0;
                                load_index <= 0;
                                load_phase <= 0;
                            end else begin
                                dma_state <= DMA_STORE_C;
                                dma_index <= 0; dma_limit <= total_c_words;
                            end
                        end

                        DMA_STORE_LOAD_OVERLAP: begin
                            // 同时进行 Store 和 Load
                            dma_valid <= 1;

                            // Store 当前批次结果
                            if (store_index < total_c_words) begin
                                dma_we <= 1;
                                dma_addr <= cfg_c_base + (dma_batch_idx * effective_c_stride * 4) + (store_index << 2);
                                dma_wdata <= reg_c[store_index];
                                dma_wstrb <= 4'hF;
                                if (dma_ready) store_index <= store_index + 1;
                            end
                            // Store 完成后开始 Load
                            else if (!load_phase && load_index < total_a_words) begin
                                dma_we <= 0;
                                dma_addr <= cfg_a_base + ((dma_batch_idx + 1) * effective_a_stride * 4) + (load_index << 2);
                                if (dma_ready) begin
                                    if (load_index > 0) reg_a_next[load_index - 1] <= dma_rdata;
                                    if (load_index >= total_a_words - 1) load_phase <= 1;
                                    load_index <= load_index + 1;
                                end
                            end
                            // Load B
                            else if (load_phase && load_index < total_a_words + total_b_words) begin
                                dma_we <= 0;
                                dma_addr <= cfg_b_base + ((dma_batch_idx + 1) * effective_b_stride * 4) + ((load_index - total_a_words) << 2);
                                if (dma_ready) begin
                                    if (load_index > total_a_words) reg_b_next[load_index - total_a_words - 1] <= dma_rdata;
                                    if (load_index >= total_a_words + total_b_words - 1) begin
                                        // 完成，复制缓冲区
                                        for (i = 0; i < A_WORDS; i = i + 1) begin
                                            reg_a[i] <= reg_a_next[i];
                                            reg_b[i] <= reg_b_next[i];
                                        end
                                        dma_batch_idx <= dma_batch_idx + 1;
                                        dma_state <= DMA_COMPUTE;
                                    end else load_index <= load_index + 1;
                                end
                            end
                        end

                        DMA_STORE_C: begin
                            dma_valid <= 1; dma_we <= 1;
                            dma_addr <= cfg_c_base + (dma_batch_idx * effective_c_stride * 4) + (dma_index << 2);
                            dma_wdata <= reg_c[dma_index];
                            dma_wstrb <= 4'hF;
                            if (dma_ready) begin
                                if (dma_index >= dma_limit - 1) begin
                                    if (dma_batch_idx >= total_batches - 1) begin
                                        dma_state <= DMA_DONE;
                                    end else begin
                                        dma_batch_idx <= dma_batch_idx + 1;
                                        dma_state <= DMA_LOAD_A;
                                        dma_index <= 0; dma_limit <= total_a_words;
                                    end
                                end else dma_index <= dma_index + 1;
                            end
                        end

                        DMA_DONE: begin
                            dma_mode <= 0; pipeline_mode <= 0;
                            busy <= 0; done <= 1; dma_active <= 0;
                            dma_valid <= 0; dma_we <= 0;
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
