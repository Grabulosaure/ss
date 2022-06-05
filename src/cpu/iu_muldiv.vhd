--------------------------------------------------------------------------------
-- TEM : TACUS
-- Unité entière : Module Multiplication / Division
--------------------------------------------------------------------------------
-- DO 9/2009
--------------------------------------------------------------------------------
-- Ce module est toujours présent, par contre les instructions MUL/DIV peuvent
-- être désactivées / remplacées par des traps.
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

-- On suppose que les entrées RS1, RS2 sont stables pendant toute la durée des
-- calculs.
-- Les données sont valides quand ACK=1

-- Multiplication & Division, signed & unsigned

-- REQ=1 pendant le niveau EXECUTE du pipe entier, les valeurs des registres
-- sont alors accessibles.
-- il y a bloquage du pipe tant que ACK=0

-- Les résultats de mul/div sont valides 1 cycle après ACK=1 (et restent figés
-- tant que REQ=0)

--------------------------------------------------------------------------------
-- MODES

  -- MUL : Instructions SMUL, UMUL, SMULcc, UMULcc. Sparc V8
  --   0 : Série, 1 bit par cycle,
  --   2 : Multiplieur 17x17, calcul en 4 cycles
  --   7 : Simulation.

  -- DIV : Instructions SDIV, UDIV, SDIVcc, UDIVcc. Sparc V8
  --   0 : Série sans restauration. 1 bit par cycle
  --   7 : Simulation.
 
--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY std;
USE std.textio.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.cpu_conf_pack.ALL;
USE work.iu_pack.ALL;
USE work.disas_pack.ALL;

ENTITY  iu_muldiv IS
  GENERIC (
    MULDIV   : boolean;
    TECH     : natural);
  PORT (
    op       : IN uv2;           -- 0:MUL 1:DIV | 0:Unsigned 1:Signed
    req      : IN std_logic;
    ack      : OUT std_logic;    -- Dernier cycle de l'instruction MUL/DIV
    rs1      : IN uv32;
    rs2      : IN uv32;
    ry       : IN uv32;
    
    rd_o     : OUT uv32;
    ry_o     : OUT uv32;
    icc_o    : OUT type_icc;
    dz_o     : OUT std_logic;   -- Division par zéro
    
    clk      : IN std_logic     -- Horloge
    );
END ENTITY iu_muldiv;

--------------------------------------------------------------------------------

ARCHITECTURE rtl OF iu_muldiv IS
  SIGNAL signe : std_logic;
  SIGNAL mul2_cpt : natural RANGE 0 TO 31;
  SIGNAL mul5_cpt : natural RANGE 0 TO 3;
  
  SIGNAL mul_rd : uv32;
  SIGNAL mul_ry : uv32;
  SIGNAL mul_calc,mul_ack : std_logic;
  SIGNAL mul5_acc : unsigned(33 DOWNTO 0);

  SIGNAL div1_cpt : natural RANGE 0 TO 36;

  SIGNAL div_b_prec : std_logic;
  SIGNAL div_r : unsigned(65 DOWNTO 0);  -- Reste/Calcul intermediaire
  SIGNAL div_rr32 : std_logic;
  SIGNAL div_oov,div_deo : std_logic;
  SIGNAL div_rd : uv32;
  SIGNAL div_calc,div_ack,div_dpz : std_logic;
  SIGNAL div_zpre : std_logic;
  SIGNAL dz_om,dz_om_c : std_logic;
  
