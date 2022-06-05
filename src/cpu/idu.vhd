--------------------------------------------------------------------------------
-- TEM : TACUS
-- Interface Debug Universelle
--------------------------------------------------------------------------------
-- DO 9/2017
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

-- OP   aa bb cc dd : Write
-- OP > aa bb cc dd : Read

-- OP :
-- 4:7 : Address
-- 3   : 0=Read 1=Write
-- 2:1 : Register

--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

USE work.base_pack.ALL;
USE work.iu_pack.ALL;
USE work.plomb_pack.ALL;

ENTITY idu IS
  PORT (
    -- Série
    tx_data  : OUT uv8;    
    tx_req   : OUT std_logic;
    tx_rdy   : IN  std_logic;
    
    rx_data  : IN  uv8;
    rx_req   : IN  std_logic;
    rx_ack   : OUT std_logic;
    
    -- Debug Link
    dl_w     : OUT type_dl_w;
    dl_r     : IN  type_dl_r;
    
    -- Glo
    reset_n  : IN  std_logic;
    clk      : IN  std_logic
    );
END ENTITY idu;

-------------------------------------------------------------------------------
ARCHITECTURE rtl OF idu IS
  
  TYPE enum_state IS (sIDLE,sD1,sD2,sD3,sD4);
  SIGNAL wstate,rstate : enum_state;
  
  SIGNAL tx_req_i,rx_ack_i : std_logic;

  SIGNAL ddr : uv32;
  
BEGIN
  
  ------------------------------------------------------------------------------
  Coccinelle:PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      --------------------------------------
      tx_req_i<='0';
      rx_ack_i<='0';
      dl_w.wr<='0';
      
      --------------------------------------
      CASE wstate IS
        WHEN sIDLE =>
          IF rx_req='1' AND rx_ack_i='0' THEN
            rx_ack_i<='1';
            dl_w.a <=rx_data(7 DOWNTO 4);
            dl_w.op<=rx_data(3 DOWNTO 0);
            IF rx_data/=x"FF" AND rx_data/=x"00" THEN
              IF rx_data(3)='1' THEN
                wstate<=sD1;
              ELSE
                dl_w.wr<='1';
              END IF;
            END IF;
          END IF;
          
        WHEN sD1 =>
          IF rx_req='1' AND rx_ack_i='0' THEN
            rx_ack_i<='1';
            dl_w.d(7 DOWNTO 0)<=rx_data;
            wstate<=sD2;
          END IF;

        WHEN sD2 =>
          IF rx_req='1' AND rx_ack_i='0' THEN
            rx_ack_i<='1';
            dl_w.d(15 DOWNTO 8)<=rx_data;
            wstate<=sD3;
          END IF;

        WHEN sD3 =>
          IF rx_req='1' AND rx_ack_i='0' THEN
            rx_ack_i<='1';
            dl_w.d(23 DOWNTO 16)<=rx_data;
            wstate<=sD4;
          END IF;

        WHEN sD4 =>
          IF rx_req='1' AND rx_ack_i='0' THEN
            rx_ack_i<='1';
            dl_w.d(31 DOWNTO 24)<=rx_data;
            wstate<=sIDLE;
            dl_w.wr<='1';
          END IF;
          
      END CASE;

      -------------------------------------------------
      CASE rstate IS
        WHEN sIDLE =>
          ddr<=dl_r.d;
          IF dl_r.rd='1' THEN
            rstate<=sD1;
          END IF;

        WHEN sD1 =>
          tx_req_i<='1';
          tx_data<=ddr(7 DOWNTO 0);
          IF tx_rdy='1' AND tx_req_i='1' THEN
            rstate<=sD2;
            tx_req_i<='0';
          END IF;

        WHEN sD2 =>
          tx_req_i<='1';
          tx_data<=ddr(15 DOWNTO 8);
          IF tx_rdy='1' AND tx_req_i='1' THEN
            rstate<=sD3;
            tx_req_i<='0';
          END IF;

        WHEN sD3 =>
          tx_req_i<='1';
          tx_data<=ddr(23 DOWNTO 16);
          IF tx_rdy='1' AND tx_req_i='1' THEN
            rstate<=sD4;
            tx_req_i<='0';
          END IF;

        WHEN sD4 =>
          tx_req_i<='1';
          tx_data<=ddr(31 DOWNTO 24);
          IF tx_rdy='1' AND tx_req_i='1' THEN
            rstate<=sIDLE;
            tx_req_i<='0';
          END IF;

      END CASE;

      IF reset_n='0' THEN
        rstate<=sIDLE;
        wstate<=sIDLE;
        dl_w.wr<='0';
      END IF;
    END IF;
  END PROCESS Coccinelle;

  tx_req<=tx_req_i;
  rx_ack<=rx_ack_i;
  
  -------------------------------------------------
  
END ARCHITECTURE rtl;
