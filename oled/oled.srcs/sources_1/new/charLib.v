`timescale 1ns / 1ps
// 字库 ROM：用 $readmemh 从 charLib.mem 读入 1024 个 8bit 数据
// 接口要和 OledEX 里的一致：clka, addra, douta

module charLib(
    input  wire        clka,
    input  wire [10:0] addra,   // OledEX 里是 11 位地址
    output reg  [7:0]  douta
);

    // 实际 ROM 深度是 1024，所以只用 addra[9:0]
    reg [7:0] rom [0:1023];

    initial begin
        // 确保 Vivado 工程里能找到这个相对路径
        $readmemh("charLib.mem", rom);
    end

    always @(posedge clka) begin
        douta <= rom[addra[9:0]];  // 高位忽略
    end

endmodule
