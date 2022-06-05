--------------------------------------------------------------------------------
-- TEM : TS
-- Timers
--------------------------------------------------------------------------------
-- DO 9/2010
--------------------------------------------------------------------------------
-- Timers Sun4m
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

-- <AFAIRE> Cohérence 64bits
-- <AVOIR>  Fonctionnement réel ! Arrêt du comptage automatique ?

-- 0_n000 : Processor Counter Limit register, User Timer MSW
--          [31] : Limit Reached
--          [30:9] : Limit [21:0]
--          [30:0] : Counter [53:23]

-- 0_n004 : Processor Counter Register, User Timer LSW
--          [31]   : Limit reached
--          [30:9] : Counter [21:0]

-- 0_n008 : Processor Counter Limit register, non resetting
--          [30:9] : Limit [21:0]

-- 0_n00C : Processor Counter User Timer Start / Stop
--          [0] : Start(1) / Stop(0)

-- 1_0000 : System Limit register

-- 1_0004 : System Counter register

-- 1_0008 : System Limit register, non resetting

-- 1_000C : Reserved

-- 1_0010 : Timer Configuration register
--          [0] : Processor : User Timer(1) / Counter(0)

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.plomb_pack.ALL;
USE work.ts_pack.ALL;

ENTITY ts_timer IS
  GENERIC (
    SYSFREQ : natural;
    CPU0    : boolean;
    CPU1    : boolean;
    CPU2    : boolean;
    CPU3    : boolean);  
  PORT (
    sel    : IN  std_logic;
    w      : IN  type_pvc_w;
    r      : OUT type_pvc_r;
    int_s  : OUT std_logic; -- System Timer Interrupt (10)
    int_p0 : OUT std_logic; -- Processor 0 Timer Interrupt (14)
    int_p1 : OUT std_logic; -- Processor 1 Timer Interrupt (14)
    int_p2 : OUT std_logic; -- Processor 2 Timer Interrupt (14)
    int_p3 : OUT std_logic; -- Processor 3 Timer Interrupt (14)
    stopa  : IN  std_logic;
    
    -- Global
    clk     : IN std_logic;
    reset_n : IN std_logic
    );
END ENTITY ts_timer;

--##############################################################################

ARCHITECTURE rtl OF ts_timer IS

  -- Comptage timers : 2MHz
  CONSTANT PULSE_PER : natural RANGE 0 TO 255 := SYSFREQ/2/1000000;
  SIGNAL cpt : natural RANGE 0 TO 255;
  SIGNAL pulse : std_logic;

  SIGNAL rsel : std_logic;

  TYPE arr_cpt IS ARRAY (natural RANGE <>) OF unsigned(53 DOWNTO 0);
  SIGNAL p_cpt  : arr_cpt(3 DOWNTO 0);
  SIGNAL p_mode : uv4; -- 0=Counter 1=User Timer
  SIGNAL p_run  : uv4; -- 0=Stop 1=Run
  SIGNAL p_ov   : uv4; -- Overflow
  
  SIGNAL s_cpt : unsigned(21 DOWNTO 0); -- System counter
  SIGNAL s_lim : unsigned(21 DOWNTO 0); -- System limit
  SIGNAL s_ov : std_logic;
  
  CONSTANT UNITE : unsigned(21 DOWNTO 0) := "0000000000000000000001";
  CONSTANT C1 : uv64 := (OTHERS =>'1');
  CONSTANT CPUEN : uv4 :=to_std_logic(CPU3) & to_std_logic(CPU2) &
                         to_std_logic(CPU1) & to_std_logic(CPU0);
  SIGNAL dr : uv32;
  
