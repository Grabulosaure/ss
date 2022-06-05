----*-vhdl-*--------------------------------------------------------------------
-- TEM : TS
-- Ethernet Lance
--------------------------------------------------------------------------------
-- DO 10/2010
--------------------------------------------------------------------------------
-- AMD Lance
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

-- Hypothèses :
--  - Pas de chaînage de paquets en réception.
--  - Chaînage de paquets possible en émission si
--     taille buffers multiple de 16bits
--  - Alignement des buffers sur 16bits (Datasheet : 8bits)
--  - Alignement du 'initialisation block' sur 32bits (Datasheet : 16bits)
--  - Interface full duplex, pas de collision, pas de répétition de trames...
--  - Les ring pointers tdra, rdra sont alignés sur 64bits, dans le même burst

-- En réception, on mémorise le CRC
-- En émission, le CRC est généré automatiquement

-- 0 : Data register
-- 2 : Address register

--------------------------------------
-- Control/Status register 0

-- 15 : ERR  : Error summary : BABL+CERR+MISS+MERR
-- 14 : BABL : Babble =0 <non>
-- 13 : CERR : Collision =0 <non>
-- 12 : MISS : Missed Packet
-- 11 : MERR : Memory Error = 0 <non>
-- 10 : RINT : Receiver Interrupt
--  9 : TINT : Transmitter Interrupt
--  8 : IDON : Initialisaiton Done
--  7 : INTR : Interrupt : BABL + MISS + MERR + RINT + TINT + IDON
--  6 : INEA : Interrupt Enable
--  5 : RXON : Receiver ON
--  4 : TXON : Transmitter ON
--  3 : TDMD : Transmit Demand
--  2 : STOP : Stop
--  1 : STRT : Start
--  0 : INIT : Initialize

-- Control/Status register 1
--  15:1 : IADR[15:1]

-- Control/Status register 2
--   7:0 : IADR[23:16]

-- Control/Status register 3
--   0 : BCON : Byte Control = ? <non>
--   1 : ACON : ALE Control = ? <non>
--   2 : BSWP : Byte Swap. =1 Activé pour Sparc (big Endian)

--------------------------------------
-- Receive Message Descriptors

-- 0 : RMD01
--    31:16: ADR[15:0]
--       15: OWN  : 0=Host, 1=LANCE
--       14: ERR  : FRAM + OFLO + CRC + BUFF
--       13: FRAM : Framing Error <non=0>
--       12: OFLO : Overflow <non=0>
--       11: CRC  : CRC Error
--       10: BUFF : Buffer Error, pas de buffer dispo
--        9: STP  : Start of Packet =1 <pas de frag>
--        8: ENP  : End of Packet =1 <pas de frag>
--      7:0: ADR[23:16]

-- 4 : RMD23
--    31:28 : =1111
--    27:16 : BCNT : Buffer Byte Count (neg.)
--    15:12 : =0000
--    11:0  : MCNT : Message Byte Count (Avec le CRC)

--------------------------------------
-- Transmit Message Descriptor

-- 0 : TMD01
--    31:16 : ADR[15:0]
--       15 : OWN  : 0=Host, 1=LANCE
--       14 : ERR  : LCOL+LCAR+UFLO+RTRY = 0
--       13 : ADD_FCS : Ajout CRC
--       12 : MORE : =0
--       11 : ONE  : =0
--       10 : DEF  : =0
--        9 : STP  : Start of Packet
--        8 : ENP  : End of Packet
--      7:0 : ADR[23:16]

-- 4 : TMD23
--    31:28 : =1111
--    27:16 : BCNT : Buffer Byte Count (negatif, sans le CRC)
--       15 : BUFF : Buffer Error = 0
--       14 : UFLO : Underflow = 0
--       13 : Reserved=0
--       12 : LCOL : =0 <non>
--       11 : LCAR : =0 <non>
--       10 : RTRY : =0 <non>
--      9:0 : TDR  : =0 <non>

--------------------------------------
-- Initialisation block

-- 0 : INIT01 : MODE / PADR[15:0]
--       31 : PROM : Promiscuous
--    30:24 : Réservé
--       23 : EMBA : Enable Modified Backoff <non>
--       22 : INTL : Internal Loopback
--       21 : DRTY : Disable Retry <non>
--       20 : COLL : Force collision <non>
--       19 : DTCR : Disable Transmit CRC
--       18 : LOOP : Loopback
--       17 : DTX  : Disable Transmitter
--       16 : DRX  : Disable Receiver
--     15:0 : PADR[15:0]

-- 4 : INIT23 : PADR
--    31:16 : PADR[31:16]
--     15:0 : PADR[47:32]

-- 8 : INIT45 : LADRF
--    31:16 : LADRF[15:0]
--     15:0 : LADRF[31:16]

-- C : INIT67 : LADRF 
--    31:16 : LADRF[47:32]
--     15:0 : LADRF[63:48]

--10 : INIT89 : RDRA / RLEN
--    31:19 : RDRA[15:3]
--    18:16 : 000 (alignement RDRA)
--    15:13 : RLEN : Receive Ring Length 1...128
--     12:8 : Réservé
--      7:0 : RDRA[23:16]

--14 : INITAB : TDRA / TLEN
--    31:19 : TDRA[15:3]
--    18:16 : 000 (alignement TDRA)
--    15:13 : TLEN : Transmit Ring Length 1...128
--     12:8 : Réservé
--      7:0 : TDRA[23:16]

--------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.plomb_pack.ALL;
USE work.ts_pack.ALL;

ENTITY ts_lance IS
  GENERIC (
    BURSTLEN   : natural := 4;
    ASI        : uv8);
  PORT (
    sel        : IN  std_logic;
    w          : IN  type_pvc_w;
    r          : OUT type_pvc_r;
    
    pw         : OUT type_plomb_w;
    pr         : IN  type_plomb_r;

    mac_emi_w  : OUT type_mac_emi_w;
    mac_emi_r  : IN  type_mac_emi_r;
    mac_rec_w  : OUT type_mac_rec_w;
    mac_rec_r  : IN  type_mac_rec_r;

    int        : OUT std_logic;
    eth_ba     : IN  uv8;    -- Poids forts adresses Ethernet
    stopa      : IN  std_logic;
    
    -- Global
    clk        : IN std_logic;
    reset      : IN std_logic;
    reset_n    : IN std_logic
    );
