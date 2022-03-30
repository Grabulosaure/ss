--------------------------------------------------------------------------------
-- TEM : TS
-- Terasic DE10nano + MiSTer
--------------------------------------------------------------------------------
-- DO 2/2018
--------------------------------------------------------------------------------
-- Cyclone V SoC 5CSEBA6U23I7
--------------------------------------------------------------------------------

-- ASCAL : 2000_0000
--           80_0000
-- FB    : 2200_0000
--           

--  CONSTANT OBRAM_ADRS : uv32 := x"1F80_0000";
--  CONSTANT TCX_ADRS   : uv32 := x"1FC0_0000";
  

--[    1.599461] MiSTer_fb 22000000.MiSTer_fb: width = 960, height = 540, format=8888


--#define FB_SIZE  (1024*1024*8/4)               // 8MB
--#define FB_ADDR  (0x20000000 + (32*1024*1024)) // 512mb + 32mb(Core's fb)

--  Audio: CMA addr = 0x1EE00000


LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.plomb_pack.ALL;
USE work.ts_pack.ALL;
USE work.cpu_conf_pack.ALL;

ENTITY emu IS
  PORT (
    -- Master input clock
    clk_50m          : IN    std_logic;

    -- Async reset from top-level module.
    -- Can be used as initial reset.
    reset            : IN    std_logic;

    -- Must be passed to hps_io module
    hps_bus          : INOUT std_logic_vector(45 DOWNTO 0);

    -- Base video clock. Usually equals to CLK_SYS.
    clk_video        : OUT   std_logic;

    -- Multiple resolutions are supported using different ce_pixel rates.
    -- Must be based on clk_video
    ce_pixel         : OUT   std_logic;

    -- VGA
    vga_r            : OUT   uv8;
    vga_g            : OUT   uv8;
    vga_b            : OUT   uv8;
    vga_hs           : OUT   std_logic; -- positive pulse!
    vga_vs           : OUT   std_logic; -- positive pulse!
    vga_de           : OUT   std_logic; -- = not (VBlank or HBlank)
    vga_f1           : OUT   std_logic;
    vga_sl           : OUT   std_logic_vector(1 DOWNTO 0);
    fb_direct        : OUT   std_logic;
    fb_pal_clk       : OUT   std_logic;
    fb_pal_d         : OUT   uv24;
    fb_pal_a         : OUT   uv8;
    fb_pal_wr        : OUT   std_logic;
    
    -- LED
    led_user         : OUT   std_logic; -- 1 - ON, 0 - OFF.
    
    -- b[1]: 0 - LED status is system status ORed with b[0]
    --       1 - LED status is controled solely by b[0]
    -- hint: supply 2'b00 to let the system control the LED.
    led_power        : OUT   std_logic_vector(1 DOWNTO 0);
    led_disk         : OUT   std_logic_vector(1 DOWNTO 0);

    -- Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
    video_arx        : OUT   std_logic_vector(7 DOWNTO 0);
    video_ary        : OUT   std_logic_vector(7 DOWNTO 0);

    -- AUDIO
    audio_l          : OUT   std_logic_vector(15 DOWNTO 0);
    audio_r          : OUT   std_logic_vector(15 DOWNTO 0);
    audio_s          : OUT   std_logic; -- 1 - signed audio samples, 0 - unsigned
    audio_mix        : OUT   std_logic_vector(1 DOWNTO 0);
    
    adc_bus          : INOUT std_logic_vector(3 DOWNTO 0);
    
    -- SD card direct
    sd_sck           : OUT   std_logic;
    sd_dat           : INOUT std_logic_vector(3 DOWNTO 0);
    sd_cmd           : INOUT std_logic;
    sd_cd            : IN    std_logic;
    
    -- High latency DDR3 RAM interface
    -- Use for non-critical time purposes
    ddram_clk           : OUT   std_logic;
    ddram_waitrequest   : IN    std_logic;
    ddram_burstcount    : OUT   std_logic_vector(7 DOWNTO 0);
    ddram_address       : OUT   std_logic_vector(28 DOWNTO 0);
    ddram_readdata      : IN    std_logic_vector(63 DOWNTO 0);
    ddram_readdatavalid : IN    std_logic;
    ddram_read          : OUT   std_logic;
    ddram_writedata     : OUT   std_logic_vector(63 DOWNTO 0);
    ddram_byteenable    : OUT   std_logic_vector(7 DOWNTO 0);
    ddram_write         : OUT   std_logic;
    
    ddram2_clk           : OUT   std_logic;
    ddram2_waitrequest   : IN    std_logic;
    ddram2_burstcount    : OUT   std_logic_vector(7 DOWNTO 0);
    ddram2_address       : OUT   std_logic_vector(28 DOWNTO 0);
    ddram2_readdata      : IN    std_logic_vector(63 DOWNTO 0);
    ddram2_readdatavalid : IN    std_logic;
    ddram2_read          : OUT   std_logic;
    ddram2_writedata     : OUT   std_logic_vector(63 DOWNTO 0);
    ddram2_byteenable    : OUT   std_logic_vector(7 DOWNTO 0);
    ddram2_write         : OUT   std_logic;
    
    -- SDRAM interface with lower latency
    sdram_CLK        : OUT   std_logic;
    sdram_CKE        : OUT   std_logic;
    sdram_A          : OUT   std_logic_vector(12 DOWNTO 0);
    sdram_BA         : OUT   std_logic_vector(1 DOWNTO 0);
    sdram_DQ         : INOUT std_logic_vector(15 DOWNTO 0);
    sdram_DQML       : OUT   std_logic;
    sdram_DQMH       : OUT   std_logic;
    sdram_nCS        : OUT   std_logic;
    sdram_nCAS       : OUT   std_logic;
    sdram_nRAS       : OUT   std_logic;
    sdram_nWE        : OUT   std_logic;
    
    -- Access to host
    uart_cts         : IN    std_logic;
    uart_rts         : OUT   std_logic;
    uart_rxd         : IN    std_logic;
    uart_txd         : OUT   std_logic;
    uart_dtr         : OUT   std_logic;
    uart_dsr         : IN    std_logic;
    
    debug_txd        : OUT   std_logic;
    debug_rxd        : IN    std_logic;
    
    user_in          : IN    std_logic_vector(5 DOWNTO 0);
    user_out         : OUT   std_logic_vector(5 DOWNTO 0);
    
    osd_status       : IN    std_logic);
END ENTITY emu;

--##############################################################################
ARCHITECTURE rtl OF emu IS

  
  --###################################################################
