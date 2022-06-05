-------------------------------------------------------------------------------
-- TEM : TS
-------------------------------------------------------------------------------
-- DO 12/2010
-------------------------------------------------------------------------------
-- Interface MAC RMII pour LANCE, 16bits

-- Domaines d'horloge :
-- phy_ : Synchrone horloge RMII
-- mac_ : Synchrone horloge interne

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
USE work.plomb_pack.ALL;
USE work.ts_pack.ALL;

ENTITY ts_lance_mac IS
  PORT (
    -- MII -> RMII
    phy_txd     : OUT uv4;       -- MII Data             RMII : TXD[1:0]
    phy_tx_en   : OUT std_logic; -- MII Transmit Enable  RMII : TX_EN
    phy_tx_er   : OUT std_logic; -- MII Transmit Error   RMII : Speed Detect
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
    reset_n     : IN std_logic
    );
END ENTITY ts_lance_mac;

-------------------------------------------------------------------------------
ARCHITECTURE rmii OF ts_lance_mac IS
  
  CONSTANT MAGIC     : uv32 := x"C704DD7B";  -- CRC final
  CONSTANT CRC_POLY  : uv32 := x"04C11DB7";  -- Polynôme

  FUNCTION crc2_iter (
    CONSTANT d   : IN uv2;
    CONSTANT crc : IN uv32) RETURN unsigned IS
    VARIABLE c,mm : uv32;
  BEGIN
    c:=crc;
    FOR I IN 0 TO 1 LOOP
      mm:=(OTHERS =>d(I) XOR c(31));
      c:=(c(30 DOWNTO 0) & '0') XOR (mm AND CRC_POLY);
    END LOOP;
    RETURN c;
  END FUNCTION crc2_iter;
  
  FUNCTION crc2 (
    CONSTANT d   : IN uv2;
    CONSTANT crc : IN uv32) RETURN unsigned IS
    VARIABLE co : uv32;
    VARIABLE h  : uv2;
  BEGIN
    h(0):=d(0) XOR crc(31);
    h(1):=d(1) XOR crc(30);
    co(0) :=h(1);
    co(1) :=h(0)   XOR h(1);
    co(2) :=crc(0)  XOR h(0) XOR h(1);
    co(3) :=crc(1)  XOR h(0);
    co(4) :=crc(2)  XOR h(1);
    co(5) :=crc(3)  XOR h(0) XOR h(1);
    co(6) :=crc(4)  XOR h(0);
    co(7) :=crc(5)  XOR h(1);
    co(8) :=crc(6)  XOR h(0) XOR h(1);
    co(9) :=crc(7)  XOR h(0);
    co(10):=crc(8)  XOR h(1);
    co(11):=crc(9)  XOR h(0) XOR h(1);
    co(12):=crc(10) XOR h(0) XOR h(1);
    co(13):=crc(11) XOR h(0);
    co(14):=crc(12);
    co(15):=crc(13);
    co(16):=crc(14) XOR h(1);
    co(17):=crc(15) XOR h(0);
    co(18):=crc(16);
    co(19):=crc(17);
    co(20):=crc(18);
    co(21):=crc(19);
    co(22):=crc(20) XOR h(1);
    co(23):=crc(21) XOR h(0) XOR h(1);
    co(24):=crc(22) XOR h(0);
    co(25):=crc(23);
    co(26):=crc(24) XOR h(1);
    co(27):=crc(25) XOR h(0);
    co(28):=crc(26);
    co(29):=crc(27);
    co(30):=crc(28);
    co(31):=crc(29);
    RETURN co;    
  END crc2;

  SIGNAL phy_reset_na : std_logic;

  --------------------------------------
  -- Réception
  SIGNAL phy_rxd2 : uv2;
  SIGNAL phy_rx_dv2,phy_rx_dv3,phy_rx_dv4 : std_logic;
  SIGNAL phy_rx_dv5,phy_rx_dv6,phy_rx_dv7,phy_rx_dv8 : std_logic;
  SIGNAL rec_pulse,rec_spd : std_logic; -- 0=100MHz 1=10MHz
  SIGNAL rec_div,rec_dcpt,rec_dcptmem : natural RANGE 0 TO 10;
  SIGNAL rec_ref : uv2;
  TYPE enum_rec_dstate IS (sIDLE,sPRIM,sSUI);
  SIGNAL rec_dstate : enum_rec_dstate;
  SIGNAL rec_len : unsigned(11 DOWNTO 0);
  SIGNAL rec_error : std_logic;
  SIGNAL rec_c0,rec_c1,rec_c2 : std_logic;
  SIGNAL rec_data,rec_data2,rec_data3,rec_data4,rec_d_mem : uv16;
  SIGNAL rec_srec,rec_srec2,rec_srec3 : std_logic;
  SIGNAL rec_eof,rec_eof_mem : std_logic;
  SIGNAL rec_filt : std_logic;
  SIGNAL rec_crc : uv32;
  SIGNAL rec_dhash : unsigned(5 DOWNTO 0);
  SIGNAL rec_dcrcok : std_logic;
  SIGNAL rec_push : std_logic;
  SIGNAL mac_rec_push,mac_rec_push_sync,mac_rec_push_sync2 : std_logic;
  SIGNAL mac_rec_eof,mac_rec_eof_sync,mac_rec_eof_sync2 : std_logic;
  SIGNAL rec_dlen : unsigned(11 DOWNTO 0);
  TYPE enum_rec_state IS (sIDLE,sRECEIVE,sPREAMBLE);
  SIGNAL rec_state : enum_rec_state;

  SIGNAL mac_rec_lev : natural RANGE 0 TO 32;
  SIGNAL mac_rec_fifordy : std_logic;
  SIGNAL mac_rec_cpt_in,mac_rec_cpt_out : natural RANGE 0 TO 31;
  SIGNAL mac_rec_mem1_w,mac_rec_mem2_w : type_pvc_w;
  SIGNAL mac_rec_mem1_r,mac_rec_mem2_r : type_pvc_r;
  
  --------------------------------------
  -- Emission
  SIGNAL emi_spd : std_logic; -- 0=100MHz 1=10MHz
  SIGNAL emi_div : natural RANGE 0 TO 10;
  SIGNAL emi_len : unsigned(11 DOWNTO 0);
  SIGNAL emi_crcgen : std_logic;
  SIGNAL emi_c0,emi_c1,emi_c2 : std_logic;
  CONSTANT EMI_PREAMBLE : natural := 6;
  SIGNAL emi_cptpre : natural RANGE 0 TO EMI_PREAMBLE;
  SIGNAL emi_crc : uv32;
  CONSTANT EMI_DELAI_IFG : natural := 24;  -- 12 octets d'IFG
  SIGNAL emi_cptifg : natural RANGE 0 TO EMI_DELAI_IFG;
  SIGNAL emi_pos : unsigned(10 DOWNTO 0);
  TYPE enum_emi_state IS (sIDLE,sPREAMBLE0,sPREAMBLE1,sDATA,
                          sCRC0,sCRC1,sCRC2,sCRC3,sIFG);
  SIGNAL emi_state,emi_state_delai,emi_state_delai2 : enum_emi_state;
  SIGNAL emi_data : uv16;
  SIGNAL emi_stp,emi_busy : std_logic;
  SIGNAL emi_enp,emi_enp_pre2,emi_enp_pre : std_logic;
  SIGNAL emi_pop,emi_popx : std_logic;
  SIGNAL mac_emi_pop,mac_emi_pop_sync,mac_emi_pop_sync2 : std_logic;

  SIGNAL mac_emi_stp,mac_emi_stp_sync : std_logic;
  SIGNAL mac_emi_busy,mac_emi_busy_sync : std_logic;
  SIGNAL mac_emi_lev : natural RANGE 0 TO 64;
  SIGNAL mac_emi_cpt_in,mac_emi_cpt_out : natural RANGE 0 TO 63;
  SIGNAL mac_emi_mem1_w,mac_emi_mem2_w : type_pvc_w;
  SIGNAL mac_emi_mem1_r,mac_emi_mem2_r : type_pvc_r;
  
  SIGNAL phy_live : unsigned(5 DOWNTO 0);
  SIGNAL live : std_logic;
