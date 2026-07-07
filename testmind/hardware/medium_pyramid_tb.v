`timescale 1ns / 1ps

module medium_pyramid_tb;

    reg clk;
    reg rst_n;
    reg start;
    reg [7:0] pixel_in;
    reg pixel_valid;

    wire [5:0] selected_indices [0:15];
    wire done;

    // 实例化 DUT
    medium_pyramid_top #(
        .IMAGE_SIZE(112),
        .GRID_SIZE(8),
        .TOP_K(16)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .pixel_in(pixel_in),
        .pixel_valid(pixel_valid),
        .selected_indices(selected_indices),
        .done(done)
    );

    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 图像数据
    reg [7:0] test_image [0:12543];  // 112x112

    // 测试流程
    integer i;
    integer fd;
    initial begin
        $dumpfile("medium_pyramid.vcd");
        $dumpvars(0, medium_pyramid_tb);

        // 加载测试图像
        $readmemh("test_image.hex", test_image);

        // 复位
        rst_n = 0;
        start = 0;
        pixel_valid = 0;
        pixel_in = 0;

        #20;
        rst_n = 1;
        #10;

        // 启动
        start = 1;
        #10;
        start = 0;

        // 输入像素数据
        pixel_valid = 1;
        for (i = 0; i < 12544; i = i + 1) begin
            pixel_in = test_image[i];
            #10;
        end
        pixel_valid = 0;

        // 等待完成
        wait(done);
        #50;

        // 输出结果
        $display("=== Top-16 Selected Indices ===");
        for (i = 0; i < 16; i = i + 1) begin
            $display("Index %2d: %d", i, selected_indices[i]);
        end

        // 写入输出文件
        fd = $fopen("output_indices.hex", "w");
        for (i = 0; i < 16; i = i + 1) begin
            $fwrite(fd, "%h\n", selected_indices[i]);
        end
        $fclose(fd);

        $display("Simulation complete!");
        $finish;
    end

    // 超时保护
    initial begin
        #5000000;
        $display("ERROR: Simulation timeout");
        $finish;
    end

endmodule
