`timescale 1ns / 1ps

module mini_pyramid_tb;

    reg clk;
    reg rst_n;
    reg start;
    reg [7:0] pixel_in;
    reg pixel_valid;

    wire [3:0] selected_indices [0:3];
    wire done;

    // 实例化 DUT
    mini_pyramid_top #(
        .IMAGE_SIZE(32),
        .GRID_SIZE(4),
        .TOP_K(4)
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
    reg [7:0] test_image [0:1023];  // 32x32

    // 测试流程
    integer i;
    integer fd;  // 文件描述符
    initial begin
        $dumpfile("mini_pyramid.vcd");
        $dumpvars(0, mini_pyramid_tb);

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
        for (i = 0; i < 1024; i = i + 1) begin
            pixel_in = test_image[i];
            #10;
        end
        pixel_valid = 0;

        // 等待完成
        wait(done);
        #50;

        // 输出结果
        $display("=== Top-4 Selected Indices ===");
        $display("Index 0: %d", selected_indices[0]);
        $display("Index 1: %d", selected_indices[1]);
        $display("Index 2: %d", selected_indices[2]);
        $display("Index 3: %d", selected_indices[3]);

        // 写入输出文件（手动写入）
        fd = $fopen("output_indices.hex", "w");
        $fwrite(fd, "%h\n", selected_indices[0]);
        $fwrite(fd, "%h\n", selected_indices[1]);
        $fwrite(fd, "%h\n", selected_indices[2]);
        $fwrite(fd, "%h\n", selected_indices[3]);
        $fclose(fd);

        $display("Simulation complete!");
        $finish;
    end

    // 超时保护
    initial begin
        #100000;
        $display("ERROR: Simulation timeout");
        $finish;
    end

endmodule
