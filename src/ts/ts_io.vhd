--------------------------------------------------------------------------------
-- TEM : TS
-- Toutes les I/O
--------------------------------------------------------------------------------
-- DO 12/2010
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.plomb_pack.ALL;
USE work.asi_pack.ALL;
USE work.ts_pack.ALL;

ENTITY ts_io IS
  GENERIC (
    SS20       : boolean;
    ETHERNET   : boolean;
    PS2        : boolean;
    TCX_ACCEL  : boolean;
    SPORT2     : boolean;
    TCX_ADR    : uv32;
    TCX_ADR_H  : uv4;
    HWCONF     : uv8;
    SYSFREQ    : natural := 50_000_000;
    CPU0       : boolean := true;
    CPU1       : boolean := false;
    CPU2       : boolean := false;
    CPU3       : boolean := false;
    TRACE      : boolean := true;
    IOMMU_VER  : uv8     := x"04");
  PORT (
    -- Ports série
    led         : OUT std_logic;
    ps2_i       : IN  uv4;
    ps2_o       : OUT uv4;
    sync_rs     : IN  std_logic;
    rxd1        : IN  std_logic;           -- KB
    txd1        : OUT std_logic;           -- KB
    rxd2        : IN  std_logic;           -- Mouse
    txd2        : OUT std_logic;           -- (Mouse)
    rxd4        : IN  std_logic;           -- SPORT 2
    txd4        : OUT std_logic;           -- SPORT 2
    
    rxd3_data   : IN  uv8;              -- SPORT1  / DEBUG
    rxd3_req    : IN  std_logic;
    rxd3_ack    : OUT std_logic;
    txd3_data   : OUT uv8;
    txd3_req    : OUT std_logic;
    txd3_rdy    : IN  std_logic;
    
    -- Video
    vga_r       : OUT uv8;
    vga_g       : OUT uv8;
    vga_b       : OUT uv8;
    vga_de      : OUT std_logic;
    vga_hsyn    : OUT std_logic;
    vga_vsyn    : OUT std_logic;
    vga_hpos    : OUT uint12;
    vga_vpos    : OUT uint12;
    vga_clk     : IN  std_logic;
    vga_en      : IN  std_logic;
    vga_on      : IN  std_logic;
    pal_clk     : OUT std_logic;
    pal_d       : OUT uv24;
    pal_a       : OUT uv8;
    pal_wr      : OUT std_logic;
    
    -- SCSI
    scsi_w      : OUT type_scsi_w;
    scsi_r      : IN  type_scsi_r;
    sd_reg_w    : OUT type_sd_reg_w;
    sd_reg_r    : IN  type_sd_reg_r;

    -- RTC init.
    rtcinit     : IN unsigned(43 DOWNTO 0);
    rtcset      : IN std_logic;
    
    -- Ethernet MII / RMII
    phy_txd     : OUT uv4;       -- MII/RMII Data
    phy_tx_clk  : IN  std_logic;
    phy_tx_en   : OUT std_logic; -- MII/RMII Transmit Enable
    phy_tx_er   : OUT std_logic; -- MII/RMII Transmit Error
    
    phy_col     : IN  std_logic; -- MII/RMII Collision (async.)
    
    phy_rxd     : IN  uv4;       -- MII/RMII Data
    phy_rx_dv   : IN  std_logic; -- MII/RMII Receive Data Valid
    phy_rx_er   : IN  std_logic; -- MII/RMII Receive Error
    phy_rx_clk  : IN  std_logic; -- MII/RMII Receive Clock 25MHz/2.5MHz
    
    phy_crs     : IN  std_logic; -- MII/RMII Carrier Sense (async.)
    
    -- Ethernet MDIO
    phy_mdc     : OUT std_logic;
    phy_mdio_o  : OUT std_logic;
    phy_mdio_en : OUT std_logic;
    phy_mdio_i  : IN  std_logic;
    phy_int_n   : IN  std_logic;
    phy_reset_n : OUT std_logic;    
    
    -- Interruptions
    irl0        : OUT uv4;
    irl1        : OUT uv4;
    irl2        : OUT uv4;
    irl3        : OUT uv4;
    
    -- Bus périphériques
    io_w        : IN  type_pvc_w;
    io_r        : OUT type_pvc_r;
    
    -- Bus Plomb
    iommu_pw    : OUT type_plomb_w;            -- PLOMB Ethernet/SCSI IOMMU
    iommu_pr    : IN  type_plomb_r;            -- PLOMB Ethernet/SCSI IOMMU
    vid_pw      : OUT type_plomb_w;            -- PLOMB Video
    vid_pr      : IN  type_plomb_r;            -- PLOMB Video

    -- FLASH
    flash_w     : OUT type_pvc_w;
    flash_r     : IN  type_pvc_r;
    ibram_w     : OUT type_pvc_w;
    ibram_r     : IN  type_pvc_r;

    -- I²C
    iic1_scl    : OUT std_logic;
    iic1_sda_o  : OUT std_logic;
    iic1_sda_i  : IN  std_logic;
    iic2_scl    : OUT std_logic;
    iic2_sda_o  : OUT std_logic;
    iic2_sda_i  : IN  std_logic;
    iic3_scl    : OUT std_logic;
    iic3_sda_o  : OUT std_logic;
    iic3_sda_i  : IN  std_logic;

    -- Direct
    reset_mask_rev : IN uv8;
    kbm_layout  : IN  uv8;
    swconf      : IN  uv8;
    
    -- Global
    stopa       : IN  std_logic;
    iboot       : IN  std_logic;        -- 1=Boot RAM interne, 0=Boot FLASH
    clk         : IN  std_logic;
    reset_n     : IN  std_logic
    );
