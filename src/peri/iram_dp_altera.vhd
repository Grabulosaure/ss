--------------------------------------------------------------------------------
-- TEM : PLOMB
-- Banc mémoire RAM générique à double accès
--------------------------------------------------------------------------------
-- DO 9/2009
--------------------------------------------------------------------------------
-- Initialisation d'après un fichier Motorola S-Record

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

-- ll : Longueur, en comptant adresse, données et checksum
-- aaaa : Adresse
-- cc : Checksum

-- Format S :
-- S0 ll aaaa 00112233445566.... CC
--            Bloc de début

-- S1 ll aaaa 00112233445566.... CC
-- S2 ll aaaaaa 00112233445566.... CC
-- S3 ll aaaaaaaa 00112233445566.... CC
--            Bloc de données

-- S5 ll aaaa 00112233445566.... CC
--            'Record Count'

-- S7 ll aaaaaaaa CC
-- S8 ll aaaaaa CC
-- S9 ll aaaa CC
--            Bloc de fin

--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
use std.textio.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.plomb_pack.ALL;

--##############################################################################

ARCHITECTURE simu OF iram_dp IS

  CONSTANT SIZE : natural := 2 ** (N-2);

  TYPE type_mem32 IS ARRAY(0 TO SIZE-1) OF uv32;
  TYPE type_mem8  IS ARRAY(0 TO SIZE-1) OF uv8;
  
  SIGNAL wr1,wr2 : unsigned(0 TO 3);
  
  SHARED VARIABLE mem : type_mem32 :=(OTHERS => x"00000000");
  SHARED VARIABLE mem0 : type_mem8 :=(OTHERS => x"00");
  SHARED VARIABLE mem1 : type_mem8 :=(OTHERS => x"00");
  SHARED VARIABLE mem2 : type_mem8 :=(OTHERS => x"00");
  SHARED VARIABLE mem3 : type_mem8 :=(OTHERS => x"00");

  ATTRIBUTE ramstyle : string;
  ATTRIBUTE ramstyle OF mem  : VARIABLE IS "no_rw_check";
  ATTRIBUTE ramstyle OF mem0 : VARIABLE IS "no_rw_check";
  ATTRIBUTE ramstyle OF mem1 : VARIABLE IS "no_rw_check";
  ATTRIBUTE ramstyle OF mem2 : VARIABLE IS "no_rw_check";
  ATTRIBUTE ramstyle OF mem3 : VARIABLE IS "no_rw_check";

--------------------------------------------------------------------------------
    
BEGIN
  
  --------------------------------------
  wr1<=mem1_w.be WHEN mem1_w.req='1' AND mem1_w.wr='1' ELSE "0000";
  wr2<=mem2_w.be WHEN mem2_w.req='1' AND mem2_w.wr='1' ELSE "0000";
  
  mem1_r.ack<='1';
  mem2_r.ack<='1';
  
  --------------------------------------
  GenNoOCT: IF NOT OCT GENERATE
    mem1:PROCESS  (clk1)
    BEGIN
      IF rising_edge(clk1) THEN
        mem1_r.dr<=mem(to_integer(to_01(mem1_w.a(N-1 DOWNTO 2))));
        IF wr1(0)='1' THEN
          mem(to_integer(to_01(mem1_w.a(N-1 DOWNTO 2)))):=mem1_w.dw;
        END IF;
      END IF;
    END PROCESS mem1;

    mem2:PROCESS  (clk2)
    BEGIN
      IF rising_edge(clk2) THEN
        mem2_r.dr<=mem(to_integer(to_01(mem2_w.a(N-1 DOWNTO 2))));
        IF wr2(0)='1' THEN
          mem(to_integer(to_01(mem2_w.a(N-1 DOWNTO 2)))):=mem2_w.dw;
        END IF;
      END IF;
    END PROCESS mem2;
  END GENERATE GenNoOCT;

  --------------------------------------
  GenOCT:IF OCT GENERATE
    
    pmem1:PROCESS  (clk1)
    BEGIN
      IF rising_edge(clk1) THEN
        mem1_r.dr(31 DOWNTO 24)<=mem0(to_integer(mem1_w.a(N-1 DOWNTO 2)));
        IF wr1(0)='1' THEN
          mem0(to_integer(mem1_w.a(N-1 DOWNTO 2))):=mem1_w.dw(31 DOWNTO 24);
        END IF;

        mem1_r.dr(23 DOWNTO 16)<=mem1(to_integer(mem1_w.a(N-1 DOWNTO 2)));
        IF wr1(1)='1' THEN
          mem1(to_integer(mem1_w.a(N-1 DOWNTO 2))):=mem1_w.dw(23 DOWNTO 16);
        END IF;
        
        mem1_r.dr(15 DOWNTO 8)<=mem2(to_integer(mem1_w.a(N-1 DOWNTO 2)));
        IF wr1(2)='1' THEN
          mem2(to_integer(mem1_w.a(N-1 DOWNTO 2))):=mem1_w.dw(15 DOWNTO 8);
        END IF;

        mem1_r.dr(7 DOWNTO 0)<=mem3(to_integer(mem1_w.a(N-1 DOWNTO 2)));
        IF wr1(3)='1' THEN
          mem3(to_integer(mem1_w.a(N-1 DOWNTO 2))):=mem1_w.dw(7 DOWNTO 0);
        END IF;
      END IF;
    END PROCESS pmem1;
    
    pmem2:PROCESS  (clk2)
    BEGIN
      IF rising_edge(clk2) THEN
        mem2_r.dr(31 DOWNTO 24)<=mem0(to_integer(mem2_w.a(N-1 DOWNTO 2)));
        IF wr2(0)='1' THEN
          mem0(to_integer(mem2_w.a(N-1 DOWNTO 2))):=mem2_w.dw(31 DOWNTO 24);
        END IF;

        mem2_r.dr(23 DOWNTO 16)<=mem1(to_integer(mem2_w.a(N-1 DOWNTO 2)));
        IF wr2(1)='1' THEN
          mem1(to_integer(mem2_w.a(N-1 DOWNTO 2))):=mem2_w.dw(23 DOWNTO 16);
        END IF;
        
        mem2_r.dr(15 DOWNTO 8)<=mem2(to_integer(mem2_w.a(N-1 DOWNTO 2)));
        IF wr2(2)='1' THEN
          mem2(to_integer(mem2_w.a(N-1 DOWNTO 2))):=mem2_w.dw(15 DOWNTO 8);
        END IF;

        mem2_r.dr(7 DOWNTO 0)<=mem3(to_integer(mem2_w.a(N-1 DOWNTO 2)));
        IF wr2(3)='1' THEN
          mem3(to_integer(mem2_w.a(N-1 DOWNTO 2))):=mem2_w.dw(7 DOWNTO 0);
        END IF;
      END IF;
    END PROCESS pmem2;
    
  END GENERATE GenOCT;
  --------------------------------------
  
END ARCHITECTURE simu;
