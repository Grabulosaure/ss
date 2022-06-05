--------------------------------------------------------------------------------
-- TEM : PLOMB
-- Banc mémoire double bus
--------------------------------------------------------------------------------
-- DO 11/2010
--------------------------------------------------------------------------------
-- 32 bits
-- 2 zones mémoire séparées
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
use std.textio.all;

LIBRARY work;
USE work.base_pack.ALL;
USE work.plomb_pack.ALL;

ENTITY iram_bi IS
  GENERIC (
    N    : uint8   :=10;                -- 2^N octets
    OCT  : boolean :=true;              -- Accès par octets
    INIT : string  :="void.sr");        -- Fichier d'initialisation
  PORT (
    -- Port 1
    mem1_w    : IN  type_pvc_w;
    mem1_r    : OUT type_pvc_r;
    
    -- Port 2
    mem2_w    : IN  type_pvc_w;
    mem2_r    : OUT type_pvc_r;
    clk       : IN std_logic
    );
END ENTITY iram_bi;
