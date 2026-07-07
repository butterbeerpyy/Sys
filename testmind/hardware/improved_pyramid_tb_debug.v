`timescale 1ns / 1ps

module improved_pyramid_tb;

    reg clk;
    reg rst_n;
    reg start;
    reg [7:0] pixel_in;
    reg pixel_valid;

    wire [5:0] selected_indices [0:15];
    wire done;

    improved_pyramid_top #(
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

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    reg [7:0] test_image [0:12543];

    integer i;
    integer fd;
    initial begin
        $dumpfile("improved_pyramid.vcd");
        $dumpvars(0, improved_pyramid_tb);

        $readmemh("test_image.hex", test_image);

        rst_n = 0;
        start = 0;
        pixel_valid = 0;
        pixel_in = 0;

        #20;
        rst_n = 1;
        #10;

        start = 1;
        $display("Start signal asserted");
        #10;
        start = 0;

        $display("Feeding 12544 pixels...");
        pixel_valid = 1;
        for (i = 0; i < 12544; i = i + 1) begin
            pixel_in = test_image[i];
            #10;
        end
        pixel_valid = 0;
        $display("Pixel input complete");

        // 等待一段时间后检查状态
        #10000;
        $display("After 10000 time units:");
        $display("  Scanner done: %b", dut.u_scanner.done);
        $display("  Selector start: %b", dut.selector_start);
        $display("  Selector done: %b", dut.u_selector.done);
        $display("  Top done: %b", done);

        wait(done);
        #50;

        $display("=== Improved Top-16 Selected Indices ===");
        for (i = 0; i < 16; i = i + 1) begin
            $display("Index %2d: %d", i, selected_indices[i]);
        end

        fd = $fopen("output_indices.hex", "w");
        for (i = 0; i < 16; i = i + 1) begin
            $fwrite(fd, "%h\n", selected_indices[i]);
        end
        $fclose(fd);

        $display("Simulation complete!");
        $finish;
    end

    initial begin
        #5000000;
        $display("ERROR: Simulation timeout after 5000000 time units");
        $display("Final state:");
        $display("  Scanner done: %b", dut.u_scanner.done);
        $display("  Selector start: %b", dut.selector_start);
        $display("  Selector done: %b", dut.u_selector.done);
        $display("  Top done: %b", done);
        $finish;
    end

endmodule
