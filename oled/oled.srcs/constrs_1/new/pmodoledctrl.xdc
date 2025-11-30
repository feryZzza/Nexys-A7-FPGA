## ==========================================
## Nexys A7-100T + PmodOLED (接在 Pmod JA)
## 顶层模块端口名：CLK, RST, CS, SDIN, SCLK, DC, RES, VBAT, VDD
## ==========================================

## 100MHz 板载时钟 (CLK)
set_property PACKAGE_PIN E3 [get_ports {CLK}]
set_property IOSTANDARD LVCMOS33 [get_ports {CLK}]

## 中间按键 BTNC 作为 RST (高电平复位)
set_property PACKAGE_PIN N17 [get_ports {RST}]
set_property IOSTANDARD LVCMOS33 [get_ports {RST}]

## Pmod JA 引脚映射 (根据 Nexys A7 原理图/手册)
## JA1 = C17, JA2 = D18, JA3 = E18, JA4 = G17
## JA7 = D17, JA8 = E17, JA9 = F18, JA10 = G18

# JA1 - CS
set_property PACKAGE_PIN C17 [get_ports {CS}]
set_property IOSTANDARD LVCMOS33 [get_ports {CS}]

# JA2 - SDIN (MOSI)
set_property PACKAGE_PIN D18 [get_ports {SDIN}]
set_property IOSTANDARD LVCMOS33 [get_ports {SDIN}]

# JA4 - SCLK
set_property PACKAGE_PIN G17 [get_ports {SCLK}]
set_property IOSTANDARD LVCMOS33 [get_ports {SCLK}]

# JA7 - DC
set_property PACKAGE_PIN D17 [get_ports {DC}]
set_property IOSTANDARD LVCMOS33 [get_ports {DC}]

# JA8 - RES
set_property PACKAGE_PIN E17 [get_ports {RES}]
set_property IOSTANDARD LVCMOS33 [get_ports {RES}]

# JA9 - VBAT (低=开)
set_property PACKAGE_PIN F18 [get_ports {VBAT}]
set_property IOSTANDARD LVCMOS33 [get_ports {VBAT}]

# JA10 - VDD (低=开)
set_property PACKAGE_PIN G18 [get_ports {VDD}]
set_property IOSTANDARD LVCMOS33 [get_ports {VDD}]
