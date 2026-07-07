`timescale 1ns / 1ps

// 混合版本：位置权重 + 图像梯度

module vlm_scanner #(
    parameter IMAGE_SIZE = 112,
    parameter PATCH_SIZE = 14,
    parameter GRID_SIZE = 8
)(
    input wire clk,
    input wire rst_n,
    input wire start,

    input wire [7:0] pixel_in,
    input wire pixel_valid,

    output reg [7:0] interest_out [0:GRID_SIZE*GRID_SIZE-1],
    output reg done
);

    localparam IDLE = 2'd0;
    localparam SCAN = 2'd1;
    localparam COMPUTE = 2'd2;
    localparam DONE_STATE = 2'd3;

    reg [1:0] state;
    reg [15:0] pixel_cnt;
    reg [7:0] image_buffer [0:IMAGE_SIZE*IMAGE_SIZE-1];

    integer i, row, col, img_i, img_j;
    integer dist_r, dist_c, dist_total;
    reg [15:0] position_weight;
    reg [15:0] gradient_score;
    reg [7:0] p00, p01, p10, p11;
    reg signed [8:0] gx, gy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            pixel_cnt <= 0;
            done <= 0;
            for (i = 0; i < GRID_SIZE*GRID_SIZE; i = i + 1)
                interest_out[i] <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= SCAN;
                        pixel_cnt <= 0;
                        done <= 0;
                    end
                end

                SCAN: begin
                    if (pixel_valid) begin
                        image_buffer[pixel_cnt] <= pixel_in;
                        pixel_cnt <= pixel_cnt + 1;

                        if (pixel_cnt == IMAGE_SIZE*IMAGE_SIZE - 1) begin
                            state <= COMPUTE;
                        end
                    end
                end

                COMPUTE: begin
                    // 计算每个 patch 的兴趣度
                    for (i = 0; i < GRID_SIZE*GRID_SIZE; i = i + 1) begin
                        row = i / GRID_SIZE;
                        col = i % GRID_SIZE;

                        // === 1. 位置权重 ===
                        dist_r = (row >= 4) ? (row - 4) : (4 - row);
                        dist_c = (col >= 4) ? (col - 4) : (4 - col);
                        dist_total = dist_r + dist_c;

                        if (dist_total == 0)
                            position_weight = 16'd1000;  // 中心超高权重
                        else if (dist_total == 1)
                            position_weight = 16'd800;
                        else if (dist_total == 2)
                            position_weight = 16'd500;
                        else if (dist_total == 3)
                            position_weight = 16'd200;
                        else
                            position_weight = 16'd0;

                        // === 2. 梯度特征 ===
                        img_i = row * PATCH_SIZE + (PATCH_SIZE >> 1);
                        img_j = col * PATCH_SIZE + (PATCH_SIZE >> 1);

                        if (img_i > 0 && img_i < IMAGE_SIZE-1 &&
                            img_j > 0 && img_j < IMAGE_SIZE-1) begin
                            p00 = image_buffer[(img_i-1)*IMAGE_SIZE + (img_j-1)];
                            p01 = image_buffer[(img_i-1)*IMAGE_SIZE + (img_j+1)];
                            p10 = image_buffer[(img_i+1)*IMAGE_SIZE + (img_j-1)];
                            p11 = image_buffer[(img_i+1)*IMAGE_SIZE + (img_j+1)];

                            gx = $signed({1'b0, p01}) - $signed({1'b0, p00});
                            gy = $signed({1'b0, p11}) - $signed({1'b0, p10});

                            gradient_score = (gx[8] ? -gx : gx) + (gy[8] ? -gy : gy);
                        end else begin
                            gradient_score = 0;
                        end

                        // === 3. 混合评分 ===
                        // 位置主导（80%），梯度辅助（20%）
                        interest_out[i] <= (position_weight + (gradient_score >> 2)) >> 3;
                    end
                    state <= DONE_STATE;
                end

                DONE_STATE: begin
                    done <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