BEGIN
  
  -- Horloge 2MHz
  Pulsar: PROCESS (clk)
  BEGIN
    IF rising_edge(clk) THEN
      IF cpt=PULSE_PER-1 THEN
        pulse<='1';
        cpt<=0;
      ELSE
        pulse<='0';
        IF stopa='0' THEN
          cpt<=cpt+1;
        END IF;
      END IF;
    END IF;
  END PROCESS Pulsar;

  rsel<=w.req AND sel;
  
  Pendulette: PROCESS (clk)
    VARIABLE ad : uv2;
  BEGIN
    IF rising_edge(clk) THEN
      ----------------------------------------------
      -- Comptage
      IF pulse='1' THEN
        --------------- Procs. Timers
        FOR I IN 0 TO 3 LOOP
          IF p_mode(I)='0' THEN
            -- Timer/Counter : Comptage périodique sur 22 bits avec limite
            IF p_cpt(I)(21 DOWNTO 0)=p_cpt(I)(53 DOWNTO 32) THEN
              p_cpt(I)(21 DOWNTO 0)<=UNITE;
              p_ov(I)<='1';
            ELSIF p_cpt(I)(21 DOWNTO 0)=C1(21 DOWNTO 0) THEN
              p_cpt(I)(21 DOWNTO 0)<=UNITE;
            ELSE
              p_cpt(I)(21 DOWNTO 0)<=p_cpt(I)(21 DOWNTO 0)+UNITE;
            END IF;
          ELSE
            -- User Timer : Comptage 54 bits
            IF p_run(I)='1' THEN
              IF p_cpt(I)=C1(53 DOWNTO 0) THEN
                p_ov(I)<='1';
              END IF;
              p_cpt(I)<=p_cpt(I)+1;
            END IF;
          END IF;
        END LOOP;
        --------------- Sys. Timer
        IF s_cpt=s_lim THEN
          s_cpt<=UNITE;
          s_ov<='1';
        ELSIF s_cpt=C1(21 DOWNTO 0) THEN
          s_cpt<=UNITE;
        ELSE
          s_cpt<=s_cpt+UNITE;
        END IF;
        
      END IF;
      
      ----------------------------------------------
      -- Lectures & Ecritures
      
      ----------------------------------------------
      -- 0_n000 : Processor Counter Limit register, User Timer MSW
      FOR I IN 0 TO 3 LOOP
        ad:=to_unsigned(I,2);
        IF rsel='1' AND w.a(16 DOWNTO 12)="000" & ad AND w.a(3 DOWNTO 2)="00"
          AND CPUEN(I)='1' THEN
          IF w.be="1111" AND w.wr='1' THEN
            p_cpt(I)(53 DOWNTO 23)<=w.dw(30 DOWNTO 0);
            IF p_mode(I)='0' THEN
              p_cpt(I)(22 DOWNTO 0)<='0' & UNITE;
            END IF;
          END IF;
          p_ov(I)<='0';
          IF p_mode(I)='0' THEN
            dr<=p_ov(I) & p_cpt(I)(53 DOWNTO 32) & "000000000";
          ELSE
            dr<=p_ov(I) & p_cpt(I)(53 DOWNTO 23);
          END IF;
        END IF;

        -- 0_n004 : Processor Counter Register, User Timer LSW
        IF rsel='1' AND w.a(16 DOWNTO 12)="000" & ad AND w.a(3 DOWNTO 2)="01"
          AND CPUEN(I)='1' THEN
          -- 'Writeable as User Timer LSW, read-only as Counter Register'
          IF w.be="1111" AND w.wr='1' AND p_mode(I)='1' THEN
            p_cpt(I)(22 DOWNTO 0)<=w.dw(31 DOWNTO 9);
            p_ov(I)<='0';
          END IF;
          IF p_mode(I)='0' THEN
            dr<=p_ov(I) & p_cpt(I)(21 DOWNTO 0) & "000000000";
          ELSE
            dr<=p_cpt(I)(22 DOWNTO 0) & "000000000";        
          END IF;
        END IF;

        -- 0_n008 : Processor Counter Limit register, non resetting
        IF rsel='1' AND w.a(16 DOWNTO 12)="000" & ad AND w.a(3 DOWNTO 2)="10"
          AND CPUEN(I)='1' THEN
          IF w.be="1111" AND w.wr='1' AND p_mode(I)='0' THEN
            p_cpt(I)(53 DOWNTO 23)<=w.dw(30 DOWNTO 0);
          END IF;
          p_ov(I)<='0';
          dr<=p_ov(I) & p_cpt(I)(53 DOWNTO 32) & "000000000";
        END IF;

        -- 0_n00C : Processor Counter User Timer Start / Stop
        IF rsel='1' AND w.a(16 DOWNTO 12)="000" & ad AND w.a(3 DOWNTO 2)="11"
          AND CPUEN(I)='1' THEN
          IF w.be(3)='1' AND w.wr='1' THEN
            p_run(I)<=w.dw(I);
          END IF;
          dr<="0000000000000000000000000000000" & p_run(I);
        END IF;
      END LOOP;
      ----------------------------------------------
      -- 1_0000 : System Limit register
      IF rsel='1' AND w.a(16)='1' AND w.a(4 DOWNTO 2)="000" THEN
        IF w.be="1111" AND w.wr='1' THEN
          s_lim<=w.dw(30 DOWNTO 9);
          s_cpt<=UNITE;
        END IF;
        s_ov<='0';
        dr<=s_ov & s_lim & "000000000";
      END IF;
      
      -- 1_0004 : System Counter register
      IF rsel='1' AND w.a(16)='1' AND w.a(4 DOWNTO 2)="001" THEN
        dr<=s_ov & s_cpt & "000000000";
      END IF;
      
      -- 1_0008 : System Limit register, non resetting
      IF rsel='1' AND w.a(16)='1' AND w.a(4 DOWNTO 2)="010" THEN
        IF w.be="1111" AND w.wr='1' THEN
          s_lim<=w.dw(30 DOWNTO 9);
        END IF;
        s_ov<='0';
        dr<=s_ov & s_lim & "000000000";
      END IF;

      -- 1_0010 : Timer Configuration register
      IF rsel='1' AND w.a(16)='1' AND w.a(4 DOWNTO 2)="100" THEN
        IF w.be(3)='1' AND w.wr='1' THEN
          p_mode<=w.dw(3 DOWNTO 0) AND CPUEN;
        END IF;
        dr<="0000000000000000000000000000" & p_mode;
      END IF;

      ----------------------------------------------
      IF reset_n='0' THEN
        p_ov<="0000";
        p_mode<="0000";
        p_run<="0000";
        p_cpt(0)<=x"00000000" & UNITE;
        p_cpt(1)<=x"00000000" & UNITE;
        p_cpt(2)<=x"00000000" & UNITE;
        p_cpt(3)<=x"00000000" & UNITE;
        
        s_cpt<=UNITE;
        s_lim<=(OTHERS => '0');
        s_ov<='0';
      END IF;
    END IF;    
  END PROCESS Pendulette;
  
  -- Relectures
  R_GEN:PROCESS(dr,rsel)
  BEGIN
    r.ack<=rsel;
    r.dr<=dr;
  END PROCESS R_GEN;
  
  -- Interruptions
  int_s<=s_ov;
  int_p0<=p_ov(0) AND NOT p_mode(0) AND CPUEN(0);
  int_p1<=p_ov(1) AND NOT p_mode(1) AND CPUEN(1);
  int_p2<=p_ov(2) AND NOT p_mode(2) AND CPUEN(2);
  int_p3<=p_ov(3) AND NOT p_mode(3) AND CPUEN(3);
    
END ARCHITECTURE rtl;
