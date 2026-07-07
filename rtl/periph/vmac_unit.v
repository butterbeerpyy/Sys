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
    localparam integer A_BASE_WORD = 0;
    localparam integer B_BASE_WORD = A_BASE_WORD + A_WORDS;
    localparam integer C_BASE_WORD = B_BASE_WORD + B_WORDS;
    localparam integer CFG_A_BASE_WORD = C_BASE_WORD + C_WORDS;
    localparam integer CFG_B_BASE_WORD = CFG_A_BASE_WORD + 1;
    localparam integer CFG_C_BASE_WORD = CFG_A_BASE_WORD + 2;
    localparam integer CFG_M_WORD = CFG_A_BASE_WORD + 3;
    localparam integer CFG_N_WORD = CFG_A_BASE_WORD + 4;
    localparam integer CFG_K_WORD = CFG_A_BASE_WORD + 5;
    localparam integer CFG_A_STRIDE_WORD = CFG_A_BASE_WORD + 6;
    localparam integer CFG_B_STRIDE_WORD = CFG_A_BASE_WORD + 7;
    localparam integer CFG_C_STRIDE_WORD = CFG_A_BASE_WORD + 8;
    localparam integer CTRL_WORD = CFG_A_BASE_WORD + 9;
    localparam integer STATUS_WORD = CFG_A_BASE_WORD + 10;
    localparam integer CFG_BATCH_WORD = CFG_A_BASE_WORD + 11;
    localparam integer WINDOW_BYTES = (CFG_BATCH_WORD + 1) * 4;
    localparam [6:0] PCPI_OPCODE = 7'b0001011;
    localparam [6:0] PCPI_FUNCT7 = 7'b0000001;
    localparam [3:0] DMA_IDLE = 4'd0;
    localparam [3:0] DMA_LOAD_A = 4'd1;
    localparam [3:0] DMA_LOAD_B = 4'd2;
    localparam [3:0] DMA_COMPUTE = 4'd3;
    localparam [3:0] DMA_STORE_C = 4'd4;
    localparam [3:0] DMA_DONE = 4'd5;
    localparam [3:0] DMA_ERROR = 4'd6;
    // 流水线状态（新增）
    localparam [3:0] DMA_LOAD_A_PIPE = 4'd7;  // 流水加载A（并行计算）
    localparam [3:0] DMA_LOAD_B_PIPE = 4'd8;  // 流水加载B（并行计算）
    localparam [3:0] DMA_STORE_C_PIPE = 4'd9; // 流水存储C（并行加载）
    localparam integer DMA_TIMEOUT_MAX = 16'hFFFF;
    localparam [31:0] RAM_SIZE = 32'h0800;  // 2KB (512 words × 4 bytes)

    reg [31:0] reg_a [0:A_WORDS-1];
    reg [31:0] reg_b [0:B_WORDS-1];
    reg [31:0] reg_c [0:C_WORDS-1];

    // 双缓冲寄存器（用于流水线预加载）
    reg [31:0] reg_a_shadow [0:A_WORDS-1];
    reg [31:0] reg_b_shadow [0:B_WORDS-1];
    reg buffer_select;  // 0=使用主缓冲reg_a/b, 1=使用shadow缓冲

    // 计算状态跟踪
    reg compute_busy;        // 计算单元忙标志
    reg compute_started;     // 计算是否已启动
    reg [7:0] compute_cycle; // 计算周期计数
    reg pipeline_loading;    // 是否正在流水线加载
    localparam integer COMPUTE_LATENCY = MATRIX_DIM * MATRIX_DIM * 2; // M*N*K粗略估计

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
    reg [3:0] dma_state;  // 扩展为4位以支持流水线状态
    reg [31:0] dma_index;
    reg [31:0] dma_limit;
    reg [31:0] dma_batch_idx;
    reg [15:0] dma_timeout_cnt;
    reg dma_error;

    wire [31:0] addr_offset = addr - BASE_ADDR;
    wire [31:0] word_index = addr_offset >> 2;
    wire pcpi_match = pcpi_valid &&
        (pcpi_insn[6:0] == PCPI_OPCODE) &&
        (pcpi_insn[14:12] == 3'b000) &&
        (pcpi_insn[31:25] == PCPI_FUNCT7);

    wire [31:0] effective_m = (cfg_m == 32'b0) ? MATRIX_DIM : ((cfg_m > MATRIX_DIM) ? MATRIX_DIM : cfg_m);
    wire [31:0] effective_n = (cfg_n == 32'b0) ? MATRIX_DIM : ((cfg_n > MATRIX_DIM) ? MATRIX_DIM : cfg_n);
    wire [31:0] effective_k = (cfg_k == 32'b0) ? MATRIX_DIM : ((cfg_k > MATRIX_DIM) ? MATRIX_DIM : cfg_k);
    wire [31:0] effective_batch = (cfg_batch == 32'b0) ? 32'd1 : cfg_batch;
    wire [31:0] effective_a_stride = (cfg_a_stride == 32'b0) ? (effective_m * effective_k) : cfg_a_stride;
    wire [31:0] effective_b_stride = (cfg_b_stride == 32'b0) ? (effective_k * effective_n) : cfg_b_stride;
    wire [31:0] effective_c_stride = (cfg_c_stride == 32'b0) ? (effective_m * effective_n) : cfg_c_stride;
    wire [31:0] total_a_words = effective_a_stride;
    wire [31:0] total_b_words = effective_b_stride;
    wire [31:0] total_c_words = effective_c_stride;

    assign selected = valid && (addr >= BASE_ADDR) && (addr < BASE_ADDR + WINDOW_BYTES);
    assign ready = selected;
    assign pcpi_ready = pcpi_match && pcpi_active && done;
    assign pcpi_wait = pcpi_match && !(pcpi_active && done);
    assign pcpi_wr = pcpi_ready;
    assign pcpi_rd = result_value;

    integer i;
    integer row;
    integer col;
    integer k_idx;
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
            end else if (word_index == CFG_A_BASE_WORD) begin
                rdata = cfg_a_base;
            end else if (word_index == CFG_B_BASE_WORD) begin
                rdata = cfg_b_base;
            end else if (word_index == CFG_C_BASE_WORD) begin
                rdata = cfg_c_base;
            end else if (word_index == CFG_M_WORD) begin
                rdata = cfg_m;
            end else if (word_index == CFG_N_WORD) begin
                rdata = cfg_n;
            end else if (word_index == CFG_K_WORD) begin
                rdata = cfg_k;
            end else if (word_index == CFG_A_STRIDE_WORD) begin
                rdata = cfg_a_stride;
            end else if (word_index == CFG_B_STRIDE_WORD) begin
                rdata = cfg_b_stride;
            end else if (word_index == CFG_C_STRIDE_WORD) begin
                rdata = cfg_c_stride;
            end else if (word_index == CTRL_WORD) begin
                rdata = ctrl_reg;
            end else if (word_index == STATUS_WORD) begin
                rdata = {27'b0, dma_error, dma_active, pcpi_active, done, busy};
            end else if (word_index == CFG_BATCH_WORD) begin
                rdata = cfg_batch;
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
            // 初始化双缓冲寄存器
            for (i = 0; i < A_WORDS; i = i + 1) begin
                reg_a_shadow[i] <= 32'b0;
            end
            for (i = 0; i < B_WORDS; i = i + 1) begin
                reg_b_shadow[i] <= 32'b0;
            end
            buffer_select <= 1'b0;
            // 初始化计算状态
            compute_busy <= 1'b0;
            compute_started <= 1'b0;
            compute_cycle <= 8'b0;
            pipeline_loading <= 1'b0;
            cfg_a_base <= 32'b0;
            cfg_b_base <= 32'b0;
            cfg_c_base <= 32'b0;
            cfg_m <= 32'b0;
            cfg_n <= 32'b0;
            cfg_k <= 32'b0;
            cfg_a_stride <= 32'b0;
            cfg_b_stride <= 32'b0;
            cfg_c_stride <= 32'b0;
            cfg_batch <= 32'b0;
            ctrl_reg <= 32'b0;
            busy <= 1'b0;
            done <= 1'b0;
            pcpi_active <= 1'b0;
            done_pulse <= 1'b0;
            busy_count <= 2'b0;
            dma_mode <= 1'b0;
            dma_state <= DMA_IDLE;
            dma_index <= 32'b0;
            dma_limit <= 32'b0;
            dma_batch_idx <= 32'b0;
            dma_timeout_cnt <= 16'b0;
            dma_error <= 1'b0;
            dma_valid <= 1'b0;
            dma_we <= 1'b0;
            dma_addr <= 32'b0;
            dma_wdata <= 32'b0;
            dma_wstrb <= 4'b0;
            dma_active <= 1'b0;
            result_value <= 32'b0;
        end else begin
            done_pulse <= 1'b0;
            dma_valid <= 1'b0;
            dma_we <= 1'b0;
            dma_wstrb <= 4'b0;

            if (pcpi_match && !pcpi_active) begin
                pcpi_active <= 1'b1;
            end

            if (pcpi_match && !busy && !pcpi_active) begin
                busy <= 1'b1;
                done <= 1'b0;
                dma_error <= 1'b0;
                if (ctrl_reg[1]) begin
                    dma_mode <= 1'b1;
                    dma_state <= DMA_LOAD_A;
                    dma_index <= 32'b0;
                    dma_batch_idx <= 32'b0;
                    dma_limit <= total_a_words;
                    dma_active <= 1'b1;
                    dma_timeout_cnt <= 16'b0;
                end else begin
                    dma_mode <= 1'b0;
                    busy_count <= 2'd3;
                    dma_active <= 1'b0;
                end
            end

            if (busy) begin
                if (dma_mode) begin
                    // Timeout detection
                    if (dma_valid && !dma_ready) begin
                        if (dma_timeout_cnt >= DMA_TIMEOUT_MAX) begin
                            dma_state <= DMA_ERROR;
                            dma_error <= 1'b1;
                            dma_timeout_cnt <= 16'b0;
                        end else begin
                            dma_timeout_cnt <= dma_timeout_cnt + 1;
                        end
                    end else begin
                        dma_timeout_cnt <= 16'b0;
                    end

                    case (dma_state)
                        DMA_LOAD_A: begin
                            dma_active <= 1'b1;
                            dma_valid <= 1'b1;
                            dma_we <= 1'b0;
                            dma_addr <= cfg_a_base + (dma_batch_idx * effective_a_stride * 4) + (dma_index << 2);
                            if (dma_ready) begin
                                if (dma_index > 0) begin
                                    reg_a[dma_index - 1] <= dma_rdata;
                                end
                                if (dma_index >= dma_limit) begin
                                    dma_state <= DMA_LOAD_B;
                                    dma_index <= 32'b0;
                                    dma_limit <= total_b_words;
                                end else begin
                                    dma_index <= dma_index + 1;
                                end
                            end
                        end
                        DMA_LOAD_B: begin
                            dma_active <= 1'b1;
                            dma_valid <= 1'b1;
                            dma_we <= 1'b0;
                            dma_addr <= cfg_b_base + (dma_batch_idx * effective_b_stride * 4) + (dma_index << 2);
                            if (dma_ready) begin
                                if (dma_index > 0) begin
                                    reg_b[dma_index - 1] <= dma_rdata;
                                end
                                if (dma_index >= dma_limit) begin
                                    dma_state <= DMA_COMPUTE;
                                end else begin
                                    dma_index <= dma_index + 1;
                                end
                            end
                        end
                        DMA_COMPUTE: begin
                            // 执行矩阵乘法（组合逻辑，单周期完成）
                            c00_next = 32'b0;
                            for (row = 0; row < MATRIX_DIM; row = row + 1) begin
                                if (row < effective_m) begin
                                    for (col = 0; col < MATRIX_DIM; col = col + 1) begin
                                        if (col < effective_n) begin
                                            sum = 32'b0;
                                            for (k_idx = 0; k_idx < MATRIX_DIM; k_idx = k_idx + 1) begin
                                                if (k_idx < effective_k) begin
                                                    a_index = row * effective_k + k_idx;
                                                    b_index = k_idx * effective_n + col;
                                                    sum = sum + (buffer_select ? reg_a_shadow[a_index] : reg_a[a_index]) *
                                                                (buffer_select ? reg_b_shadow[b_index] : reg_b[b_index]);
                                                end
                                            end
                                            c_index = row * effective_n + col;
                                            reg_c[c_index] <= sum;
                                            if (row == 0 && col == 0) begin
                                                c00_next = sum;
                                            end
                                        end
                                    end
                                end
                            end
                            result_value <= c00_next;

                            // 计算完成后，检查是否需要流水线加载下一batch
                            if ((dma_batch_idx + 1 < effective_batch)) begin
                                // 有下一个batch，启动流水线预加载
                                dma_state <= DMA_LOAD_A_PIPE;
                                buffer_select <= ~buffer_select;  // 切换缓冲区
                                dma_index <= 32'b0;
                                dma_limit <= total_a_words;
                            end else begin
                                // 没有下一个batch，直接进入存储
                                dma_state <= DMA_STORE_C;
                                dma_index <= 32'b0;
                                dma_limit <= total_c_words;
                            end
                        end
                        DMA_STORE_C: begin
                            dma_active <= 1'b1;
                            dma_valid <= 1'b1;
                            dma_we <= 1'b1;
                            dma_addr <= cfg_c_base + (dma_batch_idx * effective_c_stride * 4) + (dma_index << 2);
                            dma_wdata <= reg_c[dma_index];
                            dma_wstrb <= 4'hF;
                            if (dma_ready) begin
                                dma_index <= dma_index + 1;
                                if (dma_index + 1 >= dma_limit) begin
                                    // 存储完成，递增batch索引
                                    dma_batch_idx <= dma_batch_idx + 1;
                                    // 检查是否还有更多batch
                                    if (dma_batch_idx + 1 < effective_batch) begin
                                        // 下一batch已预加载到shadow缓冲，直接计算
                                        dma_state <= DMA_COMPUTE;
                                        dma_index <= 32'b0;
                                    end else begin
                                        // 所有batch完成
                                        dma_state <= DMA_DONE;
                                    end
                                end
                            end
                        end
                        DMA_DONE: begin
                            dma_active <= 1'b0;
                            dma_mode <= 1'b0;
                            busy <= 1'b0;
                            done <= 1'b1;
                            done_pulse <= 1'b1;
                            dma_state <= DMA_IDLE;
                        end
                        DMA_ERROR: begin
                            dma_active <= 1'b0;
                            dma_mode <= 1'b0;
                            dma_valid <= 1'b0;
                            busy <= 1'b0;
                            done <= 1'b0;
                            dma_error <= 1'b1;
                            dma_state <= DMA_IDLE;
                        end
                        // 流水线加载A（并行计算）
                        DMA_LOAD_A_PIPE: begin
                            dma_active <= 1'b1;
                            dma_valid <= 1'b1;
                            dma_we <= 1'b0;
                            dma_addr <= cfg_a_base + ((dma_batch_idx + 1) * effective_a_stride * 4) + (dma_index << 2);
                            if (dma_ready) begin
                                if (dma_index > 0) begin
                                    // 根据buffer_select加载到对应缓冲区
                                    if (buffer_select)
                                        reg_a_shadow[dma_index - 1] <= dma_rdata;
                                    else
                                        reg_a[dma_index - 1] <= dma_rdata;
                                end
                                dma_index <= dma_index + 1;
                                if (dma_index + 1 >= dma_limit) begin
                                    dma_state <= DMA_LOAD_B_PIPE;
                                    dma_index <= 32'b0;
                                    dma_limit <= total_b_words;
                                end
                            end
                        end
                        // 流水线加载B（并行计算）
                        DMA_LOAD_B_PIPE: begin
                            dma_active <= 1'b1;
                            dma_valid <= 1'b1;
                            dma_we <= 1'b0;
                            dma_addr <= cfg_b_base + ((dma_batch_idx + 1) * effective_b_stride * 4) + (dma_index << 2);
                            if (dma_ready) begin
                                if (dma_index > 0) begin
                                    // 根据buffer_select加载到对应缓冲区
                                    if (buffer_select)
                                        reg_b_shadow[dma_index - 1] <= dma_rdata;
                                    else
                                        reg_b[dma_index - 1] <= dma_rdata;
                                end
                                dma_index <= dma_index + 1;
                                if (dma_index + 1 >= dma_limit) begin
                                    // 预加载完成，进入存储当前batch结果（不递增batch_idx）
                                    dma_state <= DMA_STORE_C;
                                    dma_index <= 32'b0;
                                    dma_limit <= total_c_words;
                                end
                            end
                        end
                    endcase
                end else begin
                    if (busy_count == 2'd0) begin
                        c00_next = 32'b0;
                        for (row = 0; row < MATRIX_DIM; row = row + 1) begin
                            for (col = 0; col < MATRIX_DIM; col = col + 1) begin
                                sum = 32'b0;
                                for (k_idx = 0; k_idx < MATRIX_DIM; k_idx = k_idx + 1) begin
                                    a_index = row * MATRIX_DIM + k_idx;
                                    b_index = k_idx * MATRIX_DIM + col;
                                    sum = sum + reg_a[a_index] * reg_b[b_index];
                                end
                                c_index = row * MATRIX_DIM + col;
                                reg_c[c_index] <= sum;
                                if (row == 0 && col == 0) begin
                                    c00_next = sum;
                                end
                            end
                        end

                        result_value <= c00_next;
                        busy <= 1'b0;
                        done <= 1'b1;
                        done_pulse <= 1'b1;
                    end else begin
                        busy_count <= busy_count - 2'd1;
                    end
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
                end else if (word_index == CFG_A_BASE_WORD) begin
                    // Check address bounds: base + (batch * stride * 4) + (words * 4) < RAM_SIZE
                    if (wdata < RAM_SIZE) begin
                        cfg_a_base <= wdata;
                    end
                    done <= 1'b0;
                end else if (word_index == CFG_B_BASE_WORD) begin
                    if (wdata < RAM_SIZE) begin
                        cfg_b_base <= wdata;
                    end
                    done <= 1'b0;
                end else if (word_index == CFG_C_BASE_WORD) begin
                    if (wdata < RAM_SIZE) begin
                        cfg_c_base <= wdata;
                    end
                    done <= 1'b0;
                end else if (word_index == CFG_M_WORD) begin
                    cfg_m <= wdata;
                    done <= 1'b0;
                end else if (word_index == CFG_N_WORD) begin
                    cfg_n <= wdata;
                    done <= 1'b0;
                end else if (word_index == CFG_K_WORD) begin
                    cfg_k <= wdata;
                    done <= 1'b0;
                end else if (word_index == CFG_A_STRIDE_WORD) begin
                    cfg_a_stride <= wdata;
                    done <= 1'b0;
                end else if (word_index == CFG_B_STRIDE_WORD) begin
                    cfg_b_stride <= wdata;
                    done <= 1'b0;
                end else if (word_index == CFG_C_STRIDE_WORD) begin
                    cfg_c_stride <= wdata;
                    done <= 1'b0;
                end else if (word_index == CFG_BATCH_WORD) begin
                    cfg_batch <= wdata;
                    done <= 1'b0;
                end else if (word_index == CTRL_WORD) begin
                    ctrl_reg <= wdata;
                    done <= 1'b0;
                end
            end
        end
    end
endmodule
