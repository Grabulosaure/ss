--------------------------------------------------------------------------------
-- TEM : TACUS
-- Contrôleur MMU. Tablewalk / L2TLB
--------------------------------------------------------------------------------
-- DO 7/2018
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

--Cache TLB L2
-- 32 I + 32 D

-- <AFAIRE> mmu_cr_aw
-- <AFAIRE> Tags superviseur partagés

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

USE work.base_pack.ALL;
USE work.plomb_pack.ALL;
USE work.asi_pack.ALL;
USE work.mcu_pack.ALL;
USE work.cpu_conf_pack.ALL;

ENTITY mcu_tw IS
  GENERIC (
    NB_CONTEXT : natural;
    WBSIZE     : uv32    := x"0000_0000";
    CPUTYPE    : natural := 0);
  PORT (
    -- INST
    inst_tw_req    : IN  std_logic;
    inst_tw_rdy    : OUT std_logic;
    inst_ext_c     : IN  type_ext;
    itlb_inval     : IN  std_logic;
    tw_done_inst   : OUT std_logic;
    
    -- DATA
    data_tw_req    : IN  std_logic;
    data_tw_rdy    : OUT std_logic;
    data_ext_c     : IN  type_ext;
    dtlb_inval     : IN  std_logic;
    tw_done_data   : OUT std_logic;

    -- INST+DATA
    tlb_mod        : OUT type_tlb;
    tw_pte         : OUT uv32;
    tw_err         : OUT std_logic;
    tw_va          : OUT uv32;
    tw_op          : OUT enum_tw_op;
    
    -- EXT
    tw_ext         : OUT type_ext;
    tw_ext_req     : OUT std_logic;
    tw_ext_ack     : IN  std_logic;
    ext_dreq_tw    : IN  std_logic;
    ext_dr         : IN  uv32;
    
    -- REGS
    mmu_cr_nf      : IN  std_logic;
    mmu_cr_l2tlb   : IN  std_logic;
    mmu_cr_wb      : IN  std_logic;
    mmu_cr_aw      : IN  std_logic;
    mmu_ctxtpr     : IN  unsigned(35 DOWNTO 6);
    mmu_ctxtpr_maj : IN  std_logic;
    mmu_ctxr       : IN  unsigned(NB_CONTEXT-1 DOWNTO 0);
    mmu_ctxr_maj   : IN  std_logic;

    -- FAULT
    mmu_tw_fault   : OUT std_logic;
    mmu_tw_ft      : OUT unsigned(2 DOWNTO 0);
    mmu_tw_st      : OUT uv2;
    mmu_tw_di      : OUT std_logic; -- 0=DATA 1=INST
    
    reset_n        : IN  std_logic;
    clk            : IN  std_logic
    );
  
END ENTITY mcu_tw;
--------------------------------------------------------------------------------

