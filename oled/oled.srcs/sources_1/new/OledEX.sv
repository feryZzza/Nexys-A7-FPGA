`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Digilent Inc.
// Engineers: Ryan Kim, Josh Sackos
//
// Modified: 适配 Vivado SystemVerilog，修复 unpacked array 报错
//           - 使用 1 维常量数组保存屏幕内容
//           - 保留原始显示功能
//////////////////////////////////////////////////////////////////////////////////
module OledEX(
    input  wire CLK,
    input  wire RST,
    input  wire EN,
    output wire CS,
    output wire SDO,
    output wire SCLK,
    output wire DC,
    output wire FIN
    );

    // ===========================================================================
    //  参数与屏幕内容常量
    // ===========================================================================

    // 屏幕是 4 行 × 16 列 = 64 个字符
    localparam int SCREEN_ROWS = 4;
    localparam int SCREEN_COLS = 16;
    localparam int SCREEN_SIZE = SCREEN_ROWS * SCREEN_COLS;  // 64

    // 当前屏幕内容（按 [行][列] 存）
    reg [7:0] current_screen [0:SCREEN_ROWS-1][0:SCREEN_COLS-1];

    // 展开之后的字母屏幕：Alphabet + 数字
    localparam logic [7:0] alphabet_screen [0:SCREEN_SIZE-1] = '{
        // row 0
        8'h41, 8'h42, 8'h43, 8'h44, 8'h45, 8'h46, 8'h47, 8'h48,
        8'h49, 8'h4A, 8'h4B, 8'h4C, 8'h4D, 8'h4E, 8'h4F, 8'h50,
        // row 1
        8'h51, 8'h52, 8'h53, 8'h54, 8'h55, 8'h56, 8'h57, 8'h58,
        8'h59, 8'h5A, 8'h61, 8'h62, 8'h63, 8'h64, 8'h65, 8'h66,
        // row 2
        8'h67, 8'h68, 8'h69, 8'h6A, 8'h6B, 8'h6C, 8'h6D, 8'h6E,
        8'h6F, 8'h70, 8'h71, 8'h72, 8'h73, 8'h74, 8'h75, 8'h76,
        // row 3
        8'h77, 8'h78, 8'h79, 8'h7A, 8'h30, 8'h31, 8'h32, 8'h33,
        8'h34, 8'h35, 8'h36, 8'h37, 8'h38, 8'h39, 8'h7F, 8'h7F
    };

    // 清屏：全部空格 0x20
    localparam logic [7:0] clear_screen [0:SCREEN_SIZE-1] = '{
        default: 8'h20
    };

    // "This is Digilent's PmodOLED"
    localparam logic [7:0] digilent_screen [0:SCREEN_SIZE-1] = '{
        // row 0: "This is        "
        8'h54, 8'h68, 8'h69, 8'h73, 8'h20, 8'h69, 8'h73, 8'h20,
        8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20,
        // row 1: "Digilent's     "
        8'h44, 8'h69, 8'h67, 8'h69, 8'h6C, 8'h65, 8'h6E, 8'h74,
        8'h27, 8'h73, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20,
        // row 2: "PmodOLED       "
        8'h50, 8'h6D, 8'h6F, 8'h64, 8'h4F, 8'h4C, 8'h45, 8'h44,
        8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20,
        // row 3: "                "
        8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20,
        8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20
    };

    // ===========================================================================
    //  状态机相关寄存器
    // ===========================================================================

    // 当前总状态
    reg [143:0] current_state;
    // SPI/Delay 完成后要去的状态
    reg [111:0] after_state;
    // 设置 Page 完成后要去的状态
    reg [142:0] after_page_state;
    // 发送字符序列完成后要去的状态
    reg [95:0]  after_char_state;
    // UpdateScreen 完成后要去的状态
    reg [39:0]  after_update_state;

    integer i;
    integer j;

    // DC 输出
    reg temp_dc;
    assign DC = temp_dc;

    // FIN 只在 Done 状态拉高
    assign FIN = (current_state == "Done") ? 1'b1 : 1'b0;

    // ---------------- Delay block 接口 ----------------
    reg  [11:0] temp_delay_ms;   // 延时毫秒数
    reg         temp_delay_en;   // 延时使能
    wire        temp_delay_fin;  // 延时完成

    // ---------------- SPI block 接口 ------------------
    reg         temp_spi_en;     // SPI 使能
    reg  [7:0]  temp_spi_data;   // SPI 数据
    wire        temp_spi_fin;    // SPI 完成

    // 字符与字模访问
    reg  [7:0]  temp_char;
    reg  [10:0] temp_addr;
    wire [7:0]  temp_dout;
    reg  [1:0]  temp_page;       // 当前页 0..3
    reg  [3:0]  temp_index;      // 当前页内位置 0..15

    // ===========================================================================
    //  实例化 SPI / Delay / charLib
    // ===========================================================================

    SpiCtrl SPI_COMP (
        .CLK     (CLK),
        .RST     (RST),
        .SPI_EN  (temp_spi_en),
        .SPI_DATA(temp_spi_data),
        .CS      (CS),
        .SDO     (SDO),
        .SCLK    (SCLK),
        .SPI_FIN (temp_spi_fin)
    );

    Delay DELAY_COMP (
        .CLK      (CLK),
        .RST      (RST),
        .DELAY_MS (temp_delay_ms),
        .DELAY_EN (temp_delay_en),
        .DELAY_FIN(temp_delay_fin)
    );

    // 字库 ROM，单端口
    charLib CHAR_LIB_COMP (
        .clka (CLK),
        .addra(temp_addr),
        .douta(temp_dout)
    );

    // ===========================================================================
    //  主状态机
    // ===========================================================================

    always @(posedge CLK or posedge RST) begin
        if (RST) begin
            current_state     <= "Idle";
            temp_dc           <= 1'b0;
            temp_delay_ms     <= 12'd0;
            temp_delay_en     <= 1'b0;
            temp_spi_en       <= 1'b0;
            temp_spi_data     <= 8'h00;
            temp_char         <= 8'h00;
            temp_addr         <= 11'd0;
            temp_page         <= 2'd0;
            temp_index        <= 4'd0;
        end else begin
            case (current_state)

                //===========================
                // Idle: 等待 EN = 1
                //===========================
                "Idle": begin
                    if (EN == 1'b1) begin
                        temp_page        <= 2'd0;
                        temp_index       <= 4'd0;
                        current_state    <= "ClearDC";
                        after_page_state <= "Alphabet";
                    end
                end

                //===========================
                // Alphabet: 显示字母+数字
                //===========================
                "Alphabet": begin
                    // 把 alphabet_screen 的一维内容拷贝到 current_screen[行][列]
                    for (i = 0; i < SCREEN_ROWS; i = i + 1) begin
                        for (j = 0; j < SCREEN_COLS; j = j + 1) begin
                            current_screen[i][j] <= alphabet_screen[i*SCREEN_COLS + j];
                        end
                    end

                    current_state       <= "UpdateScreen";
                    after_update_state  <= "Wait1";
                end

                // 等待 4000ms 再清屏
                "Wait1": begin
                    temp_delay_ms  <= 12'd4000;   // 4000 ms
                    after_state    <= "ClearScreen";
                    current_state  <= "Transition3";
                end

                //===========================
                // ClearScreen: 清屏
                //===========================
                "ClearScreen": begin
                    for (i = 0; i < SCREEN_ROWS; i = i + 1) begin
                        for (j = 0; j < SCREEN_COLS; j = j + 1) begin
                            current_screen[i][j] <= clear_screen[i*SCREEN_COLS + j];
                        end
                    end

                    after_update_state <= "Wait2";
                    current_state      <= "UpdateScreen";
                end

                // 再等 1000ms，显示 Digilent 字样
                "Wait2": begin
                    temp_delay_ms  <= 12'd1000;   // 1000 ms
                    after_state    <= "DigilentScreen";
                    current_state  <= "Transition3";
                end

                //===========================
                // DigilentScreen: 显示文字
                //===========================
                "DigilentScreen": begin
                    for (i = 0; i < SCREEN_ROWS; i = i + 1) begin
                        for (j = 0; j < SCREEN_COLS; j = j + 1) begin
                            current_screen[i][j] <= digilent_screen[i*SCREEN_COLS + j];
                        end
                    end

                    after_update_state <= "Done";
                    current_state      <= "UpdateScreen";
                end

                //===========================
                // Done: 完成，FIN=1
                //===========================
                "Done": begin
                    if (EN == 1'b0) begin
                        current_state <= "Idle";
                    end
                end

                //===========================
                // UpdateScreen: 遍历每个字符，发送字形数据
                //===========================
                "UpdateScreen": begin
                    temp_char <= current_screen[temp_page][temp_index];

                    if (temp_index == 4'd15) begin
                        temp_index       <= 4'd0;
                        temp_page        <= temp_page + 1'b1;
                        after_char_state <= "ClearDC";

                        if (temp_page == 2'b11) begin
                            after_page_state <= after_update_state;
                        end else begin
                            after_page_state <= "UpdateScreen";
                        end
                    end else begin
                        temp_index       <= temp_index + 1'b1;
                        after_char_state <= "UpdateScreen";
                    end

                    current_state <= "SendChar1";
                end

                //===========================
                // 设置 Page / 列的命令序列
                //===========================
                "ClearDC": begin
                    temp_dc       <= 1'b0;   // 命令模式
                    current_state <= "SetPage";
                end

                "SetPage": begin
                    temp_spi_data <= 8'b0010_0010;  // 0x22: Set Page Address
                    after_state   <= "PageNum";
                    current_state <= "Transition1";
                end

                "PageNum": begin
                    temp_spi_data <= {6'b000000, temp_page};
                    after_state   <= "LeftColumn1";
                    current_state <= "Transition1";
                end

                "LeftColumn1": begin
                    temp_spi_data <= 8'b0000_0000;
                    after_state   <= "LeftColumn2";
                    current_state <= "Transition1";
                end

                "LeftColumn2": begin
                    temp_spi_data <= 8'b0001_0000;
                    after_state   <= "SetDC";
                    current_state <= "Transition1";
                end

                "SetDC": begin
                    temp_dc       <= 1'b1;   // 数据模式
                    current_state <= after_page_state;
                end

                //===========================
                // 发送单个字符的 8 列字形
                //===========================
                "SendChar1": begin
                    temp_addr   <= {temp_char, 3'b000};
                    after_state <= "SendChar2";
                    current_state <= "ReadMem";
                end

                "SendChar2": begin
                    temp_addr   <= {temp_char, 3'b001};
                    after_state <= "SendChar3";
                    current_state <= "ReadMem";
                end

                "SendChar3": begin
                    temp_addr   <= {temp_char, 3'b010};
                    after_state <= "SendChar4";
                    current_state <= "ReadMem";
                end

                "SendChar4": begin
                    temp_addr   <= {temp_char, 3'b011};
                    after_state <= "SendChar5";
                    current_state <= "ReadMem";
                end

                "SendChar5": begin
                    temp_addr   <= {temp_char, 3'b100};
                    after_state <= "SendChar6";
                    current_state <= "ReadMem";
                end

                "SendChar6": begin
                    temp_addr   <= {temp_char, 3'b101};
                    after_state <= "SendChar7";
                    current_state <= "ReadMem";
                end

                "SendChar7": begin
                    temp_addr   <= {temp_char, 3'b110};
                    after_state <= "SendChar8";
                    current_state <= "ReadMem";
                end

                "SendChar8": begin
                    temp_addr   <= {temp_char, 3'b111};
                    after_state <= after_char_state;
                    current_state <= "ReadMem";
                end

                "ReadMem": begin
                    current_state <= "ReadMem2";   // 等一拍让 ROM 数据稳定
                end

                "ReadMem2": begin
                    temp_spi_data <= temp_dout;
                    current_state  <= "Transition1";
                end

                //===========================
                // SPI Transitions
                //===========================
                "Transition1": begin
                    temp_spi_en   <= 1'b1;
                    current_state <= "Transition2";
                end

                "Transition2": begin
                    if (temp_spi_fin == 1'b1) begin
                        current_state <= "Transition5";
                    end
                end

                //===========================
                // Delay Transitions
                //===========================
                "Transition3": begin
                    temp_delay_en <= 1'b1;
                    current_state <= "Transition4";
                end

                "Transition4": begin
                    if (temp_delay_fin == 1'b1) begin
                        current_state <= "Transition5";
                    end
                end

                //===========================
                // 清理 EN 信号，跳转到 after_state
                //===========================
                "Transition5": begin
                    temp_spi_en   <= 1'b0;
                    temp_delay_en <= 1'b0;
                    current_state <= after_state;
                end

                default: begin
                    current_state <= "Idle";
                end

            endcase
        end
    end

endmodule