END ENTITY ts_lance;

--##############################################################################

ARCHITECTURE rtl OF ts_lance IS

  CONSTANT C0 : uv32 := (OTHERS =>'0');
  CONSTANT C1 : uv32 := (OTHERS =>'1');
  
  -- Registres
  SIGNAL dr : uv32;
  
  SIGNAL rap : unsigned(1 DOWNTO 0);    -- Register Address Port
  SIGNAL iadr : unsigned(23 DOWNTO 1);  -- Initialisation Address
  SIGNAL bswp : std_logic;              -- CSR3.BSWP : Bus Swap
  
  SIGNAL init,strt,stop : std_logic;    -- Initialize / Start / Stop
  SIGNAL tdmd,tdmd_cpt_set,tdmd_clr : std_logic;  -- Transmit Demand
  SIGNAL inea : std_logic;              -- Interrupt Enable
  SIGNAL idon,idon_set : std_logic;     -- Initialisation done
  SIGNAL tint,rint,miss : std_logic; -- Transmit / Receive Int. / Missed packet
  SIGNAL tint_set,rint_set,miss_set : std_logic;
  -- Plomb
  CONSTANT N_LINE : natural := ilog2(BURSTLEN);
  
  SIGNAL pw_i : type_plomb_w;
  
  TYPE type_fifo IS RECORD
    d   : uv32;
    be  : uv0_3;
  END RECORD;
  TYPE arr_fifo IS ARRAY(natural RANGE <>) OF type_fifo;
  SIGNAL dma_fifo  : arr_fifo(0 TO BURSTLEN-1);
  SIGNAL dma_fifo_o : type_fifo;
  SIGNAL fifo_ali : unsigned(N_LINE+1 DOWNTO 2);
  SIGNAL fifo_lev : natural RANGE 0 TO BURSTLEN-1;
  SIGNAL mic_dw : uv32;
  SIGNAL mic_be : uv0_3;
  
  SIGNAL dma_a : unsigned(23 DOWNTO 0);
  SIGNAL dma_rd,dma_wr,dma_busy : std_logic;
  SIGNAL dma_rw : std_logic;
  SIGNAL dma_ra : unsigned(N_LINE-1 DOWNTO 0);
  SIGNAL dma_rdok : std_logic;

  SIGNAL rec_eof,rec_eof_clr : std_logic;
  
  -- Compteur de scrutation émissions
  CONSTANT PERIODE_TXCPT : natural := 100000;  -- Période de scrutation émission
