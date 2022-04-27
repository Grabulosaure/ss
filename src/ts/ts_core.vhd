--------------------------------------------------------------------------------
-- TEM : TS
-- Presque tout
--------------------------------------------------------------------------------
-- DO 12/2010
--------------------------------------------------------------------------------
-- CPU/FPU + MCU + BlocIO + connexions
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

-- SWCONF :
--  0 : 0=HD image         1=SD raw       (MISTER)
--        MicroSD            External SD  (C5G)
--        SystemACE          External SD  (SP605)
--  1 :  0=Single SCSI      1=Dual SCSI
--  2 :  0=TCX              1=CG3
--  3 :  0=AutoBoot         1=NoAutoBoot
--  4 :
--  5 : 
--  6 : 0=Serial           1=Video  
--  7 :

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.plomb_pack.ALL;
USE work.iu_pack.ALL;
USE work.ts_pack.ALL;
USE work.mcu_pack.ALL;
USE work.cpu_conf_pack.ALL;

ENTITY ts_core IS
  GENERIC (
    ACIABREAK   : boolean := true;      -- false = CTS     | true = BREAK
    SS20        : boolean := false;     -- false = SS5     | true = SS20
    NCPUS       : natural RANGE 1 TO 4    := 1;
    RAMSIZE     : natural RANGE 0 TO 1023 := 126;
    FPU_MULTI   : boolean := true;      -- false = Separate FPUs | true = Shared
    ETHERNET    : boolean := true;      -- false = Disable | true = Enable
    PS2         : boolean := false;     -- false = SunKBM  | true = PS2
    TCX_ACCEL   : boolean := false;     -- false = Disable | true = Accelerator
    SPORT2      : boolean := false;     -- UART4 = SPORT2
    OBRAM_ADR   : uv32 := x"07C0_0000"; -- OpenBIOS in RAM base address
    OBRAM_ADR_H : uv4  := x"0";
    TCX_ADR     : uv32 := x"07E0_0000"; -- Video RAM base address
    TCX_ADR_H   : uv4  := x"0";
    OBRAM       : boolean := false;     -- OpenBIOS in RAM
    HWCONF      : uv8;
    TECH        : natural := 0;         -- Techno. implementation variants
    TRACE       : boolean := false;     -- Debug traces
    SYSFREQ     : natural := 50000000;
    SERIALRATE  : natural := 115200);
  PORT (
    -- Plomb RAM
    dram_pw     : OUT type_plomb_w;
    dram_pr     : IN  type_plomb_r;
    
    -- Video framebuffer
    vram_pw     : OUT type_plomb_w;
    vram_pr     : IN  type_plomb_r;
    
    -- Video
    vga_r       : OUT uv8;
    vga_g       : OUT uv8;
    vga_b       : OUT uv8;
    vga_de      : OUT std_logic;
    vga_hsyn    : OUT std_logic;
    vga_vsyn    : OUT std_logic;
    vga_clk     : IN  std_logic;
    vga_en      : IN  std_logic;
    vga_dis     : IN  std_logic;
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
    phy_tx_clk  : IN  std_logic; -- MII/RMII Transmit Clock
    phy_tx_en   : OUT std_logic; -- MII/RMII Transmit Enable
    phy_tx_er   : OUT std_logic; -- MII      Transmit Error
    
    phy_col     : IN  std_logic; -- MII      Collision (async.)
    
    phy_rxd     : IN  uv4;       -- MII/RMII Data
    phy_rx_dv   : IN  std_logic; -- MII/RMII Receive Data Valid
    phy_rx_er   : IN  std_logic; -- MII      Receive Error
    phy_rx_clk  : IN  std_logic; -- MII/RMII Receive Clock 25MHz/2.5MHz
    
    phy_crs     : IN  std_logic; -- MII      Carrier Sense (async.)

    -- Ethernet MDIO
    phy_mdc     : OUT std_logic;
    phy_mdio_o  : OUT std_logic;
    phy_mdio_en : OUT std_logic;
    phy_mdio_i  : IN  std_logic;
    phy_int_n   : IN  std_logic;
    phy_reset_n : OUT std_logic;    

    -- FLASH
    flash_w     : OUT type_pvc_w;
    flash_r     : IN  type_pvc_r;
    ibram_w     : OUT type_pvc_w;
    ibram_r     : IN  type_pvc_r;
    iboot       : IN  std_logic;

    -- Bus I²C (SP605)
    iic1_scl    : OUT std_logic;
    iic1_sda_o  : OUT std_logic;
    iic1_sda_i  : IN  std_logic;
    iic2_scl    : OUT std_logic;
    iic2_sda_o  : OUT std_logic;
    iic2_sda_i  : IN  std_logic;
    iic3_scl    : OUT std_logic;
    iic3_sda_o  : OUT std_logic;
    iic3_sda_i  : IN  std_logic;

    -- Serial
    rxd1        : IN  std_logic;
    rxd2        : IN  std_logic;
    rxd3        : IN  std_logic;
    rxd4        : IN  std_logic;
    txd1        : OUT std_logic;
    txd2        : OUT std_logic;
    txd3        : OUT std_logic;
    txd4        : OUT std_logic;
    cts         : IN  std_logic;
    rts         : OUT std_logic;

    -- Direct
    ps2_i       : IN  uv4;
    ps2_o       : OUT uv4;
    
    -- Configuration/Reset
    reset       : IN  std_logic;
    reset_na    : IN  std_logic;
    swconf      : IN  uv8;
    cachena     : IN  std_logic;
    l2tlbena    : IN  std_logic;
    wback       : IN  std_logic;
    aow         : IN  std_logic;
    
    reset_mask_rev : IN uv8;
    kbm_layout  : IN  uv8;
    
    dreset      : OUT std_logic;
    
    -- Horloge
    sclk        : IN  std_logic
    );
END ENTITY ts_core;

--##############################################################################

ARCHITECTURE rtl OF ts_core IS
  CONSTANT NCPUV : natural :=mux(SS20,NCPUS,1); -- SS5 -> Force 1 CPU
  
