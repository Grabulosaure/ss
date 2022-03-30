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

ARCHITECTURE srec OF iram_bi IS

  COMPONENT iram IS
    GENERIC (
      N    : uint8;
      VAR  : uint8;
      OCT  : boolean;
      INIT : string);
    PORT (
      mem_w    : IN  type_pvc_w;
      mem_r    : OUT type_pvc_r;
      clk      : IN  std_logic;
      reset_na : IN  std_logic);
  END COMPONENT iram;
  
--------------------------------------------------------------------------------
BEGIN

  iram1:iram
    GENERIC MAP (
      N   => N,
      VAR => 0,
      OCT => OCT,
      INIT=> INIT)
   PORT MAP (
     mem_w    => mem1_w,
     mem_r    => mem1_r,
     clk      => clk,
     reset_na => reset_na);
    
  iram2:iram
    GENERIC MAP (
      N   => N,
      VAR => 0,
      OCT => OCT,
      INIT=> INIT)
   PORT MAP (
     mem_w => mem2_w,
     mem_r => mem2_r,
     clk      => clk,
     reset_na => reset_na);
  
END ARCHITECTURE srec;
