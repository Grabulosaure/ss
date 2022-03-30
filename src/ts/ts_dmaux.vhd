--------------------------------------------------------------------------------
-- TEM : TS
-- Registres DMA2 + AuxIO + Spéciaux
--------------------------------------------------------------------------------
-- DO 9/2010
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

-- <DMA2>
-- <AFAIRE : INIT RESET>
-- 00 :             : DMA2 SCSI. Control/Status Register

-- 04 :             : DMA2 SCSI. Address Register

-- 08 :             : DMA2 SCSI. Byte Count Register

-- 0C :             : DMA2 SCSI. Test Register

-- 10 : E_CSR       : DMA2 Ethernet. Control/Status
--        0 : E_INT_PEND : Ethernet Interrupt pending (R)
--        4 : E_INT_EN   : Ethernet Interrupt enable
--        7 : E_RESET    : Ethernet RESET
--    31:28 : E_DEV_ID : Ethernet DeviceID = 1010

-- 14 : E_TST_CSR   : DMA2 Ethernet. Test --> Inutile.

-- 18 : E_VLID      : DMA2 Ethernet. Cache Valid bits --> Inutile

-- 1C : E_BASE_ADDR : DMA2 Ethernet. Base Address Ethernet

-- <AUXIO0  : PA = 0xF_F180_0000> <7190_0000>
--     0 : SWCONF (0)
--     1 : SWCONF (1)
--     2 : SWCONF (2) : 1 = CG3        0 = TCX
--     3 : SWCONF (3) : 1 = NoAutoBoot 0 = AutoBoot
--     4 : SWCONF (4)
--     5 : SWCONF (5)
--     6 : SWCONF (6)
--     7 : SWCONF (7)
--     8 : ETHERNET : 1=ON 0=OFF
-- 23:16 : HWCONF
--    24 : LED
--     

-- <CONF0 : PA = 0xF_F180_0004> <7190_0004>
--     0 : IIC1 SCL : (RW) Video DDC & DAC Chrontel (1)
--     1 : IIC1 SDA : (RW) Video DDC & DAC Chrontel (1)
--     2 : IIC1 SDA : (R ) Video DDC & DAC Chrontel

--     4 : IIC2 SCL : (RW) Main : EEPROM M24C08 (1)
--     5 : IIC2 SDA : (RW) Main : EEPROM M24C08 (1)
--     6 : IIC2 SDA : (R ) Main : EEPROM M24C08

--     8 : IIC3 SCL : (RW) SFP (1)
--     9 : IIC3 SDA : (RW) SFP (1)
--    10 : IIC3 SDA : (R ) SFP

--    12 : MCLK : (RW) PHY MDIO CLK   (0)
--    13 : MDIO : (RW) PHY MDIO D_out (1)
--    14 : MDIO : (RW) PHY MDIO D_en  (0)
---   15 : MDIO : (R ) PHY MDIO D_in

-- 31:16 : Video Control :
--    16 : VGA_RUN
-- 19:17 : VGA_BPP

-- <CONF3 : PA = 0xF_F180_0010> <7190_0010>
-- 31:24 : IOMMU MASK_REV

-- <TICKTIMER : PA = 0xF_F180_0014>

-- <SD_CONF/STAT : PA = 0xF_F180_0018> <7190_0018>
--    22 : SYSACE_EN
--    23 : SDMMC_EN

-- <SD_AADRS     : PA = 0xF_F180_001C>


-- <AUXIO1  : PA = 0xF_F1A0_1000>
--  0 : Power OFF (1=Shutdown)
--  1 : Inhibit keyboard power-on interrupt
--  4 : Keyboard power-on interrupt
--  5 : Power fail detect

--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.plomb_pack.ALL;
USE work.ts_pack.ALL;
USE work.cpu_conf_pack.ALL;

ENTITY ts_dmaux IS
  GENERIC (
    HWCONF   : uv8;
    ETHERNET : boolean);
  PORT (
    sel_dma2   : IN  std_logic;
    sel_auxio0 : IN  std_logic;
    sel_auxio1 : IN  std_logic;
    w          : IN  type_pvc_w;
    r          : OUT type_pvc_r;
    
    dma_esp_iena     : OUT std_logic;
    dma_esp_int      : IN  std_logic;
    dma_esp_reset    : OUT std_logic;
    dma_esp_write    : OUT std_logic;
    dma_esp_addr_w   : OUT uv32;
    dma_esp_addr_r   : IN  uv32;
    dma_esp_addr_maj : OUT std_logic;
    
    dma_eth_int   : IN  std_logic; -- Ethernet Interrupt pending
    dma_eth_iena  : OUT std_logic; -- Ethernet Interrupt enable
    dma_eth_reset : OUT std_logic; -- Ethernet RESET controller
    dma_eth_ba    : OUT uv8;       -- Poids forts adresses Ethernet
    
    led         : OUT std_logic;
    
    -- I²C / MDIO
    iic1_scl    : OUT std_logic;
    iic1_sda_o  : OUT std_logic;
    iic1_sda_i  : IN  std_logic;
    iic2_scl    : OUT std_logic;
    iic2_sda_o  : OUT std_logic;
    iic2_sda_i  : IN  std_logic;
    iic3_scl    : OUT std_logic;
    iic3_sda_o  : OUT std_logic;
    iic3_sda_i  : IN  std_logic;
    
    phy_mdc     : OUT std_logic;
    phy_mdio_o  : OUT std_logic;
    phy_mdio_en : OUT std_logic;
    phy_mdio_i  : IN  std_logic;
    
    -- Video
    vga_ctrl    : OUT uv16;
    
    -- SD/MMC
    sd_reg_w    : OUT  type_sd_reg_w;
    sd_reg_r    : IN   type_sd_reg_r;
    
    -- Zarb
    mask_rev       : OUT uv8;
    reset_mask_rev : IN uv8;
    
    -- Auxtest
    swconf      : IN  uv8;
    stopa       : IN  std_logic;
    
    -- Global
    clk         : IN  std_logic;
    reset_na    : IN  std_logic
    );
