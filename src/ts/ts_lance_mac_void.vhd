-------------------------------------------------------------------------------
-- TEM : TS
-------------------------------------------------------------------------------
-- DO 3/2018
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.plomb_pack.ALL;
USE work.ts_pack.ALL;

ENTITY ts_lance_mac IS
  PORT (
    -- MII -> RMII
    phy_txd     : OUT uv4;       -- MII Data             RMII : TXD[1:0]
    phy_tx_en   : OUT std_logic; -- MII Transmit Enable  RMII : TX_EN
    phy_tx_er   : OUT std_logic; -- MII Transmit Error   RMII : Unused
    phy_tx_clk  : IN  std_logic; -- MII Transmit Clock   RMII : CLK = RX_CLK
    phy_col     : IN  std_logic; -- MII Collision (async.) RMII : Unused
    
    phy_rxd     : IN  uv4;       -- MII Data             RMII : RXD[1:0]
    phy_rx_dv   : IN  std_logic; -- MII Receive Data Valid RMII : CRS_DV
    phy_rx_er   : IN  std_logic; -- MII Receive Error      RMII : Unused
    phy_rx_clk  : IN  std_logic; -- MII Receive Clock 25MHz/2.5MHz RMII : CLK
    phy_crs     : IN  std_logic; -- MII Carrier Sense (async.) : RMII : Unused
    
    phy_int_n   : IN  std_logic;
    phy_reset_n : OUT std_logic;
    
    -- Interne
    mac_emi_w   : IN  type_mac_emi_w;
    mac_emi_r   : OUT type_mac_emi_r;
    mac_rec_w   : IN  type_mac_rec_w;
    mac_rec_r   : OUT type_mac_rec_r;
    
    clk         : IN std_logic;
    reset_na    : IN std_logic
    );
END ENTITY ts_lance_mac;

-------------------------------------------------------------------------------
ARCHITECTURE rmii OF ts_lance_mac IS
  
BEGIN

  mac_emi_r.fifordy<='1';
  mac_emi_r.busy<='0';

  mac_rec_r.fifordy<='0';
  mac_rec_r.deof<='0';
  mac_rec_r.eof<='0';

  phy_txd<="0000";
  phy_tx_en<='0';
  phy_tx_er<='0';
  phy_reset_n<='1';

  
  
END ARCHITECTURE rmii;
