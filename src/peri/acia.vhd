-------------------------------------------------------------------------------
-- TEM
-------------------------------------------------------------------------------
-- DO ?/2004
-------------------------------------------------------------------------------
-- Contrôleur de liaison série asynchrone à deux balles
-------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

-- Fbit = Fclk / 16 * MUL / DIV

--      25MHz *  192 / 15625 = 19200b/s * 16
--      25MHz * 1152 / 15625 = 115200b/s * 16

-------------------------------------------------------------------------------
LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;

ENTITY acia IS
  GENERIC (
    TFIFO : natural :=0;
    RFIFO : natural :=1);
  PORT (
    sync     : IN  std_logic;
    
    txd      : OUT std_logic;
    tx_data  : IN  uv8;    
    tx_req   : IN  std_logic;        -- Demande de transmission
    tx_rdy   : OUT std_logic;        -- Buffer Emission vide
    
    rxd      : IN  std_logic;
    rx_data  : OUT uv8;
    rx_break : OUT std_logic;
    rx_req   : OUT std_logic;        -- Buffer Réception vide
    rx_ack   : IN  std_logic;        -- Acquittement donnee recue
    
    clk      : IN std_logic;
    reset_n  : IN std_logic);
END ENTITY acia;

-------------------------------------------------------------------------------
ARCHITECTURE rtl OF acia IS

  SIGNAL sync16   : std_logic;
  SIGNAL cpt16 : natural RANGE 0 TO 15;

  SIGNAL tx_fifo  : arr_uv8(0 TO TFIFO-1);
  SIGNAL tx_lev   : natural RANGE 0 TO TFIFO;
  SIGNAL tx_vv    : std_logic;
  SIGNAL tx_trans : std_logic;
  SIGNAL tx_buf   : unsigned(9 DOWNTO 0);
  SIGNAL tx_cpt   : natural RANGE 0 TO 11;

  SIGNAL rx_fifo  : arr_uv8(0 TO RFIFO-1);
  SIGNAL rx_lev   : natural RANGE 0 TO RFIFO;
  SIGNAL rx_vv    : std_logic;
  SIGNAL rx_phase : natural RANGE 0 TO 15;
  SIGNAL rx_trans : std_logic;
  SIGNAL rx_rad   : unsigned(8 DOWNTO 0);
  SIGNAL rx_cpt   : natural RANGE 0 TO 11;
  SIGNAL rxd_sync,rxd_sync2 : std_logic;
  SIGNAL rx_brx : std_logic;
  