BEGIN

  ------------------------------------------------------------------------------
  -- Multiplieur séquentiel 
  Gen_MUL_0: IF TECHS(TECH).mul=0 AND MULDIV GENERATE
    Seq_Mul:PROCESS(clk)
      VARIABLE ss : unsigned(32 DOWNTO 0);
      VARIABLE ii : uv32;
    BEGIN
      IF rising_edge(clk) THEN
        IF req='1' AND op(1)='0' THEN
          mul2_cpt<=1;
          mul_ack<='0';
          mul_calc<='1';
          ii:=(rs1 AND sext(rs2(0),32)) XOR (signe & sext('0',31));
          ss:=(signe & ii);
        ELSIF mul2_cpt=31 THEN
          mul2_cpt<=0;
          mul_ack<='1';
          mul_calc<='0';
          ii:=(rs1 AND sext(rs2(31),32)) XOR ('0' & sext(signe,31));
          ss:=('0' & ii)+('0' & mul_ry);
          ss(32):=ss(32) XOR signe;
        ELSIF mul_calc='1' THEN
          mul2_cpt<=mul2_cpt+1;
          mul_ack<='0';
          ii:=(rs1 AND sext(rs2(mul2_cpt),32)) XOR (signe & sext('0',31));
          ss:=('0' & ii)+('0' & mul_ry);
        ELSE
          mul2_cpt<=0;
          mul_ack<='0';
          mul_calc<='0';
        END IF;
        
        mul_ry<=ss(32 DOWNTO 1);
        mul_rd<=ss(0) & mul_rd(31 DOWNTO 1);
        
      END IF;
    END PROCESS Seq_Mul;
    
  END GENERATE Gen_MUL_0;
  
  ------------------------------------------------------------------------------
  -- Multiplieur à base de multiplieur signé 17bits * 17bits
  Gen_MUL_2: IF TECHS(TECH).mul=2 AND MULDIV GENERATE
    Seq_Mul:PROCESS(clk)
      VARIABLE op1,op2 : unsigned(16 DOWNTO 0);
      VARIABLE mul : unsigned(33 DOWNTO 0);
    BEGIN
      IF rising_edge(clk) THEN
        CASE mul5_cpt IS
          WHEN 0 =>
            op1:='0' & rs1(15 DOWNTO 0);
            op2:='0' & rs2(15 DOWNTO 0);
            
          WHEN 1 =>
            op1:='0' & rs1(15 DOWNTO 0);
            op2:=(rs2(31) AND signe) & rs2(31 DOWNTO 16);
            
          WHEN 2 =>
            op1:=(rs1(31) AND signe) & rs1(31 DOWNTO 16);
            op2:='0' & rs2(15 DOWNTO 0);

          WHEN 3 =>
            op1:=(rs1(31) AND signe) & rs1(31 DOWNTO 16);
            op2:=(rs2(31) AND signe) & rs2(31 DOWNTO 16);
            
          WHEN OTHERS => NULL;
        END CASE;
        mul:=unsigned(signed(op1) * signed(op2));
        
        CASE mul5_cpt IS
          WHEN 0 =>
            mul5_acc<=uext('0',18) & mul(31 DOWNTO 16);
            mul_rd(15 DOWNTO 0)<=mul(15 DOWNTO 0);
            
          WHEN 1 =>
            mul5_acc<=mul5_acc + (sext(mul(31) AND signe,2) & mul(31 DOWNTO 0));
            
          WHEN 2 =>
            mul5_acc<=mul5_acc + (sext(mul(31) AND signe,2) & mul(31 DOWNTO 0));
            
          WHEN 3 =>
            mul_rd(31 DOWNTO 16)<=mul5_acc(15 DOWNTO 0);
            mul_ry<=sext(mul5_acc(33 DOWNTO 16),32) + mul(31 DOWNTO 0);
        END CASE;
        
        IF req='1' AND op(1)='0' THEN
          mul5_cpt<=1;
          mul_ack<='0';
          mul_calc<='1';
        ELSIF mul5_cpt=3 THEN
          mul5_cpt<=0;
          mul_ack<='1';
          mul_calc<='0';
        ELSIF mul_calc='1' THEN
          mul5_cpt<=mul5_cpt+1;
          mul_ack<='0';
        ELSE
          mul5_cpt<=0;
          mul_ack<='0';
          mul_calc<='0';
        END IF;
        
      END IF;
    END PROCESS Seq_Mul;
    
  END GENERATE Gen_MUL_2;
  
  -- Diviseur sans restauration.
  Gen_DIV_0:IF TECHS(TECH).div=0 AND MULDIV GENERATE
    Seq_Div:PROCESS(clk)
      CONSTANT ZERO_33 : unsigned(32 DOWNTO 0) := (OTHERS => '0');
      VARIABLE r : unsigned(65 DOWNTO 0);  -- Reste/Calcul intermediaire
      VARIABLE m : unsigned(32 DOWNTO 0);  -- Diviseur
      VARIABLE b,sm,sd,sov,uov,deo : std_logic;
      VARIABLE zero : std_logic;
    BEGIN
      IF rising_edge(clk) THEN

        sd:= ry(31) AND signe;                  -- Signe dividende
        sm:=rs2(31) AND signe;                  -- Signe diviseur
        m:=(rs2(31) AND signe) & rs2;           -- Diviseur
        div_rr32<=div_r(31);
        -------------------------------------------
        -- Reste
        IF req='1' THEN
          r(65 DOWNTO 33):=(ry(31) AND signe) &
                           (ry(31) AND signe) & ry(31 DOWNTO 1);  -- Reste
        ELSIF div1_cpt/=34 THEN
          IF b='0' THEN  -- ADD
            r(65 DOWNTO 33):=div_r(64 DOWNTO 32) + m;
          ELSE  -- SUB
            r(65 DOWNTO 33):=div_r(64 DOWNTO 32) - m;
          END IF;
        ELSE
          IF b='0' THEN  -- ADD
            r(65 DOWNTO 33):=div_r(65 DOWNTO 33) + m;
          ELSE  -- SUB
            r(65 DOWNTO 33):=div_r(65 DOWNTO 33) - m;
          END IF;
        END IF;

        -------------------------------------------
        -- Bit
        b:=NOT r(65) XOR sm;
        div_b_prec<=b;
        
        zero:=to_std_logic(r(65 DOWNTO 33)=ZERO_33);
        div_zpre<=zero;
        
        -- Détection séquence 0111...1111
        IF div1_cpt=2 THEN
          div_deo<=NOT b;
        ELSIF div1_cpt<=33 THEN
          div_deo<=div_deo AND b;
        END IF;

        -------------------------------------------
        deo:=div_deo;

        IF req='1' THEN
          r(32 DOWNTO 0) :=ry(0) & rs1;
        ELSIF div1_cpt/=33 THEN
          r(32 DOWNTO 0) :=div_r(31 DOWNTO 0) & b;
        ELSE
          r(32 DOWNTO 0) :=div_r(31 DOWNTO 0) & '1';
        END IF;
        
        IF div1_cpt=34 THEN
          div_rd<=div_r(31 DOWNTO 0);
          IF zero='1' THEN
            IF sm='1' THEN
              div_rd<=div_r(31 DOWNTO 0) +1;
            ELSE
              div_rd<=div_r(31 DOWNTO 0) -1;
              deo:='0';
            END IF;
          ELSIF zero='0' AND div_zpre='0' THEN
            -- Correction finale
            IF (div_b_prec XOR sm)=sd THEN
              IF div_b_prec='1' THEN
                div_rd<=div_r(31 DOWNTO 0) +1;
              ELSE
                div_rd<=div_r(31 DOWNTO 0) -1;
                deo:='0';
              END IF;
            ELSE
              deo:='0';
            END IF;
          ELSE
            deo:='0';
          END IF;
          
          uov:=(div_rr32 AND NOT signe) OR
                ((div_rr32 XOR sd XOR sm) AND signe);
          sov:=(div_r(31) XOR sd XOR sm) AND signe;
          sov:=(deo AND NOT (sd XOR sm)) OR (NOT deo AND sov);
          
          -- Overflow final
          div_oov<=uov OR sov;
          IF sov='1' OR uov='1' THEN
            IF signe='1' THEN
              IF (sd XOR sm)='1' THEN
                div_rd<=x"80000000";
              ELSE
                div_rd<=x"7FFFFFFF";
              END IF;
            ELSE
              div_rd<=x"FFFFFFFF";
            END IF;
          END IF;
        END IF;
        
        IF req='1' AND op(1)='1' THEN
          div1_cpt<=1;
          div_ack<='0';
          div_calc<='1';
        ELSIF div1_cpt=34 THEN
          div1_cpt<=0;
          div_ack<='1';
          div_calc<='0';
        ELSIF div_calc='1' THEN
          div1_cpt<=div1_cpt+1;
          div_ack<='0';          
        ELSE
          div1_cpt<=0;
          div_ack<='0';
          div_calc<='0';
        END IF;
        
        IF div_calc='0' THEN
          div_dpz<='0';
        ELSIF rs2=x"00000000" AND div1_cpt=1 THEN
          div_calc<='0';
          div_dpz<='1';
        END IF;
        div_r<=r;
        
      END IF;
    END PROCESS Seq_Div;
  END GENERATE Gen_DIV_0;
  
  ------------------------------------------------------------------------------
  Comb:PROCESS(op,rs1,rs2,ry,mul_rd,mul_ry,mul_ack,dz_om,req,
                     div_rd,div_ack,div_oov,div_dpz)
    VARIABLE tmp64 : unsigned(63 DOWNTO 0);
    VARIABLE rd_ot : uv32;
    VARIABLE t : std_logic;
  BEGIN
    ack<='0';
    ry_o<=mul_ry;
    t:='0';
    rd_ot:=mul_rd;
    signe<=op(0);
    dz_o<=dz_om;
    dz_om_c<=dz_om;
    IF req='1' THEN
      dz_o<='0';
      dz_om_c<='0';
    END IF;
    
    IF op(1)='0' THEN               -- UMUL, UMULcc, SMUL, SMULcc
      CASE TECHS(TECH).mul IS
        WHEN 7 =>
          ack<='1';
          IF op(0)='0' THEN          -- Unsigned
            tmp64:=unsigned(unsigned(rs1) * unsigned(rs2));
            ry_o<=tmp64(63 DOWNTO 32);
            rd_ot:=tmp64(31 DOWNTO 0);
          ELSE                        -- Signed
            tmp64:=unsigned(signed(rs1) * signed(rs2));
            ry_o<=tmp64(63 DOWNTO 32);
            rd_ot:=tmp64(31 DOWNTO 0);
          END IF;
        WHEN OTHERS =>
          ack<=mul_ack;
          ry_o<=mul_ry;
          rd_ot:=mul_rd;
      END CASE;
      icc_o.v<='0';
      icc_o.c<='0';
        
    ELSE                              -- UDIV, UDIVcc, SDIV, SDIVcc     
      CASE TECHS(TECH).div IS
        WHEN 7 =>
          ack<='1';
          IF op(0)='0' THEN          -- Unsigned
            IF rs2=x"00000000" THEN
              dz_o<='1';
            ELSE
              tmp64:=unsigned(unsigned'(ry & rs1) /
                              unsigned(uext(rs2,64)));
            END IF;
            t:=NOT to_std_logic(tmp64(63 DOWNTO 32)=x"00000000");
            IF t='1' THEN
              rd_ot:=x"FFFFFFFF";
            ELSE
              rd_ot:=tmp64(31 DOWNTO 0);
            END IF;
          ELSE                        -- Signed
            IF rs2=x"00000000" THEN
              dz_o<='1';
            ELSE
              tmp64:=unsigned(signed(unsigned'(ry & rs1)) /
                              signed(sext(rs2,64)));
            END IF;
            t:=NOT (to_std_logic(tmp64(63 DOWNTO 31)=x"00000000" & '0')
                 OR to_std_logic(tmp64(63 DOWNTO 31)=x"FFFFFFFF" & '1'));
            IF t='1' THEN
              IF tmp64(63)='0' THEN
                rd_ot:=x"7FFFFFFF";
              ELSE
                rd_ot:=x"80000000";
              END IF;
            ELSE
              rd_ot:=tmp64(31 DOWNTO 0);
            END IF;                
          END IF;
        WHEN OTHERS =>
          ack<=div_ack;
          rd_ot:=div_rd;
          t:=div_oov;
          IF div_dpz='1' THEN
            dz_o<='1';
            dz_om_c<='1';
            ack<='1';
          END IF;
      END CASE;
      icc_o.v<=t;
      icc_o.c<='0';
    END IF;
    rd_o<=rd_ot;
    icc_o.n<=rd_ot(31);
    icc_o.z<=to_std_logic(rd_ot=x"00000000");
  END PROCESS Comb;

  dz_om<=dz_om_c WHEN rising_edge(clk);
  
END ARCHITECTURE rtl;
