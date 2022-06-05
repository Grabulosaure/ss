--------------------------------------------------------------------------------
-- TEM : TACUS
-- Unité flottante : Multiplications
--------------------------------------------------------------------------------
-- DO 6/2011
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

--                                         SIMPLE        DOUBLE
-- 0 : Multipliers 17x17 . Spartan6             1             2
-- 1 : Direct multiplication.  CycloneV         1             1

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
ENTITY  fpu_mul IS
  GENERIC (
    TECH        : natural :=TECH_SPARTAN6);
  PORT (
    mul_sd      : IN  std_logic;            -- 0=Simple 1=Double
    mul_flush   : IN  std_logic;
    mul_start   : IN  std_logic;
    mul_end     : OUT std_logic;
    mul_busy    : OUT std_logic;
    mul_stall   : OUT std_logic;
    mul_fs1_man : IN  unsigned(53 DOWNTO 0);
    mul_fs2_man : IN  unsigned(52 DOWNTO 0);
    mul_fs_man  : OUT unsigned(54 DOWNTO 0);
    mul_inx     : OUT std_logic;
    reset_n    : IN std_logic;            -- Reset asynchrone
    clk         : IN std_logic             -- Horloge
    );
END ENTITY fpu_mul;

--------------------------------------------------------------------------------

ARCHITECTURE rtl OF fpu_mul IS

  SIGNAL mul_i : natural RANGE 0 TO 1;
  SIGNAL mul_bsy : std_logic;
  SIGNAL sum_mem : unsigned(72 DOWNTO 0);
  SIGNAL or_mem : std_logic;
  CONSTANT ZERO : uv64 := (OTHERS => '0');
  