ARCHITECTURE rtl OF mcu_tw IS
  
  CONSTANT NB_L2TLB    : natural := CPUCONF(CPUTYPE).NB_L2TLB;
  CONSTANT N_PTD_L2    : natural := CPUCONF(CPUTYPE).N_PTD_L2;

  TYPE enum_tw_etat IS (sOISIF,sTABLEWALK,sTABLEWALK_ADRS,sTABLEWALK_READ,
                        sTABLEWALK_FINAL,sTABLEWALK_WRITE,sTABLEWALK_L2TLB);
  SIGNAL tw_etat : enum_tw_etat;

  CONSTANT TDI_DATA : std_logic :='0';
  CONSTANT TDI_INST : std_logic :='1';
  
  TYPE type_tw IS RECORD
    op  : enum_tw_op;                    -- Type d'opération TW
    di  : std_logic;                     -- Data Inst
    ls  : std_logic;                     -- 0=Load 1=Store
    us  : std_logic;                     -- User/Super, pour ASI Tablewalk
    va  : uv32;                          -- Adresse virtuelle
  END RECORD;
  SIGNAL tww : type_tw;
  
  FUNCTION tw_asi (
    CONSTANT ext_dr_us : std_logic;
    CONSTANT ext_dr_di : std_logic) RETURN unsigned IS
  BEGIN
    IF ext_dr_us='0' AND ext_dr_di=TDI_DATA THEN
      RETURN ASI_USER_DATA_TABLEWALK;
    ELSIF ext_dr_us='1' AND ext_dr_di=TDI_DATA THEN
      RETURN ASI_SUPER_DATA_TABLEWALK;
    ELSIF ext_dr_us='0' AND ext_dr_di=TDI_INST THEN
      RETURN ASI_USER_INSTRUCTION_TABLEWALK;
    ELSE  --IF ext_dr_us='1' AND ext_dr_di=TDI_INST THEN
      RETURN ASI_SUPER_INSTRUCTION_TABLEWALK;
    END IF;    
  END;
  
  SIGNAL data_tw_rdy_l,inst_tw_rdy_l : std_logic;
  SIGNAL data_tw_mem,inst_tw_mem : type_ext;
  SIGNAL data_tw2_req_c,inst_tw2_req_c : std_logic;
  SIGNAL data_tw2_c ,inst_tw2_c  : type_ext;
  SIGNAL tw_st : uv2;              -- Niveau pagetable pendant TW
  
  -------------------------------------------------------------
  TYPE type_ptd_l2 IS RECORD
    ptd : unsigned(31 DOWNTO 2);  -- Inst Lev.2 Page Table Pointer
    tag : unsigned(31 DOWNTO 18); -- Inst Lev.2 Virt. Adrs
    v   : std_logic;              -- Valid  
  END RECORD;
  TYPE arr_ptd_l2 IS ARRAY(natural RANGE <>) OF type_ptd_l2;

  SIGNAL ptd_l2i : arr_ptd_l2(0 TO N_PTD_L2-1);
  SIGNAL ptd_l2d : arr_ptd_l2(0 TO N_PTD_L2-1);

  SIGNAL ptd_l2d_hist : uv8;
  SIGNAL ptd_l2i_hist : uv8;

  -- SIGNAL ptd_l2i : unsigned(31 DOWNTO 2);      -- Inst Lev.2 Page Table Pointer
  -- SIGNAL ptd_l2i_tag : unsigned(31 DOWNTO 18); -- Inst Lev.2 Virt. Adrs
  -- SIGNAL ptd_l2i_val : std_logic;              -- Valid
  -- SIGNAL ptd_l2d : unsigned(31 DOWNTO 2);      -- Data Lev.2 Page Table Pointer
  -- SIGNAL ptd_l2d_tag : unsigned(31 DOWNTO 18); -- Data Lev.2 Virt. Adrs
  -- SIGNAL ptd_l2d_val : std_logic;              -- Valid

  SIGNAL ptd_l0 : unsigned(31 DOWNTO 2);       -- Lev.0 Page Table Pointer
  SIGNAL ptd_l0_val : std_logic;               -- Valid

  -------------------------------------------------------------
  -- l2TLB
  SIGNAL l2tlb_a,l2tlb_a_mem : unsigned(NB_L2TLB+1 DOWNTO 0);
  SIGNAL l2tlb_dr,l2tlb_dw : uv32;
  SIGNAL l2tlb_wr,l2tlb_wr2 : std_logic;

  SIGNAL l2tlb_w  : type_pvc_w;
  SIGNAL l2tlb_r  : type_pvc_r;
  SIGNAL l2tlb_tw : std_logic;
  
  SIGNAL l2tlb_ipend,l2tlb_dpend : natural RANGE 0 TO 15;

  SIGNAL l2tlb_icpt,l2tlb_dcpt,l2tlb_cpt : unsigned(NB_L2TLB-1 DOWNTO 0);
  SIGNAL l2tlb_cpt2 : unsigned(NB_L2TLB DOWNTO 0);
  SIGNAL l2tlb_inc,l2tlb_idec,l2tlb_ddec : std_logic;
  SIGNAL l2tlb_iflu,l2tlb_dflu : std_logic;

  SIGNAL tw_pte_l : uv32;
  SIGNAL mmu_tw_st_l : uv2;
  SIGNAL wbzone : std_logic;
  
