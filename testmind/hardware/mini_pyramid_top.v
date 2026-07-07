`timescale 1ns / 1ps

// Mini 金字塔处理器顶层
// 集成：扫描器 + Top-K 选择器

module mini_pyramid_top #(
    parameter IMAGE_SIZE = 32,
    parameter GRID_SIZE = 4,
    parameter TOP_K = 4
)(
    input wire clk,
    input wire rst_n,
    input wire start,

    // 图像输入
    input wire [7:0] pixel_in,
    input wire pixel_valid,

    // Top-K 输出
    output wire [3:0] selected_indices [0:TOP_K-1],
    output wire done
);

    // 中间信号
    wire scanner_done;
    wire [7:0] interest_map [0:GRID_SIZE*GRID_SIZE-1];

    wire selector_start;
    wire selector_done;

    // 扫描器
    mini_coarse_scanner #(
        .IMAGE_SIZE(IMAGE_SIZE),
        .PATCH_SIZE(8),
        .GRID_SIZE(GRID_SIZE)
    ) u_scanner (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .pixel_in(pixel_in),
        .pixel_valid(pixel_valid),
        .interest_out(interest_map),
        .done(scanner_done)
    );

    // Top-K 选择器
    mini_topk_selector #(
        .NUM_VALUES(GRID_SIZE*GRID_SIZE),
        .TOP_K(TOP_K),
        .INDEX_WIDTH(4)
    ) u_selector (
        .clk(clk),
        .rst_n(rst_n),
        .start(selector_start),
        .values(interest_map),
        .topk_indices(selected_indices),
        .done(selector_done)
    );

    // 控制逻辑
    assign selector_start = scanner_done;
    assign done = selector_done;

endmodule
