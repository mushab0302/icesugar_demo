`timescale 1ns/1ps

module blinky_tb;
    reg clk;
    wire led1, led2, led3, led4, led5;

    top_blinky_ping_pong dut (
        .clock(clk),
        .led1(led1),
        .led2(led2),
        .led3(led3),
        .led4(led4),
        .led5(led5)
    );

    initial begin
        clk = 0;
    end

    always #5 clk = ~clk;

    initial begin
        $dumpfile("build/top_blinky_ping_pong_tb.vcd");
        $dumpvars(0, blinky_tb);

        #100;
        $finish;
    end

endmodule