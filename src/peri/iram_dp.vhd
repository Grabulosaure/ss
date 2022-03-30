--------------------------------------------------------------------------------
-- TEM : PLOMB
-- Banc mémoire RAM générique à double accès
--------------------------------------------------------------------------------
-- DO 5/2007
--------------------------------------------------------------------------------
-- 32 bits
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

ENTITY iram_dp IS
  GENERIC (
    N    : uint8   :=10;                -- 2^N octets
    OCT  : boolean :=true;              -- Accès par octets
    NOM  : string  :="void.sr");        -- Fichier d'initialisation
  PORT (
    -- Port 1
    mem1_w    : IN  type_pvc_w;
    mem1_r    : OUT type_pvc_r;
    clk1      : IN std_logic;
    reset1_na : IN std_logic;
    
    -- Port 2
    mem2_w    : IN  type_pvc_w;
    mem2_r    : OUT type_pvc_r;
    clk2      : IN std_logic;
    reset2_na : IN std_logic
    );
END ENTITY iram_dp;

