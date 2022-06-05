--------------------------------------------------------------------------------
-- TEM : TACUS
-- Unité entière PIPE5 : Version pipelinée à 5 étages
--------------------------------------------------------------------------------
-- DO 4/2009
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

-- <ALU>
--        | FETCH   |         |         |         |         |         |
--        |         | DECODE  |         |         |         |         |
--        |         |         | EXECUTE |         |         |         |
--        |         |         |         | (MEMORY)|         |         |
--        |         |         |         |         | WRITE   |         |

-- <LOAD>
--        | FETCH   |         |         |         |         |         |
--        |         | DECODE  |         |         |         |         |
--        |         |         | EXECUTE |         |         |         |
--        |         |         |         | MEMORY  |         |         |
--        |         |         |         |         | WRITE   |         |

-- <LOAD_DOUBLE>
--        | FETCH   |         |         |         |         |         |
--        |         | DECODE  | DECODE  |         |         |         |
--        |         |         | EXECUTE | EXECUTE |         |         |
--        |         |         |         | MEMORY  | MEMORY  |         |
--        |         |         |         |         | WRITE   | WRITE   |

-- <STORE>
--        | FETCH   |         |         |         |         |         |
--        |         | DECODE  | DECODE  |         |         |         |
--        |         |         | EXECUTE | EXECUTE |         |         |
--        |         |         |         |         | MEMORY  |         |
--        |         |         |         |         |         | WRITE   |

-- <STORE_DOUBLE>
--        | FETCH   |         |         |         |         |         |
--        |         | DECODE  | DECODE  | DECODE  |         |         |
--        |         |         | EXECUTE | EXECUTE | EXECUTE |         |
--        |         |         |         |         | MEMORY  | MEMORY  |
--        |         |         |         |         |         | WRITE   | WRITE

-- TRAPs :
--   DECODE : Erreur d'accès bus instructions, instruction invalide
--   EXECUTE : Erreur d'opération : Désaligné, division par Zéro...
--   WRITE : Erreur d'accès bus données

-- FETCH -> DECODE -> EXECUTE : Détection du trap
--   MEMORY -> WRITE -> Démarrage du trap ->
--   EXECUTE -> Changement de fenêtre, Double cycle, charge nouveau psr,pc
--     MEMORY ->: Rien, Rien
--       WRITE : Ecrit R17=PC
--       WRITE : Ecrit R18=nPC

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

USE std.textio.ALL;

USE work.base_pack.ALL;
USE work.plomb_pack.ALL;
USE work.asi_pack.ALL;
USE work.iu_pack.ALL;
USE work.disas_pack.ALL;
USE work.cpu_conf_pack.ALL;

ARCHITECTURE pipe5 OF iu IS

  CONSTANT NWINDOWS : natural :=CPUCONF(CPUTYPE).NWINDOWS;
  SUBTYPE regnum IS natural RANGE 0 TO NWINDOWS*16 + 7;  
  CONSTANT IU_IMP_VERSION : uv8 := CPUCONF(CPUTYPE).IU_IMP_VER;
  CONSTANT IFLUSH  : boolean := CPUCONF(CPUTYPE).IFLUSH;
  CONSTANT CASA    : boolean := CPUCONF(CPUTYPE).CASA;
  CONSTANT MULDIV  : boolean := CPUCONF(CPUTYPE).MULDIV;
  CONSTANT FPU_VER : unsigned(2 DOWNTO 0) := CPUCONF(CPUTYPE).FPU_VER;
  

