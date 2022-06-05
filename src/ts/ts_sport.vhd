--------------------------------------------------------------------------------
-- TEM : TS
-- Port Serie
--------------------------------------------------------------------------------
-- DO 9/2010
--------------------------------------------------------------------------------
-- Ports série, clavier, souris. Zilog 85C30
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

-- 0000 : Port B / Mouse Control
-- 0002 : Port B / Mouse Data
-- 0004 : Port A / Keyboard Control
-- 0006 : Port A / Keyboard Data

-- On suppose qu'il n'y a jamais d'accès simultané de "Control" et de "Data"

-- ESCC_CLOCK = 4_915_200
-- ESCC_CLOCK_DIVISOR = 16

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.plomb_pack.ALL;

ENTITY ts_sport IS
  PORT (
    sel     : IN  std_logic;
    w       : IN  type_pvc_w;
    r       : OUT type_pvc_r;
    
    di1_data : IN  uv8;       -- Réception Port 1=A
    di1_req  : IN  std_logic;
    di1_rdy  : OUT std_logic;
    do1_data : OUT uv8;       -- Emission Port 1=A
    do1_req  : OUT std_logic;
    do1_rdy  : IN  std_logic;
    
    di2_data : IN  uv8;       -- Reception Port 2=B
    di2_req  : IN  std_logic;
    di2_rdy  : OUT std_logic;
    do2_data : OUT uv8;       -- Emission Port 2=B
    do2_req  : OUT std_logic;
    do2_rdy  : IN  std_logic;
    
    int      : OUT std_logic; -- Interruption
    
    -- Global
    clk      : IN std_logic;
    reset_n  : IN std_logic
    );
END ENTITY ts_sport;

--##############################################################################

ARCHITECTURE rtl OF ts_sport IS

  SIGNAL rsel : std_logic;
  SIGNAL rdr : uv32;

  TYPE type_parms IS RECORD
    baud : uv16; -- Baudrate gen
    rate : uv2;  -- Clock Rate
    par  : uv2;  -- Parity
    stop : uv2;  -- Stop bits
    
    rx_bits : uv2;
    rx_en   : std_logic;
    rx_ie   : uv2;
    rx_ibrk : std_logic;
    
    tx_bits : uv2;
    tx_en   : std_logic;
    tx_ie   : std_logic;
  END RECORD;

  CONSTANT RX_IE_DISABLE : uv2 := "00";
  CONSTANT RX_IE_FIRST   : uv2 := "01";
  CONSTANT RX_IE_ALL     : uv2 := "10";
