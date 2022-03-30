--------------------------------------------------------------------------------
-- TEM : TACUS
-- IU : Banque de registres 2R1W, 32bits
--------------------------------------------------------------------------------
-- DO 3/2009
--------------------------------------------------------------------------------
-- THRU=true  : Recopie si lecture & écriture simulatanée au même endroit
--      false : Lecture ancienne valeur
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;

LIBRARY work;
USE work.base_pack.ALL;

ENTITY iu_regs_2r1w IS
  GENERIC (
    THRU  : boolean := false;
    NREGS : natural);
  PORT (
    n_rs1    : IN  natural RANGE 0 TO NREGS-1;
    rs1      : OUT uv32;
    n_rs2    : IN  natural RANGE 0 TO NREGS-1;
    rs2      : OUT uv32;
    n_rd     : IN  natural RANGE 0 TO NREGS-1;
    rd       : IN  uv32;
    rd_maj   : IN  std_logic;   
    
    reset_na : IN  std_logic;
    clk      : IN  std_logic
    );
END ENTITY iu_regs_2r1w;

ARCHITECTURE beh OF iu_regs_2r1w IS

--------------------------------------------------------------------------------
  SHARED VARIABLE mem1 : arr_uv32(0 TO NREGS-1) :=(OTHERS => x"00000000");
  SHARED VARIABLE mem2 : arr_uv32(0 TO NREGS-1) :=(OTHERS => x"00000000");

  SIGNAL rs1_direct,rs2_direct : std_logic;
  SIGNAL rs1_i,rs2_i : uv32;
  SIGNAL rd_mem : uv32;
  
BEGIN

  regfile1: PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      IF rd_maj='1' THEN
        mem1(n_rd):=rd;
      END IF;
      rs1_i<=mem1(n_rs1);
    END IF;

  END PROCESS regfile1;

  regfile2: PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      IF rd_maj='1' THEN
        mem2(n_rd):=rd;      
      END IF;
      rs2_i<=mem2(n_rs2);
    END IF;

  END PROCESS regfile2;
  
  direct: PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      rd_mem<=rd;      
      IF rd_maj='1' AND n_rd=n_rs1 THEN
        rs1_direct<='1';
      ELSE
        rs1_direct<='0';
      END IF;
      IF rd_maj='1' AND n_rd=n_rs2 THEN
        rs2_direct<='1';
      ELSE
        rs2_direct<='0';
      END IF;
    END IF;
  END PROCESS direct;

  rs1<=rd_mem WHEN rs1_direct='1' AND THRU ELSE rs1_i;
  rs2<=rd_mem WHEN rs2_direct='1' AND THRU ELSE rs2_i; 
  
END ARCHITECTURE beh;
