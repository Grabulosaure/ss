--------------------------------------------------------------------------------
-- TEM : TS
-- Contrôleur d'interruptions
--------------------------------------------------------------------------------
-- DO 9/2010
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

-- Hardware interrupts levels :
--  1 = [SoftInt]
--  2 = (VME+SBUS)
--  3 = (VME+SBUS)
--  4 = SCSI
--  5 = (VME+SBUS)
--  6 = Ethernet
--  7 = (VME+SBUS)
--  8 = (Video)
--  9 = (VME+SBUS+ModInterrupt)
-- 10 = System Timer
-- 11 = (VME+SBUS+Floppy)
-- 12 = Keyboard/Mouse + Sport
-- 13 = (VME+SBUS+ISDN Audio)
-- 14 = Processor Timer
-- 15 = (Asynch. errors broadcast)

-- On dit qu'il n'y a jamais d'exception n°15 (super-grave)

-- 0_n000 : Processor interrupt pending register (R)
-- 0_n004 : Processor clear pending pseudo-register (W)
-- 0_n008 : Processor set soft int pseudo-register (W)
-- 0_n00C : Reserved
-- 1_0000 : System Interrupt pending register (R)
-- 1_0004 : System Interrupt target mask register (R)
-- 1_0008 : System Interrupt target mask clear pseudo-register (W)
-- 1_000C : System Interrupt target mask set pseudo-register (W)
-- 1_0010 : System Interrupt target register (RW)

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.plomb_pack.ALL;
USE work.ts_pack.ALL;

ENTITY ts_inter IS
  GENERIC (
    CPU0  : boolean;
    CPU1  : boolean;
    CPU2  : boolean;
    CPU3  : boolean);
  PORT (
    sel   : IN  std_logic;
    w     : IN  type_pvc_w;
    r     : OUT type_pvc_r;

    irl0  : OUT uv4;
    irl1  : OUT uv4;
    irl2  : OUT uv4;
    irl3  : OUT uv4;
    
    int_timer_s  : IN std_logic; -- System timer
    int_timer_p0 : IN std_logic; -- Processor 0 timer
    int_timer_p1 : IN std_logic; -- Processor 1 timer
    int_timer_p2 : IN std_logic; -- Processor 2 timer
    int_timer_p3 : IN std_logic; -- Processor 3 timer
    int_esp      : IN std_logic; -- SCSI ESP
    int_ether    : IN std_logic; -- Ethernet
    int_sport    : IN std_logic; -- Serial port
    int_kbm      : IN std_logic; -- Keyboard / Mouse
    int_video    : IN std_logic; -- Video (CG3)
    
    -- Global
    clk      : IN std_logic;
    reset_na : IN std_logic
    );
END ENTITY ts_inter;

--##############################################################################

ARCHITECTURE rtl OF ts_inter IS

  SIGNAL hs_int0 ,hs_int1 ,hs_int2 ,hs_int3  : unsigned(15 DOWNTO 1);
  SIGNAL hardint0,hardint1,hardint2,hardint3 : unsigned(15 DOWNTO 1);
  SIGNAL softint0,softint1,softint2,softint3 : unsigned(15 DOWNTO 1);
  SIGNAL pend,mask : uv32;
  SIGNAL itr : uv2;
  SIGNAL sysint : uv32;
  SIGNAL dr : uv32;
  SIGNAL rsel : std_logic;
  CONSTANT ZERO32 : uv32 := (OTHERS =>'0');
  CONSTANT MP : boolean :=
    (CPU0 AND CPU1) OR (CPU0 AND CPU2) OR (CPU0 AND CPU3) OR
    (CPU1 AND CPU2) OR (CPU1 AND CPU3) OR (CPU2 AND CPU3);

  FUNCTION hardint(pend        : IN uv32;
                   int_timer_p : IN std_logic;
                   itr         : IN uv2;
                   cpu         : IN uv2) RETURN unsigned IS
  BEGIN
    IF NOT MP OR itr=cpu THEN
      RETURN
        (pend(30) OR pend(29) OR pend(28) OR pend(27)) & -- 15 : Async errors
        int_timer_p &                          -- 14: Per-processor counter
        (pend(6) OR pend(13) OR pend(17)) &    -- 13: VME7 + SBUS7 + Audio
        (pend(14) OR pend(15)) &               -- 12: Keyboard/Mouse + Sport
        (pend(5) OR pend(12) OR pend(22)) &    -- 11: VME6 + SBUS6 + Floppy
        pend(19) &                             -- 10: System Timer
        (pend(4) OR pend(11) OR pend(21)) &    --  9: VME5 + SBUS5 + Module
        pend(20) &                             --  8: Video (mainboard)
        (pend(3) OR pend(10)) &                --  7: VME4 + SBUS4
        pend(16) &                             --  6: Ethernet
        (pend(2) OR pend(9)) &                 --  5: VME3 + SBUS3
        pend(18) &                             --  4: SCSI
        (pend(1) OR pend(8)) &                 --  3: VME2 + SBUS2
        (pend(0) OR pend(7)) &                 --  2: VME1 + SBUS1
        '0';                                   --  1: (Softint)
    ELSE
      RETURN '0' & int_timer_p & "0000000000000";
    END IF;
  END FUNCTION;