--CONSTANT RX_IE_SPECIAL : uv2 := "11";
  
  TYPE arr_parms IS ARRAY(natural RANGE <>) OF type_parms;
  
  SIGNAL parms : arr_parms(1 TO 2);

  SIGNAL rad : uv4; -- 1 pointeur commun pour A et B

  TYPE arr_bis IS ARRAY(natural RANGE <>) OF uv8;
  SIGNAL emi,rec  : arr_bis(1 TO 2);
  SIGNAL emi_push : unsigned(1 TO 2);
  SIGNAL rec_pop  : unsigned(1 TO 2);

  TYPE type_buf IS RECORD
    d    : uv8;
    full : std_logic;
  END RECORD type_buf;
  TYPE arr_buf IS ARRAY(natural RANGE <>) OF type_buf;

  SIGNAL emibuf,recbuf : arr_buf(1 TO 2);
  
  SIGNAL tx_ip,rx_ip : unsigned(1 TO 2);  -- Rec/Transmit Interrupt Pending
  
  SIGNAL tx_all_sent : unsigned(1 TO 2);  -- TX All sent : File d'émission vide
  SIGNAL tx_empty    : unsigned(1 TO 2);  -- TX Empty : On peut écrire 1 char
  SIGNAL rx_avail    : unsigned(1 TO 2);  -- RX Char avail : on peut lire 1 char
  SIGNAL rx_iclr     : unsigned(1 TO 2);  -- RX Interrupt Clear
  SIGNAL rx_maj      : unsigned(1 TO 2);  -- RX Conf. update
  SIGNAL tx_iclr     : unsigned(1 TO 2);  -- TX Interrupt Clear
  SIGNAL tx_cip,tx_mip : unsigned(1 TO 2); -- TX Clear Int. Pending /Mask Int.
  
  SIGNAL tx_fin_pre   : unsigned(1 TO 2);
  SIGNAL rx_avail_pre : unsigned(1 TO 2);
  CONSTANT rx_break   : unsigned(1 TO 2) := "00";  -- RX Break Character
  
  SIGNAL vector : uv8;                   -- Interrupt Vector
  SIGNAL vecode : unsigned(2 DOWNTO 0);  -- Code dans vecteur interruption
  SIGNAL vechilo : std_logic;
  
  CONSTANT VC_B_TX_EMPTY : unsigned(2 DOWNTO 0) := "000";  -- B Tx Buffer Empty
  CONSTANT VC_B_EXTSTAT  : unsigned(2 DOWNTO 0) := "001";  -- B External/Status
  CONSTANT VC_B_RX_AVAIL : unsigned(2 DOWNTO 0) := "010";  -- B Rx Char Avail
  CONSTANT VC_B_SPECIAL  : unsigned(2 DOWNTO 0) := "011";  -- B Rx Special Cond
  CONSTANT VC_A_TX_EMPTY : unsigned(2 DOWNTO 0) := "100";  -- A Tx Buffer Empty
  CONSTANT VC_A_EXTSTAT  : unsigned(2 DOWNTO 0) := "101";  -- A External/Status
  CONSTANT VC_A_RX_AVAIL : unsigned(2 DOWNTO 0) := "110";  -- A Rx Char Avail
  CONSTANT VC_A_SPECIAL  : unsigned(2 DOWNTO 0) := "111";  -- A Rx Special Cond

  SIGNAL do,di : arr_uv8(1 TO 2);
  SIGNAL do_req,do_rdy : unsigned(1 TO 2);
  SIGNAL di_req,di_rdy : unsigned(1 TO 2);
  SIGNAL tx_fin : unsigned(1 TO 2);
  
