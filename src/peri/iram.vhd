--------------------------------------------------------------------------------
-- TEM : PLOMB
-- Banc mémoire RAM générique à simple accès
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

ENTITY iram IS
  GENERIC (
    N    : uint8   :=10;                -- 2^N octets
    VAR  : uint8   :=0;                 -- Variante d'instanciation
    OCT  : boolean :=true;              -- Accès par octets
    INIT : string  :="void.sr");        -- Fichier d'initialisation
  PORT (
    mem_w : IN  type_pvc_w;
    mem_r : OUT type_pvc_r;
    
    -- Global
    clk      : IN std_logic;
    reset_na : IN std_logic
    );
END ENTITY iram;
