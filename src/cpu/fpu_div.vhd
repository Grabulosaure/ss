--------------------------------------------------------------------------------
-- TEM : TACUS
-- Unité flottante : Divisions et Racine Carrée
--------------------------------------------------------------------------------
-- DO 6/2011
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################


-- <AVOIR> : Bugs diviseurs SRT
--                                     SIMPLE        DOUBLE

-- FDIV_MODE :
--  0 : Non Restoring      DIV/SQRT       25            54
--  1 : SRT Radix 2        DIV/SQRT       27            56
--  2 : SRT Radix 4        DIV/SQRT       14            29

-- Division/Racine SRT base 2 et base 4, carry-save,
-- d'après Peter Kornerup 'Digit Selection for SRT Division and Square Root'

--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

USE work.base_pack.ALL;
USE work.fpu_pack.ALL;
USE work.cpu_conf_pack.ALL;
--pragma synthesis_off
USE work.fpu_sim_pack.ALL;
--pragma synthesis_on

--------------------------------------------------------------------------------
ENTITY  fpu_div IS
  GENERIC (
    TECH        : natural);
  PORT (
    div_sd      : IN  std_logic;            -- 0=Simple 1=Double
    div_dr      : IN  std_logic;            -- 0=DIV 1=SQRT
    div_flush   : IN  std_logic;
    div_start   : IN  std_logic;
    div_end     : OUT std_logic;
    div_busy    : OUT std_logic;
    div_fs1_man : IN  unsigned(53 DOWNTO 0);
    div_fs2_man : IN  unsigned(52 DOWNTO 0);
    div_fs_man  : OUT unsigned(54 DOWNTO 0);
    div_inx     : OUT std_logic;
    
    reset_na    : IN std_logic;            -- Reset asynchrone
    clk         : IN std_logic             -- Horloge
    );
END ENTITY fpu_div;

--------------------------------------------------------------------------------

