`timescale 1ns / 1ps

module vlm_preprocessing_top #(
    parameter IMAGE_SIZE = 112,
    parameter GRID_SIZE = 8,
    parameter TOP_K = 16
)(
    input wire clk,
    input wire rst_n,
    input wire start,

    input wire [7:0] pixel_in,
    input wire pixel_valid,

    output wire [5:0] selected_indices [0:TOP_K-1],
    output wire done
);

    wire scanner_done;
    wire [7:0] interest_map [0:GRID_SIZE*GRID_SIZE-1];

    wire selector_start;
    wire selector_done;

    // 使用简单改进版扫描器
    vlm_scanner #(
        .IMAGE_SIZE(IMAGE_SIZE),
        .PATCH_SIZE(14),
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

    vlm_topk_selector #(
        .NUM_VALUES(GRID_SIZE*GRID_SIZE),
        .TOP_K(TOP_K),
        .INDEX_WIDTH(6)
    ) u_selector (
        .clk(clk),
        .rst_n(rst_n),
        .start(selector_start),
        .values(interest_map),
        .topk_indices(selected_indices),
        .done(selector_done)
    );

    assign selector_start = scanner_done;
    assign done = selector_done;

endmodule