BEGIN

  -------------------------------------------------
  -- Générateur d'horloge, synthétiseur
  ClockGen:PROCESS (clk)
  BEGIN
    IF rising_edge(clk) THEN
      sync16<='0';
      IF sync='1' THEN
        IF cpt16/=15 THEN
          cpt16<=cpt16+1;
        ELSE
          cpt16<=0;
          sync16<='1';
        END IF;
      END IF;

      IF reset_n = '0' THEN
        sync16<='0';
        cpt16<=0;
      END IF;
    END IF;
  END PROCESS ClockGen;

  -------------------------------------------------
  -- Emission
  Emit:PROCESS (clk)
    VARIABLE pop_v : std_logic;
  BEGIN
    IF rising_edge(clk) THEN
      ---------------------------------------------
      IF sync16='1' THEN
        IF tx_trans='0' THEN
          txd<='1';
        ELSE
          tx_buf<='1' & tx_buf(9 DOWNTO 1);
          txd<=tx_buf(0);
        END IF;
        
        IF tx_cpt<9 THEN
          tx_cpt<=tx_cpt+1;
        ELSE
          tx_trans<='0';
        END IF;
      END IF;
      pop_v:='0';
      IF (tx_vv='1'  AND tx_trans='0' AND TFIFO>0) OR
         (tx_req='1' AND tx_trans='0' AND TFIFO=0) THEN
        tx_trans<='1';
        tx_cpt<=0;
        IF TFIFO=0 THEN
          tx_buf<='1' & tx_data & '0';
        ELSE
          tx_buf<='1' & tx_fifo(tx_lev) & '0';
        END IF;
        pop_v:='1';
      END IF;
      ---------------------------------------------
      -- FIFO
      IF tx_req='1' AND TFIFO>0 THEN
        tx_fifo<=tx_data & tx_fifo(0 TO TFIFO-2);
      END IF;
      IF tx_req='1' AND pop_v='0' AND TFIFO>0 THEN
        -- Empile
        IF tx_vv='1' THEN
          tx_lev<=tx_lev+1;
        END IF;
        tx_vv<='1';
      ELSIF tx_req='0' AND pop_v='1' AND TFIFO>0 THEN
        -- Dépile
        IF tx_lev>0 THEN
          tx_lev<=tx_lev-1;
        ELSE
          tx_vv<='0';
        END IF;
      END IF;
      ---------------------------------------------
      IF reset_n = '0' THEN
        tx_cpt<=0;
        tx_trans<='0';
        tx_buf<="1111111111";
        txd<='1';
        tx_vv<='0';
        tx_lev<=0;
      END IF;
    END IF;
  END PROCESS Emit;

  tx_rdy<=to_std_logic(((tx_lev<TFIFO-1) AND TFIFO>1) OR
                       (tx_vv='0'        AND TFIFO=1) OR
                       (tx_trans='0'     AND TFIFO=0));
  
  -------------------------------------------------
  -- Réception
  Recept: PROCESS (clk)
    VARIABLE push_v : std_logic;
  BEGIN
    IF rising_edge(clk) THEN
      rx_break<='0';
      push_v:='0';
      rxd_sync<=rxd;
      rxd_sync2<=rxd_sync;              -- Asynchronismes
      IF sync='1' THEN            -- Horloge bit *16
        IF rx_trans='0' THEN
          IF rxd_sync2='0' THEN
            rx_trans<='1';
            rx_phase<=cpt16;
            rx_cpt<=0;
          END IF;
        ELSE
          IF rx_phase=(cpt16 + 8) MOD 16 THEN
            rx_rad<=rxd_sync2 & rx_rad(8 DOWNTO 1);
            IF rx_cpt/=9 THEN
              rx_cpt<=rx_cpt+1;
            ELSE
              IF rxd_sync2='1' THEN
                push_v:=NOT rx_brx;
                rx_trans<='0';
                rx_brx<='0';
                rx_break<=rx_brx;
              ELSE
                rx_brx<='1';
              END IF;
            END IF;
          END IF;
        END IF;
      END IF;
      ---------------------------------------------
      -- FIFO
      IF push_v='1' THEN
        rx_fifo<=rx_rad(8 DOWNTO 1) & rx_fifo(0 TO RFIFO-2);
      END IF;
      IF push_v='1' AND rx_ack='0' THEN
        -- Empile
        IF rx_vv='1' AND rx_lev<RFIFO-1 THEN
          rx_lev<=rx_lev+1;
        ELSE
          rx_vv<='1';
        END IF;
      ELSIF push_v='0' AND rx_ack='1' AND rx_vv='1' THEN
        -- Dépile
        IF rx_lev>0 THEN
          rx_lev<=rx_lev-1;
        ELSE
          rx_vv<='0';
        END IF;
      END IF;

      ---------------------------------------------      
      IF reset_n = '0' THEN
        rx_trans<='0';
        rx_phase<=0;
        rx_cpt<=0;
        rx_rad<=(OTHERS =>'0');
        rx_vv<='0';
        rx_lev<=0;
        rx_brx<='0';
      END IF;
    END IF;
  END PROCESS Recept;

  rx_data<=rx_fifo(rx_lev);
  rx_req<=rx_vv;

  ASSERT RFIFO>0 REPORT "Erreur RFIFO" SEVERITY error;

END ARCHITECTURE rtl;
