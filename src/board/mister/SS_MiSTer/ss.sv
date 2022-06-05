//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,

	// Use framebuffer in DDRAM (USE_FB=1 in qsf)
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SDIO
	inout  [3:0]  SDIO_DAT,
	inout         SDIO_CMD,
	output        SDIO_CLK,
/*
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,
*/
	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM2_CLK,
	input         DDRAM2_BUSY,
	output  [7:0] DDRAM2_BURSTCNT,
	output [28:0] DDRAM2_ADDR,
	input  [63:0] DDRAM2_DOUT,
	input         DDRAM2_DOUT_READY,
	output        DDRAM2_RD,
	output [63:0] DDRAM2_DIN,
	output  [7:0] DDRAM2_BE,
	output        DDRAM2_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// User port.
	output  [6:0] USER_EN,
 	output  [6:0] USER_OUT,
	input   [6:0] USER_IN,

	input         OSD_STATUS
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;

assign {UART_RTS, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER = 1;
assign HDMI_FREEZE = 0;

assign AUDIO_S = 0;
assign AUDIO_L = 0;
assign AUDIO_R = 0;
assign AUDIO_MIX = 0;

assign BUTTONS = 0;

assign FB_FORMAT = 6'b000011; // 8bpp
assign FB_WIDTH = 1024;
assign FB_HEIGHT = 768;
assign FB_BASE = 32'h3E400000;
assign FB_STRIDE = 1024;
assign FB_FORCE_BLANK = 0;

assign LED_POWER[1]=0;
assign LED_DISK[1]=0;

//////////////////////////////////////////////////////////////////

wire clk_sys;


/* 0         1         2         3          4         5         6   
   01234567890123456789012345678901 23456789012345678901234567890123
   0123456789ABCDEFGHIJKLMNOPQRSTUV 0123456789ABCDEFGHIJKLMNOPQRSTUV
    XXXXXX XXXXXX  XXXXXX X
*/

`include "build_id.v" 

localparam CONF_STR = {
    "SparcStation;;" ,
    "-;" ,
    "O13,SCSI,Image,Direct SD,Image+Image,SD+Image,Image+SD;" ,
    "S0,RAW,HD;" ,
    "S1,RAW,HD2;" ,
    "O45,CDROM,OFF,2048,512;" ,
    "S2,ISO,CDROM;" ,
    "O6,Aspect ratio,4:3,16:9,[ARC1],[ARC2];" ,
    "O8,AutoBoot,ON,OFF;" ,
    "O9,Boot,Video,Serial;" ,
    "OA,Video,TCX,CG3;" ,
    "OB,Video,Internal,Scaler framebuffer;" ,
    "OCD,Keyboard,US,FR,DE,ES;" ,
    "-;" ,
    "R0,RESET;" ,
    "-;" ,
    "OG,Cachena,ON,OFF;" ,
    "OH,L2TLB,OFF,ON;" ,
`ifdef SS20
    "OI,WB,OFF,ON;" ,
    "OJ,AOW,OFF,ON;" ,
`endif
    "OKL,IOMMU rev,26 (Default),11 (Next),23,30;" ,
    "ON,Ethernet PHY present,NO,YES;",
    "F,ROM,BIOS;" ,
    "-;" ,
    "V,v",`BUILD_DATE 
};

wire forced_scandoubler;

wire  [63:0] status;
wire  [2:0]  img_mounted;
wire  img_readonly;
wire  [63:0] img_size;
wire  [31:0] sd_lba0,sd_lba1,sd_lba2;
wire  [2:0] sd_rd;
wire  [2:0] sd_wr;
wire  [2:0] sd_ack;
wire  [7:0] sd_buff_addr;
wire  [15:0] sd_buff_dout;
wire  [15:0] sd_buff_din0,sd_buff_din1,sd_buff_din2;
wire  sd_buff_wr;
wire  ioctl_download;
wire  [7:0] ioctl_index;
wire  ioctl_wr;
wire  [24:0] ioctl_addr;
wire  [15:0] ioctl_dout;
wire  ioctl_wait;
wire  [64:0] RTC;
wire  ps2_kbd_clk_out,ps2_kbd_data_out,ps2_kbd_clk_in,ps2_kbd_data_in;
wire  [2:0] ps2_kbd_led_status,ps2_kbd_led_use;
wire  ps2_mouse_clk_out,ps2_mouse_data_out,ps2_mouse_clk_in,ps2_mouse_data_in;
  
