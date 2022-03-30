--------------------------------------------------------------------------------
-- TEM : TS
-- Horloge temps réel + NVRAM
--------------------------------------------------------------------------------
-- DO 9/2010
--------------------------------------------------------------------------------
-- ST M48T08 TimeKeeper 8KB
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

-- 1FF8                         1 1111 1111 10..
-- 1FFC                         1 1111 1111 11..

--            40    36  32    28  24    20  16    12   8     4   0
-- RTCINIT : 7D | 10Y | Y | 10M | M | 10D | D | 10H | H | 10S | S
-- 7D : 0..6 : Week

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.plomb_pack.ALL;
USE work.ts_pack.ALL;

ENTITY ts_rtc IS
  GENERIC (
    SYSFREQ : natural := 50000000);  
  PORT (
    sel : IN  std_logic;
    w   : IN  type_pvc_w;
    r   : OUT type_pvc_r;
    
    rtcinit : IN unsigned(43 DOWNTO 0);
    rtcset  : IN std_logic;
    
    -- Global
    clk      : IN std_logic;
    reset_na : IN std_logic
    );
END ENTITY ts_rtc;

--##############################################################################

ARCHITECTURE rtl OF ts_rtc IS

  -- Samedi 1er janvier 2011 0:00:00
  --CONSTANT CONF_DATE : unsigned(23 DOWNTO 0) := x"11" & x"01" & x"01";
  --CONSTANT CONF_JOUR : unsigned(2 DOWNTO 0) := "110";

  -- Mercredi 1er janvier 2014 0:00:00
  CONSTANT CONF_DATE : unsigned(23 DOWNTO 0) := x"14" & x"01" & x"01";
  CONSTANT CONF_JOUR : unsigned(2 DOWNTO 0) := "011";
  
  CONSTANT PERIODE : natural := SYSFREQ;
  SIGNAL cpt : natural RANGE 0 TO SYSFREQ :=0;
  
  SIGNAL pps : std_logic;

  SIGNAL cpt_y : uv8 :=CONF_DATE(23 DOWNTO 16); -- 00 .. 99
  SIGNAL cpt_m : uv8 :=CONF_DATE(15 DOWNTO 8); --  1 .. 12
  SIGNAL cpt_d : uv8 :=CONF_DATE(7 DOWNTO 0); --  1 .. 31
  SIGNAL cpt_j : unsigned(2 DOWNTO 0):=CONF_JOUR; -- 1 .. 7
  SIGNAL cpt_h : uv8 :=x"00"; -- 00 .. 23
  SIGNAL cpt_i : uv8 :=x"00"; -- 00 .. 59
  SIGNAL cpt_s : uv8 :=x"00"; -- 00 .. 59

  SIGNAL m_r : type_pvc_r;
  SIGNAL m_w : type_pvc_w;
  
  SIGNAL mem_y : uv8;
  SIGNAL mem_m : uv5;
  SIGNAL mem_d : uv6;
  SIGNAL mem_j : uv3;
  SIGNAL mem_h : uv6;
  SIGNAL mem_i : uv7;
  SIGNAL mem_s : uv7;
  
  SIGNAL cr,cw,st : std_logic;

  SIGNAL a_delay : unsigned(12 DOWNTO 2);
  
  FUNCTION bcd_inc (CONSTANT i : unsigned(7 DOWNTO 0))
    RETURN unsigned IS
  BEGIN
    IF i(3 DOWNTO 0)=x"9" THEN
      RETURN (i(7 DOWNTO 4)+x"1") & x"0";
    ELSE
      RETURN i(7 DOWNTO 4) & (i(3 DOWNTO 0)+x"1");
    END IF;
  END bcd_inc;

--------------------------------------------------------------------------------
  