--  CONSTANT PERIODE_TXCPT : natural := 10000000;
  SIGNAL tx_cpt : natural RANGE 0 TO PERIODE_TXCPT;

  -- Variables INIT
  SIGNAL init_pulse,init_pend : std_logic;
  SIGNAL initvec : unsigned(24*8-1 DOWNTO 0);  -- 192 bits
  -- INIT0 :  PADR[15:0]       MODE
  -- INIT1 :  PADR[47:32]      PADR[31:16]
  ALIAS prom  : std_logic             IS initvec(15);
  ALIAS dtcr  : std_logic             IS initvec( 3);
  ALIAS lopo  : std_logic             IS initvec( 2);
  ALIAS dtx   : std_logic             IS initvec( 1);
  ALIAS drx   : std_logic             IS initvec( 0);
  ALIAS padr  : unsigned(47 DOWNTO 0) IS initvec(    63 DOWNTO     16);
  -- INIT2 :  LADRF[31:16]     LADRF[15:0]
  -- INIT3 :  LADRF[63:48]     LADRF[47:32]
  ALIAS ladrf : unsigned(63 DOWNTO 0) IS initvec(   127 DOWNTO     64);
  -- INIT4 :  RLEN[2:0]    RDRA[23:3]
  ALIAS rdra  : unsigned(23 DOWNTO 3) IS initvec(128+23 DOWNTO 128+ 3);
  ALIAS rlen  : unsigned( 2 DOWNTO 0) IS initvec(128+31 DOWNTO 128+29);
  -- INIT5 :  TLEN[2:0]    TDRA[23:3]
  ALIAS tdra  : unsigned(23 DOWNTO 3) IS initvec(160+23 DOWNTO 160+ 3);
  ALIAS tlen  : unsigned( 2 DOWNTO 0) IS initvec(160+31 DOWNTO 160+29);

  -- Comptage descripteurs TX / RX
  SIGNAL rmd_cpt,tmd_cpt : unsigned(6 DOWNTO 0);  -- Compteurs Rec/Trans
  FUNCTION inc (
    CONSTANT cpt : unsigned(6 DOWNTO 0);
    CONSTANT len : unsigned(2 DOWNTO 0)) RETURN unsigned IS
    VARIABLE v : unsigned(6 DOWNTO 0);
  BEGIN
    v:=cpt+1;
    CASE len IS
      WHEN "000"  => v:="0000000";
      WHEN "001"  => v(6 DOWNTO 1) :="000000";
      WHEN "010"  => v(6 DOWNTO 2) :="00000";
      WHEN "011"  => v(6 DOWNTO 3) :="0000";
      WHEN "100"  => v(6 DOWNTO 4) :="000";
      WHEN "101"  => v(6 DOWNTO 5) :="00";
      WHEN "110"  => v(6) :='0';
      WHEN OTHERS => NULL;
    END CASE;
    RETURN v;
  END FUNCTION inc;

  SIGNAL rxon,txon,rsel : std_logic;
  SIGNAL err_buf : std_logic :='0';       -- <AFAIRE> Indéfini
  ---------------------------------------------------------
  SIGNAL rmd : uv64;
  -- RMD0(15:0) : RX : Low Buffer Address
  -- RMD1(7:0)  : RX : High Buffer Address
  ALIAS rmd_adr : unsigned(23 DOWNTO 0) IS rmd(23 DOWNTO 0);
  -- RMD1(15) : OWN
  ALIAS rmd_own : std_logic IS rmd(31);
  
  -- RMD2(11:0) : RX : Buffer Byte Count : Nombre d'octets dispo dans le buffer
  ALIAS rmd_bcnt : unsigned(11 DOWNTO 0) IS rmd(43 DOWNTO 32);
  SIGNAL radr : unsigned(23 DOWNTO 0);
  SIGNAL rx_act,rec_deof : std_logic;
  SIGNAL loop_co : std_logic;
  SIGNAL rec_skip : std_logic;
  SIGNAL rdma  : unsigned(23 DOWNTO 0);
  ---------------------------------------------------------
  SIGNAL tmd : uv64;
  -- TMD0(15:0) : TX : Low Buffer Address
  -- TMD1(7:0)  : TX : High Buffer Address
  ALIAS tmd_adr : unsigned(23 DOWNTO 0) IS tmd(23 DOWNTO 0);
  
  -- TMD1(13)   : TX : ADD_FCS : Add CRC, override disable Transmit CRC
  ALIAS tmd_add_fcs : std_logic IS tmd(29);
  
  -- TMD1(15) : OWN
  ALIAS tmd_own : std_logic IS tmd(31);
  
  -- TMD1(9)  : STP
  ALIAS tmd_stp : std_logic IS tmd(25);
  
  -- TMD1(8)  : ENP
  ALIAS tmd_enp : std_logic IS tmd(24);
  
  -- TMD2(11:0) : TX : Buffer Byte Count : Taille du message à envoyer
  ALIAS tmd_bcnt : unsigned(11 DOWNTO 0) IS tmd(43 DOWNTO 32);

  SIGNAL tcpt,tx_len : unsigned(11 DOWNTO 0);
  SIGNAL tx_act,tx_stp,tx_enp : std_logic;
  ---------------------------------------------------------
  -- Compteurs sur 2^12 octets = 4096 octets max par message ?
  
  SIGNAL pc : uint6;
  SIGNAL prim : std_logic;

  -- DMA READ / DMA WRITE
  CONSTANT IADR_00              : uint6 :=0;
  CONSTANT IADR_04              : uint6 :=1;
  CONSTANT IADR_08              : uint6 :=2;
  CONSTANT IADR_0C              : uint6 :=3;
  CONSTANT IADR_10              : uint6 :=4;
  CONSTANT IADR_14              : uint6 :=5;
  CONSTANT REC_DESC             : uint6 :=9;
  CONSTANT EMI_DESC             : uint6 :=10;
  CONSTANT PTR                  : uint6 :=12;
  
  CONSTANT L_INIT               : uint6 :=0;
  CONSTANT L_RMD                : uint6 :=1;
  CONSTANT L_TMD                : uint6 :=2;
  CONSTANT L_ALIGN              : uint6 :=3;
  
  CONSTANT RMD_MAJ              : uint6 :=0;
  CONSTANT TMD_MAJ              : uint6 :=1;
  CONSTANT SET_TXACT            : uint6 :=2;
  CONSTANT CLR_TXACT            : uint6 :=3;
  CONSTANT CLR_RXACT            : uint6 :=4;
  CONSTANT EMI_CLRTDMD          : uint6 :=5;
  CONSTANT INIT_END             : uint6 :=6;
  CONSTANT REC_RADR_RXACT       : uint6 :=7;
  CONSTANT MAJ_ADR_SKIP         : uint6 :=8;
  CONSTANT DMA_FLUSH            : uint6 :=9;
  
  -- On insère le microcode ici
  % MICROCODE
  
BEGIN
  
  ------------------------------------------------------------------------------
  -- Accès registres
  Regs: PROCESS (clk)
    VARIABLE intr_v : std_logic;
    VARIABLE rap_v : unsigned(1 DOWNTO 0);
    VARIABLE rap16_v : uv16;
    VARIABLE tdmd_set_v,idon_clr_v : std_logic;
    VARIABLE init_set_v,strt_set_v,stop_set_v : std_logic;
    VARIABLE tint_clr_v,rint_clr_v,miss_clr_v : std_logic;
  BEGIN
    IF rising_edge(clk) THEN
      -- Interruption
      intr_v:=miss OR rint OR tint OR idon;
      int <=inea AND intr_v;
      
      --------------------------------------
      rap_v:=rap;
      IF rsel='1' AND w.be(3)='1' AND w.wr='1' THEN
        -- Ecriture Adress Port
        rap<=w.dw(1 DOWNTO 0);
        rap_v:=w.dw(1 DOWNTO 0);
      END IF;
      init_set_v:='0';
      strt_set_v:='0';
      stop_set_v:='0';
      tdmd_set_v:='0';
      idon_clr_v:='0';
      tint_clr_v:='0';
      rint_clr_v:='0';
      miss_clr_v:='0';
      IF rsel='1' AND w.be(0 TO 1)="11" AND w.wr='1' THEN
        -- Ecriture Data Port
        CASE rap_v IS
          WHEN "00" =>                  -- CSR0
            init_set_v:=w.dw(16);
            strt_set_v:=w.dw(17);
            stop_set_v:=w.dw(18);
            tdmd_set_v:=w.dw(19);
            inea<=w.dw(22) AND NOT w.dw(18);
            idon_clr_v:=w.dw(24);
            tint_clr_v:=w.dw(25);
            rint_clr_v:=w.dw(26);
            miss_clr_v:=w.dw(28);
          WHEN "01" =>                  -- CSR1
            iadr(15 DOWNTO 1) <=w.dw(31 DOWNTO 17);
          WHEN "10" =>                  -- CSR2
            iadr(23 DOWNTO 16)<=w.dw(23 DOWNTO 16);