--------------------------------------------------------------------------------
  TYPE type_pipe IS RECORD
    v        : std_logic;                -- Valide
    anu      : std_logic;                -- Annul
    cat      : type_cat;                 -- Catégorie instruction
    cycle    : natural RANGE 0 TO 2;     -- Séquence pour instruction multicycle
    trap     : type_trap;
    pc       : uv32;                     -- Seulement pour la simulation
    npc      : uv32;
    num_rs1  : regnum;
    num_rs2  : regnum;
    num_rd   : regnum;
    fst      : std_logic;                -- Fast Store
    casa     : std_logic;                -- CASA instruction
    casa_rs2 : uv32;                     -- CASA RS2
    cwp      : unsigned(4 DOWNTO 0);
    by_rs1   : uv32;
    by_sel1  : unsigned(0 TO 1);
    by_rs2   : uv32;
    by_sel2  : unsigned(0 TO 1);
    rd       : uv32;
    rd_maj   : std_logic;
    ry       : uv32;
    psr      : type_psr;
    data_w   : type_plomb_w;
    adrs10   : unsigned(1 DOWNTO 0);
  END RECORD;
  
  ------------------------------------------------------------------------------
  -- Bypass : true=DECODE (fast), false=EXECUTE (small)
  CONSTANT BYPASS_DEC : boolean := true;
  -- Relecture banque de registres (false) ou par le bypass (true)
  CONSTANT BYPASS_WRI : boolean := true;

  ------------------------------------------------------------------------------
  -- Teste les dépendances entre niveaux du PIPE
  FUNCTION deps (
    CONSTANT num_rs : IN regnum;
    CONSTANT pipe_dec : IN type_pipe;
    CONSTANT pipe_exe : IN type_pipe) RETURN boolean IS
  BEGIN
    IF pipe_dec.cat.mode.l='1' AND pipe_dec.v='1' AND
        pipe_dec.num_rd=num_rs AND pipe_dec.cat.mode.f='0' THEN
      RETURN true;
    END IF;
    IF pipe_exe.cat.mode.l='1' AND pipe_exe.v='1' AND
        pipe_exe.num_rd=num_rs AND pipe_exe.cat.mode.f='0' THEN
      RETURN true;
    END IF;
    RETURN false;
  END FUNCTION deps;

  -- BYPASS, option DEC
  PROCEDURE bypass_sel (
    SIGNAL   rs       : OUT uv32;
    SIGNAL   sel      : OUT unsigned(0 TO 1);
    CONSTANT num_rs   : IN  regnum;
    CONSTANT pipe_dec : IN  type_pipe;
    CONSTANT pipe_exe : IN  type_pipe;
    CONSTANT pipe_mem : IN  type_pipe;
    CONSTANT pipe_wri : IN  type_pipe) IS
  BEGIN
    IF num_rs=0 THEN
      sel<="11";      -- R0=0
      rs<=x"00000000";
    ELSIF pipe_dec.num_rd=num_rs AND pipe_dec.v='1' AND pipe_dec.rd_maj='1' THEN
      sel<="01";      -- Rebouclage sur place niveau EXE
      rs<=x"00000000"; 
    ELSIF pipe_exe.num_rd=num_rs AND pipe_exe.v='1' AND pipe_exe.rd_maj='1' THEN
      sel<="11";      -- Injection EXE
      rs<=pipe_exe.rd;
    ELSIF pipe_mem.num_rd=num_rs AND pipe_mem.v='1' AND pipe_mem.rd_maj='1' AND
      BYPASS_WRI THEN
      sel<="10";      -- Injection WRI
      rs<=x"00000000";
    ELSE
      sel<="00";      -- Accès registre direct
      rs<=x"00000000";
    END IF;
  END bypass_sel;
  
  FUNCTION bypass_mux (
    CONSTANT mux      : IN unsigned(0 TO 1);
    CONSTANT reg      : IN uv32;
    CONSTANT exe      : IN uv32;
    CONSTANT wri      : IN uv32;
    CONSTANT dec      : IN uv32) RETURN unsigned IS
    VARIABLE val : unsigned(0 TO 1);
  BEGIN
    CASE mux IS
      WHEN "00"   => RETURN reg;        -- Accès registre
      WHEN "01"   => RETURN exe;        -- Bypass direct EXE
      WHEN "10"   =>
        IF BYPASS_WRI THEN
          RETURN wri;        -- Bypass Write
        ELSE
          RETURN dec;        -- Défaut
        END IF;
      WHEN OTHERS => RETURN dec;        -- Bypass autres niveaux
    END CASE;
  END FUNCTION bypass_mux;
  
  -- Bypass, option EXE
  FUNCTION bypass (
    CONSTANT rs       : IN uv32;
    CONSTANT num_rs   : IN regnum;
    CONSTANT pipe_exe : IN type_pipe;
    CONSTANT pipe_mem : IN type_pipe;
    CONSTANT pipe_wri : IN type_pipe) RETURN uv32 IS
  BEGIN
    IF num_rs=0 THEN
      RETURN x"00000000";
    ELSIF pipe_exe.num_rd=num_rs AND pipe_exe.v='1' AND pipe_exe.rd_maj='1' THEN
      RETURN pipe_exe.rd;
    ELSIF pipe_mem.num_rd=num_rs AND pipe_mem.v='1' AND pipe_mem.rd_maj='1' THEN
      RETURN pipe_mem.rd;
    ELSIF pipe_wri.num_rd=num_rs AND pipe_wri.v='1' AND pipe_wri.rd_maj='1'
      AND BYPASS_WRI THEN
      RETURN pipe_wri.rd;
    ELSE
      RETURN rs;
    END IF;
  END FUNCTION bypass;
  
  ------------------------------------------------------------------------------
  CONSTANT VIDE : string := "...";
  CONSTANT ZERO : uv32 := x"00000000";
  
  SIGNAL rs1,rs2,rd_c : uv32;
  SIGNAL num_rd_c : regnum;
  SIGNAL rd_maj : std_logic;
  
  SIGNAL pc    : uv32;              -- Program Counter
  SIGNAL npc   : uv32;              -- nPC
  SIGNAL psr   : type_psr;          -- Processor Status Register
  SIGNAL wim   : unsigned(NWINDOWS-1 DOWNTO 0);
  SIGNAL tbr   : type_tbr;          -- Trap Base Register
  SIGNAL ry    : uv32;              -- Registre Y
  
  --------------------------------------
  -- FETCH
  SIGNAL xx_stall : std_logic;
  SIGNAL inst_w_i : type_plomb_w;
  SIGNAL inst_w_mem : type_plomb_w;
  SIGNAL inst_lev : natural RANGE 0 TO 2;
  SIGNAL inst_aec : natural RANGE 0 TO 2;
  
  --------------------------------------
  -- DECODE
  SIGNAL inst_r_mem,inst_r_mem2 : type_plomb_r;
  SIGNAL inst_r_lev : natural RANGE 0 TO 2;
  SIGNAL inst_dval_c : std_logic;
  SIGNAL pipe_dec,pipe_dec_c : type_pipe;
  SIGNAL as_dec_c : std_logic;  -- AS=Au Suivant
  SIGNAL na_c : std_logic;
  SIGNAL annul,annul_c : std_logic;
  SIGNAL cycle_dec,cycle_dec_c : natural RANGE 0 TO 2;
  SIGNAL npc_c,npc_p4 : uv32;
  SIGNAL npc_cont_c : std_logic;
  SIGNAL npc_super_c : std_logic;
  SIGNAL dias_dec : string(1 TO 50);
  ALIAS dias : string(1 TO 50) IS dias_dec;
  SIGNAL vazy_mem : std_logic;
  SIGNAL dir_rs1_c,dir_rdi_c : uv32;
  SIGNAL cwp_dec,cwp_dec_c : unsigned(4 DOWNTO 0);
  SIGNAL n_rs1_c,n_rs2_c,dec_n_rs1_c,dec_n_rs2_c : regnum;
  
  --------------------------------------
  -- EXECUTE
  SIGNAL pipe_exe,pipe_exe_c : type_pipe;
  SIGNAL as_exe_c,as_exe : std_logic;  -- AS=Au Suivant
  SIGNAL psr_c : type_psr;
  SIGNAL ry_c : uv32;
  SIGNAL npc_exe_c,npc_exe : uv32;
  SIGNAL dias_exe : string(1 TO 50);
  SIGNAL rs1_muldiv,rs2_muldiv : uv32;
  SIGNAL endlock_c,endlock : std_logic;
  SIGNAL muldiv_op : uv2;  -- 0:MUL 1:DIV | 0:Unsigned 1:Signed
  SIGNAL muldiv_req_c : std_logic;
  SIGNAL muldiv_ack : std_logic;
  SIGNAL muldiv_ack_mem : std_logic;
  SIGNAL muldiv_rd_o  : uv32;
  SIGNAL muldiv_ry_o  : uv32;
  SIGNAL muldiv_icc_o : type_icc;
  SIGNAL muldiv_dz_o  : std_logic;

  --------------------------------------
  -- MEMORY
  SIGNAL pipe_mem,pipe_mem_c : type_pipe;
  SIGNAL as_mem_c : std_logic;  -- AS=Au Suivant
  SIGNAL dias_mem : string(1 TO 50);
  SIGNAL data_aec : natural RANGE 0 TO 1;
  SIGNAL data_wu_req : std_logic;
  SIGNAL data_w_c : type_plomb_w;
  
  --------------------------------------
  -- WRITE
  SIGNAL pipe_wri : type_pipe;
  SIGNAL pipe_wri_v_c : std_logic;
  SIGNAL as_wri_c : std_logic;  -- AS=Au Suivant
  SIGNAL regs_maj_c : std_logic;
  SIGNAL dias_wri : string(1 TO 50);
  
  SIGNAL tbr_trap_c : uv8;
  SIGNAL trap_stop_c,trap_stop : std_logic;
  SIGNAL trap_stop_delay : std_logic;
  SIGNAL trap_pc,trap_npc : uv32;
  SIGNAL halterror_c,halterror : std_logic;
  SIGNAL trap_c : type_trap;

  SIGNAL debug_rd  : uv32;
  SIGNAL dstop_c,dstop,udstop : std_logic;
  SIGNAL psr_fin   : type_psr;
  SIGNAL ry_fin    : uv32;
  SIGNAL halterror_trap : type_trap;
  SIGNAL casa_cmp_c,casa_cmp : std_logic;
  
  --------------------------------------
  -- FPU
  SIGNAL fpu_do : uv32;
  SIGNAL fpu_do_ack : std_logic;
  SIGNAL fpu_di : uv32;
  SIGNAL fpu_di_maj : std_logic;
  SIGNAL fpu_fcc   : unsigned(1 DOWNTO 0);
  SIGNAL fpu_fccv  : std_logic;
  SIGNAL fpu_req_c   : std_logic;
  SIGNAL fpu_rdy   : std_logic;
  SIGNAL fpu_wri_c : std_logic;
  SIGNAL fpu_present : std_logic;
  SIGNAL fpu_fexc  : std_logic;
  SIGNAL fpu_fxack : std_logic;
  
  --------------------------------------
  -- Debug
  -- Trace exécution

  SIGNAL syn_npc_dec_c : uv32;
  FILE fil : text OPEN write_mode IS "Trace_pipe5.log";
  ATTRIBUTE KEEP : string;
  ATTRIBUTE KEEP OF syn_npc_dec_c : SIGNAL IS "true";
  ATTRIBUTE KEEP OF npc_p4        : SIGNAL IS "true";
