--------------------------------------------------------------------------------
-- TEM : TACUS
-- Contrôleur MMU / Cache Multiprocesseur
--------------------------------------------------------------------------------
-- DO 9/2015
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
USE work.mcu_pack.ALL;

ENTITY mcu_mp IS
  GENERIC (
    MMU_DIS   : boolean := false;        -- Mode Cache sans MMU
    ASICACHE  : boolean := true;         -- ASI CACHE tag
    ASIINST   : boolean := true;         -- Cross ASI inst
    BOOTMODE  : boolean := true;         -- Bit 'bootmode'
    CPUID     : natural := 0;            -- No. CPU = 0..3
    SYSCONF   : uv32    := x"0000_0000"; -- Config
    WBSIZE    : uv32    := x"0000_0000"; -- Write-back area size 0...WBSIZE-1
    CPUTYPE   : natural := 0);           -- Type CPU
  PORT (
    inst_w   : IN  type_plomb_w;        -- Pipe Instructions IU -> MCU
    inst_r   : OUT type_plomb_r;        -- Pipe Instructions MCU -> IU
    data_w   : IN  type_plomb_w;        -- Pipe Données      IU -> MCU
    data_r   : OUT type_plomb_r;        -- Pipe Données      MCU -> IU
    
    ext_w    : OUT type_plomb_w;        -- Pipe MCU -> MEM
    ext_r    : IN  type_plomb_r;        -- Pipe MCU <- MEM
    
    smp_w    : OUT type_smp;
    smp_r    : IN  type_smp;
    
    hitx     : IN  std_logic;
    hit      : OUT std_logic;           -- HIT cache (shared)
    cwb      : OUT std_logic;           -- HIT mod. cache, Coherent Write back
    last     : OUT std_logic;           -- Last cycle of transaction
    sel      : IN  std_logic;           -- Currently Selected CPU for SMP_W
    
    cachena  : IN std_logic;
    l2tlbena : IN std_logic;
    wback    : IN std_logic;
    aow      : IN std_logic;
    reset    : IN std_logic;            -- Reset synchrone
    reset_na : IN std_logic;            -- Reset asynchrone
    clk      : IN std_logic             -- Horloge
    );
END ENTITY mcu_mp;


--SMP_W : Entrée
--	Multiplexage EXT_W

--SEL  : Entrée
--	Processeur sélectionné pour SMP_W
--	Mise à jour différente selon que l'accès est à l'initiative du proc, 
--	ou d'un autre.

--HITX : Entrée
--	Ou entre tous les HIT
--	Pendant un FILL, positionne le cache en SHARED au lieu de EXCLU

--HIT  : Sortie
--	Cache Hit, instruction ou data
--	Sert à génerer HITX dans SMPMUX

--CWB  : Sortie
--	Cache Hit, modifié
