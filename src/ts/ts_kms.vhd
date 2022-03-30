--------------------------------------------------------------------------------
-- TEM : TS
-- Keyboard / Mouse / SPort selector
--------------------------------------------------------------------------------
-- DO 10/2012
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

ENTITY ts_kms IS
  PORT (
    -- Extern
    ex_data : IN  uv8;
    ex_req  : IN  std_logic;
    ex_rdy  : OUT std_logic;

    -- Keyboard side : Receive only
    sp_data : OUT uv8;
    sp_req  : OUT std_logic;
    sp_rdy  : IN  std_logic;

    -- Keyboard side : Receive only
    kb_data : OUT uv8;
    kb_req  : OUT std_logic;
    kb_rdy  : IN  std_logic;

    -- Keyboard side : Receive only
    mo_data : OUT uv8;
    mo_req  : OUT std_logic;
    mo_rdy  : IN  std_logic;
    
    -- Global
    clk      : IN std_logic;
    reset_na : IN std_logic
    );
END ENTITY ts_kms;

--##############################################################################

ARCHITECTURE rtl OF ts_kms IS

  TYPE enum_sel IS (KEYBOARD,MOUSE,SPORT);
  SIGNAL sel,mem : enum_sel;
  SIGNAL ex_rdy_i : std_logic;
  SIGNAL cpt : natural RANGE 0 TO 3;

  CONSTANT CHAR_K_MIN : uv8 := to_unsigned(character'pos('k'),8);
  CONSTANT CHAR_K_MAJ : uv8 := to_unsigned(character'pos('K'),8);
  CONSTANT CHAR_M_MIN : uv8 := to_unsigned(character'pos('m'),8);
  CONSTANT CHAR_M_MAJ : uv8 := to_unsigned(character'pos('M'),8);
  CONSTANT CHAR_S_MIN : uv8 := to_unsigned(character'pos('s'),8);
  CONSTANT CHAR_S_MAJ : uv8 := to_unsigned(character'pos('S'),8);
  
BEGIN

  sp_data<=ex_data;
  kb_data<=ex_data;
  mo_data<=ex_data;
  
  sp_req <=ex_req WHEN sel=SPORT    ELSE '0';
  kb_req <=ex_req WHEN sel=KEYBOARD ELSE '0';
  mo_req <=ex_req WHEN sel=MOUSE    ELSE '0';
  
  ex_rdy_i <=sp_rdy OR kb_rdy OR mo_rdy;
  ex_rdy<=ex_rdy_i;
  
  Filtrox: PROCESS (clk,reset_na)
    VARIABLE ch  : enum_sel;
    VARIABLE raz : std_logic;
  BEGIN
    IF reset_na='0' THEN
      sel<=SPORT;
      cpt<=0;
    ELSIF rising_edge(clk) THEN
      raz:='0';
      IF ex_rdy_i='1' AND ex_req='1' THEN
        IF ex_data=CHAR_K_MIN OR ex_data=CHAR_K_MAJ THEN
          ch:=KEYBOARD;
        ELSIF ex_data=CHAR_M_MIN OR ex_data=CHAR_M_MAJ THEN
          ch:=MOUSE;
        ELSIF ex_data=CHAR_S_MIN OR ex_data=CHAR_S_MAJ THEN
          ch:=SPORT;
        ELSE
          ch:=SPORT;
          raz:='1';
        END IF;
        ----------------------
        IF raz='1' OR ch/=mem THEN
          cpt<=0;
        ELSE
          cpt<=cpt+1;
          IF cpt=2 THEN
            sel<=ch;
            cpt<=0;
          END IF;
        END IF;
        mem<=ch;
      END IF;
      
    END IF;
  END PROCESS Filtrox;
  
END ARCHITECTURE rtl;