ARCHITECTURE rtl OF fpu_div IS
  SIGNAL dnr_r : unsigned(57 DOWNTO 0);
  SIGNAL dnr_q,dnr_m : unsigned(54 DOWNTO 0);
  SIGNAL dnr_quo : unsigned(54 DOWNTO 0);
  SIGNAL dnr_inx : std_logic;
  SIGNAL dnr_i : natural RANGE 0 TO 63;
  SIGNAL dnr_sd : std_logic;
  SIGNAL div_bsy : std_logic;
  SIGNAL srt_x,srt_xp : unsigned(60 DOWNTO 0);
  SIGNAL srt_m : unsigned(60 DOWNTO 0);
  SIGNAL srt_r_c,srt_r_d : unsigned(60 DOWNTO 0);
  SIGNAL srt_i : natural RANGE 0 TO 63;
  SIGNAL srt_j : natural RANGE 0 TO 31;
  SIGNAL div_ov : std_logic;
  
  --------------------------------------
  -- Addition Carry-Save
  PROCEDURE cs_add61 (
    VARIABLE s_d : OUT unsigned(60 DOWNTO 0);
    VARIABLE s_c : OUT unsigned(60 DOWNTO 0);
    CONSTANT e_d : IN  unsigned(60 DOWNTO 0);
    CONSTANT e_c : IN  unsigned(60 DOWNTO 0);
    CONSTANT v   : IN  unsigned(60 DOWNTO 0);
    CONSTANT c   : IN  std_logic) IS
    VARIABLE m : unsigned(60 DOWNTO 0);
  BEGIN
    m:=e_d XOR v XOR (e_c(59 DOWNTO 0) & c);
    s_c:=(e_d AND v) OR
          (e_d AND (e_c(59 DOWNTO 0) & c)) OR
          (v AND (e_c(59 DOWNTO 0) & c));
    s_d:=m;
  END cs_add61;
  --------------------------------------
  -- Table SRT base 4
    CONSTANT XK : natural := 2;
  TYPE arr_srt4_coef IS ARRAY(0 TO 1023) OF natural RANGE 0 TO 2;
  
  CONSTANT SRT4_COEF : arr_srt4_coef := ( 
     0, 0, 0, 0, 0, 0, 0, 0, -- 000.0000
     0, 0, 0, 0, 0, 0, 0, 0, -- 000.0001
     0, 0, 0, 0, 0, 0, 0, 0, -- 000.0010
     0, 0, 0, 0, 0, 0, 0, 0, -- 000.0011
     0, 0, 0, 0, 0, 0, 0, 0, -- 000.0100
     0, 0, 0, 0, 0, 0, 0, 0, -- 000.0101
     0, 0, 0, 0, 0, 0, 0, 0, -- 000.0110
     1, 1, 0, 0, 0, 0, 0, 0, -- 000.0111
     1, 1, 1, 0, 0, 0, 0, 0, -- 000.1000
     1, 1, 1, 1, 1, 0, 0, 0, -- 000.1001
     1, 1, 1, 1, 1, 1, 0, 0, -- 000.1010
     1, 1, 1, 1, 1, 1, 1, 0, -- 000.1011
     1, 1, 1, 1, 1, 1, 1, 1, -- 000.1100
     1, 1, 1, 1, 1, 1, 1, 1, -- 000.1101
     1, 1, 1, 1, 1, 1, 1, 1, -- 000.1110
     1, 1, 1, 1, 1, 1, 1, 1, -- 000.1111
     1, 1, 1, 1, 1, 1, 1, 1, -- 001.0000
     1, 1, 1, 1, 1, 1, 1, 1, -- 001.0001
     1, 1, 1, 1, 1, 1, 1, 1, -- 001.0010
     1, 1, 1, 1, 1, 1, 1, 1, -- 001.0011
     1, 1, 1, 1, 1, 1, 1, 1, -- 001.0100
     1, 1, 1, 1, 1, 1, 1, 1, -- 001.0101
     1, 1, 1, 1, 1, 1, 1, 1, -- 001.0110
     1, 1, 1, 1, 1, 1, 1, 1, -- 001.0111
     1, 1, 1, 1, 1, 1, 1, 1, -- 001.1000
     2, 1, 1, 1, 1, 1, 1, 1, -- 001.1001
     2, 1, 1, 1, 1, 1, 1, 1, -- 001.1010
     2, 1, 1, 1, 1, 1, 1, 1, -- 001.1011
     2, 2, 1, 1, 1, 1, 1, 1, -- 001.1100
     2, 2, 1, 1, 1, 1, 1, 1, -- 001.1101
     2, 2, 1, 1, 1, 1, 1, 1, -- 001.1110
     2, 2, 2, 1, 1, 1, 1, 1, -- 001.1111
     2, 2, 2, 1, 1, 1, 1, 1, -- 010.0000
     2, 2, 2, 2, 1, 1, 1, 1, -- 010.0001
     2, 2, 2, 2, 1, 1, 1, 1, -- 010.0010
     2, 2, 2, 2, 1, 1, 1, 1, -- 010.0011
     2, 2, 2, 2, 2, 1, 1, 1, -- 010.0100
     2, 2, 2, 2, 2, 1, 1, 1, -- 010.0101
     2, 2, 2, 2, 2, 1, 1, 1, -- 010.0110
     2, 2, 2, 2, 2, 2, 1, 1, -- 010.0111
     2, 2, 2, 2, 2, 2, 1, 1, -- 010.1000
     2, 2, 2, 2, 2, 2, 2, 1, -- 010.1001
     2, 2, 2, 2, 2, 2, 2, 1, -- 010.1010
     2, 2, 2, 2, 2, 2, 2, 1, -- 010.1011
     2, 2, 2, 2, 2, 2, 2, 1, -- 010.1100
     2, 2, 2, 2, 2, 2, 2, 1, -- 010.1101
     2, 2, 2, 2, 2, 2, 2, 1, -- 010.1110
     2, 2, 2, 2, 2, 2, 2, 2, -- 010.1111
     2, 2, 2, 2, 2, 2, 2, 2, -- 011.0000
    XK, 2, 2, 2, 2, 2, 2, 2, -- 011.0001
    XK, 2, 2, 2, 2, 2, 2, 2, -- 011.0010
    XK, 2, 2, 2, 2, 2, 2, 2, -- 011.0011
    XK, 2, 2, 2, 2, 2, 2, 2, -- 011.0100
    XK, 2, 2, 2, 2, 2, 2, 2, -- 011.0101
    XK,XK, 2, 2, 2, 2, 2, 2, -- 011.0110
    XK,XK, 2, 2, 2, 2, 2, 2, -- 011.0111
    XK,XK, 2, 2, 2, 2, 2, 2, -- 011.1000
    XK,XK, 2, 2, 2, 2, 2, 2, -- 011.1001
    XK,XK, 2, 2, 2, 2, 2, 2, -- 011.1010
    XK,XK, 2, 2, 2, 2, 2, 2, -- 011.1011
    XK,XK, 2, 2, 2, 2, 2, 2, -- 011.1100
    XK,XK, 2, 2, 2, 2, 2, 2, -- 011.1101
    XK,XK, 2, 2, 2, 2, 2, 2, -- 011.1110
    XK,XK, 2, 2, 2, 2, 2, 2, -- 011.1111
    XK,XK,XK, 2, 2, 2, 2, 2, -- 100.0000
    XK,XK,XK,XK, 2, 2, 2, 2, -- 100.0001
    XK,XK,XK,XK, 2, 2, 2, 2, -- 100.0010
    XK,XK,XK,XK, 2, 2, 2, 2, -- 100.0011
    XK,XK,XK,XK, 2, 2, 2, 2, -- 100.0100
    XK,XK,XK,XK, 2, 2, 2, 2, -- 100.0101
    XK,XK,XK,XK,XK, 2, 2, 2, -- 100.0110
    XK,XK,XK,XK,XK, 2, 2, 2, -- 100.0111
    XK,XK,XK,XK,XK, 2, 2, 2, -- 100.1000
    XK,XK,XK,XK,XK, 2, 2, 2, -- 100.1001
    XK,XK,XK,XK,XK, 2, 2, 2, -- 100.1010
    XK,XK,XK,XK,XK,XK, 2, 2, -- 100.1011
    XK,XK,XK,XK,XK,XK, 2, 2, -- 100.1100
    XK,XK,XK,XK,XK,XK, 2, 2, -- 100.1101
    XK,XK,XK,XK,XK,XK, 2, 2, -- 100.1110
    XK,XK,XK,XK,XK,XK, 2, 2, -- 100.1111
    XK,XK,XK,XK,XK,XK, 2, 2, -- 101.0000
    XK,XK,XK,XK,XK,XK,XK, 2, -- 101.0001
    XK,XK,XK,XK,XK,XK,XK, 2, -- 101.0010
    XK,XK,XK,XK,XK,XK,XK, 2, -- 101.0011
    XK,XK,XK,XK,XK,XK,XK, 2, -- 101.0100
    XK,XK,XK,XK,XK,XK,XK, 2, -- 101.0101
    XK,XK,XK,XK,XK,XK,XK,XK, -- 101.0110
    XK,XK,XK,XK,XK,XK,XK,XK, -- 101.0111
    XK,XK,XK,XK,XK,XK,XK,XK, -- 101.1000
    XK,XK,XK,XK,XK,XK,XK,XK, -- 101.1001
    XK,XK,XK,XK,XK,XK,XK,XK, -- 101.1010
    XK,XK,XK,XK,XK,XK,XK,XK, -- 101.1011
    XK,XK,XK,XK,XK,XK,XK,XK, -- 101.1100
    XK,XK,XK,XK,XK,XK,XK,XK, -- 101.1101
    XK,XK,XK,XK,XK,XK,XK,XK, -- 101.1110
    XK,XK,XK,XK,XK,XK,XK,XK, -- 101.1111
    XK,XK,XK,XK,XK,XK,XK,XK, -- 110.0000
    XK,XK,XK,XK,XK,XK,XK,XK, -- 110.0001
    XK,XK,XK,XK,XK,XK,XK,XK, -- 110.0010
    XK,XK,XK,XK,XK,XK,XK,XK, -- 110.0011
    XK,XK,XK,XK,XK,XK,XK,XK, -- 110.0100
    XK,XK,XK,XK,XK,XK,XK,XK, -- 110.0101
    XK,XK,XK,XK,XK,XK,XK,XK, -- 110.0110
    XK,XK,XK,XK,XK,XK,XK,XK, -- 110.0111
    XK,XK,XK,XK,XK,XK,XK,XK, -- 110.1000
    XK,XK,XK,XK,XK,XK,XK,XK, -- 110.1001
    XK,XK,XK,XK,XK,XK,XK,XK, -- 110.1010
    XK,XK,XK,XK,XK,XK,XK,XK, -- 110.1011
    XK,XK,XK,XK,XK,XK,XK,XK, -- 110.1100
    XK,XK,XK,XK,XK,XK,XK,XK, -- 110.1101
    XK,XK,XK,XK,XK,XK,XK,XK, -- 110.1110
    XK,XK,XK,XK,XK,XK,XK,XK, -- 110.1111
    XK,XK,XK,XK,XK,XK,XK,XK, -- 111.0000
    XK,XK,XK,XK,XK,XK,XK,XK, -- 111.0001
    XK,XK,XK,XK,XK,XK,XK,XK, -- 111.0010
    XK,XK,XK,XK,XK,XK,XK,XK, -- 111.0011
    XK,XK,XK,XK,XK,XK,XK,XK, -- 111.0100
    XK,XK,XK,XK,XK,XK,XK,XK, -- 111.0101
    XK,XK,XK,XK,XK,XK,XK,XK, -- 111.0110
    XK,XK,XK,XK,XK,XK,XK,XK, -- 111.0111
    XK,XK,XK,XK,XK,XK,XK,XK, -- 111.1000
    XK,XK,XK,XK,XK,XK,XK,XK, -- 111.1001
    XK,XK,XK,XK,XK,XK,XK,XK, -- 111.1010
    XK,XK,XK,XK,XK,XK,XK,XK, -- 111.1011
    XK,XK,XK,XK,XK,XK,XK,XK, -- 111.1100
    XK,XK,XK,XK,XK,XK,XK,XK, -- 111.1101
    XK,XK,XK,XK,XK,XK,XK,XK, -- 111.1110
    XK,XK,XK,XK,XK,XK,XK,XK  -- 111.1111
    );
  CONSTANT ZERO : uv64 := (OTHERS => '0');