--------------------------------------------------------------------------------
  CONSTANT SMP  : boolean := (NCPUV>1);
  CONSTANT CPU0 : boolean := true;
  CONSTANT CPU1 : boolean := (NCPUV>=2);
  CONSTANT CPU2 : boolean := (NCPUV>=3);
  CONSTANT CPU3 : boolean := (NCPUV>=4);
  
  -- [31:20] : RAMSIZE
  -- [19:5]  : TBD
  -- [4]     : 0=SS5 1=SS20
  -- [3-2]   : TBD
  -- [1:0]   : NCPU-1
  CONSTANT SYSCONF : uv32 := to_unsigned(RAMSIZE,12) & x"0" &
                             x"00" &
                             "000" & to_std_logic(SS20) &
                             "00" & to_unsigned(NCPUV-1,2);

  CONSTANT WBSIZE  : uv32 := to_unsigned(RAMSIZE,12) & x"00000";

  FUNCTION calc_ncpu(c0,c1,c2,c3 : boolean) RETURN natural IS
    VARIABLE v : natural := 0;
  BEGIN
    IF c0 THEN v:=v+1; END IF;
    IF c1 THEN v:=v+1; END IF;
    IF c2 THEN v:=v+1; END IF;
    IF c3 THEN v:=v+1; END IF;
    RETURN v;
  END FUNCTION;

  FUNCTION smptype(smp : boolean) RETURN natural IS
  BEGIN
    IF NOT SMP THEN
      RETURN CPUTYPE_MS2; -- MicroSparc II
    ELSE
      RETURN CPUTYPE_SS;  -- SuperSparc
    END IF;
  END FUNCTION;

  CONSTANT CPUTYPE : natural :=smptype(SS20);
  CONSTANT IOMMU_VER : uv8 := CPUCONF(CPUTYPE).IOMMU_VER;
  
  CONSTANT NCPU : natural :=calc_ncpu(CPU0,CPU1,CPU2,CPU3); -- <AVOIR : Saute ordre>
  
  COMPONENT iu
    GENERIC (
      DUMP    : boolean;
      CPUTYPE : natural;
      TECH    : natural;
      CID     : string);
    PORT (
      inst_w   : OUT type_plomb_w;
      inst_r   : IN  type_plomb_r;
      data_w   : OUT type_plomb_w;
      data_r   : IN  type_plomb_r;
      fpu_i    : OUT type_fpu_i;
      fpu_o    : IN  type_fpu_o;
      debug_s  : OUT type_debug_s;
      debug_t  : IN  type_debug_t;
      irl      : IN  uv4;
      intack   : OUT std_logic;
      reset    : IN  std_logic;
      reset_na : IN  std_logic;
      clk      : IN  std_logic);
  END COMPONENT;

  COMPONENT fpu IS
    GENERIC (
      TECH     : natural);
    PORT (
      i        : IN  type_fpu_i;
      o        : OUT type_fpu_o;
      reset    : IN  std_logic;
      reset_na : IN  std_logic;
      clk      : IN  std_logic);
  END COMPONENT fpu;

  COMPONENT fpu_mp IS
    GENERIC (
      N        : natural RANGE 1 TO 4;
      TECH     : natural);
    PORT (
      i0       : IN  type_fpu_i;
      o0       : OUT type_fpu_o;
      i1       : IN  type_fpu_i;
      o1       : OUT type_fpu_o;
      i2       : IN  type_fpu_i;
      o2       : OUT type_fpu_o;
      i3       : IN  type_fpu_i;
      o3       : OUT type_fpu_o;
      reset    : IN  std_logic;
      reset_na : IN  std_logic;
      clk      : IN  std_logic);
  END COMPONENT fpu_mp;
  
  COMPONENT iu_debug IS
    GENERIC (
      ADRS : uv4);
    PORT (
      dl_w     : IN  type_dl_w;
      dl_r     : OUT type_dl_r;
      debug_s  : IN  type_debug_s;
      debug_t  : OUT type_debug_t;
      debug_c  : OUT uv4;
      dreset   : OUT std_logic;
      stopa    : OUT std_logic;
      xstop    : IN  std_logic;
      reset_na : IN  std_logic;
      clk      : IN  std_logic);
  END COMPONENT iu_debug;
  
  COMPONENT iu_debug_mp IS
    GENERIC (
      ADRS : uv4;
      CPU0 : boolean;
      CPU1 : boolean;
      CPU2 : boolean;
      CPU3 : boolean);
    PORT (
      dl_w     : IN  type_dl_w;
      dl_r     : OUT type_dl_r;
      debug0_s : IN  type_debug_s;
      debug0_t : OUT type_debug_t;
      debug1_s : IN  type_debug_s;
      debug1_t : OUT type_debug_t;
      debug2_s : IN  type_debug_s;
      debug2_t : OUT type_debug_t;
      debug3_s : IN  type_debug_s;
      debug3_t : OUT type_debug_t;
      debug_c  : OUT uv4;
      dreset   : OUT std_logic;
      stopa    : OUT std_logic;
      xstop    : IN  std_logic;
      reset_na : IN  std_logic;
      clk      : IN  std_logic);
  END COMPONENT iu_debug_mp;
  
  COMPONENT mcu
    GENERIC (
      MMU_DIS  : boolean;
      ASICACHE : boolean;
      ASIINST  : boolean;
      BOOTMODE : boolean;
      SYSCONF  : uv32;
      CPUTYPE  : natural);
    PORT (
      inst_w   : IN  type_plomb_w;
      inst_r   : OUT type_plomb_r;
      data_w   : IN  type_plomb_w;
      data_r   : OUT type_plomb_r;
      ext_w    : OUT type_plomb_w;
      ext_r    : IN  type_plomb_r;
      cachena  : IN  std_logic;
      l2tlbena : IN  std_logic;
      reset    : IN  std_logic;
      reset_na : IN  std_logic;
      clk      : IN  std_logic);
  END COMPONENT;
  
  COMPONENT ts_io
    GENERIC (
      SS20        : boolean;
      ETHERNET    : boolean;
      PS2         : boolean;
      TCX_ACCEL   : boolean;
      SPORT2      : boolean;
      TCX_ADR     : uv32;
      TCX_ADR_H   : uv4;
      HWCONF      : uv8;
      SYSFREQ     : natural;
      CPU0        : boolean;
      CPU1        : boolean;
      CPU2        : boolean;
      CPU3        : boolean;
      TRACE       : boolean;
      IOMMU_VER   : uv8);
    PORT (
      led         : OUT std_logic;
      ps2_i       : IN  uv4;
      ps2_o       : OUT uv4;
      sync_rs     : IN  std_logic;
      rxd1        : IN  std_logic;
      txd1        : OUT std_logic;
      rxd2        : IN  std_logic;
      txd2        : OUT std_logic;
      rxd4        : IN  std_logic;
      txd4        : OUT std_logic;
      rxd3_data   : IN  uv8;
      rxd3_req    : IN  std_logic;
      rxd3_ack    : OUT std_logic;
      txd3_data   : OUT uv8;
      txd3_req    : OUT std_logic;
      txd3_rdy    : IN  std_logic;
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
      vga_dis     : IN  std_logic;
      pal_clk     : OUT std_logic;
      pal_d       : OUT uv24;
      pal_a       : OUT uv8;
      pal_wr      : OUT std_logic;
      scsi_w      : OUT type_scsi_w;
      scsi_r      : IN  type_scsi_r;
      sd_reg_w    : OUT type_sd_reg_w;
      sd_reg_r    : IN  type_sd_reg_r;
      rtcinit     : IN unsigned(43 DOWNTO 0);
      rtcset      : IN std_logic;
      phy_txd     : OUT uv4;
      phy_tx_clk  : IN  std_logic;
      phy_tx_en   : OUT std_logic;
      phy_tx_er   : OUT std_logic;
      phy_col     : IN  std_logic;
      phy_rxd     : IN  uv4;
      phy_rx_dv   : IN  std_logic;
      phy_rx_er   : IN  std_logic;
      phy_rx_clk  : IN  std_logic;
      phy_crs     : IN  std_logic;
      phy_mdc     : OUT std_logic;
      phy_mdio_o  : OUT std_logic;
      phy_mdio_en : OUT std_logic;
      phy_mdio_i  : IN  std_logic;
      phy_int_n   : IN  std_logic;
      phy_reset_n : OUT std_logic;
      irl0        : OUT uv4;
      irl1        : OUT uv4;
      irl2        : OUT uv4;
      irl3        : OUT uv4;
      io_w        : IN  type_pvc_w;
      io_r        : OUT type_pvc_r;
      iommu_pw    : OUT type_plomb_w;
      iommu_pr    : IN  type_plomb_r;
      vid_pw      : OUT type_plomb_w;
      vid_pr      : IN  type_plomb_r;
      flash_w     : OUT type_pvc_w;
      flash_r     : IN  type_pvc_r;
      ibram_w     : OUT type_pvc_w;
      ibram_r     : IN  type_pvc_r;
      iic1_scl    : OUT std_logic;
      iic1_sda_o  : OUT std_logic;
      iic1_sda_i  : IN  std_logic;
      iic2_scl    : OUT std_logic;
      iic2_sda_o  : OUT std_logic;
      iic2_sda_i  : IN  std_logic;
      iic3_scl    : OUT std_logic;
      iic3_sda_o  : OUT std_logic;
      iic3_sda_i  : IN  std_logic;
      reset_mask_rev : IN uv8;
      kbm_layout  : IN  uv8;
      swconf      : IN  uv8;
      stopa       : IN  std_logic;
      iboot       : IN  std_logic;
      clk         : IN  std_logic;
      reset_na    : IN  std_logic);
  END COMPONENT;
  
  --------------------------------------------
  SIGNAL io_txd3_data : uv8;
  SIGNAL io_txd3_req,io_txd3_rdy : std_logic;
  SIGNAL io_rxd3_data : uv8;
  SIGNAL io_rxd3_req,io_rxd3_ack : std_logic;
  SIGNAL led_io : std_logic;
  SIGNAL sync_rs,sync_rs_hi : std_logic;
  SIGNAL rscpt : natural RANGE 0 TO 7;
  SIGNAL osel,obreak : std_logic;
  
  SIGNAL inst0_pw,data0_pw,ext0_pw : type_plomb_w;
  SIGNAL inst0_pr,data0_pr,ext0_pr : type_plomb_r;
  SIGNAL inst1_pw,data1_pw,ext1_pw : type_plomb_w;
  SIGNAL inst1_pr,data1_pr,ext1_pr : type_plomb_r;
  SIGNAL inst2_pw,data2_pw,ext2_pw : type_plomb_w;
  SIGNAL inst2_pr,data2_pr,ext2_pr : type_plomb_r;
  SIGNAL inst3_pw,data3_pw,ext3_pw : type_plomb_w;
  SIGNAL inst3_pr,data3_pr,ext3_pr : type_plomb_r;
  
  SIGNAL fpu0_i,fpu1_i,fpu2_i,fpu3_i : type_fpu_i;
  SIGNAL fpu0_o,fpu1_o,fpu2_o,fpu3_o : type_fpu_o;
  
  SIGNAL smp0_w,smp1_w,smp2_w,smp3_w,smp_r : type_smp;
  SIGNAL hitx0,hitx1,hitx2,hitx3,hit0,hit1,hit2,hit3 : std_logic :='0';
  SIGNAL cwb0,cwb1,cwb2,cwb3 : std_logic :='0';
  SIGNAL sel0,sel1,sel2,sel3 : std_logic :='0';
  SIGNAL last0,last1,last2,last3 : std_logic :='0';
  
  SIGNAL io_pw,mem_pw,memm_pw,memx_pw,smem_pw : type_plomb_w;
  SIGNAL io_pr,mem_pr,smem_pr : type_plomb_r;
  SIGNAL iommu_pw,vid_pw : type_plomb_w;
  SIGNAL iommu_pr,vid_pr : type_plomb_r;
  SIGNAL ext_vo_pw : arr_plomb_w(0 TO 1);
  SIGNAL ext_vo_pr : arr_plomb_r(0 TO 1);
  SIGNAL mux_vi_pw : arr_plomb_w(0 TO 1);
  SIGNAL mux_vi_pr : arr_plomb_r(0 TO 1);
  SIGNAL ext_no : natural RANGE 0 TO 1;
  
  FUNCTION sel_decodage_nosmp (CONSTANT w : type_plomb_w) RETURN natural IS
  BEGIN
    IF OBRAM AND w.a(31 DOWNTO 28)=x"F" THEN
      RETURN 0; -- OpenBIOS in RAM
    ELSIF w.a(31 DOWNTO 28)=x"0" OR
      (w.a(31 DOWNTO 28)=x"5" AND w.a(23)='1') THEN
      RETURN 0; -- MEM + VIDEO
    ELSE
      RETURN 1; -- I/O
    END IF;
  END FUNCTION sel_decodage_nosmp;

  FUNCTION sel_decodage_smp (CONSTANT w : type_plomb_w) RETURN natural IS
  BEGIN
    IF OBRAM AND w.ah=x"F" AND w.a(31 DOWNTO 24)=x"F0" THEN
      RETURN 0; -- OpenBIOS in RAM
    ELSIF w.ah(35)='0' OR (w.ah=x"E" AND w.a(31)='0' AND w.a(23)='1') THEN
      RETURN 0; -- MEM + VIDEO
    ELSE
      RETURN 1; -- I/O
    END IF;
  END FUNCTION sel_decodage_smp;
  
  SIGNAL io_w : type_pvc_w;
  SIGNAL io_r : type_pvc_r;
  
  --------------------------------------------
  SIGNAL debug0_s,debug1_s,debug2_s,debug3_s : type_debug_s;
  SIGNAL debug0_t,debug1_t,debug2_t,debug3_t : type_debug_t;
  SIGNAL debug_conf : uv4;

  SIGNAL debug_tx_data,debug_rx_data : uv8;
  SIGNAL debug_tx_req,debug_tx_rdy : std_logic;
  SIGNAL debug_rx_req,debug_rx_ack : std_logic;
  SIGNAL debug_rx_break : std_logic;
  SIGNAL aux_c : uv16;
  SIGNAL debug_stopa,xstop : std_logic;

  SIGNAL scsi_w_i : type_scsi_w;
  SIGNAL dl_w : type_dl_w;
  SIGNAL dl_r,dl_r_cpu,dl_r_t0,dl_r_t1,dl_r_t2,dl_r_t3,dl_r_scsi : type_dl_r;
  
  SIGNAL irl0,irl1,irl2,irl3 : uv4;
  SIGNAL intack0,intack1,intack2,intack3 : std_logic;
  SIGNAL clk    : std_logic;
  SIGNAL kk_cpt : natural RANGE 0 TO 7;
  SIGNAL kk_pulse : std_logic;

  SIGNAL iled : uv8;
  SIGNAL swconfs : uv8;
  SIGNAL timecode : uv32;
  SIGNAL trigs : uv4;
  SIGNAL vga_hpos,vga_vpos : uint12;

  SIGNAL sigs : uv32;
  CONSTANT astart : std_logic :='1';
  