END ENTITY ts_dmaux;

--##############################################################################

ARCHITECTURE rtl OF ts_dmaux IS
  SIGNAL dma_esp_iena_i : std_logic;
  SIGNAL dma_esp_reset_i : std_logic;
  SIGNAL dma_esp_write_i : std_logic;
  SIGNAL dma_esp_endma_i : std_logic;
  SIGNAL dma_eth_iena_i : std_logic;
  SIGNAL dma_eth_reset_i : std_logic;
  SIGNAL dma_eth_ba_i : uv8;
  SIGNAL led_i : std_logic;
  SIGNAL dr : uv32;
  SIGNAL c1_cl,c1_da : std_logic;
  SIGNAL c2_cl,c2_da : std_logic;
  SIGNAL c3_cl,c3_da : std_logic;
  SIGNAL mdc,mdio_o,mdio_en  : std_logic;
  SIGNAL vgactrl : uv16;
  
  SIGNAL tick : uv32;
  SIGNAL mask_rev_i : uv8;
  
--------------------------------------------------------------------------------
  
BEGIN

  -----------------------------------
  Sync_Regs: PROCESS (clk,reset_na,reset_mask_rev)
  BEGIN
    IF reset_na='0' THEN
      dma_eth_reset_i<='0';
      dma_eth_iena_i<='0';
      led_i<='0';
      c1_cl<='1';
      c1_da<='1';
      c2_cl<='1';
      c2_da<='1';
      c3_cl<='1';
      c3_da<='1';
      vgactrl<=x"0000";
      mdc<='0';
      mask_rev_i<=reset_mask_rev; --IOMMU_MASK_REV;
    ELSIF rising_edge(clk) THEN
      dr<=x"00000000"; -- Tous les autres registres.

      -------------------------------------------------------------
      -- 00 : DMA2 SCSI. Control/Status Register
      IF sel_dma2='1' AND w.req='1' AND w.a(5 DOWNTO 2)="00000" THEN
        IF w.be="1111" AND w.wr='1' THEN
          dma_esp_iena_i<=w.dw(4);
          dma_esp_reset_i<=w.dw(7);
          dma_esp_write_i<=w.dw(8);
          dma_esp_endma_i<=w.dw(9);
        END IF;
        dr<="1010" & x"0000" & "00" & dma_esp_endma_i & dma_esp_write_i &
             dma_esp_reset_i & "00" & dma_esp_iena_i & "000" & dma_esp_int;
      END IF;

      -- 04 : DMA2 SCSI. Address REGISTER
      dma_esp_addr_maj<='0';
      IF sel_dma2='1' AND w.req='1' AND w.a(5 DOWNTO 2)="00001" THEN
        IF w.be(3)='1' AND w.wr='1' THEN
          dma_esp_addr_maj<='1';
        END IF;
        dr<=dma_esp_addr_r;
      END IF;
      dma_esp_addr_w<=w.dw;
      
      -- 08 : DMA2 SCSI. Byte Count Register
      
      -- 0C : DMA2 SCSI. Test Register
      
      -------------------------------------------------------------
      -- 10 : E_CSR       : DMA2 Ethernet. Control/Status
      --        0 : E_INT_PEND : Ethernet Interrupt pending (R)
      --        4 : E_INT_EN   : Ethernet Interrupt enable
      --        7 : E_RESET    : Ethernet RESET
      --    31:28 : E_DEV_ID : Ethernet DeviceID = 1010
      IF sel_dma2='1' AND w.req='1' AND w.a(5 DOWNTO 2)="00100" THEN
        IF w.be="1111" AND w.wr='1' THEN
          dma_eth_reset_i<=w.dw(7);
          dma_eth_iena_i<=w.dw(4);
        END IF;
        dr<="1010" & x"00000" & dma_eth_reset_i &
             "00" & dma_eth_iena_i & "000" & dma_eth_int;
      END IF;
      
      -- 1C : E_BASE_ADDR : DMA2 Ethernet. Base Address Ethernet
      IF sel_dma2='1' AND w.req='1' AND w.a(5 DOWNTO 2)="00111" THEN
        IF w.be(3)='1' AND w.wr='1' THEN
          dma_eth_ba_i<=w.dw(31 DOWNTO 24);
        END IF;
        dr<=dma_eth_ba_i & x"000000";
      END IF;

      -------------------------------------------------------------
      -- AUXIO0
      IF sel_auxio0='1' AND w.req='1' AND w.a(4 DOWNTO 2)="000" THEN
        IF w.be(0)='1' AND w.wr='1' THEN
          led_i<=w.dw(24);
        END IF;
        dr<="0000000" & led_i & HWCONF &
             "0000000" & to_std_logic(ETHERNET) & swconf;
        
      END IF;

      -------------------------------------------------------------
      -- CONF0
      IF sel_auxio0='1' AND w.req='1' AND w.a(4 DOWNTO 2)="001" THEN
        IF w.be(3)='1' AND w.wr='1' THEN
          c1_cl<=w.dw(0);
          c1_da<=w.dw(1);
          c2_cl<=w.dw(4);
          c2_da<=w.dw(5);
        END IF;
        IF w.be(2)='1' AND w.wr='1' THEN
          c3_cl<=w.dw(8);
          c3_da<=w.dw(9);
          mdc    <=w.dw(12);
          mdio_o <=w.dw(13);
          mdio_en<=w.dw(14);
        END IF;
        IF w.be(0 TO 1)="11" AND w.wr='1' THEN
          vgactrl<=w.dw(31 DOWNTO 16);
        END IF;
        dr<= vgactrl &
             phy_mdio_i & mdio_en & mdio_o & mdc & 
             '0' & iic3_sda_i & c3_da & c3_cl &
             '0' & iic2_sda_i & c2_da & c2_cl &
             '0' & iic1_sda_i & c1_da & c1_cl;
      END IF;
      
      -------------------------------------------------------------
      -- CONF3
      IF sel_auxio0='1' AND w.req='1' AND w.a(4 DOWNTO 2)="100" THEN
        IF w.be(0)='1' AND w.wr='1' THEN
          mask_rev_i<=w.dw(31 DOWNTO 24);
        END IF;
        dr<=mask_rev_i & x"000000";
      END IF;
      
      -------------------------------------------------------------
      -- Tick Counter
      IF stopa='0' THEN
        tick<=tick+1;
      END IF;
      
      IF sel_auxio0='1' AND w.req='1' AND w.a(4 DOWNTO 2)="101" THEN
        IF w.be/="0000" AND w.wr='1' THEN
          tick<=x"00000000";
        END IF;
        dr<=tick;
      END IF;
      
      -------------------------------------------------------------
      -- SD/MMC CONFSTAT
      sd_reg_w.wr0<='0';
      IF sel_auxio0='1' AND w.req='1' AND w.a(4 DOWNTO 2)="110" THEN
        IF w.be/="0000" AND w.wr='1' THEN
          sd_reg_w.wr0<='1';
        END IF;
        dr<=sd_reg_r.d0;
      END IF;
      sd_reg_w.d<=w.dw;
      
      -------------------------------------------------------------
      -- SD/MMC ADRS
      sd_reg_w.wr1<='0';
      IF sel_auxio0='1' AND w.req='1' AND w.a(4 DOWNTO 2)="111" THEN
        IF w.be/="0000" AND w.wr='1' THEN
          sd_reg_w.wr1<='1';
        END IF;
        dr<=sd_reg_r.d1;
      END IF;
      
      -------------------------------------------------------------
    END IF;
  END PROCESS Sync_Regs;

  ----------------------------------------
  iic1_scl  <=c1_cl;
  iic1_sda_o<=c1_da;
  iic2_scl  <=c2_cl;
  iic2_sda_o<=c2_da;
  iic3_scl  <=c3_cl;
  iic3_sda_o<=c3_da;
  
  vga_ctrl<=vgactrl;
  phy_mdc<=mdc;
  phy_mdio_o <=mdio_o;
  phy_mdio_en<=mdio_en;
  
  mask_rev<=reset_mask_rev; --mask_rev_i;
  
  ----------------------------------------
  -- Relectures
  R_Gen:PROCESS(w,dr,sel_dma2,sel_auxio0,sel_auxio1)
  BEGIN
    r.ack<=w.req AND (sel_dma2 OR sel_auxio0 OR sel_auxio1);
    r.dr<=dr;
  END PROCESS R_Gen;

  dma_esp_iena<=dma_esp_iena_i;
  dma_esp_reset<=dma_esp_reset_i;
  dma_esp_write<=dma_esp_write_i;
  
  dma_eth_reset<=dma_eth_reset_i;
  dma_eth_iena<=dma_eth_iena_i;
  dma_eth_ba<=dma_eth_ba_i;
  
END ARCHITECTURE rtl;
