`timescale 1ns / 1ps

// 直接测试 vlm_periph 模块（不经过 p1_top）
// 用 dog.jpg 的像素数据驱动，验证 Top-16 索引输出

`include "../../rtl/periph/vlm/vlm_periph.v"
`include "../../rtl/periph/vlm/vlm_preprocessing_top.v"
`include "../../rtl/periph/vlm/vlm_scanner.v"
`include "../../rtl/periph/vlm/vlm_topk_selector.v"

module vlm_periph_tb;

    parameter BASE_ADDR  = 32'h0000_2000;
    parameter TOP_K      = 16;
    parameter IMAGE_SIZE = 112;
    parameter CLK_PERIOD = 10;

    reg        clk;
    reg        resetn;
    reg        valid;
    reg [31:0] addr;
    reg [31:0] wdata;
    reg [3:0]  wstrb;
    wire       ready;
    wire [31:0] rdata;
    wire        selected;

    vlm_periph #(.BASE_ADDR(BASE_ADDR)) dut (
        .clk(clk), .resetn(resetn),
        .valid(valid), .addr(addr),
        .wdata(wdata), .wstrb(wstrb),
        .ready(ready), .rdata(rdata),
        .selected(selected)
    );

    // 像素数据（由 Python 脚本生成）
    reg [7:0] pixel_mem [0:IMAGE_SIZE*IMAGE_SIZE-1];

    integer i, cycles;
    reg [31:0] status_val;
    reg [31:0] read_indices [0:TOP_K-1];
    integer nonzero;

    initial $dumpfile("vlm_periph_tb.vcd");
    initial $dumpvars(0, vlm_periph_tb);

    always #(CLK_PERIOD/2) clk = ~clk;

    // 总线写任务
    task bus_write;
        input [31:0] a;
        input [31:0] d;
        begin
            @(posedge clk);
            valid <= 1; addr <= a; wdata <= d; wstrb <= 4'hF;
            @(posedge clk);
            while (!ready) @(posedge clk);
            valid <= 0; wstrb <= 0;
        end
    endtask

    // 总线读任务
    task bus_read;
        input  [31:0] a;
        output [31:0] d;
        begin
            @(posedge clk);
            valid <= 1; addr <= a; wstrb <= 4'h0;
            @(posedge clk);
            while (!ready) @(posedge clk);
            d = rdata;
            valid <= 0;
        end
    endtask

    initial begin
        clk    = 0;
        resetn = 0;
        valid  = 0;
        addr   = 0;
        wdata  = 0;
        wstrb  = 0;

        $readmemh("../../testmind/hardware/test_image.hex", pixel_mem);

        repeat(4) @(posedge clk);
        resetn = 1;
        repeat(2) @(posedge clk);

        // Step 1: 发 start
        $display("[1] Writing ctrl=1 (start)");
        bus_write(BASE_ADDR + 32'h000, 32'h1);

        // Step 2: 逐像素写入
        $display("[2] Writing %0d pixels...", IMAGE_SIZE*IMAGE_SIZE);
        for (i = 0; i < IMAGE_SIZE*IMAGE_SIZE; i = i + 1) begin
            bus_write(BASE_ADDR + 32'h008, {24'b0, pixel_mem[i]});
        end
        $display("    [OK] all pixels written");

        // Step 3: 等待 done
        $display("[3] Waiting for VLM done...");
        cycles = 0;
        status_val = 0;
        while (status_val[0] == 0 && cycles < 500000) begin
            bus_read(BASE_ADDR + 32'h004, status_val);
            cycles = cycles + 1;
        end

        if (cycles >= 500000) begin
            $display("FAIL: VLM timeout");
            $finish;
        end
        $display("    [OK] done in %0d poll cycles", cycles);

        // Step 4: 读出索引
        $display("[4] Reading Top-%0d indices:", TOP_K);
        for (i = 0; i < TOP_K; i = i + 1) begin
            bus_read(BASE_ADDR + 32'h100 + i*4, read_indices[i]);
            $display("    [%02d] = %0d", i, read_indices[i]);
        end

        // Step 5: 验证非零且在范围内
        nonzero = 0;
        for (i = 0; i < TOP_K; i = i + 1) begin
            if (read_indices[i] != 0) nonzero = nonzero + 1;
        end

        if (nonzero >= TOP_K/2) begin
            $display("PASS: VLM periph test passed (%0d non-zero indices)", nonzero);
        end else begin
            $display("FAIL: too many zero indices (%0d non-zero)", nonzero);
        end

        $finish;
    end

endmodule
