--------------------------------------------------------------------------------
-- TEM : PLOMB
-- Banc mémoire RAM générique à simple accès
--------------------------------------------------------------------------------
-- DO 9/2009
--------------------------------------------------------------------------------
-- Initialisation d'après un fichier Motorola S-Record
--------------------------------------------------------------------------------

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
USE std.textio.all;

LIBRARY work;
USE work.base_pack.ALL;
USE work.plomb_pack.ALL;

--##############################################################################

ARCHITECTURE srec OF iram IS

  CONSTANT SIZE : natural := 2 ** (N-2);

  TYPE type_mem IS ARRAY(0 TO SIZE-1) OF uv8;
  
  SIGNAL wr : unsigned(0 TO 3);
  SIGNAL dr,dw : uv32;

  SHARED VARIABLE mem0 : type_mem:=(OTHERS => x"00");
  SHARED VARIABLE mem1 : type_mem:=(OTHERS => x"00");
  SHARED VARIABLE mem2 : type_mem:=(OTHERS => x"00");
  SHARED VARIABLE mem3 : type_mem:=(OTHERS => x"00");

  ATTRIBUTE ramstyle : string;
  ATTRIBUTE ramstyle OF mem0 : VARIABLE IS "M9K, no_rw_check";
  ATTRIBUTE ramstyle OF mem1 : VARIABLE IS "M9K, no_rw_check";
  ATTRIBUTE ramstyle OF mem2 : VARIABLE IS "M9K, no_rw_check";
  ATTRIBUTE ramstyle OF mem3 : VARIABLE IS "M9K, no_rw_check";

--------------------------------------------------------------------------------
    
BEGIN

  wr<=mem_w.be WHEN mem_w.req='1' AND mem_w.wr='1' ELSE "0000";

  memproc:PROCESS  (clk)
  BEGIN
    IF rising_edge(clk) THEN
      dr(31 DOWNTO 24)<=mem0(to_integer(mem_w.a(N-1 DOWNTO 2)));
      IF wr(0)='1' THEN
        mem0(to_integer(mem_w.a(N-1 DOWNTO 2))):=dw(31 DOWNTO 24);
      END IF;

      dr(23 DOWNTO 16)<=mem1(to_integer(mem_w.a(N-1 DOWNTO 2)));
      IF wr(1)='1' THEN
        mem1(to_integer(mem_w.a(N-1 DOWNTO 2))):=dw(23 DOWNTO 16);
      END IF;
      
      dr(15 DOWNTO 8)<=mem2(to_integer(mem_w.a(N-1 DOWNTO 2)));
      IF wr(2)='1' THEN
        mem2(to_integer(mem_w.a(N-1 DOWNTO 2))):=dw(15 DOWNTO 8);
      END IF;

      dr(7 DOWNTO 0)<=mem3(to_integer(mem_w.a(N-1 DOWNTO 2)));
      IF wr(3)='1' THEN
        mem3(to_integer(mem_w.a(N-1 DOWNTO 2))):=dw(7 DOWNTO 0);
      END IF;
    END IF;
  END PROCESS memproc;
  
  mem_r.dr<=dr;
  dw<=mem_w.dw;
  
  mem_r.ack<='1';
  
  --------------------------------------
  --pragma synthesis_off
  Initialise: PROCESS IS
    FILE fil : text OPEN read_mode IS INIT;
    VARIABLE l : line;
    VARIABLE c : character;
    VARIABLE len,v : uint8;
    VARIABLE adrs,J : natural;
    VARIABLE da : boolean;
    VARIABLE txt : string(1 TO 32) :="                                ";

    IMPURE FUNCTION hex_read (CONSTANT nb : IN natural :=1) RETURN natural IS
      VARIABLE v : natural:=0;
      VARIABLE c : character;
    BEGIN
      FOR I IN 0 TO 2*nb-1 LOOP
        read (l,c);
        v:=v*16;
        IF c>='0' AND c<='9' THEN
          v:=v+character'pos(c)-character'pos('0');
        ELSIF c>='A' AND c<='F' THEN
          v:=v+character'pos(c)-character'pos('A')+10;
        ELSIF c>='a' AND c<='f' THEN
          v:=v+character'pos(c)-character'pos('a')+10;
        ELSE
          REPORT "Lecture fichier S-rec:Caractère invalide" SEVERITY failure;
        END IF;
      END LOOP;
      RETURN v;
    END FUNCTION hex_read;
    
  BEGIN
    IF init/="" AND init/="void.sr" THEN
      WHILE NOT endfile(fil) LOOP
        readline(fil,l);
        read(l,c);
        IF c='S' THEN
          read (l,c);
          len:=hex_read(1);
          da:=false;
          CASE c IS
            WHEN '0' =>                   -- A16 / Init
              adrs:=hex_read(2);
              FOR I IN 1 TO len-3 LOOP
                v:=hex_read(1);
                txt(I):=character'val(v);
              END LOOP;
              REPORT "Fichier :'" & txt & "'" SEVERITY note;
              
            WHEN '1' =>                   -- A16 / Data
              adrs:=hex_read(2);
              da:=true;
              len:=len-3;
            WHEN '2' =>                   -- A24 / Data
              adrs:=hex_read(3);
              da:=true;
              len:=len-4;
            WHEN '3' =>                   -- A32 / Data
              adrs:=hex_read(1);        -- Suppression Offset Fxxx_xxxx
              adrs:=hex_read(3);
              da:=true;
              len:=len-5;
            WHEN '7' | '8' | '9' =>
              NULL;
              
            WHEN OTHERS =>
              REPORT "Lecture fichier S-rec:Caractère invalide"
                SEVERITY failure;
          END CASE;
          IF da THEN
            --REPORT "Init:  A=" & integer'image(adrs) &
            --  " L=" & integer'image(len-3) SEVERITY note;
            FOR I IN 0 TO len-1 LOOP
              v:=hex_read(1);
              J:=(adrs+I) MOD 4;
              IF (adrs+I)/4<=SIZE-1 THEN
                CASE J IS
                  WHEN 0 =>      mem0((adrs+I)/4):=to_unsigned(v,8);
                  WHEN 1 =>      mem1((adrs+I)/4):=to_unsigned(v,8);
                  WHEN 2 =>      mem2((adrs+I)/4):=to_unsigned(v,8);
                  WHEN OTHERS => mem3((adrs+I)/4):=to_unsigned(v,8);
                END CASE;
              ELSE
                REPORT "Initialisation IRAM hors limites : " &
                  To_HString(to_unsigned(adrs+I,32))
                  SEVERITY warning;
              END IF;
            END LOOP;
          END IF;
        END IF;
      END LOOP;

      WAIT;
    ELSE
      WAIT;
    END IF;
    
  END PROCESS Initialise;
  --pragma synthesis_on
    
END ARCHITECTURE srec;