--------------------------------------------------------------------------------
BEGIN

  --###############################################################
  NOSMP:IF NOT SS20 GENERATE
    i_iu: iu
      GENERIC MAP (
        DUMP => true,
        CPUTYPE => CPUTYPE,
        TECH    => TECH,
        CID     => " ")
      PORT MAP (
        inst_w   => inst0_pw,
        inst_r   => inst0_pr,
        data_w   => data0_pw,
        data_r   => data0_pr,
        fpu_i    => fpu0_i,
        fpu_o    => fpu0_o,
        debug_s  => debug0_s,
        debug_t  => debug0_t,
        irl      => irl0,
        intack   => intack0,
        reset    => reset,
        reset_na => reset_na,
        clk      => clk);
    
    i_fpu: fpu
      GENERIC MAP (
        TECH     => TECH)
      PORT MAP (
        i        => fpu0_i,
        o        => fpu0_o,
        reset    => reset,
        reset_na => reset_na,
        clk      => clk);
    
    -----------------------------------
    i_mcu: mcu
      GENERIC MAP (
        MMU_DIS  => false,
        ASICACHE => true,
        ASIINST  => true,
        BOOTMODE => true,
        SYSCONF  => SYSCONF,
        CPUTYPE  => CPUTYPE)
      PORT MAP (
        inst_w   => inst0_pw,
        inst_r   => inst0_pr,
        data_w   => data0_pw,
        data_r   => data0_pr,
        ext_w    => ext0_pw,
        ext_r    => ext0_pr,
        cachena  => cachena,
        l2tlbena => l2tlbena,
        reset    => reset,
        reset_na => reset_na,
        clk      => clk);

    -----------------------------------
    i_iu_debug: iu_debug
      GENERIC MAP (
        ADRS => x"0")
      PORT MAP (
        dl_w     => dl_w,
        dl_r     => dl_r_cpu,
        debug_s  => debug0_s,
        debug_t  => debug0_t,
        debug_c  => debug_conf,
        dreset   => dreset,
        stopa    => debug_stopa,
        xstop    => xstop,
        reset_na => reset_na,
        clk      => clk);
    
    --pragma synthesis_off
    ilog_inst:ENTITY work.plomb_log
      GENERIC MAP (nom => "INST")
      PORT MAP (w => inst0_pw, r => inst0_pr, clk => clk, reset_na => reset_na);
    ilog_data:ENTITY work.plomb_log
      GENERIC MAP (nom => "DATA")
      PORT MAP (w => data0_pw, r => data0_pr, clk => clk, reset_na => reset_na);

