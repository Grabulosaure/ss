--------------------------------------------------------------------------------
-- TEM : TS
-- Décodage d'adresses
--------------------------------------------------------------------------------
-- DO 9/2010
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
USE work.ts_pack.ALL;

ENTITY ts_decode IS
  GENERIC (
    SS20 : boolean := false);
  PORT (
    a   : IN unsigned(31 DOWNTO 0);
    ah  : IN unsigned(35 DOWNTO 32);
    s   : OUT type_sel;
    -- Global
    iboot    : IN std_logic;
    clk      : IN std_logic;
    reset_na : IN std_logic
    );
END ENTITY ts_decode;

--##############################################################################

--  XXXX  XXXX XXXX XXXX XXXX  XXXX XXXX XXXX XXXX
--  3333  3322 2222 2222 1111  1111 11            
--  5432  1098 7654 3210 9876  5432 1098 7654 3210

ARCHITECTURE rtl OF ts_decode IS

  SIGNAL sel : type_sel;
  SIGNAL aa : unsigned(35 DOWNTO 0);
--------------------------------------------------------------------------------
  
BEGIN
  aa<=ah & a;

-- SparcStation 5
  Gen5: IF NOT SS20 GENERATE
    
    -- x 0xxx xxxx : Main Memory (256M max)
    sel.ram    <=to_std_logic(aa(31 DOWNTO 28)=x"0"); -- RAM
    
    -- x 5xxx xxxx : Video
    sel.video  <=to_std_logic(aa(31 DOWNTO 28)=x"5"); -- Framebuffer
    
    -- x 784x xxxx : DMA2
    sel.dma2   <=to_std_logic(aa(31 DOWNTO 20)=x"784");

    -- x 788x xxxx : SCSI (ESP) DMA2
    sel.esp    <=to_std_logic(aa(31 DOWNTO 20)=x"788"); --ESP SCSI

    -- x 78Cx xxxx : LANCE
    sel.lance  <=to_std_logic(aa(31 DOWNTO 20)=x"78C"); -- Lance Ethernet
    
    -- x 1xxx xxxx : IOMMU
    sel.iommu  <=to_std_logic(aa(31 DOWNTO 28)=x"1"
--                            OR (aa(35 DOWNTO 32)="0000" AND aa(28)='1')
                              );   -- IOMMU + Arbitration
    
    -- x Bxxx xxxx :
    -- x F0xx xxxx : Boot ROM / IBRAM
    -- Si IBOOT est actif, on démarre depuis une RAM interne,pas depuis la FLASH
    sel.ibram  <=to_std_logic(aa(31 DOWNTO 28)=x"F") AND iboot;
    sel.rom    <=(to_std_logic(aa(31 DOWNTO 28)=x"F") AND NOT iboot) OR
                  to_std_logic(aa(31 DOWNTO 28)=x"B");
    
    -- x 71xx xxxx : System control space : SLAVIO
    sel.kbm    <=to_std_logic(aa(31 DOWNTO 20)=x"710"); -- Keyboard / Mouse
    sel.sport  <=to_std_logic(aa(31 DOWNTO 20)=x"711"); -- Serial ports
    sel.rtc    <=to_std_logic(aa(31 DOWNTO 20)=x"712"); -- NVRAM / TOD
    -- 713     : GPIO
    -- 714     : Floppy
    -- 715-716 : Reserved
    -- 718     : Configuration register
    sel.auxio0 <=to_std_logic(aa(31 DOWNTO 20)=x"719"); -- Auxiliary IO regs
    sel.auxio1 <=to_std_logic(aa(31 DOWNTO 20)=x"71A"); -- Diag message
    -- 71B     : MoDem
    -- 71C     : Reserved
    sel.timer  <=to_std_logic(aa(31 DOWNTO 20)=x"71D"); -- Timers
    sel.inter  <=to_std_logic(aa(31 DOWNTO 20)=x"71E"); -- Interrupt controller
    sel.syscon <=to_std_logic(aa(31 DOWNTO 20)=x"71F"); -- System Control Regs
    sel.led    <=to_std_logic(aa(31 DOWNTO 20)=x"716"); -- Diagnostic LEDs

    -- Unimplemented :
    -- 1F0 : System Control Reg
    --   - Soft Reset. Watchdog
    -- 180 : Configuration Reg
    --   - Modem ring interrupt enable
    --   - Modem ring select
    --   - Power fail detect
    --   - Floppy density
    --   - SuperSparc/MicroSparc chip mode.
    -- 1A0 : Diagnostic message Reg
    --   - 8 bits, no effect
    
  END GENERATE Gen5;
  
