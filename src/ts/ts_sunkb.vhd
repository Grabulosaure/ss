--------------------------------------------------------------------------------
-- TEM : TS
-- Sun Type 4 keyboard emulation
--------------------------------------------------------------------------------
-- DO 10/2012
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

-- Commandes :
--  01 : RESET
--     -> FF 04 7F
--  02 : Bell ON
--  03 : Bell OFF
--  0A : Click ON
--  0B : Click OFF
--  0E <stat> : LED : 0=NumLock 1=Compose 2=Scroll 3=Caps
--  0F : Layout
--     -> FE <layout>

--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.plomb_pack.ALL;

ENTITY ts_sunkb IS
  PORT (
    -- ESCC side
    si_data : OUT uv8;                  -- KB -> Serial port
    si_req  : OUT std_logic;
    si_rdy  : IN  std_logic;
    so_data : IN  uv8;                  -- Serial port -> KB
    so_req  : IN  std_logic;
    so_rdy  : OUT std_logic;

    -- Keyboard side : Receive only
    kb_data : IN  uv8;
    kb_req  : IN  std_logic;
    kb_rdy  : OUT std_logic;
    leds    : OUT uv4;
    ledsm   : OUT std_logic;

    layout  : IN  uv8;
    
    -- Global
    clk     : IN std_logic;
    reset_n : IN std_logic
    );
END ENTITY ts_sunkb;

--##############################################################################

ARCHITECTURE rtl OF ts_sunkb IS

  CONSTANT CMD_RESET  : uv8 := x"01";
  CONSTANT CMD_LED    : uv8 := x"0E";
  CONSTANT CMD_LAYOUT : uv8 := x"0F";

  TYPE enum_etat IS (sOISIF,sREC,sREC2,
                     sRESET,sRESET2,sRESET3,
                     sLED,sLAYOUT,sLAYOUT2);
  SIGNAL etat : enum_etat;
  
  CONSTANT MAX : natural := 1_000; --<_000;  -- Délai 20ms
  SIGNAL cpt : natural RANGE 0 TO MAX;
  
BEGIN

  Machine: PROCESS (clk)
  BEGIN
    IF rising_edge(clk) THEN
      kb_rdy<='0';
      si_req<='0';
      so_rdy<='1';
      ledsm<='0';
      
      CASE etat IS
          --------------------------------------
        WHEN sOISIF =>
          cpt<=0;
          si_data<=kb_data;
          IF kb_req='1' THEN
            etat<=sREC;
            si_req<='1';
          ELSIF so_req='1' THEN
            IF so_data=CMD_RESET THEN
              etat<=sRESET;
            ELSIF so_data=CMD_LED THEN
              etat<=sLED;
            ELSIF so_data=CMD_LAYOUT THEN
              etat<=sLAYOUT;
            END IF;
            so_rdy<='0';
          END IF;
          
          --------------------------------------
        WHEN sREC =>
          si_data<=kb_data;
          IF si_rdy='1' THEN
            etat<=sREC2;
            kb_rdy<='1';
          ELSE
            si_req<='1';
          END IF;
          
        WHEN sREC2 =>
          si_data<=kb_data;
          etat<=sOISIF;
          
          --------------------------------------
        WHEN sRESET =>
          si_data<=x"FF";
          IF cpt/=MAX THEN
            cpt<=cpt+1;
          ELSE
            si_req<='1';
          END IF;
          so_rdy<='0';
          IF si_rdy='1'  THEN
            etat<=sRESET2;
            si_req<='0';
            cpt<=0;
          END IF;

        WHEN sRESET2 =>
          si_data<=x"04";
          IF cpt/=MAX THEN
            cpt<=cpt+1;
          ELSE
            si_req<='1';
          END IF;
          so_rdy<='0';
          IF si_rdy='1' THEN
            etat<=sRESET3;
            si_req<='0';
            cpt<=0;
          END IF;
          
        WHEN sRESET3 =>
          si_data<=x"7F";
          IF cpt/=MAX THEN
            cpt<=cpt+1;
          ELSE
            si_req<='1';
          END IF;
          so_rdy<='0';
          IF si_rdy='1' THEN
            etat<=sOISIF;
            si_req<='0';
            cpt<=0;
          END IF;
          
          --------------------------------------
        WHEN sLED =>
          si_data<=layout;
          si_req<='0';
          IF so_req='1' THEN
            so_rdy<='0';
            etat<=sOISIF;
            leds<=so_data(3 DOWNTO 0);
            ledsm<='1';
          END IF;
          
          --------------------------------------
        WHEN sLAYOUT =>
          si_data<=x"FE";
          IF cpt/=MAX THEN
            cpt<=cpt+1;
          ELSE
            si_req<='1';
          END IF;
          so_rdy<='0';
          IF si_rdy='1'  THEN
            etat<=sLAYOUT2;
            si_req<='0';
            cpt<=0;
          END IF;

        WHEN sLAYOUT2 =>
          si_data<=layout;
          IF cpt/=MAX THEN
            cpt<=cpt+1;
          ELSE
            si_req<='1';
          END IF;
          IF si_rdy='1'  THEN
            etat<=sOISIF;
            si_req<='0';
            cpt<=0;
          END IF;
          
          --------------------------------------
      END CASE;
      
      IF reset_n='0' THEN
        etat<=sOISIF;
      END IF;

    END IF;
  END PROCESS Machine;
  
END ARCHITECTURE rtl;