BEGIN
  
  ------------------------------------------------------------------------------
  iregs: ENTITY work.iu_regs_2r1w
    GENERIC MAP (
      THRU => NOT BYPASS_WRI,
      NREGS => NWINDOWS*16+8)
    PORT MAP (
      n_rs1    => n_rs1_c,
      rs1      => rs1,
      n_rs2    => n_rs2_c,
      rs2      => rs2,
      n_rd     => num_rd_c,
      rd       => rd_c,
      rd_maj   => rd_maj,
      clk      => clk);

  n_rs1_c<=dec_n_rs1_c WHEN BYPASS_DEC ELSE pipe_dec_c.num_rs1;
  n_rs2_c<=dec_n_rs2_c WHEN BYPASS_DEC ELSE pipe_dec_c.num_rs2;
  
  i_muldiv: ENTITY work.iu_muldiv
    GENERIC MAP (
      MULDIV   => MULDIV,
      TECH     => TECH)
    PORT MAP (
      op       => muldiv_op,
      req      => muldiv_req_c,
      ack      => muldiv_ack,
      rs1      => rs1_muldiv,
      rs2      => rs2_muldiv,
      ry       => ry,
      rd_o     => muldiv_rd_o,
      ry_o     => muldiv_ry_o,
      icc_o    => muldiv_icc_o,
      dz_o     => muldiv_dz_o,
      clk      => clk);
      
  muldiv_op<=pipe_dec.cat.op(21) & pipe_dec.cat.op(19);

  fpu_i.cat   <=pipe_dec_c.cat;
  fpu_i.pc    <=pc;
  fpu_i.req   <=fpu_req_c;
  fpu_i.wri   <=fpu_wri_c;
  fpu_i.tstop <=trap_stop;
  fpu_i.fxack <=fpu_fxack;
  fpu_i.do_ack<=fpu_do_ack;
  fpu_i.di    <=fpu_di;
  fpu_i.di_maj<=fpu_di_maj;
  fpu_i.dstop <=dstop;
  fpu_i.ver   <=FPU_VER;

  fpu_present <=fpu_o.present;
  fpu_rdy     <=fpu_o.rdy;
  fpu_fexc    <=fpu_o.fexc;
  fpu_do      <=fpu_o.do;
  fpu_fcc     <=fpu_o.fcc;
  fpu_fccv    <=fpu_o.fccv;
  
  --------------------------------------
  Sync_FETCH:PROCESS(clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      IF trap_stop='1' AND dstop='0' THEN
        pc<=npc_c;
        npc<=npc_c OR x"00000004";
      ELSIF na_c='1' AND (dstop='0' OR debug_t.ppc='1') THEN
        pc<=npc;
        npc<=npc_c;
      END IF;
      
      IF trap_stop_delay='1' AND trap_stop='0' THEN
        IF dstop='0' THEN
          inst_w_i<=plomb_rd(npc_c,ASI_SUPER_INSTRUCTION,LDST_UW);
          inst_w_i.req<='1';
          inst_w_mem<=
            plomb_rd(npc_c OR x"00000004",ASI_SUPER_INSTRUCTION,LDST_UW);
          inst_w_mem.cont<='1';
          inst_w_mem.req<='1';
          inst_lev<=2;
        END IF;
      ELSIF na_c='1' AND (dstop='0' OR debug_t.ppc='1') AND trap_stop='0' THEN
        -- Adresse suivante
        IF inst_lev=0 OR
          (inst_lev=1 AND inst_w_i.req='1' AND inst_r.ack='1') THEN
          -- On pousse directement
          inst_w_i<=plomb_rd(npc_c,x"00",LDST_UW);
          inst_w_i.cont<=npc_cont_c;
          inst_w_i.asi<=mux(npc_super_c,
                            ASI_SUPER_INSTRUCTION,ASI_USER_INSTRUCTION);
          inst_w_i.req<=NOT dstop;
          inst_lev<=1;
          
        ELSE
          -- On pousse au niveau 1
          inst_w_mem<=plomb_rd(npc_c,x"00",LDST_UW);
          inst_w_mem.cont<=npc_cont_c;
          inst_w_mem.asi<=mux(npc_super_c,
                              ASI_SUPER_INSTRUCTION,ASI_USER_INSTRUCTION);
          inst_w_mem.req<=NOT dstop;
          IF inst_r.ack='0' OR dstop='1' THEN
            inst_lev<=2;
          ELSE
            inst_w_i<=inst_w_mem;
          END IF;
        END IF;
      ELSE
        IF inst_lev=1 AND inst_w_i.req='1' AND inst_r.ack='1' THEN
          inst_w_i.req<='0';
          inst_lev<=0;
        ELSIF inst_lev=2 AND inst_w_i.req='1' AND inst_r.ack='1' THEN
          inst_w_i<=inst_w_mem;
          inst_w_i.req<='1';
          inst_lev<=1;
        END IF;
        IF inst_lev>0 AND dstop='0' AND inst_w_i.req='0' THEN
          inst_w_i.req<='1';
        END IF;
      END IF;

      inst_w_i.dack<='1';
      
      -- LEV : Nombre d'accès demandés, en attente
      -- AEC : Nombre d'accès en cours (entre REQ et DREQ)
      IF inst_w_i.req='1' AND inst_r.ack='1' AND NOT inst_r.dreq='1' THEN
        inst_aec<=inst_aec+1;
      ELSIF NOT (inst_w_i.req='1' AND inst_r.ack='1') AND inst_r.dreq='1' THEN
        inst_aec<=inst_aec-1;
      END IF;
      
      ------------------------------------
      IF as_dec_c='1' AND inst_r.dreq='0' THEN
        IF inst_r_lev/=0 THEN
          inst_r_lev<=inst_r_lev-1;
        END IF;
        inst_r_mem<=inst_r_mem2;
      ELSIF as_dec_c='1' AND inst_r.dreq='1' THEN
        IF inst_r_lev=2 THEN
          inst_r_mem<=inst_r_mem2;
        ELSE
          inst_r_mem<=inst_r;
        END IF;
      ELSIF as_dec_c='0' AND inst_r.dreq='1' THEN
        IF inst_r_lev=0 THEN
          inst_r_mem<=inst_r;
        END IF;
        inst_r_lev<=inst_r_lev+1;
      END IF;
      IF inst_r.dreq='1' THEN
        inst_r_mem2<=inst_r;
      END IF;

      IF debug_t.vazy='1' AND dstop='1' THEN
        inst_r_mem.d   <=debug_t.op;
        inst_r_mem.code<=debug_t.code;
        inst_r_lev<=1;
      END IF;
        
      ASSERT inst_r.dreq='0' OR inst_r_lev/=2 OR as_dec_c='1'
        REPORT "ECRASEMENT" SEVERITY error;

      IF reset_n='0' THEN
        inst_w_i.req<='0';
        inst_w_i.dack<='1';
        inst_lev<=0;
        inst_aec<=0;
        inst_r_lev<=0;
      END IF;  
    END IF;

  END PROCESS Sync_FETCH;

  inst_w<=inst_w_i;
                 
  ------------------------------------------------------------------------------
  -- DECODE
  Comb_DECODE:PROCESS(inst_r,inst_r_mem,inst_r_lev,pipe_dec_c,npc_p4,cwp_dec,
                      dir_rs1_c,dir_rdi_c,annul,cycle_dec,pc,npc,as_exe_c,
                      psr_c,trap_stop,fpu_rdy,fpu_fcc,fpu_fexc, fpu_fccv,
                      dstop,udstop,pipe_dec,pipe_exe,pipe_mem,pipe_wri,tbr,
                      npc_exe_c,debug_t,trap_stop_delay) IS
    VARIABLE cat_v     : type_cat;
    VARIABLE npc_v     : uv32;
    VARIABLE npc_mav   : std_logic;
    VARIABLE n_rs1_v   : uint5;
    VARIABLE n_rs2_v   : uint5;
    VARIABLE n_rd_v    : uint5;
    VARIABLE num_rs1_v : regnum;
    VARIABLE num_rs2_v : regnum;
    VARIABLE num_rd_v  : regnum;
    VARIABLE trap_dec_v : type_trap;
    VARIABLE annul_v   : std_logic;
    VARIABLE ncycles_v  : natural RANGE 0 TO 2;
    VARIABLE next_cwp_v : unsigned(4 DOWNTO 0);
    VARIABLE inst_d_v : uv32;
    VARIABLE inst_code_v : enum_plomb_code;
    VARIABLE inst_dval_v : std_logic;
    VARIABLE fst_v : std_logic;
  BEGIN
    
    IF inst_r_lev/=0 THEN
      inst_d_v:=inst_r_mem.d;
      inst_code_v:=inst_r_mem.code;
      inst_dval_v:='1';
    ELSE
      inst_d_v:=inst_r.d;
      inst_code_v:=inst_r.code;
      inst_dval_v:=inst_r.dreq;
    END IF;
    
    inst_dval_c<=inst_dval_v;
    
    --------------------------------------------------------------
    decode(inst_d_v,IFLUSH,CASA,cat_v,n_rd_v,n_rs1_v,n_rs2_v);
    op_dec(op=>inst_d_v,pc=>pc,npc_o=>npc_v,npc_maj=>npc_mav,
           psr=>psr_c,fcc=>fpu_fcc,fexc=>fpu_fexc,annul_o=>annul_v);
    
    IF inst_code_v/=PB_OK AND annul='0' THEN
      trap_dec_v:=plomb_trap_inst(inst_code_v);
    ELSIF ((pc(31 DOWNTO 2)=debug_t.ib(31 DOWNTO 2) AND debug_t.ib_ena='1') OR
        udstop='1') AND cycle_dec=0 AND dstop='0' AND annul='0' THEN
      trap_dec_v:=TT_WATCHPOINT_DETECTED;
    ELSE
      trap_dec_v:=TT_NONE;
    END IF;
    IF inst_dval_v='0' OR (trap_stop='1' AND dstop='0') THEN
      trap_dec_v:=TT_NONE;
    END IF;
    -- Anticipe le futur PSR.CWP : SAVE, RESTORE, RETT
    next_cwp_v:=cwpcalc(psr_c.cwp,cat_v.m_psr_cwp AND NOT annul,'0',inst_d_v,
                        NWINDOWS);
    cwp_dec_c<=next_cwp_v;
    
    --------------------------------------
    -- Init pipe
    pipe_dec_c.anu   <=annul;
    pipe_dec_c.cat   <=cat_v;
    pipe_dec_c.cycle <=cycle_dec;
    pipe_dec_c.trap  <=trap_dec_v;

    IF cycle_dec=0 THEN
      pipe_dec_c.rd_maj<=cat_v.m_reg;
    ELSIF cycle_dec=1 THEN
      pipe_dec_c.rd_maj<=cat_v.mode.l AND
                          ((cat_v.mode.d AND NOT cat_v.mode.f) OR cat_v.mode.s);
    ELSE
      pipe_dec_c.rd_maj<='0';
    END IF;

    IF (inst_d_v(13)='1' OR n_rs2_v=0) AND cat_v.mode.s='1' AND
      cat_v.mode.l='0' THEN
      -- Immédiat ou 1 registre, store en 1 cycle.
      fst_v:='1';
    ELSE
      fst_v:='0';
    END IF;
    
    pipe_dec_c.fst<=fst_v;
    pipe_dec_c.casa<=to_std_logic(CASA AND
      inst_d_v(31 DOWNTO 30)="11" AND inst_d_v(24 DOWNTO 19)="111100");
    
    IF (cycle_dec=1 AND (cat_v.mode.s='0' OR fst_v='1')) OR
       (cycle_dec=2 AND (cat_v.mode.s='0' OR cat_v.mode.l='0')) THEN
      n_rd_v:=to_integer(to_unsigned(n_rd_v,10) OR "0000000001");
    END IF;
    
    num_rs1_v:=regad(n_rs1_v,cwp_dec,NWINDOWS);
    pipe_dec_c.num_rs1<=num_rs1_v;
    IF cycle_dec=0 AND fst_v='0' THEN
      num_rs2_v:=regad(n_rs2_v,cwp_dec,NWINDOWS);
    ELSE
      num_rs2_v:=regad(n_rd_v,cwp_dec,NWINDOWS);  -- STORE : Lecture RD     
    END IF;
    pipe_dec_c.num_rs2<=num_rs2_v;
    
    num_rd_v:=regad(n_rd_v,next_cwp_v,NWINDOWS);

    dec_n_rs1_c<=num_rs1_v;
    dec_n_rs2_c<=num_rs2_v;
    
    pipe_dec_c.num_rd <=num_rd_v;
    pipe_dec_c.cwp<=next_cwp_v;
    bypass_sel(pipe_dec_c.by_rs1,pipe_dec_c.by_sel1,
               num_rs1_v,pipe_dec,pipe_exe,pipe_mem,pipe_wri);
    bypass_sel(pipe_dec_c.by_rs2,pipe_dec_c.by_sel2,
               num_rs2_v,pipe_dec,pipe_exe,pipe_mem,pipe_wri);
    pipe_dec_c.rd<=x"00000000";
    pipe_dec_c.ry<=x"00000000";
    pipe_dec_c.psr<=PSR_0;
    pipe_dec_c.data_w<=plomb_rd(x"00000000",ASI_USER_DATA,LDST_UW);
    pipe_dec_c.adrs10<="00";
    pipe_dec_c.pc    <=pc;
    pipe_dec_c.npc   <=mux(pipe_dec.cat.mode.j AND pipe_dec.v,
                           npc_exe_c,npc);

    --------------------------------------
    xx_stall<='0';
    fpu_req_c<='0';
    as_dec_c<='0';
    
    IF trap_stop='1' THEN
      copie(dias_dec,"<TRAP>");
      as_dec_c<='1';
      na_c<='0';
      annul_c<='0';
      cycle_dec_c<=0;
      pipe_dec_c.v<='0';
      
    ELSIF as_exe_c='0' THEN
      -- Bloquage pipe : Stall sur instruction IU avec IU non prête
      na_c<='0';
      xx_stall<='H';
      pipe_dec_c<=pipe_dec;
      cycle_dec_c<=cycle_dec;
      annul_c<=annul;
      pipe_dec_c.by_rs1<=dir_rs1_c;
      pipe_dec_c.by_rs2<=dir_rdi_c;
      pipe_dec_c.by_sel1<="11";         -- Force maintien
      pipe_dec_c.by_sel2<="11";
      
    ELSIF inst_dval_v='0' THEN
      -- Pas d'instruction
      copie(dias_dec,VIDE);
      as_dec_c<='1';
      na_c<='0';
      annul_c<=annul;
      cycle_dec_c<=0;
      pipe_dec_c.v<='0';
      
    ELSIF annul='1' OR trap_dec_v.t='1' THEN
      -- L'instruction annulée ne fait rien
      IF annul='1' THEN
        copie(dias_dec,"<ANNUL>");
      ELSE
        copie(dias_dec,"<TRAP : " & trap_decode(trap_dec_v) & ">");
      END IF;
      as_dec_c<='1';
      na_c<='1';
      annul_c<='0';
      cycle_dec_c<=0;
      pipe_dec_c.v<='1';
      pipe_dec_c.rd_maj<='0';
      pipe_dec_c.cat.mode<=CALC;
      
    ELSIF (deps(num_rs1_v,pipe_dec,pipe_exe) AND
           cat_v.r_reg(1)='1' AND n_rs1_v/=0)
      OR (deps(num_rs2_v,pipe_dec,pipe_exe) AND
          ((cat_v.r_reg(2)='1' AND cycle_dec=0  AND n_rs2_v/=0) OR
           (cat_v.r_reg(3)='1' AND (cycle_dec/=0 OR fst_v='1') AND n_rd_v/=0
            --AND (cat_v.mode.l='0' OR cat_v.mode.s='0')
            )))
      -- Stall si un JMPL ou un RETT est dans le niveau EXE, sauf si
      -- l'instruction au niveau DEC est un JMPL ou un RETT
      OR (cat_v.mode.j='0' AND pipe_dec.cat.mode.j='1' AND pipe_dec.v='1')
      -- Stall sur instruction FPU avec FPU non prête
      OR (cat_v.mode.f='1' AND fpu_rdy='0' AND cycle_dec=0)
      -- Stall si FBfcc avec FPU non prète... Car un trap peut survenir !
      OR (inst_d_v(31 DOWNTO 30)="00" AND
          inst_d_v(24 DOWNTO 22)="110" AND fpu_rdy='0')
      -- Stall sur FBfcc avec FPU non prête
      OR (cat_v.r_fcc='1' AND fpu_fccv='0')
      OR (pipe_dec.cat.m_psr='1' AND pipe_dec.v='1' AND BSD_MODE)  -- NetBSD !
    THEN
      na_c<='0';
      pipe_dec_c.v<='0';
      cycle_dec_c<=cycle_dec;
      annul_c<=annul;
      xx_stall<='1';
    ELSE
      -- Il y a une vraiment une instruction à exécuter...
      copie(dias_dec,disassemble(inst_d_v,pc));

      -- <AFAIRE> : TRAP FPU !
      annul_c<=annul_v;

      IF cat_v.mode.s='1' AND fst_v='0'
        AND (cat_v.mode.d='1' OR cat_v.mode.l='1') THEN
        -- STD 2 registres, SWAP/LDSTUB
        ncycles_v:=2;
      ELSIF (cat_v.mode.s='1' AND fst_v='0') OR cat_v.mode.d='1' THEN
        -- ST 2 registres, LDD
        ncycles_v:=1;
      ELSE
        ncycles_v:=0;
      END IF;
      
      IF cycle_dec=0 THEN
        fpu_req_c<='1';
      END IF;
      IF cycle_dec>=ncycles_v THEN
        as_dec_c <='1';
        na_c<=NOT cat_v.mode.j;
        cycle_dec_c<=0;
      ELSE
        na_c<='0';
        cycle_dec_c<=cycle_dec+1;
      END IF;
      
      pipe_dec_c.v<='1';
      
    END IF;
    -----------------------------------------------------------------
    syn_npc_dec_c<=npc_v;               -- Optim. Synth.
    
    IF trap_stop_delay='1' THEN
      npc_c<=tbr.tba & tbr.tt & "0000";
      npc_cont_c<='0';
    ELSIF pipe_dec.cat.mode.j='1' AND pipe_dec.v='1' AND as_exe_c='1' THEN
      -- Injection de nPC issu du niveau EXE : Instructions JMPL, RETT
      npc_c<=npc_exe_c;
      npc_cont_c<='0';
      na_c<='1';
    ELSIF npc_mav='1' AND annul='0' THEN
      -- Instructions de saut
      npc_c<=npc_v;
      npc_cont_c<='0';
    ELSE
      npc_c<=npc_p4;
      npc_cont_c<='1';
    END IF;
    
  END PROCESS Comb_DECODE;
  
  -- Test RETT instruction
  npc_super_c<=psr.ps WHEN
                pipe_dec_c.cat.op(31 DOWNTO 30)="10" AND
                pipe_dec_c.cat.op(24 DOWNTO 19)="111001"
          ELSE psr_c.s;

  -- JMPL + PRIV = RETT !
  --npc_super_c<=mux(pipe_dec_c.cat.mode.j AND pipe_dec_c.cat.priv,psr.ps,psr_c.s);
  npc_p4<=npc+4;
  
  --------------------------------------
  --pragma synthesis_off
  Test_BADACCE5: PROCESS(clk) IS
  BEGIN
    IF falling_edge(clk) THEN
      ASSERT inst_r.d/=x"BADACCE5" OR inst_r.code/=PB_OK OR
        annul='1' OR inst_r.dreq='0'
        REPORT "Instruction BADACCE5, PC=" & To_HString(pc)
        SEVERITY error;
    END IF;
  END PROCESS Test_BADACCE5;
  --pragma synthesis_on
  
  --------------------------------------
  Sync_DECODE:PROCESS(clk,reset_n) IS
    VARIABLE lout : line;
    VARIABLE c : string(1 TO 3);
  BEGIN
    IF rising_edge(clk) THEN
      --pragma synthesis_off
      IF DUMP THEN
        IF pipe_dec_c.anu='0' THEN
          c:=" : ";
        ELSE
          c:="nul";
        END IF;
        IF (pipe_dec_c.v='1' AND as_dec_c='1') THEN
          write (lout,string'(CID & "  " & To_HString(pipe_dec_c.pc) & c &
                              disassemble(pipe_dec_c.cat.op,pc)) &
                              " {" & time'image(now) & " } ");
          writeline (fil,lout);
        END IF;
      END IF;
      --pragma synthesis_on
      annul<=annul_c;
      pipe_dec<=pipe_dec_c;
      cycle_dec<=cycle_dec_c;
      vazy_mem<=(debug_t.vazy OR vazy_mem) AND NOT as_dec_c;
      
      IF pipe_dec_c.v='0' THEN
        cwp_dec<=psr_c.cwp;
      ELSIF as_exe_c='1' AND pipe_dec_c.v='1' THEN
        cwp_dec<=cwp_dec_c;
      END IF;
      
      IF debug_t.stop='1' THEN
        udstop<='1';
      ELSIF dstop='1' OR debug_t.run='1' THEN
        udstop<='0';
      END IF;

      IF reset_n='0' THEN
        pipe_dec.v<='0';
        udstop<='0';
      END IF;

    END IF;
  END PROCESS Sync_DECODE;

  ------------------------------------------------------------------------------
  -- EXEC
  Comb_EXEC:PROCESS(pipe_dec,psr,rs1,rs2,ry,tbr,wim,fpu_fexc,fpu_present,
                    as_mem_c,pipe_exe,pipe_mem,pipe_wri,trap_stop,psr_fin,
                    inst_dval_c,muldiv_ack,muldiv_ack_mem,muldiv_rd_o,
                    dstop,debug_t,trap_stop_delay,ry_fin,
                    as_exe,npc_exe,irl,casa_cmp_c,
                    muldiv_ry_o,muldiv_icc_o,muldiv_dz_o,fpu_do) IS
    VARIABLE rs1_v,rs2_v : uv32;
    VARIABLE rd_v,rdi_v  : uv32;
    VARIABLE sum_v       : uv32;
    VARIABLE ry_v        : uv32;
    VARIABLE npc_exe_v   : uv32;
    VARIABLE npc_mav     : std_logic;
    VARIABLE sert_a_rien : std_logic;
    VARIABLE psr_v       : type_psr;
    VARIABLE data_w_v    : type_plomb_w;
    VARIABLE trap_exe_v  : type_trap;
    VARIABLE trap_alu_v  : type_trap;
    VARIABLE trap_lsu_v  : type_trap;
  BEGIN
    IF BYPASS_DEC THEN
      rs1_v:=bypass_mux(pipe_dec.by_sel1,rs1,pipe_exe.rd,
                        pipe_wri.rd,pipe_dec.by_rs1);
      rdi_v:=bypass_mux(pipe_dec.by_sel2,rs2,pipe_exe.rd,
                        pipe_wri.rd,pipe_dec.by_rs2);
    ELSE
      rs1_v:=bypass(rs1,pipe_dec.num_rs1,pipe_exe,pipe_mem,pipe_wri);
      rdi_v:=bypass(rs2,pipe_dec.num_rs2,pipe_exe,pipe_mem,pipe_wri);
    END IF;
    dir_rs1_c<=rs1_v;
    dir_rdi_c<=rdi_v;
    IF pipe_dec.cat.op(13)='1' THEN
      rs2_v:=sext(pipe_dec.cat.op(12 DOWNTO 0),32);
    ELSIF pipe_dec.cat.op(4 DOWNTO 0)="00000" OR pipe_dec.casa='1' THEN
      rs2_v:=x"00000000";
    ELSE
      rs2_v:=rdi_v;
    END IF;

    rs1_muldiv<=rs1_v;
    rs2_muldiv<=rs2_v;
    
    fpu_do_ack<='0';
    
    op_exe(
      cat=>pipe_dec.cat,pc=>pipe_dec.pc,npc_o=>npc_exe_v,npc_maj=>sert_a_rien,
      rs1=>rs1_v,rs2=>rs2_v,rd_o=>rd_v,sum_o=>sum_v,ry=>ry,ry_o=>ry_v,
      psr=>psr,psr_o=>psr_v,
      muldiv_rd=>muldiv_rd_o,muldiv_ry=>muldiv_ry_o,muldiv_icc=>muldiv_icc_o,
      muldiv_dz=>muldiv_dz_o,cwp=>pipe_dec.cwp,
      wim=>wim,tbr=>tbr,fexc=>fpu_fexc,trap_o=>trap_alu_v,
      MULDIV=>MULDIV,IU_IMP_VERSION=>IU_IMP_VERSION);
    
    rdi_v:=mux(pipe_dec.cat.mode.f AND fpu_present,fpu_do,rdi_v);
    
    op_lsu(cat=>pipe_dec.cat,rd=>rdi_v,
           sum=>sum_v,psr=>psr,fexc=>fpu_fexc,
           IFLUSH=>IFLUSH,FPU_LDASTA=>FPU_LDASTA,CASA=>CASA,
           data_w=>data_w_v,trap_o=>trap_lsu_v);

    --------------------------------------
    trap_exe_v:=TT_NONE;
    
    -- Load/Store trap
    IF pipe_dec.cat.mode.l='1' OR pipe_dec.cat.mode.s='1' THEN
      trap_exe_v:=trap_lsu_v;
      IF trap_exe_v.t='0' AND
        data_w_v.a(31 DOWNTO 2)=debug_t.db(31 DOWNTO 2) AND
        debug_t.db_ena='1' THEN
        trap_exe_v:=TT_WATCHPOINT_DETECTED;
      END IF;
    ELSE
      trap_exe_v:=trap_alu_v;
    END IF;
    
    -- FPU disabled trap
    IF (pipe_dec.cat.mode.f='1' OR              -- FPop, LSFPU
        (pipe_dec.cat.op(31 DOWNTO 30)="00" AND -- FBfcc
         pipe_dec.cat.op(24 DOWNTO 22)="110")) THEN
      IF psr.ef='0' THEN
        trap_exe_v:=TT_FP_DISABLED;
      ELSIF fpu_fexc='1' THEN
        trap_exe_v:=TT_FP_EXCEPTION;
      END IF;
    END IF;
    -- Privilegied instruction trap (higher priority)
    IF pipe_dec.cat.priv='1' AND psr.s='0' AND dstop='0' THEN
      trap_exe_v:=TT_PRIVILEGED_INSTRUCTION;
    END IF;
    
    IF pipe_dec.cycle/=0 THEN
      trap_exe_v.t:='0';
    ELSIF pipe_dec.trap.t='1' THEN
      trap_exe_v:=pipe_dec.trap;
    ELSIF (psr.pil<irl OR irl="1111") AND psr.et='1' AND dstop='0'
      AND pipe_exe.cat.m_psr='0' 
    THEN
      trap_exe_v.t:='1';
      trap_exe_v.tt:=to_unsigned(16+to_integer(irl),8);
    END IF;
    
    --------------------------------------
    npc_exe_c<=mux(as_exe,npc_exe_v,npc_exe);
    ry_c<=ry;

    muldiv_req_c<=pipe_dec.cat.mode.m AND as_exe AND pipe_dec.v;
    
    psr_c<=psr;
    IF pipe_exe.v='1' AND pipe_exe.cat.m_psr='1' AND pipe_exe.anu='0' THEN
      -- Décalage de la mise à jour complète
      wrpsr(psr_v,pipe_exe.rd,fpu_present,NWINDOWS);
      psr_c<=psr_v;
    END IF;
    
    --------------------------------------
    IF pipe_dec.cycle=0 THEN
      pipe_exe_c<=pipe_dec;
      pipe_exe_c.rd<=rd_v;
      pipe_exe_c.casa_rs2<=rdi_v;
      pipe_exe_c.trap<=trap_exe_v;
      pipe_exe_c.adrs10<=data_w_v.a(1 DOWNTO 0);
      pipe_exe_c.data_w<=data_w_v;
    ELSE
      pipe_exe_c<=pipe_exe;
      IF pipe_dec.cat.mode.s='1' THEN
        pipe_exe_c.cycle<=pipe_dec.cycle-1;
      ELSE
        pipe_exe_c.cycle<=pipe_dec.cycle;
      END IF;
      IF pipe_dec.cat.mode.l='1' AND pipe_dec.cat.mode.s='1'
        AND pipe_dec.cycle=2 THEN
        -- Ecriture second accès SWAP/LDSTUB/CASA
        pipe_exe_c.data_w.mode<=PB_MODE_WR_ACK;
        pipe_exe_c.rd<=rd_v;
        IF pipe_dec.casa='1' AND CASA AND casa_cmp_c='0' THEN
          pipe_exe_c.data_w.be<=x"0";
        END IF;
      END IF;
      IF (pipe_dec.cycle=2
          AND NOT (pipe_dec.cat.mode.l='1' AND pipe_dec.cat.mode.s='1'))
        OR (pipe_dec.cycle=1
            AND ((pipe_dec.cat.mode.l='1' AND pipe_dec.cat.mode.d='1') OR
                 pipe_dec.fst='1')) THEN
        pipe_exe_c.data_w.a<=pipe_exe.data_w.a OR x"00000004";
      END IF;
    END IF;
    
    pipe_exe_c.rd_maj  <=pipe_dec.rd_maj;
    pipe_exe_c.num_rd  <=pipe_dec.num_rd;
    pipe_exe_c.data_w.d<=data_w_v.d;
    IF pipe_dec.cat.mode.l='1' AND pipe_dec.cat.mode.s='1' AND
      pipe_dec.cycle/=1 THEN            -- SWAP
        pipe_exe_c.data_w.d<=pipe_exe.data_w.d;
    END IF;

    --------------------------------------
    IF trap_stop='1' THEN
      ry_c<=ry;
      psr_c<=psr;
      IF trap_stop_delay='0' THEN
        ry_c<=ry_fin;       -- Récupère la valeur précédente de RY & PSR
        psr_c<=psr_fin;
        IF dstop='0' THEN
          psr_c.et<='0';
          psr_c.ps<=psr_fin.s;
          psr_c.s<='1';
          IF psr_fin.cwp=0 THEN
            psr_c.cwp<=cwpfix(to_unsigned(NWINDOWS-1,5),NWINDOWS);
          ELSE
            psr_c.cwp<=cwpfix(psr_fin.cwp - 1,NWINDOWS);
          END IF;
          copie(dias_exe,"<TRAP>");
        END IF;
      END IF;
      as_exe_c<=as_mem_c;
      pipe_exe_c.v<='0';

    ELSIF as_mem_c='0' THEN
      -- Bloquage pipe
      pipe_exe_c<=pipe_exe;
      as_exe_c<='0';
      -- Si des calculs de muldiv se termine avant l'accès mémoire, on mémorise
      -- le drapeau.
    ELSIF pipe_dec.v='0' OR pipe_dec.anu='1' THEN
      IF pipe_dec.v='0' THEN
        copie(dias_exe,VIDE);
      ELSE
        copie(dias_exe,"<ANNUL>");
      END IF;
      as_exe_c<='1';
      pipe_exe_c<=pipe_dec;
      pipe_exe_c.casa_rs2<=pipe_exe.casa_rs2;
      pipe_exe_c.data_w<=pipe_exe.data_w;
      pipe_exe_c.adrs10<=pipe_exe.adrs10;
      
    ELSE
      IF pipe_dec.cat.m_ry='1' THEN
        ry_c<=ry_v;
      END IF;
      IF pipe_dec.cat.m_psr_icc='1' THEN
        psr_c.icc<=psr_v.icc;
      END IF;
      IF pipe_dec.cat.m_psr_cwp='1' THEN
        psr_c.cwp<=pipe_dec.cwp;
      END IF;
      IF pipe_dec.cat.m_psr_s='1' THEN
        psr_c.s<=psr_v.s;
        psr_c.et<=psr_v.et;
      END IF;
      
      as_exe_c<='1';
      pipe_exe_c.v<='1';
      ------------------------------
      IF trap_exe_v.t='1' THEN
        copie(dias_exe,"<TRAP : " & trap_decode(trap_exe_v) & ">");
      ELSE
        IF pipe_dec.cat.mode.s='1' AND
          pipe_dec.cat.mode.f='1' AND (pipe_dec.cycle/=0 OR pipe_dec.fst='1')
          AND as_mem_c='1' THEN
          fpu_do_ack<='1';
        END IF;
        copie(dias_exe,disassemble(pipe_dec.cat.op,pipe_dec.pc));
        IF pipe_dec.cycle=0 AND pipe_dec.cat.mode.s='1' AND pipe_dec.fst='0'
        THEN
          -- Pour STORE & STORE_DOUBLE & LOAD_STORE, il y a 1 cycle
          -- d'attente : lecture RD...
          pipe_exe_c.v<='0';
        END IF;
        
        IF muldiv_ack='0' AND muldiv_ack_mem='0' AND pipe_dec.cat.mode.m='1' THEN
          as_exe_c<='0';                -- Bloquage du fetch ?
          pipe_exe_c.v<='0';
          --pipe_exe_c.rd<=pipe_exe.rd;   -- Maintien du RD pendant bloquage MDU
        END IF;
        ----------------------------
        IF pipe_dec.cat.mode.j='1' AND pipe_dec.cat.priv='0' AND
          inst_dval_c='0' AND dstop='0' THEN
          -- A cause des enchaînements JMPL/RETT, il faut attendre que
          -- l'instruction suivante soit prête avant de terminer le JMPL.
          as_exe_c<='0';
          pipe_exe_c.v<='0';
        END IF;
        
      END IF;                           -- IF trap=0
    END IF;                             -- IF atrap=0 & as_mem_c=1
  END PROCESS Comb_EXEC;

  --------------------------------------
  Sync_EXEC:PROCESS(clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      psr<=psr_c;
      ry <=ry_c;
      pipe_exe<=pipe_exe_c;
      pipe_exe.psr<=psr_c;
      pipe_exe.ry<=ry_c;
      npc_exe<=npc_exe_c;
      as_exe<=as_exe_c;
      IF as_exe_c='1' THEN
        muldiv_ack_mem<='0';
      ELSIF muldiv_ack='1' THEN
        muldiv_ack_mem<='1';
      END IF;

      IF reset_n='0' THEN
        pipe_exe.v<='0';
        psr.et<='0';
        psr.s<='1';
        psr.cwp<="00000";                 -- AJOUT !!!
      END IF;
    END IF;
  END PROCESS Sync_EXEC;
  
  ------------------------------------------------------------------------------
  -- MEMORY
  Comb_MEM:PROCESS(pipe_exe,pipe_mem,data_r,as_wri_c,psr,dstop,fpu_present,
                   trap_stop_c,trap_stop,trap_npc,endlock) IS
    VARIABLE psr_v : type_psr;
  BEGIN
    --------------------------------------
    data_w_c<=pipe_exe.data_w;
    data_w_c.dack<='1';
    
    pipe_mem_c<=pipe_exe;
    IF pipe_exe.v='1' AND pipe_exe.cat.m_psr='1' AND pipe_exe.anu='0' THEN
      -- Décalage de la mise à jour complète
      wrpsr(psr_v,pipe_exe.rd,fpu_present,NWINDOWS);
      pipe_mem_c.psr<=psr_v;
    END IF;

    endlock_c<=endlock;
    --------------------------------------
    IF trap_stop='1' THEN
      -- Arrêt TRAP
      data_w_c.req<='0';
      as_mem_c<='1';
      pipe_mem_c.v<=NOT dstop; -- On impose une nouvelle instruction...
      pipe_mem_c.anu<='0';
      pipe_mem_c.cat<=CAT_ALU;
      pipe_mem_c.cat.r_reg<="000";
      pipe_mem_c.num_rd<=regad(18,psr.cwp,NWINDOWS); -- R18=L2 : Sauvegarde nPC
      pipe_mem_c.rd<=trap_npc;
      pipe_mem_c.rd_maj<='1';
      pipe_mem_c.trap.t<='0';
      
    ELSIF as_wri_c='0' THEN
      -- Tant que l'étage suivant n'est pas prêt, on empêche de commencer
      -- un nouvel accès que le bus de données.
      pipe_mem_c<=pipe_mem;
      as_mem_c<='0';
      data_w_c.req<='0';
      
    ELSIF pipe_exe.v='0' OR pipe_exe.anu='1' OR pipe_exe.trap.t='1' THEN
      IF pipe_exe.v='0' THEN
        copie(dias_mem,VIDE);
      ELSIF pipe_exe.anu='1' THEN
        copie(dias_mem,"<ANNUL>");
      ELSE
        copie(dias_mem,"<TRAP : " & trap_decode(pipe_exe.trap) & ">");
      END IF;
      as_mem_c<='1';
      data_w_c.req<='0';
      pipe_mem_c.rd<=pipe_mem.rd;
      IF endlock='1' THEN
        data_w_c.lock<='0';
      END IF;
    ELSE
      endlock_c<='0';
      copie(dias_mem,disassemble(pipe_exe.cat.op,pipe_exe.pc));
      IF pipe_exe.cat.mode.l='0' AND pipe_exe.cat.mode.s='0' THEN
        -- Instruction sans accès mémoire
        -- Si seconde partie CASA et différent, annule l'écriture.
        as_mem_c<='1';
        data_w_c.req<='0';
      ELSIF pipe_mem.trap.t='1' THEN
        as_mem_c<='0';
        data_w_c.req<='0';
      ELSE
        -- Instruction avec accès mémoire
        as_mem_c<=data_r.ack;
        pipe_mem_c.v<=data_r.ack;
        data_w_c.req<='1';
      END IF;
      IF pipe_exe.cat.mode.l='1' AND pipe_exe.cat.mode.s='1' AND
        pipe_exe.cycle=1 THEN
        endlock_c<='1';
      END IF;
    END IF;
    IF trap_stop_c='1' THEN
      data_w_c.req<='0';
    END IF;
    
  END PROCESS Comb_MEM;

  data_w<=data_w_c;
  
  --------------------------------------
  Sync_MEM:PROCESS(clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      pipe_mem<=pipe_mem_c;
      endlock<=endlock_c;
      IF as_wri_c='1' AND pipe_mem.v='1' AND trap_stop='0'
        AND pipe_mem.cycle=0 AND (dstop='0' OR debug_t.ppc='1') THEN
        trap_npc<=pipe_mem.npc;
        trap_pc<=trap_npc;
--        trap_pc<=pipe_mem.pc;
      END IF;
      data_wu_req<=data_w_c.req;

      IF data_w_c.req='1' AND data_r.ack='1' AND data_r.dreq='0' THEN
        data_aec<=1;
      ELSIF NOT (data_w_c.req='1' AND data_r.ack='1') AND data_r.dreq='1' THEN
        -- data_w.dack est toujours à 1
        data_aec<=0;
      END IF;

      IF reset_n='0' THEN
        data_aec<=0;
        data_wu_req<='0';
        pipe_mem.v<='0';
        endlock<='0';
      END IF;
    END IF;
  END PROCESS Sync_MEM;

  ------------------------------------------------------------------------------
  -- WRITE
  Comb_WRITE:PROCESS(pipe_mem,data_r,trap_stop,trap_stop_delay,halterror,
                     psr_fin,data_wu_req,psr,trap_pc,casa_cmp,pipe_exe,
                     inst_aec,inst_lev,data_aec,inst_w_i,inst_r_lev,
                     dstop,debug_t,reset) IS
    VARIABLE trap_wri_v : type_trap;
  BEGIN
    --------------------------------------
    trap_wri_v:=pipe_mem.trap;
    IF trap_wri_v.t='0' AND data_r.dreq='1' AND
      (pipe_mem.cat.mode.l='1' OR pipe_mem.cat.mode.s='1')
      AND pipe_mem.cycle=0 THEN
      trap_wri_v:=plomb_trap_data(data_r.code);
    END IF;
    --------------------------------------
    tbr_trap_c<=trap_wri_v.tt;
    trap_c<=trap_wri_v;
    trap_stop_c<='0';
    regs_maj_c<='0';
    rd_maj<='0';
    fpu_wri_c<='0';
    fpu_di_maj<='0';
    fpu_fxack<='0';
    
    halterror_c<=halterror;

    num_rd_c<=pipe_mem.num_rd;
    
    --------------------------------------
    dstop_c<=(dstop AND NOT debug_t.run) AND debug_t.ena;

    IF pipe_mem.cat.mode.l='1' THEN
      rd_c<=ld(pipe_mem.cat.size,pipe_mem.adrs10,data_r.d);
    ELSE
      rd_c<=pipe_mem.rd;
    END IF;

    casa_cmp_c<=casa_cmp;
    IF pipe_mem.v='1' AND CASA THEN
      IF ld(pipe_mem.cat.size,pipe_mem.adrs10,data_r.d) = pipe_exe.casa_rs2 THEN
        casa_cmp_c<='1';
      ELSE
        casa_cmp_c<='0';
      END IF;
    END IF;
    
    --------------------------------------
    IF trap_stop='1' THEN
      copie(dias_wri,"[TRAP]");
      trap_stop_c<=NOT (
        to_std_logic(inst_aec=0 AND inst_w_i.req='0' AND inst_lev=0 AND
                     inst_r_lev=0 AND data_aec=0 AND data_wu_req='0' AND
                     trap_stop_delay='1') ) OR reset;
      pipe_wri_v_c<='0';
      as_wri_c<='1';

      num_rd_c<=regad(17,psr.cwp,NWINDOWS);  -- R17=L1 : Sauvegarde PC
      rd_c<=trap_pc;
      rd_maj<=trap_stop_delay AND NOT dstop;
      
    ELSIF pipe_mem.v='0' OR pipe_mem.anu='1' THEN
      IF pipe_mem.v='0' THEN
        copie(dias_wri,VIDE);
      ELSE
        copie(dias_wri,"<ANNUL>");
      END IF;
      pipe_wri_v_c<='0';
      as_wri_c<='1';

    ELSIF pipe_mem.trap=TT_WATCHPOINT_DETECTED AND debug_t.ena='1' THEN
      -- Arrêt debugger !
      pipe_wri_v_c<='1';
      dstop_c<='1';
      as_wri_c<='1';
      trap_stop_c<='1';
    ELSE
      pipe_wri_v_c<='1';
      IF trap_wri_v.t='1' THEN
        IF trap_wri_v=TT_FP_EXCEPTION THEN
          fpu_fxack<='1';
        END IF;
        as_wri_c<='1';
        trap_stop_c<='1'; --NOT dstop; -- <ESSAI>'1';
        IF psr_fin.et='0' AND dstop='0' THEN
          halterror_c<='1';
          dstop_c<='1';
        END IF;
        copie(dias_wri,"<TRAP : " & trap_decode(trap_wri_v) & ">");
      ELSE
        copie(dias_wri,disassemble(pipe_mem.cat.op,pipe_mem.pc));
        
        IF pipe_mem.cat.mode.l='1' OR pipe_mem.cat.mode.s='1' THEN
          rd_maj<=pipe_mem.rd_maj AND data_r.dreq;
          as_wri_c<=data_r.dreq;
        ELSE
          rd_maj<=pipe_mem.rd_maj;
          as_wri_c<='1';
        END IF;
        regs_maj_c<='1';

        fpu_di_maj<=data_r.dreq AND
                     pipe_mem.cat.mode.f AND pipe_mem.cat.mode.l;
        fpu_wri_c<=pipe_mem.cat.mode.f AND
                    (NOT pipe_mem.cat.mode.l AND NOT pipe_mem.cat.mode.s);
      END IF;
      --------------------------------------
    END IF;

  END PROCESS Comb_WRITE;
  
  fpu_di<=data_r.d;
  
  --------------------------------------
  Sync_WRITE:PROCESS(clk) IS
    VARIABLE lout : line;
  BEGIN
    IF rising_edge(clk) THEN
      pipe_wri<=pipe_mem;
      pipe_wri.v<=pipe_wri_v_c;
      pipe_wri.rd<=rd_c;

      casa_cmp<=casa_cmp_c;

      IF regs_maj_c='1' THEN
        psr_fin<=pipe_mem.psr;
        ry_fin <=pipe_mem.ry;
        
        IF pipe_mem.cat.m_wim='1' THEN
          wim<=pipe_mem.rd(NWINDOWS-1 DOWNTO 0);
        END IF;
        IF pipe_mem.cat.m_tbr='1' THEN
          tbr<=(pipe_mem.rd(31 DOWNTO 12),pipe_mem.rd(11 DOWNTO 4));
        END IF;
      END IF;
      IF trap_stop_c='1' AND trap_stop='0' AND dstop_c='0' THEN
        tbr.tt<=tbr_trap_c;
      END IF;
      trap_stop<=trap_stop_c OR reset;
      trap_stop_delay<=trap_stop;
      halterror<=halterror_c AND NOT debug_t.run AND NOT reset;
      
      dstop<=dstop_c;
      IF halterror_c='1' AND halterror='0' THEN
          halterror_trap<=trap_c;
          REPORT "TRAP Récursif : Error Mode :h" &
            To_HString(trap_c.tt) SEVERITY error;
          REPORT "TRAP PC=" & To_HString(pipe_mem.pc) & " nPC=" &
            To_HString(pipe_mem.npc) SEVERITY note;
      END IF;
      IF pipe_wri_v_c='1' AND trap_c.t='1' THEN
        REPORT "TRAP : h" &
          To_HString(trap_c.tt) & " = " &
          trap_decode(trap_c) SEVERITY note;
        REPORT "TRAP PC=" & To_HString(pipe_mem.pc) & " nPC=" &
          To_HString(pipe_mem.npc) SEVERITY note;
        --pragma synthesis_off
        IF DUMP THEN
          write (lout,string'(CID & " TRAP : PC=" & To_HString(pipe_mem.pc) &
                 "  nPC=" &  To_HString(pipe_mem.npc) &
                 "  TT=" &  To_HString(trap_c.tt) &
                 " : " & trap_decode(trap_c) &
                 " {" & time'image(now) & " } "));
          writeline (fil,lout);
        END IF;
        --pragma synthesis_on

      END IF;
      --pragma synthesis_off
      IF dstop/=dstop_c AND DUMP THEN
        write(lout,string'("DSTOP=" & std_logic'image(dstop_c)));
        writeline(fil,lout);
      END IF;
      --pragma synthesis_on
      
      IF pipe_mem.rd_maj='1' THEN
        debug_rd<=pipe_mem.rd;
      END IF;
    
      IF reset='1' THEN
        tbr.tba<=(OTHERS => '0');
        tbr.tt <=(OTHERS => '0');
      END IF;
      IF reset_n='0' THEN
        trap_stop<='1';
        halterror<='0';
        dstop<='0';
        pipe_wri.v<='0';
        psr_fin<=PSR_0;
      END IF;
    END IF;
  END PROCESS Sync_WRITE;
  
  ------------------------------------------------------------------------------
  debug_s.dstop<=dstop;
  debug_s.trap_stop<=trap_stop;
  debug_s.halterror<=halterror;
  debug_s.d    <=debug_rd;
  debug_s.pc   <=trap_pc;
  debug_s.npc  <=trap_npc;
  debug_s.psr  <=psr;
  debug_s.fcc  <=fpu_fcc;
  debug_s.fccv <=fpu_fccv;
  debug_s.wim  <=ZERO(31 DOWNTO NWINDOWS) & wim;
  debug_s.tbr  <=tbr;
  debug_s.ry   <=ry;
  debug_s.irl  <=irl;
  debug_s.trap <=trap_c WHEN trap_stop='1' ELSE TT_NONE;
  debug_s.hetrap<=halterror_trap;
  intack<='0';                          -- <AFAIRE> INTACK

  debug_s.stat(7 DOWNTO 0)<=pc(7 DOWNTO 2) & to_unsigned(inst_lev,2);
  debug_s.stat(15 DOWNTO 8)<=npc(7 DOWNTO 2) & to_unsigned(inst_r_lev,2);
  
END ARCHITECTURE pipe5;
