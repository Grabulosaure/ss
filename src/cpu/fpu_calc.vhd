--------------------------------------------------------------------------------
-- TEM : TACUS
-- Unité flottante. Calculs
--------------------------------------------------------------------------------
-- DO 7/2014
--------------------------------------------------------------------------------
-- Calculs. Pipelinés
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

--------------------------------------------------------------------------------
-- FMOVs, FNEGs, FABSs         : 2      Copie

-- FADDs, FSUBs, FCMPs, FCMPEs : 4      Extract/Decal/Add/Arrondi/Convert
-- FADDd, FSUBd, FCMPd, FCMPEd : 4      Extract/Decal/Add/Arrondi/Convert
-- FiTOs, FiTOd                : 4=add  Extract/Decal/Add/Arrondi/Convert
-- FsTOd, FdTOs                : 4=ftof Extract/Decal/Arrondi/Convert
-- FsTOi, FdTOi                : 4=add  Extract/Decal/Add/Direct/Convert

-- FMULs, FsMULd               : 4      Extract/Decal/MUL*2/Arrondi/Convert
-- FMULd                       : 5      Extract/Decal/MUL*3/Arrondi/Convert

-- FDIVs, FSQRTs               : 32     Extract/Decal/DIVSQR*25/Arrondi/Convert
-- FDIVd, FSQRTd               : 61     Extract/Decal/DIVSQR*54/Arrondi/Convert

--------------------------------------------------------------------------------

--    cX.v : Actif en permanence tant qu'il y a quelquechose en cours
--   asX_c : A 1 si le niveau suivant est prêt à accepter
--cX_rdy_c : indique la fin de la phase en cours. 

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

USE work.base_pack.ALL;
USE work.iu_pack.ALL;
USE work.fpu_pack.ALL;
USE work.disas_pack.ALL;

ENTITY  fpu_calc IS
  GENERIC (
    DENORM_HARD : boolean;
    DENORM_FTZ  : boolean;
    DENORM_ITER : boolean;
    TECH        : natural);
  PORT (
    -- Contrôle
    rdy      : OUT std_logic;
    req      : IN  std_logic;
    fin      : OUT std_logic;
    flush    : IN  std_logic;
    stall    : IN  std_logic;
    idle     : OUT std_logic;
    
    -- Opération
    fop      : IN  uv4;       -- Opcode 
    sdi      : IN  std_logic; -- Simple/Double IN
    sdo      : IN  std_logic; -- Simple/Double OUT
    rd       : IN  uv2;       -- Round Direction
    tem      : IN  unsigned(4 DOWNTO 0);
    
    -- Opérandes
    fs1      : IN  uv64; -- S1
    fs2      : IN  uv64; -- S2
    fd       : OUT uv64; -- Dest
    fcc      : OUT uv2;  -- Code Condition
    exc      : OUT unsigned(4 DOWNTO 0); -- Exceptions
    unf      : OUT std_logic;            -- Unfinished FPop : Denormals
    
    -- Général
    reset_na : IN std_logic;
    clk      : IN std_logic
    );
END ENTITY fpu_calc;

