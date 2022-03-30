--------------------------------------------------------------------------------
-- TEM : TACUS
-- Unité entière
--------------------------------------------------------------------------------
-- DO 4/2009
--------------------------------------------------------------------------------
-- Entité
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
USE work.iu_pack.ALL;

ENTITY iu IS
  GENERIC (
    DUMP     : boolean := false;        -- Execution dump
    CPUTYPE  : natural := 0;            -- Type CPU
    TECH     : natural := 0;            -- Techno. implementation details
    CID      : string  := "");          -- CPU ID header
  PORT (
    inst_w   : OUT type_plomb_w;        -- Pipe Instruction CPU -> MEM
    inst_r   : IN  type_plomb_r;        -- Pipe Instruction MEM -> CPU
    data_w   : OUT type_plomb_w;        -- Pipe Données     CPU -> MEM
    data_r   : IN  type_plomb_r;        -- Pipe Données     MEM -> CPU

    fpu_i    : OUT type_fpu_i;          -- FPU
    fpu_o    : IN  type_fpu_o;          -- FPU
    
    debug_s  : OUT type_debug_s;        -- Debug
    debug_t  : IN  type_debug_t;        -- Debug
    
    irl      : IN  uv4;
    intack   : OUT std_logic;           -- External Interrupt acknowledge
    reset    : IN  std_logic;           -- Reset synchrone
    
    reset_na : IN std_logic;            -- Reset asynchrone
    clk      : IN std_logic             -- Horloge
    );
END ENTITY iu;
