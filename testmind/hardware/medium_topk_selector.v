`timescale 1ns / 1ps

// 中等 Top-K 选择器
// 输入：64 个值，输出：Top-16 的索引

module medium_topk_selector #(
    parameter NUM_VALUES = 64,
    parameter TOP_K = 16,
    parameter INDEX_WIDTH = 6  // log2(64) = 6
)(
    input wire clk,
    input wire rst_n,
    input wire start,

    input wire [7:0] values [0:NUM_VALUES-1],
    output reg [INDEX_WIDTH-1:0] topk_indices [0:TOP_K-1],
    output reg done
);

    localparam IDLE = 2'd0;
    localparam SORT = 2'd1;
    localparam DONE_STATE = 2'd2;

    reg [1:0] state;
    reg [7:0] sorted_values [0:TOP_K-1];
    reg [INDEX_WIDTH-1:0] sorted_indices [0:TOP_K-1];
    integer i, j;
    reg [7:0] temp_val;
    reg [INDEX_WIDTH-1:0] temp_idx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 0;
            for (i = 0; i < TOP_K; i = i + 1) begin
                sorted_values[i] <= 0;
                sorted_indices[i] <= 0;
                topk_indices[i] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= SORT;
                        done <= 0;

                        for (i = 0; i < TOP_K; i = i + 1) begin
                            sorted_values[i] <= values[i];
                            sorted_indices[i] <= i;
                        end
                    end
                end

                SORT: begin
                    // 简化：单周期完成
                    for (i = TOP_K; i < NUM_VALUES; i = i + 1) begin
                        if (values[i] > sorted_values[TOP_K-1]) begin
                            sorted_values[TOP_K-1] <= values[i];
                            sorted_indices[TOP_K-1] <= i;

                            for (j = TOP_K-1; j > 0; j = j - 1) begin
                                if (sorted_values[j] > sorted_values[j-1]) begin
                                    temp_val = sorted_values[j];
                                    temp_idx = sorted_indices[j];
                                    sorted_values[j] <= sorted_values[j-1];
                                    sorted_indices[j] <= sorted_indices[j-1];
                                    sorted_values[j-1] <= temp_val;
                                    sorted_indices[j-1] <= temp_idx;
                                end
                            end
                        end
                    end

                    for (i = 0; i < TOP_K; i = i + 1) begin
                        topk_indices[i] <= sorted_indices[i];
                    end

                    state <= DONE_STATE;
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
