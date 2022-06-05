-------------------------------------------------------------------------------
-- TEM
-- Interface PS/2
-------------------------------------------------------------------------------
-- DO 10/2012
-------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;

ENTITY ps2 IS
  GENERIC (
    SYSFREQ  : natural :=50_000_000);
  PORT (
    di       : IN  std_logic;
    do       : OUT std_logic;
    cki      : IN  std_logic;
    cko      : OUT std_logic;
    
    tx_data  : IN  uv8;    
    tx_req   : IN  std_logic;        -- Demande de transmission
    tx_ack   : OUT std_logic;        -- Prise en compte dmande
    
    rx_data  : OUT uv8;
    rx_err   : OUT std_logic;
    rx_val   : OUT std_logic;        -- Buffer Réception plein
    
    clk      : IN std_logic;
    reset_n  : IN std_logic
    );

END ENTITY ps2;

-------------------------------------------------------------------------------
ARCHITECTURE rtl OF ps2 IS
  
  CONSTANT WAIT_1us   : natural :=      1 * (SYSFREQ/1000_000);
  CONSTANT WAIT_5us   : natural :=      5 * (SYSFREQ/1000_000);
  CONSTANT WAIT_125us : natural :=    125 * (SYSFREQ/1000_000);
  CONSTANT WAIT_20ms  : natural := 20_000 * (SYSFREQ/1000_000);
  SIGNAL cpt    : natural RANGE 0 TO 11;
  SIGNAL tim    : natural RANGE 0 TO WAIT_125us+1;
  SIGNAL timout : natural RANGE 0 TO WAIT_20ms;
  
  SIGNAL ckis,ckis2,cki_sync,cki_sync2,cki_sync3 : std_logic;
  SIGNAL ckcpt : natural RANGE 0 TO WAIT_1us;
  
  TYPE enum_etat IS (sOISIF,
                    sREC,sREC2,
                    sEMIT,sEMIT2,sEMIT3,sEMIT4,sEMIT_END);
  SIGNAL etat : enum_etat;

  SIGNAL rad : unsigned(10 DOWNTO 0);
  SIGNAL rxpar : std_logic;

  FUNCTION par (CONSTANT v : uv8) RETURN std_logic IS
  BEGIN
    RETURN v(0) XOR v(1) XOR v(2) XOR v(3) XOR
           v(4) XOR v(5) XOR v(6) XOR NOT v(7);
  END FUNCTION;
  
BEGIN

  Machine: PROCESS (clk)
  BEGIN
    IF rising_edge(clk) THEN
      -- Antirebond
      cki_sync<=cki;
      cki_sync2<=cki_sync;
      cki_sync3<=cki_sync2;
      IF cki_sync3=cki_sync2 THEN
        IF ckcpt>0 THEN
          ckcpt<=ckcpt-1;
        END IF;
      ELSE
        ckcpt<=WAIT_1us;
      END IF;
      IF ckcpt=0 THEN
        ckis<=cki_sync3;
      END IF;
      ckis2<=ckis;
      -------------------------------------------------
      tim<=0;
      rx_val<='0';
      tx_ack<='0';
      cko<='1';
      do<='1';
      
      -------------------------------------------------
      CASE etat IS
        WHEN sOISIF =>
          cpt<=0;
          rxpar<='0';
          rad<=di & par(tx_data) & tx_data & '0';
          IF ckis2='1' AND ckis='0' THEN  -- Front descendant clock
            etat<=sREC;
          END IF;
          IF tx_req='1' AND ckis='1' THEN
            etat<=sEMIT;
            tx_ack<='1';
          END IF;
          -------------------------------------------------
          -- Réception trame
        WHEN sREC =>
          rad<=di & rad(10 DOWNTO 1);
          rxpar<=rxpar XOR di;
          IF cpt=10 THEN
            rx_data<=rad(9 DOWNTO 2);
            rx_err <=NOT (di AND rxpar);
            rx_val <='1';
            etat<=sOISIF;
          ELSE
            cpt<=cpt+1;
            etat<=sREC2;
          END IF;
          
        WHEN sREC2 =>
          IF ckis2='1' AND ckis='0' THEN  -- Front descendant clock
            etat<=sREC;
          END IF;
          -------------------------------------------------
          -- Emission trame
        WHEN sEMIT =>
          cko<='0';
          tim<=tim+1;
          IF tim=WAIT_125us THEN
            etat<=sEMIT2;
            tim<=0;
          END IF;
          
        WHEN sEMIT2 =>
          cko<='0';
          do<=rad(0);
          tim<=tim+1;
          IF tim=WAIT_5us THEN
            etat<=sEMIT3;
          END IF;

        WHEN sEMIT3 =>
          do<=rad(0);
          IF ckis2='1' AND ckis='0' THEN
            etat<=sEMIT4;
          END IF;

        WHEN sEMIT4 =>
          do<=rad(0);
          rad<=di & rad(10 DOWNTO 1);
          IF cpt=9 THEN
            etat<=sEMIT_END;
          ELSE
            cpt<=cpt+1;
            etat<=sEMIT3;
          END IF;
          
          -- ACK
        WHEN sEMIT_END =>
          IF ckis2='1' AND ckis='0' THEN
            etat<=sOISIF;
          END IF;
          -------------------------------------------------
      END CASE;
      -- Protection timeout
      IF etat=sOISIF THEN
        timout<=0;
      ELSIF timout=WAIT_20ms THEN
        etat<=sOISIF;
      ELSE
        timout<=timout+1;
      END IF;
      
      IF reset_n='0' THEN
        ckis<='0';
        etat<=sOISIF;
      END IF;
    END IF;
  END PROCESS Machine;
  
END ARCHITECTURE rtl;

