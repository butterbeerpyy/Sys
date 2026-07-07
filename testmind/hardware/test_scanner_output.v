`timescale 1ns / 1ps

module test_scanner_output;
    reg clk, rst_n, start;
    reg [7:0] pixel_in;
    reg pixel_valid;
    wire [7:0] interest_out [0:63];
    wire done;

    simple_improved_scanner dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .pixel_in(pixel_in), .pixel_valid(pixel_valid),
        .interest_out(interest_out), .done(done)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    integer i;
    initial begin
        rst_n = 0; start = 0; pixel_valid = 0; pixel_in = 0;
        #20; rst_n = 1; #10;

        start = 1; #10; start = 0;

        // 输入随机数据
        pixel_valid = 1;
        for (i = 0; i < 12544; i = i + 1) begin
            pixel_in = i % 256;
            #10;
        end
        pixel_valid = 0;

        wait(done);
        #50;

        $display("=== Interest Map (8x8) ===");
        for (i = 0; i < 64; i = i + 1) begin
            if (i % 8 == 0) $write("\n");
            $write("%3d ", interest_out[i]);
        end
        $display("\n\nCenter should be high (27,28,35,36):");
        $display("  interest_out[27]=%d", interest_out[27]);
        $display("  interest_out[28]=%d", interest_out[28]);
        $display("  interest_out[35]=%d", interest_out[35]);
        $display("  interest_out[36]=%d", interest_out[36]);

        $finish;
    end

    initial begin
        #200000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