--          WHEN "11" =>                -- CSR3
          WHEN OTHERS =>
            bswp<=w.dw(18);
            
        END CASE;
      END IF;
      rap16_v:="00000000000000" & rap_v;
      CASE rap_v IS
        WHEN "00" =>                    -- CSR0
          dr<=miss & "00" & miss & '0' & rint & tint & idon &
               intr_v & inea & rxon & txon & '0' & stop & strt & init &
               rap16_v;
        WHEN "01" =>                    -- CSR1
          dr<=iadr(15 DOWNTO 1) & '0' &
               rap16_v;
        WHEN "10" =>                    -- CSR2
          dr<="00000000" & iadr(23 DOWNTO 16) &
               rap16_v;
--        WHEN "11" =>                    -- CSR3
        WHEN OTHERS =>
          dr<="0000000000000" & bswp & "00" &
               rap16_v;
          dr(31 DOWNTO 20)<=to_unsigned(pc,6) & dma_wr & dma_rd & 
                          mac_emi_r.busy &  mac_emi_r.fifordy & tx_act & tdmd;
          
      END CASE;
      
      --------------------------------------
      -- INIT : Initialise, STRT : Start, STOP : Stop
      IF stop_set_v='1' THEN
        init<='0';
        strt<='0';
        stop<='1';
        tint_clr_v:='1';
        rint_clr_v:='1';
        miss_clr_v:='1';
        txon<='0';
        rxon<='0';
      ELSIF init_set_v='1' AND stop='1' THEN
        init<='1';
        strt<='0';
        stop<='0';
        tint_clr_v:='1';
        rint_clr_v:='1';
        miss_clr_v:='1';
      ELSIF strt_set_v='1' AND (stop='1' OR init='1') THEN
        init<='0';
        strt<='1';
        stop<='0';
        txon<=NOT dtx;
        rxon<=NOT drx;
      END IF;
      
      init_pulse<=init_set_v;
      
      -- TDMD : Transmit Demand
      tdmd<=(tdmd_set_v OR tdmd_cpt_set) OR (tdmd AND NOT tdmd_clr);

      -- IDON : Initialisation done
      idon<=idon_set OR (idon AND NOT idon_clr_v);
      
      -- TXON : Transmiter On, RXON : Receiver ON
      -- dépend du bloc d'initialisation
      
      -- INEA : Interrupt Enable.
      -- fixé plus haut
      
      -- TINT : Transmitter Interrupt, RINT : Receiver Interrupt
      -- MISS : Missed Packet (receive ring full)
      tint<=tint_set OR (tint AND NOT tint_clr_v);
      rint<=rint_set OR (rint AND NOT rint_clr_v);
      miss<=miss_set OR (miss AND NOT miss_clr_v);
      
      -- RESET Synchrone
      IF reset='1' THEN
        rap<="00";
        rint<='0';
        tint<='0';
        idon<='0';
        inea<='0';
        stop<='1';
        strt<='0';
        init<='0';
      END IF;
      IF reset_n='0' THEN
        rap<="00";
        rint<='0';
        tint<='0';
        idon<='0';
        inea<='0';
        stop<='1';
        strt<='0';
        init<='0';
        init_pulse<='0';
        txon<='0';
        rxon<='0';
        miss<='0';
        tdmd<='0';
      END IF;
    END IF;    
  END PROCESS Regs;
  
  rsel<=w.req AND sel;  
  
  -- Relectures registres
  R_Gen:PROCESS(dr,sel)
  BEGIN
    r.ack<=sel;
    r.dr<=dr;
  END PROCESS R_Gen;
  
  ------------------------------------------------------------------------------
  -- Microcode
 
  -- label    OPERATION           PARM/label
  ----------------------------------
  -- Boucle d'attente
  %0:
  %debut:     IF_DODO             0
  %           IF_TX_FIFO_EMPTY    tx_empty
  %           IF_RX_EVENT         rx_event
  %           IF_TX_NEW           tx_new
  %           IF_INIT             init
  %           GOTO                debut
  
  ----------------------------------
  -- Initialisation    
  -- - Charge registres init
  -- - On charge par mots de 32bits, car on ne connait pas vraiment l'alignement
  %init:      DMA_READ            IADR_00
  %           LOAD                L_INIT  -- INIT0 : MODE / PADR[15:0]
  %           OP                  DMA_FLUSH
  %           DMA_READ            IADR_04
  %           LOAD                L_INIT  -- INIT1 : PADR[31:16] / PADR[47:32]
  %           OP                  DMA_FLUSH
  %           DMA_READ            IADR_08
  %           LOAD                L_INIT  -- INIT2 : LADRF[15:0] / LADRF[31:16]
  %           OP                  DMA_FLUSH
  %           DMA_READ            IADR_0C
  %           LOAD                L_INIT  -- INIT3 : LADRF[47:32] / LADRF[63:48]
  %           OP                  DMA_FLUSH
  %           DMA_READ            IADR_10
  %           LOAD                L_INIT  -- INIT4 : RDRA[15:0] / RLEN
  %           OP                  DMA_FLUSH
  %           DMA_READ            IADR_14
  %           LOAD                L_INIT  -- INIT5 : TDRA[15:0] / TLEN
  %           OP                  DMA_FLUSH
  %           OP                  INIT_END
  %           GOTO                debut
    
  ----------------------------------
  -- RX : FIFO réception pleine
  -- - Si nouveau transfert
  --    - Chargement descripteur
  --    - Marque RX_act=1
  -- - Dépile / copie

  %rx_event:  IF_RXACT_SET        rec_copie  -- (26)
  %           DMA_READ            REC_DESC   -- Lecture rdra(rmd_cpt)
  %           LOAD                L_RMD      -- MD0=BURST[0] : RMD0, RMD1
  %           LOAD                L_RMD      -- MD1=BURST[1] : RMD2, RMD3
  %           OP                  MAJ_ADR_SKIP --(30)Si OWN=0, pas de buffer
  %rec_copie: OP                  DMA_FLUSH
  %           OP                  REC_RADR_RXACT -- RXACT=1
  %           LOOP_STORE          0          -- (33)Boucle de copie
  %           DMA_WRITE           PTR        -- Ecriture burst
  %           RADR_IF_NOT_RXEOF   debut      -- Test fin de trame
  %           OP                  RMD_MAJ    -- Mise à jour RMD, incrément
  %           OP                  DMA_FLUSH
  %           STORE               L_RMD      -- BURST[0] = RMD0
  %           STORE               L_RMD      -- BURST[1] = RMD1
  %           STORE               L_ALIGN
  %           DMA_WRITE           REC_DESC   -- Ecriture rdra(rmd_cpt)
  %           OP                  CLR_RXACT  -- RXACT=0
  %           GOTO                debut
  
  ----------------------------------
  -- TX : Nouvelle trame (44)
  %tx_new:
  -- - Charge descripteur
  -- - TX_act=1
  -- - Copie / Empile
  %           DMA_READ            EMI_DESC   -- Lecture tdra(rmd_cpt)
  %           OP                  EMI_CLRTDMD
  %           LOAD                L_TMD      -- MD0=BURST[0] : RMD0, RMD1
  %           LOAD                L_TMD      -- MD1=BURST[1] : RMD2, RMD3
  %           IF_TMD_OWN0         debut      -- Si OWN=0, rien à émettre
  %           OP                  SET_TXACT
  %tx_empty: -- TX : FIFO vide (50)
  -- - Copie / Empile
  -- - Si fin de trame : TX_act=0, Mise à jour descripteur
  %           DMA_READ            PTR
  %           LOOP_LOAD           0
  %           IF_NOT_TXEND        debut
  %           OP                  TMD_MAJ    -- Mise à jour TMD   incrément
  %           OP                  DMA_FLUSH
  %           STORE               L_TMD      -- BURST[0] = MD0
  %           STORE               L_TMD      -- BURST[1] = MD1
  %           STORE               L_ALIGN
  %           DMA_WRITE           EMI_DESC   -- Ecriture tdra(tmd_cpt)
  %           OP                  CLR_TXACT
  %           GOTO                debut
  
  --------------------------------------------------------------------
  Proc:PROCESS(clk)
    VARIABLE saut_v,loop_v : boolean;
    VARIABLE act_init_v,act_tx_new_v,act_tx_empty_v : boolean;
    VARIABLE act_rx_event_v : boolean;
    VARIABLE dma_a_v : unsigned(23 DOWNTO 0);
    VARIABLE dma_rw_v : std_logic;
    VARIABLE tcnt_neg_v : unsigned(11 DOWNTO 0);
    VARIABLE op_v  : enum_code;
    VARIABLE val_v : uint6;
    VARIABLE fifo_i_v : type_fifo;
    VARIABLE fifo_push_v,fifo_pop_v,fifo_flush_v : std_logic;
    VARIABLE ali_inc_v,ali_clr_v : std_logic;
    VARIABLE mic_pop_v,mic_push_v : std_logic;
    VARIABLE mic_dw_v : uv32;
    VARIABLE mic_be_v : unsigned(0 TO 3);
    VARIABLE rec_pop_v,emi_push_v,emi_start_v : std_logic;
  BEGIN
    
    IF rising_edge(clk) THEN
      --------------------------------------------------------------------
      -- Compteur de scrutation émissions
      IF tdmd='1' THEN
        tx_cpt<=0;
        tdmd_cpt_set<='0';
      ELSIF tx_cpt<PERIODE_TXCPT THEN
        IF stopa='0' THEN
          tx_cpt<=tx_cpt+1;
        END IF;
        tdmd_cpt_set<='0';
      ELSE
        tdmd_cpt_set<='1';
      END IF;
      
      --------------------------------------------------------------------
      -- Inversion complément à 2 du buffer byte count.
      tcnt_neg_v:="000000000000" - tmd_bcnt;
      
      --------------------------------------------------------------------
      -- Evènements :
      -- - Commande INIT
      init_pend<=(init_pend OR init_pulse) AND NOT idon_set;
      act_init_v:=(init_pend='1');
      
      -- - TX : Fin timer et pas de transfert en cours ou requête émission
      act_tx_new_v  :=((txon AND strt AND tdmd AND NOT tx_act AND
                        NOT mac_emi_r.busy )='1') OR
                       (tx_enp='0' AND mac_emi_r.busy='1' AND mac_emi_r.fifordy='1');
      
      -- - TX : FIFO vide & actif
      act_tx_empty_v:=(mac_emi_r.fifordy='1' AND tx_act='1');
      
      -- - RX : FIFO pleine ou fin de trame
      rec_eof<=(mac_rec_r.eof OR rec_eof) AND NOT rec_eof_clr;
      rec_eof_clr<='0';
      
      act_rx_event_v:=((rxon AND strt AND (rec_eof OR mac_rec_r.fifordy))='1');

      --------------------------------------------------------------------
      saut_v:=false;
      loop_v:=false;
      ----------------------------------
      idon_set<='0';
      miss_set<='0';
      ----------------------------------
      rec_pop_v:='0';
      emi_push_v:='0';
      emi_start_v:='0';
      
      rint_set<='0';
      tint_set<='0';
      tdmd_clr<='0';

      dma_rd<='0';
      dma_wr<='0';
      dma_rw_v:=dma_rw;
      mic_pop_v:='0';
      mic_push_v:='0';
      fifo_flush_v:='0';
      ali_inc_v:='0';
      ali_clr_v:='0';
      mic_dw_v:=mic_dw;
      mic_be_v:=mic_be;
      
      ----------------------------------
      dma_a_v:=dma_a;
      --------------------------------------------------------------------
      op_v :=microcode(pc).op;
      val_v:=microcode(pc).val;
      
      CASE op_v IS
        ----------------------------------
        -- Sauts simples
        WHEN GOTO =>
          saut_v:=true;
          
        WHEN IF_DODO =>
          -- Si rien à faire
          saut_v:=(NOT act_rx_event_v AND
                   NOT act_tx_new_v AND NOT act_tx_empty_v AND NOT act_init_v);
          
        WHEN IF_RX_EVENT =>
          saut_v:=act_rx_event_v AND NOT act_init_v;
          
        WHEN IF_TX_NEW =>
          saut_v:=act_tx_new_v AND NOT act_init_v;

        WHEN IF_TX_FIFO_EMPTY =>
          saut_v:=act_tx_empty_v AND NOT act_init_v;

        WHEN IF_INIT =>
          saut_v:=act_init_v;

        WHEN IF_TMD_OWN0 =>
          saut_v:=(tmd_own='0');

        WHEN IF_RXACT_SET =>
          saut_v:=(rx_act='1');

        WHEN IF_NOT_TXEND =>
          saut_v:=(tcpt<tcnt_neg_v);
          
        WHEN RADR_IF_NOT_RXEOF =>
          -- Vérifie RXEOF
          radr<=rdma;
          saut_v:=(rec_deof='0');
          -- Si il s'agit d'un paquet à sauter, on arrête ici le traitement
          IF rec_deof='1' AND rec_skip='1' THEN
            rec_skip<='0';
            rec_deof<='0';
            rx_act<='0';
            saut_v:=true;
          END IF;
          
        ----------------------------------
        -- Lecture Buffer <-- MEM
        WHEN DMA_READ =>
          loop_v:=(dma_rdok='0');
          dma_rw_v:='1';
          dma_rd<=prim;
          fifo_flush_v:=prim;
          ali_clr_v:='1';
          CASE (val_v MOD 16) IS
            WHEN REC_DESC => dma_a_v:=(rdra & "000") + (rmd_cpt & "000");
            WHEN EMI_DESC => dma_a_v:=(tdra & "000") + (tmd_cpt & "000");
            WHEN PTR      => dma_a_v:=tmd_adr + tcpt;
            WHEN OTHERS   => dma_a_v:=iadr & '0' + to_unsigned(val_v*4,8);
          END CASE;
          
        ----------------------------------
        -- Ecriture Buffer --> MEM
        WHEN DMA_WRITE =>               
          loop_v:=((dma_busy='1' OR prim='1' OR dma_wr='1') AND rec_skip='0');
          dma_rw_v:='0';
          IF (val_v MOD 16=PTR) AND rec_skip='1' THEN
            -- Inhibition du burst sur les accès à sauter
            dma_wr<='0';
          ELSE
            dma_wr<=prim;
          END IF;
          ali_clr_v:='1';
          CASE (val_v MOD 16) IS
            WHEN REC_DESC => dma_a_v:=(rdra & "000") + (rmd_cpt & "000");
            WHEN EMI_DESC => dma_a_v:=(tdra & "000") + (tmd_cpt & "000");
            WHEN PTR      => dma_a_v:=radr; -- + rcpt; -- R_PTR
            WHEN OTHERS   => dma_a_v:=iadr & '0' + to_unsigned(val_v*4,8);
          END CASE;
          
        ----------------------------------
        -- Lecture Buffer --> Registres
        WHEN LOAD =>
          loop_v:=NOT (fifo_ali=dma_a(N_LINE+1 DOWNTO 2));
          dma_rw_v:='1';
          mic_pop_v:='1';
          ali_inc_v:='1';
          CASE (val_v MOD 4) IS
            WHEN L_INIT =>
              IF NOT loop_v THEN
                initvec(159 DOWNTO 0)<=initvec(191 DOWNTO 32);
                initvec(15+160 DOWNTO    160)<=dma_fifo_o.d(31 DOWNTO 16);
                initvec(31+160 DOWNTO 16+160)<=dma_fifo_o.d(15 DOWNTO 0);
                dma_a_v:=dma_a_v+4;
              END IF;
              
            WHEN L_RMD =>
              IF NOT loop_v THEN
                rmd(31 DOWNTO 0)<=rmd(63 DOWNTO 32);
                rmd(47 DOWNTO 32)<=dma_fifo_o.d(31 DOWNTO 16);
                rmd(63 DOWNTO 48)<=dma_fifo_o.d(15 DOWNTO 0);
                dma_a_v:=dma_a_v+4;
              END IF;

            WHEN OTHERS => -- TMD
              IF NOT loop_v THEN
                tmd(31 DOWNTO 0)<=tmd(63 DOWNTO 32);
                tmd(47 DOWNTO 32)<=dma_fifo_o.d(31 DOWNTO 16);
                tmd(63 DOWNTO 48)<=dma_fifo_o.d(15 DOWNTO 0);
                dma_a_v:=dma_a_v+4;
              END IF;
              
          END CASE;
          
        ----------------------------------
        -- Ecriture Buffer <-- Registres
        WHEN STORE =>
          loop_v:=NOT (fifo_ali=dma_a(N_LINE+1 DOWNTO 2));
          dma_rw_v:='0';
          mic_push_v:='1';
          IF (fifo_ali=dma_a(N_LINE+1 DOWNTO 2)) THEN
            mic_be_v:="1111";
          ELSE
            mic_be_v:="0000";
          END IF;
          ali_inc_v:='1';
          CASE (val_v MOD 4) IS
            WHEN L_RMD =>
              mic_dw_v:=rmd(15 DOWNTO 0) & rmd(31 DOWNTO 16);
              IF NOT loop_v THEN
                rmd(31 DOWNTO 0)<=rmd(63 DOWNTO 32);
                dma_a_v:=dma_a_v+4;
              END IF;
              
            WHEN L_TMD =>
              mic_dw_v:=tmd(15 DOWNTO 0) & tmd(31 DOWNTO 16);
              IF NOT loop_v THEN
                tmd(31 DOWNTO 0)<=tmd(63 DOWNTO 32);
                dma_a_v:=dma_a_v+4;
              END IF;

            WHEN OTHERS => -- ALIGN
              mic_dw_v:=tmd(15 DOWNTO 0) & tmd(31 DOWNTO 16);
              mic_be_v:="0000";
              loop_v:=(fifo_ali/="11" AND NOT (fifo_ali="00" AND prim='1'));
          END CASE;
          
        ----------------------------------
        -- Boucle copie réception Buffer <-- MAC
        WHEN LOOP_STORE =>
          loop_v:=(dma_a(N_LINE+1 DOWNTO 1)/=C1(N_LINE+1 DOWNTO 1));
          dma_rw_v:='0';
          IF fifo_ali=dma_a_v(N_LINE+1 DOWNTO 2) THEN
            IF loop_co='1' THEN
              rec_deof<=rec_deof OR mac_rec_r.deof;
              rec_eof_clr<=mac_rec_r.deof;
              IF dma_a_v(1)='0' THEN
                mic_be_v:=mux(rec_deof,"0000","1100");
                mic_dw_v(31 DOWNTO 16):=mac_rec_r.d;
              ELSE
                mic_be_v:=mux(rec_deof,"0000","0011") OR mic_be;
                mic_dw_v(15 DOWNTO 0):=mac_rec_r.d;
              END IF;
              ali_inc_v:=dma_a_v(1);
              mic_push_v:=dma_a_v(1);
              dma_a_v:=dma_a_v+2;
            END IF;
            rec_pop_v:='1';
            loop_co<='1';
          ELSE
            mic_be_v:="0000";
            ali_inc_v:='1';
            mic_push_v:='1';
          END IF;
          IF NOT loop_v OR rec_deof='1' OR (mac_rec_r.deof='1' AND loop_co='1')
          THEN
            rec_pop_v:='0';
          END IF;
          rdma<=dma_a_v;
          
        ----------------------------------
        -- Boucle copie émission Buffer --> MAC
        WHEN LOOP_LOAD =>
          loop_v:=(tcpt<tcnt_neg_v) AND
                   (dma_a(N_LINE+1 DOWNTO 1)/=C1(N_LINE+1 DOWNTO 1));
          dma_rw_v:='1';
          IF fifo_ali=dma_a_v(N_LINE+1 DOWNTO 2) THEN
            dma_a_v:=dma_a_v+2;
            IF tcpt<tcnt_neg_v THEN
              emi_push_v:='1';
              tcpt<=tcpt+2;
              IF dma_a_v(1)='0' THEN
                mic_pop_v:='1';
                ali_inc_v:='1';
              END IF;
            END IF;
            tx_stp<='0';
          ELSE
            mic_pop_v:='1';
            ali_inc_v:='1';
          END IF;
          
        --------------------------------------------------------------------
        -- Opérations registres, drapeaux...
        WHEN OP =>
          CASE (val_v MOD 16) IS
            WHEN RMD_MAJ =>
              -- Mise à jour RMD
              -- <AVOIR> Mise à jour _r.len, _r.crcok au début
              rmd(31)<='0';                            -- OWN=0
              rmd(30)<=NOT mac_rec_r.crcok OR err_buf; -- ERR
              rmd(29 DOWNTO 28)<="00";                 -- FRAM=0, OFLOW=0
              rmd(27)<=NOT mac_rec_r.crcok;            -- CRC error
              rmd(26)<=err_buf;                        -- BUFF
              rmd(25 DOWNTO 24)<="11";                 -- STP=1, ENP=1
              rmd(59 DOWNTO 48)<=mac_rec_r.len;        -- Message byte count
              dma_a_v:=(rdra & "000") + (rmd_cpt & "000");
              rec_deof<='0';
              
            WHEN TMD_MAJ =>
              -- Mise à jour TMD
              tmd(31)<='0';                            -- OWN=0
              tmd(30)<='0';                            -- ERR=0
              tmd(28 DOWNTO 26)<="000";                -- MORE=0,ONE=0,DEF=0
              tmd(63 DOWNTO 48)<=x"0000";              -- Rien de rien
              dma_a_v:=(tdra & "000") + (tmd_cpt & "000");
              
            WHEN SET_TXACT =>
              tx_act<='1';
              tx_stp<=tmd_stp;
              tx_enp<=tmd_enp;
              IF tmd_stp='1' THEN
                tx_len<="000000000000" - tmd_bcnt;
              ELSE
                tx_len<=tx_len - tmd_bcnt;
              END IF;
              
              tcpt<=(OTHERS => '0');
              
            WHEN CLR_TXACT =>
              tx_act<='0';
              tmd_cpt<=inc(tmd_cpt,tlen); -- Incrémente le pointeur d'émission
              tint_set<=tx_enp;
              
            WHEN CLR_RXACT =>
              rx_act<='0';
              rmd_cpt<=inc(rmd_cpt,rlen); -- Incrémente le ptr de réception
              rint_set<='1';
              
            WHEN EMI_CLRTDMD =>
              tdmd_clr<='1';
              
            WHEN INIT_END =>
              -- Positionne IDON=Initialisation Done
              idon_set<='1';
              -- RàZ pointeurs
              tmd_cpt<="0000000";
              rmd_cpt<="0000000";
              rec_skip<='0';
              tx_act<='0';
              rx_act<='0';
              
            WHEN REC_RADR_RXACT =>
              dma_a_v:=radr;
              loop_co<='0';
              rx_act<='1';
              
            WHEN MAJ_ADR_SKIP =>
              radr<=rmd_adr;
              miss_set<=NOT rmd_own;
              -- Si pas de own, buffer pas dipo, les données reçues
              -- sont perdues. Le paquet est dépilé sans écriture.
              rec_skip<=NOT rmd_own;
              
            WHEN OTHERS =>
