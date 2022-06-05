--------------------------------------------------------------------------------
-- TEM : TACUS
-- Unité flottante
--------------------------------------------------------------------------------
-- DO 11/2009
--------------------------------------------------------------------------------
-- Version pipelinée
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

-- <AFAIRE> Denorm. "flush to zero"
-- <AFAIRE> LDFSR doit attendre que toutes les FPoPs soit terminées avant
-- de modifier FSR.
-- <AFAIRE> STDFQ est privilégiée...
-- <AFAIRE> Il faudra bloquer le pipe tant qu'une
-- instruction qui lit/écrit FPR ou DFQ est dans le pipe.

-- The store flating-point deferred-trap queue instruction (STDFQ)
-- stores the front doubleword of the Floating-point Queue (FQ) into
-- memory. An attempt to execute STDFQ on an implementation without a
-- foating-point queue causes an fp_exception trap with FSR.ftt set TO
-- 4 (sequence_error). On an implementation with a floating-point
-- queue, an attempt to execute STDFQ when the FQ is empty
-- (FSR.qne = 0) should cause an fp_exception trap with FSR.ftt set TO
-- 4 (sequence_error). Any additional semantics of this instruction are
-- implementation-dependent. See Appendix L, "Implementation
-- Characteristics", for information on the formats of the
-- deferred-trap queues.

--------------------------------------------------------------------------------
-- FMOVs, FNEGs, FABSs         : 2      Copie

-- FADDs, FSUBs, FCMPs, FCMPEs : 4      Extract+Decal/Add/Arrondi/Convert
-- FADDd, FSUBd, FCMPd, FCMPEd : 4      Extract+Decal/Add/Arrondi/Convert
-- FiTOs, FiTOd                : 4=add  Extract+Decal/Add/Arrondi/Convert
-- FsTOd, FdTOs                : 4=ftof Extract+Decal/Arrondi/Convert
-- FsTOi, FdTOi                : 4=stoi Extract+Decal/Add/Convert

-- FMULs, FsMULd               : 4      Extract+Decal/MUL/Arrondi/Convert
-- FMULd                       : 5      Extract+Decal/MUL*2/Arrondi/Convert

-- FDIVs, FSQRTs               : 32     Extract+Decal/DIVSQR*25/Arrondi/Convert
-- FDIVd, FSQRTd               : 61     Extract+Decal/DIVSQR*54/Arrondi/Convert

-- OP3 [24..19]
--      100000 : LDF
--      100011 : LDDF
--      100001 : LDFSR
--      100100 : STF
--      100111 : STDF
--      100101 : STFSR
--      100110 : STDFQ

--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

USE work.base_pack.ALL;
USE work.iu_pack.ALL;
USE work.fpu_pack.ALL;
USE work.disas_pack.ALL;

--------------------------------------------------------------------------------
ENTITY  fpu_mp IS
  GENERIC (
    N    : natural RANGE 1 TO 4;
    TECH : natural);
  PORT (
    i0 : IN  type_fpu_i;
    o0 : OUT type_fpu_o;
    i1 : IN  type_fpu_i;
    o1 : OUT type_fpu_o;
    i2 : IN  type_fpu_i;
    o2 : OUT type_fpu_o;
    i3 : IN  type_fpu_i;
    o3 : OUT type_fpu_o;
    
    -- Général
    reset    : IN std_logic;             -- Reset synchrone   
    reset_n  : IN std_logic;             -- Reset
    clk      : IN std_logic              -- Horloge
    );
END ENTITY fpu_mp;

