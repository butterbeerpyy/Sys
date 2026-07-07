`timescale 1ns / 1ps

module test_topk_only;
    reg clk, rst_n, start;
    reg [7:0] values [0:63];
    wire [5:0] topk_indices [0:15];
    wire done;

    multicycle_topk_selector #(
        .NUM_VALUES(64),
        .TOP_K(16),
        .INDEX_WIDTH(6)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .values(values),
        .topk_indices(topk_indices),
        .done(done)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    integer i;
    initial begin
        // 初始化测试数据（中心高，边缘低）
        for (i = 0; i < 64; i = i + 1) begin
            if (i >= 27 && i <= 36) // 中心区域
                values[i] = 8'd200 + i;
            else
                values[i] = 8'd50 + i;
        end

        rst_n = 0;
        start = 0;
        #20;
        rst_n = 1;
        #10;

        start = 1;
        #10;
        start = 0;

        // 监控状态
        fork
            begin
                repeat(1000) begin
                    #100;
                    $display("Time %0t: state=%d, current_idx=%d, done=%b",
                             $time, dut.state, dut.current_idx, done);
                end
            end
            begin
                wait(done);
                $display("SUCCESS! Done at time %0t", $time);
                $display("Indices: %d %d %d %d", 
                         topk_indices[0], topk_indices[1], 
                         topk_indices[2], topk_indices[3]);
                $finish;
            end
            begin
                #500000;
                $display("TIMEOUT at state=%d, current_idx=%d", 
                         dut.state, dut.current_idx);
                $finish;
            end
        join
    end
endmodule