--            WHEN DMA_FLUSH =>
              -- Remet à zéro tous les Byte Enables, avant d'écrire
              fifo_flush_v:='1';
              fifo_ali<=(OTHERS => '0');
              mic_be_v:="0000";
              
          END CASE;
      END CASE;

      --------------------------------------------------------------------
      -- Accès mémoire DMA
      dma_a<=dma_a_v;
      dma_rw<=dma_rw_v;
      mic_dw<=mic_dw_v;
      mic_be<=mic_be_v;
      
      --------------------------------------------------------------------
      -- EMI_W
      mac_emi_w.d<=mux(dma_a(1),
                       dma_fifo_o.d(15 DOWNTO 0),dma_fifo_o.d(31 DOWNTO 16));
      mac_emi_w.stp<=tx_stp;
      mac_emi_w.enp<=tx_enp;
      mac_emi_w.len<=tx_len;
      
      mac_emi_w.crcgen<=NOT dtcr OR tmd_add_fcs;
      mac_emi_w.push <=emi_push_v;
      mac_emi_w.clr  <=init;
      
      -- REC_W
      mac_rec_w.padr <=padr;
      mac_rec_w.ladrf<=ladrf;
      mac_rec_w.pop  <=rec_pop_v;
      mac_rec_w.clr  <=init;
      
      --------------------------------------------------------------------
      IF saut_v THEN
        pc<=val_v;
      ELSIF NOT loop_v THEN
        pc<=pc+1;
      END IF;
      prim<=to_std_logic(saut_v OR NOT loop_v);
      
      --------------------------------------------------------------------
      -- ALI
      IF ali_inc_v='1' THEN
        fifo_ali<=fifo_ali+1;
      ELSIF ali_clr_v='1' THEN
        fifo_ali<=(OTHERS => '0');
      END IF;
      
      --------------------------------------------------------------------
      -- FIFO trames
      fifo_i_v.d :=mux(dma_rw_v,pr.d,mic_dw_v);
      fifo_i_v.be:=mux(dma_rw_v,"1111",mic_be_v);
      fifo_push_v:=(pr.dreq AND to_std_logic(op_v=DMA_READ) )
                    OR mic_push_v;
      fifo_pop_v :=(pr.ack AND to_std_logic(op_v=DMA_WRITE) AND dma_busy )
                    OR mic_pop_v;
      
      IF fifo_flush_v='1' THEN
        fifo_lev<=3;
        FOR i IN 0 TO BURSTLEN-1 LOOP
          dma_fifo(i).be<="0000";
        END LOOP;
      END IF;
      IF fifo_push_v='1' THEN
        dma_fifo<=fifo_i_v & dma_fifo(0 TO BURSTLEN-2);
      END IF;
      IF fifo_push_v='1' AND fifo_pop_v='0' THEN
        -- Empile
        fifo_lev<=(fifo_lev+1) MOD BURSTLEN;
      ELSIF fifo_push_v='0' AND fifo_pop_v='1' THEN
        -- Dépile
        fifo_lev<=(fifo_lev-1) MOD BURSTLEN;
      END IF;

      IF reset_n='0' THEN
        pc<=0;
        init_pend<='0';
        dma_rd<='0';
        dma_wr<='0';
        miss_set<='0';
        tdmd_cpt_set<='0';
        tdmd_clr<='0';
  --      fifo_lev<=3;
        tint_set<='0';
        rint_set<='0';
        rec_eof<='0';
        rec_eof_clr<='0';
        rec_deof<='0';
        rx_act<='0';
        tx_act<='0';
        tx_stp<='0';
        tx_enp<='0';
        loop_co<='0';
        mac_emi_w.stp<='0';
      END IF;
    END IF;

  END PROCESS Proc;
  
  dma_fifo_o <=dma_fifo(fifo_lev);
  
  ------------------------------------------------------------------------------
  -- Plomb DMA burst
  Plombage:PROCESS(clk)
    VARIABLE ptr : unsigned(N_LINE-1 DOWNTO 0);
  BEGIN
    IF rising_edge(clk) THEN
      pw_i.ah<=x"0";
      pw_i.asi<=ASI;
      pw_i.cache<='0';
      pw_i.lock<='0';
      pw_i.dack<='1';
      
      -- Pipage Adresses/Ecritures
      IF dma_busy='0' THEN
        pw_i.a<=eth_ba & dma_a(23 DOWNTO N_LINE+2) & C0(N_LINE+1 DOWNTO 0);
        pw_i.burst<=pb_blen(BURSTLEN);
        pw_i.req<=dma_wr OR dma_rd;
        dma_busy<=dma_wr OR dma_rd;
        IF dma_wr='1' OR dma_rd='1' THEN
          dma_ra<=(OTHERS => '0');
        END IF;
        pw_i.mode<=mux(dma_rw,PB_MODE_RD,PB_MODE_WR);
      ELSE
        IF pr.ack='1' THEN
          ptr:=pw_i.a(N_LINE+1 DOWNTO 2)+1;
          pw_i.a(N_LINE+1 DOWNTO 2)<=ptr;
          pw_i.mode<=mux(dma_rw,PB_MODE_RD,PB_MODE_WR);
          pw_i.burst<=PB_SINGLE;
          IF pw_i.a(N_LINE+1 DOWNTO 2)=C1(N_LINE+1 DOWNTO 2) THEN
            dma_busy<='0';
            pw_i.req<='0';
          END IF;
        END IF;
      END IF;
      
      -- Pipage données relues
      IF pr.dreq='1' THEN
        dma_ra<=dma_ra+1;
      END IF;

      dma_rdok<=to_std_logic(dma_ra=C1(N_LINE-1 DOWNTO 0)) AND pr.dreq;

      IF reset_n='0' THEN
        pw_i.req<='0';
        pw_i.ah<=x"0";
        pw_i.asi<=ASI;
        pw_i.cache<='0';
        pw_i.lock<='0';
        pw_i.dack<='1';
        pw_i.cont<='0';
        dma_ra<=(OTHERS => '0');
        dma_busy<='0';
        dma_rdok<='0';
      END IF;
    END IF;
  END PROCESS Plombage;

  PWGEN:PROCESS(pw_i,dma_fifo_o,dma_rw)
  BEGIN
    pw   <=pw_i;
    pw.d <=dma_fifo_o.d;
    pw.be<=mux(dma_rw,"1111",dma_fifo_o.be);
  END PROCESS PWGEN;
  
END ARCHITECTURE rtl;