--------------------------------------------------------------------------------
ARCHITECTURE multi OF fpu_mp IS

  CONSTANT DENORM_FTZ : boolean := false;
  
  -- DENORM_HARD : false=Trap    | true=HW
  CONSTANT DENORM_HARD : boolean := true;
  
  -- DENORM_ITER : false=1 cycle | true=iterative
  CONSTANT DENORM_ITER : boolean := true;

  CONSTANT NB : natural := mux(N>=3,1,0)+mux(N>=2,1,0);
  
  --------------------------------------
  -- FIFO / PIPELINE FPU
  CONSTANT REG_FR   : uv2 :="00";
  CONSTANT REG_FSR  : uv2 :="10";
  CONSTANT REG_DFQ  : uv2 :="11";
  
  TYPE type_fifo IS RECORD
    ld     : std_logic; -- 0=FPop 1=LDF
    reg    : uv2;       -- 0x=FPR 10=FSR 11=DFQ
    sd     : std_logic; -- 0=Simple 1=Double
    n_fd   : unsigned(4 DOWNTO 0);
    unimp  : std_logic;
    cmp    : std_logic; -- Compare opcode
    op     : uv32;
    pc     : uv32;
  END RECORD;
  TYPE arr_fifo IS ARRAY(natural RANGE <>) OF type_fifo;

  CONSTANT FIFO_MAX : natural :=4;
  CONSTANT DFQ_MAX  : natural :=7;
  
  SIGNAL fifo,fifo_c : arr_fifo(0 TO FIFO_MAX-1);
  SIGNAL fifo_lev,fifo_lev_c : integer RANGE 0 TO FIFO_MAX;
  SIGNAL fifo_lv,fifo_lv_c : std_logic;
  SIGNAL dfq_lev_i,dfq_lev_i_c : integer RANGE 0 TO DFQ_MAX;
  SIGNAL dfq_lev_o,dfq_lev_o_c : integer RANGE 0 TO DFQ_MAX;
  SIGNAL st_reg,st_reg_c : uv2;
  SIGNAL st_sd,st_sd_c : std_logic;

  SIGNAL wri_cpt,wri_cpt_c : natural RANGE 0 TO 5;

  TYPE arr_fpu_i IS ARRAY(natural RANGE <>) OF type_fpu_i;
  SIGNAL ix : arr_fpu_i(0 TO 3);
  SIGNAL ox : type_fpu_o;

  TYPE opls_enum IS (OP,LS);
  SIGNAL opls,opls_c : opls_enum;
  SIGNAL flush_pend : std_logic;

  SIGNAL cpusel,cpusel_c : natural RANGE 0 TO N-1;
  SIGNAL fexc : unsigned(0 TO 3);
  
  --------------------------------------
  -- Calculs
  SIGNAL calc_rdy,calc_fin : std_logic;
  SIGNAL calc_req_c : std_logic;
  SIGNAL calc_flush : std_logic;
  SIGNAL calc_stall_c : std_logic;
  SIGNAL calc_idle : std_logic;
  SIGNAL calc_fop_c : uv4;
  SIGNAL calc_sdi_c : std_logic;
  SIGNAL calc_sdo_c : std_logic;
  SIGNAL calc_fs1, calc_fs2,calc_fd : uv64;
  SIGNAL calc_fcc : uv2;
  SIGNAL calc_exc : unsigned(4 DOWNTO 0);
  SIGNAL calc_unf : std_logic;
  
  --------------------------------------
  SIGNAL exception, exception_c : unsigned(0 TO 3); -- Exception en attente

  SIGNAL ld_hilo, ld_hilo_c : std_logic;
  SIGNAL st_hilo, st_hilo_c : std_logic;
  TYPE arr_fsr IS ARRAY(natural RANGE <>) OF type_fsr;
  SIGNAL fsr, fsr_c : arr_fsr(0 TO 3);
  SIGNAL fsr_rd : uv2;
  SIGNAL fsr_tem : unsigned(4 DOWNTO 0);
  SIGNAL req2 : std_logic;

  SIGNAL n_fs1_c,n_fs1,n_fs2_c,n_fs2,n_fd_c : unsigned(5+NB DOWNTO 0);
  SIGNAL fs1r,mem_fs1r,fs2r,fd_c : uv64;
  SIGNAL fd_maj_c : uv2;
  SIGNAL do_c : uv32;
  SIGNAL dias : string(1 TO 50);

  FUNCTION deps(
    CONSTANT fs : unsigned(4 DOWNTO 0);
    CONSTANT sd : std_logic;
    CONSTANT pipe : type_fifo) RETURN boolean IS
  BEGIN    
    RETURN fs(4 DOWNTO 1)=pipe.n_fd(4 DOWNTO 1) AND
      (sd='1' OR pipe.sd='1' OR fs(0)=pipe.n_fd(0));
  END;
  
