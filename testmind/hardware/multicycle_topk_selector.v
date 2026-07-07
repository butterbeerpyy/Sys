`timescale 1ns / 1ps

// 超简化 Top-K：不排序，只找最大的 K 个

module multicycle_topk_selector #(
    parameter NUM_VALUES = 64,
    parameter TOP_K = 16,
    parameter INDEX_WIDTH = 6
)(
    input wire clk,
    input wire rst_n,
    input wire start,

    input wire [7:0] values [0:NUM_VALUES-1],
    output reg [INDEX_WIDTH-1:0] topk_indices [0:TOP_K-1],
    output reg done
);

    localparam IDLE = 2'd0;
    localparam SCAN = 2'd1;
    localparam DONE_STATE = 2'd2;

    reg [1:0] state;
    reg [7:0] scan_idx;

    // 当前找到的最小值
    reg [7:0] min_value;
    reg [INDEX_WIDTH-1:0] min_idx;

    // Top-K 数组
    reg [7:0] top_values [0:TOP_K-1];

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            scan_idx <= 0;
            done <= 0;
            for (i = 0; i < TOP_K; i = i + 1) begin
                top_values[i] <= 0;
                topk_indices[i] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= SCAN;
                        scan_idx <= 0;
                        done <= 0;
                        // 初始化为前 TOP_K 个
                        for (i = 0; i < TOP_K; i = i + 1) begin
                            top_values[i] <= values[i];
                            topk_indices[i] <= i;
                        end
                    end
                end

                SCAN: begin
                    if (scan_idx < NUM_VALUES) begin
                        // 找当前 Top-K 中的最小值
                        min_value = top_values[0];
                        min_idx = 0;
                        for (i = 1; i < TOP_K; i = i + 1) begin
                            if (top_values[i] < min_value) begin
                                min_value = top_values[i];
                                min_idx = i;
                            end
                        end

                        // 如果当前值更大，替换最小值
                        if (values[scan_idx] > min_value) begin
                            top_values[min_idx] <= values[scan_idx];
                            topk_indices[min_idx] <= scan_idx;
                        end

                        scan_idx <= scan_idx + 1;
                    end else begin
                        state <= DONE_STATE;
                    end
                end

                DONE_STATE: begin
                    done <= 1;
                    if (!start) begin
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

endmodule