BEGIN
  
  ------------------------------------------------------------------------------
  -- Division et Racine "sans restoration"
  Gen_DIV_NR:IF TECHS(TECH).fdiv=0 GENERATE

    div_busy<=div_bsy;
    
    Algo_DIV_NR:PROCESS (clk,reset_na)
      VARIABLE r_v : unsigned(57 DOWNTO 0);
    BEGIN
      IF reset_na='0' THEN
        div_bsy<='0';
      ELSIF rising_edge(clk) THEN
        IF div_start='1' THEN
          dnr_i<=0;
          div_bsy<='1';
          div_end<='0';
          dnr_inx<='1';
          dnr_sd<=div_sd;
        ELSE
          dnr_i<=(dnr_i+1) MOD 64;
          IF (dnr_i=25 AND dnr_sd='0') OR (dnr_i=54 AND dnr_sd='1') THEN
            div_end<=div_bsy;
            div_bsy<='0';
          ELSE
            div_end<='0';
          END IF;
        END IF;

        IF div_bsy/='1' THEN
          dnr_m<=(OTHERS => '0');
          IF div_dr='0' THEN
            -- Division
            dnr_q<='0' & div_fs2_man & '0';
          ELSE
            -- Racine
            dnr_q<=(OTHERS => '0');
            dnr_m(54)<='1';
          END IF;
          dnr_r<="00" & div_fs1_man & "00";    -- Reste
        ELSE
          dnr_m<='0' & dnr_m(54 DOWNTO 1);
          IF dnr_r(57)='0' THEN
            r_v:=(dnr_r(56 DOWNTO 0) & '0') -
                  ('0' & dnr_q & "00") - ("00" & dnr_m & '0');
            dnr_q<=dnr_q+dnr_m;
          ELSE
            r_v:=(dnr_r(56 DOWNTO 0) & '0') +
                  ('0' & dnr_q & "00") - ("00" & dnr_m & '0');
            dnr_q<=dnr_q-dnr_m;
          END IF;
          dnr_r<=r_v;
          IF (dnr_sd='1' AND r_v=ZERO(57 DOWNTO 0)) OR
            (dnr_sd='0' AND r_v(57 DOWNTO 28)=ZERO(28 DOWNTO 0)) THEN
            dnr_inx<='0';
          END IF;
          IF dnr_sd='1' THEN
            dnr_quo<=dnr_quo(53 DOWNTO 0) & NOT r_v(57);
          ELSE
            dnr_quo<=dnr_quo(53 DOWNTO 29) & NOT r_v(57) &
                      ZERO(28 DOWNTO 0);
          END IF;
        END IF;
        
        -- <AVOIR> synchronisation valeur finale Sticky division
        IF div_flush='1' THEN
          div_bsy<='0';
        END IF;
      END IF;
    END PROCESS Algo_DIV_NR;
    
    div_fs_man<=dnr_quo;
    div_inx<=dnr_inx;
    
  END GENERATE Gen_DIV_NR;
  
  ------------------------------------------------------------------------------
  -- Division et Racine SRT base 2
  Gen_DIV_SRT2:IF TECHS(TECH).fdiv=1 GENERATE

    div_busy<=div_bsy;
    
    Algo_DIV_SRT2:PROCESS (clk,reset_na)
      VARIABLE r_c_v,r_d_v     : unsigned(60 DOWNTO 0);
      VARIABLE add1_v,add2_v   : unsigned(60 DOWNTO 0);
      VARIABLE add1c_v,add2c_v : std_logic;
      VARIABLE p_v  : unsigned(7 DOWNTO 0);
      VARIABLE ru_v : unsigned(8 DOWNTO 0);
      VARIABLE d_v : integer RANGE -1 TO 1;
      VARIABLE x_v : unsigned(60 DOWNTO 0);      
    BEGIN
      IF reset_na='0' THEN
        div_bsy<='0';
      ELSIF rising_edge(clk) THEN
        IF div_start='1' THEN
          -- Précalcul : R0=Y=dvd, X0=0, M0=1
          srt_r_d<="00" & div_fs1_man & "00000";             -- R=00d.vd
          srt_r_c<=ZERO(60 DOWNTO 0);
          
          srt_m<="0001" & ZERO(56 DOWNTO 0);      -- M=000.01 = 0.25
          
          srt_x <=ZERO(60 DOWNTO 0);               -- X = 000.0 = 0
          srt_xp<="111" & ZERO(57 DOWNTO 0);       -- X-1 = 111.0 = -1 
          srt_i<=0;
          div_bsy<='1';
          div_end<='0';
        ELSE
          IF srt_i<57 THEN
            srt_i<=srt_i+1;
          END IF;
          -- <AVOIR> Vérifier nombre d'itérations
          IF (srt_i=26 AND div_sd='0') OR (srt_i=55 AND div_sd='1') THEN
            div_end<=div_bsy;
            div_bsy<='0';
          ELSE
            div_end<='0';
          END IF;
          
          -- Il faut faire R*8 --> 3 chiffres après la virgule en plus
          -- Le reste peut atteindre 1, 1 chiffre avant la virgule
          -- Avec le signe, il en faut 1 de plus ! -->
          r_d_v:=srt_r_d;
          r_c_v:=srt_r_c;
          ru_v:=r_d_v(60 DOWNTO 52) + r_c_v(59 DOWNTO 51);
          p_v:=ru_v(8 DOWNTO 1);
          
          IF p_v(7)='0' THEN                    -- Positif
            IF p_v(6 DOWNTO 3)/="0000" THEN  -- >2
              d_v:=1;
            ELSE
              d_v:=0;
            END IF;
          ELSE
            p_v:=NOT p_v; -- - 1;                     -- Négatif
            IF p_v(6 DOWNTO 3)/="0000" THEN  -- >2
              d_v:=-1;
            ELSE
              d_v:=0;
            END IF;
          END IF;

          add2_v:=ZERO(60 DOWNTO 0);
          add2c_v:='0';
          CASE d_v IS
            WHEN  1 =>
              IF div_dr='0' THEN  -- R=R -1*Y
                add1_v:=NOT ("000" & div_fs2_man & "00000");
                add1c_v:='1';
              ELSE  -- R=R -1*(2*X) -1*M
                add1_v:=NOT (srt_x(59 DOWNTO 0) & '0');
                add1c_v:='1';
                add2_v:=NOT srt_m;
                add2c_v:='1';
              END IF;
              srt_xp<=srt_x;
              srt_xp(58-(srt_i+1))<='0';
              srt_x (58-(srt_i+1))<='1';
              
            WHEN -1 =>
              IF div_dr='0' THEN  -- R=R +1*Y
                add1_v:="000" & div_fs2_man & "00000";
                add1c_v:='0';
              ELSE  -- R=R +1*(2*X) -1*M
                add1_v:=srt_x(59 DOWNTO 0) & '0';
                add1c_v:='0';
                add2_v:=NOT srt_m;
                add2c_v:='1';
              END IF;
              srt_x<=srt_xp;
              srt_xp(58-(srt_i+1))<='0';
              srt_x (58-(srt_i+1))<='1';
              
            WHEN OTHERS =>
              -- d=0 : On ne change rien au reste r
              add1_v:=ZERO(60 DOWNTO 0);
              add1c_v:='0';
              srt_xp(58-(srt_i+1))<='1';
              srt_x (58-(srt_i+1))<='0'; -- Inutile...
              
          END CASE;

          cs_add61(r_d_v,r_c_v,r_d_v,r_c_v,add1_v,add1c_v);
          cs_add61(r_d_v,r_c_v,r_d_v,r_c_v,add2_v,add2c_v);
          
          r_d_v:=r_d_v(59 DOWNTO 0) & '0';   -- R=R*2
          r_c_v:=r_c_v(59 DOWNTO 0) & '0';
          srt_r_d<=r_d_v;
          srt_r_c<=r_c_v;
          srt_m<='0' & srt_m(60 DOWNTO 1);
        END IF;

        -- Calcul de l'arrondi.
        r_d_v:=srt_r_d+(srt_r_c(59 DOWNTO 0) & '0');
        IF r_d_v(60)='1' THEN
          -- Si le reste est négatif, on décrémente
          x_v:=srt_xp;
        ELSE
          x_v:=srt_x;
        END IF;
        
        IF div_bsy='1' THEN
          IF r_d_v=ZERO(60 DOWNTO 0) THEN
            div_inx<='0';
          ELSE
            div_inx<='1';
          END IF;
          
          div_fs_man<=x_v(57 DOWNTO 3);
        END IF;
        IF div_flush='1' THEN
          div_bsy<='0';
        END IF;
      END IF;
      
    END PROCESS Algo_DIV_SRT2;
  END GENERATE Gen_DIV_SRT2;

  ------------------------------------------------------------------------------
  -- Division et Racine SRT base 4
  Gen_DIV_SRT4:IF TECHS(TECH).fdiv=2 GENERATE

    div_busy<=div_bsy;
    
    Algo_DIV_SRT4:PROCESS (clk,reset_na)
      VARIABLE r_c_v,r_d_v     : unsigned(60 DOWNTO 0);
      VARIABLE add1_v,add2_v   : unsigned(60 DOWNTO 0);
      VARIABLE add1c_v,add2c_v : std_logic;
      VARIABLE p_v  : unsigned(7 DOWNTO 0);
      VARIABLE q_v  : unsigned(4 DOWNTO 0);
      VARIABLE ru_v : unsigned(8 DOWNTO 0);
      VARIABLE d_v : integer RANGE -2 TO 2;
      VARIABLE x_v : unsigned(60 DOWNTO 0);
    BEGIN
      IF reset_na='0' THEN
        div_bsy<='0';
      ELSIF rising_edge(clk) THEN
        IF div_start='1' THEN
          -- Précalcul : R0=Y=dvd, X0=0, M0=1
          srt_r_d<="000" & div_fs1_man & "0000";             -- R=000.dvd
          srt_r_c<=ZERO(60 DOWNTO 0);
          
          srt_m<="00001" & ZERO(55 DOWNTO 0);      -- M=000.01 = 0.25
          
          srt_x <=ZERO(60 DOWNTO 0);               -- X = 000.0 = 0
          srt_xp<="111" & ZERO(57 DOWNTO 0);       -- X-1 = 111.0 = -1 
          srt_j<=0;
          div_bsy<='1';
          div_end<='0';
          ELSE
            srt_j<=(srt_j+1) MOD 32;
          IF div_ov='1' THEN
            div_end<=div_bsy;
            div_bsy<='0';
          ELSE
            div_end<='0';
          END IF;
          
          IF (srt_j=13 AND div_sd='0') OR (srt_j=28 AND div_sd='1') THEN
            div_ov<=div_bsy;
          ELSE
            div_ov<='0';
          END IF;
          -- Il faut faire R*32 --> 5 chiffres après la virgule
          -- Pour la racine, R*64 --> 6 chiffres ALV
          -- Le reste peut atteindre 2.66 --> 2 chiffres avant la virgule
          -- Avec le signe, il en faut 1 de plus ! --> R[58:0]
          -- 58-56 . 55-50
          --   P1=32 * R0 pour division, 64 * R0 pour racine
          --   Pi=32 * Ri-1
          r_d_v:=srt_r_d;
          r_c_v:=srt_r_c;
          ru_v:=r_d_v(60 DOWNTO 52) + r_c_v(59 DOWNTO 51);
          IF div_dr='0' OR srt_j/=0 THEN
            p_v:=ru_v(8 DOWNTO 1);
          ELSE
            p_v:=ru_v(7 DOWNTO 0);
          END IF;

          --   Q1=16 * dvs pour division, 10 pour racine
          --   Qi=16 * dvs pour division, 32 * Xi-1 pour racine
          IF div_dr='0' THEN
            q_v:='0' & div_fs2_man(52 DOWNTO 49);           -- 8 < q < 15 
          ELSE
            IF srt_j=0 THEN
              q_v:="01010";
            ELSE
              q_v:=srt_x(57 DOWNTO 53);
            END IF;
            IF q_v(4)='1' THEN
              q_v:="01111";  -- Repliement colonne 16 racine
            END IF;
          END IF;
          IF p_v(7)='0' THEN                    -- Positif
            d_v:=SRT4_COEF(to_integer(p_v & q_v(2 DOWNTO 0)));
          ELSE
            p_v:=NOT p_v - 1;                   -- Négatif
            IF p_v(7)='1' THEN
              p_v:="00000000";
            END IF;
            d_v:=-SRT4_COEF(to_integer(p_v & q_v(2 DOWNTO 0)));
          END IF;
          
          add2_v:=ZERO(60 DOWNTO 0);
          add2c_v:='0';
          CASE d_v IS
            WHEN  1 =>
              IF div_dr='0' THEN  -- R=R -1*Y
                add1_v:=NOT ("000" & div_fs2_man & "00000");
                add1c_v:='1';
              ELSE  -- R=R -1*(2*X) -1*M
                add1_v:=NOT (srt_x(59 DOWNTO 0) & '0');
                add1c_v:='1';
                add2_v:=NOT srt_m;
                add2c_v:='1';
              END IF;
              IF srt_j<29 THEN
                srt_xp<=srt_x;
                srt_xp(59-2*(srt_j+1) DOWNTO 58-2*(srt_j+1))<="00";
                srt_x (59-2*(srt_j+1) DOWNTO 58-2*(srt_j+1))<="01";
              END IF;

            WHEN 2 =>
              IF div_dr='0' THEN  -- R=R -2*Y
                add1_v:=NOT ("00" & div_fs2_man & "000000");
                add1c_v:='1';
              ELSE  -- R=R -2*(2*X) -4*M
                add1_v:=NOT (srt_x(58 DOWNTO 0) & "00");
                add1c_v:='1';
                add2_v:=NOT (srt_m(58 DOWNTO 0) & "00");
                add2c_v:='1';
              END IF;
              IF srt_j<29 THEN
                srt_xp<=srt_x;
                srt_xp(59-2*(srt_j+1) DOWNTO 58-2*(srt_j+1))<="01";
                srt_x (59-2*(srt_j+1) DOWNTO 58-2*(srt_j+1))<="10";
              END IF;
              
            WHEN -1 =>
              IF div_dr='0' THEN  -- R=R +1*Y
                add1_v:="000" & div_fs2_man & "00000";
                add1c_v:='0';
              ELSE  -- R=R +1*(2*X) -1*M
                add1_v:=srt_x(59 DOWNTO 0) & '0';
                add1c_v:='0';
                add2_v:=NOT srt_m;
                add2c_v:='1';
              END IF;
              IF srt_j<29 THEN
                srt_x<=srt_xp;
                srt_xp(59-2*(srt_j+1) DOWNTO 58-2*(srt_j+1))<="10";
                srt_x (59-2*(srt_j+1) DOWNTO 58-2*(srt_j+1))<="11";
              END IF;

            WHEN -2 =>
              IF div_dr='0' THEN  -- R=R +2*Y
                add1_v:="00" & div_fs2_man & "000000";
                add1c_v:='0';
              ELSE  -- R=R + 2*(2*X) -4*M
                add1_v:=srt_x(58 DOWNTO 0) & "00";
                add1c_v:='0';
                add2_v:=NOT (srt_m(58 DOWNTO 0) & "00");
                add2c_v:='1';
              END IF;
              IF srt_j<29 THEN
                srt_x<=srt_xp;
                srt_xp(59-2*(srt_j+1) DOWNTO 58-2*(srt_j+1))<="01";
                srt_x (59-2*(srt_j+1) DOWNTO 58-2*(srt_j+1))<="10";
              END IF;
              
            WHEN OTHERS =>
              -- d=0 : On ne change rien au reste r
              add1_v:=ZERO(60 DOWNTO 0);
              add1c_v:='0';
              IF srt_j<29 THEN
                srt_xp(59-2*(srt_j+1) DOWNTO 58-2*(srt_j+1))<="11";
                srt_x (59-2*(srt_j+1) DOWNTO 58-2*(srt_j+1))<="00"; --Inutile...
              END IF;
              
          END CASE;

          cs_add61(r_d_v,r_c_v,r_d_v,r_c_v,add1_v,add1c_v);
          cs_add61(r_d_v,r_c_v,r_d_v,r_c_v,add2_v,add2c_v);
          
          r_d_v:=r_d_v(58 DOWNTO 0) & "00";   -- R=R*4
          r_c_v:=r_c_v(58 DOWNTO 0) & "00";
          srt_r_d<=r_d_v;
          srt_r_c<=r_c_v;
          srt_m<="00" & srt_m(60 DOWNTO 2);
        END IF;

        -- Calcul de l'arrondi.
        IF div_ov='1' THEN
          r_d_v:=srt_r_d+(srt_r_c(59 DOWNTO 0) & '0');
          IF r_d_v(60)='1' THEN
            -- Si le reste est négatif, on décrémente
            x_v:=srt_xp;
          ELSE
            x_v:=srt_x;
          END IF;

          IF div_bsy='1' THEN
            IF r_d_v=ZERO(60 DOWNTO 0) THEN
              div_inx<='0';
            ELSE
              div_inx<='1';
            END IF;

            IF div_dr='0' THEN
              div_fs_man<=x_v(55 DOWNTO 1);
            ELSE
              div_fs_man<=x_v(56 DOWNTO 2);
            END IF;
          END IF;
        END IF;
        IF div_flush='1' THEN
          div_bsy<='0';
        END IF;
      END IF;
      
    END PROCESS Algo_DIV_SRT4;
  END GENERATE Gen_DIV_SRT4;

END ARCHITECTURE rtl;