BEGIN

  --------------------------------------
  ix<=(i0,i1,i2,i3);
  
  Oxgen:PROCESS(ox,fexc,fsr,cpusel,exception) IS
  BEGIN
    o0<=ox;
    o0.rdy <=ox.rdy AND to_std_logic(cpusel=0);
    o0.fexc<=exception(0);
    o0.fcc <=fsr(0).fcc;
    o1<=ox;
    o1.rdy <=ox.rdy AND to_std_logic(cpusel=1);
    o1.fexc<=exception(1);
    o1.fcc <=fsr(1).fcc;
    o2<=ox;
    o2.rdy <=ox.rdy AND to_std_logic(cpusel=2);
    o2.fexc<=exception(2);
    o2.fcc <=fsr(2).fcc;
    o3<=ox;
    o3.rdy <=ox.rdy AND to_std_logic(cpusel=3);
    o3.fexc<=exception(3);
    o3.fcc <=fsr(3).fcc;
  END PROCESS Oxgen;
    
  ox.present<='1';  
  --------------------------------------
  -- Registres
  i_fpu_regs_2r1w: ENTITY work.fpu_regs_2r1w
    GENERIC MAP (
      THRU     => true,
      N        => 5 + NB) -- REGS : NCPU * (16*64bits + DFQ)
    PORT MAP (
      n_fs1    => n_fs1_c(5 + NB DOWNTO 1),
      fs1      => fs1r,
      n_fs2    => n_fs2_c(5 + NB DOWNTO 1),
      fs2      => fs2r,
      n_fd     => n_fd_c(5 + NB DOWNTO 1),
      fd       => fd_c,
      fd_maj   => fd_maj_c,
      clk      => clk);
  
  --------------------------------------
  -- Machine à états FPU
  Comb_Machine:PROCESS(i0,i1,i2,i3,req2,wri_cpt,fsr,st_sd,st_reg,n_fs1,n_fs2,
                       fs1r,mem_fs1r,exception,calc_rdy,
                       ld_hilo,st_hilo,dfq_lev_i,dfq_lev_o,
                       fifo_lv,calc_fd,calc_fin,calc_fcc,calc_exc,calc_unf,
                       fifo,fifo_lev,opls,cpusel
                       ) IS
    VARIABLE deco_v : type_decode;
    VARIABLE fifo_out_v,fifo_in_v : type_fifo;
    VARIABLE fsr_v  : type_fsr;
    VARIABLE push_v,pop_v : std_logic;
    VARIABLE push_fq_v,pop_fq_v : std_logic;
    VARIABLE fs1_v,fs2_v : unsigned(4 DOWNTO 0);
    VARIABLE fifo_l0,fifo_l1,fifo_l2,fifo_l3 : boolean;
    VARIABLE i_v : type_fpu_i;
    VARIABLE nin_v : unsigned(0 TO NB-1);
  BEGIN
    
    fifo_out_v:=fifo(fifo_lev);
    
    --====================================================
    nin_v:=to_unsigned(cpusel,NB);
    
    IF cpusel=1 AND N>=2 THEN
      i_v:=i1;
    ELSIF cpusel=2 AND N>=3 THEN
      i_v:=i2;
    ELSIF cpusel=3 AND N=4 THEN
      i_v:=i3;
    ELSE
      i_v:=i0;
    END IF;
    
    IF fifo_lv='0' AND wri_cpt=0 AND exception="0000" AND i_v.req='0' THEN
      IF i0.req='1' THEN
        cpusel_c<=0;
      ELSIF i1.req='1' AND N>=2 THEN
        cpusel_c<=1;
      ELSIF i2.req='1' AND N>=3 THEN
        cpusel_c<=2;
      ELSIF i3.req='1' AND N=4 THEN
        cpusel_c<=3;
      ELSE
        cpusel_c<=cpusel;
      END IF;
    ELSE
      cpusel_c<=cpusel;
    END IF;

    --====================================================
    -- Comptage wri. WRI ne concerne que les FPops
    wri_cpt_c<=wri_cpt;
    IF i_v.wri='1' AND calc_fin='0' THEN
      wri_cpt_c<=wri_cpt+1;
    ELSIF i_v.wri='0' AND calc_fin='1' THEN
      IF wri_cpt>0 THEN
        wri_cpt_c<=wri_cpt-1;
      END IF;
    END IF;
    
    ------------------------------------------------------
    pop_v:='0';
    fsr_c<=fsr;
    exception_c<=exception;
    push_fq_v:='0';
    
    n_fd_c<=nin_v & '0' & fifo_out_v.n_fd;
    IF fifo_out_v.ld='1' THEN
      fd_c<=i_v.di & i_v.di;
    ELSE
      fd_c<=calc_fd;
    END IF;
    fd_maj_c<="00";
    
    calc_stall_c<='0';
    ox.rdy<='1';
    
    ------------------------------------------------------
    IF calc_fin='1' THEN
      IF i_v.wri='1' OR wri_cpt>0 THEN
        -- FPop : Fin calcul
        pop_v:='1';
        IF fifo_out_v.cmp='1' THEN
          fsr_c(cpusel).fcc<=calc_fcc;
        END IF;
        IF fifo_out_v.unimp='1' THEN
          fsr_c(cpusel).ftt<=FTT_UNIMPLEMENTED_FPOP;
          exception_c(cpusel)<='1';
          push_fq_v:='1';
          n_fd_c<=nin_v & '1' & to_unsigned(dfq_lev_i,4) & '0';
          fd_c<=fifo_out_v.pc & fifo_out_v.op;
          fd_maj_c<="11";
          
        ELSIF calc_unf='1' AND NOT DENORM_HARD THEN
          fsr_c(cpusel).ftt<=FTT_UNFINISHED_FPOP;
          exception_c(cpusel)<='1';
          push_fq_v:='1';
          n_fd_c<=nin_v & '1' & to_unsigned(dfq_lev_i,4) & '0';
          fd_c<=fifo_out_v.pc & fifo_out_v.op;
          fd_maj_c<="11";
          
        ELSIF  (calc_exc AND fsr(cpusel).tem)/="00000" THEN
          -- Une exception IEEE est non masquée
          fsr_c(cpusel).ftt<=FTT_IEEE_754_EXCEPTION;
          fsr_c(cpusel).cexc<=calc_exc;
          exception_c(cpusel)<='1';
          push_fq_v:='1';
          n_fd_c<=nin_v & '1' & to_unsigned(dfq_lev_i,4) & '0';
          fd_c<=fifo_out_v.pc & fifo_out_v.op;
          fd_maj_c<="11";
          
        ELSIF exception(cpusel)='1' THEN
          -- Instructions empilées après l'instruction qui a trappé
          push_fq_v:='1';
          n_fd_c<=nin_v & '1' & to_unsigned(dfq_lev_i,4) & '0';
          fd_c<=fifo_out_v.pc & fifo_out_v.op;
          fd_maj_c<="11";
          
        ELSE
          fsr_c(cpusel).ftt<=FTT_NONE;
          fsr_c(cpusel).cexc<=calc_exc;
          fsr_c(cpusel).aexc<=fsr(cpusel).aexc OR calc_exc;
          IF fifo_out_v.cmp='1' THEN
            fd_maj_c<="00";
          ELSIF fifo_out_v.sd='1' THEN
            fd_maj_c<="11";
          ELSE
            fd_maj_c<=NOT fifo_out_v.n_fd(0) & fifo_out_v.n_fd(0);
          END IF;
        END IF;
      ELSE
        -- Si pas de WRI quand la FPOP se termine, bloque le pipe FPOP
        -- le calc_fin est rallongé jusqu'à WRI=1
        calc_stall_c<='1';
      END IF;
    END IF;
    
    ------------------------------------------------------
    -- LOAD : LDF, LDDF, LDFSR
    ld_hilo_c<=ld_hilo;
    
    IF i_v.di_maj='1' THEN
      IF ld_hilo='1' OR fifo_out_v.sd='0' OR fifo_out_v.reg/=REG_FR THEN
        pop_v:='1';
        ld_hilo_c<='0';
      ELSE
        ld_hilo_c<='1';
      END IF;
      -- LOAD : Ecriture registre
      IF fifo_out_v.reg=REG_FR THEN
        IF fifo_out_v.sd='1' THEN
          fd_maj_c<=NOT ld_hilo & ld_hilo;
        ELSE
          fd_maj_c<=NOT fifo_out_v.n_fd(0) & fifo_out_v.n_fd(0);
        END IF;
      END IF;
      IF fifo_out_v.reg=REG_FSR THEN
        -- LDFSR
        wrfsr(fsr_v,i_v.di);
        fsr_c(cpusel).rd <=fsr_v.rd;     -- Round direction
        fsr_c(cpusel).tem<=fsr_v.tem;    -- Trap enable mask
        fsr_c(cpusel).ns <=fsr_v.ns;     -- Nonstandard
        fsr_c(cpusel).fcc<=fsr_v.fcc;    -- Cond. Codes
        fsr_c(cpusel).aexc<=fsr_v.aexc;  -- Accrued exception
        fsr_c(cpusel).cexc<=fsr_v.cexc;  -- Current exception
        -- .ftt & .qne non modifiés par LDFSR
      END IF;
    END IF;
    
    --====================================================
    -- Décodage instructions.
    push_v:='0';
    calc_req_c<='0';
    opls_c<=opls; -- =0=LS 1=FPOP
    deco_v:=fpu_decode(i_v.cat.op);
    
    calc_fop_c<=deco_v.fop;
    calc_sdi_c<=deco_v.sdi;
    calc_sdo_c<=deco_v.sdo;
    copie(dias,"...");
    IF i_v.req='1' AND exception(cpusel)='0' AND i_v.cat.mode.f='1' THEN
      -- REQ n'est activé que si RDY est déjà à 1
      copie(dias,disassemble(i_v.cat.op,x"0000_0000"));
      IF i_v.cat.mode.l='0' AND i_v.cat.mode.s='0' THEN
        -- FPOP
        push_v:='1';
        opls_c<=OP;
        calc_req_c<='1';
      ELSE
        -- LDF, LDDF, LDFSR, STF, STDF, STFSR, STDFQ
        opls_c<=LS;
        IF i_v.cat.op(21)='0' THEN
          -- On empile que les LOAD
          push_v:='1';
        END IF;
      END IF;
    END IF;
    
    ------------------------------------------------------
    -- Préparation FIFO
    IF i_v.cat.op(31 DOWNTO 30)="10" THEN -- FPop
      fifo_in_v.ld   :='0';
      fifo_in_v.reg  :=REG_FR;
      fifo_in_v.sd   :=deco_v.sdo;
      fifo_in_v.unimp:=deco_v.unimp;
      fifo_in_v.cmp  :=deco_v.cmp;
    ELSE
      fifo_in_v.ld   :='1';
      CASE i_v.cat.op(20 DOWNTO 19) IS
        WHEN "00"   => fifo_in_v.reg:=REG_FR;  -- LDF, STF
        WHEN "01"   => fifo_in_v.reg:=REG_FSR; -- LDFSR, STFSR
        WHEN "10"   => fifo_in_v.reg:=REG_DFQ; -- STDFQ
        WHEN OTHERS => fifo_in_v.reg:=REG_FR;  -- LDDF, STDF
      END CASE;
      fifo_in_v.sd   :=i_v.cat.op(20);
      fifo_in_v.unimp:='0';
      fifo_in_v.cmp  :='0';
    END IF;
    fifo_in_v.n_fd:=i_v.cat.op(29 DOWNTO 25);
    fifo_in_v.op:=i_v.cat.op;
    fifo_in_v.pc:=i_v.pc;
    
    ------------------------------------------------------
    -- STORE : STF, STDF, STFSR, STDFQ
    IF i_v.req='1' THEN
      st_reg_c <=fifo_in_v.reg;
      st_sd_c  <=fifo_in_v.sd;
      st_hilo_c<=fifo_in_v.n_fd(0);
    ELSE
      st_reg_c <=st_reg;
      st_sd_c  <=st_sd;
      st_hilo_c<=st_hilo OR (i_v.do_ack AND st_sd);
    END IF;
    
    IF st_reg="10" THEN -- FSR
      do_c<=rdfsr(fsr(cpusel),i_v.ver);  
    ELSE
      IF st_hilo='0' THEN -- FR & DFQ
        do_c<=mux(req2,fs1r(63 DOWNTO 32),mem_fs1r(63 DOWNTO 32));
      ELSE
        do_c<=mux(req2,fs1r(31 DOWNTO 0) ,mem_fs1r(31 DOWNTO 0));
      END IF;
    END IF;
    
    pop_fq_v:='0';
    IF st_reg="11" AND st_hilo='1' THEN -- DFQ
      pop_fq_v:=i_v.do_ack AND NOT i_v.dstop;
    END IF;

    ------------------------------------------------------
    -- Dépendances
    fifo_l0:=fifo_lv='1' AND (fifo_lev>0 OR pop_v='0');
    fifo_l1:=fifo_lev>0  AND (fifo_lev>1 OR pop_v='0');
    fifo_l2:=fifo_lev>1  AND (fifo_lev>2 OR pop_v='0');
    fifo_l3:=fifo_lev>2  AND pop_v='0';

    IF i_v.cat.mode.f='1' AND (i_v.cat.mode.l='1' OR i_v.cat.mode.s='1') THEN
      IF fifo_lv='1' AND opls=OP THEN
        ox.rdy<='0';
      END IF;
    END IF;
    
    IF i_v.cat.op(31 DOWNTO 30)="11" AND i_v.cat.op(21)='1' THEN -- STORE FP
      -- Test dépendances STORE [op(21)=1 : Store] après LOAD
      --< AVOIR : EXception pour STDFQ : On ne bloque pas!
      IF (deps(fifo_in_v.n_fd,fifo_in_v.sd,fifo(0)) AND fifo_l0) OR
         (deps(fifo_in_v.n_fd,fifo_in_v.sd,fifo(1)) AND fifo_l1) OR
         (deps(fifo_in_v.n_fd,fifo_in_v.sd,fifo(2)) AND fifo_l2) OR
         (deps(fifo_in_v.n_fd,fifo_in_v.sd,fifo(3)) AND fifo_l3) THEN
        ox.rdy<='0';
      END IF;
    END IF;
    
    IF i_v.cat.op(31 DOWNTO 30)="10" THEN  --FPop
      -- Test dépendances FPOP
      fs1_v:=i_v.cat.op(18 DOWNTO 14);
      fs2_v:=i_v.cat.op(4 DOWNTO 0);
      IF fifo_lv='1' AND opls=LS THEN
        ox.rdy<='0';
      END IF;
      IF calc_rdy='0' THEN
        ox.rdy<='0';
      END IF;

      IF (deco_v.bin='1' AND
          ((deps(fs1_v,deco_v.sdi,fifo(0)) AND fifo_l0) OR
           (deps(fs1_v,deco_v.sdi,fifo(1)) AND fifo_l1) OR
           (deps(fs1_v,deco_v.sdi,fifo(2)) AND fifo_l2) OR
           (deps(fs1_v,deco_v.sdi,fifo(3)) AND fifo_l3))) OR
         ( (deps(fs2_v,deco_v.sdi,fifo(0)) AND fifo_l0) OR
           (deps(fs2_v,deco_v.sdi,fifo(1)) AND fifo_l1) OR
           (deps(fs2_v,deco_v.sdi,fifo(2)) AND fifo_l2) OR
           (deps(fs2_v,deco_v.sdi,fifo(3)) AND fifo_l3)) THEN
        ox.rdy<='0';
      END IF;
    END IF;
    
    ------------------------------------------------------
    IF i_v.fxack='1' THEN
      exception_c(cpusel)<='0';
    END IF;
    
    --====================================================
    -- Si le do_ack apparait après le cycle après le REQ, on maintien
    --  les dernières valeurs
    ---------------------------
    -- Accès registres
    IF calc_rdy='0' THEN
      -- Si bloquage, on reconduit les registres précédents.
      n_fs1_c<=n_fs1;
      n_fs2_c<=n_fs2;
    ELSE
      IF i_v.cat.op(31 DOWNTO 30)="10" THEN -- FPop
        n_fs1_c<=nin_v & '0' & i_v.cat.op(18 DOWNTO 14);
      ELSIF i_v.cat.op(20 DOWNTO 19)="10" THEN -- STDFQ
        n_fs1_c<=nin_v & '1' & to_unsigned(dfq_lev_o,4) & '0';
      ELSE -- ST / STD
        n_fs1_c<=nin_v & '0' & i_v.cat.op(29 DOWNTO 25);
      END IF;
      n_fs2_c<=nin_v & '0' & i_v.cat.op(4 DOWNTO 0);
    END IF;
    
    --====================================================
    -- FIFO / PIPE FPU
    fifo_c<=fifo;
    fifo_lev_c<=fifo_lev;
    fifo_lv_c<=fifo_lv;
    
    IF push_v='1' THEN
      fifo_c<=fifo_in_v & fifo(0 TO FIFO_MAX-2);
    END IF;
    IF push_v='1' AND pop_v='0' THEN
      fifo_lv_c<='1';
      IF fifo_lv='1' THEN
        fifo_lev_c<=fifo_lev+1;
      END IF;
    ELSIF push_v='0' AND pop_v='1' THEN
      IF fifo_lev=0 THEN
        fifo_lv_c<='0';
      ELSE
        fifo_lev_c<=fifo_lev-1;
      END IF;
    END IF;
    
    ---------------------------
    -- DFQ : La FQ ne contient que des instructions validées.
    IF push_fq_v='1' THEN
      dfq_lev_i_c<=(dfq_lev_i + 1) MOD (DFQ_MAX+1);
    ELSE
      dfq_lev_i_c<=dfq_lev_i;
    END IF;
    IF pop_fq_v='1' THEN
      dfq_lev_o_c<=(dfq_lev_o + 1) MOD (DFQ_MAX+1);
    ELSE
      dfq_lev_o_c<=dfq_lev_o;
    END IF;
    ---------------------------
  END PROCESS Comb_Machine;
  
  ox.do<=do_c;
  
  Machine:PROCESS(clk) IS
  BEGIN
    IF rising_edge(clk) THEN

      cpusel<=cpusel_c;
      
      fifo<=fifo_c;
      fifo_lev<=fifo_lev_c;
      fifo_lv<=fifo_lv_c;
      dfq_lev_i<=dfq_lev_i_c;
      dfq_lev_o<=dfq_lev_o_c;
      
      opls<=opls_c;
      
      st_reg<=st_reg_c;
      st_sd<=st_sd_c;
      st_hilo<=st_hilo_c;
      
      ld_hilo<=ld_hilo_c;
      
      IF ix(cpusel).tstop='1' THEN
        flush_pend<='1';
      ELSIF flush_pend='1' AND wri_cpt=0 THEN
        calc_flush<='1';
        flush_pend<='0';
        fifo_lev<=0;
        fifo_lv<='0';
        st_hilo<='0';
      ELSE
        calc_flush<='0';
      END IF;
      
      wri_cpt<=wri_cpt_c;
      
      IF req2='1' THEN
        mem_fs1r<=fs1r;
      END IF;
      
      req2<=ix(cpusel).req;
      
      exception<=exception_c;
      
      fsr<=fsr_c;
      fsr(cpusel).qne<=to_std_logic(dfq_lev_i/=dfq_lev_o);
      
      n_fs1<=n_fs1_c;
      n_fs2<=n_fs2_c;
      
      ---------------------------
      IF reset_n='0' THEN
        exception<="0000";
        fifo_lev<=0;
        fifo_lv<='0';
        dfq_lev_i<=0;
        dfq_lev_o<=0;
        wri_cpt<=0;
        ld_hilo<='0';
        st_hilo<='0';
        calc_flush<='0';
        flush_pend<='0';
      END IF;
    END IF;
  END PROCESS Machine;
  
  ox.fccv<=NOT fifo_lv;
  
  --############################################################################
  
  calc_fs1<=mux(n_fs1(0),fs1r(31 DOWNTO 0),fs1r(63 DOWNTO 32)) &
             fs1r(31 DOWNTO 0);
  calc_fs2<=mux(n_fs2(0),fs2r(31 DOWNTO 0),fs2r(63 DOWNTO 32)) &
             fs2r(31 DOWNTO 0);

  i_fpu_calc: ENTITY work.fpu_calc
    GENERIC MAP (
      DENORM_HARD => DENORM_HARD,
      DENORM_FTZ  => DENORM_FTZ,
      DENORM_ITER => DENORM_ITER,
      TECH        => TECH)
    PORT MAP (
      rdy      => calc_rdy,
      req      => calc_req_c,
      fin      => calc_fin,
      flush    => calc_flush,
      stall    => calc_stall_c,
      idle     => calc_idle,
      fop      => calc_fop_c,
      sdi      => calc_sdi_c,
      sdo      => calc_sdo_c,
      rd       => fsr_rd,
      tem      => fsr_tem,
      fs1      => calc_fs1,
      fs2      => calc_fs2,
      fd       => calc_fd,
      fcc      => calc_fcc,
      exc      => calc_exc,
      unf      => calc_unf,
      reset_n  => reset_n,
      clk      => clk);

  fsr_rd<=fsr(cpusel).rd;
  fsr_tem<=fsr(cpusel).tem;
  
  ------------------------------------------------------------------------------
  
END ARCHITECTURE multi;