--pragma synthesis_on

    ext_no<=sel_decodage_nosmp(ext0_pw);
    ext_vo_pr(0)<=mem_pr;
    ext_vo_pr(1)<=io_pr;
    mem_pw<=ext_vo_pw(0);
    io_pw <=ext_vo_pw(1);
    
    i_plomb_sel: ENTITY work.plomb_sel
      GENERIC MAP (
        NB   => 2,
        PROF => 20)
      PORT MAP (
        i_w      => ext0_pw,
        i_r      => ext0_pr,
        no       => ext_no,
        vo_w     => ext_vo_pw,
        vo_r     => ext_vo_pr,
        clk      => clk,
        reset_na => reset_na);
    
    mux_vi_pw(0)<=memm_pw;
    mux_vi_pw(1)<=iommu_pw;
    mem_pr<=mux_vi_pr(0);
    iommu_pr<=mux_vi_pr(1);
    
    i_plomb_mux: ENTITY work.plomb_mux
      GENERIC MAP (
        NB   => 2,
        PROF => 20)
      PORT MAP (
        vi_w     => mux_vi_pw,
        vi_r     => mux_vi_pr,
        o_w      => dram_pw,
        o_r      => dram_pr,
        clk      => clk,
        reset_na => reset_na);
    
  END GENERATE NOSMP;
  --###############################################################
  -----------------------------------
  DOSMP:IF SS20 GENERATE
    iCPU0:IF CPU0 GENERATE
      i_iu0: iu
        GENERIC MAP (
          DUMP     => true,
          CPUTYPE  => CPUTYPE,
          TECH     => TECH,
          CID      => "0>")
        PORT MAP (
          inst_w   => inst0_pw,
          inst_r   => inst0_pr,
          data_w   => data0_pw,
          data_r   => data0_pr,
          fpu_i    => fpu0_i,
          fpu_o    => fpu0_o,
          debug_s  => debug0_s,
          debug_t  => debug0_t,
          irl      => irl0,
          intack   => intack0,
          reset    => reset,
          reset_na => reset_na,
          clk      => clk);
      
      i_mcu_mp0: ENTITY work.mcu_mp
        GENERIC MAP (
          MMU_DIS  => false,
          ASICACHE => true,
          ASIINST  => true,
          BOOTMODE => true,
          CPUID    => 0,
          SYSCONF  => SYSCONF,
          WBSIZE   => WBSIZE,
          CPUTYPE  => CPUTYPE)
        PORT MAP (
          inst_w   => inst0_pw,
          inst_r   => inst0_pr,
          data_w   => data0_pw,
          data_r   => data0_pr,
          ext_w    => ext0_pw,
          ext_r    => ext0_pr,
          smp_w    => smp0_w,
          smp_r    => smp_r,
          hitx     => hitx0,
          hit      => hit0,
          cwb      => cwb0,
          last     => last0,
          sel      => sel0,
          cachena  => cachena,
          l2tlbena => l2tlbena,
          wback    => wback,
          aow      => aow,
          reset    => reset,
          reset_na => reset_na,
          clk      => clk);
      
    END GENERATE iCPU0;

    iCPU1:IF CPU1 GENERATE
      i_iu1: iu
        GENERIC MAP (
          DUMP     => true,
          CPUTYPE  => CPUTYPE,
          TECH     => TECH,
          CID      => "1>")
        PORT MAP (
          inst_w   => inst1_pw,
          inst_r   => inst1_pr,
          data_w   => data1_pw,
          data_r   => data1_pr,
          fpu_i    => fpu1_i,
          fpu_o    => fpu1_o,
          debug_s  => debug1_s,
          debug_t  => debug1_t,
          irl      => irl1,
          intack   => intack1,
          reset    => reset,
          reset_na => reset_na,
          clk      => clk);
      
      i_mcu_mp1: ENTITY work.mcu_mp
        GENERIC MAP (
          MMU_DIS  => false,
          ASICACHE => true,
          ASIINST  => true,
          BOOTMODE => true,
          CPUID    => 1,
          SYSCONF  => SYSCONF,
          WBSIZE   => WBSIZE,
          CPUTYPE  => CPUTYPE)
        PORT MAP (
          inst_w   => inst1_pw,
          inst_r   => inst1_pr,
          data_w   => data1_pw,
          data_r   => data1_pr,
          ext_w    => ext1_pw,
          ext_r    => ext1_pr,
          smp_w    => smp1_w,
          smp_r    => smp_r,
          hitx     => hitx1,
          hit      => hit1,
          cwb      => cwb1,
          last     => last1,
          sel      => sel1,
          cachena  => cachena,
          l2tlbena => l2tlbena,
          wback    => wback,
          aow      => aow,
          reset    => reset,
          reset_na => reset_na,
          clk      => clk);
      
    END GENERATE iCPU1;

    iCPU2:IF CPU2 GENERATE
      i_iu2: iu
        GENERIC MAP (
          DUMP     => true,
          CPUTYPE  => CPUTYPE,
          TECH     => TECH,
          CID      => "2>")
        PORT MAP (
          inst_w   => inst2_pw,
          inst_r   => inst2_pr,
          data_w   => data2_pw,
          data_r   => data2_pr,
          fpu_i    => fpu2_i,
          fpu_o    => fpu2_o,
          debug_s  => debug2_s,
          debug_t  => debug2_t,
          irl      => irl2,
          intack   => intack2,
          reset    => reset,
          reset_na => reset_na,
          clk      => clk);
      
      i_mcu_mp2: ENTITY work.mcu_mp
        GENERIC MAP (
          MMU_DIS  => false,
          ASICACHE => true,
          ASIINST  => true,
          BOOTMODE => true,
          CPUID    => 2,
          SYSCONF  => SYSCONF,
          WBSIZE   => WBSIZE,
          CPUTYPE  => CPUTYPE)
        PORT MAP (
          inst_w   => inst2_pw,
          inst_r   => inst2_pr,
          data_w   => data2_pw,
          data_r   => data2_pr,
          ext_w    => ext2_pw,
          ext_r    => ext2_pr,
          smp_w    => smp2_w,
          smp_r    => smp_r,
          hitx     => hitx2,
          hit      => hit2,
          cwb      => cwb2,
          last     => last2,
          sel      => sel2,
          cachena  => cachena,
          l2tlbena => l2tlbena,
          wback    => wback,
          aow      => aow,
          reset    => reset,
          reset_na => reset_na,
          clk      => clk);
      
    END GENERATE iCPU2;
    
    iCPU3:IF CPU3 GENERATE
      i_iu3: iu
        GENERIC MAP (
          DUMP     => true,
          CPUTYPE  => CPUTYPE,
          TECH     => TECH,
          CID      => "3>")
        PORT MAP (
          inst_w   => inst3_pw,
          inst_r   => inst3_pr,
          data_w   => data3_pw,
          data_r   => data3_pr,
          fpu_i    => fpu3_i,
          fpu_o    => fpu3_o,
          debug_s  => debug3_s,
          debug_t  => debug3_t,
          irl      => irl3,
          intack   => intack3,
          reset    => reset,
          reset_na => reset_na,
          clk      => clk);
      
      i_mcu_mp3: ENTITY work.mcu_mp
        GENERIC MAP (
          MMU_DIS  => false,
          ASICACHE => true,
          ASIINST  => true,
          BOOTMODE => true,
          CPUID    => 3,
          SYSCONF  => SYSCONF,
          WBSIZE   => WBSIZE,
          CPUTYPE  => CPUTYPE)
        PORT MAP (
          inst_w   => inst3_pw,
          inst_r   => inst3_pr,
          data_w   => data3_pw,
          data_r   => data3_pr,
          ext_w    => ext3_pw,
          ext_r    => ext3_pr,
          smp_w    => smp3_w,
          smp_r    => smp_r,
          hitx     => hitx3,
          hit      => hit3,
          cwb      => cwb3,
          last     => last3,
          sel      => sel3,
          cachena  => cachena,
          l2tlbena => l2tlbena,
          wback    => wback,
          aow      => aow,
          reset    => reset,
          reset_na => reset_na,
          clk      => clk);
      
    END GENERATE iCPU3;

    
    --fpu1_i <=FPU_MP_NOCPU;
    --ext1_pw.req<='0';
    --ext1_pw.dack<='1';

    GEN_FPU_MULTI:IF FPU_MULTI GENERATE
      i_fpu_mp01: fpu_mp
        GENERIC MAP (
          N        => NCPU,
          TECH     => TECH)
        PORT MAP (
          i0       => fpu0_i,
          o0       => fpu0_o,
          i1       => fpu1_i,
          o1       => fpu1_o,
          i2       => FPU_MP_NOCPU,
          o2       => OPEN,
          i3       => FPU_MP_NOCPU,
          o3       => OPEN,
          reset    => reset,
          reset_na => reset_na,
          clk      => clk);

      i_fpu_mp23: fpu_mp
        GENERIC MAP (
          N        => NCPU,
          TECH     => TECH)
        PORT MAP (
          i0       => fpu2_i,
          o0       => fpu2_o,
          i1       => fpu3_i,
          o1       => fpu3_o,
          i2       => FPU_MP_NOCPU,
          o2       => OPEN,
          i3       => FPU_MP_NOCPU,
          o3       => OPEN,
          reset    => reset,
          reset_na => reset_na,
          clk      => clk);
      
    END GENERATE GEN_FPU_MULTI;

    GEN_FPU_UNI:IF NOT FPU_MULTI GENERATE
      i_fpu0: fpu
        GENERIC MAP (
          TECH     => TECH)
        PORT MAP (
          i        => fpu0_i,
          o        => fpu0_o,
          reset    => reset,
          reset_na => reset_na,
          clk      => clk);
      i_fpu1: fpu
        GENERIC MAP (
          TECH    => TECH)
        PORT MAP (
          i        => fpu1_i,
          o        => fpu1_o,
          reset    => reset,
          reset_na => reset_na,
          clk      => clk);
      i_fpu2: fpu
        GENERIC MAP (
          TECH     => TECH)
        PORT MAP (
          i        => fpu2_i,
          o        => fpu2_o,
          reset    => reset,
          reset_na => reset_na,
          clk      => clk);
      i_fpu3: fpu
        GENERIC MAP (
          TECH    => TECH)
        PORT MAP (
          i        => fpu3_i,
          o        => fpu3_o,
          reset    => reset,
          reset_na => reset_na,
          clk      => clk);
    END GENERATE GEN_FPU_UNI;
    
    -----------------------------------
    i_smpmux: ENTITY work.smpmux
      GENERIC MAP (
        NCPU => NCPU,
        PROF => 20)
      PORT MAP (
        smp0_w   => smp0_w,
        cpu0_w   => ext0_pw,
        cpu0_r   => ext0_pr,
        hit0     => hit0,
        hitx0    => hitx0,
        cwb0     => cwb0,
        last0    => last0,
        sel0     => sel0,
        smp1_w   => smp1_w,
        cpu1_w   => ext1_pw,
        cpu1_r   => ext1_pr,
        hit1     => hit1,
        hitx1    => hitx1,
        cwb1     => cwb1,
        last1    => last1,
        sel1     => sel1,
        smp2_w   => smp2_w,
        cpu2_w   => ext2_pw,
        cpu2_r   => ext2_pr,
        hit2     => hit2,
        hitx2    => hitx2,
        cwb2     => cwb2,
        last2    => last2,
        sel2     => sel2,
        smp3_w   => smp3_w,
        cpu3_w   => ext3_pw,
        cpu3_r   => ext3_pr,
        hit3     => hit3,
        hitx3    => hitx3,
        cwb3     => cwb3,
        last3    => last3,
        sel3     => sel3,
        io_w     => iommu_pw,
        io_r     => iommu_pr,
        smp_r    => smp_r,
        mem_w    => smem_pw,
        mem_r    => smem_pr,
        reset_na => reset_na,
        clk      => clk);
    
    ext_no<=sel_decodage_smp(mem_pw);
    ext_vo_pr(0)<=mem_pr;
    ext_vo_pr(1)<=io_pr;
    mem_pw<=ext_vo_pw(0);
    io_pw <=ext_vo_pw(1);
    
    i_plomb_sel: ENTITY work.plomb_sel
      GENERIC MAP (
        NB   => 2,
        PROF => 20)
      PORT MAP (
        i_w      => smem_pw,
        i_r      => smem_pr,
        no       => ext_no,
        vo_w     => ext_vo_pw,
        vo_r     => ext_vo_pr,
        clk      => clk,
        reset_na => reset_na);
    
    i_iu_debug_mp: iu_debug_mp
      GENERIC MAP (
        ADRS => x"0",
        CPU0 => CPU0,
        CPU1 => CPU1,
        CPU2 => CPU2,
        CPU3 => CPU3)
      PORT MAP (
        dl_w     => dl_w,
        dl_r     => dl_r_cpu,
        debug0_s => debug0_s,
        debug0_t => debug0_t,
        debug1_s => debug1_s,
        debug1_t => debug1_t,
        debug2_s => debug2_s,
        debug2_t => debug2_t,
        debug3_s => debug3_s,
        debug3_t => debug3_t,
        debug_c  => debug_conf,
        dreset   => dreset,
        stopa    => debug_stopa,
        xstop    => xstop,
        reset_na => reset_na,
        clk      => clk);
    
    -----------------------------------
    dram_pw<=memm_pw;
    mem_pr<=dram_pr;

    --pragma synthesis_off
    ilog_inst:ENTITY work.plomb_log
      GENERIC MAP (nom => "INST0")
      PORT MAP (w => inst0_pw, r => inst0_pr, clk => clk, reset_na => reset_na);
    ilog_data:ENTITY work.plomb_log
      GENERIC MAP (nom => "DATA0")
      PORT MAP (w => data0_pw, r => data0_pr, clk => clk, reset_na => reset_na);
    ilog_inst2:ENTITY work.plomb_log
      GENERIC MAP (nom => "INST1")
      PORT MAP (w => inst1_pw, r => inst1_pr, clk => clk, reset_na => reset_na);
    ilog_data2:ENTITY work.plomb_log
      GENERIC MAP (nom => "DATA1")
      PORT MAP (w => data1_pw, r => data1_pr, clk => clk, reset_na => reset_na);

    ilog_mem:ENTITY work.plomb_log
      GENERIC MAP (nom => "MEM")
      PORT MAP (w => mem_pw, r => mem_pr, clk => clk, reset_na => reset_na);
    
    --pragma synthesis_on

      
  END GENERATE DOSMP;
  --###############################################################
  
  -----------------------------------
  
  xstop<='0';
  i_sync_rs: ENTITY work.synth
    GENERIC MAP (
      FREQ => SYSFREQ,
      RATE => SERIALRATE*8)
    PORT MAP (
      sync     => sync_rs_hi,
      clk      => clk,
      reset_na => reset_na);

  RSCLK:PROCESS(clk)
  BEGIN
    IF rising_edge(clk) THEN
      sync_rs<='0';
      IF sync_rs_hi='1' THEN
        rscpt<=(rscpt+1) MOD 8;
        IF debug_conf(0)='0' THEN
          sync_rs<=to_std_logic(rscpt=0);  -- 115200 bits/sec
        ELSE
          sync_rs<='1';                    -- 921600 bits/sec
        END IF;
      END IF;
    END IF;
  END PROCESS RSCLK;
  
  i_aciamux: ENTITY work.ts_aciamux
    GENERIC MAP (
      BREAK => ACIABREAK,
      TFIFO => 60,
      RFIFO => 10)
    PORT MAP (
      sync     => sync_rs,
      cts      => cts,
      txd      => txd3,
      tx0_data => io_txd3_data,
      tx0_req  => io_txd3_req,
      tx0_rdy  => io_txd3_rdy,
      tx1_data => debug_tx_data,
      tx1_req  => debug_tx_req,
      tx1_rdy  => debug_tx_rdy,
      rxd      => rxd3,
      rx0_data => io_rxd3_data,
      rx0_req  => io_rxd3_req,
      rx0_ack  => io_rxd3_ack,
      rx1_data => debug_rx_data,
      rx1_req  => debug_rx_req,
      rx1_ack  => debug_rx_ack,
      obreak   => obreak,
      osel     => osel,
      clk      => clk,
      reset_na => reset_na);

  -----------------------------------
  i_idu: ENTITY work.idu
    PORT MAP (
      tx_data  => debug_tx_data,
      tx_req   => debug_tx_req,
      tx_rdy   => debug_tx_rdy,
      rx_data  => debug_rx_data,
      rx_req   => debug_rx_req,
      rx_ack   => debug_rx_ack,
      dl_w     => dl_w,
      dl_r     => dl_r,
      reset_na => reset_na,
      clk      => clk);
  
  -----------------------------------
  i_dl_scsi: ENTITY work.dl_scsi
    GENERIC MAP (
      ADRS => x"8",
      N    => 11)
    PORT MAP (
      dl_w     => dl_w,
      dl_r     => dl_r_scsi,
      scsi_w   => scsi_w_i,
      scsi_r   => scsi_r,
      aux      => "0000000000",
      timecode => timecode,
      clk      => sclk,
      reset_na => reset_na);
  
  scsi_w<=scsi_w_i;
  
  -----------------------------------
  dl_r <=dl_r_cpu OR dl_r_t0 OR dl_r_t1 OR dl_r_t2 OR dl_r_t3 OR dl_r_scsi;
  
  -----------------------------------
  sigs(0)<=inst0_pw.req; -- 0
  sigs(1)<=data0_pw.req; -- 0
  sigs(2)<=ext0_pw.req; -- 1
  sigs(3)<=hit0; -- 0
  sigs(4)<=hitx0; -- 0
  sigs(5)<=sel0; -- 0
  sigs(6)<=cwb0; -- 0
  sigs(7)<='0';
  sigs(8)<=mem_pw.req; -- 0 
  sigs(9)<=smp0_w.req; -- 0
  sigs(15 DOWNTO 10)<=mem_pr.ack & ext0_pr.ack & ext0_pr.dreq &
                      mem_pr.dreq & inst0_pr.dreq & inst0_pr.ack;
  
  -----------------------------------
  timecode<=x"00000000" WHEN reset_na='0' ELSE
             mux(debug_stopa,timecode,timecode+1) WHEN rising_edge(clk);
  
  ------------------------------------------------------
  
  GenTrace:IF TRACE GENERATE
    i_dl_plomb_trace1: ENTITY work.dl_plomb_trace
      GENERIC MAP (ADRS =>x"4",SIGS => 0,ENAH => false,PROF =>4)
      PORT MAP (
        dl_w     => dl_w,
        dl_r     => dl_r_t0,
        pw       => inst0_pw,
        pr       => inst0_pr,
        sig      => sigs(0 DOWNTO 1),
        trig     => trigs,
        trigo    => trigs(0),
        gpo      => OPEN,
        timecode => timecode,
        astart   => astart,
        clk      => clk,
        reset_na => reset_na);

    i_dl_plomb_trace2: ENTITY work.dl_plomb_trace
      GENERIC MAP (ADRS =>x"5",SIGS => 32,ENAH => false,PROF =>16)
      PORT MAP (
        dl_w     => dl_w,
        dl_r     => dl_r_t1,
        pw       => data0_pw, --iommu_pw, --vid_pw,-- data0_pw, --data_pw, --filtre_pw, --io_pw, --data_pw,
        pr       => data0_pr, --iommu_pr, --vid_pr,-- data0_pr, --data_pr, --filtre_pr, --io_pr, --data_pr,
        sig      => sigs,
        trig     => trigs,
        trigo    => trigs(1),
        gpo      => OPEN,
        timecode => timecode,
        astart   => astart,
        clk      => clk,
        reset_na => reset_na);
    
    PROCESS(mem_pw,cwb0,cwb1,sel0,sel1,hit0,hit1) IS
    BEGIN
      memx_pw<=mem_pw;
      memx_pw.a(23 DOWNTO 16)<=cwb0 & cwb1 & "00" &
                                sel0 & sel1 & hit0 & hit1;
    END PROCESS;
    
    i_dl_plomb_trace3: ENTITY work.dl_plomb_trace
      GENERIC MAP (ADRS =>x"6",SIGS => 0,ENAH => false,PROF =>16)
      PORT MAP (
        dl_w     => dl_w,
        dl_r     => dl_r_t2,
        pw       => inst1_pw, --io_pw, --iommu_pw, --iommu_pw, --ext_pw,
        pr       => inst1_pr, --io_pr, --iommu_pr, --iommu_pr, --ext_pr,
        sig      => sigs(0 DOWNTO 1),
        trig     => trigs,
        trigo    => trigs(2),
        gpo      => OPEN,
        timecode => timecode,
        astart   => astart,
        clk      => clk,
        reset_na => reset_na);
    
    i_dl_plomb_trace4: ENTITY work.dl_plomb_trace  
      GENERIC MAP (ADRS =>x"7",SIGS => 0,ENAH => false,PROF =>16)
      PORT MAP (
        dl_w     => dl_w,
        dl_r     => dl_r_t3,
        pw       => data1_pw, --io_pw, --iommu_pw, --iommu_pw, --ext_pw,
        pr       => data1_pr, --io_pr, --iommu_pr, --iommu_pr, --ext_pr,
        sig      => sigs(0 DOWNTO 1),
        trig     => trigs,
        trigo    => trigs(3),
        gpo      => OPEN,
        timecode => timecode,
        astart   => astart,
        clk      => clk,
        reset_na => reset_na);
    
  END GENERATE GenTrace;

  GenNoTrace:IF NOT TRACE GENERATE
    dl_r_t0<=(x"0000_0000",'0');
    dl_r_t1<=(x"0000_0000",'0');
    dl_r_t2<=(x"0000_0000",'0');
    dl_r_t3<=(x"0000_0000",'0');
    
  END GENERATE GenNoTrace;
  
  -----------------------------------
  -- Remap framebuffer & ROM
  VideoShmuck:PROCESS(mem_pw)
  BEGIN
    memm_pw<=mem_pw;
    IF SS20 THEN
      -- Remap
      IF OBRAM AND mem_pw.ah=x"F" AND mem_pw.a(31 DOWNTO 24)=x"F0" THEN
        memm_pw.a(31 DOWNTO 21)<=OBRAM_ADR(31 DOWNTO 21);
        memm_pw.ah<=OBRAM_ADR_H;
      ELSIF mem_pw.ah=x"E" AND mem_pw.a(31)='0' AND mem_pw.a(23)='1' THEN
        memm_pw.a(31 DOWNTO 21)<=TCX_ADR(31 DOWNTO 21);
        memm_pw.ah<=TCX_ADR_H;
      END IF;
    ELSE
      IF OBRAM AND mem_pw.a(31 DOWNTO 28)=x"F" THEN
        memm_pw.a(31 DOWNTO 21)<=OBRAM_ADR(31 DOWNTO 21);
        memm_pw.ah<=OBRAM_ADR_H;
      ELSIF mem_pw.a(31 DOWNTO 28)=x"5" AND mem_pw.a(23)='1' THEN
        memm_pw.a(31 DOWNTO 21)<=TCX_ADR(31 DOWNTO 21);
        memm_pw.ah<=TCX_ADR_H;
      END IF;
    END IF;
  END PROCESS VideoShmuck;
  
  vram_pw<=vid_pw;
  vid_pr<=vram_pr;

  mem_io: ENTITY work.plomb_pvc
    GENERIC MAP (MODE => RW)
    PORT MAP (
      bus_w    => io_pw,
      bus_r    => io_pr,
      mem_w    => io_w,
      mem_r    => io_r,
      clk      => clk,
      reset_na => reset_na);
  
  --pragma synthesis_off
  ilog_ext:ENTITY work.plomb_log
    GENERIC MAP (nom => "EXT")
    PORT MAP (w => ext0_pw, r => ext0_pr, clk => clk, reset_na => reset_na);
  ilog_io:ENTITY work.plomb_log
    GENERIC MAP (nom => "IO")
    PORT MAP (w => io_pw, r => io_pr, clk => clk, reset_na => reset_na);
  ilog_iommu:ENTITY work.plomb_log
    GENERIC MAP (nom => "IOMMU")
    PORT MAP (w => iommu_pw, r => iommu_pr, clk => clk, reset_na => reset_na);
  --pragma synthesis_on
  
  -----------------------------------
  i_ts_io: ts_io
    GENERIC MAP (
      SS20       => SS20,
      ETHERNET   => ETHERNET,
      PS2        => PS2,
      TCX_ACCEL  => TCX_ACCEL,
      SPORT2     => SPORT2,
      TCX_ADR    => TCX_ADR,
      TCX_ADR_H  => TCX_ADR_H,
      HWCONF     => HWCONF,
      SYSFREQ    => SYSFREQ,
      CPU0       => CPU0,
      CPU1       => CPU1,
      CPU2       => CPU2,
      CPU3       => CPU3,
      TRACE      => TRACE,
      IOMMU_VER  => IOMMU_VER)
    PORT MAP (
      led         => led_io,
      ps2_i       => ps2_i,
      ps2_o       => ps2_o,
      sync_rs     => sync_rs,
      rxd1        => rxd1,
      txd1        => txd1,
      rxd2        => rxd2,
      txd2        => txd2,
      rxd4        => rxd4,
      txd4        => txd4,
      rxd3_data   => io_rxd3_data,
      rxd3_req    => io_rxd3_req,
      rxd3_ack    => io_rxd3_ack,
      txd3_data   => io_txd3_data,
      txd3_req    => io_txd3_req,
      txd3_rdy    => io_txd3_rdy,
      vga_r       => vga_r,
      vga_g       => vga_g,
      vga_b       => vga_b,
      vga_de      => vga_de,
      vga_hsyn    => vga_hsyn,
      vga_vsyn    => vga_vsyn,
      vga_hpos    => vga_hpos,
      vga_vpos    => vga_vpos,
      vga_clk     => vga_clk,
      vga_en      => vga_en,
      vga_dis     => vga_dis,
      pal_clk     => pal_clk,
      pal_d       => pal_d,
      pal_a       => pal_a,
      pal_wr      => pal_wr,
      scsi_w      => scsi_w_i,
      scsi_r      => scsi_r,
      sd_reg_w    => sd_reg_w,
      sd_reg_r    => sd_reg_r,
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
      irl0        => irl0,
      irl1        => irl1,
      irl2        => irl2,
      irl3        => irl3,
      io_w        => io_w,
      io_r        => io_r,
      iommu_pw    => iommu_pw,
      iommu_pr    => iommu_pr,
      vid_pw      => vid_pw,
      vid_pr      => vid_pr,
      flash_w     => flash_w,
      flash_r     => flash_r,
      ibram_w     => ibram_w,
      ibram_r     => ibram_r,
      iic1_scl    => iic1_scl,
      iic1_sda_o  => iic1_sda_o,
      iic1_sda_i  => iic1_sda_i,
      iic2_scl    => iic2_scl,
      iic2_sda_o  => iic2_sda_o,
      iic2_sda_i  => iic2_sda_i,
      iic3_scl    => iic3_scl,
      iic3_sda_o  => iic3_sda_o,
      iic3_sda_i  => iic3_sda_i,
      reset_mask_rev => reset_mask_rev,
      kbm_layout  => kbm_layout,
      swconf      => swconfs,
      stopa       => debug_stopa,
      iboot       => iboot,
      clk         => clk,
      reset_na    => reset_na);
  
  -----------------------------------
  -- Activation 1/8
  Gen8: PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      kk_cpt<=(kk_cpt+1) MOD 8;
      IF kk_cpt=0 THEN
        kk_pulse<='1';
      ELSE
        kk_pulse<='0';
      END IF;
    END IF;
  END PROCESS Gen8;
  
  -----------------------------------
  swconfs<=swconf WHEN rising_edge(clk);
  
  clk<=sclk;
  
  -----------------------------------
  rts <=debug0_s.dstop;
  
  ------------------------------------------------------------------------------
END ARCHITECTURE rtl;