END ENTITY ts_io;

--##############################################################################

ARCHITECTURE rtl OF ts_io IS
  
--------------------------------------------------------------------------------
  SIGNAL sel,sel2 : type_sel;
  SIGNAL int_ether,int_sport : std_logic;
  SIGNAL int_kbm,int_timer_s : std_logic;
  SIGNAL int_timer_p0,int_timer_p1,int_timer_p2,int_timer_p3 : std_logic;
  SIGNAL dmaux_r,inter_r,iommu_r,lance_r : type_pvc_r;
  SIGNAL rtc_r,sport1_r,sport2_r,timer_r,vid_r : type_pvc_r;
  
  -- Ports série
  SIGNAL di1_data,di2_data,di3_data,di4_data : uv8;
  SIGNAL di1_req,di2_req,di3_req,di4_req : std_logic;
  SIGNAL di1_rdy,di2_rdy,di3_rdy,di4_rdy : std_logic;
  
  SIGNAL do1_data,do2_data,do3_data,do4_data : uv8;
  SIGNAL do1_req,do2_req,do3_req,do4_req : std_logic;
  SIGNAL do1_rdy,do2_rdy,do3_rdy,do4_rdy : std_logic;
  
  SIGNAL sync_kbm,sync_sport2 : std_logic;
  
  SIGNAL mux_pw : type_plomb_w;
  SIGNAL mux_pr : type_plomb_r;
  SIGNAL vi_w   : arr_plomb_w(0 TO 1);
  SIGNAL vi_r   : arr_plomb_r(0 TO 1);
  
  -- SCSI ESP
  SIGNAL esp_r   : type_pvc_r;
  SIGNAL esp_pw  : type_plomb_w;
  SIGNAL esp_pr  : type_plomb_r;
  SIGNAL esp_int : std_logic;
  SIGNAL dma_esp_addr_w,dma_esp_addr_r : uv32;
  SIGNAL dma_esp_addr_maj : std_logic;
  SIGNAL dma_esp_int,dma_esp_iena,dma_esp_reset,dma_esp_write : std_logic;
  
  -- SD/MMC
  SIGNAL sd_reg0_w,sd_reg0_r : uv32;
  SIGNAL sd_reg1_w,sd_reg1_r : uv32;
  SIGNAL sd_reg0_wr,sd_reg1_wr : std_logic;
  
  -- Ethernet
  SIGNAL eth_int : std_logic;
  SIGNAL dma_eth_iena : std_logic;
  SIGNAL dma_eth_reset : std_logic;
  SIGNAL dma_eth_ba : uv8;
  SIGNAL lance_pw : type_plomb_w;
  SIGNAL lance_pr : type_plomb_r;
  SIGNAL mac_emi_w : type_mac_emi_w;
  SIGNAL mac_emi_r : type_mac_emi_r;
  SIGNAL mac_rec_w : type_mac_rec_w;
  SIGNAL mac_rec_r : type_mac_rec_r;

  -- Video
  SIGNAL vga_ctrl : uv16;
  SIGNAL int_video : std_logic;
  
  SIGNAL mask_rev : uv8;
  