--------------------------------------------------------------------------------
ARCHITECTURE rtl OF fpu_calc IS

  CONSTANT SSTALL : boolean :=true; -- Synchronous STALL, no comb. path with input
  
  COMPONENT fpu_mul
    GENERIC (
      TECH : natural);
    PORT (
      mul_sd      : IN  std_logic;
      mul_flush   : IN  std_logic;
      mul_start   : IN  std_logic;
      mul_end     : OUT std_logic;
      mul_busy    : OUT std_logic;
      mul_stall   : OUT std_logic;
      mul_fs1_man : IN  unsigned(53 DOWNTO 0);
      mul_fs2_man : IN  unsigned(52 DOWNTO 0);
      mul_fs_man  : OUT unsigned(54 DOWNTO 0);
      mul_inx     : OUT std_logic;
      reset_na    : IN  std_logic;
      clk         : IN  std_logic);
  END COMPONENT;

  COMPONENT fpu_div
    GENERIC (
      TECH : natural);
    PORT (
      div_sd      : IN  std_logic;
      div_dr      : IN  std_logic;
      div_flush   : IN  std_logic;
      div_start   : IN  std_logic;
      div_end     : OUT std_logic;
      div_busy    : OUT std_logic;
      div_fs1_man : IN  unsigned(53 DOWNTO 0);
      div_fs2_man : IN  unsigned(52 DOWNTO 0);
      div_fs_man  : OUT unsigned(54 DOWNTO 0);
      div_inx     : OUT std_logic;
      reset_na    : IN  std_logic;
      clk         : IN  std_logic);
  END COMPONENT;

  CONSTANT ZERO : unsigned(63 DOWNTO 0) := x"00000000_00000000";

  SIGNAL fd_i_c  : uv64;
  SIGNAL fcc_i_c : uv2;
  SIGNAL exc_i_c : unsigned(4 DOWNTO 0);
  SIGNAL fin_i_c : std_logic;
  SIGNAL unf_i_c : std_logic;
  
  --------------------------------------
  TYPE type_fpipe IS RECORD
    v         : std_logic;
    fop       : uv4;
    ma        : std_logic;              -- 1=MDS 0=ASC
    sdi       : std_logic;
    sdo       : std_logic;
    rd        : uv2;
    fs1_class : type_class;
    fs2_class : type_class;
  END RECORD;
  
  --------------------------------------
  -- C1
  SIGNAL c1 : type_fpipe;
  SIGNAL as1_c : std_logic;
  
  -- C1
  SIGNAL c2_fs2_man : unsigned(51 DOWNTO 0);
  SIGNAL c2_fs2_exp : unsigned(10 DOWNTO 0);
  SIGNAL c2_fs2_exp0 : std_logic;
  
  -- C2
  SIGNAL c2_rdy_c : std_logic;
  SIGNAL as2_c,c2_rdy : std_logic;
  SIGNAL c2_rdymd : std_logic;
  SIGNAL c2 : type_fpipe;
  SIGNAL c2_asc_fhi_man,c2_asc_flo_man : unsigned(55 DOWNTO 0);
  SIGNAL c2_asc_fhi_s,c2_asc_flo_s : std_logic;
  SIGNAL c2_asc_expo : unsigned(10 DOWNTO 0);
  SIGNAL c2_asc_diff : unsigned(12 DOWNTO 0);
  SIGNAL c2i_fs1_deca,c2i_fs2_deca : unsigned(12 DOWNTO 0);
  SIGNAL c2i_expo : unsigned(12 DOWNTO 0);
  SIGNAL c2_mds_fs1_man : unsigned(53 DOWNTO 0);
  SIGNAL c2_mds_fs2_man : unsigned(52 DOWNTO 0);
  SIGNAL c2_mds_expo : unsigned(12 DOWNTO 0);
  SIGNAL c2_mds_unf : std_logic;

  SIGNAL mul_start,div_start : std_logic;
  SIGNAL mul_end,div_end : std_logic;
  SIGNAL mul_stall,mul_busy,div_busy : std_logic;
  SIGNAL mul_inx,div_inx : std_logic;
  SIGNAL mul_fs_man : unsigned(54 DOWNTO 0);
  SIGNAL div_fs_man : unsigned(54 DOWNTO 0);
  
  -- C3
  SIGNAL as3_c,c3_rdy_c,c3_rdy : std_logic;
  SIGNAL c3 : type_fpipe;
  SIGNAL c3_asc_fhi_s,c3_asc_flo_s : std_logic;
  SIGNAL c3_asc_addsub : unsigned(56 DOWNTO 0);
  SIGNAL c3_asc_nz : natural RANGE 0 TO 63;
  SIGNAL c3_asc_fo_s : std_logic;
  SIGNAL c3_asc_nxf,c3_asc_nvf : std_logic;
  SIGNAL c3_asc_expo : unsigned(10 DOWNTO 0);
  SIGNAL c3_mds_fs_man   : unsigned(53 DOWNTO 0);
  SIGNAL c3p_mds_fs1_man : unsigned(53 DOWNTO 0);
  SIGNAL c3_mds_expo,c3p_mds_expo : unsigned(12 DOWNTO 0);
  SIGNAL c3_mds_sticky : std_logic;
  SIGNAL c3_mds_unf : std_logic;
  
  -- C4
  SIGNAL as4_c,c4_rdy : std_logic;
  SIGNAL c4 : type_fpipe;
  SIGNAL c4_asc_fcc : unsigned(1 DOWNTO 0);
  SIGNAL c4_mds_emod : unsigned(6 DOWNTO 0);
  SIGNAL c4_mds_unf : std_logic;
  
  SIGNAL c4_mix_udf,c4_mix_nvf,c4_mix_nxf : std_logic;
  SIGNAL c4_mix_fs_man : unsigned(53 DOWNTO 0);
  SIGNAL c4_mix_expo : unsigned(12 DOWNTO 0);
  SIGNAL c4_mix_sticky : std_logic;
  SIGNAL c4_mix_fo_s : std_logic;
  SIGNAL c4_mix_mds : boolean;

  -- C5
  SIGNAL as5_c : std_logic;

  SIGNAL mem_fd  : uv64;
  SIGNAL mem_fcc : uv2;
  SIGNAL mem_exc : unsigned(4 DOWNTO 0);
  SIGNAL mem_unf : std_logic;
  SIGNAL mem_stall : std_logic;
  
  SIGNAL xxx_fop : string(1 TO 4);
  SIGNAL xxx_c1_fop : string(1 TO 4);
  SIGNAL xxx_c2_fop,xxx_c3_fop,xxx_c4_fop : string(1 TO 4);
  
  ------------------------------------------------------------------------------