BEGIN
  
  rsel<=w.req AND sel;
  
  ----------------------------------------------
  -- Lectures & Ecritures registres
  BusRW: PROCESS (clk)
    VARIABLE cw,dw,cr,dr : uv8; -- Ecritures, Lectures

    VARIABLE drv : arr_uv32(1 TO 2);
    VARIABLE c_rd,d_rd : unsigned(1 TO 2); -- Ctrl/Data A/B Read/Write
    VARIABLE c_wr,d_wr : unsigned(1 TO 2);
  BEGIN
    IF rising_edge(clk) THEN
      emi_push<="00";
      rec_pop<="00";
      tx_iclr<="00";
      rx_iclr<="00";
      tx_cip<="00";
      rx_maj<="00";
      ----------------------------------------------
      cw:=w.dw(31 DOWNTO 24);
      dw:=w.dw(15 DOWNTO 8);
      c_rd(2):=rsel AND NOT w.a(2) AND w.be(0) AND NOT w.wr;
      c_wr(2):=rsel AND NOT w.a(2) AND w.be(0) AND     w.wr;
      c_rd(1):=rsel AND     w.a(2) AND w.be(0) AND NOT w.wr;
      c_wr(1):=rsel AND     w.a(2) AND w.be(0) AND     w.wr;
      d_rd(2):=rsel AND NOT w.a(2) AND w.be(2) AND NOT w.wr;
      d_wr(2):=rsel AND NOT w.a(2) AND w.be(2) AND     w.wr;
      d_rd(1):=rsel AND     w.a(2) AND w.be(2) AND NOT w.wr;
      d_wr(1):=rsel AND     w.a(2) AND w.be(2) AND     w.wr;
      
      -- Boucle Port A / Port B
      FOR i IN 1 TO 2 LOOP
        IF c_wr(i)='1' OR c_rd(i)='1' THEN
          rad<="0000"; -- RAZ rad après chaque accès CTRL
        END IF;
        ----------------------------------------------
        -- Ecritures Control
        IF c_wr(i)='1' THEN
          REPORT "SPORT WR CTRL (" & integer'image(i) &
            ") : " & To_HString(cw) & " RAD=" & To_String(rad) SEVERITY note;
          CASE rad IS
            WHEN "0000" => -- WR0
              -- 2:0 : Register Selection
              -- 5:3 : Command Codes
              -- 7:6 : CRC Reset Codes <non>
              rad<='0' & cw(2 DOWNTO 0);
              
              CASE cw(5 DOWNTO 3) IS
                WHEN "000" =>
                  -- Null, no effect
                  
                WHEN "001" => -- <QEMU>
                  -- Point High
                  rad(3)<='1';
                  
                WHEN "010" =>
                  -- Reset External / Status Interrupts
                  
                WHEN "011" =>
                  -- Send Abort
                  
                WHEN "100" =>
                  -- Enable Interrupt on next RX character
                  
                WHEN "101" => -- <QEMU>
                  -- Reset Tx Interrupt pending
                  -- Pour signaler la fin d'un message, on ne signale pas
                  -- l'interruption après la fin de l'émission du dernier
                  -- caractère.
                  tx_cip(i)<='1';
                  
                  
                WHEN "111" => -- <QEMU>
                  -- Reset highest Interrupt Under Service
                  -- <AVOIR> Gestion séparée des 2 voies ?
                  IF tx_ip(1)='1' THEN
                    tx_iclr(1)<='1';
                  ELSIF tx_ip(2)='1' THEN
                    tx_iclr(2)<='1';
                  END IF;
                  
                WHEN OTHERS => -- "110"
                  -- Error Reset
                  NULL;
                  
              END CASE;
              
            WHEN "0001" => -- WR1
              -- Transmit / Receive Interrupt and Data Transfer Mode Definition
              --   0 : External/Status Master Interrupt Enable
              --   1 : Transmitter Interrupt Enable <QEMU>
              --   2 : Parity is Special Condition
              -- 4:3 : 00 : Rx Int Disabled
              --       01 : Rx Int on First Char or Spec. Condition <QEMU>
              --       10 : Interrupt on All Rx Char or Special Condition <QEMU>
              --       11 : Receive Interrupt on Special Condition
              --   5 : WAIT / DMA Request On Receive Transmit
              --   6 : WAIT / DMA Request function
              --   7 : WAIT / DMA Request enable
              parms(i).tx_ie<=cw(1);
              parms(i).rx_ie<=cw(4 DOWNTO 3);
              rx_maj(i)<='1';
              
            WHEN "0010" => -- WR2
              -- Interrupt Vector <noqemu>
              vector<=cw;

            WHEN "0011" => -- WR3
              -- Receive Parameters and Control
              --   0 : Receiver Enable <QEMU>
              --   1 : Sync Character Load Inhibit <non>
              --   2 : Address Search Mode <non>
              --   3 : Receiver CRC Enable <non>
              --   4 : Enter Hunt mode
              --   5 : Auto Enables DCD & CTS
              -- 7:6 : Rx Bits/character : 5/6/7/8
              parms(i).rx_en  <=cw(0);
              parms(i).rx_bits<=cw(7 DOWNTO 6);
              rx_maj(i)<='1';
              
            WHEN "0100" => -- WR4
              -- Transmit/Receiver Misc Parameters & Modes
              -- 7:6 : Clock Rate <non> <QEMU>
              -- 5:4 : Sync Mode <non>
              -- 3:2 : Stop bits Sync/1/1.5/2 <non> <QEMU>
              --   1 : Parity Even=1 Odd=0 <QEMU>
              --   0 : Parity Enable <QEMU>
              parms(i).rate<=cw(7 DOWNTO 6);
              parms(i).stop<=cw(3 DOWNTO 2);
              parms(i).par<=cw(1 DOWNTO 0);
              
            WHEN "0101" => -- WR5
              -- Transmit Parameter and Controls
              --   0 : Transmit CRC Enable <non>
              --   1 : RTS
              --   2 : SDLC/CRC16 <non>
              --   3 : Transmit Enable <QEMU>
              --   4 : Send break
              -- 6:5 : Tx Bits/character : 5/6/7/8 <QEMU>
              --   7 : DTR
              parms(i).tx_en  <=cw(3);
              parms(i).tx_bits<=cw(7 DOWNTO 6);
              
            WHEN "0110" => -- WR6
              -- Sync Character or SDLC Address <non> <noqemu>

            WHEN "0111" => -- WR7
              -- <Probleme doc> <noqemu>

            WHEN "1000" => -- WR8
              -- Transmit buffer = Ecriture DATA <noqemu>
              dw:=cw;
              d_wr(i):='1';

            WHEN "1001" => -- WR9
              -- Master Interrupt Control
              --   0 : VIS : Vector Includes Status
              --   1 : NV : No Vector
              --   2 : DLC : Disable Lower Chain (interrupt daisy chain)
              --   3 : MIE :  Master Interrupt Enable
              --   4 : Status High/Low : Int. Vector modification <QEMU>
              --   5 : Interrupt masking without intack
              -- 7:6 : Reset : No / B / A / HW RESET <QEMU>
              -- Commun channel A, channel B !!
              vechilo<=cw(4);
              IF cw(6)='1' THEN
                parms(2).rx_en<='0';
                parms(2).tx_en<='0';
                parms(2).rx_ie<=RX_IE_DISABLE;
                parms(2).tx_ie<='0';
              END IF;
              IF cw(7)='1' THEN
                parms(1).rx_en<='0';
                parms(1).tx_en<='0';
                parms(1).rx_ie<=RX_IE_DISABLE;
                parms(1).tx_ie<='0';
              END IF;

            WHEN "1010" => -- WR10
              -- Misc. Transmitter/Receiver Control <noqemu>
              --   0 : 6bits/8bits sync <non>
              --   1 : Loop mode <non>
              --   2 : Abort/Flag on Underrun <non>
              --   3 : Mark/Flag idle <non>
              --   4 : Go active on poll <non>
              -- 6:5 : Data encoding <non>
              --   7 : CRC preset <non>

            WHEN "1011" => -- WR11
              -- Clock mode control <non> <Qemu-init>
              -- 1:0 : TRxC OUT
              --   2 : TRxC O/I
              -- 4:3 : Transmit clock
              -- 6:5 : Receive Clock
              --   7 : Xtal

            WHEN "1100" => -- WR12
              -- Baud rate LSB
              -- 7:0 : Time constant [7:0] <QEMU>
              parms(i).baud(7 DOWNTO 0)<=cw;
              
            WHEN "1101" => -- WR13
              -- Baud rate MSB
              -- 7:0 : Time constant [15:8] <QEMU>
              parms(i).baud(15 DOWNTO 8)<=cw;
              
            WHEN "1110" => -- WR14
              -- Misc. Control bits <non> <Qemu-init>
              --   0 : Baud Rate gen. enable
              --   1 : Baud Rate gen. source
              --   2 : DTR/TRansmit DMA
              --   3 : Auto Echo
              --   4 : Local Loopback
              -- 7:5 : DPLL Commands
              
            WHEN "1111" => -- WR15
              -- External/Status Interrupt Control
              --   0 : SDLC/HDLC Enhancement Ena
              --   1 : Zero count IE
              --   2 : 10x19 bit frame status fifo enable
              --   3 : DCD IE <Qemu-init>
              --   4 : Sync/Hunt IE <Qemu-init>
              --   5 : CTS IE <Qemu-init>
              --   6 : Tx Underrun <Qemu-init>
              --   7 : Break/Abort IE <QEMU>
              parms(i).rx_ibrk<=cw(7);
              
            WHEN OTHERS =>
              NULL;
              
          END CASE;
        END IF; -- IF c_wr(i)='1'

        ----------------------------------------------
        -- Lectures Control
        IF c_rd(i)='1' THEN
          CASE rad IS
            WHEN "0000" | "0100" => -- RR0
              -- Transmit/Receive Buffer Status ans EXternal Status
              --   0 : Rx Character available <QEMU>
              --   1 : Zero count
              --   2 : Tx Buffer empty <QEMU>
              --   3 : DCD  <Qemu-init, si disabled>
              --   4 : Sync/Hunt <Qemu-init, si disabled>
              --   5 : CTS <Qemu-init, si disabled>
              --   6 : Tx Underrun/EOM <Qemu-init>
              --   7 : Break/Abort <QEMU>
              cr:=rx_break(i) & "1000" & tx_empty(i) & '0' & rx_avail(i);
              
            WHEN "0001" | "0101" => -- RR1
              -- Special Receive Conditions Status
              --   0 : All Sent <QEMU>
              --   1 : Residue Code 2 <Qemu-init>
              --   2 : Residue Code 1 <Qemu-init>
              --   3 : Residue Code 0
              --   4 : Parity Error
              --   5 : Rx Overrun Error
              --   6 : CRC/Framing error
              --   7 : End of Frame (SDLC)
              cr:="0000011" & tx_all_sent(i);
              
            WHEN "0010" | "0110" => -- RR2
              -- Interrupt vector, written in WR2 <QEMU>
              -- Different ChannelA/ChannelB
              IF i=1 THEN
                -- Channel A : Vecteur brut
                cr:=vector;
              ELSE
                -- Channel B : Vecteur noyauté
                IF vechilo='0' THEN
                  -- Bits 3-2-1 modifiés
                  cr:=vector(7 DOWNTO 4) &
                       vecode(2) & vecode(1) & vecode(0) & vector(0);
                ELSE
                  -- Bits 4-5-6 modifiés
                  cr:=vector(7) & vecode(0) & vecode(1) & vecode(2) &
                       vector(3 DOWNTO 0);
                END IF;
              END IF;
              
            WHEN "0011" | "0111" => -- RR3
              -- Interrupt pending register
              --   0 : Channel B EXT/STAT IP <noqemu>
              --   1 : Channel B Tx IP <QEMU>
              --   2 : Channel B Rx IP <QEMU>
              --   3 : Channel A EXT/STAT IP <noqemu>
              --   4 : Channel A Tx IP <QEMU>
              --   5 : Channel A Rx IP <QEMU>
              -- 7:6 : 00
              IF i=1 THEN
                -- Seulement channel A
                cr:="00" & rx_ip(1) & tx_ip(1) & '0' &
                     rx_ip(2) & tx_ip(2) & '0';
              ELSE
                cr:=x"00";
              END IF;
            WHEN "1000" => -- RR8
              -- Receive data register <noqemu>
              cr:=rec(i);
              rec_pop(i)<='1';
              
            WHEN "1001" | "1101" => -- RR13
              -- Read WR13 : Baud rate generator HI
              cr:=parms(i).baud(15 DOWNTO 8);
              
            WHEN "1010" | "1110" => -- RR10
              -- Misc. status bits
              --   0 : 0
              --   1 : On loop
              -- 3:2 : 00
              --   4 : Loop sending
              --   5 : 0
              -- 7:6 : One Clock/Two clocks missing
              cr:=x"00";

            WHEN "1100" => -- RR12
              -- Read WR12 : Baud rate generator LO
              cr:=parms(i).baud(7 DOWNTO 0);

            WHEN OTHERS => --"1011" | "1111" => -- RR15
              -- Relecture WR15 : External/Status IE bits
              --   0 : SDLC/HDLC Enhancement Ena
              --   1 : Zero count IE
              --   2 : 10x19 bit frame status fifo enable
              --   3 : DCD IE
              --   4 : Sync/Hunt IE
              --   5 : CTS IE
              --   6 : Tx Underrun
              --   7 : Break/Abort IE <QEMU>
              cr:=x"00";
              
          END CASE;
          --REPORT "SPORT RD CTRL (" & integer'image(i) &
          --  ") : " & To_HString(cr) & " RAD=" & To_String(rad) SEVERITY note;
          
        END IF; -- If c_rd(i)='1'
        
        ----------------------------------------------
        -- Ecriture Data
        IF d_wr(i)='1' THEN
          emi(i)<=dw;
          emi_push(i)<='1';
          tx_iclr(i)<='1';
          REPORT "SPORT : WR DATA (" & integer'image(i) &
            ") : " & To_HString(dw) SEVERITY note;
        END IF;
        
        ----------------------------------------------
        -- Lectures Data
        IF d_rd(i)='1' THEN
          dr:=rec(i);
          rec_pop(i)<='1';
          rx_iclr(i)<='1';
          REPORT "SPORT : RD DATA (" & integer'image(i) &
            ") : " & To_HString(dr) SEVERITY note;
        END IF;
        
        drv(i):=cr & x"00" & dr & x"00";

        ----------------------------------------------
      END LOOP;  -- Boucle Port A=1 / Port B=2
      
      ----------------------------------------------
      -- Mux relecture Port A / Port B
      IF w.a(2)='1' THEN
        rdr<=drv(1);
      ELSE
        rdr<=drv(2);
      END IF;
      ----------------------------------------------
      IF reset_n='0' THEN
        emi_push<="00";
        rec_pop<="00";
        rad<="0000";       -- <AVOIR> Bug OpenBIOS : RAZ rad avant init UART
        parms(1).rx_en<='0';
        parms(2).rx_en<='0';
        parms(1).rx_ie<=RX_IE_DISABLE;
        parms(2).rx_ie<=RX_IE_DISABLE;
        parms(1).baud <=x"0000";
        parms(2).baud <=x"0000";
        parms(1).rate <="00";
        parms(2).rate <="00";
        parms(1).par <="00";
        parms(2).par <="00";
        parms(1).stop <="00";
        parms(2).stop <="00";
        parms(1).rx_bits <="00";
        parms(2).rx_bits <="00";
        parms(1).tx_bits <="00";
        parms(2).tx_bits <="00";
        parms(1).tx_en<='0';
        parms(2).tx_en<='0';
        parms(1).tx_ie<='0';
        parms(2).tx_ie<='0';
        vector <= x"00";
        vechilo<='0';
      END IF;
    END IF;
  END PROCESS BusRW;
  
  ----------------------------------------------
  -- Relectures
  R_Gen:PROCESS(rsel,rdr)
  BEGIN
    r.ack<=rsel;
    r.dr<=rdr;
  END PROCESS R_Gen;
  
  ----------------------------------------------
  do1_data<=do(1);
  do2_data<=do(2);
  do1_req<=do_req(1);
  do2_req<=do_req(2);
  do_rdy<=do1_rdy & do2_rdy;

  di<=di1_data & di2_data;
  di_req<=di1_req & di2_req;
  di1_rdy<=di_rdy(1);
  di2_rdy<=di_rdy(2);
  
  ----------------------------------------------
  -- Emission/Receptions
  EmiRec:PROCESS (clk)
  BEGIN
    IF rising_edge(clk) THEN
      -- Emissions
      FOR i IN 1 TO 2 LOOP
        IF parms(i).tx_en='1' THEN
          -- Buffer
          IF emi_push(i)='1' THEN
            emibuf(i).d<=emi(i);
            emibuf(i).full<='1';
            tx_fin(i)<='0';
          END IF;
          -- Sortie
          do_req(i)<='0';
          IF do_rdy(i)='1' AND emibuf(i).full='1' THEN
            do(i)<=emibuf(i).d;
            do_req(i)<='1';
            emibuf(i).full<='0';
            tx_fin(i)<='1';
          END IF;
          -- Drapeaux
          tx_all_sent(i)<=do_rdy(i) AND NOT emibuf(i).full;
          tx_empty(i)<=NOT emibuf(i).full;
        ELSE
          tx_fin(i)<='0';
          tx_empty(i)<='1';
          tx_all_sent(i)<='1';
          emibuf(i).full<='0';
        END IF;
      END LOOP;
      
      -- Réceptions
      FOR I IN 1 TO 2 LOOP
        IF parms(i).rx_en='1' THEN
          -- Entree
          IF di_req(i)='1' AND di_rdy(i)='0' THEN
            recbuf(i).d<=di(i);
            recbuf(i).full<='1';
          END IF;
          -- Buffer
          di_rdy(i)<='0';
          IF recbuf(i).full='1' AND rx_avail(i)='0' THEN
            rec(i)<=recbuf(i).d;
            rx_avail(i)<='1';
            recbuf(i).full<='0';
            di_rdy(i)<='1';
          END IF;
          
          -- Drapeaux
          IF rec_pop(i)='1' THEN
            rx_avail(i)<='0';
          END IF;
        ELSE
          rx_avail(i)<='0';
          recbuf(i).full<='0';
          di_rdy(i)<='1';
        END IF;
      END LOOP;
      
      ---------------------------------
      IF reset_n='0' THEN
        emibuf(1).full<='0';
        emibuf(2).full<='0';
        recbuf(1).full<='0';
        recbuf(2).full<='0';
        rx_avail<="00";
        tx_fin<="00";
        do_req<="00";
      END IF;
    END IF;
  END PROCESS EmiRec;

  ----------------------------------------------
  -- Interruptions
  Inter:PROCESS (clk)
  BEGIN
    IF rising_edge(clk) THEN
      tx_fin_pre<=tx_fin;
      rx_avail_pre<=rx_avail;
      
      FOR i IN 1 TO 2 LOOP
        -- Interruptions émissions
        IF parms(i).tx_en='1' AND parms(i).tx_ie='1' AND
          tx_fin(i)='1' AND tx_fin_pre(i)='0' THEN
          tx_ip(i)<=NOT tx_mip(i);
          tx_mip(i)<='0';
        END IF;
        IF tx_iclr(i)='1' THEN
          tx_ip(i)<='0';
        END IF;

        IF tx_cip(i)='1' THEN
          -- Si CIP=1, on inhibe la génération de la prochaine interruption TX
          -- En fait, "Reset TxInt pend." remet à zéro l'interruption en cours
          tx_mip(i)<=NOT tx_ip(i);
          tx_ip(i)<='0';
        END IF;
        IF parms(i).tx_en='0' THEN
          tx_mip(i)<='0';
          tx_ip(i)<='0';
        END IF;
        
        -- Interruptions réception
        IF parms(i).rx_en='1' AND rx_avail(i)='1' AND
          (rx_avail_pre(i)='0' OR rx_maj(i)='1') AND
          (parms(i).rx_ie=RX_IE_ALL OR parms(i).rx_ie=RX_IE_FIRST) THEN
          rx_ip(i)<='1';
        END IF;
        IF rx_iclr(i)='1' THEN
          rx_ip(i)<='0';
        END IF;
      END LOOP;
      ----------------------------------------
      IF reset_n='0' THEN
        rx_ip<="00";
        tx_ip<="00";
        tx_mip<="00";
      END IF;
    END IF;
  END PROCESS Inter;

  -- Priorités d'interruption :
  --   RX A (high) -> TX A -> Ext A -> RX B -> TX B -> Ext B (low)
  vecode<=VC_A_RX_AVAIL WHEN rx_ip(1)='1' ELSE
          VC_A_TX_EMPTY WHEN tx_ip(1)='1' ELSE
          VC_B_RX_AVAIL WHEN rx_ip(2)='1' ELSE
          VC_B_TX_EMPTY WHEN tx_ip(2)='1' ELSE
          VC_B_SPECIAL;

  int<=rx_ip(1) OR rx_ip(2) OR tx_ip(1) OR tx_ip(2);

END ARCHITECTURE rtl;