BEGIN

  phy_reset_na<='0' WHEN reset_n='0' ELSE '1' WHEN rising_edge(phy_rx_clk);
  
  --#######################################################################
  -- CLK
  ClkDetect:PROCESS (phy_rx_clk,phy_reset_na)
  BEGIN
    IF phy_reset_na='0' THEN
      phy_live<=(OTHERS =>'0');
    ELSIF rising_edge(phy_rx_clk) THEN
      phy_live<=phy_live(4 DOWNTO 0) & '1';
    END IF;
  END PROCESS ClkDetect;
  live<=phy_live(5) WHEN rising_edge(clk); -- <ASYNC>
  
  --#######################################################################
  -- RECEPTION
  Rec:PROCESS (phy_rx_clk, phy_reset_na)
    VARIABLE rec_filt_v : std_logic;
  BEGIN
    IF phy_reset_na = '0' THEN
      rec_state<=sIDLE;
      rec_len<=(OTHERS => '0');
      rec_c2<='0';
      rec_c1<='0';
      rec_c0<='0';
      rec_push<='0';
      rec_spd<='0'; -- 100Mbps default
      emi_spd<='0'; -- 100Mbps default
    ELSIF rising_edge(phy_rx_clk) THEN
      ------------------------------------------
      -- Bascules en entrée
      phy_rxd2<=phy_rxd(1 DOWNTO 0);
      phy_rx_dv2<=phy_rx_dv;
      
      IF rec_pulse='1' THEN
        phy_rx_dv3<=phy_rx_dv2;
        phy_rx_dv4<=phy_rx_dv3;
        phy_rx_dv5<=phy_rx_dv4;
        phy_rx_dv6<=phy_rx_dv5;
        phy_rx_dv7<=phy_rx_dv6;
        phy_rx_dv8<=phy_rx_dv7;
      END IF;
      
      ------------------------------------------
      -- Rate detect
      CASE rec_dstate IS
        WHEN sIDLE =>
          IF phy_rx_dv2='1' AND phy_rx_dv3='1' THEN
            rec_dstate<=sPRIM;
          END IF;
          rec_ref<=phy_rxd2;
          rec_dcpt<=0;
          rec_dcptmem<=9;
          
        WHEN sPRIM =>
          rec_ref<=phy_rxd2;
          IF phy_rx_dv2='0' THEN
            rec_dstate<=sIDLE;
          END IF;
          IF phy_rxd2/=rec_ref THEN
            rec_dstate<=sSUI;
          END IF;
          
        WHEN sSUI =>
          rec_ref<=phy_rxd2;
          IF rec_dcpt<8 THEN
            rec_dcpt<=rec_dcpt+1;
          END IF;
          IF phy_rxd2/=rec_ref THEN
            rec_dcpt<=0;
            IF rec_dcptmem>rec_dcpt THEN
              rec_dcptmem<=rec_dcpt;
            END IF;
          END IF;
          IF phy_rx_dv2='0' THEN
            rec_dstate<=sIDLE;
            IF rec_dcptmem<4 THEN
              rec_spd<='0'; -- 100MHz
              emi_spd<='0';
            ELSE
              rec_spd<='1';
              emi_spd<='1';
            END IF;
          END IF;    
      END CASE;
      
      phy_tx_er<=rec_spd;
      
      ------------------------------------------
      -- 10MHz / 100MHz
      IF rec_spd='0' THEN -- 100MHz
        rec_pulse<='1';
      ELSE
        IF rec_div=9 THEN
          rec_div<=0;
          rec_pulse<='1';
        ELSE
          rec_div<=rec_div+1;
          rec_pulse<='0';
        END IF;
      END IF;
      
      ------------------------------------------
      IF rec_pulse='1' THEN
        rec_c0<=NOT rec_c0;
        rec_c1<=rec_c1 XOR NOT rec_c0;
        rec_c2<=rec_c2 XOR (NOT rec_c1 AND NOT rec_c0);
      END IF;
      
      ------------------------------------------
      IF rec_pulse='1' THEN
        -- Données 16bits
        rec_data<=rec_data(1 DOWNTO 0) & rec_data(15 DOWNTO 10) &
                   phy_rxd2 & rec_data(7 DOWNTO 2);
        -- Longueur
        IF rec_state=sRECEIVE AND
          (phy_rx_dv3='1' OR phy_rx_dv2='1') AND rec_c0='0' AND rec_c1='0' THEN
          rec_len<=rec_len+1;
        ELSIF rec_state=sPREAMBLE THEN
          rec_len<=to_unsigned(1,12);
        END IF;
        
        IF rec_state=sRECEIVE AND (phy_rx_dv7='1' OR phy_rx_dv6='1') THEN
          rec_crc<=crc2(rec_data(15 DOWNTO 14),rec_crc);
        ELSIF rec_state=sPREAMBLE THEN
          rec_crc<=x"FFFFFFFF";
        END IF;
        
        -- CRC Hachage
        IF rec_len=6 THEN
          rec_dhash<=rec_crc(31 DOWNTO 26);
        END IF;
        
        IF phy_rx_dv7='0' AND phy_rx_dv8='1' THEN
          rec_dlen<=rec_len;
          rec_dcrcok<=to_std_logic(rec_crc=MAGIC);
        END IF;
      END IF;
      
      ------------------------------------------
      -- Machine à états
      IF rec_pulse='1' THEN
        CASE rec_state IS
          WHEN sIDLE =>
            IF rec_data(15 DOWNTO 14)="01" AND phy_rx_dv3='1' THEN
              rec_state<=sPREAMBLE;
            END IF;
            rec_error<='0';
            
          WHEN sPREAMBLE =>
            IF rec_data(15  DOWNTO 14)="11" AND phy_rx_dv3='1' THEN
              rec_state<=sRECEIVE;
            ELSIF rec_data(15  DOWNTO 14)/="01" OR phy_rx_dv3='0' THEN
              rec_state<=sIDLE;
            END IF;
            rec_c0<='0';
            rec_c1<='0';
            rec_c2<='0';
            
          WHEN sRECEIVE =>
            IF phy_rx_dv3='0' AND rec_c0='1' AND rec_c1='0' AND rec_c2='0' THEN
              rec_state<=sIDLE;
            END IF;
            -- <AFAIRE> Erreur Nibble, rx_er
        END CASE;
      END IF;
      
      ------------------------------------------
      -- Décalage
      IF rec_pulse='1' THEN
        IF rec_c2='1' AND rec_c1='0' AND rec_c0='1' THEN
          rec_data2<=rec_data;
          rec_data3<=rec_data2;
          rec_data4<=rec_data3;
          rec_srec<=to_std_logic(rec_state=sRECEIVE);
          rec_srec2<=rec_srec;
          rec_srec3<=rec_srec2;
        END IF;
        
        rec_filt_v:=rec_filt;
        IF rec_srec2='1' AND rec_srec3='0' AND rec_c2='1' THEN
          rec_filt_v:=to_std_logic(
            (rec_data(7 DOWNTO 0) & rec_data(15 DOWNTO 8) &
             rec_data2(7 DOWNTO 0) & rec_data2(15 DOWNTO 8) &
             rec_data3(7 DOWNTO 0) & rec_data3(15 DOWNTO 8))=mac_rec_w.padr
            OR rec_data3(15)='1');
        END IF;
        rec_filt<=rec_filt_v;
        
        rec_eof<=NOT rec_srec2 AND rec_srec3 AND rec_filt_v;
        
        IF rec_c0='1' AND rec_c1='1' AND rec_c2='1' AND
          rec_srec3='1' AND rec_filt_v='1' THEN
          -- On peut empiler la trame.
          rec_push<=NOT rec_push;
          rec_d_mem<=rec_data4;
          rec_eof_mem<=rec_eof;
        END IF;
      END IF;
    END IF;
  END PROCESS Rec;
  
  -------------------------------------------------------------------------
  -- Buffer réception
  -- 64 octets = 32 blocs de 16bits + EOF, encodés sur 32bits --> fifo 128octet
  rec_iram_dp: ENTITY work.iram_dp
    GENERIC MAP (N   => 7)
    PORT MAP (
      mem1_w    => mac_rec_mem1_w,
      mem1_r    => mac_rec_mem1_r,
      clk1      => clk,
      mem2_w    => mac_rec_mem2_w,
      mem2_r    => mac_rec_mem2_r,
      clk2      => clk);

  mac_rec_mem1_w.req<='1';
  mac_rec_mem1_w.be<="1111";
  mac_rec_mem1_w.wr<='1';
  mac_rec_mem1_w.a(6 DOWNTO 0)<=to_unsigned(mac_rec_cpt_in,5) & "00";
  mac_rec_mem1_w.a(31 DOWNTO 7)<=(OTHERS => '0');
  mac_rec_mem1_w.ah<=(OTHERS => '0');
  mac_rec_mem1_w.dw<="000000000000000" & rec_eof_mem & rec_d_mem;  -- <ASYNC>
  
  mac_rec_mem2_w.req<='1';
  mac_rec_mem2_w.be<="1111";
  mac_rec_mem2_w.wr<='0';
  mac_rec_mem2_w.a(6 DOWNTO 0)<=
    to_unsigned((mac_rec_cpt_out+1) MOD 32,5) & "00" WHEN mac_rec_w.pop='1' ELSE
    to_unsigned(mac_rec_cpt_out,5) & "00";
  mac_rec_mem2_w.a(31 DOWNTO 7)<=(OTHERS => '0');
  mac_rec_mem2_w.ah<=(OTHERS => '0');
  mac_rec_mem2_w.dw<=(OTHERS => '0');
  
  --  Buffers circulaires
  MAC_RecFIFO:PROCESS (clk)
  BEGIN
    IF rising_edge(clk) THEN
      mac_rec_push_sync<=rec_push;      -- <ASYNC>
      mac_rec_push_sync2<=mac_rec_push_sync;
      mac_rec_push<=mac_rec_push_sync XOR mac_rec_push_sync2;
      mac_rec_eof_sync<=rec_eof;
      mac_rec_eof_sync2<=mac_rec_eof_sync;
      
      IF mac_rec_push='1' THEN
        mac_rec_cpt_in<=(mac_rec_cpt_in+1) MOD 32;
      END IF;
      IF mac_rec_w.pop='1' THEN
        mac_rec_cpt_out<=(mac_rec_cpt_out+1) MOD 32;
      END IF;
      IF mac_rec_push='1' AND mac_rec_w.pop='0' THEN
        mac_rec_lev<=(mac_rec_lev+1) MOD 32;
      ELSIF mac_rec_push='0' AND mac_rec_w.pop='1' THEN
        mac_rec_lev<=(mac_rec_lev-1) MOD 32;
      END IF;
      mac_rec_fifordy<=to_std_logic(mac_rec_lev>8);

      mac_rec_eof<=mac_rec_eof_sync AND NOT mac_rec_eof_sync2;

      IF mac_rec_w.clr='1' OR reset_n='0' THEN
        mac_rec_lev<=0;
        mac_rec_cpt_in<=0;
        mac_rec_cpt_out<=0;
      END IF;
      
    END IF;
  END  PROCESS MAC_RecFIFO;
  
  -------------------------------------------------------------------------
  mac_rec_r.d       <=mac_rec_mem2_r.dr(15 DOWNTO 0);
  mac_rec_r.deof    <=mac_rec_mem2_r.dr(16) WHEN mac_rec_lev>0 ELSE '0';
  mac_rec_r.fifordy <=mac_rec_fifordy;
  mac_rec_r.len     <=rec_dlen;            -- <ASYNC>
  mac_rec_r.crcok   <=rec_dcrcok;          -- <ASYNC>
  mac_rec_r.eof     <=mac_rec_eof;
                                  
  --#######################################################################
  -- EMISSION
  
  Emi:PROCESS (phy_rx_clk, phy_reset_na)
    VARIABLE v16_v : uv16;
    VARIABLE v8_v : uv8;
    VARIABLE v4_v : uv4;
    VARIABLE v2_v,ss_v : uv2;
  BEGIN
    IF phy_reset_na = '0' THEN
      emi_state<=sIDLE;
      phy_tx_en<='0';
      emi_c2<='0';
      emi_c1<='0';
      emi_c0<='1';
      emi_popx<='0';
      emi_busy<='0';
    ELSIF rising_edge(phy_rx_clk) THEN
      ------------------------------------------
      -- Séquencement 8 cycles à 50MHz pour 16bits
      IF rec_pulse='1' THEN
        emi_c0<=NOT emi_c0;
        emi_c1<=emi_c1 XOR NOT emi_c0;
        emi_c2<=emi_c2 XOR (NOT emi_c1 AND NOT emi_c0);
        
        emi_state_delai<=emi_state;
        emi_state_delai2<=emi_state_delai;
      END IF;
      
      ------------------------------------------
      -- Compteurs
      IF emi_c0='1' AND emi_c1='1' AND rec_pulse='1' THEN
        IF emi_state=sDATA THEN
          emi_pos<=emi_pos+1;
        ELSIF emi_state=sIDLE THEN
          emi_pos<=(OTHERS =>'0');
        END IF;
        IF emi_state=sPREAMBLE0 THEN
          emi_cptpre<=emi_cptpre+1;
        ELSE
          emi_cptpre<=0;
        END IF;
        IF emi_state=sIFG THEN
          emi_cptifg<=emi_cptifg+1;
        ELSE
          emi_cptifg<=0;
        END IF;
      END IF;
      
      ------------------------------------------
      IF rec_pulse='1' THEN
        IF emi_c0='0' AND emi_c1='1' AND emi_c2='1' THEN
          -- <ASYNCHRONES> Mais signaux stables...
          IF emi_state=sDATA THEN
            emi_data<=mac_emi_mem2_r.dr(15 DOWNTO 0);
          END IF;
          emi_stp<=mac_emi_stp_sync;
        END IF;
        
        -- Dépile FIFO
        IF emi_c0='0' AND emi_c1='1' AND emi_c2='1' AND emi_state=sDATA THEN
          emi_popx<=NOT emi_popx;
        END IF;
      END IF;
      
      ------------------------------------------
      -- Données
      -- IEEE 802.3 §3.3 : Order of bit transmission : Each octet of the MAC
      -- frame,with the exception of the FCS,is transmitted low-order bit first.
      IF rec_pulse='1' THEN
        IF emi_state_delai=sCRC0 OR emi_state_delai=sCRC1 THEN
          v16_v:=NOT(emi_crc(24) & emi_crc(25) & emi_crc(26) & emi_crc(27) &
                     emi_crc(28) & emi_crc(29) & emi_crc(30) & emi_crc(31) &
                     emi_crc(16) & emi_crc(17) & emi_crc(18) & emi_crc(19) & 
                     emi_crc(20) & emi_crc(21) & emi_crc(22) & emi_crc(23));
        ELSIF emi_state_delai=sCRC2 OR emi_state_delai=sCRC3 THEN
          v16_v:=NOT(emi_crc(8)  & emi_crc(9)  & emi_crc(10) & emi_crc(11) &
                     emi_crc(12) & emi_crc(13) & emi_crc(14) & emi_crc(15) &
                     emi_crc(0)  & emi_crc(1)  & emi_crc(2)  & emi_crc(3)  &
                     emi_crc(4)  & emi_crc(5)  & emi_crc(6)  & emi_crc(7));
        ELSIF emi_state_delai=sDATA THEN
          v16_v:=emi_data;
        ELSIF emi_state_delai=sPREAMBLE1 THEN
          v16_v:=x"55D5"; --01 01 | 01 01 | 11 01 | 01 01
        ELSE
          v16_v:=x"5555";
        END IF;
        
        IF emi_state_delai=sCRC0 OR emi_state_delai=sCRC2 THEN
          v8_v:=v16_v(15 DOWNTO 8);
        ELSIF emi_state_delai=sCRC1 OR emi_state_delai=sCRC3 THEN
          v8_v:=v16_v(7 DOWNTO 0);
        ELSE
          v8_v:=mux(NOT (emi_c1 XOR emi_c2),
                    v16_v(7 DOWNTO 0),v16_v(15 DOWNTO 8));
        END IF;
        
        v4_v:=mux(NOT emi_c1,v8_v(3 DOWNTO 0),v8_v(7 DOWNTO 4));
        v2_v:=mux(emi_c0,v4_v(1 DOWNTO 0),v4_v(3 DOWNTO 2));
        
        -- CRC
        IF emi_state=sIDLE THEN
          emi_crc<=x"FFFFFFFF";
        ELSIF emi_state_delai=sDATA THEN
          emi_crc<=crc2(v2_v,emi_crc);
        END IF;
        
        -- PHY
        IF emi_state_delai/=sIDLE AND emi_state_delai/=sIFG THEN
          phy_txd<="00" & v2_v;
          phy_tx_en<='1';
        ELSE
          phy_txd<="0000";
          phy_tx_en<='0';
        END IF;
        
      END IF;

      emi_len<=mac_emi_w.len;           -- <ASYNC>
      emi_crcgen<=mac_emi_w.crcgen;     -- <ASYNC>
      emi_enp_pre2<=mac_emi_w.enp;      -- <ASYNC>
      emi_enp_pre<=emi_enp_pre2;
      emi_enp<=emi_enp_pre;
      
      ------------------------------------------
      -- Machine à états
      IF emi_c0='1' AND emi_c1='1' AND rec_pulse='1' THEN
        CASE emi_state IS
          WHEN sIDLE =>
            IF emi_c2='1' THEN
              IF emi_stp='1' THEN
                emi_state<=sPREAMBLE0;
              END IF;
            END IF;
            
          WHEN sPREAMBLE0 =>
            IF emi_c2='1' THEN
              IF emi_cptpre=EMI_PREAMBLE-1 THEN
                emi_state<=sPREAMBLE1;
              END IF;
            END IF;
            
          WHEN sPREAMBLE1 =>
            IF emi_c2='1' THEN
              emi_state<=sDATA;
            END IF;
            
          WHEN sDATA =>
            IF emi_pos=emi_len-1 AND emi_enp='1' THEN
              IF emi_crcgen='1' THEN
                emi_state<=sCRC0;
              ELSE
                emi_state<=sIFG;
              END IF;
            END IF;
            
          WHEN sCRC0 =>
            emi_state<=sCRC1;
            
          WHEN sCRC1 =>
            emi_state<=sCRC2;
            
          WHEN sCRC2 =>
            emi_state<=sCRC3;
            
          WHEN sCRC3 =>
            emi_state<=sIFG;
            
          WHEN sIFG =>
            emi_c2<='1';
            IF emi_cptifg=EMI_DELAI_IFG-1 THEN
              emi_state<=sIDLE;
            END IF;
            
        END CASE;
      END IF;

      emi_busy<=to_std_logic(emi_state/=sIDLE);
    END IF;
  END PROCESS Emi;
  
  -------------------------------------------------------------------------
  -- Buffer émission
  -- 128 octets = 64 blocs de 16bits + SOF, encodés sur 32bits --> fifo 256octet
  emi_iram_dp: ENTITY work.iram_dp
    GENERIC MAP (N   => 8)
    PORT MAP (
      mem1_w    => mac_emi_mem1_w,
      mem1_r    => mac_emi_mem1_r,
      clk1      => clk,
      mem2_w    => mac_emi_mem2_w,
      mem2_r    => mac_emi_mem2_r,
      clk2      => clk);
  
  ---------------------------------
  mac_emi_mem1_w.req<='1';
  mac_emi_mem1_w.be<="1111";
  mac_emi_mem1_w.wr<='1';
  mac_emi_mem1_w.a(7 DOWNTO 0)<=to_unsigned(mac_emi_cpt_in,6) & "00";
  mac_emi_mem1_w.a(31 DOWNTO 8)<=(OTHERS => '0');
  mac_emi_mem1_w.ah<=(OTHERS => '0');
  mac_emi_mem1_w.dw<="000000000000000" & mac_emi_w.stp & mac_emi_w.d;
  
  mac_emi_mem2_w.req<='1';
  mac_emi_mem2_w.be<="1111";
  mac_emi_mem2_w.wr<='0';
  mac_emi_mem2_w.a(7 DOWNTO 0)<=to_unsigned(mac_emi_cpt_out,6) & "00";
  mac_emi_mem2_w.a(31 DOWNTO 8)<=(OTHERS => '0');
  mac_emi_mem2_w.ah<=(OTHERS => '0');
  mac_emi_mem2_w.dw<=(OTHERS => '0');
  
  ---------------------------------  
  --  Buffers circulaires
  MAC_EmiFIFO:PROCESS (clk)
    VARIABLE pop_v : std_logic;
  BEGIN
    IF rising_edge(clk) THEN
      mac_emi_pop_sync<=emi_popx;      -- <ASYNC>
      mac_emi_pop_sync2<=mac_emi_pop_sync;
      pop_v:=mac_emi_pop_sync XOR mac_emi_pop_sync2;
      mac_emi_busy_sync<=emi_busy;      -- <ASYNC>
      mac_emi_busy<=mac_emi_busy_sync;
      IF mac_emi_lev=0 THEN
        pop_v:='0';
      END IF;
      IF pop_v='1' AND mac_emi_lev/=0 THEN
        mac_emi_cpt_out<=(mac_emi_cpt_out+1) MOD 64;
      END IF;
      IF mac_emi_w.push='1' THEN
        mac_emi_cpt_in<=(mac_emi_cpt_in+1) MOD 64;
      END IF;
      IF mac_emi_w.push='1' AND pop_v='0' THEN
        mac_emi_lev<=mac_emi_lev+1;
      ELSIF mac_emi_w.push='0' AND (pop_v='1' AND mac_emi_lev/=0) THEN
        mac_emi_lev<=mac_emi_lev-1;
      END IF;
      mac_emi_r.fifordy<=to_std_logic(mac_emi_lev<56) OR NOT live;
      IF mac_emi_w.clr='1' OR (mac_emi_busy='1' AND mac_emi_busy_sync='0') THEN
        mac_emi_lev<=0;
        mac_emi_cpt_in<=0;
        mac_emi_cpt_out<=0;
      END IF;
      mac_emi_stp<=(mac_emi_stp OR mac_emi_w.stp) AND NOT mac_emi_busy;
      mac_emi_stp_sync<=mac_emi_stp AND to_std_logic(mac_emi_lev>=24);
      
      mac_emi_r.busy     <=mac_emi_busy;

      IF reset_n = '0' THEN
        mac_emi_lev<=0;
        mac_emi_cpt_in<=0;
        mac_emi_cpt_out<=0;
        mac_emi_stp<='0';
        mac_emi_busy_sync<='0';
      END IF;

    END IF;
  END PROCESS MAC_EmiFIFO;
  
  -------------------------------------------------------------------------
  phy_reset_n<='1';
  
END ARCHITECTURE rmii;