--  CONSTANT SYSFREQ   : natural := 40_000_000
--  CONSTANT SYSFREQ   : natural := 65_000_000;
  CONSTANT SYSFREQ   : natural := 50_000_000;

  CONSTANT SS20      : boolean := true; --true; -- false = SS5     | true = SS20
  CONSTANT NCPUS     : natural := 3;    -- 1..4. SS20 if >=2
  
  CONSTANT FPU_MULTI : boolean := false;-- false = Separate FPUs | true = Shared

  CONSTANT TCX_ACCEL : boolean := true;  -- false = Disable | true = Accelerator
  
  CONSTANT TRACE     : boolean := true; -- false = No trace blocks
  
  CONSTANT OBRAM_ADRS : uv32 := x"1D00_0000";
  CONSTANT TCX_ADRS   : uv32 := x"1D40_0000";
  
  CONSTANT RAMSIZE    : natural := mux(SS20,512-32-16,256);
  
  --###################################################################

  SIGNAL sclk : std_logic;
  SIGNAL clk65m,clk80m,clk40m : std_logic;
  SIGNAL spll_locked : std_logic;
  
  -- Core
  SIGNAL downmux : std_logic;
  SIGNAL dram_pw,vram_pw : type_plomb_w;
  SIGNAL dram_pr,vram_pr : type_plomb_r;
  SIGNAL flash_w,ibram_w : type_pvc_w;
  SIGNAL flash_r,ibram_r : type_pvc_r;
  SIGNAL rxd1,rxd2,rxd3,rxd4,cts : std_logic;
  SIGNAL txd1,txd2,txd3,txd4,rts : std_logic;
  SIGNAL preset : std_logic :='1';
  SIGNAL halt : std_logic :='0';
  SIGNAL postdownload : std_logic :='0';
  SIGNAL resetx,presetx : unsigned(0 TO 7) :=x"00";
  SIGNAL reset_na,preset_na : std_logic :='0';
  SIGNAL ioctl_cpt : uint8;
  SIGNAL preset_delay : unsigned(3 DOWNTO 0);
  SIGNAL reset_cpt : uint7;
  
  TYPE enum_state IS (sRESET,sRESET2,sRESET3,sIDLE,sWAIT,
                      sCLR,sGAP,sDOWNLOAD);
  SIGNAL state : enum_state;
  
  SIGNAL led : uv8;
  SIGNAL ps2_i,ps2_o : uv4;
  SIGNAL iboot : std_logic :='0';
  SIGNAL swconf : uv8;
  SIGNAL cachena,l2tlbena : std_logic;
  
  -- SCSI
  SIGNAL scsi_sel,scsi_bis : std_logic;
  SIGNAL scsi_w,scsi0_mist_w,scsi1_mist_w,scsi6_mist_w,scsi_sd_w : type_scsi_w;
  SIGNAL scsi_r,scsi0_mist_r,scsi1_mist_r,scsi6_mist_r,scsi_sd_r : type_scsi_r;
  SIGNAL disk_busy,busy0_mist,busy1_mist,busy6_mist,busy_sd  : std_logic;
  SIGNAL id_sd,id0_mist,id1_mist,id6_mist : unsigned(2 DOWNTO 0);
  SIGNAL sd_reg_w : type_sd_reg_w;
  SIGNAL sd_reg_r : type_sd_reg_r;
  SIGNAL sd_clk_o  : std_logic;
  SIGNAL sd_clk_i  : std_logic;
  SIGNAL sd_dat_o  : unsigned(3 DOWNTO 0);
  SIGNAL sd_dat_i  : unsigned(3 DOWNTO 0);
  SIGNAL sd_dat_en : std_logic;
  SIGNAL sd_cmd_o  : std_logic;
  SIGNAL sd_cmd_i  : std_logic;
  SIGNAL sd_cmd_en : std_logic;

  -- RTC
  SIGNAL rtcinit  : unsigned(43 DOWNTO 0);
  SIGNAL rtcset   : std_logic;
  
  -- SD/MMC
  SIGNAL scsi_disks : uv2;

  SIGNAL ddram_address_i,ddram2_address_i : std_logic_vector(28 DOWNTO 0);
  
  -- PHY Ethernet (absent)
  SIGNAL phy_mdio_o,phy_mdc,phy_mdio_i : std_logic;
  SIGNAL phy_mdio_en,phy_int_n,phy_reset_n : std_logic;
  SIGNAL phy_txd,phy_rxd : uv4;
  SIGNAL phy_tx_en,phy_tx_er,phy_col : std_logic;
  SIGNAL phy_rx_dv,phy_rx_er,phy_crs : std_logic;
  SIGNAL phy_tx_clk,phy_rx_clk : std_logic;
  
  -- Video
  SIGNAL vga_clk : std_logic;
  CONSTANT vga_en : std_logic :='1';
  SIGNAL vga_gg,vga_rr,vga_bb : uv8;
  SIGNAL iic1_scl,iic1_sda_i,iic1_sda_o : std_logic;
  SIGNAL iic1_scl_pre,iic1_sda_o_pre : std_logic;
  SIGNAL iic2_scl,iic2_sda_i,iic2_sda_o : std_logic;
  SIGNAL iic3_scl,iic3_sda_i,iic3_sda_o : std_logic;
  
  ------------------------------------
  -- HPS Signals
  CONSTANT CONF_STR : string := 
    "SparcStation;;" &
    "F,ROM,BIOS;" &
    "S0,RAW,HD;" &
    "S1,RAW,HD2;" &
    "S2,ISO,CDROM;" &
    "-;" &
    "T7,RESET;" &
    "OF,SCSI,HD Image,Direct SD/MMC;" &
    "O1,Second SCSI,OFF,ON;" &
    "OH,CDROM Sector,512,2048;" &
    "OG,Aspect ratio,4:3,16:9;" &
    "O3,AutoBoot,ON,OFF;" &
    "O6,Boot,Video,Serial;" &
    "O2,Video,TCX,CG3;" &
    "OC,Video,Internal,Scaler framebuffer;" &
    "ODE,Keyboard,US,FR,DE,ES;" &
    "O4,Cachena,On,Off;" &
    "O5,L2TLB,On,Off;" &
    "OJ,WB,WBOFF,WBON;" &
    "OK,AOW,AOWOFF,AOWON;" &
    "O8,Serial Port,Internal,External;" &
--    "O8,Serial Port,External,Internal;" &
    "O9A,IOMMU rev,26 (Default),11 (Next),23,30;" &
    "-;" &
    "V,r5";