BEGIN
  --###############################################################
  -- Tablewalk
  TurlusiphonTW:PROCESS (clk)
  BEGIN
    IF rising_edge(clk) THEN
      IF inst_tw_rdy_l='1' THEN
        inst_tw_mem<=inst_ext_c;
      END IF;
      IF data_tw_rdy_l='1' THEN
        data_tw_mem<=data_ext_c;
      END IF;
      
      IF tw_etat=sOISIF AND l2tlb_wr='0' AND data_tw_req='0' AND data_tw_rdy_l='1' THEN
        inst_tw_rdy_l<='1';
      ELSIF inst_tw_req='1' THEN
        inst_tw_rdy_l<='0';
      END IF;
      
      IF tw_etat=sOISIF AND l2tlb_wr='0' THEN
        data_tw_rdy_l<='1';
      ELSIF data_tw_req='1' THEN
        data_tw_rdy_l<='0';
      END IF;

      IF reset_n='0' THEN
        inst_tw_rdy_l<='1';
        data_tw_rdy_l<='1';
      END IF;
    END IF;
  END PROCESS TurlusiphonTW;
  
  inst_tw2_c<=inst_ext_c WHEN inst_tw_rdy_l='1' ELSE inst_tw_mem;
  data_tw2_c<=data_ext_c WHEN data_tw_rdy_l='1' ELSE data_tw_mem;
  
  inst_tw2_req_c<=inst_tw_req OR NOT inst_tw_rdy_l;
  data_tw2_req_c<=data_tw_req OR NOT data_tw_rdy_l;
  
  l2tlb_a<=l2tlb_a_mem WHEN l2tlb_wr='1' ELSE
           data_tw2_c.va(NB_L2TLB+12 DOWNTO 12) & '0' WHEN -- DATA / TAG
              tw_etat=sOISIF AND data_tw2_req_c='1' ELSE
           inst_tw2_c.va(NB_L2TLB+12 DOWNTO 12) & '0' WHEN -- INST / TAG
              tw_etat=sOISIF ELSE
           l2tlb_a_mem(NB_L2TLB+1 DOWNTO 1) & '0' WHEN -- TAG
              tw_etat=sTABLEWALK AND l2tlb_wr2='1' ELSE
           l2tlb_a_mem;
  
  l2tlb_w.req<='1';
  l2tlb_w.be <="1111";
  l2tlb_w.wr <=l2tlb_wr;
  l2tlb_w.a(31 DOWNTO NB_L2TLB+4)<=(OTHERS => '0');  -- Bourrage
  l2tlb_w.a(NB_L2TLB+3 DOWNTO 0)<=l2tlb_a & "00";
  l2tlb_w.ah<=x"0";
  l2tlb_w.dw <=l2tlb_dw;
  l2tlb_dr<=l2tlb_r.dr;
  
  i_l2tlb: ENTITY work.iram
    GENERIC MAP (
      N => NB_L2TLB+4, OCT=>false)
    PORT MAP (
      mem_w    => l2tlb_w,
      mem_r    => l2tlb_r,
      clk      => clk);
  
  Walker:PROCESS (clk)
    VARIABLE l2tlb_hit_v : std_logic;
    VARIABLE l2tlb_tag_v : uv32;
    VARIABLE pa_v : unsigned(35 DOWNTO 0);
    VARIABLE cont_v,err_v : std_logic;
    VARIABLE ig_v : std_logic;
    VARIABLE ptd_l2d_v,ptd_l2i_v : unsigned(31 DOWNTO 2);
    VARIABLE ptd_l2d_hit_v,ptd_l2i_hit_v : boolean;
    VARIABLE ptd_l2d_n_v,ptd_l2i_n_v : natural RANGE 0 TO N_PTD_L2-1;
    VARIABLE ptd_l2d_old_v,ptd_l2i_old_v : natural RANGE 0 TO N_PTD_L2-1;

  BEGIN
    IF rising_edge(clk) THEN
      tw_err<='0';
      l2tlb_wr<='0';
      l2tlb_wr2<=l2tlb_wr;
      l2tlb_idec<='0';
      l2tlb_ddec<='0';
      tw_done_data<='0';
      tw_done_inst<='0';
      mmu_tw_fault<='0';
      
      tw_ext.pw.burst<=PB_SINGLE;
      tw_ext.pw.cache<='1';
      tw_ext.pw.be  <="1111";
      tw_ext.pw.cont<='0';
      tw_ext.ts<='0';      
      
      -------------------------------------------------
      vtag_test(l2tlb_hit_v,ig_v,l2tlb_dr,
                tww.va(31 DOWNTO NB_L2TLB+13) &
                l2tlb_cpt2 & tww.va(11 DOWNTO 0),
                mmu_ctxr,ASI_CACHE_FLUSH_LINE_COMBINED_ANY,12,NB_CONTEXT,false);
      
      l2tlb_tag_v:=vtag_encode(tww.va(31 DOWNTO NB_L2TLB+13) &
                               l2tlb_cpt2 & tww.va(11 DOWNTO 0),
                               mmu_ctxr,'1','0',"00",12,NB_CONTEXT);

      -------------------------------------------------
      ptd_l2d_v := (OTHERS =>'0');
      ptd_l2d_hit_v := false;
      ptd_l2d_n_v := 0;
      ptd_l2d_old_v := lru_old(ptd_l2d_hist,N_PTD_L2);
      
      ptd_l2i_v := (OTHERS =>'0');
      ptd_l2i_hit_v := false;
      ptd_l2i_n_v := 0;
      ptd_l2i_old_v := lru_old(ptd_l2i_hist,N_PTD_L2);
      
      FOR i IN 0 TO N_PTD_L2-1 LOOP
        IF ptd_l2d(i).tag(31 DOWNTO 18)=tww.va(31 DOWNTO 18) AND ptd_l2d(i).v='1' THEN
          ptd_l2d_hit_v:=true;
          ptd_l2d_v := ptd_l2d_v OR ptd_l2d(i).ptd;
          ptd_l2d_n_v := i;
        END IF;
        IF ptd_l2d(i).v='0' THEN
          ptd_l2d_old_v := i;
        END IF;
        IF ptd_l2i(i).tag(31 DOWNTO 18)=tww.va(31 DOWNTO 18) AND ptd_l2i(i).v='1' THEN
          ptd_l2i_hit_v:=true;
          ptd_l2i_v := ptd_l2i_v OR ptd_l2i(i).ptd;
          ptd_l2i_n_v := i;
        END IF;
        IF ptd_l2i(i).v='0' THEN
          ptd_l2i_old_v := i;
        END IF;
      END LOOP;

      -------------------------------------------------
      CASE tw_etat IS
        WHEN sOISIF =>
          tw_ext.pw.mode<=PB_MODE_RD;
          tw_ext.pw.lock<='0';
          l2tlb_a_mem<=inst_tw2_c.va(NB_L2TLB+12 DOWNTO 12) & '1';
          tww<=(op=>inst_tw2_c.twop,di=>TDI_INST,
                ls=>inst_tw2_c.twls,us=>inst_tw2_c.pw.asi(0),va=>inst_tw2_c.va);
          l2tlb_dw(0)<='0'; -- TAG_V=0
          tw_ext.pw.asi<=tw_asi(inst_tw2_c.pw.asi(0),TDI_INST);
          IF data_tw2_req_c='1' AND l2tlb_wr='0' THEN
            -- Tablewalk
            tw_etat<=sTABLEWALK;
            tww<=(op=>data_tw2_c.twop,di=>TDI_DATA,
                  ls=>data_tw2_c.twls,us=>data_tw2_c.pw.asi(0),va=>data_tw2_c.va);
            tw_ext.pw.asi<=tw_asi(data_tw2_c.pw.asi(0),TDI_DATA);
            l2tlb_a_mem<=data_tw2_c.va(NB_L2TLB+12 DOWNTO 12) & '1';
            
          ELSIF inst_tw2_req_c='1' AND l2tlb_wr='0' THEN
            -- Tablewalk
            tw_etat<=sTABLEWALK;
            tww<=(op=>inst_tw2_c.twop,di=>TDI_INST,
                  ls=>inst_tw2_c.twls,us=>inst_tw2_c.pw.asi(0),va=>inst_tw2_c.va);
            tw_ext.pw.asi<=tw_asi(inst_tw2_c.pw.asi(0),TDI_INST);
            
          ELSE
            IF l2tlb_ipend/=0 AND l2tlb_idec='0' THEN
              l2tlb_idec<=mmu_cr_l2tlb;
              l2tlb_wr<=mmu_cr_l2tlb;
              l2tlb_a_mem<=l2tlb_icpt & "10";
            ELSIF l2tlb_dpend/=0 AND l2tlb_ddec='0' THEN
              l2tlb_ddec<=mmu_cr_l2tlb;
              l2tlb_wr<=mmu_cr_l2tlb;
              l2tlb_a_mem<=l2tlb_dcpt & "00";  
            END IF;
          END IF;
          
          ------------------------------
        WHEN sTABLEWALK =>
          -- Parcours de la table :
          -- Pour un accès normal (lecture ou écriture), on cherche un PTE
          -- Pour un probe, on s'arrête ou on continue selon le mode.
          -- Un probe 'entire' est comme un accès normal.
          --   - Pour remplir un TLB, suite à un accès
          --   - Pour positionner le bit Modified, suite à une écriture
          --   - Pour lire une PTE (MMU_PROBE)

          -- Soit le cache PTP_niveau 2 est utilisable --> TW à partir du L2
          -- Soit le cache PTP_niveau 0 est utilisable --> TW à partir du L0
          -- Sinon, il faut lire à partir du contexte, sans aide
          tw_ext_req<='0';
          
          tw_st<="00";    -- On démarre le tablewalk de zéro par défaut
          -- Level 0 : Context : Context_Table_Pointer(Context)
          pa_v(35 DOWNTO NB_CONTEXT+2):=mmu_ctxtpr(35 DOWNTO NB_CONTEXT+2);
          pa_v(NB_CONTEXT+1 DOWNTO 0) :=mmu_ctxr(NB_CONTEXT-1 DOWNTO 0) & "00";
          
          IF l2tlb_wr2='0' THEN
            l2tlb_a_mem(0)<='1';
            tw_etat<=sTABLEWALK_ADRS;
            IF tww.op=LS
            --  OR (tww.op=PROBE AND tww.va(10 DOWNTO 8)=PT_ENTIRE)
            THEN
              IF l2tlb_hit_v='1' AND mmu_cr_l2tlb='1' AND l2tlb_tw='0' THEN
                -- DATA/INST : Le cache L2TLB correspond. Super !
                tw_st<="11";
                tw_etat<=sTABLEWALK_L2TLB;
                l2tlb_a_mem(0)<='1'; -- Lecture data
                tw_ext_req<='0';
              ELSIF ptd_l2d_hit_v AND tww.di=TDI_DATA THEN
                -- DATA : Le cache de PTP L2 est valide et il correspond
                tw_st<="11";
                pa_v(35 DOWNTO 8):=ptd_l2d_v(31 DOWNTO 4);
                pa_v( 7 DOWNTO 0):=tww.va(17 DOWNTO 12) & "00";
                tw_ext_req<='1';
                tw_ext.pw.lock<='1';
                ptd_l2d_hist <= lru_maj(ptd_l2d_hist,ptd_l2d_n_v,N_PTD_L2);

              ELSIF ptd_l2i_hit_v AND tww.di=TDI_INST THEN
                -- INST : Le cache de PTP L2 est valide et il correspond
                tw_st<="11";
                pa_v(35 DOWNTO 8):=ptd_l2i_v(31 DOWNTO 4);
                pa_v( 7 DOWNTO 0):=tww.va(17 DOWNTO 12) & "00";
                tw_ext_req<='1';
                tw_ext.pw.lock<='1';
                ptd_l2i_hist <= lru_maj(ptd_l2i_hist,ptd_l2i_n_v,N_PTD_L2);
                
              ELSIF ptd_l0_val='1' THEN
                -- Le cache de PTP L0 est valide et il correspond
                tw_st<="01";
                pa_v(35 DOWNTO 10):=ptd_l0(31 DOWNTO 6);
                pa_v( 9 DOWNTO  0):=tww.va(31 DOWNTO 24) & "00";
                tw_ext_req<='1';
                tw_ext.pw.lock<='1';

              ELSE
                tw_ext_req<='1';
                tw_ext.pw.lock<='1';
              END IF;
            ELSE
              tw_ext_req<='1';
              tw_ext.pw.lock<='1';
            END IF;
          END IF;
          tw_ext.pw.ah<=pa_v(35 DOWNTO 32);
          tw_ext.pw.a<=pa_v(31 DOWNTO 0);
          
          ------------------------------
        WHEN sTABLEWALK_ADRS => -- <gratter 1 cycle>
          IF tw_ext_ack='1' THEN
            tw_ext_req<='0';
            tw_etat<=sTABLEWALK_READ;
          END IF;
          
          ------------------------------
        WHEN sTABLEWALK_READ =>
          -- Lecture d'un PTE ou PTD
          tw_pte_l<=ext_dr;
          mmu_tw_st_l <=tw_st;
          IF ext_dr(1 DOWNTO 0)=ET_INVALID THEN
            mmu_tw_ft<=FT_INVALID;
          ELSE
            mmu_tw_ft<=FT_TRANSLATION;
          END IF;
          l2tlb_dw<=l2tlb_tag_v;
          l2tlb_a_mem(0)<='0'; -- Ecriture tag
          IF ext_dreq_tw='1' THEN
            tablewalk_test(cont_v,err_v,
                           ext_dr,tw_st,to_std_logic(tww.op=PROBE),
                           tww.va(10 DOWNTO 8));
            IF err_v='1' THEN
              -- Erreur
              tw_etat<=sOISIF;
              IF tww.op/=PROBE THEN
                mmu_tw_fault<='1';
                tw_err<=NOT mmu_cr_nf;
              END IF;
              tw_done_data<=to_std_logic(tww.di=TDI_DATA) AND NOT l2tlb_tw;
              tw_done_inst<=to_std_logic(tww.di=TDI_INST) AND NOT l2tlb_tw;
              tw_va<=tww.va;
              tw_op<=tww.op;
              l2tlb_tw<='0';

            ELSIF cont_v='1' THEN
              -- On continue le TW
              tw_st<=tw_st+1;
              tw_etat<=sTABLEWALK_ADRS;

              CASE tw_st IS
                WHEN "00" =>
                  -- Level 1 : 256 entrées, 8bits, VA[31:24]
                  pa_v(35 DOWNTO 10):=ext_dr(31 DOWNTO 6);
                  pa_v(9 DOWNTO 0):=tww.va(31 DOWNTO 24) & "00";
                WHEN "01" =>
                  -- Level 2 : 64 entrées, 6bits, VA[23:18]
                  pa_v(35 DOWNTO 8):=ext_dr(31 DOWNTO 4);
                  pa_v(7 DOWNTO 0):=tww.va(23 DOWNTO 18) & "00";
                WHEN OTHERS =>
                  -- Level 3 : 64 entrées, 6bits, VA[17:12]
                  pa_v(35 DOWNTO 8):=ext_dr(31 DOWNTO 4);
                  pa_v(7 DOWNTO 0):=tww.va(17 DOWNTO 12) & "00";
              END CASE;
              tw_ext.pw.ah<=pa_v(35 DOWNTO 32);
              tw_ext.pw.a<=pa_v(31 DOWNTO 0);
              
              tw_ext_req<='1';
            ELSE
              -- Fin du TW
              tw_etat<=sTABLEWALK_FINAL;
              tw_done_data<=to_std_logic(tww.di=TDI_DATA) AND NOT l2tlb_tw;
              tw_done_inst<=to_std_logic(tww.di=TDI_INST) AND NOT l2tlb_tw;
              tw_va<=tww.va;
              tw_op<=tww.op;
              l2tlb_tw<='0';
              IF tw_st="11" THEN -- Mise à jour tag L2TLB
                l2tlb_wr<=mmu_cr_l2tlb;
              END IF;
            END IF;
            
            -- MàJ des PTD L0 et L2D et L2I cachés
            IF tww.op/=PROBE AND err_v='0' THEN
              IF tw_st="00" AND ext_dr(1 DOWNTO 0)=ET_PTD THEN
                ptd_l0<=ext_dr(31 DOWNTO 2);
                ptd_l0_val<='1';
              END IF;
              IF tw_st="10" AND ext_dr(1 DOWNTO 0)=ET_PTD THEN
                IF tww.di=TDI_DATA THEN
                  ptd_l2d(ptd_l2d_old_v).ptd <=ext_dr(31 DOWNTO 2);
                  ptd_l2d(ptd_l2d_old_v).tag <=tww.va(31 DOWNTO 18);
                  ptd_l2d(ptd_l2d_old_v).v   <='1';
                  ptd_l2d_hist <= lru_maj(ptd_l2d_hist,ptd_l2d_old_v,N_PTD_L2);
                ELSE
                  ptd_l2i(ptd_l2i_old_v).ptd <=ext_dr(31 DOWNTO 2);
                  ptd_l2i(ptd_l2i_old_v).tag <=tww.va(31 DOWNTO 18);
                  ptd_l2i(ptd_l2i_old_v).v   <='1';
                  ptd_l2i_hist <= lru_maj(ptd_l2i_hist,ptd_l2i_old_v,N_PTD_L2);
                END IF;
              END IF;
            END IF;
          END IF;

          ------------------------------
        WHEN sTABLEWALK_FINAL =>
          -- Le TableWalk est terminé.
          -- tw_op indique ce qu'il faut faire ensuite
          l2tlb_a_mem(0)<='1'; -- Écriture data
          l2tlb_dw<=tw_pte_l;
          IF tww.op=LS THEN
            IF tw_st="11" THEN
              l2tlb_wr<=mmu_cr_l2tlb;
            END IF;
            -- Le tablewalk a été déclenché suite à une lecture, il faut
            -- positionner R=PTE(5)
            IF tww.ls='0' AND tw_pte_l(5)='0' THEN
              -- Si R=PTE(5) est à zéro,il faut mettre à jour la PTE.
              tw_ext.pw.d <=tw_pte_l OR x"00000020";  -- R=1
              l2tlb_dw<=tw_pte_l OR x"00000020";  -- R=1
              tw_ext_req<='1';
              tw_etat<=sTABLEWALK_WRITE;
              tw_ext.pw.mode<=PB_MODE_WR;
            ELSIF tww.ls='1' AND (tw_pte_l(5)='0' OR tw_pte_l(6)='0') THEN
              -- Si R ou M est à zéro, il faut mettre à jour la PTE.
              tw_ext.pw.d <=tw_pte_l OR x"00000060";  -- M=1 R=1
              l2tlb_dw<=tw_pte_l OR x"00000060";  -- M=1 R=1
              tw_ext_req<='1';
              tw_etat<=sTABLEWALK_WRITE;
              tw_ext.pw.mode<=PB_MODE_WR;
            ELSE
              tw_etat<=sOISIF;
              tw_ext.pw.lock<='0';
            END IF;
          ELSE
            -- Le tablewalk fait suite à un MMU PROBE
            tw_etat<=sOISIF;
            tw_ext.pw.lock<='0';
            IF tw_st="11" THEN
              l2tlb_wr<=mmu_cr_l2tlb;
            END IF;
          END IF;
          
          ------------------------------
        WHEN sTABLEWALK_WRITE =>
          -- MAJ d'un PTE suite à un Tablewalk
          IF tw_ext_ack='1' THEN
            tw_etat<=sOISIF;
            tw_ext_req<='0';
            tw_ext.pw.lock<='0';
          END IF;

          ------------------------------
        WHEN sTABLEWALK_L2TLB =>
          -- Le L2TLB correspond. Il faut peut être modifier
          mmu_tw_st_l <="11";
          IF tww.op=LS THEN
            IF tww.ls='1' THEN
              tw_pte_l<=l2tlb_dr OR x"00000060"; -- M=1 R=1
            ELSE
              tw_pte_l<=l2tlb_dr OR x"00000020"; -- R=1
            END IF;
            tw_done_data<=to_std_logic(tww.di=TDI_DATA);
            tw_done_inst<=to_std_logic(tww.di=TDI_INST);
            tw_va<=tww.va;
            tw_op<=tww.op;
            IF l2tlb_dr(5)='0' OR (tww.ls='1' AND l2tlb_dr(6)='0') THEN
              -- S il faut mettre à jour le PTE, à cause de R ou M, il faut
              -- déclencher un vrai tablewalk.
              tw_etat<=sTABLEWALK;
              l2tlb_tw<='1';
            ELSE
              tw_etat<=sOISIF;
              tw_ext.pw.lock<='0';
            END IF;

          ELSE -- PROBE
            -- Le tablewalk fait suite à un MMU PROBE
            tw_etat<=sOISIF;
            tw_pte_l<=l2tlb_dr;
            tw_ext.pw.lock<='0';
          END IF;
          ------------------------------
      END CASE;
      
      -------------------------------------------------
      -- On force la purge des caches de PTD.
      -- <AFAIRE> Raffiner les conditions
      IF mmu_ctxtpr_maj='1' OR mmu_ctxr_maj='1' OR
        itlb_inval='1' OR dtlb_inval='1' THEN
        ptd_l0_val<='0';
      END IF;
      IF mmu_ctxtpr_maj='1' OR mmu_ctxr_maj='1' OR
        dtlb_inval='1' THEN
        FOR i IN 0 TO N_PTD_L2-1 LOOP
          ptd_l2d(i).v<='0';
        END LOOP;
      END IF;
      IF mmu_ctxtpr_maj='1' OR mmu_ctxr_maj='1' OR
        itlb_inval='1' THEN
        FOR i IN 0 TO N_PTD_L2-1 LOOP
          ptd_l2i(i).v<='0';
        END LOOP;
      END IF;
      
      -------------------------------------------------
      IF mmu_ctxtpr_maj='1' OR dtlb_inval='1' OR itlb_inval='1' THEN
        l2tlb_cpt<=l2tlb_cpt+1;
        l2tlb_cpt2<=l2tlb_cpt2+1;
        l2tlb_inc<='1';
      ELSE
        l2tlb_inc<='0';
      END IF;
      
      IF l2tlb_inc='1' AND l2tlb_ddec='0' THEN
        l2tlb_dpend<=l2tlb_dpend+1;
      ELSIF l2tlb_inc='0' AND l2tlb_ddec='1' THEN
        l2tlb_dpend<=l2tlb_dpend-1;
        l2tlb_dcpt<=l2tlb_dcpt+1;
      END IF;
      
      IF l2tlb_inc='1' AND l2tlb_idec='0' THEN
        l2tlb_ipend<=l2tlb_ipend+1;
      ELSIF l2tlb_inc='0' AND l2tlb_idec='1' THEN
        l2tlb_ipend<=l2tlb_ipend-1;
        l2tlb_icpt<=l2tlb_icpt+1;
      END IF;
      
      -------------------------------------------------
      IF reset_n='0' THEN
        l2tlb_tw<='0';
        l2tlb_ipend<=0;
        l2tlb_dpend<=0;
        l2tlb_icpt<=(OTHERS =>'0');
        l2tlb_dcpt<=(OTHERS =>'0');
        l2tlb_cpt <=(OTHERS =>'0');
        l2tlb_cpt2<=(OTHERS =>'0');
        ptd_l0_val<='0';
        FOR i IN 0 TO N_PTD_L2-1 LOOP
          ptd_l2d(i).v<='0';
          ptd_l2i(i).v<='0';
        END LOOP;
        tw_done_inst<='0';
        tw_done_data<='0';
        tw_ext_req<='0';
        tw_etat<=sOISIF;
      END IF;        

    END IF;
  END PROCESS Walker;
  
  tw_pte<=tw_pte_l;
  wbzone<=to_std_logic(tw_pte_l(31 DOWNTO 8)<x"0" & WBSIZE(31 DOWNTO 4));
  tlb_mod<=tlb_encode(tw_pte_l,tww.va,mmu_tw_st_l,mmu_ctxr,tww.ls,
                      wbzone AND mmu_cr_wb,
                      wbzone AND mmu_cr_aw AND mmu_cr_wb);
  
  data_tw_rdy<=data_tw_rdy_l;
  inst_tw_rdy<=inst_tw_rdy_l;
  
  mmu_tw_st<=mmu_tw_st_l;
  
  mmu_tw_di<=tww.di;
  
END ARCHITECTURE rtl;