BEGIN

  -- 1 Pulse Per Second
  Sync_PPS: PROCESS (clk)
  BEGIN
    IF rising_edge(clk) THEN
      IF cpt=PERIODE-1 THEN
        pps<=NOT st;
        cpt<=0;
      ELSE
        pps<='0';
        cpt<=cpt+1;
      END IF;
    END IF;
  END PROCESS Sync_PPS;

  Sync_HTR: PROCESS (clk,reset_na)
    VARIABLE s_x,i_x,h_x,j_x,d_x,m_x,y_x : boolean;
  BEGIN
    IF reset_na='0' THEN
      cr<='0';
      cw<='0';
      st<='0';
    ELSIF rising_edge(clk) THEN
      ------------------------------------------
      s_x:=(cpt_s=x"59"); -- seconde
      i_x:=(cpt_i=x"59"); -- minute
      h_x:=(cpt_h=x"23"); -- heure
      j_x:=(cpt_j="111"); -- jour
      IF cpt_m=x"04" OR cpt_m=x"06" OR cpt_m=x"09" OR cpt_m=x"11" THEN
        -- Avril, Juin, Septembre, Novembre
        d_x:=(cpt_d=x"30"); -- date
      ELSIF cpt_m=x"02" THEN
        -- Fevrier
        IF cpt_y(1 DOWNTO 0)="00" THEN
          d_x:=(cpt_d=x"29");
        ELSE
          d_x:=(cpt_d=x"28");
        END IF;
      ELSE
        -- Autres
        d_x:=(cpt_d=x"31");
      END IF;
      m_x:=(cpt_m=x"12");
      y_x:=(cpt_y=x"99");
      ------------------------------------------
      IF cr='0' THEN
        mem_y<=cpt_y;
        mem_m<=cpt_m(4 DOWNTO 0);
        mem_d<=cpt_d(5 DOWNTO 0);
        mem_j<=cpt_j;
        mem_h<=cpt_h(5 DOWNTO 0);
        mem_i<=cpt_i(6 DOWNTO 0);
        mem_s<=cpt_s(6 DOWNTO 0);
      END IF;
      -- Ecritures
      IF w.req='1' AND w.wr='1' AND sel='1' THEN
        IF w.a(12 DOWNTO 2)="11111111110" THEN
          IF w.be(0)='1' THEN
            -- 1FF8 : W | R | S | CAL[4:0]
            cw<=w.dw(31);
            cr<=w.dw(30);
          END IF;
          IF w.be(1)='1' THEN
            -- 1FF9 : ST | Secondes[6:0]
            mem_s<=w.dw(22 DOWNTO 16);
            st<=w.dw(23);
          END IF;
          IF w.be(2)='1' THEN
            -- 1FFA : 0 | Minutes
            mem_i<=w.dw(14 DOWNTO 8); 
          END IF;
          IF w.be(3)='1' THEN
            -- 1FFB : 00 | Heures
            mem_h<=w.dw(5 DOWNTO 0);
          END IF;
        END IF;
        IF w.a(12 DOWNTO 2)="11111111111" THEN
          IF w.be(0)='1' THEN
            -- 1FFC : 00000 | Jour
            mem_j<=w.dw(26 DOWNTO 24);
          END IF;
          IF w.be(1)='1' THEN
            -- 1FFD : 00 | Date
            mem_d<=w.dw(21 DOWNTO 16);
          END IF;
          IF w.be(2)='1' THEN
            -- 1FFE : 000 | Mois
            mem_m<=w.dw(12 DOWNTO 8); 
          END IF;
          IF w.be(3)='1' THEN
            -- 1FFF : Année
            mem_y<=w.dw(7 DOWNTO 0);
          END IF;
        END IF;
      END IF;

      -- Comptage
      IF cw='1' THEN
        -- Registres figés
        cpt_y<=mem_y;
        cpt_m<="000" & mem_m;
        cpt_d<="00" & mem_d;
        cpt_j<=mem_j;
        cpt_h<="00" & mem_h;
        cpt_i<='0' & mem_i;
        cpt_s<='0' & mem_s;
      ELSE
        IF pps='1' THEN
          IF s_x THEN
            cpt_s<=x"00";
            IF i_x THEN
              cpt_i<=x"00";
              IF h_x THEN
                cpt_h<=x"00";
                IF j_x THEN
                  cpt_j<="001";
                ELSE
                  cpt_j<=cpt_j+"001";
                END IF;
                IF d_x THEN
                  cpt_d<=x"01";
                  IF m_x THEN
                    cpt_m<=x"01";
                    IF y_x THEN
                      cpt_y<=x"00";
                    ELSE
                      cpt_y<=bcd_inc(cpt_y);
                    END IF;
                  ELSE
                    cpt_m<=bcd_inc(cpt_m);
                  END IF;
                ELSE
                  cpt_d<=bcd_inc(cpt_d);
                END IF;
              ELSE
                cpt_h<=bcd_inc(cpt_h);
              END IF;
            ELSE
              cpt_i<=bcd_inc(cpt_i);
            END IF;
          ELSE
            cpt_s<=bcd_inc(cpt_s);
          END IF;
        END IF;
      END IF;

      a_delay<=w.a(12 DOWNTO 2);
      
      ----------------------------------
      IF rtcset='1' THEN
        mem_y<=rtcinit(39 DOWNTO 32); -- Year
        mem_m<=rtcinit(28 DOWNTO 24); -- Month
        mem_d<=rtcinit(21 DOWNTO 16); -- Day
        mem_j<=rtcinit(42 DOWNTO 40); -- Day week
        mem_h<=rtcinit(13 DOWNTO  8); -- Hour
        mem_s<=rtcinit( 6 DOWNTO  0); -- Sec
      END IF;
    END IF;
  END PROCESS Sync_HTR;
  
  W_GEN:PROCESS(w,sel)
  BEGIN
    m_w<=w;
    m_w.wr<=w.wr AND sel;   
  END PROCESS W_GEN;
  
  i_iramrtc: ENTITY work.iram_rtc -- 8kB
    PORT MAP (
      mem_w => m_w,
      mem_r => m_r,
      clk   => clk,
      reset_na => reset_na);
  
  R_Gen:PROCESS(w,m_r,cw,cr,st,
                mem_s,mem_i,mem_h,mem_j,mem_d,mem_m,mem_y,a_delay,sel)
  BEGIN
    r.ack<=w.req AND sel;
    IF a_delay="11111111110" THEN
      r.dr<=cw & cr & "000000" & st & mem_s & '0' & mem_i & "00" & mem_h;
    ELSIF a_delay="11111111111" THEN
      r.dr<="00000" & mem_j & "00" & mem_d & "000" & mem_m & mem_y;
    ELSE
      r.dr<=m_r.dr;
    END IF;
  END PROCESS R_Gen;
  
END ARCHITECTURE rtl;
