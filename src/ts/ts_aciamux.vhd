--------------------------------------------------------------------------------
-- TEM : TS
-- Multiplexage Port Serie
--------------------------------------------------------------------------------
-- DO 12/2014
--------------------------------------------------------------------------------
-- Multiplex BREAK
--------------------------------------------------------------------------------

-- [BREAK] '4' : Sélection port 0
-- [BREAK] '3' : Sélection port 1

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

ENTITY ts_aciamux IS
  GENERIC (
    BREAK : boolean:=false;          -- false : CTS, true : BREAK
    TFIFO : natural:=0;
    RFIFO : natural:=1);
  PORT (
    sync     : IN  std_logic;
    cts      : IN  std_logic;
    txd      : OUT std_logic;
    tx0_data : IN  uv8;    
    tx0_req  : IN  std_logic;
    tx0_rdy  : OUT std_logic;
    tx1_data : IN  uv8;    
    tx1_req  : IN  std_logic;
    tx1_rdy  : OUT std_logic;
    
    rxd      : IN  std_logic;
    rx0_data : OUT uv8;
    rx0_req  : OUT std_logic;
    rx0_ack  : IN  std_logic;
    rx1_data : OUT uv8;
    rx1_req  : OUT std_logic;
    rx1_ack  : IN  std_logic;

    obreak   : OUT std_logic;
    osel     : OUT std_logic;
    clk      : IN std_logic;
    reset_na : IN std_logic
    );
END ENTITY ts_aciamux;

--##############################################################################

ARCHITECTURE rtl OF ts_aciamux IS
  
  SIGNAL tx_data  : uv8;
  SIGNAL tx_req   : std_logic;
  SIGNAL tx_rdy   : std_logic;
  SIGNAL rx_data  : uv8;
  SIGNAL rx_break : std_logic;
  SIGNAL rx_req   : std_logic;
  SIGNAL rx_ack   : std_logic;
  SIGNAL idi,sel  : std_logic;
  
BEGIN

  i_acia: ENTITY work.acia
    GENERIC MAP (
      TFIFO => TFIFO,
      RFIFO => RFIFO)
    PORT MAP (
      sync     => sync,
      txd      => txd,
      tx_data  => tx_data,
      tx_req   => tx_req,
      tx_rdy   => tx_rdy,
      rxd      => rxd,
      rx_data  => rx_data,
      rx_break => rx_break,
      rx_req   => rx_req,
      rx_ack   => rx_ack,
      clk      => clk,
      reset_na => reset_na);
  
  -----------------------------------
  -- Commutation signal CTS
  GenCTS: IF NOT BREAK GENERATE
    sel<=cts;
    idi<='0';
  END GENERATE GenCTS;

  -----------------------------------
  -- Commutation code BREAK
  GenBREAK: IF BREAK GENERATE
    Sync_sel:PROCESS (clk,reset_na) IS
    BEGIN
      IF reset_na='0' THEN
        idi<='0';
        sel<='0';
      ELSIF rising_edge(clk) THEN
        IF rx_break='1' THEN
          idi<='1';
        ELSIF rx_req='1' THEN
          idi<='0';
          IF idi='1' THEN
            IF rx_data=x"34" THEN       -- '4' 0011_0100
              sel<='0';
            END IF;
            IF rx_data=x"33" THEN       -- '3' 0011_0011
              sel<='1';
            END IF;
          END IF;
        END IF;
      END IF;
    END PROCESS;
  END GENERATE GenBREAK;
  
  -----------------------------------
  Async_sel:PROCESS (idi,sel,rx_req,rx0_ack,rx1_ack)
  BEGIN
    IF idi='0' THEN
      IF sel='0' THEN
        rx0_req<=rx_req;
        rx1_req<='0';
        rx_ack<=rx0_ack;
      ELSE
        rx0_req<='0';
        rx1_req<=rx_req;
        rx_ack<=rx1_ack;
      END IF;
    ELSE
      rx0_req<='0';
      rx1_req<='0';
      rx_ack<=rx_req;
    END IF;
  END PROCESS;

  rx0_data<=rx_data;
  rx1_data<=rx_data;

  tx0_rdy<=tx_rdy AND NOT sel;
  tx1_rdy<=tx_rdy AND sel;

  tx_data<=tx0_data WHEN sel='0' ELSE tx1_data;
  tx_req <=tx0_req  WHEN sel='0' ELSE tx1_req;

  obreak<=rx_break;
  osel<=sel;

END ARCHITECTURE rtl;