BEGIN

  rdy<=NOT c1.v OR as2_c;
  
  c2_rdy_c<=NOT c3.v AND NOT c4.v AND as5_c WHEN
             c2.fop=FOP_MOV OR c2.fop=FOP_NEG OR c2.fop=FOP_ABS
             ELSE
             c2_rdymd;
  
  as1_c<=NOT c1.v OR as2_c;
  as2_c<=NOT c2.v OR (as3_c AND c2_rdy_c);
  as3_c<=NOT c3.v OR (as4_c AND c3_rdy_c);
  as4_c<=NOT c4.v OR (as5_c AND c4_rdy);
  as5_c<=NOT stall WHEN NOT SSTALL ELSE NOT mem_stall;
  
  xxx_fop   <=fop_string(fop);
  xxx_c1_fop<=fop_string(c1.fop);
  xxx_c2_fop<=fop_string(c2.fop);
  xxx_c3_fop<=fop_string(c3.fop);
  xxx_c4_fop<=fop_string(c4.fop);

  idle<=NOT (c1.v OR c2.v OR c3.v OR c4.v);
  
  CalcM:PROCESS(clk,reset_na) IS
  BEGIN
    IF reset_na='0' THEN
      c1.v<='0';
    ELSIF rising_edge(clk) THEN
      IF req='1' AND (NOT c1.v OR as2_c)='1' THEN
        c1.fop<=fop;
        c1.sdi<=sdi;
        c1.sdo<=sdo;
        c1.rd <=rd;
        c1.v<='1';
      ELSIF as1_c='1' THEN
        c1.v<='0';
      END IF;
      IF flush='1' THEN
        c1.v<='0';
      END IF;
    END IF;
  END PROCESS CalcM;
  -- Le contenu des registres n'est accessible que pendant le premier cycle
  --   de C1. C1.V est maintenu tant que la partie C2 n'est pas terminée.
  
  ------------------------------------------------------------------------------
  -- Etage 1 : Prénormalisation, alignements
  Seq1:PROCESS (clk,reset_na) IS
    VARIABLE fhi_man_v,flo_man_v : unsigned(55 DOWNTO 0);
    VARIABLE fhi_s_v,flo_s_v : std_logic;
    VARIABLE expo_asc_v: unsigned(10 DOWNTO 0);
    VARIABLE expo_mds_v,expo_mds2_v,diff_v : unsigned(12 DOWNTO 0);
    VARIABLE expo_mds3_v : unsigned(12 DOWNTO 0);
    VARIABLE fs1_man0_v,fs2_man0_v : unsigned(51 DOWNTO 0);
    VARIABLE fs1_class_v,fs2_class_v : type_class;
    VARIABLE fs1_exp_v,fs2_exp_v : unsigned(10 DOWNTO 0);
    VARIABLE fs2_exp0_v : std_logic;
    VARIABLE fs1_man_v : unsigned(53 DOWNTO 0);
    VARIABLE fs2_man_v : unsigned(52 DOWNTO 0);
    VARIABLE ifs1_man_v,ifs2_man_v : unsigned(52 DOWNTO 0);
    VARIABLE fs1_deca_v,fs2_deca_v : unsigned(12 DOWNTO 0);
    VARIABLE unf_v : std_logic;
    VARIABLE rdy_v : std_logic;
    VARIABLE cx_v : type_fpipe;
  BEGIN
    IF reset_na='0' THEN
      c2.v<='0';
      c2_rdy<='0';
      
    ELSIF rising_edge(clk) THEN
      rdy_v:='0';
      
      asc_mds_1(fs1_man0_v,fs2_man0_v,
                fs1_class_v,fs2_class_v,fs1_exp_v,fs2_exp_v,
                fs2_exp0_v,fs1,fs2,c1.fop,c1.sdi);
      
      -----------------------------------------------------------------------
      IF as2_c='1' THEN
        -- Charge nouvelles données
        c2<=c1;
        c2.v<=c1.v;
        c2_rdy<='0';
        
        IF c1.fop=FOP_MUL OR c1.fop=FOP_DIV OR
          c1.fop=FOP_SQRT OR c1.fop=FOP_fTOf THEN
          c2.ma<='1';
        ELSE
          c2.ma<='0';
        END IF;
        c2.fs1_class<=fs1_class_v;
        c2.fs2_class<=fs2_class_v;
        c2_fs2_man<=fs2_man0_v;
        c2_fs2_exp<=fs2_exp_v;
        c2_fs2_exp0<=fs2_exp0_v;
        
        -- 1) ADD : Recherche du plus grand exposant, décalage exposant faible
        asc_2(fhi_man_v,flo_man_v,fhi_s_v,flo_s_v,expo_asc_v,diff_v,
              fs1_man0_v,fs2_man0_v,fs1_class_v,fs2_class_v,
              fs1_exp_v,fs2_exp_v,fs2_exp0_v,c1.fop,c1.sdi,c1.sdo);
        
        c2_asc_fhi_man<=fhi_man_v;
        c2_asc_flo_man<=flo_man_v;
        c2_asc_fhi_s<=fhi_s_v;
        c2_asc_flo_s<=flo_s_v;
        c2_asc_expo<=expo_asc_v;
        c2_asc_diff<=diff_v;
      END IF;
      
      IF as2_c='1' THEN
        cx_v:=c1;
        cx_v.fs1_class:=fs1_class_v;
        cx_v.fs2_class:=fs2_class_v;
      ELSE
        cx_v:=c2;
      END IF;
        
      -----------------------------------------------------------------------
      IF as2_c='1' OR c2_rdy='0' THEN
        IF NOT DENORM_HARD THEN
          -- 1) MULDIV : Renormalisation : Pas de renormalisation
          mds_2_unf(fs1_man_v,fs2_man_v,expo_mds2_v,unf_v,
                    fs1_man0_v,fs2_man0_v,
                    fs1_class_v,fs2_class_v,
                    fs1_exp_v,fs2_exp_v,c1.fop,c1.sdi);
          c2_mds_unf<=unf_v;
          ifs2_man_v:=fs2_man_v;
          rdy_v:='1';
          
        ELSIF NOT DENORM_ITER THEN
          -- 1) MULDIV : Renormalisation : Renormalisation en un cycle
          mds_2(fs1_man_v,fs2_man_v,expo_mds2_v,
                fs1_man0_v,fs2_man0_v,
                fs1_class_v,fs2_class_v,
                fs1_exp_v,fs2_exp_v,c1.fop,c1.sdi);
          ifs2_man_v:=fs2_man_v;
          rdy_v:='1';
          
        ELSE
          IF as2_c='1' THEN
            -- 1) MULDIV : Renormalisation itérative pour MUL/DIV
            IF c1.fop=FOP_MUL THEN
              ifs1_man_v:=NOT fs1_class_v(2) & fs1_man0_v;
              ifs2_man_v:=NOT fs2_class_v(2) & fs2_man0_v;
            ELSIF c1.fop=FOP_DIV THEN
              ifs1_man_v:=NOT fs1_class_v(2) & fs1_man0_v;
              ifs2_man_v:=NOT fs2_class_v(2) & fs2_man0_v;
            ELSE -- SQRT, fTOf
              ifs1_man_v:=NOT fs2_class_v(2) & fs2_man0_v;
              ifs2_man_v:='1' & fs2_man0_v;
            END IF;
            fs1_deca_v:=ZERO(12 DOWNTO 0);
            fs2_deca_v:=ZERO(12 DOWNTO 0);
            IF c1.fop=FOP_MUL THEN
              expo_mds_v:=("00" & fs1_exp_v) + ("00" & fs2_exp_v);
            ELSIF c1.fop=FOP_DIV THEN
              expo_mds_v:=("00" & fs1_exp_v) - ("00" & fs2_exp_v);
            ELSE
              expo_mds_v:="00" & fs2_exp_v;
            END IF;
            c2i_expo<=expo_mds_v;
          ELSE         -- Cycles suivants : récupère résultats précédents
            ifs1_man_v:=c2_mds_fs1_man(53 DOWNTO 1);
            ifs2_man_v:=c2_mds_fs2_man;
            fs1_deca_v:=c2i_fs1_deca;
            fs2_deca_v:=c2i_fs2_deca;
            expo_mds_v:=c2i_expo;
          END IF;
          
          -- Décalage / renormalisation
          IF ifs1_man_v(52 DOWNTO 45)=x"00" THEN  -- <<8
            ifs1_man_v:=ifs1_man_v(44 DOWNTO 0) & x"00";
            fs1_deca_v(12 DOWNTO 3):=fs1_deca_v(12 DOWNTO 3)+1;
          ELSIF ifs1_man_v(52)='0' THEN -- <<1
            ifs1_man_v:=ifs1_man_v(51 DOWNTO 0) & '0';
            fs1_deca_v(2 DOWNTO 0):=fs1_deca_v(2 DOWNTO 0)+1;
          END IF;
          IF ifs2_man_v(52 DOWNTO 45)=x"00" THEN  -- <<8
            ifs2_man_v:=ifs2_man_v(44 DOWNTO 0) & x"00";
            fs2_deca_v(12 DOWNTO 3):=fs2_deca_v(12 DOWNTO 3)+1;
          ELSIF ifs2_man_v(52)='0' THEN  -- <<1
            ifs2_man_v:=ifs2_man_v(51 DOWNTO 0) & '0';
            fs2_deca_v(2 DOWNTO 0):=fs2_deca_v(2 DOWNTO 0)+1;
          END IF;
          
          c2i_fs1_deca<=fs1_deca_v;
          c2i_fs2_deca<=fs2_deca_v;
          
          expo_mds2_v:=expo_mds_v - fs1_deca_v;
          IF cx_v.fop=FOP_MUL THEN
            expo_mds2_v:=expo_mds2_v - fs2_deca_v;
          ELSE
            expo_mds2_v:=expo_mds2_v + fs2_deca_v;
          END IF;
          
          fs1_man_v:=ifs1_man_v & '0';
          fs2_man_v:=ifs2_man_v;
          
          -- 1) MUL : Correction exposant, réalignement mantisse 1bit (DIF,SQRT)
          IF cx_v.fop=FOP_MUL OR cx_v.fop=FOP_DIV THEN
            IF (cx_v.fs1_class(1 DOWNTO 0)="00" OR ifs1_man_v(52)/='0') AND
              (cx_v.fs2_class(1 DOWNTO 0)="00" OR ifs2_man_v(52)/='0') THEN
              rdy_v:='1';
            END IF;
          ELSIF cx_v.fop=FOP_SQRT OR cx_v.fop=FOP_fTOf THEN
            IF cx_v.fs2_class(1 DOWNTO 0)="00" OR ifs1_man_v(52)/='0' THEN
              rdy_v:='1';
            END IF;
          ELSE
            rdy_v:='1';
          END IF;
          
        END IF; -- IF NOT DENORM_ITER
        
        c2_rdy<=rdy_v;
        
        IF rdy_v='1' THEN
          -- A la fin du calcul itératif de C2
          c2_mds_fs2_man<=ifs2_man_v;
          mds_3(fs1_man_v,expo_mds3_v,
                fs1_man_v,expo_mds2_v,cx_v.fop,cx_v.sdi,cx_v.sdo);
          c2_mds_fs1_man<=fs1_man_v;
          c2_mds_expo<=expo_mds3_v;

        ELSE
          -- Pendant l'itération
          c2_mds_fs2_man<=ifs2_man_v;
          c2_mds_fs1_man<=fs1_man_v;
        END IF;
        
      END IF; -- as2_c='1' OR c2_rdy='0'
      
      IF flush='1' THEN
        c2.v<='0';
      END IF;

    END IF;
  END PROCESS Seq1;
  
  ------------------------------------------------------------------------------
  -- Etage 2 : Calculs : ADD / SUB
  Seq2:PROCESS (clk,reset_na) IS
    -- ADD
    VARIABLE addsub_v : unsigned(56 DOWNTO 0);
    VARIABLE nz_v : natural RANGE 0 TO 63;
    VARIABLE fo_s_v : std_logic;
    VARIABLE nxf_v,nvf_v : std_logic;
    
  BEGIN
    IF reset_na='0' THEN
      c3.v<='0';
    ELSIF rising_edge(clk) THEN
      -----------------------------------------------------------------------
      IF as3_c='1' THEN
        c3<=c2;
        c3.v<=c2.v AND c2_rdymd;
        CASE c2.fop IS
          WHEN FOP_ADD | FOP_SUB | FOP_CMP  | FOP_CMPE | FOP_iTOf | FOP_fTOi |
            FOP_MUL | FOP_DIV | FOP_SQRT | FOP_fTOf =>
            c3.v<=c2.v AND c2_rdymd;
            
          WHEN OTHERS => --FOP_MOV | FOP_NEG | FOP_ABS
            c3.v<='0';
            
        END CASE;

        -----------------------------------------------------------------------
        -- 2) ADD : Addition/Soustraction
        asc_3(addsub_v,nz_v,fo_s_v,nxf_v,nvf_v,
              c2_asc_diff,c2_asc_fhi_man,c2_asc_flo_man,
              c2_asc_fhi_s,c2_asc_flo_s,c2.fop);
        c3_asc_addsub<=addsub_v;
        c3_asc_nz<=nz_v;
        c3_asc_fo_s<=fo_s_v;
        c3_asc_nxf<=nxf_v;
        c3_asc_nvf<=nvf_v;
        c3_asc_expo<=c2_asc_expo;
        c3_asc_fhi_s<=c2_asc_fhi_s;
        c3_asc_flo_s<=c2_asc_flo_s;
        
        -----------------------------------------------------------------------
        -- 2) MUL/DIV
        c3_mds_unf<=c2_mds_unf;
        c3p_mds_expo<=c2_mds_expo;
        c3p_mds_fs1_man<=c2_mds_fs1_man;

      END IF;

      IF flush='1' THEN
        c3.v<='0';
      END IF;

      c3_rdy<=(c3_rdy OR c3_rdy_c) AND NOT as3_c;
      
    END IF;
  END PROCESS Seq2;
  
  --------------------------------------------------------
  -- Etage 2 : Calculs : MUL / DIV
  mul_start<=c2.v AND c2_rdy AND as3_c AND
              NOT mul_busy AND NOT div_busy AND
              to_std_logic(c2.fop=FOP_MUL);
  div_start<=c2.v AND c2_rdy AND as3_c AND
              NOT mul_busy AND NOT div_busy AND
              to_std_logic(c2.fop=FOP_DIV OR c2.fop=FOP_SQRT);

  c2_rdymd<=c2_rdy AND NOT mul_stall;
  
  i_fpu_mul: fpu_mul
    GENERIC MAP (
      TECH        => TECH)
    PORT MAP (
      mul_sd      => c2.sdi,
      mul_flush   => flush,
      mul_start   => mul_start,
      mul_end     => mul_end,
      mul_stall   => mul_stall,
      mul_busy    => mul_busy,
      mul_fs1_man => c2_mds_fs1_man,
      mul_fs2_man => c2_mds_fs2_man,
      mul_fs_man  => mul_fs_man,
      mul_inx     => mul_inx,
      reset_na    => reset_na,
      clk         => clk);
  
  i_fpu_div: fpu_div
    GENERIC MAP (
      TECH        => TECH)
    PORT MAP (
      div_sd      => c2.sdi,
      div_dr      => c2.fop(1),
      div_flush   => flush,
      div_start   => div_start,
      div_end     => div_end,
      div_busy    => div_busy,
      div_fs1_man => c2_mds_fs1_man,
      div_fs2_man => c2_mds_fs2_man,
      div_fs_man  => div_fs_man,
      div_inx     => div_inx,
      reset_na    => reset_na,
      clk         => clk);
  
  Comb2_MulDiv:PROCESS (mul_fs_man,mul_inx,div_fs_man,div_inx,
                 c3,c3p_mds_fs1_man,c3p_mds_expo) IS
    VARIABLE fs_man_v : unsigned(54 DOWNTO 0);
    VARIABLE sticky_v : std_logic;
  BEGIN
    IF c3.fop=FOP_MUL THEN
      fs_man_v:=mul_fs_man;
      sticky_v:=mul_inx;
    ELSIF c3.fop=FOP_DIV OR c3.fop=FOP_SQRT THEN
      fs_man_v:=div_fs_man;
      sticky_v:=div_inx;
    ELSE
      -- Conversion sTOd, dTOs
      fs_man_v:='0' & c3p_mds_fs1_man;
      sticky_v:='0';
    END IF;
    -- 3) Conversion
    IF fs_man_v(54)='1' THEN
      IF c3.sdo='0' THEN
        sticky_v:=sticky_v OR fs_man_v(29);
      ELSE
        sticky_v:=sticky_v OR fs_man_v(0);
      END IF;
      c3_mds_fs_man<=fs_man_v(54 DOWNTO 1);
      c3_mds_expo<=c3p_mds_expo;
    ELSE
      c3_mds_fs_man<=fs_man_v(53 DOWNTO 0);
      c3_mds_expo<=c3p_mds_expo-1;
    END IF;
    
    c3_mds_sticky<=sticky_v;
  END PROCESS Comb2_MulDiv;
  
  c3_rdy_c<=NOT c3.v OR mul_end OR div_end OR
             to_std_logic(c3.fop/=FOP_MUL AND
                          c3.fop/=FOP_DIV AND c3.fop/=FOP_SQRT) OR
             c3_rdy;
  
  ------------------------------------------------------------------------------
  -- Etage 3 : Réalignements, arrondis
  Seq3:PROCESS (clk,reset_na) IS
    VARIABLE fcc_v : unsigned(1 DOWNTO 0);
    VARIABLE asc_fs_man_v,mds_fs_man_v : unsigned(53 DOWNTO 0);
    VARIABLE asc_expo_v : unsigned(10 DOWNTO 0);
    VARIABLE mds_expo_v : unsigned(12 DOWNTO 0);
    VARIABLE asc_sticky_v,mds_sticky_v : std_logic;
    VARIABLE asc_fo_s_v : std_logic;
    VARIABLE asc_nxf_v,mds_nxf_v,mds_udf_v : std_logic;
    VARIABLE mds_emod_v : unsigned(6 DOWNTO 0);
    VARIABLE mds_deno_v : boolean;
    VARIABLE cx_v : type_fpipe;
  BEGIN
    IF reset_na='0' THEN
      c4.v<='0';
    ELSIF rising_edge(clk) THEN
      IF as4_c='1' THEN
        cx_v:=c3;
      ELSE
        cx_v:=c4;
      END IF;
      
      c4_rdy<='1';
      
      -------------------------------------------------------------------
      -- 3) Réalignement après soustraction avec annulation, Calc. FCC
      IF as4_c='1' THEN
        asc_4(asc_fs_man_v,fcc_v,asc_nxf_v,asc_sticky_v,asc_expo_v,asc_fo_s_v,
              c3_asc_expo,c3_asc_nz,c3_asc_addsub,c3_asc_fo_s,c3_asc_nxf,
              c3_asc_fhi_s,c3_asc_flo_s,c3.fop,c3.sdi,c3.rd);
        
        c4_asc_fcc<=fcc_v;
        
        c4<=c3;
        c4.v<=c3.v AND c3_rdy_c;
        
      END IF;
      
      IF as4_c='1' OR c4_rdy='0' THEN
        -------------------------------------------------------------------
        -- 3) Dénormalisation mul/div/sqrt
        IF NOT DENORM_HARD THEN
          -- Pas de dénormalisation
          mds_4_unf(mds_fs_man_v,mds_expo_v,mds_sticky_v,mds_udf_v,mds_nxf_v,
                    c3_mds_fs_man,c3_mds_expo,c3_mds_sticky,c3.sdo,tem(X_UF));
          mds_deno_v:=c3_mds_expo(12)='1' OR c3_mds_expo=ZERO(12 DOWNTO 0);
          c4_mds_unf<=c3_mds_unf OR to_std_logic(mds_deno_v);
          
        ELSIF NOT DENORM_ITER THEN
          -- Dénormalisation en 1 cycle
          mds_4(mds_fs_man_v,mds_expo_v,mds_sticky_v,mds_udf_v,mds_nxf_v,
                c3_mds_fs_man,c3_mds_expo,c3_mds_sticky,c3.sdo,tem(X_UF));
          
        ELSE
          -- Dénormalisation itérative pour MUL/DIV/SQRT
          IF c4_rdy='1' THEN -- Premier cycle
            mds_fs_man_v:=c3_mds_fs_man;
            mds_sticky_v:=c3_mds_sticky;
            mds_expo_v:=c3_mds_expo-2;
            mds_emod_v:=v_and(mds_expo_v(11 DOWNTO 6)) & mds_expo_v(5 DOWNTO 0);
            mds_expo_v:=c3_mds_expo;
            mds_deno_v:=c3_mds_expo(12)='1' OR c3_mds_expo=ZERO(12 DOWNTO 0);
            
          ELSE -- Suite
            mds_fs_man_v:=c4_mix_fs_man;
            mds_sticky_v:=c4_mix_sticky;
            mds_emod_v:=c4_mds_emod;
            mds_expo_v:="0000000000001";
            mds_deno_v:=true;
          END IF;
          
          IF mds_deno_v THEN
            IF mds_emod_v(6 DOWNTO 3)/="1111" THEN
              mds_sticky_v:=mds_sticky_v OR v_or(mds_fs_man_v(7 DOWNTO 0));
              mds_fs_man_v:="00000000" & mds_fs_man_v(53 DOWNTO 8);
              mds_emod_v(6 DOWNTO 3):=mds_emod_v(6 DOWNTO 3)+1;
            END IF;
            IF mds_emod_v(2 DOWNTO 0)/="111" THEN
              mds_sticky_v:=mds_sticky_v OR mds_fs_man_v(0);
              mds_fs_man_v:='0' & mds_fs_man_v(53 DOWNTO 1);
              mds_emod_v(2 DOWNTO 0):=mds_emod_v(2 DOWNTO 0)+1;
            END IF;
          END IF;
          
          IF c4_rdy='1' THEN
            c4_rdy<=NOT to_std_logic(mds_deno_v) OR NOT c3.v OR NOT c3_rdy_c
                     OR NOT c3.ma;
          ELSE
            c4_rdy<=NOT to_std_logic(
              mds_emod_v/="1111111" AND mds_fs_man_v/=ZERO(53 DOWNTO 0));
          END IF;
          
          c4_mds_emod<=mds_emod_v;
          
          IF cx_v.sdo='0' THEN
            mds_sticky_v:=mds_sticky_v OR v_or(mds_fs_man_v(28 DOWNTO 0));
            mds_nxf_v:=mds_sticky_v OR mds_fs_man_v(29);
          ELSE
            mds_nxf_v:=mds_sticky_v OR mds_fs_man_v(0);
          END IF;

          mds_udf_v:=to_std_logic(
            mds_expo_v="0000000000001" AND
            mds_fs_man_v/=ZERO(53 DOWNTO 0) AND
            mds_fs_man_v(53)='0');
          mds_udf_v:=(mds_udf_v AND mds_nxf_v AND NOT tem(X_UF)) OR
                     (mds_udf_v AND tem(X_UF)); -- Underflow type 'W'
        END IF;

        IF c3.ma='1' OR c4_rdy='0' THEN
          c4_mix_fs_man<=mds_fs_man_v;
          c4_mix_sticky<=mds_sticky_v;
          c4_mix_expo<=mds_expo_v;
          c4_mix_fo_s<=(cx_v.fs1_class(4) AND NOT cx_v.fop(1)) XOR
                        cx_v.fs2_class(4);
          c4_mix_nxf<=mds_nxf_v;
          c4_mix_udf<=mds_udf_v;
          c4_mix_nvf<='0';
          c4_mix_mds<=true;
        ELSE
          c4_mix_fs_man<=asc_fs_man_v;
          c4_mix_sticky<=asc_sticky_v;
          c4_mix_expo<="00" & asc_expo_v;
          c4_mix_fo_s<=asc_fo_s_v;
          c4_mix_nxf<=asc_nxf_v;
          c4_mix_udf<='0';                   -- <AVOIR> Underflow ADDSUB
          c4_mix_nvf<=c3_asc_nvf;
          c4_mix_mds<=false;
        END IF;
      END IF;
        
      IF flush='1' THEN
        c4.v<='0';
        c4_rdy<='1';
      END IF;
    END IF;
  END PROCESS Seq3;
  
  ------------------------------------------------------------------------------
  -- Etage 4 : Conversions finales
  Comb4:PROCESS (c4_mix_fs_man,c4_mix_expo,c4_mix_sticky,c4_mix_fo_s,
                 c4_mix_nxf,tem,rd,c4_mix_mds,c4_mds_unf,c4_rdy,
                 c4_asc_fcc,c4_mix_nvf,c4_mix_udf,flush,c2,c3,c4,
                 c2_fs2_exp,c2_fs2_exp0,c2_fs2_man) IS
    VARIABLE nxf_v,ovf_v : std_logic;
    VARIABLE etq_fo_v : uv64;
    VARIABLE iii_v : uv32;
    VARIABLE etq_nvf_v,etq_ovf_v,etq_udf_v,etq_dzf_v,etq_nxf_v : std_logic;
    VARIABLE fcc_v : unsigned(1 DOWNTO 0);
    VARIABLE fo_v : uv64;
    VARIABLE rdy_v : std_logic;
    VARIABLE sdo_v : std_logic;
  BEGIN
    -----------------------------------------------------------------------
    fin_i_c<='0';
      
    -----------------------------------------------------------------------
    -- 4) Arrondi
    arrondi_infzero(fo_v,ovf_v,nxf_v,
                    c4_mix_fs_man,c4_mix_expo,c4_mix_sticky,c4_mix_fo_s,
                    c4.sdo,c4_mix_nxf,c4.fop,tem(X_UF),c4.rd,c4_mix_mds);

    -- 4) Test nombres exceptionnels
    test_special(etq_fo_v,iii_v,fcc_v,
                 etq_nvf_v,etq_ovf_v,etq_udf_v,etq_dzf_v,etq_nxf_v,
                 fo_v,c4_mix_fs_man(52 DOWNTO 21),c4_asc_fcc,
                 c4_mix_nvf,ovf_v,c4_mix_udf,nxf_v,
                 c4.fs1_class,c4.fs2_class,
                 c4.fop);
      
    fo_v:=conv_out(etq_fo_v,c4.sdo);
    exc_i_c<=etq_nvf_v & etq_ovf_v & etq_udf_v & etq_dzf_v & etq_nxf_v;
    fcc_i_c<=fcc_v;
    sdo_v:=c4.sdo;
    
    -- 4) Conversion finale
    unf_i_c<='0';
    IF c4.v='1' THEN
      fin_i_c<=c4_rdy;
      CASE c4.fop IS
        WHEN FOP_MUL | FOP_DIV | FOP_SQRT | FOP_fTOf =>
          IF NOT DENORM_HARD THEN
            unf_i_c<=c4_mds_unf;
          ELSE
            unf_i_c<='0';
          END IF;
          
        WHEN FOP_ADD | FOP_SUB | FOP_CMP  | FOP_CMPE | FOP_iTOf =>
          unf_i_c<='0';
          
        WHEN OTHERS => -- FOP_fTOi
          fo_v(63 DOWNTO 32):=iii_v;
          unf_i_c<='0';
          
      END CASE;
      sdo_v:=c4.sdo;
      
    ELSIF c2.v='1' AND c3.v='0' THEN
      IF c2.fop=FOP_MOV OR c2.fop=FOP_NEG OR c2.fop=FOP_ABS THEN
        fin_i_c<='1';
        fo_v(63 DOWNTO 32):=c2.fs2_class(4) & c2_fs2_exp(7 DOWNTO 1) &
                             c2_fs2_exp0 & c2_fs2_man(51 DOWNTO 29);
        exc_i_c<="00000";
        unf_i_c<='0';
      END IF;
      sdo_v:='0';
      
    END IF;
    
    fd_i_c<=mux(sdo_v,fo_v,fo_v(63 DOWNTO 32) & fo_v(63 DOWNTO 32));
    
    IF flush='1' THEN
      fin_i_c<='0';
    END IF;
    
  END PROCESS Comb4;
  
  ------------------------------------------------------------------------------
  Seq4:PROCESS(clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      IF stall='1' AND fin_i_c='1' AND mem_stall='0' THEN
        mem_stall<='1';
        mem_fd<=fd_i_c;
        mem_fcc<=fcc_i_c;
        mem_exc<=exc_i_c;
        mem_unf<=unf_i_c;
      END IF;

      IF stall='0' AND (fin_i_c='0' OR mem_stall='1') THEN
        mem_stall<='0';
      END IF;

      IF flush='1' THEN
        mem_stall<='0';
      END IF;
    END IF;
  END PROCESS Seq4;
  
  ------------------------------------------------------------------------------
  fin<=fin_i_c OR mem_stall;
  
  fd <=fd_i_c  WHEN mem_stall='0' OR NOT SSTALL ELSE mem_fd;
  fcc<=fcc_i_c WHEN mem_stall='0' OR NOT SSTALL ELSE mem_fcc;
  exc<=exc_i_c WHEN mem_stall='0' OR NOT SSTALL ELSE mem_exc;
  unf<=unf_i_c WHEN mem_stall='0' OR NOT SSTALL ELSE mem_unf;
  

    
END ARCHITECTURE rtl;

