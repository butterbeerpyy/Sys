`timescale 1ns / 1ps

// 简化版：逐周期计算，强中心权重

module improved_coarse_scanner #(
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
    reg [7:0] patch_idx;

    reg [7:0] cur_row, cur_col;
    reg [15:0] cur_img_i, cur_img_j;
    reg [15:0] grad;
    reg [7:0] base_weight;
    reg [7:0] dist;

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            pixel_cnt <= 0;
            patch_idx <= 0;
            done <= 0;
            for (i = 0; i < GRID_SIZE*GRID_SIZE; i = i + 1)
                interest_out[i] <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= SCAN;
                        pixel_cnt <= 0;
                        patch_idx <= 0;
                        done <= 0;
                    end
                end

                SCAN: begin
                    if (pixel_valid) begin
                        image_buffer[pixel_cnt] <= pixel_in;
                        pixel_cnt <= pixel_cnt + 1;

                        if (pixel_cnt == IMAGE_SIZE*IMAGE_SIZE - 1) begin
                            state <= COMPUTE;
                            patch_idx <= 0;
                        end
                    end
                end

                COMPUTE: begin
                    if (patch_idx < GRID_SIZE * GRID_SIZE) begin
                        // 计算 row, col
                        cur_row <= patch_idx / GRID_SIZE;
                        cur_col <= patch_idx % GRID_SIZE;

                        // 计算图像坐标
                        cur_img_i <= cur_row * PATCH_SIZE + (PATCH_SIZE >> 1);
                        cur_img_j <= cur_col * PATCH_SIZE + (PATCH_SIZE >> 1);

                        // 简化梯度计算
                        if (cur_img_i > 0 && cur_img_i < IMAGE_SIZE-1 &&
                            cur_img_j > 0 && cur_img_j < IMAGE_SIZE-1) begin
                            grad <=
                                ((image_buffer[(cur_img_i-1)*IMAGE_SIZE + cur_img_j] >
                                  image_buffer[(cur_img_i+1)*IMAGE_SIZE + cur_img_j]) ?
                                 (image_buffer[(cur_img_i-1)*IMAGE_SIZE + cur_img_j] -
                                  image_buffer[(cur_img_i+1)*IMAGE_SIZE + cur_img_j]) :
                                 (image_buffer[(cur_img_i+1)*IMAGE_SIZE + cur_img_j] -
                                  image_buffer[(cur_img_i-1)*IMAGE_SIZE + cur_img_j])) +
                                ((image_buffer[cur_img_i*IMAGE_SIZE + (cur_img_j-1)] >
                                  image_buffer[cur_img_i*IMAGE_SIZE + (cur_img_j+1)]) ?
                                 (image_buffer[cur_img_i*IMAGE_SIZE + (cur_img_j-1)] -
                                  image_buffer[cur_img_i*IMAGE_SIZE + (cur_img_j+1)]) :
                                 (image_buffer[cur_img_i*IMAGE_SIZE + (cur_img_j+1)] -
                                  image_buffer[cur_img_i*IMAGE_SIZE + (cur_img_j-1)]));
                        end else begin
                            grad <= 0;
                        end

                        // 距离计算
                        dist <= ((cur_row >= 4) ? (cur_row - 4) : (4 - cur_row)) +
                                ((cur_col >= 4) ? (cur_col - 4) : (4 - cur_col));

                        // 权重
                        if (dist == 0)
                            base_weight <= 200;
                        else if (dist == 1)
                            base_weight <= 150;
                        else if (dist == 2)
                            base_weight <= 100;
                        else if (dist == 3)
                            base_weight <= 50;
                        else
                            base_weight <= 20;

                        // 综合评分
                        interest_out[patch_idx] <= ((grad >> 3) + base_weight) >> 1;

                        patch_idx <= patch_idx + 1;
                    end else begin
                        state <= DONE_STATE;
                    end
                end

                DONE_STATE: begin
                    done <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
