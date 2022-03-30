--------------------------------------------------------------------------------
-- TEM : TACUS
-- Contrôleur MMU / Cache
--------------------------------------------------------------------------------
-- DO 2/2010
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

USE work.base_pack.ALL;
USE work.plomb_pack.ALL;

ENTITY mcu IS
  GENERIC (
    MMU_DIS   : boolean := false;        -- Mode Cache sans MMU
    ASICACHE  : boolean := true;         -- ASI CACHE tag
    ASIINST   : boolean := true;         -- Cross ASI inst
    BOOTMODE  : boolean := true;         -- Bit 'bootmode'
    SYSCONF   : uv32    := x"0000_0000"; -- Config
    CPUTYPE   : natural := 0);           -- Type CPU
  PORT (
    inst_w   : IN  type_plomb_w;        -- Pipe Instructions IU -> MCU
    inst_r   : OUT type_plomb_r;        -- Pipe Instructions MCU -> IU
    data_w   : IN  type_plomb_w;        -- Pipe Données      IU -> MCU
    data_r   : OUT type_plomb_r;        -- Pipe Données      MCU -> IU
    
    ext_w    : OUT type_plomb_w;        -- Pipe MCU -> MEM
    ext_r    : IN  type_plomb_r;        -- Pipe MCU <- MEM
    
    cachena  : IN std_logic;
    l2tlbena : IN std_logic;
    reset    : IN std_logic;            -- Reset synchrone
    reset_na : IN std_logic;            -- Reset asynchrone
    clk      : IN std_logic             -- Horloge
    );
END ENTITY mcu;