-- SparcStation 10/20
  Gen20: IF SS20 GENERATE
    
    -- 0 xxxx xxxx : Main Memory
    sel.ram    <=to_std_logic(aa(35 DOWNTO 32)=x"0"); -- RAM
    
    -- E 2xxx xxxx : Video
    sel.video  <=to_std_logic(aa(35 DOWNTO 28)=x"E2"); -- Framebuffer
    
    -- E F04x xxxx : DMA2
    sel.dma2   <=to_std_logic(aa(35 DOWNTO 20)=x"EF04");

    -- E F08x xxxx : SCSI (ESP) DMA2
    sel.esp    <=to_std_logic(aa(35 DOWNTO 20)=x"EF08"); --ESP SCSI

    -- E F0Cx xxxx : LANCE
    sel.lance  <=to_std_logic(aa(35 DOWNTO 20)=x"EF0C"); -- Lance Ethernet
    
    -- F Exxx xxxx : IOMMU
    --sel.iommu  <=to_std_logic(aa(35 DOWNTO 28)=x"FE"); -- IOMMU + Arbitration
    sel.iommu  <=to_std_logic(aa(35 DOWNTO 28)=x"FE"
                              OR (aa(35 DOWNTO 32)="0000" AND aa(28)='1')
                              );   -- IOMMU + Arbitration
    -- B xxxx xxxx :
    -- F F0xx xxxx : Boot ROM
    -- Si IBOOT est actif, on démarre depuis une RAM interne,pas depuis la FLASH
    --sel.ibram  <=to_std_logic(aa(35 DOWNTO 20)=x"FF00") AND iboot;
    --sel.rom  <=to_std_logic(aa(35 DOWNTO 24)=x"FF0") AND NOT sel.ibram; --ROM
    sel.ibram  <=aa(35) AND aa(33) AND aa(32) AND
                to_std_logic(aa(31 DOWNTO 24)=x"F0") AND (iboot XOR NOT aa(34));
    sel.rom    <=aa(35) AND aa(33) AND aa(32) AND
                to_std_logic(aa(31 DOWNTO 24)=x"F0") AND (iboot XOR aa(34));
    
    -- F F1xx xxxx : System control space
    sel.kbm    <=to_std_logic(aa(35 DOWNTO 20)=x"FF10"); -- Keyboard / Mouse
    sel.sport  <=to_std_logic(aa(35 DOWNTO 20)=x"FF11"); -- Serial ports
    sel.rtc    <=to_std_logic(aa(35 DOWNTO 20)=x"FF12"); -- NVRAM / TOD
    sel.timer  <=to_std_logic(aa(35 DOWNTO 20)=x"FF13"); -- Timers
    sel.inter  <=to_std_logic(aa(35 DOWNTO 20)=x"FF14"); -- Interrupt controller
    -- Audio / ISDN  FF15
    sel.led    <=to_std_logic(aa(35 DOWNTO 20)=x"FF16"); -- Diagnostic LEDs
    -- Floppy        FF17
    sel.auxio0 <=to_std_logic(aa(35 DOWNTO 20)=x"FF18"); -- Auxiliary IO1
    -- Reserved      FF19
    sel.auxio1 <=to_std_logic(aa(35 DOWNTO 20)=x"FF1A"); -- Auxiliary IO2
    -- Reserved      FF1B FF1C FF1D FF1E
    sel.syscon <=to_std_logic(aa(35 DOWNTO 20)=x"FF1F"); -- System Control Regs
    
  END GENERATE Gen20;

  sel.vide<=NOT (sel.ram OR sel.video OR sel.dma2 OR sel.esp OR
                 sel.lance OR sel.iommu OR
                 sel.rom OR sel.ibram OR sel.kbm OR sel.sport OR
                 sel.rtc OR sel.timer OR sel.inter OR sel.led OR
                 sel.auxio0 OR sel.auxio1 OR sel.syscon);
  
  s<=sel;
  
END ARCHITECTURE rtl;