BEGIN

  -------------------------------------------------
  sysint<=
    '0' &                  -- [31] Reserve / Mask all
    "00" &                 -- [30] Module error (L15)  [29] M-to-S (L15)
    "00" &                 -- [28] ECC Mem (L15)       [27] VME Async (L15)
    "0000" &               -- [26:23] Réservé
    '0' & '0' & '0' &      -- [22] Floppy     [21] Module    [20] Video
    int_timer_s &          -- [19] System Timer
    int_esp & '0' &        -- [18] SCSI       [17] Audio
    int_ether &            -- [16] Ethernet
    int_sport &            -- [15] Sport
    int_kbm &              -- [14] Keyboard + Mouse
    "00" &                 -- [13:12] : SBUS(7-6)
    int_video &            -- [11]    : SBUS5 : Video (CG3)
    "0000" &               -- [10:7]  : SBUS(4-3-2-1)
    "0000000";             -- [6:0] VME
  
  pend<=sysint AND NOT mask AND mux(mask(31),x"00000000",x"FFFFFFFF");

  hardint0<=hardint(pend,int_timer_p0,itr,"00");
  hardint1<=hardint(pend,int_timer_p1,itr,"01");
  hardint2<=hardint(pend,int_timer_p2,itr,"10");
  hardint3<=hardint(pend,int_timer_p3,itr,"11");
  
  -------------------------------------------------
  Interrupteur: PROCESS (clk,reset_na)
  BEGIN
    IF reset_na='0' THEN
      softint0<="000000000000000";
      softint1<="000000000000000";
      softint2<="000000000000000";
      softint3<="000000000000000";
      mask<=x"7FFFFFFF";
      
    ELSIF rising_edge(clk) THEN
      ----------------------------------------------
      -- Lectures & Ecritures

      ----------------
      -- CPU0
      -- 0_0000 : Processor interrupt pending register (R)
      IF rsel='1' AND w.a(16 DOWNTO 12)="00000" AND w.a(3 DOWNTO 2)="00"
        AND CPU0 THEN
        dr<=softint0 & '0' & hardint0 & '0';
      END IF;

      -- 0_0004 : Processor clear pending pseudo-register (W)
      IF rsel='1' AND w.a(16 DOWNTO 12)="00000" AND w.a(3 DOWNTO 2)="01"
        AND CPU0 THEN
        IF w.be="1111" AND w.wr='1' THEN
          softint0<=softint0 AND NOT w.dw(31 DOWNTO 17);
        END IF;
        dr<=ZERO32;
      END IF;
      
      -- 0_0008 : Processor set soft int pseudo-register (W)
      IF rsel='1' AND w.a(16 DOWNTO 12)="00000" AND w.a(3 DOWNTO 2)="10"
        AND CPU0 THEN
        IF w.be="1111" AND w.wr='1' THEN
          softint0<=softint0 OR w.dw(31 DOWNTO 17);
        END IF;
        dr<=ZERO32;
      END IF;

      ----------------
      -- CPU1
      -- 0_1000 : Processor interrupt pending register (R)
      IF rsel='1' AND w.a(16 DOWNTO 12)="00001" AND w.a(3 DOWNTO 2)="00"
        AND CPU1 THEN
        dr<=softint1 & '0' & hardint1 & '0';
      END IF;

      -- 0_1004 : Processor clear pending pseudo-register (W)
      IF rsel='1' AND w.a(16 DOWNTO 12)="00001" AND w.a(3 DOWNTO 2)="01"
        AND CPU1 THEN
        IF w.be="1111" AND w.wr='1' THEN
          softint1<=softint1 AND NOT w.dw(31 DOWNTO 17);
        END IF;
        dr<=ZERO32;
      END IF;
      
      -- 0_1008 : Processor set soft int pseudo-register (W)
      IF rsel='1' AND w.a(16 DOWNTO 12)="00001" AND w.a(3 DOWNTO 2)="10"
        AND CPU1 THEN
        IF w.be="1111" AND w.wr='1' THEN
          softint1<=softint1 OR w.dw(31 DOWNTO 17);
        END IF;
        dr<=ZERO32;
      END IF;
      
      ----------------
      -- CPU2
      -- 0_2000 : Processor interrupt pending register (R)
      IF rsel='1' AND w.a(16 DOWNTO 12)="00010" AND w.a(3 DOWNTO 2)="00"
        AND CPU2 THEN
        dr<=softint2 & '0' & hardint2 & '0';
      END IF;

      -- 0_2004 : Processor clear pending pseudo-register (W)
      IF rsel='1' AND w.a(16 DOWNTO 12)="00010" AND w.a(3 DOWNTO 2)="01"
        AND CPU2 THEN
        IF w.be="1111" AND w.wr='1' THEN
          softint2<=softint2 AND NOT w.dw(31 DOWNTO 17);
        END IF;
        dr<=ZERO32;
      END IF;
      
      -- 0_2008 : Processor set soft int pseudo-register (W)
      IF rsel='1' AND w.a(16 DOWNTO 12)="00010" AND w.a(3 DOWNTO 2)="10"
        AND CPU2 THEN
        IF w.be="1111" AND w.wr='1' THEN
          softint2<=softint2 OR w.dw(31 DOWNTO 17);
        END IF;
        dr<=ZERO32;
      END IF;

      ----------------
      -- CPU3
      -- 0_3000 : Processor interrupt pending register (R)
      IF rsel='1' AND w.a(16 DOWNTO 12)="00011" AND w.a(3 DOWNTO 2)="00"
        AND CPU3 THEN
        dr<=softint3 & '0' & hardint3 & '0';
      END IF;

      -- 0_3004 : Processor clear pending pseudo-register (W)
      IF rsel='1' AND w.a(16 DOWNTO 12)="00011" AND w.a(3 DOWNTO 2)="01"
        AND CPU3 THEN
        IF w.be="1111" AND w.wr='1' THEN
          softint3<=softint3 AND NOT w.dw(31 DOWNTO 17);
        END IF;
        dr<=ZERO32;
      END IF;
      
      -- 0_3008 : Processor set soft int pseudo-register (W)
      IF rsel='1' AND w.a(16 DOWNTO 12)="00011" AND w.a(3 DOWNTO 2)="10"
        AND CPU3 THEN
        IF w.be="1111" AND w.wr='1' THEN
          softint3<=softint3 OR w.dw(31 DOWNTO 17);
        END IF;
        dr<=ZERO32;
      END IF;
      
      -- 0_n00C : Reserved

      ----------------
      -- 1_0000 : System Interrupt pending register (R)
      IF rsel='1' AND w.a(16)='1' AND w.a(4 DOWNTO 2)="000" THEN
        dr<=sysint;
        -- <On ne montre pas les interruptions masquées ???>
      END IF;
      
      -- 1_0004 : System Interrupt target mask register (R)
      IF rsel='1' AND w.a(16)='1' AND w.a(4 DOWNTO 2)="001" THEN
        dr<=mask;
      END IF;
      
      -- 1_0008 : System Interrupt target mask clear pseudo-register (W)
      IF rsel='1' AND w.a(16)='1' AND w.a(4 DOWNTO 2)="010" THEN
        IF w.be="1111" AND w.wr='1' THEN
          mask<=mask AND NOT w.dw;
        END IF;
        dr<=ZERO32;
      END IF;
      
      -- 1_000C : System Interrupt target mask set pseudo-register (W)
      IF rsel='1' AND w.a(16)='1' AND w.a(4 DOWNTO 2)="011" THEN
        IF w.be="1111" AND w.wr='1' THEN
          mask<=mask OR w.dw;
        END IF;
        dr<=ZERO32;
      END IF;

      -- 1_0010 : System Interrupt target register (RW)
      IF rsel='1' AND w.a(16)='1' AND w.a(4 DOWNTO 2)="100" THEN
        IF MP THEN
          IF w.be(3)='1' AND w.wr='1' THEN
            itr<=w.dw(1 DOWNTO 0);
          END IF;
          dr<=x"000000" & "000000" & itr;
        ELSE
          dr<=ZERO32;
        END IF;
      END IF;

    END IF;    
  END PROCESS Interrupteur;

  rsel<=w.req AND sel;
  
  -- Relectures registres
  R_GEN:PROCESS(sel,dr)
  BEGIN
    r.ack<=sel;
    r.dr<=dr;
  END PROCESS R_GEN;

  ------------------------------------------------
  Encodeur: PROCESS (clk)
    ----------------------------------------------
    FUNCTION enc(CONSTANT a : unsigned(1 DOWNTO 0)) RETURN unsigned IS
    BEGIN
      CASE a IS
        WHEN "00" => RETURN "10";
        WHEN "01" => RETURN "01";
        WHEN "10" => RETURN "00";
        WHEN OTHERS => RETURN "00";
      END CASE;
    END FUNCTION enc;
    
    FUNCTION clzi(
      CONSTANT n : IN natural;
      CONSTANT i : IN unsigned) RETURN unsigned IS
      VARIABLE v : unsigned(i'length-1 DOWNTO 0):=i;  
    BEGIN
      IF v(n-1+n)='0' THEN
        RETURN (v(n-1+n) AND v(n-1)) & '0' & v(2*n-2 DOWNTO n);
      ELSE
        RETURN (v(n-1+n) AND v(n-1)) & NOT v(n-1) & v(n-2 DOWNTO 0);
      END IF;
    END FUNCTION clzi;
    
    FUNCTION clz16 (CONSTANT v : unsigned(0 TO 15)) RETURN unsigned IS
      VARIABLE e : unsigned(0 TO 15);     -- 16
      VARIABLE a : unsigned(0 TO 4*3-1);  -- 12
      VARIABLE b : unsigned(0 TO 2*4-1);  -- 8
    BEGIN
      FOR i IN 0 TO 7  LOOP e(i*2 TO i*2+1):=enc(v(i*2 TO i*2+1));  END LOOP;
      FOR i IN 0 TO 3  LOOP a(i*3 TO i*3+2):=clzi(2,e(i*4 TO i*4+3)); END LOOP;
      FOR i IN 0 TO 1  LOOP b(i*4 TO i*4+3):=clzi(3,a(i*6 TO i*6+5)); END LOOP;
      RETURN clzi(4,b(0 TO 7));
    END FUNCTION clz16;
    
    FUNCTION encode_pre(int : unsigned(15 DOWNTO 1)) RETURN unsigned IS
      VARIABLE v : unsigned(4 DOWNTO 0);
    BEGIN
      v:=clz16(int & '1');
      RETURN NOT v(3 DOWNTO 0);
    END;
    
    ----------------------------------------------
    FUNCTION encode_p2(int : unsigned(15 DOWNTO 1)) RETURN unsigned IS
    BEGIN
      IF    int(15)='1' THEN  RETURN x"F";
      ELSIF int(14)='1' THEN  RETURN x"E";
      ELSIF int(13)='1' THEN  RETURN x"D";
      ELSIF int(12)='1' THEN  RETURN x"C";
      ELSIF int(11)='1' THEN  RETURN x"B";
      ELSIF int(10)='1' THEN  RETURN x"A";
      ELSIF int( 9)='1' THEN  RETURN x"9";
      ELSIF int( 8)='1' THEN  RETURN x"8";
      ELSIF int( 7)='1' THEN  RETURN x"7";
      ELSIF int( 6)='1' THEN  RETURN x"6";
      ELSIF int( 5)='1' THEN  RETURN x"5";
      ELSIF int( 4)='1' THEN  RETURN x"4";
      ELSIF int( 3)='1' THEN  RETURN x"3";
      ELSIF int( 2)='1' THEN  RETURN x"2";
      ELSIF int( 1)='1' THEN  RETURN x"1";
      ELSE                    RETURN x"0";
      END IF;
    END;
    
    ----------------------------------------------
    FUNCTION encode(int : unsigned(15 DOWNTO 1)) RETURN unsigned IS
      VARIABLE b3 : std_logic;
      VARIABLE b210 : unsigned(2 DOWNTO 0);
      VARIABLE int8 : unsigned(7 DOWNTO 0);
    BEGIN
      IF int(15 DOWNTO 8)="00000000" THEN
        b3:='0';
        int8:=int(7 DOWNTO 1) & '0';
      ELSE
        b3:='1';
        int8:=int(15 DOWNTO 8);
      END IF;
      IF    int8( 7)='1' THEN b210:="111";
      ELSIF int8( 6)='1' THEN b210:="110";
      ELSIF int8( 5)='1' THEN b210:="101";
      ELSIF int8( 4)='1' THEN b210:="100";
      ELSIF int8( 3)='1' THEN b210:="011";
      ELSIF int8( 2)='1' THEN b210:="010";
      ELSIF int8( 1)='1' THEN b210:="001";
      ELSE                    b210:="000";
      END IF;
      
      RETURN b3 & b210;
    END;
    
    ----------------------------------------------
    
  BEGIN
    IF rising_edge(clk) THEN      
      -- Encodage IRL
      hs_int0<=softint0 OR hardint0;
      hs_int1<=softint1 OR hardint1;
      hs_int2<=softint2 OR hardint2;
      hs_int3<=softint3 OR hardint3;
      irl0<=encode(hs_int0);
      irl1<=encode(hs_int1);
      irl2<=encode(hs_int2);
      irl3<=encode(hs_int3);
    END IF;
  END PROCESS Encodeur;
  
END ARCHITECTURE rtl;