BEGIN
  
  GenMUL0:IF TECHS(TECH).fmul=0 GENERATE

    --  m5:=(OTHERS => '0');
    --  m1:=ah*bh;           -- [105..72] 34  (36+36) 2 [71..38]
    --  m2:=am*bh;           -- [ 88..55] 34  (36+19) 1 [54..21]
    --  m3:=ah*bm;           -- [ 88..55] 34  (36+19) 1 [54..21]
    --  m4:=am*bm;           -- [ 71..38] 34  (19+19) 0 [37.. 4]
    --  n3:=(OTHERS => '0');
    --  n4:=(OTHERS => '0');
    --  n1:=ax*bh;           -- [ 54..36] 19  (36+0)    [20.. 2]
    --  n2:=ah*bx;           -- [ 54..36] 19  (36+0)    [20.. 2]
    --  ll:=(OTHERS => '0');
    
    --  m5:=al*bh;           -- [ 71..38] 34  (36+2) 2
    --  m1:=ah*bl;           -- [ 71..38] 34  (36+2) 2
    --  m2:=am*bl;           -- [ 54..21] 34  (19+2) 1
    --  m3:=al*bm;           -- [ 54..21] 34  (19+2) 1
    --  m4:=al*bl;           -- [ 37.. 4] 34  (2+2)  0
    --  n3:=ax*bm;           -- [ 37..19] 19  (19+0)
    --  n4:=am*bx;           -- [ 37..19] 19  (19+0)    
    --  n1:=ax*bl;           -- [ 20.. 2] 19  (2+0)
    --  n2:=al*bx;           -- [ 20.. 2] 19  (2+0)
    --  ll:=ax*bx;           -- [  3.. 0] 4   (0+0)
    

    mul_stall<=mul_sd AND mul_start;
    mul_busy <=mul_bsy;

    CalcMul:PROCESS (clk,reset_n) IS
      VARIABLE a,b : unsigned(52 DOWNTO 0);
      VARIABLE ah,am,al,bh,bm,bl : unsigned(16 DOWNTO 0);
      VARIABLE ax,bx             : unsigned(1 DOWNTO 0);
      VARIABLE sum,sum2 : unsigned(72 DOWNTO 0);
      VARIABLE sumz : unsigned(57 DOWNTO 0);
      
      VARIABLE m1,m2,m3,m4,m5,m6,m7,m8,m9 : unsigned(33 DOWNTO 0);
      VARIABLE n1,n2,n3,n4                : unsigned(18 DOWNTO 0);
      VARIABLE ll : unsigned(3 DOWNTO 0);
      CONSTANT Z : unsigned(72 DOWNTO 0) := (OTHERS =>'0');

      VARIABLE b_hl,a_hl : unsigned(16 DOWNTO 0);
      VARIABLE a_x,b_x : unsigned(1 DOWNTO 0);
    BEGIN
      IF reset_n='0' THEN
        mul_bsy<='0';
        mul_end<='0';
      ELSIF rising_edge(clk) THEN
        -------------------------------------------------------
        IF mul_bsy='1' THEN
          mul_end<='1';
          mul_bsy<='0';
        END IF;
        IF mul_start='1' THEN
          IF mul_sd='0' THEN
            mul_end<='1';
            mul_bsy<='0';
          ELSE
            mul_end<='0';
            mul_bsy<='1';
          END IF;
        END IF;
        IF mul_start='0' AND mul_bsy='0' THEN
          mul_end<='0';
        END IF;
        IF mul_flush='1' THEN
          mul_bsy<='0';
        END IF;
        
        --------------------------------------------------------
        a:='1' & mul_fs1_man(52 DOWNTO 1);
        ax:=a(1  DOWNTO 0);
        al:=a(18 DOWNTO 2);
        am:=a(35 DOWNTO 19);
        ah:=a(52 DOWNTO 36);
        b:='1' & mul_fs2_man(51 DOWNTO 0);
        bx:=b(1  DOWNTO 0);
        bl:=b(18 DOWNTO 2);
        bm:=b(35 DOWNTO 19);
        bh:=b(52 DOWNTO 36);

        -- Simple : AL=0, AX=0, BL=0, BX=0

        IF mul_sd='0' OR mul_bsy='1' THEN
          b_hl:=bh;
          a_hl:=ah;
          a_x:="00";
          b_x:="00";
          m4:=am*bm;
          m5:=(OTHERS => '0');
        ELSE
          b_hl:=bl;
          a_hl:=al;
          a_x:=ax;
          b_x:=bx;
          m4:=al*bl;
          m5:=al*bh;
        END IF;
        
        m1:=ah*b_hl;
        m2:=am*b_hl;
        m3:=a_hl*bm;
        n1:=ax*b_hl;
        n2:=a_hl*bx;
        n3:=a_x*bm;
        n4:=am*b_x;
        ll:=a_x*b_x;

        --sum:=((Z(72 DOWNTO 72) & m5 & Z(37 DOWNTO 0)) +
        --      (Z(72 DOWNTO 72) & m1 & Z(37 DOWNTO 0))) +
        --     ((Z(72 DOWNTO 55) & m2 & Z(20 DOWNTO 0)) +
        --      (Z(72 DOWNTO 55) & m3 & Z(20 DOWNTO 0))) +
        --     ((Z(72 DOWNTO 38) & m4 & Z( 3 DOWNTO 0)) +
        --      (Z(72 DOWNTO 38) & n3 & Z(18 DOWNTO 0)) +
        --      (Z(72 DOWNTO 38) & n4 & Z(18 DOWNTO 0))) +
        --     ((Z(72 DOWNTO 21) & n1 & Z( 1 DOWNTO 0)) +
        --      (Z(72 DOWNTO 21) & n2 & Z( 1 DOWNTO 0)) +
        --      (Z(72 DOWNTO  4) & ll));

        sumz:=(Z(57 DOWNTO 55) & m2 & n1 & Z( 1 DOWNTO 0)) +
              (Z(57 DOWNTO 55) & m3 & n2 & Z( 1 DOWNTO 0)) +
              (Z(57 DOWNTO 38) & m4 & ll);
        
        sum:=(Z(72 DOWNTO 72) & m5 & n3 & Z(18 DOWNTO 0)) +
             (Z(72 DOWNTO 72) & m1 & n4 & Z(18 DOWNTO 0)) +
             (Z(72 DOWNTO 58) & sumz); 
        
        IF mul_bsy='1' THEN
          sum2:=sum+sum_mem(72 DOWNTO 34);
        ELSE
          sum2:=sum;
        END IF;
          
        mul_inx<=v_or(sum2(16 DOWNTO 0)) OR (or_mem AND mul_bsy);
        or_mem<=v_or(sum(33 DOWNTO 0));
        
        IF mul_start='1' OR mul_bsy='1' THEN
          mul_fs_man<=sum2(71 DOWNTO 17);
          sum_mem<=sum2;
        END IF;
      
      END IF;
    END PROCESS CalcMul;
  END GENERATE GenMUL0;

  --------------------------------------------------------------
  GenMUL1:IF TECHS(TECH).fmul=1 GENERATE

    mul_stall<='0';
    mul_busy <='0';
    
    CalcMul:PROCESS (clk,reset_n) IS
      VARIABLE fs1,fs2 : unsigned(52 DOWNTO 0);
      VARIABLE mul : unsigned(105 DOWNTO 0);
      VARIABLE ZZ : unsigned(63 DOWNTO 0) :=(OTHERS =>'0');
    BEGIN
      IF reset_n='0' THEN
        mul_end<='0';
      ELSIF rising_edge(clk) THEN
        mul_end<=mul_start;

        fs1:='1' & mul_fs1_man(52 DOWNTO 1);
        fs2:='1' & mul_fs2_man(51 DOWNTO 0);
        
        mul:=fs1 * fs2;
        
        mul_fs_man<=mul(105 DOWNTO 51);
        mul_inx<=v_or(mul(50 DOWNTO 0));
        
      END IF;
    END PROCESS CalcMul;



  END GENERATE GenMUL1;



END ARCHITECTURE rtl;
