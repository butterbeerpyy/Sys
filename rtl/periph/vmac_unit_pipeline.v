`timescale 1ns / 1ps

// vmac_unit_pipeline.v
// 三级流水线版本的矩阵乘法加速器
//
// 流水线结构:
//   Stage 1: Load  - DMA 读取 A, B 矩阵
//   Stage 2: Compute - 矩阵乘法计算
//   Stage 3: Store - DMA 写回 C 矩阵
//
// 优势：3 个 batch 可以同时在不同阶段执行
// 原始: batch0(load+compute+store) → batch1(...) → batch2(...)
// 流水: batch0_load | batch1_load | batch2_load
//                   | batch0_compute | batch1_compute
//                                   | batch0_store

module vmac_unit_pipeline #(
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
    localparam integer CFG_BATCH_WORD = 15;
    localparam integer WINDOW_BYTES = (CFG_BATCH_WORD + 1) * 4;
    localparam [6:0] PCPI_OPCODE = 7'b0001011;
    localparam [6:0] PCPI_FUNCT7 = 7'b0000001;

    // DMA 状态（流水线版本）
    localparam [2:0] PIPE_IDLE = 3'd0;
    localparam [2:0] PIPE_LOAD = 3'd1;      // Stage 1
    localparam [2:0] PIPE_COMPUTE = 3'd2;   // Stage 2
    localparam [2:0] PIPE_STORE = 3'd3;     // Stage 3
    localparam [2:0] PIPE_DRAIN = 3'd4;     // 排空流水线
    localparam [2:0] PIPE_DONE = 3'd5;

    // 原始单阶段 DMA 状态（兼容 CPU 模式）
    localparam [2:0] DMA_IDLE = 3'd0;
    localparam [2:0] DMA_LOAD_A = 3'd1;
    localparam [2:0] DMA_LOAD_B = 3'd2;
    localparam [2:0] DMA_COMPUTE = 3'd3;
    localparam [2:0] DMA_STORE_C = 3'd4;
    localparam [2:0] DMA_DONE = 3'd5;
    localparam [2:0] DMA_ERROR = 3'd6;

    // 流水线寄存器
    // Stage 1: Load
    reg [31:0] pipe_a_load [0:A_WORDS-1];
    reg [31:0] pipe_b_load [0:B_WORDS-1];
    reg        pipe_load_valid;
    reg [31:0] pipe_load_batch_idx;

    // Stage 2: Compute
    reg [31:0] pipe_a_compute [0:A_WORDS-1];
    reg [31:0] pipe_b_compute [0:B_WORDS-1];
    reg [31:0] pipe_c_compute [0:C_WORDS-1];
    reg        pipe_compute_valid;
    reg [31:0] pipe_compute_batch_idx;

    // Stage 3: Store
    reg [31:0] pipe_c_store [0:C_WORDS-1];
    reg        pipe_store_valid;
    reg [31:0] pipe_store_batch_idx;

    // CPU 直写模式寄存器（保持兼容）
    reg [31:0] reg_a [0:A_WORDS-1];
    reg [31:0] reg_b [0:B_WORDS-1];
    reg [31:0] reg_c [0:C_WORDS-1];

    // 配置寄存器
    reg [31:0] cfg_a_base;
    reg [31:0] cfg_b_base;
    reg [31:0] cfg_c_base;
    reg [31:0] cfg_m;
    reg [31:0] cfg_n;
    reg [31:0] cfg_k;
    reg [31:0] cfg_a_stride;
    reg [31:0] cfg_b_stride;
    reg [31:0] cfg_c_stride;
    reg [31:0] cfg_batch;
    reg [31:0] ctrl_reg;

    reg busy;
    reg done;
    reg pcpi_active;
    reg [1:0] busy_count;
    reg dma_mode;
    reg pipeline_mode;  // 新增：流水线模式标志
    reg [2:0] dma_state;
    reg [2:0] pipe_state;  // 新增：流水线状态
    reg [31:0] dma_index;
    reg [31:0] dma_limit;
    reg [31:0] dma_batch_idx;
    reg [31:0] pipe_batches_issued;    // 已发射的 batch 数
    reg [31:0] pipe_batches_completed; // 已完成的 batch 数
    reg [15:0] dma_timeout_cnt;
    reg dma_error;

    // Load 阶段控制
    reg        load_phase;  // 0=加载A, 1=加载B
    reg [31:0] load_index;

    // Store 阶段控制
    reg [31:0] store_index;

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

    integer row, col, k_idx, a_index, b_index, c_index;
    reg [31:0] sum;
    reg [31:0] c00_next;

    // CPU 寄存器读写
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            ctrl_reg <= 0;
            cfg_a_base <= 0;
            cfg_b_base <= 0;
            cfg_c_base <= 0;
            cfg_m <= MATRIX_DIM;
            cfg_n <= MATRIX_DIM;
            cfg_k <= MATRIX_DIM;
            cfg_a_stride <= 0;
            cfg_b_stride <= 0;
            cfg_c_stride <= 0;
            cfg_batch <= 0;
            rdata <= 0;
            for (row = 0; row < A_WORDS; row = row + 1) begin
                reg_a[row] <= 0;
                reg_b[row] <= 0;
                reg_c[row] <= 0;
            end
        end else begin
            if (selected && !dma_active) begin
                if (|wstrb) begin
                    // 写操作
                    if (addr_offset == 32'h200) begin
                        ctrl_reg <= wdata;
                        // 检测流水线模式（bit[2]=1 表示使用流水线）
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
                    // 读操作
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
            busy <= 0;
            done <= 0;
            pcpi_active <= 0;
            busy_count <= 0;
            dma_mode <= 0;
            pipeline_mode <= 0;
            dma_state <= DMA_IDLE;
            pipe_state <= PIPE_IDLE;
            dma_valid <= 0;
            dma_we <= 0;
            dma_active <= 0;
            dma_index <= 0;
            dma_batch_idx <= 0;
            dma_timeout_cnt <= 0;
            dma_error <= 0;
            done_pulse <= 0;
            result_value <= 0;
            pipe_load_valid <= 0;
            pipe_compute_valid <= 0;
            pipe_store_valid <= 0;
            pipe_batches_issued <= 0;
            pipe_batches_completed <= 0;
            pipe_load_batch_idx <= 0;
            pipe_compute_batch_idx <= 32'hFFFFFFFF;  // 无效标记
            pipe_store_batch_idx <= 0;
            load_phase <= 0;
            load_index <= 0;
            store_index <= 0;
        end else begin
            done_pulse <= 0;

            // 启动检测
            if (!busy && !dma_mode && ctrl_reg[0]) begin
                busy <= 1;
                done <= 0;
                busy_count <= 0;
                ctrl_reg <= 0;
            end else if (!busy && !dma_mode && ctrl_reg[1]) begin
                dma_mode <= 1;
                pipeline_mode <= ctrl_reg[2];
                busy <= 1;
                done <= 0;
                dma_active <= 1;
                dma_error <= 0;
                dma_timeout_cnt <= 0;
                ctrl_reg <= 0;

                if (ctrl_reg[2]) begin
                    // 流水线模式
                    pipe_state <= PIPE_LOAD;
                    pipe_batches_issued <= 0;
                    pipe_batches_completed <= 0;
                    pipe_load_valid <= 0;
                    pipe_compute_valid <= 0;
                    pipe_store_valid <= 0;
                    pipe_compute_batch_idx <= 32'hFFFFFFFF;  // 无效标记
                    load_phase <= 0;
                    load_index <= 0;
                end else begin
                    // 非流水线 DMA 模式
                    dma_state <= DMA_LOAD_A;
                    dma_index <= 0;
                    dma_limit <= total_a_words;
                    dma_batch_idx <= 0;
                end
            end

            // ========== 流水线模式状态机 ==========
            if (dma_mode && pipeline_mode) begin
                case (pipe_state)
                    PIPE_IDLE: begin
                        // 空闲状态
                    end

                    PIPE_LOAD: begin
                        // Stage 1: Load A and B
                        dma_valid <= 1;
                        dma_we <= 0;

                        if (!load_phase) begin
                            // 加载 A
                            dma_addr <= cfg_a_base + (pipe_batches_issued * effective_a_stride * 4) + (load_index << 2);

                            if (dma_ready) begin
                                if (load_index > 0) begin
                                    pipe_a_load[load_index - 1] <= dma_rdata;
                                end

                                if (load_index >= total_a_words) begin
                                    load_phase <= 1;
                                    load_index <= 0;
                                end else begin
                                    load_index <= load_index + 1;
                                end
                            end
                        end else begin
                            // 加载 B
                            dma_addr <= cfg_b_base + (pipe_batches_issued * effective_b_stride * 4) + (load_index << 2);

                            if (dma_ready) begin
                                if (load_index > 0) begin
                                    pipe_b_load[load_index - 1] <= dma_rdata;
                                end

                                if (load_index >= total_b_words) begin
                                    // Load 完成，推入 Compute stage
                                    pipe_load_valid <= 1;
                                    pipe_load_batch_idx <= pipe_batches_issued;
                                    pipe_batches_issued <= pipe_batches_issued + 1;
                                    load_phase <= 0;
                                    load_index <= 0;
                                    dma_valid <= 0;

                                    // 转到 STORE 状态（如果有数据要存）或继续 LOAD
                                    if (pipe_store_valid) begin
                                        // 有数据需要存储，先存储
                                        pipe_state <= PIPE_STORE;
                                        store_index <= 0;
                                    end else if (pipe_batches_issued >= total_batches) begin
                                        // 所有批次都已加载，等待完成
                                        pipe_state <= PIPE_DRAIN;
                                    end else begin
                                        // 继续加载下一批
                                        pipe_state <= PIPE_LOAD;
                                    end
                                end else begin
                                    load_index <= load_index + 1;
                                end
                            end
                        end
                    end

                    PIPE_COMPUTE: begin
                        // Stage 2 在组合逻辑中完成（见下方）
                        // 这里只处理流水线推进
                        pipe_state <= PIPE_STORE;
                    end

                    PIPE_STORE: begin
                        // Stage 3: Store C
                        if (pipe_store_valid) begin
                            dma_valid <= 1;
                            dma_we <= 1;
                            dma_addr <= cfg_c_base + (pipe_store_batch_idx * effective_c_stride * 4) + (store_index << 2);
                            dma_wdata <= pipe_c_store[store_index];
                            dma_wstrb <= 4'hF;

                            if (dma_ready) begin
                                if (store_index >= total_c_words - 1) begin
                                    pipe_batches_completed <= pipe_batches_completed + 1;
                                    pipe_store_valid <= 0;
                                    store_index <= 0;
                                    dma_valid <= 0;
                                    dma_we <= 0;

                                    // Store 完成，检查是否继续加载
                                    if (pipe_batches_issued < total_batches) begin
                                        // 还有更多批次要加载
                                        pipe_state <= PIPE_LOAD;
                                    end else if (pipe_batches_completed + 1 >= total_batches) begin
                                        // 所有批次完成
                                        pipe_state <= PIPE_DONE;
                                    end else begin
                                        // 等待剩余批次完成
                                        pipe_state <= PIPE_DRAIN;
                                    end
                                end else begin
                                    store_index <= store_index + 1;
                                end
                            end
                        end else begin
                            // 没有数据要存储
                            dma_valid <= 0;
                            dma_we <= 0;

                            // 检查是否继续加载
                            if (pipe_batches_issued < total_batches) begin
                                pipe_state <= PIPE_LOAD;
                            end else begin
                                pipe_state <= PIPE_DRAIN;
                            end
                        end
                    end

                    PIPE_DRAIN: begin
                        // 排空流水线：等待所有 batch 计算和存储完成
                        if (pipe_store_valid) begin
                            // 还有数据要存储
                            pipe_state <= PIPE_STORE;
                            store_index <= 0;
                        end else if (pipe_batches_completed >= total_batches) begin
                            pipe_state <= PIPE_DONE;
                        end
                    end

                    PIPE_DONE: begin
                        dma_mode <= 0;
                        pipeline_mode <= 0;
                        busy <= 0;
                        done <= 1;
                        dma_active <= 0;
                        done_pulse <= 1;
                        result_value <= reg_c[0];
                        pipe_state <= PIPE_IDLE;
                    end

                    default: pipe_state <= PIPE_IDLE;
                endcase
            end

            // ========== 非流水线 DMA 模式（保持兼容）==========
            else if (dma_mode && !pipeline_mode) begin
                dma_timeout_cnt <= dma_timeout_cnt + 1;

                if (dma_timeout_cnt >= 16'hFFFF) begin
                    dma_error <= 1;
                    dma_state <= DMA_IDLE;
                    dma_mode <= 0;
                    busy <= 0;
                    done <= 1;
                    dma_active <= 0;
                end else begin
                    case (dma_state)
                        DMA_LOAD_A: begin
                            dma_active <= 1;
                            dma_valid <= 1;
                            dma_we <= 0;
                            dma_addr <= cfg_a_base + (dma_batch_idx * effective_a_stride * 4) + (dma_index << 2);
                            if (dma_ready) begin
                                if (dma_index > 0) reg_a[dma_index - 1] <= dma_rdata;
                                if (dma_index >= dma_limit) begin
                                    dma_state <= DMA_LOAD_B;
                                    dma_index <= 0;
                                    dma_limit <= total_b_words;
                                end else begin
                                    dma_index <= dma_index + 1;
                                end
                            end
                        end

                        DMA_LOAD_B: begin
                            dma_valid <= 1;
                            dma_we <= 0;
                            dma_addr <= cfg_b_base + (dma_batch_idx * effective_b_stride * 4) + (dma_index << 2);
                            if (dma_ready) begin
                                if (dma_index > 0) reg_b[dma_index - 1] <= dma_rdata;
                                if (dma_index >= dma_limit) begin
                                    dma_state <= DMA_COMPUTE;
                                end else begin
                                    dma_index <= dma_index + 1;
                                end
                            end
                        end

                        DMA_COMPUTE: begin
                            dma_valid <= 0;
                            // 计算在组合逻辑中完成
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
                            dma_state <= DMA_STORE_C;
                            dma_index <= 0;
                            dma_limit <= total_c_words;
                        end

                        DMA_STORE_C: begin
                            dma_valid <= 1;
                            dma_we <= 1;
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
                                        dma_index <= 0;
                                        dma_limit <= total_a_words;
                                    end
                                end else begin
                                    dma_index <= dma_index + 1;
                                end
                            end
                        end

                        DMA_DONE: begin
                            dma_mode <= 0;
                            busy <= 0;
                            done <= 1;
                            dma_active <= 0;
                            dma_valid <= 0;
                            dma_we <= 0;
                            done_pulse <= 1;
                            result_value <= reg_c[0];
                            dma_state <= DMA_IDLE;
                        end

                        default: dma_state <= DMA_IDLE;
                    endcase
                end
            end

            // ========== CPU 直写模式（保持兼容）==========
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
                    busy <= 0;
                    done <= 1;
                    done_pulse <= 1;
                    result_value <= c00_next;
                end
            end

            // PCPI 接口
            if (pcpi_match && !busy) begin
                pcpi_active <= 1;
                busy <= 1;
                done <= 0;
                busy_count <= 0;
            end else if (done) begin
                pcpi_active <= 0;
            end

            // ========== 流水线推进逻辑 ==========
            // Stage 1 → Stage 2
            if (pipe_load_valid) begin
                for (row = 0; row < A_WORDS; row = row + 1) begin
                    pipe_a_compute[row] <= pipe_a_load[row];
                    pipe_b_compute[row] <= pipe_b_load[row];
                end
                pipe_compute_valid <= 1;
                pipe_compute_batch_idx <= pipe_load_batch_idx;
                pipe_load_valid <= 0;
            end

            // Stage 2 → Stage 3 (Compute) - 需要2周期避免时序问题
            if (pipe_compute_valid) begin
                // 第1周期：计算并写入 pipe_c_compute
                for (row = 0; row < MATRIX_DIM; row = row + 1) begin
                    if (row < effective_m) begin
                        for (col = 0; col < MATRIX_DIM; col = col + 1) begin
                            if (col < effective_n) begin
                                sum = 0;
                                for (k_idx = 0; k_idx < MATRIX_DIM; k_idx = k_idx + 1) begin
                                    if (k_idx < effective_k) begin
                                        a_index = row * MATRIX_DIM + k_idx;
                                        b_index = k_idx * MATRIX_DIM + col;
                                        sum = sum + pipe_a_compute[a_index] * pipe_b_compute[b_index];
                                    end
                                end
                                c_index = row * MATRIX_DIM + col;
                                pipe_c_compute[c_index] <= sum;
                            end
                        end
                    end
                end
                pipe_compute_valid <= 0;
                // 不在同一周期复制，等下一周期
            end else if (pipe_compute_batch_idx != 32'hFFFFFFFF && !pipe_store_valid) begin
                // 第2周期：从 pipe_c_compute 复制到 pipe_c_store
                for (row = 0; row < C_WORDS; row = row + 1) begin
                    pipe_c_store[row] <= pipe_c_compute[row];
                end
                pipe_store_valid <= 1;
                pipe_store_batch_idx <= pipe_compute_batch_idx;
                pipe_compute_batch_idx <= 32'hFFFFFFFF;  // 标记已处理
            end
        end
    end

endmodule