-- 0         1         2         3          4         5         6   
-- 01234567890123456789012345678901 23456789012345678901234567890123
-- 0123456789ABCDEFGHIJKLMNOPQRSTUV 0123456789ABCDEFGHIJKLMNOPQRSTUV
  
  -- convert string to std_logic_vector to be given to user_io
  FUNCTION to_slv(s: string) RETURN std_logic_vector IS
    CONSTANT ss: string(1 TO s'length) := s; 
    VARIABLE rval: std_logic_vector(1 TO 8 * s'length); 
    VARIABLE p,c: integer; 
  BEGIN
    FOR i IN ss'range LOOP
      p := 8 * i;
      c := character'pos(ss(i));
      rval(p - 7 to p) := std_logic_vector(to_unsigned(c,8)); 
    END LOOP; 
    RETURN rval; 
  END FUNCTION; 
  
  SIGNAL joystick_0         : std_logic_vector(15 DOWNTO 0);
  SIGNAL joystick_1         : std_logic_vector(15 DOWNTO 0);
  SIGNAL joystick_analog_0  : std_logic_vector(15 DOWNTO 0);
  SIGNAL joystick_analog_1  : std_logic_vector(15 DOWNTO 0);
  SIGNAL buttons            : std_logic_vector(1 DOWNTO 0);
  SIGNAL forced_scandoubler : std_logic;
  SIGNAL status             : std_logic_vector(31 DOWNTO 0);
  SIGNAL img_mounted        : std_logic_vector(2 DOWNTO 0);
  SIGNAL img_readonly       : std_logic;
  SIGNAL img0_readonly,img1_readonly,img6_readonly : std_logic;
  SIGNAL img_size           : std_logic_vector(63 DOWNTO 0);
  SIGNAL img0_size,img1_size,img6_size : std_logic_vector(63 DOWNTO 0);
  SIGNAL sd_lba,sd0_lba,sd1_lba,sd6_lba : std_logic_vector(31 DOWNTO 0);
  SIGNAL sd_rd : std_logic_vector(2 DOWNTO 0);
  SIGNAL sd_wr : std_logic_vector(2 DOWNTO 0);
  SIGNAL sd0_rd,sd1_rd,sd6_rd,sd0_wr,sd1_wr,sd6_wr : std_logic;
  SIGNAL sd_ack,sd_ack2,sd0_ack,sd1_ack,sd6_ack : std_logic;
  SIGNAL sd_conf            : std_logic :='0';
  SIGNAL sd_ack_conf        : std_logic;
  SIGNAL sd_buff_addr       : std_logic_vector(7 DOWNTO 0);
  SIGNAL sd_buff_dout       : std_logic_vector(15 DOWNTO 0);
  SIGNAL sd_buff_din        : std_logic_vector(15 DOWNTO 0);
  SIGNAL sd0_buff_din,sd1_buff_din,sd6_buff_din : std_logic_vector(15 DOWNTO 0);
  SIGNAL sd_buff_wr         : std_logic;
  SIGNAL sd0_buff_wr,sd1_buff_wr,sd6_buff_wr : std_logic;
  TYPE enum_scsimux IS (sIDLE,sREAD0,sREAD1,sREAD6,
                        sWRITE0,sWRITE1,sWRITE6,sWAIT);
  SIGNAL scsimux : enum_scsimux;
  SIGNAL cptwait : uint6;
  SIGNAL ssize : std_logic;
  
  SIGNAL ioctl_download     : std_logic;
  SIGNAL ioctl_download2    : std_logic;
  SIGNAL ioctl_index        : std_logic_vector(7 DOWNTO 0);
  SIGNAL ioctl_wr,ioctl_wr2 : std_logic;
  SIGNAL ioctl_addr         : std_logic_vector(24 DOWNTO 0);
  SIGNAL ioctl_dout         : std_logic_vector(15 DOWNTO 0);
  SIGNAL ioctl_wait         : std_logic :='0';
  SIGNAL RTC                : std_logic_vector(64 DOWNTO 0);
  SIGNAL ps2_kbd_clk_out    : std_logic;
  SIGNAL ps2_kbd_data_out   : std_logic;
  SIGNAL ps2_kbd_clk_in     : std_logic;
  SIGNAL ps2_kbd_data_in    : std_logic;
  SIGNAL ps2_kbd_led_status : std_logic_vector(2 DOWNTO 0);
  SIGNAL ps2_kbd_led_use    : std_logic_vector(2 DOWNTO 0);
  SIGNAL ps2_mouse_clk_out  : std_logic;
  SIGNAL ps2_mouse_data_out : std_logic;
  SIGNAL ps2_mouse_clk_in   : std_logic;
  SIGNAL ps2_mouse_data_in  : std_logic;
  
  SIGNAL rtc_delay : std_logic;
  SIGNAL reset_mask_rev,kbm_layout : uv8;
  SIGNAL dreset : std_logic;
  
  SIGNAL down : std_logic;

  SIGNAL ddram_s_readdata      : std_logic_vector(63 DOWNTO 0);
  SIGNAL ddram_s_writedata     : std_logic_vector(63 DOWNTO 0);
  SIGNAL ddram_s_byteenable    : std_logic_vector(7 DOWNTO 0);
    
  SIGNAL ddram2_s_readdata     : std_logic_vector(63 DOWNTO 0);
  SIGNAL ddram2_s_writedata    : std_logic_vector(63 DOWNTO 0);
  SIGNAL ddram2_s_byteenable   : std_logic_vector(7 DOWNTO 0);
  
  SIGNAL ddram2a_waitrequest  : std_logic;
  SIGNAL ddram2a_burstcount   ,ddram2b_burstcount : std_logic_vector(7 DOWNTO 0);
  SIGNAL ddram2a_address      ,ddram2b_address : std_logic_vector(28 DOWNTO 0);
  SIGNAL ddram2a_readdata      : std_logic_vector(63 DOWNTO 0);
  SIGNAL ddram2a_readdatavalid : std_logic;
  SIGNAL ddram2a_read          : std_logic;
  SIGNAL ddram2a_writedata    ,ddram2b_writedata : std_logic_vector(63 DOWNTO 0);
  SIGNAL ddram2a_byteenable   ,ddram2b_byteenable : std_logic_vector(7 DOWNTO 0);
  SIGNAL ddram2a_write        ,ddram2b_write : std_logic;
  
  SIGNAL wback,aow : std_logic;
  
  ------------------------------------
  
  COMPONENT hps_io
    GENERIC (
      STRLEN : integer;
      PS2DIV : integer := 1000;
      WIDE   : integer := 0;
      VDNUM  : integer := 3;
      PS2WE  : integer := 0);
    PORT (
      clk_sys           : IN  std_logic;
      hps_bus           : INOUT std_logic_vector(45 DOWNTO 0);
      conf_str          : IN  std_logic_vector(8*STRLEN-1 DOWNTO 0);
      joystick_0        : OUT std_logic_vector(31 DOWNTO 0);
      joystick_1        : OUT std_logic_vector(31 DOWNTO 0);
      joystick_2        : OUT std_logic_vector(31 DOWNTO 0);
      joystick_3        : OUT std_logic_vector(31 DOWNTO 0);
      joystick_4        : OUT std_logic_vector(31 DOWNTO 0);
      joystick_5        : OUT std_logic_vector(31 DOWNTO 0);
      joystick_analog_0 : OUT std_logic_vector(15 DOWNTO 0);
      joystick_analog_1 : OUT std_logic_vector(15 DOWNTO 0);
      joystick_analog_2 : OUT std_logic_vector(15 DOWNTO 0);
      joystick_analog_3 : OUT std_logic_vector(15 DOWNTO 0);
      joystick_analog_4 : OUT std_logic_vector(15 DOWNTO 0);
      joystick_analog_5 : OUT std_logic_vector(15 DOWNTO 0);
      buttons           : OUT std_logic_vector(1 DOWNTO 0);
      forced_scandoubler: OUT std_logic;
      status            : OUT std_logic_vector(31 DOWNTO 0);
      status_in         : IN  std_logic_vector(31 DOWNTO 0);
      status_set        : IN  std_logic;
      status_menumask   : IN  std_logic_vector(15 DOWNTO 0);
      new_vmode         : IN  std_logic;
      img_mounted       : OUT std_logic_vector(2 DOWNTO 0);
      img_readonly      : OUT std_logic;
      img_size          : OUT std_logic_vector(63 DOWNTO 0);
      sd_lba            : IN  std_logic_vector(31 DOWNTO 0);
      sd_rd             : IN  std_logic_vector(2 DOWNTO 0);
      sd_wr             : IN  std_logic_vector(2 DOWNTO 0);
      sd_ack            : OUT std_logic;
      sd_conf           : IN  std_logic;
      sd_ack_conf       : OUT std_logic;
      sd_buff_addr      : OUT std_logic_vector(8-WIDE DOWNTO 0);
      sd_buff_dout      : OUT std_logic_vector(7+WIDE*8 DOWNTO 0);
      sd_buff_din       : IN  std_logic_vector(7+WIDE*8 DOWNTO 0);
      sd_buff_wr        : OUT std_logic;
      ioctl_download    : OUT std_logic;
      ioctl_index       : OUT std_logic_vector(7 DOWNTO 0);
      ioctl_wr          : OUT std_logic;
      ioctl_addr        : OUT std_logic_vector(24 DOWNTO 0);
      ioctl_dout        : OUT std_logic_vector(7+WIDE*8 DOWNTO 0);
      ioctl_wait        : IN  std_logic;
      rtc               : OUT std_logic_vector(64 DOWNTO 0);
      timestamp         : OUT std_logic_vector(32 DOWNTO 0);
      uart_mode         : IN  std_logic_vector(15 DOWNTO 0);
      ps2_kbd_clk_out   : OUT std_logic;
      ps2_kbd_data_out  : OUT std_logic;
      ps2_kbd_clk_in    : IN  std_logic;
      ps2_kbd_data_in   : IN  std_logic;
      ps2_kbd_led_use   : IN  std_logic_vector(2 DOWNTO 0);
      ps2_kbd_led_status: IN  std_logic_vector(2 DOWNTO 0);
      ps2_mouse_clk_out : OUT std_logic;
      ps2_mouse_data_out: OUT std_logic;
      ps2_mouse_clk_in  : IN  std_logic;
      ps2_mouse_data_in : IN  std_logic;
      ps2_key           : OUT std_logic_vector(10 DOWNTO 0);
      ps2_mouse         : OUT std_logic_vector(24 DOWNTO 0);
      ps2_mouse_ext     : OUT std_logic_vector(15 DOWNTO 0));
  END COMPONENT hps_io;

  COMPONENT syspll IS
    PORT (
      refclk   : IN  std_logic := '0';
      rst      : IN  std_logic := '0';
      outclk_0 : OUT std_logic;
      outclk_1 : OUT std_logic;
      outclk_2 : OUT std_logic;
      locked   : OUT std_logic);
  END COMPONENT syspll;

  SIGNAL scsi6f_mist_w : type_scsi_w;
  SIGNAL scsi6f_mist_r : type_scsi_r;
  
BEGIN
  
  ------------------------------------------
  reset_mask_rev<=x"26" WHEN status(10 DOWNTO 9)="00" ELSE
                  x"11" WHEN status(10 DOWNTO 9)="01" ELSE
                  x"23" WHEN status(10 DOWNTO 9)="10" ELSE
                  x"30";

  -- PS2 to Sun keyboard layout
  -- "Layouts for Type 4, 5, and 5c Keyboards"
  -- "https://docs.oracle.com/cd/E19253-01/817-2521/new-311/index.html"
  -- 21 : USA,    QWERTY, ANSI layout
  -- 23 : France, AZERTY, ISO  layout
  -- 25 : Germany, QWERTZ
  -- 2A : Spain
  kbm_layout<=x"21" WHEN status(14 DOWNTO 13)="00" ELSE
              x"23" WHEN status(14 DOWNTO 13)="01" ELSE
              x"25" WHEN status(14 DOWNTO 13)="10" ELSE
              x"2A";
  
  fb_direct<=status(12);
  
  ------------------------------------------
  i_ts_core: ENTITY work.ts_core
    GENERIC MAP (
      ACIABREAK  => true,
      SS20       => SS20,
      NCPUS      => NCPUS,
      -- 12MB scaler + 2MB CG3/TCX + 2MB ROM
      RAMSIZE    => RAMSIZE,
      FPU_MULTI  => FPU_MULTI,
      ETHERNET   => false, --true, -- FAKE !
      PS2        => true,
      TCX_ACCEL  => TCX_ACCEL,
      SPORT2     => true,
      OBRAM_ADR   => OBRAM_ADRS,
      OBRAM_ADR_H => x"0",
      TCX_ADR    => TCX_ADRS,
      TCX_ADR_H  => x"0",
      OBRAM      => true,
      HWCONF     => HWCONF_MiSTer,
      TECH       => 0,
      TRACE      => TRACE,
      SYSFREQ    => SYSFREQ,
      SERIALRATE => 115200
      )
    PORT MAP (
      dram_pw     => dram_pw,
      dram_pr     => dram_pr,
      vram_pw     => vram_pw,
      vram_pr     => vram_pr,
      vga_r       => vga_r,
      vga_g       => vga_g,
      vga_b       => vga_b,
      vga_de      => vga_de,
      vga_hsyn    => vga_hs,
      vga_vsyn    => vga_vs,
      vga_clk     => vga_clk,
      vga_en      => vga_en,
      vga_dis     => status(12),
      pal_clk     => fb_pal_clk,
      pal_d       => fb_pal_d,
      pal_a       => fb_pal_a,
      pal_wr      => fb_pal_wr,
      scsi_w      => scsi_w,
      scsi_r      => scsi_r,
      scsi6_w     => scsi6f_mist_w,
      scsi6_r     => scsi6f_mist_r,
      sd_reg_w    => sd_reg_w,
      sd_reg_r    => sd_reg_r,
      scsi_disks  => scsi_disks,
      rtcinit     => rtcinit,
      rtcset      => rtcset,
      phy_txd     => phy_txd,
      phy_tx_clk  => phy_tx_clk,
      phy_tx_en   => phy_tx_en,
      phy_tx_er   => phy_tx_er,
      phy_col     => phy_col,
      phy_rxd     => phy_rxd,
      phy_rx_dv   => phy_rx_dv,
      phy_rx_er   => phy_rx_er,
      phy_rx_clk  => phy_rx_clk,
      phy_crs     => phy_crs,
      phy_mdc     => phy_mdc,
      phy_mdio_o  => phy_mdio_o,
      phy_mdio_en => phy_mdio_en,
      phy_mdio_i  => phy_mdio_i,
      phy_int_n   => phy_int_n,
      phy_reset_n => phy_reset_n,
      flash_w     => flash_w,
      flash_r     => flash_r,
      ibram_w     => ibram_w,
      ibram_r     => ibram_r,
      iboot       => iboot,
      iic1_scl    => iic1_scl,
      iic1_sda_o  => iic1_sda_o,
      iic1_sda_i  => iic1_sda_i,
      iic2_scl    => iic2_scl,
      iic2_sda_o  => iic2_sda_o,
      iic2_sda_i  => iic2_sda_i,
      iic3_scl    => iic3_scl,
      iic3_sda_o  => iic3_sda_o,
      iic3_sda_i  => iic3_sda_i,
      rxd1        => rxd1,
      rxd2        => rxd2,
      rxd3        => rxd3,
      rxd4        => rxd4,
      txd1        => txd1,
      txd2        => txd2,
      txd3        => txd3,
      txd4        => txd4,
      cts         => cts,
      rts         => rts,
      led         => led,
      ps2_i       => ps2_i,
      ps2_o       => ps2_o,
      reset       => preset,
      reset_na    => reset_na,
      reset_mask_rev => reset_mask_rev,
      kbm_layout  => kbm_layout,
      swconf      => swconf,
      cachena     => cachena,
      l2tlbena    => l2tlbena,
      wback       => wback,
      aow         => aow,
      dreset      => dreset,
      sclk        => sclk);
  
  vga_f1<='0';
  vga_sl<="00";
  
  ----------------------------------------------------------
  i_hps_io : hps_io
    GENERIC MAP (
      STRLEN => CONF_STR'length,
      WIDE   => 1)
    PORT MAP (
      clk_sys            => sclk,
      hps_bus            => hps_bus,
      conf_str           => to_slv(CONF_STR),
      joystick_0         => OPEN,
      joystick_1         => OPEN,
      joystick_2         => OPEN,
      joystick_3         => OPEN,
      joystick_4         => OPEN,
      joystick_5         => OPEN,
      joystick_analog_0  => OPEN,
      joystick_analog_1  => OPEN,
      joystick_analog_2  => OPEN,
      joystick_analog_3  => OPEN,
      joystick_analog_4  => OPEN,
      joystick_analog_5  => OPEN,
      buttons            => OPEN,
      forced_scandoubler => OPEN,
      status             => status,
      status_in          => status,
      status_set         => '0',
      status_menumask    => x"0000",
      new_vmode          => '0',
      img_mounted        => img_mounted,
      img_readonly       => img_readonly,
      img_size           => img_size,
      sd_lba             => sd_lba,
      sd_rd              => sd_rd,
      sd_wr              => sd_wr,
      sd_ack             => sd_ack,
      sd_conf            => sd_conf,
      sd_ack_conf        => sd_ack_conf,
      sd_buff_addr       => sd_buff_addr,
      sd_buff_dout       => sd_buff_dout,
      sd_buff_din        => sd_buff_din,
      sd_buff_wr         => sd_buff_wr,
      ioctl_download     => ioctl_download,
      ioctl_index        => ioctl_index,
      ioctl_wr           => ioctl_wr,
      ioctl_addr         => ioctl_addr,
      ioctl_dout         => ioctl_dout,
      ioctl_wait         => ioctl_wait,
      rtc                => RTC,
      timestamp          => OPEN,
      uart_mode          => x"0000",
      ps2_kbd_clk_out    => ps2_kbd_clk_out,
      ps2_kbd_data_out   => ps2_kbd_data_out,
      ps2_kbd_clk_in     => ps2_kbd_clk_in,
      ps2_kbd_data_in    => ps2_kbd_data_in,
      ps2_kbd_led_status => ps2_kbd_led_status,
      ps2_kbd_led_use    => ps2_kbd_led_use,
      ps2_mouse_clk_out  => ps2_mouse_clk_out,
      ps2_mouse_data_out => ps2_mouse_data_out,
      ps2_mouse_clk_in   => ps2_mouse_clk_in,
      ps2_mouse_data_in  => ps2_mouse_data_in,
      ps2_key            => OPEN,
      ps2_mouse          => OPEN);
  
  ----------------------------------------------------------
  i_scsi_mist: ENTITY work.scsi_mist
    GENERIC MAP (SYSFREQ => SYSFREQ)
    PORT MAP (
      scsi_w     => scsi0_mist_w,
      scsi_r     => scsi0_mist_r,
      id         => id0_mist,
      busy       => busy0_mist,
      hd_lba     => sd0_lba,
      hd_rd      => sd0_rd,
      hd_wr      => sd0_wr,
      hd_ack     => sd0_ack,
      hdb_adrs   => sd_buff_addr,
      hdb_dw     => sd_buff_dout,
      hdb_dr     => sd0_buff_din,
      hdb_wr     => sd0_buff_wr,
      hd_size    => img0_size,
      hd_mounted => img_mounted(0),
      hd_ro      => img0_readonly,
      clk        => sclk,
      reset_na   => reset_na);
  
  id0_mist<="00" & scsi_sel;
  
  ----------------------------------------------------------
  i_scsi_mist2: ENTITY work.scsi_mist
    GENERIC MAP (SYSFREQ => SYSFREQ)
    PORT MAP (
      scsi_w     => scsi1_mist_w,
      scsi_r     => scsi1_mist_r,
      id         => id1_mist,
      busy       => busy1_mist,
      hd_lba     => sd1_lba,
      hd_rd      => sd1_rd,
      hd_wr      => sd1_wr,
      hd_ack     => sd1_ack,
      hdb_adrs   => sd_buff_addr,
      hdb_dw     => sd_buff_dout,
      hdb_dr     => sd1_buff_din,
      hdb_wr     => sd1_buff_wr,
      hd_size    => img1_size,
      hd_mounted => img_mounted(1),
      hd_ro      => img1_readonly,
      clk        => sclk,
      reset_na   => reset_na);
  
  id1_mist<="010";
  
  ----------------------------------------------------------
  i_scsi_mist6: ENTITY work.scsi_mist_cdrom
    GENERIC MAP (SYSFREQ => SYSFREQ)
    PORT MAP (
      scsi_w     => scsi6_mist_w,
      scsi_r     => scsi6_mist_r,
      id         => id6_mist,
      busy       => busy6_mist,
      hd_lba     => sd6_lba,
      hd_rd      => sd6_rd,
      hd_wr      => sd6_wr,
      hd_ack     => sd6_ack,
      hdb_adrs   => sd_buff_addr,
      hdb_dw     => sd_buff_dout,
      hdb_dr     => sd6_buff_din,
      hdb_wr     => sd6_buff_wr,
      hd_size    => img6_size,
      hd_mounted => img_mounted(2),
      hd_ro      => img6_readonly,
      ssize      => ssize,
      clk        => sclk,
      reset_na   => reset_na);
  
  id6_mist<="110";
  ssize<=status(17);
  wback<=status(19);
  aow<=status(20);
  
  ----------------------------------------------------------
  -- SS5 SCSI ID (SunOS) :
  -- 0 External disk drive
  -- 1 Internal HD
  -- 2 External disk drive
  -- 3 Internal HD
  -- 4 External tape drive
  -- 5 External tape drive
  -- 6 Internal / External CDROM
  -- 7 [HOST]
  
  ----------------------------------------------------------
  PROCESS(sclk) IS
  BEGIN
    IF rising_edge(sclk) THEN
      ----------------------------------
      IF img_mounted(0)='1' THEN
        img0_size<=img_size;
        img0_readonly<=img_readonly;
      END IF;
      IF img_mounted(1)='1' THEN
        img1_size<=img_size;
        img1_readonly<=img_readonly;
      END IF;
      IF img_mounted(2)='1' THEN
        img6_size<=img_size;
        img6_readonly<=img_readonly;
      END IF;
      
      ----------------------------------
      sd_ack2<=sd_ack;
      CASE scsimux IS
        WHEN sIDLE =>
          cptwait<=0;
          IF sd0_rd='1' THEN
            scsimux<=sREAD0;
          ELSIF sd0_wr='1' THEN
            scsimux<=sWRITE0;
          ELSIF sd1_rd='1' THEN
            scsimux<=sREAD1;
          ELSIF sd1_wr='1' THEN
            scsimux<=sWRITE1;
          ELSIF sd6_rd='1' THEN
            scsimux<=sREAD6;
          ELSIF sd6_wr='1' THEN
            scsimux<=sWRITE6;
          END IF;
          
        WHEN sREAD0 =>
          IF sd_ack='0' AND sd_ack2='1' THEN scsimux<=sWAIT; END IF;
        WHEN sREAD1 =>
          IF sd_ack='0' AND sd_ack2='1' THEN scsimux<=sWAIT; END IF;
        WHEN sREAD6 =>
          IF sd_ack='0' AND sd_ack2='1' THEN scsimux<=sWAIT; END IF;
        WHEN sWRITE0 =>
          IF sd_ack='0' AND sd_ack2='1' THEN scsimux<=sWAIT; END IF;
        WHEN sWRITE1 =>
          IF sd_ack='0' AND sd_ack2='1' THEN scsimux<=sWAIT; END IF;
        WHEN sWRITE6 =>
          IF sd_ack='0' AND sd_ack2='1' THEN scsimux<=sWAIT; END IF;

        WHEN sWAIT =>
          cptwait<=cptwait+1;
          IF cptwait=31 THEN
            scsimux<=sIDLE;
          END IF;
          
      END CASE;
      ----------------------------------
    END IF;
  END PROCESS;
  
  sd_rd(0)<=to_std_logic(scsimux=sREAD0)  AND NOT sd_ack2;
  sd_rd(1)<=to_std_logic(scsimux=sREAD1)  AND NOT sd_ack2;
  sd_rd(2)<=to_std_logic(scsimux=sREAD6)  AND NOT sd_ack2;
  sd_wr(0)<=to_std_logic(scsimux=sWRITE0) AND NOT sd_ack2;
  sd_wr(1)<=to_std_logic(scsimux=sWRITE1) AND NOT sd_ack2;
  sd_wr(2)<=to_std_logic(scsimux=sWRITE6) AND NOT sd_ack2;
  
  sd0_ack<=sd_ack AND to_std_logic(scsimux=sREAD0 OR scsimux=sWRITE0);
  sd1_ack<=sd_ack AND to_std_logic(scsimux=sREAD1 OR scsimux=sWRITE1);
  sd6_ack<=sd_ack AND to_std_logic(scsimux=sREAD6 OR scsimux=sWRITE6);
  sd0_buff_wr<=sd_buff_wr AND to_std_logic(scsimux=sREAD0 OR scsimux=sWRITE0);
  sd1_buff_wr<=sd_buff_wr AND to_std_logic(scsimux=sREAD1 OR scsimux=sWRITE1);
  sd6_buff_wr<=sd_buff_wr AND to_std_logic(scsimux=sREAD6 OR scsimux=sWRITE6);

  sd_buff_din<=sd1_buff_din WHEN scsimux=sREAD1 OR scsimux=sWRITE1 ELSE
               sd6_buff_din WHEN scsimux=sREAD6 OR scsimux=sWRITE6 ELSE
               sd0_buff_din;
  sd_lba<=sd1_lba WHEN scsimux=sREAD1 OR scsimux=sWRITE1 ELSE
          sd6_lba WHEN scsimux=sREAD6 OR scsimux=sWRITE6 ELSE
          sd0_lba;
  
  ----------------------------------------------------------
  i_scsi_sd: ENTITY work.scsi_sd
    GENERIC MAP (SYSFREQ => SYSFREQ)
    PORT MAP (
      scsi_w    => scsi_sd_w,
      scsi_r    => scsi_sd_r,
      id        => id_sd,
      busy      => busy_sd,
      sd_clk_o  => sd_clk_o,
      sd_clk_i  => sd_clk_i,
      sd_dat_o  => sd_dat_o,
      sd_dat_i  => sd_dat_i,
      sd_dat_en => sd_dat_en,
      sd_cmd_o  => sd_cmd_o,
      sd_cmd_i  => sd_cmd_i,
      sd_cmd_en => sd_cmd_en,
      reg_w     => sd_reg_w,
      reg_r     => sd_reg_r,
      clk       => sclk,
      reset_na  => reset_na);
  
  id_sd<="00" & NOT scsi_sel;
  
  sd_sck<=sd_clk_o;
  sd_clk_i<=sd_clk_o;
  
  sd_dat<=std_logic_vector(sd_dat_o) WHEN sd_dat_en='1' ELSE "ZZZZ";
  sd_dat_i<=unsigned(sd_dat);
  
  sd_cmd<=sd_cmd_o WHEN sd_cmd_en='1' ELSE 'Z';
  sd_cmd_i<=sd_cmd;
  
  ----------------------------------------------------------
  MUX_SCSI:PROCESS(scsi0_mist_r,scsi1_mist_r,scsi6_mist_r,scsi_sd_r,
                   scsi_w,scsi_sel,scsi_bis) IS
  BEGIN
    scsi0_mist_w<=scsi_w;
    scsi1_mist_w<=scsi_w;
    scsi6_mist_w<=scsi_w;
    scsi_sd_w <=scsi_w;
    
    IF scsi_bis='0' THEN -- 1 disk
      IF scsi_sel='0' THEN -- HD IMAGE
        IF scsi0_mist_r.sel='1' THEN
          scsi_r<=scsi0_mist_r;
        ELSIF scsi6_mist_r.sel='1' THEN
          scsi_r<=scsi6_mist_r;
        ELSE
          scsi_r<=scsi1_mist_r;
        END IF;
      ELSE -- Direct SD/MMC
        IF scsi1_mist_r.sel='1' THEN
          scsi_r<=scsi1_mist_r;
        ELSIF scsi6_mist_r.sel='1' THEN
          scsi_r<=scsi6_mist_r;
        ELSE
          scsi_r<=scsi_sd_r;
        END IF;
      END IF;
      
    ELSE -- 2 disks
      IF scsi_sd_r.sel='1' THEN
        scsi_r<=scsi_sd_r;
      ELSIF scsi1_mist_r.sel='1' THEN
        scsi_r<=scsi1_mist_r;
      ELSIF scsi6_mist_r.sel='1' THEN
        scsi_r<=scsi6_mist_r;
      ELSE
        scsi_r<=scsi0_mist_r;
      END IF;
      
      scsi_sd_w.bsy   <=scsi_w.bsy AND scsi_sd_r.sel;
      scsi_sd_w.ack   <=scsi_w.ack AND scsi_sd_r.sel;
      scsi_sd_w.atn   <=scsi_w.atn AND scsi_sd_r.sel;
      scsi0_mist_w.bsy<=scsi_w.bsy AND scsi0_mist_r.sel;
      scsi0_mist_w.ack<=scsi_w.ack AND scsi0_mist_r.sel;
      scsi0_mist_w.atn<=scsi_w.atn AND scsi0_mist_r.sel;
      scsi1_mist_w.bsy<=scsi_w.bsy AND scsi1_mist_r.sel;
      scsi1_mist_w.ack<=scsi_w.ack AND scsi1_mist_r.sel;
      scsi1_mist_w.atn<=scsi_w.atn AND scsi1_mist_r.sel;
      scsi6_mist_w.bsy<=scsi_w.bsy AND scsi6_mist_r.sel;
      scsi6_mist_w.ack<=scsi_w.ack AND scsi6_mist_r.sel;
      scsi6_mist_w.atn<=scsi_w.atn AND scsi6_mist_r.sel;
      
    END IF;
    
  END PROCESS MUX_SCSI;

  PROCESS(scsi6_mist_r,scsi6_mist_w) IS
  BEGIN
    scsi6f_mist_r<=scsi6_mist_r;
    scsi6f_mist_w<=scsi6_mist_w;
    IF scsi6_mist_w.did/="110" THEN
      scsi6f_mist_r.d<=x"00";
      scsi6f_mist_r.req<='0';
      scsi6f_mist_r.phase<="000";
      scsi6f_mist_r.sel<='0';
      scsi6f_mist_r.d_pc<="0000000000";
      
      scsi6f_mist_w.d<=x"00";
      scsi6f_mist_w.ack<='0';
      scsi6f_mist_w.bsy<='0';
      scsi6f_mist_w.atn<='0';
      scsi6f_mist_w.did<="000";
      scsi6f_mist_w.rst<='0';
      scsi6f_mist_w.d_state<="0000";
      
    END IF;
  END PROCESS;

  disk_busy<=(busy0_mist AND (scsi_bis OR NOT scsi_sel)) OR
              (busy_sd   AND (scsi_bis OR scsi_sel)) OR
              busy1_mist OR busy6_mist;
  
  ----------------------------------------------------------
  led_disk<=disk_busy & disk_busy WHEN rising_edge(sclk);
  
  ----------------------------------------------------------
  -- DDRAM2 : CPU + Download
  ddram2_burstcount<=ddram2a_burstcount WHEN down='0' ELSE
                     ddram2b_burstcount;
  ddram2_address_i <=ddram2a_address    WHEN down='0' ELSE
                     ddram2b_address;
  ddram2_read      <=ddram2a_read       WHEN down='0' ELSE
                     '0';
  ddram2_write     <=ddram2a_write      WHEN down='0' ELSE
                     ddram2b_write;
  ddram2_s_writedata <=ddram2a_writedata  WHEN down='0' ELSE
                     ddram2b_writedata;
  ddram2_s_byteenable<=ddram2a_byteenable WHEN down='0' ELSE
                     ddram2b_byteenable;

  ddram2a_readdata<=ddram2_s_readdata;
  ddram2a_readdatavalid<=ddram2_readdatavalid AND NOT down;
  ddram2a_waitrequest  <=ddram2_waitrequest;
  
  ddram2_clk<=sclk;

  ddram2_address<="001" & NOT ddram2_address_i(25 DOWNTO 17) &
                   ddram2_address_i(16 DOWNTO 0); -- 512 MB
  
  ----------------------------------------------------------
  -- DDRAM : VID
  ddram_clk<=sclk;
  
  ddram_address<="001" & NOT ddram_address_i(25 DOWNTO 17) &
                  ddram_address_i(16 DOWNTO 0); -- 512 MB
  
  ----------------------------------------------------------
  -- CPU
  i_plomb_avalon_dram: ENTITY work.plomb_avalon64
    GENERIC MAP (N => 32, RAMSIZE => RAMSIZE, HIMEM => OBRAM_ADRS)
    PORT MAP (
      pw                => dram_pw,
      pr                => dram_pr,
      avl_waitrequest   => ddram2a_waitrequest,
      avl_readdata      => ddram2a_readdata,
      avl_readdatavalid => ddram2a_readdatavalid,
      avl_burstbegin    => OPEN,
      avl_burstcount    => ddram2a_burstcount,
      avl_writedata     => ddram2a_writedata,
      avl_address       => ddram2a_address,
      avl_write         => ddram2a_write,
      avl_read          => ddram2a_read,
      avl_byteenable    => ddram2a_byteenable,
      clk               => sclk,
      reset_na          => reset_na);

  ----------------------------------------------------------
  -- VIDEO
  i_plomb_avalon_vram: ENTITY work.plomb_avalon64
    GENERIC MAP (N => 32, RAMSIZE => 0, HIMEM => x"0000_0000")
    PORT MAP (
      pw                => vram_pw,
      pr                => vram_pr,
      avl_waitrequest   => ddram_waitrequest,
      avl_readdata      => ddram_s_readdata,
      avl_readdatavalid => ddram_readdatavalid,
      avl_burstbegin    => OPEN,
      avl_burstcount    => ddram_burstcount,
      avl_writedata     => ddram_s_writedata,
      avl_address       => ddram_address_i,
      avl_write         => ddram_write,
      avl_read          => ddram_read,
      avl_byteenable    => ddram_s_byteenable,
      clk               => sclk,
      reset_na          => reset_na);

  ----------------------------------------------------------
  ddram_s_readdata<=
    ddram_readdata(7  DOWNTO 0)  & ddram_readdata(15 DOWNTO 8) &
    ddram_readdata(23 DOWNTO 16) & ddram_readdata(31 DOWNTO 24) &
    ddram_readdata(39 DOWNTO 32) & ddram_readdata(47 DOWNTO 40) &
    ddram_readdata(55 DOWNTO 48) & ddram_readdata(63 DOWNTO 56);
  
  ddram_writedata<=
    ddram_s_writedata(7  DOWNTO 0)  & ddram_s_writedata(15 DOWNTO 8) &
    ddram_s_writedata(23 DOWNTO 16) & ddram_s_writedata(31 DOWNTO 24) &
    ddram_s_writedata(39 DOWNTO 32) & ddram_s_writedata(47 DOWNTO 40) &
    ddram_s_writedata(55 DOWNTO 48) & ddram_s_writedata(63 DOWNTO 56);
  
  ddram_byteenable<=
    ddram_s_byteenable(0) & ddram_s_byteenable(1) &
    ddram_s_byteenable(2) & ddram_s_byteenable(3) &
    ddram_s_byteenable(4) & ddram_s_byteenable(5) &
    ddram_s_byteenable(6) & ddram_s_byteenable(7);
  
  ddram2_s_readdata<=
    ddram2_readdata(7  DOWNTO 0)  & ddram2_readdata(15 DOWNTO 8) &
    ddram2_readdata(23 DOWNTO 16) & ddram2_readdata(31 DOWNTO 24) &
    ddram2_readdata(39 DOWNTO 32) & ddram2_readdata(47 DOWNTO 40) &
    ddram2_readdata(55 DOWNTO 48) & ddram2_readdata(63 DOWNTO 56);
  
  ddram2_writedata<=
    ddram2_s_writedata(7  DOWNTO 0)  & ddram2_s_writedata(15 DOWNTO 8) &
    ddram2_s_writedata(23 DOWNTO 16) & ddram2_s_writedata(31 DOWNTO 24) &
    ddram2_s_writedata(39 DOWNTO 32) & ddram2_s_writedata(47 DOWNTO 40) &
    ddram2_s_writedata(55 DOWNTO 48) & ddram2_s_writedata(63 DOWNTO 56);
  
  ddram2_byteenable<=
    ddram2_s_byteenable(0) & ddram2_s_byteenable(1) &
    ddram2_s_byteenable(2) & ddram2_s_byteenable(3) &
    ddram2_s_byteenable(4) & ddram2_s_byteenable(5) &
    ddram2_s_byteenable(6) & ddram2_s_byteenable(7);
  
  ----------------------------------------------------------
  -- HDMI
  vga_clk<=clk65m;
  
  clk_video<=vga_clk;
  ce_pixel<='1';
  
  video_arx <= x"04" WHEN status(16)='0' ELSE x"16";
  video_ary <= x"03" WHEN status(16)='0' ELSE x"09";
  
  --HDMI_SCL<='0' WHEN iic1_scl='0'   ELSE 'Z';
  --HDMI_SDA<='0' WHEN iic1_sda_o='0' ELSE 'Z';
  --iic1_sda_i<=HDMI_SDA;
  
  ----------------------------------------------------------
  -- UART
  debug_txd<=txd3;
  rxd3<=debug_rxd WHEN status(8)='1' ELSE uart_rxd;

  uart_txd<=txd3;
  --rxd3<=uart_rxd;
  uart_rts<='1';
  uart_dtr<='1';
  
  ps2_kbd_data_in <=ps2_o(0);
  ps2_kbd_clk_in  <=ps2_o(1);
  ps2_mouse_data_in <=ps2_o(2);
  ps2_mouse_clk_in  <=ps2_o(3);
  
  ps2_i(0)<=ps2_kbd_data_out;
  ps2_i(1)<=ps2_kbd_clk_out;
  ps2_i(2)<=ps2_mouse_data_out;
  ps2_i(3)<=ps2_mouse_clk_out;

  sdram_dq(7 DOWNTO 0)<=std_logic_vector(ps2_o) & std_logic_vector(ps2_i);
  
  ----------------------------------------------------------
  -- RTC
  --   0: second       1:  10 seconds
  --   2: 1 minute     3:  10 minutes
  --   4: 1 hour       5: 10 hour / PM/AM
  --   6: 1 day        7: 10 day
  --   8: 1 month      9: 10 month
  --  10: 1 year      11: 10 year
  --  12: week
  -- RTCINIT : 7D | 10Y|Y | 10M|M | 10D|D | 10H|H | 10S|S
  rtcinit(43 DOWNTO 40)<=unsigned(RTC(43 DOWNTO 40))-1; -- W
  rtcinit(39 DOWNTO 32)<=unsigned(RTC(39 DOWNTO 32)); -- 10Y/Y
  rtcinit(31 DOWNTO 24)<=unsigned(RTC(31 DOWNTO 24)); -- 10M/M
  rtcinit(23 DOWNTO 16)<=unsigned(RTC(23 DOWNTO 16)); -- 10D/D
  rtcinit(15 DOWNTO  8)<=unsigned(RTC(15 DOWNTO  8)); -- 10H/H
  rtcinit( 7 DOWNTO  0)<=unsigned(RTC( 7 DOWNTO  0)); -- 10S/S
  
  rtc_delay<=RTC(64) WHEN rising_edge(sclk);
  rtcset<=RTC(64) XOR rtc_delay WHEN rising_edge(sclk);
  
  ----------------------------------------------------------
  -- SWCONF :
  --  0 : 0=HD image SCSI    1=SD raw SCSI
  --  1 : 0=Single SCSI      1=Dual SCSI
  --  2 : 0=TCX              1=CG3
  --  3 : 0=AutoBoot         1=NoAutoBoot
  --  4 :                    1=Cachena
  --  5 :
  --  6 : 0=Serial           1=Video  
  --  7 : RESET
  swconf<=unsigned(status(7) & NOT status(6) & NOT status(5) & NOT status(4) &
                   status(3 DOWNTO 1) & status(15)) WHEN rising_edge(sclk);
  
  scsi_sel<=swconf(0);
  scsi_bis<=swconf(1);
  cachena <=swconf(4);
  l2tlbena<=swconf(5);
  
  ----------------------------------------------------------
  i_syspll: syspll
    PORT MAP (
      refclk   => clk_50m,
      rst      => '0',--reset,
      outclk_0 => clk65m,
      outclk_1 => clk80m,
      outclk_2 => clk40m,
      locked   => spll_locked);
  
  --sclk<=clk_50m;
  --sclk<=clk65m;
  --sclk<=clk40m;
  
  gen40:IF SYSFREQ=40_000_000 GENERATE
     sclk<=clk40m;
  END GENERATE;
  
  gen50:IF SYSFREQ=50_000_000 GENERATE
     sclk<=clk_50m;
  END GENERATE;

  gen65:IF SYSFREQ=65_000_000 GENERATE
     sclk<=clk65m;
  END GENERATE;

  ASSERT SYSFREQ=40_000_000 OR SYSFREQ=50_000_000 OR SYSFREQ=65_000_000
    SEVERITY failure;  
  
  -- 125MHz/2 = 62.5MHz
  --vga_clk<=NOT vga_clk WHEN rising_edge(clock_125_p);
  
  -----------------------------------
  PROCESS(sclk) IS
  BEGIN
    IF rising_edge(sclk) THEN
      presetx<=presetx(1 TO 7) & ( spll_locked AND NOT reset);
    END IF;
  END PROCESS;
  preset_na<=presetx(0);
  
  -----------------------------------
  PROCESS(sclk,preset_na) IS
    VARIABLE a : std_logic_vector(31 DOWNTO 0);
  BEGIN
    IF preset_na='0' THEN
      state<=sRESET;
      down<='0';
      reset_na<='0';
      ioctl_wait<='1';
      halt<='0';
      
    ELSIF rising_edge(sclk) THEN
      
      ioctl_wr2<=ioctl_wr;
      
      CASE state IS
        WHEN sRESET =>
          down<='0';
          reset_na<='0';
          ioctl_wait<='1';
          halt<='0';
          state<=sRESET2;

        WHEN sRESET2 =>
          down<='0';
          reset_na<='0';
          ioctl_wait<='1';
          halt<='0';
          state<=sRESET3;
          
        WHEN sRESET3 =>
          down<='0';
          reset_na<='0';
          ioctl_wait<='1';
          halt<='0';
          state<=sIDLE;
          
        WHEN sIDLE =>
          down<='0';
          reset_na<='1';
          ioctl_wait<='0';
          halt<='0';
          IF ioctl_download='1' THEN
            state<=sWAIT;
            ioctl_wait<='1';
          END IF;
          ioctl_cpt<=0;
          IF dreset='1' OR status(7)='1' THEN
            state<=sRESET;
          END IF;
          
        WHEN sWAIT =>
          down<='0';
          reset_na<='1';
          ioctl_wait<='1';
          halt<='1';
          IF ioctl_cpt=127 THEN
            state<=sCLR;
          END IF;
          ioctl_cpt<=ioctl_cpt+1;
          ddram2b_address<="00100000000000000000000000000";
          
        WHEN sCLR =>
          down<='1';
          ioctl_wait<='1';
          reset_na<='1';
          halt<='1';
          
          ddram2b_write<=down;
          ddram2b_writedata<=x"0000_0000_0000_0000";
          ddram2b_burstcount<=x"08";
          ddram2b_byteenable<=x"FF";
          IF ddram2_waitrequest='0' AND ddram2b_write='1' THEN
            ddram2b_address<=std_logic_vector(unsigned(ddram2b_address)+1);
            if ddram2b_address(2 DOWNTO 0)="111" THEN
              state<=sGAP;
              ddram2b_write<='0';
            END IF;
          END IF;
          
        WHEN sGAP =>
          down<='1';
          ioctl_wait<='1';
          reset_na<='1';
          halt<='1';
          
          IF ddram2b_address="01000000000000000000000000000" THEN
            state<=sDOWNLOAD;
          ELSE
            state<=sCLR;
          END IF;
          
        WHEN sDOWNLOAD =>
          a:=std_logic_vector(OBRAM_ADRS);
          a(19 DOWNTO 0):=ioctl_addr(19 DOWNTO 0);
          
          ddram2b_address<=a(31 DOWNTO 3);
          IF a(2)='0' AND a(1)='0' THEN
            ddram2b_byteenable<="11000000";
          ELSIF a(2)='0' AND a(1)='1' THEN
            ddram2b_byteenable<="00110000";
          ELSIF a(2)='1' AND a(1)='0' THEN
            ddram2b_byteenable<="00001100";
          ELSE -- "11"
            ddram2b_byteenable<="00000011";
          END IF;
          
          ddram2b_writedata<=
            ioctl_dout(7 DOWNTO 0) & ioctl_dout(15 DOWNTO 8) &
            ioctl_dout(7 DOWNTO 0) & ioctl_dout(15 DOWNTO 8) &
            ioctl_dout(7 DOWNTO 0) & ioctl_dout(15 DOWNTO 8) &
            ioctl_dout(7 DOWNTO 0) & ioctl_dout(15 DOWNTO 8);
          ddram2b_burstcount<=x"01";
          
          IF ioctl_wr='1' AND ioctl_wr2='0' THEN
            ddram2b_write<='1';
            ioctl_wait<='1';
          END IF;
          IF ddram2b_write='1' AND ddram2_waitrequest='0' THEN
            ddram2b_write<='0';
            ioctl_wait<='0';
          END IF;
          
          down<='1';
          reset_na<='0';
          ioctl_wait<='0';
          halt<='1';
          IF ioctl_download='0' THEN
            state<=sIDLE;
          END IF;
            
      END CASE;
      
    END IF;
  END PROCESS;
  
  led_user<=down;
  led_power<=preset & preset;
  
  -- 2000 0000
  -- 3FFF FFFF

  -- 512MB : 2000 0000 
  --         1FFF FFF8 [28:3] => [25:0]
  
  -----------------------------------
  -- RESET Processeur
  GenReset: PROCESS (sclk,reset_na) IS
  BEGIN
    IF reset_na='0' THEN
      preset<='1';
      preset_delay<="0000";
    ELSIF rising_edge(sclk) THEN
      IF preset_delay="1111" THEN
        preset<='0';
      ELSE
        preset<='1';
      END IF;
      preset_delay<=preset_delay(2 DOWNTO 0) & '1';

      IF halt='1' THEN
        preset<='1';
      END IF;
    END IF;
  END PROCESS GenReset;
  
  
  
END ARCHITECTURE rtl;
      
    
