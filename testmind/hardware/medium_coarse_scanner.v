`timescale 1ns / 1ps

// 中等版本：112x112 图像，检测边缘复杂度
// 输出：8x8 = 64 个兴趣度值

module medium_coarse_scanner #(
    parameter IMAGE_SIZE = 112,
    parameter PATCH_SIZE = 14,
    parameter GRID_SIZE = 8  // 112/14 = 8
)(
    input wire clk,
    input wire rst_n,
    input wire start,

    // 图像输入（灰度）
    input wire [7:0] pixel_in,
    input wire pixel_valid,

    // 兴趣度输出
    output reg [7:0] interest_out [0:GRID_SIZE*GRID_SIZE-1],
    output reg done
);

    // 状态机
    localparam IDLE = 2'd0;
    localparam SCAN = 2'd1;
    localparam DONE = 2'd2;

    reg [1:0] state;
    reg [15:0] pixel_cnt;
    reg [7:0] image_buffer [0:IMAGE_SIZE*IMAGE_SIZE-1];

    integer i, j;
    reg [15:0] grad_sum;
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
                            state <= DONE;
                        end
                    end
                end

                DONE: begin
                    done <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end

    // 计算兴趣度
    integer patch_idx, row, col;
    always @(*) begin
        for (patch_idx = 0; patch_idx < GRID_SIZE*GRID_SIZE; patch_idx = patch_idx + 1) begin
            row = patch_idx / GRID_SIZE;
            col = patch_idx % GRID_SIZE;

            i = row * PATCH_SIZE + PATCH_SIZE/2;
            j = col * PATCH_SIZE + PATCH_SIZE/2;

            if (i > 0 && i < IMAGE_SIZE-1 && j > 0 && j < IMAGE_SIZE-1) begin
                p00 = image_buffer[(i-1)*IMAGE_SIZE + (j-1)];
                p01 = image_buffer[(i-1)*IMAGE_SIZE + (j+1)];
                p10 = image_buffer[(i+1)*IMAGE_SIZE + (j-1)];
                p11 = image_buffer[(i+1)*IMAGE_SIZE + (j+1)];

                gx = $signed({1'b0, p01}) - $signed({1'b0, p00});
                gy = $signed({1'b0, p11}) - $signed({1'b0, p10});

                interest_out[patch_idx] = (gx[8] ? -gx : gx) + (gy[8] ? -gy : gy);
            end else begin
                interest_out[patch_idx] = 0;
            end
        end
    end

endmodule
