`timescale 1ns / 1ps

module simple_improved_scanner #(
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

    integer i, row, col, dist_r, dist_c, dist_total;

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
                    // 计算每个 patch 的兴趣度（纯位置）
                    for (i = 0; i < GRID_SIZE*GRID_SIZE; i = i + 1) begin
                        row = i / GRID_SIZE;
                        col = i % GRID_SIZE;

                        dist_r = (row >= 4) ? (row - 4) : (4 - row);
                        dist_c = (col >= 4) ? (col - 4) : (4 - col);
                        dist_total = dist_r + dist_c;

                        if (dist_total == 0)
                            interest_out[i] <= 255;
                        else if (dist_total == 1)
                            interest_out[i] <= 200;
                        else if (dist_total == 2)
                            interest_out[i] <= 150;
                        else if (dist_total == 3)
                            interest_out[i] <= 100;
                        else
                            interest_out[i] <= 0;
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