hps_io #(
    .CONF_STR(CONF_STR),
    .PS2DIV(1000),
    .WIDE(1),
    .VDNUM(3),
    .PS2WE(0))
hps_io
 (
  .clk_sys(clk_sys),
  .HPS_BUS(HPS_BUS),
  .ps2_kbd_clk_out(ps2_kbd_clk_out),
  .ps2_kbd_data_out(ps2_kbd_data_out),
  .ps2_kbd_clk_in(ps2_kbd_clk_in),
  .ps2_kbd_data_in(ps2_kbd_data_in),
  .ps2_kbd_led_status(ps2_kbd_led_status),
  .ps2_kbd_led_use(ps2_kbd_led_use),
  .ps2_mouse_clk_out(ps2_mouse_clk_out),
  .ps2_mouse_data_out(ps2_mouse_data_out),
  .ps2_mouse_clk_in(ps2_mouse_clk_in),
  .ps2_mouse_data_in(ps2_mouse_data_in),

  .status(status),
  .status_in(status),

  .img_mounted(img_mounted),
  .img_readonly(img_readonly),
  .img_size(img_size),

  .sd_lba('{sd_lba0, sd_lba1, sd_lba2}),
  .sd_blk_cnt('{0, 0, 0}),
  .sd_rd(sd_rd),
  .sd_wr(sd_wr),
  .sd_ack(sd_ack),

  .sd_buff_addr(sd_buff_addr),
  .sd_buff_dout(sd_buff_dout),
  .sd_buff_din('{sd_buff_din0,sd_buff_din1,sd_buff_din2}),
  .sd_buff_wr(sd_buff_wr),

  .ioctl_download(ioctl_download),
  .ioctl_index(ioctl_index),
  .ioctl_wr(ioctl_wr),
  .ioctl_addr(ioctl_addr),
  .ioctl_dout(ioctl_dout),
  .ioctl_wait(ioctl_wait),
  .RTC(RTC)

);

wire scsi_conf   = status[3:1];
wire scsi_cdconf = status[5:4];

wire [1:0] ar = status[7:6];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

wire autoboot  = ~status[8];
wire viboot    = ~status[9];
wire tcx       = ~status[10];
assign FB_EN = status[11];
wire vga_on  = 1;

/* PS2 to Sun keyboard layout
  "Layouts for Type 4, 5, and 5c Keyboards"
  "https://docs.oracle.com/cd/E19253-01/817-2521/new-311/index.html"
  21 : USA,    QWERTY, ANSI layout
  23 : France, AZERTY, ISO  layout
  25 : Germany, QWERTZ
  2A : Spain
*/
wire [7:0] kbm_layout = (status[13:12]==0)?8'h21:
                        (status[13:12]==1)?8'h23:
                        (status[13:12]==2)?8'h25:8'h2A;

wire cachena   = !status[16];
wire l2tlbena  = status[17];
wire wback     = status[18];
wire aow       = status[19];

wire [7:0] reset_mask_rev = (status[21:20]==0)?8'h26:
                            (status[21:20]==1)?8'h11:
                            (status[21:20]==2)?8'h23:8'h30;
                            
///////////////////////   CLOCKS   ///////////////////////////////

wire sd_sck;
wire [3:0] sd_dat;
wire sd_cmd;
wire sd_cd;

wire [1:0] rmii_txd,rmii_rxd;
wire rmii_txen,rmii_clk;
   
wire reset = RESET | status[0];

   
ss_core 
#(
`ifndef SS20
  .SYSFREQ(65000000),
  .SS20(0),
  .NCPUS(1),
  .TRACE(1),
`else
  .SYSFREQ(50000000),
  .SS20(1),
  .NCPUS(3),
  .TRACE(1),
`endif  
  .FPU_MULTI(0),
  .TCX_ACCEL(1)
  )
ss_core
(
 .clk_50m(CLK_50M),
 .clk_sys(clk_sys),
 .reset(reset),
 .vga_r(VGA_R),
 .vga_g(VGA_G),
 .vga_b(VGA_B),
 .vga_hs(VGA_HS),
 .vga_vs(VGA_VS),
 .vga_de(VGA_DE),
 .vga_ce(CE_PIXEL),
 .vga_clk(CLK_VIDEO),

 .fb_pal_clk(FB_PAL_CLK),
 .fb_pal_d(FB_PAL_DOUT),
 .fb_pal_a(FB_PAL_ADDR),
 .fb_pal_wr(FB_PAL_WR),
    
 .led_disk(LED_DISK[0]),
 .led_user(LED_USER),
 .led_power(LED_POWER[0]),
    
 .sd_sck(SDIO_CLK),
 .sd_dat(SDIO_DAT),
 .sd_cmd(SDIO_CMD),
 .ddram_clk(DDRAM_CLK),
 .ddram_waitrequest(DDRAM_BUSY),
 .ddram_burstcount(DDRAM_BURSTCNT),
 .ddram_address(DDRAM_ADDR),
 .ddram_readdata(DDRAM_DOUT),
 .ddram_readdatavalid(DDRAM_DOUT_READY),
 .ddram_read(DDRAM_RD),
 .ddram_writedata(DDRAM_DIN),
 .ddram_byteenable(DDRAM_BE),
 .ddram_write(DDRAM_WE),
    
 .ddram2_clk(DDRAM2_CLK),
 .ddram2_waitrequest(DDRAM2_BUSY),
 .ddram2_burstcount(DDRAM2_BURSTCNT),
 .ddram2_address(DDRAM2_ADDR),
 .ddram2_readdata(DDRAM2_DOUT),
 .ddram2_readdatavalid(DDRAM2_DOUT_READY),
 .ddram2_read(DDRAM2_RD),
 .ddram2_writedata(DDRAM2_DIN),
 .ddram2_byteenable(DDRAM2_BE),
 .ddram2_write(DDRAM2_WE),

 .reset_mask_rev(reset_mask_rev),
 .kbm_layout(kbm_layout),
 .wback(wback),
 .aow(aow),
 .cachena(cachena),
 .l2tlbena(l2tlbena),
 
 .vga_on(vga_on),
 .scsi_conf(scsi_conf),
 .scsi_cdconf(scsi_cdconf),
 .tcx(tcx),
 .autoboot(autoboot),
 .viboot(viboot),
 
 .img_mounted(img_mounted),
 .img_readonly(img_readonly),
 .img_size(img_size),
 .sd_lba0(sd_lba0),
 .sd_lba1(sd_lba1),
 .sd_lba2(sd_lba2),
 .sd_rd(sd_rd),
 .sd_wr(sd_wr),
 .sd_ack(sd_ack),
 .sd_buff_addr(sd_buff_addr),
 .sd_buff_dout(sd_buff_dout),
 .sd_buff_din0(sd_buff_din0),
 .sd_buff_din1(sd_buff_din1),
 .sd_buff_din2(sd_buff_din2),
 .sd_buff_wr(sd_buff_wr),
 .ioctl_download(ioctl_download),
 .ioctl_index(ioctl_index),
 .ioctl_wr(ioctl_wr),
 .ioctl_addr(ioctl_addr),
 .ioctl_dout(ioctl_dout),
 .ioctl_wait(ioctl_wait),
 .rtc(RTC),
 .ps2_kbd_clk_out(ps2_kbd_clk_out),
 .ps2_kbd_data_out(ps2_kbd_data_out),
 .ps2_kbd_clk_in(ps2_kbd_clk_in),
 .ps2_kbd_data_in(ps2_kbd_data_in),
 .ps2_kbd_led_status(ps2_kbd_led_status),
 .ps2_kbd_led_use(ps2_kbd_led_use),
 .ps2_mouse_clk_out(ps2_mouse_clk_out),
 .ps2_mouse_data_out(ps2_mouse_data_out),
 .ps2_mouse_clk_in(ps2_mouse_clk_in),
 .ps2_mouse_data_in(ps2_mouse_data_in),
 .rmii_rxd(rmii_rxd),
 .rmii_txd(rmii_txd),
 .rmii_txen(rmii_txen),
 .rmii_clk(rmii_clk),
 .uart_txd(UART_TXD),
 .uart_rxd(UART_RXD)

);

assign VGA_F1 =0;
assign VGA_SL =0;

/* ETHERNET PHY
   0 : RX1
   1 : RX0
   2 : RX_CLK
   3 : TXEN
   4 : TX1
   5 : TX0
   6 : NC
 */

assign USER_EN = status[23] ? 7'b0111000 : 7'b0000000 ;
assign USER_OUT = {1'b0,rmii_txd[0],rmii_txd[1],rmii_txen,3'b0};
assign rmii_rxd = {USER_IN[1],USER_IN[0]};
assign rmii_clk = USER_IN[2];
   
endmodule