--------------------------------------------------------------------------------
  
BEGIN

  -----------------------------------
  -- Décodage d'adresses
  i_ts_decode: ENTITY work.ts_decode
    GENERIC MAP (
      SS20 => SS20)
    PORT MAP (
      a        => io_w.a,
      ah       => io_w.ah,
      s        => sel,
      iboot    => iboot,
      clk      => clk,
      reset_n  => reset_n);

  -----------------------------------
  -- Registre DMA2 & AUXIO
  i_ts_dmaux: ENTITY work.ts_dmaux
    GENERIC MAP (
      HWCONF           => HWCONF,
      ETHERNET         => ETHERNET)
    PORT MAP (
      sel_dma2         => sel.dma2,
      sel_auxio0       => sel.auxio0,
      sel_auxio1       => sel.auxio1,
      w                => io_w,
      r                => dmaux_r,
      dma_esp_iena     => dma_esp_iena,
      dma_esp_int      => dma_esp_int,
      dma_esp_reset    => dma_esp_reset,
      dma_esp_write    => dma_esp_write,
      dma_esp_addr_w   => dma_esp_addr_w,
      dma_esp_addr_r   => dma_esp_addr_r,
      dma_esp_addr_maj => dma_esp_addr_maj,
      dma_eth_int      => eth_int,
      dma_eth_iena     => dma_eth_iena,
      dma_eth_reset    => dma_eth_reset,
      dma_eth_ba       => dma_eth_ba,
      led              => led,
      iic1_scl         => iic1_scl,
      iic1_sda_o       => iic1_sda_o,
      iic1_sda_i       => iic1_sda_i,
      iic2_scl         => iic2_scl,
      iic2_sda_o       => iic2_sda_o,
      iic2_sda_i       => iic2_sda_i,
      iic3_scl         => iic3_scl,
      iic3_sda_o       => iic3_sda_o,
      iic3_sda_i       => iic3_sda_i,
      phy_mdc          => phy_mdc,
      phy_mdio_o       => phy_mdio_o,
      phy_mdio_en      => phy_mdio_en,
      phy_mdio_i       => phy_mdio_i,
      vga_ctrl         => vga_ctrl,
      sd_reg_w         => sd_reg_w,
      sd_reg_r         => sd_reg_r,
      mask_rev         => mask_rev,
      reset_mask_rev   => reset_mask_rev,
      swconf           => swconf,
      stopa            => stopa,
      clk              => clk,
      reset_n          => reset_n);

  -----------------------------------
  -- Contrôleur d'interruptions
  i_ts_inter: ENTITY work.ts_inter
    GENERIC MAP (
      CPU0         => CPU0,
      CPU1         => CPU1,
      CPU2         => CPU2,
      CPU3         => CPU3)
    PORT MAP (
      sel          => sel.inter,
      w            => io_w,
      r            => inter_r,
      irl0         => irl0,
      irl1         => irl1,
      irl2         => irl2,
      irl3         => irl3,
      int_timer_s  => int_timer_s,
      int_timer_p0 => int_timer_p0,
      int_timer_p1 => int_timer_p1,
      int_timer_p2 => int_timer_p2,
      int_timer_p3 => int_timer_p3,
      int_esp      => esp_int,
      int_ether    => eth_int,
      int_sport    => int_sport,
      int_kbm      => int_kbm,
      int_video    => int_video,
      clk          => clk,
      reset_n      => reset_n);

  -----------------------------------
  -- IOMMU
  i_ts_iommu: ENTITY work.ts_iommu
    GENERIC MAP (
      IOMMU_VER => IOMMU_VER)
    PORT MAP (
      sel      => sel.iommu,
      w        => io_w,
      r        => iommu_r,
      piw      => mux_pw,
      pir      => mux_pr,
      pow      => iommu_pw,
      por      => iommu_pr,
      mask_rev => mask_rev,
      clk      => clk,
      reset_n  => reset_n);
  
  Gen_MuxLANCE: IF ETHERNET GENERATE
    vi_w(0)<=esp_pw;
    vi_w(1)<=lance_pw;
     
    esp_pr<=vi_r(0);
    lance_pr<=vi_r(1);
    i_mux: ENTITY work.plomb_mux
      GENERIC MAP (
        NB   => 2,
        PROF => 10)
      PORT MAP (
        vi_w     => vi_w,
        vi_r     => vi_r,
        o_w      => mux_pw,
        o_r      => mux_pr,
        clk      => clk,
        reset_n  => reset_n);
  END GENERATE Gen_MuxLANCE;
  
  Gen_NoMuxLANCE: IF NOT ETHERNET GENERATE
    mux_pw<=esp_pw;
    esp_pr<=mux_pr;
  END GENERATE Gen_NoMuxLANCE;
  
  -----------------------------------
  ReqFLASH:PROCESS (io_w,sel)
  BEGIN
    flash_w<=io_w;
    flash_w.req<=io_w.req AND sel.rom;
    ibram_w<=io_w;
    ibram_w.req<=io_w.req AND sel.ibram;
  END PROCESS ReqFLASH;
  
  -----------------------------------
  -- Contrôleur SCSI
  i_ts_esp: ENTITY work.ts_esp
    GENERIC MAP (
	   ASI => ASI_SUPER_DATA)
    PORT MAP (
      sel              => sel.esp,
      w                => io_w,
      r                => esp_r,
      pw               => esp_pw,
      pr               => esp_pr,
      scsi_w           => scsi_w,
      scsi_r           => scsi_r,
      int              => esp_int,
      dma_esp_iena     => dma_esp_iena,
      dma_esp_int      => dma_esp_int,
      dma_esp_reset    => dma_esp_reset,
      dma_esp_write    => dma_esp_write,
      dma_esp_addr_w   => dma_esp_addr_w,
      dma_esp_addr_r   => dma_esp_addr_r,
      dma_esp_addr_maj => dma_esp_addr_maj,
      clk              => clk,
      reset_n          => reset_n);

  -----------------------------------
  -- Ethernet Lance
  Gen_LANCE: IF ETHERNET GENERATE
    i_ts_lance: ENTITY work.ts_lance
	   GENERIC MAP (
	     ASI => ASI_SUPER_DATA)
      PORT MAP (
        sel       => sel.lance,
        w         => io_w,
        r         => lance_r,
        pw        => lance_pw,
        pr        => lance_pr,
        mac_emi_w => mac_emi_w,
        mac_emi_r => mac_emi_r,
        mac_rec_w => mac_rec_w,
        mac_rec_r => mac_rec_r,
        int       => int_ether,
        eth_ba    => dma_eth_ba,
        stopa     => stopa,
        clk       => clk,
        reset     => dma_eth_reset,
        reset_n   => reset_n);

    -- MII or RMII MAC
    i_ts_lance_mac: ENTITY work.ts_lance_mac
      PORT MAP (
        phy_txd     => phy_txd,
        phy_tx_en   => phy_tx_en,
        phy_tx_er   => phy_tx_er,
        phy_tx_clk  => phy_tx_clk,
        phy_col     => phy_col,
        phy_rxd     => phy_rxd,
        phy_rx_dv   => phy_rx_dv,
        phy_rx_er   => phy_rx_er,
        phy_rx_clk  => phy_rx_clk,
        phy_crs     => phy_crs,
        phy_int_n   => phy_int_n,
        phy_reset_n => phy_reset_n,
        mac_emi_w   => mac_emi_w,
        mac_emi_r   => mac_emi_r,
        mac_rec_w   => mac_rec_w,
        mac_rec_r   => mac_rec_r,
        clk         => clk,
        reset_n     => reset_n);
    
  END GENERATE Gen_LANCE;

  eth_int<=int_ether AND dma_eth_iena AND to_std_logic(ETHERNET);
  
  -----------------------------------
  -- Horloge temps réel & NVRAM
  i_ts_rtc: ENTITY work.ts_rtc
    GENERIC MAP (
      SYSFREQ => SYSFREQ)
    PORT MAP (
      sel      => sel.rtc,
      w        => io_w,
      r        => rtc_r,
      rtcinit  => rtcinit,
      rtcset   => rtcset,
      clk      => clk,
      reset_n  => reset_n);

  -----------------------------------
  -- Clavier, Souris
  i_ts_sport1: ENTITY work.ts_sport
    PORT MAP (
      sel       => sel.kbm,
      w         => io_w,
      r         => sport1_r,
      di1_data  => di1_data,            -- Entrée clavier
      di1_req   => di1_req,
      di1_rdy   => di1_rdy,
      do1_data  => do1_data,            -- Commandes vers clavier
      do1_req   => do1_req,
      do1_rdy   => do1_rdy,
      di2_data  => di2_data,            -- Entrée souris
      di2_req   => di2_req,
      di2_rdy   => di2_rdy,
      do2_data  => OPEN,
      do2_req   => OPEN,
      do2_rdy   => '1',
      int       => int_kbm,
      clk       => clk,
      reset_n   => reset_n);
  
  -- Ports série
  i_ts_sport2: ENTITY work.ts_sport
    PORT MAP (
      sel      => sel.sport,
      w        => io_w,
      r        => sport2_r,
      di1_data => di3_data,             -- Entrée Port série
      di1_req  => di3_req,
      di1_rdy  => di3_rdy,
      do1_data => do3_data,             -- Sortie port série
      do1_req  => do3_req,
      do1_rdy  => do3_rdy,
      di2_data => di4_data,             -- Second port
      di2_req  => di4_req,
      di2_rdy  => di4_rdy,
      do2_data => do4_data,             -- Second port
      do2_req  => do4_req,
      do2_rdy  => do4_rdy,
      int      => int_sport,
      clk      => clk,
      reset_n  => reset_n);
  
  -----------------------------------
  -- Emulation
  GenEmu: IF PS2 GENERATE

    txd1<='1';
    txd2<='1';
    
    i_ts_ps2sun: ENTITY work.ts_ps2sun
      GENERIC MAP (
        SYSFREQ => SYSFREQ)
      PORT MAP (
        ps2_i      => ps2_i,
        ps2_o      => ps2_o,
        kbm_layout => kbm_layout,
        
        di1_data   => di1_data,       -- KB emu --> SPORT
        di1_req    => di1_req,
        di1_rdy    => di1_rdy,
        
        do1_data   => do1_data,       -- SPORT  --> KB emu
        do1_req    => do1_req,
        do1_rdy    => do1_rdy,
        
        di2_data   => di2_data,       -- MOU   --> SPORT
        di2_req    => di2_req,
        di2_rdy    => di2_rdy,
        
        do2_data   => do2_data,       -- SPORT --> MOU
        do2_req    => do2_req,
        do2_rdy    => OPEN,

        clk        => clk,
        reset_n    => reset_n);
  
  END GENERATE GenEmu;

  -----------------------------------
  GenNoEmu: IF NOT PS2 GENERATE
    
    -- Baudrate 1200
    i_synth1200: ENTITY work.synth
      GENERIC MAP (
        FREQ => SYSFREQ,
        RATE => 1200)
      PORT MAP (
        sync     => sync_kbm,
        clk      => clk,
        reset_n  => reset_n);
    
    -- Keyboard
    i_acia1: ENTITY work.acia
      GENERIC MAP (
        TFIFO => 3,
        RFIFO => 6)
      PORT MAP (
        sync     => sync_kbm,
        txd      => txd1,
        tx_data  => do1_data,
        tx_req   => do1_req,
        tx_rdy   => do1_rdy,
        rxd      => rxd1,
        rx_data  => di1_data,
        rx_break => OPEN,
        rx_req   => di1_req,
        rx_ack   => di1_rdy,
        clk      => clk,
        reset_n  => reset_n);
    
    -- Mouse
    i_acia2: ENTITY work.acia
      GENERIC MAP (
        TFIFO => 0,
        RFIFO => 16)
      PORT MAP (
        sync     => sync_kbm,
        txd      => txd2,
        tx_data  => x"00",
        tx_req   => '0',
        tx_rdy   => OPEN,
        rxd      => rxd2,
        rx_data  => di2_data,
        rx_break => OPEN,
        rx_req   => di2_req,
        rx_ack   => di2_rdy,
        clk      => clk,
        reset_n  => reset_n);
    
  END GENERATE GenNoEmu;

  -----------------------------------
  -- SPORT
  txd3_data<=do3_data;
  txd3_req<=do3_req;
  do3_rdy<=txd3_rdy;
  
  di3_data<=rxd3_data;
  di3_req<=rxd3_req;
  rxd3_ack<=di3_rdy;
  
  GenSPORT2:IF SPORT2 GENERATE
    
    -- Baudrate 1200
    i_synth1200: ENTITY work.synth
      GENERIC MAP (
        FREQ => SYSFREQ,
        RATE => 115200)
      PORT MAP (
        sync     => sync_sport2,
        clk      => clk,
        reset_n  => reset_n);
    
    i_acia4: ENTITY work.acia
      GENERIC MAP (
        TFIFO => 10,
        RFIFO => 10)
      PORT MAP (
        sync     => sync_sport2,
        txd      => txd4,
        tx_data  => do4_data,
        tx_req   => do4_req,
        tx_rdy   => do4_rdy,
        rxd      => rxd4,
        rx_data  => di4_data,
        rx_break => OPEN,
        rx_req   => di4_req,
        rx_ack   => di4_rdy,
        clk      => clk,
        reset_n  => reset_n);
  END GENERATE GenSPORT2;
  -----------------------------------
  -- Timer
  i_ts_timer: ENTITY work.ts_timer
    GENERIC MAP (
      SYSFREQ => SYSFREQ,
      CPU0    => CPU0,
      CPU1    => CPU1,
      CPU2    => CPU2,
      CPU3    => CPU3)
    PORT MAP (
      sel      => sel.timer,
      w        => io_w,
      r        => timer_r,
      int_s    => int_timer_s,
      int_p0   => int_timer_p0,
      int_p1   => int_timer_p1,
      int_p2   => int_timer_p2,
      int_p3   => int_timer_p3,
      stopa    => stopa,
      clk      => clk,
      reset_n  => reset_n);
  
  -----------------------------------
  -- Video
  i_ts_tcx: ENTITY work.ts_tcx
    GENERIC MAP (
      TCX_ACCEL => TCX_ACCEL,
      ADR       => TCX_ADR,
      ADR_H     => TCX_ADR_H,
		ASI       => ASI_SUPER_INSTRUCTION)
    PORT MAP (
      sel      => sel.video,
      w        => io_w,
      r        => vid_r,
      pw       => vid_pw,
      pr       => vid_pr,
      vga_ctrl => vga_ctrl,
      cg3      => swconf(2),
      vga_r    => vga_r,
      vga_g    => vga_g,
      vga_b    => vga_b,
      vga_de   => vga_de,
      vga_hsyn => vga_hsyn,
      vga_vsyn => vga_vsyn,
      vga_hpos => vga_hpos,
      vga_vpos => vga_vpos,
      vga_clk  => vga_clk,
      vga_en   => vga_en,
      vga_on   => vga_on,
      pal_clk  => pal_clk,
      pal_d    => pal_d,
      pal_a    => pal_a,
      pal_wr   => pal_wr,
      int      => int_video,
      clk      => clk,
      reset_n  => reset_n);
  
  -----------------------------------
  sel2 <=sel  WHEN rising_edge(clk);
  
  ReadMux:PROCESS (sel2,sel,dmaux_r,inter_r,iommu_r,esp_r,lance_r,rtc_r,
                   vid_r,sport1_r,sport2_r,timer_r,flash_r,ibram_r)
  BEGIN
    IF sel2.dma2='1' OR sel2.auxio0='1' THEN
      io_r<=dmaux_r;
    ELSIF sel2.inter='1' THEN
      io_r<=inter_r;
    ELSIF sel2.iommu='1' THEN
      io_r<=iommu_r;
    ELSIF sel2.esp='1' THEN
      io_r<=esp_r;
    ELSIF sel2.lance='1' AND ETHERNET THEN
      io_r<=lance_r;
    ELSIF sel2.rtc='1' THEN
      io_r<=rtc_r;
    ELSIF sel2.kbm='1' THEN
      io_r<=sport1_r;
    ELSIF sel2.sport='1' THEN
      io_r<=sport2_r;
    ELSIF sel2.timer='1' THEN
      io_r<=timer_r;
    ELSIF sel2.video='1' THEN
      io_r<=vid_r;
    ELSIF sel2.rom='1' THEN
      io_r<=flash_r;
    ELSIF sel2.ibram='1' THEN
      io_r<=ibram_r;
    ELSE
      io_r.dr<=x"BADACCE5";
    END IF;
    
    IF sel.dma2='1' OR sel.auxio0='1' THEN
      io_r.ack<=dmaux_r.ack;
    ELSIF sel.inter='1' THEN
      io_r.ack<=inter_r.ack;
    ELSIF sel.iommu='1' THEN
      io_r.ack<=iommu_r.ack;
    ELSIF sel.esp='1' THEN
      io_r.ack<=esp_r.ack;
    ELSIF sel.lance='1' AND ETHERNET THEN
      io_r.ack<=lance_r.ack;
    ELSIF sel.rtc='1' THEN
      io_r.ack<=rtc_r.ack;
    ELSIF sel.kbm='1' THEN
      io_r.ack<=sport1_r.ack;
    ELSIF sel.sport='1' THEN
      io_r.ack<=sport2_r.ack;
    ELSIF sel.timer='1' THEN
      io_r.ack<=timer_r.ack;
    ELSIF sel.video='1' THEN
      io_r.ack<=vid_r.ack;
    ELSIF sel.rom='1' THEN
      io_r.ack<=flash_r.ack;
    ELSIF sel.ibram='1' THEN
      io_r.ack<=ibram_r.ack;
    ELSE
      io_r.ack<='1';                    -- Zone inconnue ...
    END IF;
     
  END PROCESS ReadMux;
         
END ARCHITECTURE rtl;
