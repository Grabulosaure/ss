--------------------------------------------------------------------------------
-- TEM : TACUS
-- Contrôleur MMU / Cache
--------------------------------------------------------------------------------
-- DO 2/2010
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

-- Version simple
--  - Caches Séparés I et D.
--  - Choix Direct map / Multiway LRU
--  - Write Through with no allocate
--  - Si pas de MMU, pas de cache
--  - Pas de snooping
--  - Caches pour un PTD L0, un PTD L2I et un PTD L2D

-- En Boot Mode, le cache instruction est désactivé.

-- 5 parties :
--  - Interface DATA
--  - Interface INSTRUCTION
--  - Registres MMU
--  - Séquenceur TableWalk
--  - Bus externe

-- Les accès proc sont en 2 phases pipelinées :
--  -  Première : Le proc positionne les adresses (A)
--  -  Seconde  : On fournit les données et/ou le code d'erreur (D)
--------------------------------------------------------------------------------

-- On considère que inst_w.dack='1' et data_w.dack='1' en permanence

-- Traps :
--  TT_DATA_ACCESS_EXCEPTION : MMU DATA :
--     Page invalide ou protégée en écriture...
--     Accès interdit (acc, user/super)

--  TT_DATA_ACCESS_MMU_MISS  : MMU DATA :
--     Pour software tablewalk

--  TT_INST_ACCESS_EXCEPTION : MMU INST :
--     Page invalide ou protégée en écriture...
--     Accès interdit (acc, user/super)

--  TT_INST_ACCESS_MMU_MISS : MMU INST :
--     Pour software tablewalk

--------------------------------------------------
--Cache TLB L2
-- 32 I + 32 D

-- Addresse virtuelle : VA[31:12]
-- 32 entrées Direct map : VA[16:12]

-- Index : VA[16:12] + I/D + tag/data = 7 bits

--   TAG  : VA[31:17] + Valid + I/D + Context[] + U/S
--   DATA : PTE

-- Taille : 2(I/D) * 2(tag/data) * 32(entrées) * 4(32bits) = 512 octets

-- Stocke seulement PTE L3 4kB

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

USE work.base_pack.ALL;
USE work.plomb_pack.ALL;
USE work.asi_pack.ALL;
USE work.mcu_pack.ALL;
USE work.cpu_conf_pack.ALL;

--------------------------------------------------------------------------------
ARCHITECTURE simple OF mcu IS
  
  CONSTANT BLEN_DCACHE : natural := CPUCONF(CPUTYPE).BLEN_DCACHE;
  CONSTANT BLEN_ICACHE : natural := CPUCONF(CPUTYPE).BLEN_ICACHE;
  CONSTANT NB_DCACHE   : natural := CPUCONF(CPUTYPE).NB_DCACHE;
  CONSTANT NB_ICACHE   : natural := CPUCONF(CPUTYPE).NB_ICACHE;
  CONSTANT NB_LINE     : natural := ilog2(BLEN_ICACHE);
  CONSTANT DPTAG       : boolean := CPUCONF(CPUTYPE).DPTAG;
  CONSTANT IPTAG       : boolean := CPUCONF(CPUTYPE).IPTAG;
  CONSTANT WAY_DCACHE  : natural := CPUCONF(CPUTYPE).WAY_DCACHE;
  CONSTANT WAY_ICACHE  : natural := CPUCONF(CPUTYPE).WAY_ICACHE;
  CONSTANT MMU_IMP_VERSION : uv8 := CPUCONF(CPUTYPE).MMU_IMP_VER;
  CONSTANT NB_CONTEXT  : natural := CPUCONF(CPUTYPE).NB_CONTEXT;
  CONSTANT L2TLB       : boolean := CPUCONF(CPUTYPE).L2TLB;
  
  -- MMU Général, registres
  SIGNAL mmu_cr_e : std_logic;   -- MMU Control Register(0). MMU Enable
  SIGNAL mmu_cr_nf : std_logic;  -- MMU Control Register(1). No Fault
                                 -- MMU Control Register(3..2). CPU MID  
  SIGNAL mmu_cr_l2tlb : std_logic; -- MMU Control Register (6). L2 TLB cache
  SIGNAL mmu_cr_dce : std_logic; -- MMU Control Register(8). Data Cache Enable
  SIGNAL mmu_cr_ice : std_logic; -- MMU Control Register(9). Inst Cache Enable
  
  SIGNAL mmu_cr_bm : std_logic;  -- MMU Control Register(14).Boot Mode Simple
  
  SIGNAL mmu_cr_maj : std_logic; -- MMU Control Register. MàJ

  SUBTYPE type_context IS unsigned(NB_CONTEXT-1 DOWNTO 0);
  SIGNAL mmu_ctxr : type_context;            -- MMU Context Register
  SIGNAL mmu_ctxr_maj : std_logic;           -- MMU Context Register. MàJ
  SIGNAL mmu_ctxtpr : unsigned(35 DOWNTO 6); -- MMU Context Table Pointer reg.
  SIGNAL mmu_ctxtpr_maj : std_logic;         -- MMU Context Table Pointer. MàJ

  CONSTANT MMU_FSR_EBE : uv8 :=x"00";  -- MMU Fault Status. Ext. Bus Error
  SIGNAL mmu_fsr_l   : unsigned(1 DOWNTO 0); -- MMU Fault Status. Level
  SIGNAL mmu_fsr_at  : unsigned(2 DOWNTO 0); -- MMU Fault Status. Access Type
  SIGNAL mmu_fsr_ft  : unsigned(2 DOWNTO 0); -- MMU Fault Status. Fault Type
  SIGNAL mmu_fsr_fav : std_logic;   -- MMU Fault Status. Fault Address Valid
  SIGNAL mmu_fsr_ow  : std_logic;   -- MMU Fault Status. OverWrite
  SIGNAL mmu_fsr_maj : std_logic;
  
  SIGNAL mmu_far : unsigned(31 DOWNTO 2);  -- MMU Fault Address Register

  SIGNAL mmu_tmpr : uv32;
  SIGNAL mmu_tmpr_maj : std_logic;

  TYPE enum_mmu_fclass IS (RIEN,DATA,INST,WALK);
  SIGNAL mmu_fclass : enum_mmu_fclass;  -- Type de faute mémorisée
  
  -- Empilage des données à renvoyer.
  TYPE type_push IS RECORD
    code : enum_plomb_code;
    d    : uv32;
    cx   : std_logic;
  END RECORD;
  
  SIGNAL dreg : uv32;
  SIGNAL mmu_l2tlbena : std_logic;
  
  ------------------------------------------------------------------------------
  -- Opération requise vers le contrôleur de bus externe :
  -- SINGLE   : Accès simple
  -- FILL     : Cache fill read
  -- LS       : Tablewalk, pour une lecture ou une écriture
  -- PROBE    : Tablewalk, pour un ASI_MMU_PROBE
  
  --TYPE type_ext IS RECORD
  --  pw   : type_plomb_w; -- Accès externe
  --  op   : enum_ext_op;  -- Type d'opération accès externe
  --  twop : enum_tw_op;   -- Type d'opération Tablewalk
  --  ts   : std_logic;    -- Mode User/Super du TLB
  --  va   : uv32;         -- Adresse virtuelle (pour cache fill)
  --END RECORD;
  
  --------------------------------------------------------
  -- DATA
  TYPE enum_data_etat IS (sOISIF,sREGISTRE,sCROSS,sCROSS_DATA,
                          sTABLEWALK,sEXT_READ);
  SIGNAL data_etat_c,data_etat : enum_data_etat;

  -- Contrôles
  SIGNAL data_r_c : type_plomb_r;
  SIGNAL data2_w  : type_plomb_w;        -- Cycle 2
  SIGNAL data_na_c  : std_logic;         -- Acquitte l'accès
  SIGNAL data_clr_c : std_logic;        -- Fin d'accès écriture
  
  SIGNAL data_ext_c : type_ext;         -- Paramètres accès externe data
  SIGNAL data_ext_mem : type_ext;
  
  SIGNAL data_ext_req_c,data_ext_rdy,data_ext_reqm,pop_data_c : std_logic;
  SIGNAL data_ext2_c : type_ext;
  
  SIGNAL data_ft_c : unsigned(2 DOWNTO 0);
  SIGNAL data_at_c : unsigned(2 DOWNTO 0);
  
  -- MMU
  SIGNAL dtlb : arr_tlb(0 TO N_DTLB-1); -- TLBs Data
  SIGNAL dtlb_cpt : natural RANGE 0 TO N_DTLB-1;  -- Compteur remplacement
  SIGNAL dtlb_hist : unsigned(7 DOWNTO 0);  -- Historique LRU
  SIGNAL dtlb_hit_c,dtlb_hit : unsigned(0 TO N_DTLB-1);
  SIGNAL dtlb_hitv : std_logic;
  SIGNAL dtlb_inv_c,dtlb_inv : unsigned(0 TO N_DTLB-1);
  SIGNAL dtlb_inval_c : std_logic;
  SIGNAL dtlb_maj_c : std_logic;
  SIGNAL dtlb_sel_c : std_logic;
  SIGNAL mmu_fault_data_acc_c : std_logic;
  SIGNAL dtlb_mem : type_tlb;
  SIGNAL data_jat : std_logic;          --'Juste après Tablewalk'
  SIGNAL dtlb_twm : std_logic;          -- Tablewalk pour positionner le bit M
  SIGNAL dtlb_twm_c : std_logic;
  SIGNAL dtlb_hitm : unsigned(0 TO N_DTLB-1);
  
  -- CACHE
  SIGNAL dcache_d_w,dcache_t_w : arr_pvc_w(0 TO WAY_DCACHE-1);
  SIGNAL dcache_d_r,dcache_t_r : arr_pvc_r(0 TO WAY_DCACHE-1);
  SIGNAL dcache_d_a : unsigned(NB_DCACHE-1 DOWNTO 2);  -- Adresse Data Cache
  SIGNAL dcache_d_dr : arr_uv32(0 TO WAY_DCACHE-1);
  SIGNAL dcache_d_dw : uv32;
  SIGNAL dcache_d_wr : arr_uv0_3(0 TO WAY_DCACHE-1);
  SIGNAL dcache_t_a : unsigned(NB_DCACHE-NB_LINE-1 DOWNTO 2);
  SIGNAL dcache_t_dr,dcache_t_dw : arr_uv32(0 TO WAY_DCACHE-1);
  SIGNAL dcache_t_mem : arr_uv32(0 TO WAY_DCACHE-1);
  SIGNAL dcache_tmux  : arr_uv32(0 TO WAY_DCACHE-1);
  SIGNAL dcache_blo_c : std_logic;
  SIGNAL dcache_t_wr : uv0_3;
  SIGNAL dcache_cpt : natural RANGE 0 TO WAY_DCACHE-1;  -- Cpt. aléatoire
  
  SIGNAL data_txt : string(1 TO 9);
  
  --------------------------------------------------------
  -- Passerelle DATA -> INST
  SIGNAL cross_req_c : std_logic;       -- Requête
  SIGNAL cross_ack_c : std_logic;         -- Acquittement
  SIGNAL cross,cross_c : std_logic;  -- Seconde partie accès croisé
  
  --------------------------------------------------------
  -- INST
  TYPE enum_inst_etat IS (sOISIF,sTABLEWALK,sEXT_READ);
  SIGNAL inst_etat_c,inst_etat : enum_inst_etat;
  
  SIGNAL imux_w : type_plomb_w;         -- Bus instructions multiplexé
  SIGNAL inst_r_c : type_plomb_r;
  SIGNAL imux2_w  : type_plomb_w;        -- Cycle 2
  SIGNAL inst_na_c  : std_logic;         -- Acquitte l'accès
  SIGNAL inst_clr_c : std_logic;         -- Fin d'accès écriture
  
  SIGNAL inst_ext_c : type_ext;
  SIGNAL inst_ext_mem : type_ext;
  SIGNAL inst_ext2_c : type_ext;

  SIGNAL inst_ext_req_c,inst_ext_rdy,inst_ext_reqm,pop_inst_c : std_logic;
  SIGNAL imux_cx,imux2_cx,imux3_cx : std_logic;
  SIGNAL inst_cont : std_logic;
  
  SIGNAL inst_ft_c : unsigned(2 DOWNTO 0);
  SIGNAL inst_at_c : unsigned(2 DOWNTO 0);
  SIGNAL inst_dr_c,inst_dr : type_push;
  
  -- MMU
  SIGNAL itlb : arr_tlb(0 TO N_ITLB-1); -- TLBs Instruction
  SIGNAL itlb_cpt : natural RANGE 0 TO N_ITLB-1;  -- Compteur remplacement
  SIGNAL itlb_hist : unsigned(7 DOWNTO 0);  -- Historique LRU
  SIGNAL itlb_hit_c,itlb_hit : unsigned(0 TO N_ITLB-1);
  SIGNAL itlb_hitv : std_logic;
  SIGNAL itlb_inv_c,itlb_inv : unsigned(0 TO N_ITLB-1);
  SIGNAL itlb_inval_c : std_logic;
  SIGNAL itlb_maj_c : std_logic;
  SIGNAL itlb_sel_c : std_logic;
  SIGNAL mmu_fault_inst_acc_c : std_logic;
  SIGNAL itlb_mem : type_tlb;
  SIGNAL inst_jat : std_logic;          --'Juste après Tablewalk'
  SIGNAL itlb_twm : std_logic;          -- Tablewalk pour positionner le bit M
  SIGNAL itlb_twm_c : std_logic;
  SIGNAL itlb_hitm : unsigned(0 TO N_ITLB-1);
  
  -- CACHE
  SIGNAL icache_d_w,icache_t_w : arr_pvc_w(0 TO WAY_ICACHE-1);
  SIGNAL icache_d_r,icache_t_r : arr_pvc_r(0 TO WAY_ICACHE-1);
  SIGNAL icache_d_a  : unsigned(NB_ICACHE-1 DOWNTO 2);  -- Adresse Insn Cache
  SIGNAL icache_d_dr : arr_uv32(0 TO WAY_ICACHE-1);
  SIGNAL icache_d_dw : uv32;
  SIGNAL icache_d_wr : arr_uv0_3(0 TO WAY_ICACHE-1);
  SIGNAL icache_t_a : unsigned(NB_ICACHE-NB_LINE-1 DOWNTO 2);
  SIGNAL icache_t_dr,icache_t_dw : arr_uv32(0 TO WAY_ICACHE-1);
  SIGNAL icache_t_mem : arr_uv32(0 TO WAY_ICACHE-1);
  SIGNAL icache_tmux  : arr_uv32(0 TO WAY_DCACHE-1);
  SIGNAL icache_blo_c : std_logic;
  SIGNAL icache_t_wr : uv0_3;
  SIGNAL icache_cpt : natural RANGE 0 TO WAY_ICACHE-1;  -- Cpt. aléatoire
 
  SIGNAL inst_txt : string(1 TO 9);
  
  --------------------------------------------------------
  -- TableWalker

  TYPE enum_dit IS (DI_DATA,DI_INST,DI_TW);
  
  SIGNAL data_tw_rdy   ,inst_tw_rdy    : std_logic;
  
  CONSTANT TDI_DATA : std_logic :='0';
  CONSTANT TDI_INST : std_logic :='1';
  
  SIGNAL tlb_mod_c : type_tlb;
  SIGNAL tw_ext : type_ext;
  SIGNAL tw_va : uv32;
  SIGNAL tw_op : enum_tw_op;
  
  SIGNAL tw_done_data : std_logic;     -- Tablewalk terminé
  SIGNAL tw_done_inst : std_logic;     -- Tablewalk terminé
  SIGNAL tw_pte    : uv32;             -- Données bus externe du tablewalk
  SIGNAL tw_err    : std_logic;        -- Erreur sur accès externe : Tablewalk
  
  SIGNAL tw_ext_req,pop_tw_c : std_logic;
  
  SIGNAL mmu_tw_fault : std_logic;
  SIGNAL mmu_tw_st    : uv2;              -- Niveau pagetable
  SIGNAL mmu_tw_di    : std_logic;
  SIGNAL data_tw_req_c,inst_tw_req_c : std_logic;
  
  --------------------------------------------------------
  -- Bus Externe
  TYPE enum_ext_etat IS (sOISIF,sSINGLE,sFILL);
  SIGNAL ext_etat   : enum_ext_etat;
  SIGNAL ext_dreq_data : std_logic;  -- Données bus externes prêtes pour data
  SIGNAL ext_dreq_inst : std_logic;  -- Données bus externes prêtes pour inst
  SIGNAL ext_dreq_tw   : std_logic;  -- Données bus externes prêtes pour tw
  SIGNAL ext_dr    : uv32;             -- Données bus externes vers IU
  SIGNAL ext_burst : unsigned(NB_LINE-1 DOWNTO 0);  -- Comptage Burst (côté ext)
  CONSTANT BURST_1 : unsigned(NB_LINE-1 DOWNTO 0) := (OTHERS =>'1');
  SIGNAL ext_pat_c : std_logic;
  SIGNAL mmu_tw_ft : unsigned(2 DOWNTO 0);  -- Fault Type
  SIGNAL ext_w_i : type_plomb_w;
  
  TYPE enum_ext_lock IS (LOFF,LDATA,LTW);
  SIGNAL ext_lock : enum_ext_lock;

  TYPE type_ext_fifo IS RECORD
    op  : enum_ext_op;                   -- Type d'opération accès externe
    di  : enum_dit;                      -- Data Inst TableWalk
    ts  : std_logic;                     -- MMU TLB Super, pour cache VT
    va  : uv32;                          -- Adresse virtuelle, pour cache VT
    pa  : unsigned(35 DOWNTO 0);         -- Adresse physique, pour cache PT
    al  : unsigned(NB_LINE+1 DOWNTO 2);  -- Poids faibles addresses
  END RECORD;
  
  SIGNAL ext_fifo,ext_fifo_mem,ext_fifo_mem2 : type_ext_fifo;
  SIGNAL ext_fifo_lev : natural RANGE 0 TO 3;
  SIGNAL filling_end : std_logic;
  
  -- Cache fill commandé par le bus externe
  SIGNAL ext_dfill,ext_ifill : std_logic;
  SIGNAL filling_d,filling_d2 : std_logic;
  SIGNAL filling_i,filling_i2 : std_logic;
  SIGNAL filldone : std_logic;
  
  SIGNAL fill_d : uv32;
  SIGNAL fill_va : uv32;
  SIGNAL fill_ts : std_logic;
  SIGNAL fill_pa : unsigned(35 DOWNTO 0);
  
BEGIN
  
  --###############################################################
  -- Cache Data, Instruction
  Gen_DCacheD: FOR i IN 0 TO WAY_DCACHE-1 GENERATE
    dcache_d_w(i).req<='1';
    dcache_d_w(i).be <=dcache_d_wr(i);
    dcache_d_w(i).wr <=to_std_logic(dcache_d_wr(i)/="0000");
    dcache_d_w(i).a(31 DOWNTO NB_DCACHE)<=(OTHERS => '0');  -- Bourrage
    dcache_d_w(i).a(NB_DCACHE-1 DOWNTO 0)<=dcache_d_a & "00";
    dcache_d_w(i).dw <=dcache_d_dw;
    dcache_d_dr(i)<=dcache_d_r(i).dr;
    
    i_dcache: ENTITY work.iram
      GENERIC MAP (
        N => NB_DCACHE, OCT=>true)
      PORT MAP (
        mem_w    => dcache_d_w(i),
        mem_r    => dcache_d_r(i),
        clk      => clk);
  END GENERATE Gen_DCacheD;
  
  Gen_ICacheD: FOR i IN 0 TO WAY_ICACHE-1 GENERATE
    icache_d_w(i).req<='1';
    icache_d_w(i).be <=icache_d_wr(i);
    icache_d_w(i).wr <=to_std_logic(icache_d_wr(i)/="0000");
    icache_d_w(i).a(31 DOWNTO NB_ICACHE)<=(OTHERS => '0');  -- Bourrage
    icache_d_w(i).a(NB_ICACHE-1 DOWNTO 0)<=icache_d_a & "00";
    icache_d_w(i).dw <=icache_d_dw;
    icache_d_dr(i)<=icache_d_r(i).dr;

    i_icache: ENTITY work.iram
      GENERIC MAP (
        N => NB_ICACHE, OCT=>true)
      PORT MAP (
        mem_w    => icache_d_w(i),
        mem_r    => icache_d_r(i),
        clk      => clk);
  END GENERATE Gen_ICacheD;
  
  -----------------------------------------------------------------
  -- Tags
  -- Il y a NB_DCACHE / NB_LINE / 4 tags, de 32bits, par voie
  -- Il y a NB_ICACHE / NB_LINE / 4 tags, de 32bits, par voie
  Gen_DCacheT: FOR i IN 0 TO WAY_DCACHE-1 GENERATE
    dcache_t_w(i).req<='1';
    dcache_t_w(i).be <=dcache_t_wr;
    dcache_t_w(i).wr <=to_std_logic(dcache_t_wr/="0000");
    dcache_t_w(i).a(31 DOWNTO NB_DCACHE-NB_LINE)<=(OTHERS => '0');  -- Bourrage
    dcache_t_w(i).a(NB_DCACHE-NB_LINE-1 DOWNTO 2)<=dcache_t_a;
    dcache_t_w(i).dw <=dcache_t_dw(i);
    dcache_t_dr(i)<=dcache_t_r(i).dr;
  END GENERATE Gen_DCacheT;

  Gen_ICacheT: FOR i IN 0 TO WAY_ICACHE-1 GENERATE
    icache_t_w(i).req<='1';
    icache_t_w(i).be <=icache_t_wr;
    icache_t_w(i).wr <=to_std_logic(icache_t_wr/="0000");
    icache_t_w(i).a(31 DOWNTO NB_ICACHE-NB_LINE)<=(OTHERS => '0');  -- Bourrage
    icache_t_w(i).a(NB_ICACHE-NB_LINE-1 DOWNTO 2)<=icache_t_a;
    icache_t_w(i).dw <=icache_t_dw(i);
    icache_t_dr(i)<=icache_t_r(i).dr;
  END GENERATE Gen_ICacheT;

  TagRAMBi:IF NB_DCACHE-NB_LINE<=10 AND NB_DCACHE=NB_ICACHE AND
              WAY_ICACHE=WAY_DCACHE GENERATE
    Gen_IDCacheT2: FOR i IN 0 TO WAY_ICACHE-1 GENERATE
      i_cache_tag: ENTITY work.iram_bi
        GENERIC MAP (
          N   => NB_DCACHE - NB_LINE,
          OCT => false)
        PORT MAP (
          mem1_w   => dcache_t_w(i),
          mem1_r   => dcache_t_r(i),
          mem2_w   => icache_t_w(i),
          mem2_r   => icache_t_r(i),
          clk      => clk);
    END GENERATE Gen_IDCacheT2;
  END GENERATE TagRAMBi;
  
  TagRAMSimple:IF NOT (NB_DCACHE-NB_LINE<=10 AND NB_DCACHE=NB_ICACHE
                       AND WAY_ICACHE=WAY_DCACHE) GENERATE
    Gen_DCacheT2: FOR i IN 0 TO WAY_DCACHE-1 GENERATE
      i_dcachetag: ENTITY work.iram
        GENERIC MAP (
          N => NB_DCACHE-NB_LINE, OCT=>false)
        PORT MAP (
          mem_w    => dcache_t_w(i),
          mem_r    => dcache_t_r(i),
          clk      => clk);
    END GENERATE Gen_DCacheT2;

    Gen_ICacheT2: FOR i IN 0 TO WAY_ICACHE-1 GENERATE
      i_icachetag: ENTITY work.iram
        GENERIC MAP (
          N => NB_ICACHE-NB_LINE, OCT=>false)
        PORT MAP (
          mem_w    => icache_t_w(i),
          mem_r    => icache_t_r(i),
          clk      => clk);
    END GENERATE Gen_ICacheT2;
  END GENERATE TagRAMSimple;
  
  --###############################################################
  -- Interface bus de Données
  
  -- Process combinatoire bus DATA
  Comb_Data:PROCESS (data_etat,reset,dreg,
                     mmu_tw_di,tw_va,tw_op,data_tw_rdy,mmu_ctxr,mmu_cr_e,mmu_cr_dce,mmu_cr_nf,
                     data_w,data2_w,filling_d2,
                     ext_dfill,fill_va,fill_ts,fill_pa,
                     dcache_t_dr,dcache_d_dr,dcache_tmux,
                     dtlb,dtlb_hitv,dtlb_hit,data_jat,dtlb_mem,ext_dr,tw_pte,
                     ext_dreq_data,tw_err,tw_done_data,inst_dr,
                     cross_ack_c,data_ext_rdy) IS
    -- MMU
    VARIABLE us_v,ls_v,ls2_v : std_logic;   -- User/Super Load/Store
    VARIABLE c_v,m_v,s_v : std_logic;       -- Cachable Modified Supervisor
    VARIABLE wb_v,al_v : std_logic;         -- Non utilisé (MULTI)
    VARIABLE ft_v : unsigned(2 DOWNTO 0);   -- Fault Type MMU
    VARIABLE pa_v : unsigned(35 DOWNTO 0);  -- Physical Address
    VARIABLE tlb_hit_v,tlb_inval_v : std_logic;     -- TLB Hit /éligible FLUSH
    VARIABLE tlb_hitv_v : std_logic;
    
    -- Cache
    VARIABLE tlb_sel_v      : type_tlb;  -- TLB sélectionné pour un inval
    VARIABLE cache_hit_v    : std_logic;
    VARIABLE cache_tag_v,cache_d_v : uv32;
    VARIABLE vcache_hit_v   : unsigned(0 TO WAY_DCACHE-1); -- Cache Hit
    VARIABLE vcache_inv_v   : unsigned(0 TO WAY_DCACHE-1); -- Cache Inval
    VARIABLE vcache_flu_v   : unsigned(0 TO WAY_DCACHE-1); -- Inutilisé
    VARIABLE tag_v          : uv32;      -- Contenu tag pendant cache fill
    VARIABLE nofill_v,nohit_v : natural RANGE 0 TO WAY_DCACHE-1;
    VARIABLE tags_v         : arr_uv32(0 TO WAY_DCACHE-1); -- Tag cache fill
    VARIABLE rmaj_v : boolean;
    VARIABLE dreq_v : std_logic;
    VARIABLE dout_v : type_push;
    VARIABLE na_v,write_v,readlru_v,write_tag_v,inval_v : std_logic;
    VARIABLE hist_v : uv8;
  BEGIN    
    -------------------------------------------------------------
    -- Recherche dans les TLBs pendant que les adresses sont positionnées (§1)
    IF NOT MMU_DIS THEN
      FOR I IN 0 TO N_DTLB-1 LOOP
        tlb_test(tlb_hit_v,tlb_inval_v,dtlb(I),data_w.a,data_w.asi(0),
                 mmu_ctxr,'1');
        dtlb_hit_c(I)<=tlb_hit_v;
        dtlb_inv_c(I)<=tlb_inval_v;
      END LOOP;
    ELSE
      dtlb_hit_c<=(OTHERS => '0');
      dtlb_inv_c<=(OTHERS => '0'); 
    END IF;
    
    -------------------------------------------------------------
    -- Calcul de l'adresse physique à partir du contenu des TLB (§2)
    ls_v:=to_std_logic(is_write(data2_w));    -- 0=Load 1=Store
    us_v:=data2_w.asi(0);                     -- 0=User 1=Super
    
    -- SWAP : Force écriture pour la MMU
    ls2_v:=ls_v OR data2_w.lock;
    
    IF MMU_DIS THEN
      tlb_hitv_v:='1';
    ELSIF data_jat='1' THEN
      -- Si on est juste après un Tablewalk, on prend directement le nouveau TLB
      tlb_hitv_v:='1';
      tlb_sel_v:=dtlb_mem;
    ELSE
      tlb_hitv_v:=dtlb_hitv;
      tlb_sel_v:=TLB_ZERO;
      FOR I IN 0 TO N_DTLB-1 LOOP
        IF dtlb_hit(I)='1' THEN
          tlb_sel_v:=tlb_or(dtlb(I),tlb_sel_v);
        END IF;
      END LOOP;
    END IF;
    
    IF data2_w.asi(7 DOWNTO 4)=x"2" THEN
      -- MMU Physical Pass-through
      ft_v:=FT_NONE;
      pa_v:=data2_w.asi(3 DOWNTO 0) & data2_w.a;
      c_v:='0';
      m_v:='0';
      s_v:='0';
    ELSIF MMU_DIS THEN
      -- MMU Supprimé, mode cache seul
      cache_trans(ft_v,pa_v,c_v,m_v,wb_v,al_v,
                  data2_w.a,ls_v,us_v,'0');
      s_v:='0';
    ELSIF mmu_cr_e='0' THEN
      -- MMU Désactivée
      ft_v:=FT_NONE;
      pa_v:=x"0" & data2_w.a;
      c_v:='0';
      m_v:='0';
      s_v:='0';
    ELSE
      -- MMU Normal
      tlb_trans(ft_v,pa_v,c_v,m_v,s_v,wb_v,al_v,
                tlb_sel_v,data2_w.a,ls2_v,us_v,'0');
    END IF;
    
    data_ft_c<=ft_v;                    -- FSR.FaultType
    data_at_c<=ls2_v & '0' & us_v;      -- FSR.AccessType
    
    -------------------------------------------------------------------------
    -- Test hit & inval cache (§2)
    cache_tag_v:=x"0000_0000";
    cache_d_v  :=x"0000_0000";
    FOR i IN 0 TO WAY_DCACHE-1 LOOP
      IF DPTAG THEN
        ptag_test(vcache_hit_v(i),vcache_inv_v(i),vcache_flu_v(i),
                  dcache_t_dr(i),pa_v,data2_w.asi,NB_DCACHE);
      ELSE
        vtag_test(vcache_hit_v(i),vcache_inv_v(i),
                  dcache_t_dr(i),data2_w.a,mmu_ctxr,data2_w.asi,
                  NB_DCACHE,NB_CONTEXT,MMU_DIS);
      END IF;
      IF vcache_hit_v(i)='1' THEN
        cache_tag_v:=cache_tag_v OR dcache_t_dr(i);
        cache_d_v  :=cache_d_v   OR dcache_d_dr(i);
      END IF;
    END LOOP;
    
    cache_hit_v:=v_or(vcache_hit_v); -- Si HIT sur une des voies
    nohit_v:=ff1(vcache_hit_v);      -- Numéro de la voie HIT
    
    dcache_blo_c<='0';
    hist_v:=x"00";
    FOR i IN 0 TO WAY_DCACHE-1 LOOP
      hist_v(i*2+1 DOWNTO i*2):=dcache_tmux(i)(3 DOWNTO 2);
    END LOOP;
    
    rmaj_v:=lru_rmaj(hist_v,nohit_v,LF_DCACHE,WAY_DCACHE);

    -- Si pas de hit, sélection de la ligne à évincer
    nofill_v:=tag_selfill(dcache_tmux,hist_v);
    
    -------------------------------------------------------------------------
    -- Paramètres de l'accès externe putatif
    data_ext_c.pw.a   <=pa_v(31 DOWNTO 0);  -- Adresse physique
    data_ext_c.pw.ah  <=pa_v(35 DOWNTO 32);
    data_ext_c.pw.asi <=mux(us_v,ASI_SUPER_DATA,ASI_USER_DATA);
    data_ext_c.pw.d   <=data2_w.d;
    data_ext_c.pw.be  <=data2_w.be;
    IF ls_v='0' THEN
      data_ext_c.pw.mode <=PB_MODE_RD;
    ELSE
      data_ext_c.pw.mode <=PB_MODE_WR;
    END IF;
    data_ext_c.pw.burst<=PB_SINGLE;
    data_ext_c.pw.cache<=c_v;
    data_ext_c.pw.lock<=data2_w.lock;
    data_ext_c.pw.cont<='0';
    data_ext_c.va<=data2_w.a;
    data_ext_c.ts<=s_v;
    data_ext_c.op<=SINGLE;
    data_ext_c.twop<=LS;
    data_ext_c.twls<=ls2_v;
    data_ext_req_c<='0';
    data_tw_req_c<='0';
    
    -------------------------------------------------------------------------
    data_etat_c<=data_etat;
    mmu_fault_data_acc_c<='0';
    data_clr_c<='0';
    dtlb_maj_c<='0';
    dtlb_sel_c<='0';
    dtlb_twm_c<='0';
    dtlb_inval_c<='0';
    
    write_v:='0';
    readlru_v:='0';
    write_tag_v:='0';
    inval_v:='0';
    na_v:='0';
    dreq_v:='0';
    
    data_txt<="         ";
    dout_v.d:=cache_d_v;
    dout_v.code:=PB_OK;
    dout_v.cx:='0';
    
    -------------------------------------------------------------------------
    mmu_cr_maj<='0';
    mmu_ctxtpr_maj<='0';
    mmu_ctxr_maj<='0';
    mmu_fsr_maj<='0';
    mmu_tmpr_maj<='0';
    cross_req_c<='0';
    
    -------------------------------------------------------------------------
    CASE data_etat IS
      WHEN sOISIF =>
        IF data2_w.req='0' OR reset='1' THEN
          -- Rien à faire
          na_v:='1';
        ELSIF filling_d2='1' THEN
          NULL;
        ELSE
          dcache_blo_c<='1';
          -- Accès en cours
          CASE data2_w.asi IS
              --------------------------
            WHEN ASI_MMU_FLUSH_PROBE =>
              IF MMU_DIS THEN
                dreq_v:='1';
                na_v:='1';
                dout_v.code:=PB_OK;
              ELSE
                IF BSD_MODE THEN
                  data_etat_c<=sCROSS;
                  dtlb_inval_c<='1';
                ELSE
                  -- Ecriture :INVAL : Purge un ou plusieurs TLB data et/ou code
                  -- Lecture PROBE : Lit un TLB data, ou déclenche un Tablewalk.
                  data_ext_c.twop<=PROBE;
                  IF ls_v='1' THEN
                    -- FLUSH TLB, Instruction et Data
                    data_etat_c<=sCROSS;
                    dtlb_inval_c<='1';
                  ELSE
                    -- PROBE avec TLB Miss, il faut faire un TableWalk
                    data_tw_req_c<='1';
                    IF data_tw_rdy='1' THEN
                      na_v:='1';
                      data_etat_c<=sTABLEWALK;
                    END IF;
                  END IF;
                END IF;
              END IF;
              
              --------------------------
            WHEN ASI_MMU_REGISTER =>
              -- Accès aux registres MMU
              data_etat_c<=sREGISTRE;
              
              --------------------------
            WHEN ASI_MMU_DIAGNOSTIC_FOR_INSTRUCTION_TLB |
                 ASI_MMU_DIAGNOSTIC_FOR_DATA_TLB |
                 ASI_MMU_DIAGNOSTIC_IO_TLB =>
              -- Diagnostic, on s'en fout.
              dreq_v:='1';
              na_v:='1';
              dout_v.code:=PB_OK;
              
              --------------------------
            WHEN ASI_USER_INSTRUCTION |
                 ASI_SUPER_INSTRUCTION |
                 ASI_USER_DATA |
                 ASI_SUPER_DATA =>
              dtlb_sel_c<='1';
              IF ASIINST AND data2_w.asi(1)='0' THEN
                -- User/Super Instruction
                data_etat_c<=sCROSS;
              ELSE
                -- User/Super Data
                --#####################################################
                  --Gestion MMU
                IF mmu_cr_e='1' AND tlb_hitv_v='0' THEN
                  -- Tablewalk nécessaire. Après, tlb_hitv_v=1
                  data_ext_c.twop<=LS;
                  data_tw_req_c<='1';
                  IF data_tw_rdy='1' THEN
                    data_etat_c<=sTABLEWALK;
                  END IF;
                  data_txt<="TABLEWALK";
                  
                  ---------------------------------
                ELSIF mmu_cr_e='1' AND tlb_hitv_v='1' AND ft_v=FT_NONE AND
                  m_v='0' AND ls2_v='1' THEN
                  -- Tablewalk pour positionner le bit M avant une écriture
                  dtlb_twm_c<='1';
                  data_ext_c.twop<=LS;
                  data_tw_req_c<='1';
                  IF data_tw_rdy='1' THEN
                    data_etat_c<=sTABLEWALK;
                  END IF;
                  data_txt<="TABLE_MOD";
                  
                  ---------------------------------
                ELSIF (mmu_cr_e='1' OR MMU_DIS) AND
                  tlb_hitv_v='1' AND ft_v/=FT_NONE THEN
                  -- Erreur d'accès : Violation de privilège ou de protection
                  mmu_fault_data_acc_c<='1';
                  dreq_v:='1';
                  na_v:='1';
                  IF mmu_cr_nf='0' THEN
                    dout_v.code:=PB_FAULT;
                  ELSE
                    dout_v.code:=PB_OK;
                  END IF;
                  data_txt<="MMU_ERROR";
                  
                --#####################################################
                --Lectures
                ELSIF ls_v='0' AND ((mmu_cr_e='0' AND NOT MMU_DIS) OR
                     (tlb_hitv_v='1' AND ft_v=FT_NONE AND mmu_cr_dce='0') OR
                     (tlb_hitv_v='1' AND ft_v=FT_NONE AND mmu_cr_dce='1' AND
                      c_v='0')) THEN
                  -- Lecture externe : Pas de cache, pas de MMU ou non cacheable
                  data_ext_req_c<='1';
                  data_ext_c.op<=SINGLE;
                  IF data_ext_rdy='1' THEN
                    data_etat_c<=sEXT_READ;
                    na_v:='1';
                  END IF;
                  data_txt<="LECTU_EXT";
                  
                  ---------------------------------
                ELSIF (mmu_cr_e='1' OR MMU_DIS) AND tlb_hitv_v='1' AND
                  ft_v=FT_NONE AND c_v='1' AND
                  mmu_cr_dce='1' AND cache_hit_v='1' AND ls_v='0' THEN
                  -- Lecture en cache. Simplement.
                  dout_v.d:=cache_d_v;
                  dout_v.code:=PB_OK;
                  dreq_v:='1';
                  data_etat_c<=sOISIF;
                  na_v:=to_std_logic(WAY_DCACHE=1 OR NOT rmaj_v);
                  readlru_v:=NOT na_v;
                  data_clr_c<=NOT na_v;
                  data_txt<="CACHE_LEC";
                  
                  ---------------------------------
                ELSIF (mmu_cr_e='1' OR MMU_DIS) AND tlb_hitv_v='1' AND
                  ft_v=FT_NONE AND c_v='1' AND
                  mmu_cr_dce='1' AND cache_hit_v='0' AND ls_v='0' THEN
                  -- Cache fill pour une lecture
                  data_ext_req_c<='1';
                  data_ext_c.op<=FILL;
                  IF data_ext_rdy='1' THEN
                    data_etat_c<=sEXT_READ;
                    na_v:='1';
                  END IF;
                  data_txt<="FILL READ";
                  
                --#####################################################
                --Ecritures
                ELSIF ls_v='1' AND ((mmu_cr_e='0' AND NOT MMU_DIS) OR
                        (tlb_hitv_v='1' AND ft_v=FT_NONE
                         AND m_v='1' AND mmu_cr_dce='0') OR
                        (tlb_hitv_v='1' AND ft_v=FT_NONE AND m_v='1'
                         AND c_v='0' AND mmu_cr_dce='1') OR
                        (tlb_hitv_v='1' AND ft_v=FT_NONE AND m_v='1' AND
                         c_v='1' AND mmu_cr_dce='1' AND cache_hit_v='0')) THEN
                  -- Ecriture externe : Pas de cache, pas de MMU, non cacheable
                  -- ou pas dans le cache.
                  IF NOT MMU_DIS AND NOT DPTAG THEN
                    -- Purge ligne de cache, protection aliasing!
                    inval_v:='1';
                  END IF;
                  data_ext_req_c<='1';
                  data_ext_c.op<=SINGLE;
                  IF data_ext_rdy='1' THEN -- Ecriture postée
                    dout_v.code:=PB_OK;
                    dreq_v:='1';
                    data_clr_c<='1';
                  END IF;
                  data_txt<="ECRIT_EXT";
                  
                  ---------------------------------
                ELSIF (mmu_cr_e='1' OR MMU_DIS) AND tlb_hitv_v='1' AND
                  ft_v=FT_NONE AND
                  m_v='1' AND c_v='1' AND mmu_cr_dce='1' AND cache_hit_v='1' AND
                  ls_v='1' THEN
                  -- Ecriture en cache et écriture externe (Write Through)
                  write_v:='1';
                  dout_v.code:=PB_OK;
                  -- <Il ne faut écrire que pendant 1 cycle ?>
                  -- Si écriture, on empêche l'acquittement data_r_c.ack du
                  -- second accès pendant le cycle zéro !
                  data_ext_req_c<='1';
                  data_ext_c.op<=SINGLE;
                  IF data_ext_rdy='1' THEN -- Ecriture postée !
                    dreq_v:='1';
                    data_clr_c<='1';
                  END IF;
                  data_txt<="WRITE_TRU";
                  
                  ---------------------------------
                ELSE
                  -- Jamais. Impossible en vrai.
                  
                END IF;
              END IF;
              
              --------------------------
            WHEN ASI_CACHE_TAG_INSTRUCTION =>
              -- RW cache TAG entry in split Instruction cache
              data_etat_c<=sCROSS;
              
              --------------------------
            WHEN ASI_CACHE_DATA_INSTRUCTION =>
              -- RW cache DATA entry in split Instruction cache 
              dreq_v:='1';
              na_v:='1';
              dout_v.code:=PB_OK;
              
              --------------------------
            WHEN ASI_CACHE_TAG_DATA =>
              -- RW cache TAG entry in split Data or Combined cache
              IF ASICACHE THEN
                dout_v.d:=dcache_t_dr(0);
                -- <AFAIRE> Sélection voie selon adresse...
                dout_v.code:=PB_OK;
                dreq_v:='1';
                IF ls_v='1' THEN
                  -- Ecriture TAG
                  write_tag_v:='1';
                  data_clr_c<='1';
                  data_txt<="DTAG_ECRI";
                ELSE
                  -- Lecture TAG
                  na_v:='1';
                  data_txt<="DTAG_LECT";                
                END IF;
              ELSE
                dreq_v:='1';
                na_v:='1';
                dout_v.code:=PB_OK;
              END IF;
              
              --------------------------
            WHEN ASI_CACHE_DATA_DATA =>
              -- RW cache DATA entry in split Data or Combined cache
              dreq_v:='1';
              na_v:='1';
              dout_v.code:=PB_OK;
              
              --------------------------
            WHEN ASI_CACHE_FLUSH_LINE_COMBINED_PAGE |
                 ASI_CACHE_FLUSH_LINE_COMBINED_SEGMENT |
                 ASI_CACHE_FLUSH_LINE_COMBINED_REGION |
                 ASI_CACHE_FLUSH_LINE_COMBINED_CONTEXT |
                 ASI_CACHE_FLUSH_LINE_COMBINED_USER |
                 ASI_CACHE_FLUSH_LINE_COMBINED_ANY =>
              -- FLUSH des caches I et D,
              -- Les FLUSH ne purgent qu'une ligne à la fois !!!
              IF ls_v='1' THEN
                inval_v:='1'; --cache_inval_v; -- <PROVISOIRE>
                data_etat_c<=sCROSS;
              ELSE
                dreq_v:='1';
                na_v:='1';
                dout_v.code:=PB_OK;
              END IF;
              
              --------------------------
            WHEN ASI_CACHE_FLUSH_LINE_INSTRUCTION_PAGE |
                 ASI_CACHE_FLUSH_LINE_INSTRUCTION_SEGMENT |
                 ASI_CACHE_FLUSH_LINE_INSTRUCTION_REGION |
                 ASI_CACHE_FLUSH_LINE_INSTRUCTION_CONTEXT |
                 ASI_CACHE_FLUSH_LINE_INSTRUCTION_USER |
                 ASI_CACHE_FLUSH_LINE_INSTRUCTION_ANY =>
              -- FLUSH du cache I uniquement.
              -- Les FLUSH ne purgent qu'une ligne à la fois !!!
              IF ls_v='1' THEN
                data_etat_c<=sCROSS;
              ELSE
                dreq_v:='1';
                na_v:='1';
                dout_v.code:=PB_OK;
              END IF;

              --------------------------
            WHEN ASI_BLOCK_COPY =>
              -- <AVOIR> Utile ?
              dreq_v:='1';
              na_v:='1';
              dout_v.code:=PB_OK;
              
              --------------------------
            WHEN ASI_BLOCK_FILL =>
              -- <AVOIR> Utile ?
              dreq_v:='1';
              na_v:='1';
              dout_v.code:=PB_OK;
              
              --------------------------
            WHEN ASI_MMU_PHYSICAL_PASS_THROUGH_20 |
                 ASI_MMU_PHYSICAL_PASS_THROUGH_21 |
                 ASI_MMU_PHYSICAL_PASS_THROUGH_22 |
                 ASI_MMU_PHYSICAL_PASS_THROUGH_23 |
                 ASI_MMU_PHYSICAL_PASS_THROUGH_24 |
                 ASI_MMU_PHYSICAL_PASS_THROUGH_25 |
                 ASI_MMU_PHYSICAL_PASS_THROUGH_26 |
                 ASI_MMU_PHYSICAL_PASS_THROUGH_27 |
                 ASI_MMU_PHYSICAL_PASS_THROUGH_28 |
                 ASI_MMU_PHYSICAL_PASS_THROUGH_29 |
                 ASI_MMU_PHYSICAL_PASS_THROUGH_2A |
                 ASI_MMU_PHYSICAL_PASS_THROUGH_2B |
                 ASI_MMU_PHYSICAL_PASS_THROUGH_2C |
                 ASI_MMU_PHYSICAL_PASS_THROUGH_2D |
                 ASI_MMU_PHYSICAL_PASS_THROUGH_2E |
                 ASI_MMU_PHYSICAL_PASS_THROUGH_2F =>
              -- Accès direct adresses physiques. Accès externe non caché
              data_ext_req_c<='1';
              data_ext_c.op<=SINGLE;
              IF ls_v='0' THEN
                -- Lecture
                IF data_ext_rdy='1' THEN
                  data_etat_c<=sEXT_READ;
                  na_v:='1';
                END IF;
              ELSE
                -- Ecriture postée
                IF data_ext_rdy='1' THEN
                  dout_v.code:=PB_OK;
                  na_v:='1';
                  dreq_v:='1';
                END IF;
              END IF;
              
              --------------------------
            WHEN OTHERS =>
              dreq_v:='1';
              na_v:='1';
              dout_v.code:=PB_OK;
              
          END CASE;
        END IF;
        
        ----------------------------------------------------
      WHEN sREGISTRE =>
        -- Accès aux registres de la MMU
        --     0x000000xx : Control Register
        --     0x000001xx : Context Table Pointer Register
        --     0x000002xx : Context Register
        --     0x000003xx : Fault Status Register
        --     0x000004xx : Fault Address Register
        IF data2_w.a(11 DOWNTO 8)=x"0" THEN
          -- MMU Control Register
          mmu_cr_maj<=ls_v;
        ELSIF data2_w.a(11 DOWNTO 8)=x"1" AND NOT MMU_DIS THEN
          -- Context Table Pointer Register
          mmu_ctxtpr_maj<=ls_v;
        ELSIF data2_w.a(11 DOWNTO 8)=x"2" AND NOT MMU_DIS THEN
          -- Context Register
          mmu_ctxr_maj<=ls_v;
        ELSIF data2_w.a(11 DOWNTO 8)=x"3" AND NOT MMU_DIS THEN
          -- Fault Status Register
          mmu_fsr_maj<='1';
        ELSIF data2_w.a(11 DOWNTO 8)=x"C" AND NOT MMU_DIS THEN
          -- Tmpr Register
          mmu_tmpr_maj<=ls_v;
        END IF;
        dout_v.d:=dreg;
        dout_v.code:=PB_OK;
        na_v:='1';
        dreq_v:='1';
        data_etat_c<=sOISIF;
                
        ----------------------------------------------------
      WHEN sCROSS =>
        -- Communication croisée DATA --> INST :
        --   - Lectures/Ecritures ASI USER_CODE & SUPER_CODE depuis bus data
        --   - Ecriture ASI MMU flush code
        --   - Ecriture ASI Cache flush
        cross_req_c<='1';
        IF cross_ack_c='1' THEN
          data_etat_c<=sCROSS_DATA;
          na_v:='1';
        END IF;

      WHEN sCROSS_DATA =>
        dout_v.d:=inst_dr.d;
        dout_v.code:=inst_dr.code;
        dreq_v:='1';
        data_etat_c<=sOISIF;
        
        ----------------------------------------------------
      WHEN sTABLEWALK =>
        -- Accès vers le contrôleur externe qui va faire le TableWalk
        IF (tw_op/=PROBE OR tw_va(10 DOWNTO 8)=PT_ENTIRE) AND
          tw_done_data='1' AND tw_err='0' THEN
          -- On modifie le TLB si c'est un accès normal ou un 'entire probe'
          dtlb_maj_c<='1';
        END IF;
        dout_v.d:=tw_pte;
        dout_v.code:=PB_OK;
        
        IF tw_done_data='1' THEN
          data_etat_c<=sOISIF;
          IF tw_op=PROBE THEN
            -- Si c'est un probe, on renvoie sur le bus de données le PTE/PTD
            dreq_v:='1';
          ELSIF tw_err='1' THEN -- MMU_ERROR
            na_v:='1';
            dreq_v:='1';
            IF mmu_cr_nf='0' THEN
              dout_v.code:=PB_FAULT;
            ELSE
              dout_v.code:=PB_OK;
            END IF;
          END IF;
        END IF;
        
        ----------------------------------------------------
      WHEN sEXT_READ =>
        -- Attente de données à relire depuis le bus externe
        dout_v.d:=ext_dr;
        dout_v.code:=PB_OK;
        IF ext_dreq_data='1' THEN
          dreq_v:='1';
          data_etat_c<=sOISIF;
        END IF;
    END CASE;

    -------------------------------------------------------------
    -- On pousse l'accès vers le proc
    data_r_c.d   <=dout_v.d;
    data_r_c.code<=dout_v.code;
    data_r_c.dreq<=dreq_v;
    data_r_c.ack<=na_v;
    
    data_na_c<=na_v;
    
    -------------------------------------------------------------
    -- Contrôle bus cache, adresses & données à écrire
    -- Par défaut on fait une lecture en même temps que l'accès TAG.
    -- Si écriture ou inval, il faut faire l'écriture 1 cycle après
    IF DPTAG THEN
      tag_v:=ptag_encode(fill_pa,ext_dfill,'0','0',"00",NB_DCACHE);
    ELSE
      tag_v:=vtag_encode(fill_va,mmu_ctxr,ext_dfill,fill_ts,"00",
                  NB_DCACHE,NB_CONTEXT);
    END IF;
    
    tag_maj(tags_v,
            tag_v,dcache_tmux,hist_v,readlru_v,write_v,'0',
            '0','1',inval_v,nohit_v,nofill_v,0);
    
    dcache_d_wr<=(OTHERS => "0000");
    IF ext_dfill='1' THEN
      -- Cache fill (On écrit plusieurs fois le tag sur place)
      dcache_d_a <=fill_va(NB_DCACHE-1 DOWNTO 2);
      dcache_d_dw<=ext_dr;
      dcache_d_wr(nofill_v)<="1111";
      dcache_t_a <=fill_va(NB_DCACHE-1 DOWNTO 2+NB_LINE);
      dcache_t_dw<=tags_v;
      dcache_t_wr<="1111";
      
    ELSIF inval_v='1' THEN
      -- Second cycle, invalidation cache. On modifie les tags, pas les données
      dcache_d_a <=data2_w.a(NB_DCACHE-1 DOWNTO 2);
      dcache_d_dw<=data2_w.d;
      dcache_t_a <=data2_w.a(NB_DCACHE-1 DOWNTO 2+NB_LINE);
      dcache_t_dw<=tags_v;
      dcache_t_wr<="1111";
      
    ELSIF write_v='1' OR readlru_v='1' THEN
      -- Second cycle. écriture simple. On modifie les données pas les tags
      dcache_d_a <=data2_w.a(NB_DCACHE-1 DOWNTO 2);
      dcache_d_dw<=data2_w.d;
      IF write_v='1' THEN
        dcache_d_wr(nohit_v)<=data2_w.be;
      END IF;
      dcache_t_a <=data2_w.a(NB_DCACHE-1 DOWNTO 2+NB_LINE);
      dcache_t_dw<=tags_v;
      IF WAY_DCACHE/=1 THEN
        dcache_t_wr<="1111";
      ELSE
        dcache_t_wr<="0000";
      END IF;
      
    ELSIF write_tag_v='1' THEN -- ASI spécial màj tags
      -- Second cycle. écriture tags. On modifie les tags, pas les données
      dcache_d_a <=data2_w.a(NB_DCACHE-1 DOWNTO 2);
      dcache_d_dw<=data2_w.d;
      dcache_t_a <=data2_w.a(NB_DCACHE-1 DOWNTO 2+NB_LINE);
      dcache_t_dw<=(OTHERS => data2_w.d);
      dcache_t_wr<="1111";

    ELSIF na_v='0' THEN
      -- L'adresse est déjà au niveau 2      
      dcache_d_a <=data2_w.a(NB_DCACHE-1 DOWNTO 2);
      dcache_d_dw<=data2_w.d;
      dcache_t_a <=data2_w.a(NB_DCACHE-1 DOWNTO 2+NB_LINE);
      dcache_t_dw<=tags_v;
      dcache_t_wr<="0000";
      
    ELSE
      -- Lecture data & tag
      dcache_d_a <=data_w.a(NB_DCACHE-1 DOWNTO 2);
      dcache_d_dw<=data2_w.d;
      dcache_t_a <=data_w.a(NB_DCACHE-1 DOWNTO 2+NB_LINE);
      dcache_t_dw<=tags_v;
      dcache_t_wr<="0000";
      
    END IF;
    
  END PROCESS Comb_Data;

  data_r<=data_r_c;
  
  -------------------------------------------------------------------------
  -- Process synchrone bus DATA
  Sync_Data:PROCESS (clk)
    VARIABLE tlb_trouve : std_logic;
    VARIABLE no : natural RANGE 0 TO N_DTLB-1;
    VARIABLE hist_maj_v : std_logic;
  BEGIN
    IF rising_edge(clk) THEN
      
      -------------------------------------------
      -- Gestion des TLBs
      hist_maj_v:='0';
      
      -- MàJ d'un TLB avec le contenu de tlb_mod_c.
      IF dtlb_maj_c='1' AND NOT MMU_DIS THEN
        dtlb_mem<=tlb_mod_c;
        data_jat<='1';
        IF dtlb_twm='1' THEN
          -- Cas particulier : Modification du bit M, le TLB est déjà chargé
          FOR I IN 0 TO N_DTLB-1 LOOP
            IF dtlb_hitm(I)='1' THEN
              dtlb(I)<=tlb_mod_c;
            END IF;
          END LOOP;
        ELSE          
          tlb_trouve:='0';
          FOR I IN 0 TO N_DTLB-1 LOOP
            no:=I;
            IF dtlb(I).v='0' THEN
              tlb_trouve:='1';
              dtlb(I)<=tlb_mod_c;
              hist_maj_v:='1';
            END IF;
          END LOOP;
          IF tlb_trouve='0' THEN
            IF DTLB_MODE=CPT THEN
              -- Mode compteur
              dtlb(dtlb_cpt)<=tlb_mod_c;
              IF dtlb_cpt/=N_DTLB-1 THEN
                dtlb_cpt<=dtlb_cpt+1;
              ELSE
                dtlb_cpt<=0;
              END IF;
            ELSE
              -- Mode LRU
              no:=lru_old(dtlb_hist,N_DTLB);
              dtlb(no)<=tlb_mod_c;
              hist_maj_v:='1';
            END IF;
          END IF;
        END IF;        
      END IF;
      IF dtlb_sel_c='1' THEN
        FOR I IN 0 TO N_DTLB-1 LOOP
          IF dtlb_hit(I)='1' THEN
            no:=I;
          END IF;
        END LOOP;
        hist_maj_v:='1';
      END IF;
      
      IF data_na_c='1' THEN
        data_jat<='0';
      END IF;

      IF hist_maj_v='1' AND DTLB_MODE=LRU THEN
        dtlb_hist<=lru_maj(dtlb_hist,no,N_DTLB);
      END IF;
      
      -- Flush de TLB
      FOR I IN 0 TO N_DTLB-1 LOOP
        IF dtlb_inv(I)='1' AND dtlb_inval_c='1' THEN
          dtlb(I).v<='0';
        END IF;
      END LOOP;
      
      -------------------------------------------
      -- Pipeline accès DATA
      IF data_na_c='1' THEN
        -- Si pas de bloquage, au suivant
        data2_w<=data_w;
        data2_w.asi(7 DOWNTO 6)<="00";  -- ASI sur 6 bits...
      END IF;
      IF data_clr_c='1' THEN
        data2_w.req<='0';
      END IF;

      IF data_na_c='1' THEN
        dtlb_hit  <=dtlb_hit_c;
        dtlb_inv<=dtlb_inv_c;
        dtlb_hitv <=v_or(dtlb_hit_c);
      END IF;

      IF dtlb_twm_c='1' THEN
        dtlb_hitm<=dtlb_hit;
        dtlb_twm<='1';
      ELSIF tw_done_data='1' THEN
        dtlb_twm<='0';
      END IF;
      
      filling_d2<=filling_d;
      IF dcache_blo_c='1' THEN
        dcache_t_mem<=dcache_t_dr;
      END IF;
      
      -------------------------------------------
      -- Registres
      IF data_w.a(11 DOWNTO 8)=x"0" THEN
        -- MMU Control Register
        dreg<=MMU_IMP_VERSION & x"00" &
              '0' & mmu_cr_bm & "0000" &
              mmu_cr_ice & mmu_cr_dce &
              "0" & mmu_cr_l2tlb & "0000" & mmu_cr_nf & mmu_cr_e;
        
      ELSIF data_w.a(11 DOWNTO 8)=x"1" AND NOT MMU_DIS THEN
        -- Context Table Pointer Register
        dreg<=mmu_ctxtpr(35 DOWNTO 6) & "00";
        
      ELSIF data_w.a(11 DOWNTO 8)=x"2" AND NOT MMU_DIS THEN
        -- Context Register
        dreg(31 DOWNTO NB_CONTEXT)<=(OTHERS => '0');
        dreg(NB_CONTEXT-1 DOWNTO 0)<=mmu_ctxr;
        
      ELSIF data_w.a(11 DOWNTO 8)=x"3" AND NOT MMU_DIS THEN
        -- Fault Status Register
        dreg<="00000000000000" & MMU_FSR_EBE & mmu_fsr_l &
                   mmu_fsr_at & mmu_fsr_ft & mmu_fsr_fav & mmu_fsr_ow;
        
      ELSIF data_w.a(11 DOWNTO 8)=x"B" AND NOT MMU_DIS THEN
        -- Fault Status Register, no update
        dreg<="00000000000000" & MMU_FSR_EBE & mmu_fsr_l &
                   mmu_fsr_at & mmu_fsr_ft & mmu_fsr_fav & mmu_fsr_ow;
        
      ELSIF data_w.a(11 DOWNTO 8)=x"C" AND NOT MMU_DIS THEN
        -- Tmpr Register
        dreg<=mmu_tmpr;

      ELSIF data_w.a(11 DOWNTO 8)=x"D" AND NOT MMU_DIS THEN
        -- SysConf constant
        dreg<=SYSCONF;
        
      ELSIF data_w.a(11 DOWNTO 8)=x"4" AND NOT MMU_DIS THEN
        -- Fault Address Register
        dreg<=mmu_far & "00";
      ELSE
        dreg<=MMU_IMP_VERSION & x"00" &
              '0' & mmu_cr_bm & "0000" &
              mmu_cr_ice & mmu_cr_dce &
              "0" & mmu_cr_l2tlb & "0000" & mmu_cr_nf & mmu_cr_e;
      END IF;
      IF data_na_c='0' THEN
        dreg<=dreg;
      END IF;
      
      -------------------------------------------
      -- Machine à états
      data_etat<=data_etat_c;
      
      -------------------------------------------
      IF reset_n='0' THEN
        dtlb_cpt<=0;
        data_etat<=sOISIF;
        data2_w.req<='0';
        FOR I IN 0 TO N_DTLB-1 LOOP
          dtlb(I).v<='0';
        END LOOP;
        data_jat<='0';
        dtlb_twm<='0';
        dtlb_hist<=x"00";
      END IF;
    END IF;
  END PROCESS Sync_Data;

  dcache_tmux<=dcache_t_dr WHEN dcache_blo_c='1' ELSE dcache_t_mem;
  
  --###############################################################
  -- Interface bus d' Instructions

  -- Types d'accès :
  --   - Exécution code USER / SUPER
  --   - Bypass lecture et écriture code USER / SUPER
  --   - Bypass inval ICACHE (plus tard, aussi le probe contenu & tags)
  --   - Bypass flush ITLB
  
  Comb_Inst:PROCESS(inst_etat,reset,inst_tw_rdy,mmu_ctxr,mmu_cr_bm,
                    mmu_cr_e,mmu_cr_ice,mmu_cr_nf,
                    inst_w,imux_w,imux2_w,data2_w,filling_i2,
                    ext_ifill,fill_va,fill_ts,fill_pa,
                    icache_t_dr,icache_d_dr,icache_tmux,
                    itlb,itlb_hitv,itlb_hit,inst_cont,
                    inst_jat,itlb_mem,imux2_cx,imux3_cx,
                    inst_ext_rdy,tw_pte,ext_dr,ext_dreq_inst,
                    tw_err,tw_done_inst,cross_req_c,cross) IS
    -- MMU
    VARIABLE us_v,ls_v : std_logic;         -- User/Super Load/Store
    VARIABLE c_v,m_v,s_v : std_logic;       -- Cachable Modified Super
    VARIABLE wb_v,al_v : std_logic;         -- Non utilisé
    VARIABLE ft_v : unsigned(2 DOWNTO 0);   -- Fault Type MMU
    VARIABLE pa_v : unsigned(35 DOWNTO 0);  -- Physical Address
    VARIABLE tlb_hit_v,tlb_inval_v : std_logic;     -- TLB Hit /éligible INVAL
    VARIABLE tlb_hitv_v : std_logic;
    
    -- Cache
    VARIABLE tlb_sel_v     : type_tlb;  -- TLB sélectionné pour un inval
    VARIABLE cache_hit_v   : std_logic;
    VARIABLE cache_tag_v,cache_d_v : uv32;
    VARIABLE vcache_hit_v   : unsigned(0 TO WAY_ICACHE-1); -- Cache HIT
    VARIABLE vcache_inv_v   : unsigned(0 TO WAY_ICACHE-1); -- Cache Inval
    VARIABLE vcache_flu_v   : unsigned(0 TO WAY_ICACHE-1); -- Inutilisé
    VARIABLE tag_v          : uv32;      -- Contenu tag pendant cache fill
    VARIABLE nofill_v,nohit_v : natural RANGE 0 TO WAY_DCACHE-1;
    VARIABLE tags_v         : arr_uv32(0 TO WAY_ICACHE-1); -- Tag cache fill
    VARIABLE cross_v : std_logic;    
    VARIABLE rmaj_v : boolean;
    VARIABLE ireq_v : std_logic;
    VARIABLE iout_v : type_push;
    VARIABLE na_v,write_v,readlru_v,write_tag_v,inval_v : std_logic;
    VARIABLE hist_v : uv8;
    
  BEGIN
    -------------------------------------------------------------
    -- Recherche dans les TLBs pendant que les adresses sont positionnées
    IF NOT MMU_DIS THEN
      FOR I IN 0 TO N_ITLB-1 LOOP
        tlb_test(tlb_hit_v,tlb_inval_v,itlb(I),imux_w.a,imux_w.asi(0),
                 mmu_ctxr,'1');
        itlb_hit_c(I)<=tlb_hit_v;
        itlb_inv_c(I)<=tlb_inval_v;
      END LOOP;
    ELSE
      itlb_hit_c<=(OTHERS => '0');
      itlb_inv_c<=(OTHERS => '0'); 
    END IF;
    
    -------------------------------------------------------------
    -- Calcul de l'adresse physique à partir du contenu des TLB
    ls_v:=to_std_logic(is_write(imux2_w));    -- 0=Load/Execute 1=Store
    us_v:=imux2_w.asi(0);                     -- 0=User 1=Super

    IF MMU_DIS THEN
      tlb_hitv_v:='1';
    ELSIF inst_jat='1' THEN
      -- Si on est juste après un Tablewalk, on prend directement le nouveau TLB
      tlb_hitv_v:='1';
      tlb_sel_v:=itlb_mem;
    ELSE
      tlb_hitv_v:=itlb_hitv;
      tlb_sel_v:=TLB_ZERO;
      FOR I IN 0 TO N_ITLB-1 LOOP
        IF itlb_hit(I)='1' THEN
          tlb_sel_v:=tlb_or(itlb(I),tlb_sel_v);
        END IF;
      END LOOP;
    END IF;
    
    IF mmu_cr_bm='1' AND BOOTMODE THEN
      -- Boot Mode (ne concerne que le code)
      ft_v:=FT_NONE;
      pa_v:=x"FF" & imux2_w.a(27 DOWNTO 0);
      c_v:='0';
      m_v:='0';
      s_v:='0';
    ELSIF MMU_DIS THEN
      -- MMU Supprimé, mode cache seul
      cache_trans(ft_v,pa_v,c_v,m_v,wb_v,al_v,
                  imux2_w.a,ls_v,us_v,'1');
    ELSIF mmu_cr_e='0' THEN
      -- MMU Désactivée
      ft_v:=FT_NONE;
      pa_v:=x"0" & imux2_w.a;
      c_v:='0';
      m_v:='0';
      s_v:='0';
    ELSE
      -- MMU Normal
      tlb_trans(ft_v,pa_v,c_v,m_v,s_v,wb_v,al_v,
                tlb_sel_v,imux2_w.a,ls_v,us_v,'1');
    END IF;
    
    inst_ft_c<=ft_v;                    -- FSR.FaultType
    inst_at_c<=ls_v & '1' & us_v;       -- FSR.AccessType

    -------------------------------------------------------------------------
    -- Test hit & inval cache (§2)
    cache_tag_v:=x"0000_0000";
    cache_d_v  :=x"0000_0000";
    FOR i IN 0 TO WAY_ICACHE-1 LOOP
      IF IPTAG THEN
        ptag_test(vcache_hit_v(i),vcache_inv_v(i),vcache_flu_v(i),
                  icache_t_dr(i),pa_v,imux2_w.asi,NB_ICACHE);
      ELSE
        vtag_test(vcache_hit_v(i),vcache_inv_v(i),
                  icache_t_dr(i),imux2_w.a,mmu_ctxr,imux2_w.asi,
                  NB_ICACHE,NB_CONTEXT,MMU_DIS);
      END IF;
      IF vcache_hit_v(i)='1' THEN
        cache_tag_v:=cache_tag_v OR icache_t_dr(i);
        cache_d_v  :=cache_d_v   OR icache_d_dr(i);
      END IF;
    END LOOP;
    
    cache_hit_v:=v_or(vcache_hit_v); -- Si HIT sur une des voies
    nohit_v:=ff1(vcache_hit_v);      -- Numéro de la voie HIT
    icache_blo_c<='0';
    hist_v:=x"00";
    FOR i IN 0 TO WAY_ICACHE-1 LOOP
      hist_v(i*2+1 DOWNTO i*2):=icache_tmux(i)(3 DOWNTO 2);
    END LOOP;
    
    rmaj_v:=lru_rmaj(hist_v,nohit_v,LF_ICACHE,WAY_ICACHE);
    
    -- Si pas de hit, sélection de la ligne à évincer
    nofill_v:=tag_selfill(icache_tmux,hist_v);
    
    -------------------------------------------------------------------------
    -- Paramètres de l'accès externe putatif
    inst_ext_c.pw.a   <=pa_v(31 DOWNTO 0);  -- Adresse physique
    inst_ext_c.pw.ah  <=pa_v(35 DOWNTO 32);
    inst_ext_c.pw.asi <=mux(us_v,ASI_SUPER_INSTRUCTION,ASI_USER_INSTRUCTION);
    inst_ext_c.pw.d   <=imux2_w.d;
    inst_ext_c.pw.be  <=imux2_w.be;
    IF ls_v='0' THEN
      inst_ext_c.pw.mode <=PB_MODE_RD;
    ELSE
      inst_ext_c.pw.mode <=PB_MODE_WR;
    END IF;
    inst_ext_c.pw.burst<=PB_SINGLE;
    inst_ext_c.pw.cache<=c_v;
    inst_ext_c.pw.lock<='0';
    inst_ext_c.pw.cont<='0';
    inst_ext_c.va<=imux2_w.a;
    inst_ext_c.ts<=s_v;
    inst_ext_c.op<=SINGLE;
    inst_ext_c.twop<=LS;
    inst_ext_c.twls<=ls_v;
    inst_ext_req_c<='0';
    inst_tw_req_c<='0';
    
    -------------------------------------------------------------------------
    inst_etat_c<=inst_etat;
    mmu_fault_inst_acc_c<='0';
    inst_clr_c<='0';
    itlb_maj_c<='0';
    itlb_sel_c<='0';
    itlb_twm_c<='0';
    itlb_inval_c<='0';
    
    write_v:='0';
    readlru_v:='0';
    write_tag_v:='0';
    inval_v:='0';
    na_v:='0';
    ireq_v:='0';
    
    inst_txt<="         ";
    iout_v.d:=cache_d_v;
    iout_v.code:=PB_OK;
    iout_v.cx:=imux2_cx;
    
    -------------------------------------------------------------------------
    CASE inst_etat IS
      WHEN sOISIF =>
        IF imux2_w.req='0' OR reset='1' THEN
          -- Rien à faire
          na_v:='1';
        ELSIF filling_i2='1' THEN
          IF inst_cont='1' AND imux2_w.cont='1' AND ext_ifill='1' THEN
            iout_v.d:=ext_dr;
            iout_v.code:=PB_OK;
            iout_v.cx:=imux2_cx;        -- IMUX2 ???
            ireq_v:='1';
            na_v:='1';
          END IF;
        ELSE
          icache_blo_c<='1';
          -- Accès en cours
          CASE imux2_w.asi IS
              --------------------------
            WHEN ASI_MMU_FLUSH_PROBE =>
              -- Ces requètes viennent à travers le bus D, il ne peut y avoir
              -- que des FLUSH (écritures), jamais de PROBE (lectures)
              IF BSD_MODE THEN
                itlb_inval_c<='1';
                IF ls_v='1' THEN
                  iout_v.code:=PB_OK;
                  iout_v.cx:=imux2_cx;
                  ireq_v:='1';
                  na_v:='1';
                ELSE
                  inst_tw_req_c<='1';
                  IF inst_tw_rdy='1' THEN
                    na_v:='1';
                    inst_etat_c<=sTABLEWALK;
                  END IF;
                  inst_ext_c.twop<=PROBE;
                END IF;
              ELSE
                itlb_inval_c<='1';
                iout_v.code:=PB_OK;
                iout_v.cx:=imux2_cx;
                ireq_v:='1';
                na_v:='1';
              END IF;
              
              --------------------------
            WHEN ASI_USER_INSTRUCTION |
                 ASI_SUPER_INSTRUCTION =>
              -- User/Super Instruction
              IF NOT ASIINST THEN
                -- Si jamais d'accès croisé, il n'y a que des lectures
                ls_v:='0';
              END IF;
              itlb_sel_c<='1';
                ---------------------------------
              IF mmu_cr_e='1' AND tlb_hitv_v='0' THEN
                -- Tablewalk nécessaire. Après, tlb_hitv_v=1
                inst_tw_req_c<='1';
                inst_ext_c.twop<=LS;
                IF inst_tw_rdy='1' THEN
                  inst_etat_c<=sTABLEWALK;
                END IF;
                inst_txt<="TABLEWALK";
                
                ---------------------------------
              ELSIF mmu_cr_e='1' AND tlb_hitv_v='1' AND ft_v=FT_NONE AND
                m_v='0' AND ls_v='1' THEN
                -- Tablewalk pour positionner le bit Modified avant une écriture
                itlb_twm_c<='1';
                inst_tw_req_c<='1';
                inst_ext_c.twop<=LS;
                IF inst_tw_rdy='1' THEN
                  inst_etat_c<=sTABLEWALK;
                END IF;
                inst_txt<="TABLE_MOD";

                ---------------------------------
              ELSIF (mmu_cr_e='1' OR MMU_DIS) AND
                tlb_hitv_v='1' AND ft_v/=FT_NONE THEN
                -- Erreur d'accès : Violation de privilège ou de protection
                -- <AVOIR> Test 'No Fault' CR : Cas particulier pour ASI=09
                mmu_fault_inst_acc_c<='1';
                IF mmu_cr_nf='0' THEN -- MMU ERROR
                  iout_v.code:=PB_FAULT;
                ELSE
                  iout_v.code:=PB_OK;
                END IF;
                iout_v.cx:=imux2_cx;
                ireq_v:='1';
                na_v:='1';
                inst_txt<="MMU_ERROR";
                
                ---------------------------------
              ELSIF ls_v='0' AND ((mmu_cr_e='0' AND NOT MMU_DIS) OR
                 (tlb_hitv_v='1' AND ft_v=FT_NONE AND mmu_cr_ice='0') OR
                 (tlb_hitv_v='1' AND ft_v=FT_NONE AND mmu_cr_ice='1' AND
                  c_v='0')) THEN
                -- Lecture externe : Pas de cache, Pas de MMU ou non cacheable
                inst_ext_req_c<='1';
                inst_ext_c.op<=SINGLE;
                IF inst_ext_rdy='1' THEN
                  inst_etat_c<=sEXT_READ;
                  na_v:='1';
                END IF;
                inst_txt<="LECTU_EXT";
                
                ---------------------------------
              ELSIF (mmu_cr_e='1' OR MMU_DIS) AND tlb_hitv_v='1' AND
                ft_v=FT_NONE AND
                c_v='1' AND mmu_cr_ice='1' AND cache_hit_v='1' AND ls_v='0' THEN
                -- Lecture en cache. Simplement.
                iout_v.d:=cache_d_v;
                iout_v.code:=PB_OK;
                iout_v.cx:=imux2_cx;
                ireq_v:='1';
                na_v:=to_std_logic(WAY_ICACHE=1 OR NOT rmaj_v);
                readlru_v:=NOT na_v;
                inst_clr_c<=NOT na_v;
                inst_txt<="CACHE_LEC";
                
                ---------------------------------
              ELSIF (mmu_cr_e='1' OR MMU_DIS) AND tlb_hitv_v='1' AND
                ft_v=FT_NONE AND
                c_v='1' AND mmu_cr_ice='1' AND cache_hit_v='0' AND ls_v='0' THEN
                -- Cache fill pour une lecture
                inst_ext_req_c<='1';
                inst_ext_c.op<=FILL;
                IF inst_ext_rdy='1' THEN
                  inst_etat_c<=sEXT_READ;
                  na_v:='1';
                END IF;
                inst_txt<="FILL READ";
                
                ---------------------------------
              ELSIF ls_v='1' AND ((mmu_cr_e='0' AND NOT MMU_DIS) OR
                 (tlb_hitv_v='1' AND ft_v=FT_NONE
                               AND m_v='1' AND mmu_cr_ice='0') OR
                 (tlb_hitv_v='1' AND ft_v=FT_NONE AND m_v='1'
                               AND c_v='0' AND mmu_cr_ice='1') OR
                 (tlb_hitv_v='1' AND ft_v=FT_NONE AND m_v='1' AND c_v='1' AND
                  mmu_cr_ice='1' AND cache_hit_v='0')) THEN
                -- Ecriture externe : Pas de cache, pas de MMU, non cacheable
                -- ou pas dans le cache.
                IF NOT MMU_DIS AND NOT IPTAG THEN
                  -- Purge ligne de cache, protection aliasing!
                  inval_v:='1';
                END IF;
                inst_ext_req_c<='1';
                inst_ext_c.op<=SINGLE;
                IF inst_ext_rdy='1' THEN -- Ecriture postée
                  iout_v.code:=PB_OK;
                  iout_v.cx:=imux2_cx;
                  ireq_v:='1';
                  inst_clr_c<='1';
                END IF;
                inst_txt<="ECRIT_EXT";
                
                ---------------------------------
              ELSIF (mmu_cr_e='1' OR MMU_DIS) AND tlb_hitv_v='1' AND
                ft_v=FT_NONE AND
                m_v='1' AND c_v='1' AND mmu_cr_ice='1' AND cache_hit_v='1' AND
                ls_v='1' THEN
                -- Ecriture en cache et écriture externe (Write Through)
                write_v:='1';
                -- <Il ne faut écrire que pendant 1 cycle ?>
                -- Si écriture, on empêche l'acquittement inst_r_c.ack du
                -- second accès pendant le cycle zéro !               
                inst_ext_req_c<='1';
                inst_ext_c.op<=SINGLE;
                IF inst_ext_rdy='1' THEN -- Ecriture postée !
                  iout_v.code:=PB_OK;
                  iout_v.cx:=imux2_cx;
                  ireq_v:='1';
                  inst_clr_c<='1';
                END IF;
                inst_txt<="WRITE_TRU";
                
                ---------------------------------
              ELSE
                iout_v.code:=PB_OK;
                iout_v.cx:=imux2_cx;
                ireq_v:='1';
                na_v:='1';
                inst_txt<="<Cosmos >";
                -- Désactivé, accès croisés
              END IF;
              
              --------------------------
            WHEN ASI_CACHE_TAG_INSTRUCTION =>
              IF ASICACHE THEN
                -- Cet ASI est généré via la passerelle DATA -> INST
                iout_v.d:=icache_t_dr(0);
                -- <AFAIRE> Sélection voie selon addresse...
                iout_v.code:=PB_OK;
                iout_v.cx:=imux2_cx;
                ireq_v:='1';
                IF ls_v='1' THEN
                  -- Ecriture TAG
                  write_tag_v:='1';
                  inst_clr_c<='1';
                  inst_txt<="ITAG_ECRI";
                ELSE
                  -- Lecture TAG
                  na_v:='1';
                  inst_txt<="ITAG_LECT";                
                END IF;
              ELSE
                iout_v.code:=PB_OK;
                iout_v.cx:=imux2_cx;
                ireq_v:='1';
                na_v:='1';
              END IF;
              
               --------------------------
            WHEN ASI_CACHE_FLUSH_LINE_COMBINED_PAGE |
                 ASI_CACHE_FLUSH_LINE_COMBINED_SEGMENT |
                 ASI_CACHE_FLUSH_LINE_COMBINED_REGION |
                 ASI_CACHE_FLUSH_LINE_COMBINED_CONTEXT |
                 ASI_CACHE_FLUSH_LINE_COMBINED_USER |
                 ASI_CACHE_FLUSH_LINE_COMBINED_ANY =>
              -- Ces ASI sont générés via la passerelle DATA -> INST
              IF ls_v='1' THEN
                inval_v:='1'; --cache_inval_v;  -- <PROVISOIRE>
              END IF;
              iout_v.code:=PB_OK;
              iout_v.cx:=imux2_cx;
              ireq_v:='1';
              na_v:='1';
              
              --------------------------
            WHEN ASI_CACHE_FLUSH_LINE_INSTRUCTION_PAGE |
                 ASI_CACHE_FLUSH_LINE_INSTRUCTION_SEGMENT |
                 ASI_CACHE_FLUSH_LINE_INSTRUCTION_REGION |
                 ASI_CACHE_FLUSH_LINE_INSTRUCTION_CONTEXT |
                 ASI_CACHE_FLUSH_LINE_INSTRUCTION_USER |
                 ASI_CACHE_FLUSH_LINE_INSTRUCTION_ANY =>
              -- Ces ASI sont générés via la passerelle DATA -> INST
              IF ls_v='1' THEN
                inval_v:='1'; --cache_inval_v; <PROVISOIRE>
              END IF;
              iout_v.code:=PB_OK;
              iout_v.cx:=imux2_cx;
              ireq_v:='1';
              na_v:='1';
              
              --------------------------
            WHEN OTHERS =>
              -- Jamais, impossible...
              iout_v.code:=PB_OK;
              iout_v.cx:=imux2_cx;
              ireq_v:='1';
              na_v:='1';
              
          END CASE;
        END IF;
    
        ----------------------------------------------------
      WHEN sTABLEWALK =>
        -- Accès vers le contrôleur externe qui va faire le TableWalk
        iout_v.d:=tw_pte;
        iout_v.code:=PB_OK;
        iout_v.cx:=imux3_cx;
        
        IF tw_done_inst='1' THEN
          inst_etat_c<=sOISIF;
          IF tw_op=PROBE AND BSD_MODE THEN
            ireq_v:='1';
          ELSIF tw_err='1' THEN -- MMU ERROR
            na_v:='1';
            ireq_v:='1';
            IF mmu_cr_nf='0' THEN
              iout_v.code:=PB_FAULT;
            ELSE
              iout_v.code:=PB_OK;
            END IF;
          ELSE
            itlb_maj_c<='1';
          END IF;
        END IF;
        
        ----------------------------------------------------
      WHEN sEXT_READ =>
        -- Attente de données à relire depuis le bus externe
        iout_v.d:=ext_dr;
        iout_v.code:=PB_OK;
        iout_v.cx:=imux3_cx;
        IF ext_dreq_inst='1' THEN
          ireq_v:='1';
          inst_etat_c<=sOISIF;
        END IF;
    END CASE;
    
    -------------------------------------------------------------
    -- On pousse l'accès vers le proc
    inst_r_c.d   <=iout_v.d;
    inst_r_c.code<=iout_v.code;
    inst_r_c.dreq<=ireq_v AND NOT iout_v.cx;
    inst_r_c.ack<=na_v;

    -------------------------------------------------------------
    -- Multiplexage pour passerelle DATA -> INST
    
    -- cross_req_c : Requète comm. croisée
    -- cross_ack_c : Accès terminé, données prêtes
    IF ireq_v='1' AND iout_v.cx='1' THEN
      -- Fin du cross : La donnée a été poussée
      cross_v:='0';
      cross_ack_c<='1';
      inst_r_c.ack<='0';
      na_v:='1';
    ELSIF inst_w.req='0' AND na_v='1' AND cross_req_c='1' THEN
      -- Début du cross : On attend la fin de l'accès précédent
      cross_v:='1';
      cross_ack_c<='0';
      inst_r_c.ack<='0';
    ELSE
      cross_v:=cross;
      cross_ack_c<='0';
      IF cross='1' THEN
        inst_r_c.ack<='0';
      END IF;
    END IF;
      
    IF cross_v='1' THEN
      imux_w<=data2_w;
      imux_w.dack<=inst_w.dack;
      imux_cx<='1';
    ELSE
      imux_w<=inst_w;
      imux_cx<='0';
    END IF;

    cross_c<=cross_v;
    inst_dr_c<=iout_v;
    inst_na_c<=na_v;
    
    -------------------------------------------------------------
    -- Contrôle bus cache, adresses & données à écrire
    -- Par défaut on fait une lecture en même temps que l'accès TAG.
    -- Si écriture ou inval, il faut faire l'écriture 1 cycle après
    IF IPTAG THEN
      tag_v:=ptag_encode(fill_pa,ext_ifill,'0','0',"00",NB_ICACHE);
    ELSE
      tag_v:=vtag_encode(fill_va,mmu_ctxr,ext_ifill,fill_ts,"00",
                  NB_ICACHE,NB_CONTEXT);
    END IF;
    
    tag_maj(tags_v,
            tag_v,icache_tmux,hist_v,readlru_v,write_v,'0',
            '0','1',inval_v,nohit_v,nofill_v,0);
    
    icache_d_wr<=(OTHERS => "0000");
    IF ext_ifill='1' THEN
      -- Cache fill (On écrit plusieurs fois le tag sur place)
      icache_d_a <=fill_va(NB_ICACHE-1 DOWNTO 2);
      icache_d_dw<=ext_dr;
      icache_d_wr(nofill_v)<="1111";
      icache_t_a <=fill_va(NB_ICACHE-1 DOWNTO 2+NB_LINE);
      icache_t_dw<=tags_v;
      icache_t_wr<="1111";
      
    ELSIF inval_v='1' THEN
      -- Second cycle, inval cache. On modifie les tags, pas les données
      icache_d_a <=imux2_w.a(NB_ICACHE-1 DOWNTO 2);
      icache_d_dw<=imux2_w.d;
      icache_t_a <=imux2_w.a(NB_ICACHE-1 DOWNTO 2+NB_LINE);
      icache_t_dw<=tags_v;
      icache_t_wr<="1111";
      
    ELSIF write_v='1' OR readlru_v='1' THEN
      -- Second cycle. écriture simple. On modifie les données, pas les tags
      icache_d_a <=imux2_w.a(NB_ICACHE-1 DOWNTO 2);
      icache_d_dw<=imux2_w.d;
      IF write_v='1' THEN
        icache_d_wr(nohit_v)<=imux2_w.be;
      END IF;
      icache_t_a <=imux2_w.a(NB_ICACHE-1 DOWNTO 2+NB_LINE);
      icache_t_dw<=tags_v;
      IF WAY_ICACHE/=1 THEN
        icache_t_wr<="1111";
      ELSE
        icache_t_wr<="0000";
      END IF;
      
    ELSIF write_tag_v='1' THEN
      -- Second cycle. écriture tags. On modifie les tags, pas les données
      icache_d_a <=imux2_w.a(NB_ICACHE-1 DOWNTO 2);
      icache_d_dw<=imux2_w.d;
      icache_t_a <=imux2_w.a(NB_ICACHE-1 DOWNTO 2+NB_LINE);
      icache_t_dw<=(OTHERS => imux2_w.d);
      icache_t_wr<="1111";

    ELSIF na_v='0' THEN
      -- L'adresse est déjà au niveau 2
      icache_d_a <=imux2_w.a(NB_ICACHE-1 DOWNTO 2);
      icache_d_dw<=imux2_w.d;
      icache_t_a <=imux2_w.a(NB_ICACHE-1 DOWNTO 2+NB_LINE);
      icache_t_dw<=tags_v;
      icache_t_wr<="0000";
      
    ELSE
      -- Lecture data & tag
      icache_d_a <=imux_w.a(NB_ICACHE-1 DOWNTO 2);
      icache_d_dw<=imux2_w.d;
      icache_t_a <=imux_w.a(NB_ICACHE-1 DOWNTO 2+NB_LINE);
      icache_t_dw<=tags_v;
      icache_t_wr<="0000";
      
    END IF;
    
  END PROCESS Comb_Inst;

  inst_r<=inst_r_c;
  
  -------------------------------------------------------------------------
  -- Process synchrone bus INST
  Sync_Inst:PROCESS (clk)
    VARIABLE tlb_trouve : std_logic;
    VARIABLE no : natural RANGE 0 TO N_ITLB-1;
    VARIABLE hist_maj_v : std_logic;
  BEGIN
    IF rising_edge(clk) THEN
      -------------------------------------------
      -- Accès en continu
      IF filldone='1' OR imux2_w.req='0' OR imux2_w.cont='0' OR
        ext_ifill='0' THEN
        inst_cont<='0';
      ELSIF ext_dreq_inst='1' THEN
        inst_cont<='1';
      END IF;
      -------------------------------------------
      -- Gestion des TLBs
      hist_maj_v:='0';
      
      -- MàJ d'un TLB avec le contenu de tlb_mod_c.
      IF itlb_maj_c='1' AND NOT MMU_DIS THEN
        itlb_mem<=tlb_mod_c;
        inst_jat<='1';
        IF itlb_twm='1' THEN
          -- Cas particulier : Modification du bit M, le TLB est déjà chargé
          FOR I IN 0 TO N_ITLB-1 LOOP
            IF itlb_hitm(I)='1' THEN
              itlb(I)<=tlb_mod_c;
            END IF;
          END LOOP;
        ELSE
          -- <AVOIR> Problème si plusieurs TLB sont égaux ?
          tlb_trouve:='0';
          FOR I IN 0 TO N_ITLB-1 LOOP
            no:=I;
            IF itlb(I).v='0' THEN
              tlb_trouve:='1';
              itlb(I)<=tlb_mod_c;
              hist_maj_v:='1';
            END IF;
          END LOOP;
          IF tlb_trouve='0' THEN
            IF ITLB_MODE=CPT THEN
              -- Mode compteur
              itlb(itlb_cpt)<=tlb_mod_c;
              IF itlb_cpt/=N_ITLB-1 THEN
                itlb_cpt<=itlb_cpt+1;
              ELSE
                itlb_cpt<=0;
              END IF;
            ELSE
              -- Mode LRU
              no:=lru_old(itlb_hist,N_ITLB);
              itlb(no)<=tlb_mod_c;
              hist_maj_v:='1';
            END IF;
          END IF;
        END IF;
      END IF;
      IF itlb_sel_c='1' THEN
        FOR I IN 0 TO N_ITLB-1 LOOP
          IF itlb_hit(I)='1' THEN
            no:=I;
          END IF;
        END LOOP;
        hist_maj_v:='1';
      END IF;
      
      IF inst_na_c='1' THEN
        inst_jat<='0';
      END IF;
      
      IF hist_maj_v='1' AND ITLB_MODE=LRU THEN
        itlb_hist<=lru_maj(itlb_hist,no,N_ITLB);
      END IF;
      
      -- Flush de TLB
      FOR I IN 0 TO N_ITLB-1 LOOP
        IF itlb_inv(I)='1' AND itlb_inval_c='1' THEN
          itlb(I).v<='0';
        END IF;
      END LOOP;
      
      -------------------------------------------
      -- Pipeline accès INST
      IF inst_na_c='1' THEN
        -- Si pas de bloquage, au suivant
        imux2_w<=imux_w;
        imux2_cx<=imux_cx;
        imux3_cx<=imux2_cx;
      END IF;
      IF inst_clr_c='1' THEN
        imux2_w.req<='0';
      END IF;
      
      IF inst_na_c='1' THEN
        itlb_hit  <=itlb_hit_c;
        itlb_inv<=itlb_inv_c;
        itlb_hitv <=v_or(itlb_hit_c);
      END IF;

      IF itlb_twm_c='1' THEN
        itlb_hitm<=itlb_hit;
        itlb_twm<='1';
      ELSIF tw_done_inst='1' THEN
        itlb_twm<='0';
      END IF;
      
      filling_i2<=filling_i;
      inst_dr<=inst_dr_c;      
      IF icache_blo_c='1' THEN
        icache_t_mem<=icache_t_dr;
      END IF;

      -------------------------------------------
      -- Machine à états
      inst_etat<=inst_etat_c;
      cross<=cross_c;

      -------------------------------------------
      IF reset_n='0' THEN
        itlb_cpt<=0;
        inst_etat<=sOISIF;
        imux2_w.req<='0';
        FOR I IN 0 TO N_ITLB-1 LOOP
          itlb(I).v<='0';
        END LOOP;
        inst_jat<='0';
        itlb_twm<='0';
        cross<='0';
        itlb_hist<=x"00";
      END IF;  
    END IF;
  END PROCESS Sync_Inst;

  icache_tmux<=icache_t_dr WHEN icache_blo_c='1' ELSE icache_t_mem;  

  --###############################################################
  -- Gestion Registres MMU

  Sync_Regs:PROCESS (clk)
  BEGIN
    IF rising_edge(clk) THEN
      -------------------------------------------
      -- Registres MMU
      -- Ecriture MMU Control Register
      IF mmu_cr_maj='1' THEN
        mmu_cr_e  <=data2_w.d(0) AND NOT to_std_logic(MMU_DIS);
        mmu_cr_nf <=data2_w.d(1);
        mmu_cr_l2tlb<=data2_w.d(6) AND to_std_logic(L2TLB);
        mmu_cr_dce<=data2_w.d(8) AND cachena;
        mmu_cr_ice<=data2_w.d(9) AND cachena;
        mmu_cr_bm <=data2_w.d(14) AND to_std_logic(BOOTMODE);
      END IF;
      
      -- Ecriture MMU Context Table Pointer Register
      IF mmu_ctxtpr_maj='1' THEN
        mmu_ctxtpr<=data2_w.d(31 DOWNTO 2);
        mmu_ctxtpr(NB_CONTEXT+1 DOWNTO 6)<=(OTHERS => '0');  -- Aligne NCONTEXT
      END IF;
      
      -- Ecriture MMU Context Register
      IF mmu_ctxr_maj='1' THEN
        mmu_ctxr<=data2_w.d(NB_CONTEXT-1 DOWNTO 0);
      END IF;

      -- Acquittement MMU Fault Status Register
      IF mmu_fsr_maj='1' THEN
        -- On sait que c'est lu, donc pas d'OW
        mmu_fsr_ow<='0';
        mmu_fsr_ft<=FT_NONE;
        mmu_fclass<=RIEN;
        mmu_fsr_fav<='0';   -- RAZ Fault Address Valid
      END IF;

      IF mmu_tmpr_maj='1' THEN
        mmu_tmpr<=data2_w.d;
      END IF;
      
      -- Evènements :
      --      mmu_fault_data_acc_c : Erreur d'accès data
      --      mmu_fault_inst_acc_c : Erreur d'accès instruction
      --      mmu_tw_fault         : Erreur tablewalk
      -- Règles :
      --  - Priorités : Tablewalk > Data > Instructions
      --  - RAZ de OW si classe différente d'erreur
      -- <AVOIR> Ecriture des registres MMU pour un TW depuis le process EXT
      -- ou depuis les process DATA et INSTRUCTION ?
      -- <Ecriture MMU Fault Status Reg sur faute>
      IF mmu_tw_fault='1' AND NOT MMU_DIS THEN
        -- Faute pendant un tablewalk : INVALIDE ou TRANSLATION
        IF mmu_tw_ft/=FT_INVALID OR mmu_tw_di=TDI_DATA OR mmu_fsr_fav='0' THEN
          mmu_fclass<=WALK;
          mmu_fsr_l<=mmu_tw_st;           -- Level / Short Translation
          IF mmu_tw_di=TDI_DATA THEN
            mmu_fsr_at<=data_at_c;
          ELSE
            mmu_fsr_at<=inst_at_c;
          END IF;
          mmu_fsr_ft<=mmu_tw_ft;          -- Fault Type
          mmu_fsr_fav<='1';               -- Fault Address Valid
          mmu_fsr_ow<='0';                -- OverWrite
          mmu_far<=tw_va(31 DOWNTO 2);
        END IF;
        
      ELSIF mmu_fault_data_acc_c='1' AND NOT MMU_DIS THEN
        IF mmu_fclass/=WALK AND mmu_fclass/=DATA THEN
          mmu_fclass<=DATA;
          -- Faute sur accès normal data : PROTECTION ou PRIVILEGE
          mmu_fsr_l<="00";                -- Level ???
          mmu_fsr_at<=data_at_c;          -- Access Type
          mmu_fsr_ft<=data_ft_c;          -- Fault Type
          mmu_fsr_fav<='1';               -- Fault Address Valid
          mmu_fsr_ow<=to_std_logic(mmu_fclass=DATA); -- OverWrite
          mmu_far<=data2_w.a(31 DOWNTO 2);
        END IF;
        -- <AVOIR> : !! Cascade de fautes data. Impossible ?
        
      ELSIF mmu_fault_inst_acc_c='1' AND NOT MMU_DIS THEN
        IF mmu_fclass/=WALK AND mmu_fclass/=DATA THEN
          mmu_fclass<=INST;
          -- Faute sur accès normal instruction : PROTECTION ou PRIVILEGE
          mmu_fsr_l<="00";                -- Level ???
          mmu_fsr_at<=inst_at_c;          -- Access Type
          mmu_fsr_ft<=inst_ft_c;          -- Fault Type
          mmu_fsr_fav<='1';               -- Fault Address Valid
          mmu_fsr_ow<=to_std_logic(mmu_fclass=INST); -- OverWrite
          -- L'écriture de FAR est facultative !!!
          mmu_far<=imux2_w.a(31 DOWNTO 2);
        END IF;
      END IF;

      IF reset_n='0' THEN
        mmu_cr_e<='0';
        mmu_cr_nf<='0';
        mmu_cr_dce<='0';
        mmu_cr_ice<='0';
        mmu_cr_l2tlb<='0';
        mmu_cr_bm<=to_std_logic(BOOTMODE);
        mmu_fsr_ow<='0';
        mmu_fsr_ft<=FT_NONE;
        mmu_fsr_fav<='0';
      END IF;        

    END IF;
  END PROCESS Sync_Regs;
  
  --###############################################################
  -- Tablewalker
  
  i_mcu_tw: ENTITY work.mcu_tw
    GENERIC MAP (
      NB_CONTEXT => NB_CONTEXT,
      CPUTYPE    => CPUTYPE)
    PORT MAP (
      inst_tw_req    => inst_tw_req_c,
      inst_tw_rdy    => inst_tw_rdy,
      inst_ext_c     => inst_ext_c,
      itlb_inval     => itlb_inval_c,
      tw_done_inst   => tw_done_inst,
      data_tw_req    => data_tw_req_c,
      data_tw_rdy    => data_tw_rdy,
      data_ext_c     => data_ext_c,
      dtlb_inval     => dtlb_inval_c,
      tw_done_data   => tw_done_data,
      tlb_mod        => tlb_mod_c,
      tw_pte         => tw_pte,
      tw_err         => tw_err,
      tw_va          => tw_va,
      tw_op          => tw_op,
      tw_ext         => tw_ext,
      tw_ext_req     => tw_ext_req,
      tw_ext_ack     => pop_tw_c,
      ext_dreq_tw    => ext_dreq_tw,
      ext_dr         => ext_dr,
      mmu_cr_nf      => mmu_cr_nf,
      mmu_cr_l2tlb   => mmu_l2tlbena,
      mmu_cr_wb      => '0',
      mmu_cr_aw      => '0',
      mmu_ctxtpr     => mmu_ctxtpr,
      mmu_ctxtpr_maj => mmu_ctxtpr_maj,
      mmu_ctxr       => mmu_ctxr,
      mmu_ctxr_maj   => mmu_ctxr_maj,
      mmu_tw_fault   => mmu_tw_fault,
      mmu_tw_ft      => mmu_tw_ft,
      mmu_tw_st      => mmu_tw_st,
      mmu_tw_di      => mmu_tw_di,
      reset_n        => reset_n,
      clk            => clk);
  
  mmu_l2tlbena <= mmu_cr_l2tlb AND l2tlbena;
  
  --###############################################################
  -- Mémorisation accès I/D
  
  -------------------------------------------------  
  -- Prêt pour un nouvel accès
  ext_pat_c<=to_std_logic(
    (ext_etat=sOISIF OR (ext_etat=sSINGLE AND ext_r.ack='1') OR
     (ext_etat=sFILL AND ext_r.ack='1' AND ext_burst=BURST_1))
    AND ext_fifo_lev/=2);
  
  -------------------------------------------------
  -- Priorité TW -> DATA -> INST
  -- Si accès atomiques LOCK, on maintient  TW ou DATA

  -- ? si lock_pre=1
  --   - Dépile depuis le dernier, bloque les autres
  -- ¤ sinon
  --   ? si TW=1
  --     - Dépile TW
  --   ? si DATA=1
  --     - Dépile DATA

  -- Turlu : Buffers DATA & INST
  -- Si RDY=1, on peut accepter un accès
  -- Si RDY=0, on a déjà MEM de plein.

  -- si pat_c='1' : on peut accepter un nouvel accès

  Carl:PROCESS(ext_pat_c,ext_lock,tw_ext_req,
               data_ext_req_c,data_ext_reqm,
               inst_ext_req_c,inst_ext_reqm) IS
  BEGIN
    pop_tw_c<='0';
    pop_data_c<='0';
    pop_inst_c<='0';
    IF ext_pat_c='1' THEN
      IF ext_lock=LDATA THEN
        pop_data_c<=data_ext_req_c OR data_ext_reqm;
      ELSIF ext_lock=LTW THEN
        pop_tw_c  <=tw_ext_req;
      ELSIF tw_ext_req='1' THEN
        pop_tw_c  <='1';
      ELSIF data_ext_req_c='1' OR data_ext_reqm='1' THEN
        pop_data_c<='1';
      ELSIF inst_ext_req_c='1' OR inst_ext_reqm='1' THEN
        pop_inst_c<='1';
      END IF;
    END IF;
  END PROCESS Carl;
  
  Turlusiphon:PROCESS (clk)
  BEGIN
    IF rising_edge(clk) THEN
      IF inst_ext_reqm='0' THEN
        inst_ext_mem<=inst_ext_c;
      END IF;
      IF data_ext_reqm='0' THEN
        data_ext_mem<=data_ext_c;
      END IF;
      
      IF pop_data_c='1' AND data_ext_reqm='1' THEN
        data_ext_reqm<='0';
      ELSIF data_ext_req_c='1' AND pop_data_c='0' THEN
        data_ext_reqm<='1';
      END IF;
      
      IF pop_inst_c='1' AND inst_ext_reqm='1' THEN
        inst_ext_reqm<='0';
      ELSIF inst_ext_req_c='1' AND pop_inst_c='0' THEN
        inst_ext_reqm<='1';
      END IF;

      IF reset_n='0' THEN
        inst_ext_reqm<='0';
        data_ext_reqm<='0';
      END IF;
    END IF;
  END PROCESS Turlusiphon;
  
  inst_ext2_c<=inst_ext_c WHEN inst_ext_rdy='1' ELSE inst_ext_mem;
  data_ext2_c<=data_ext_c WHEN data_ext_rdy='1' ELSE data_ext_mem;
  
  data_ext_rdy<=NOT data_ext_reqm;
  inst_ext_rdy<=NOT inst_ext_reqm;
  
  --###############################################################
  -- Bus externe

  -- - Accès lectures et écritures simples
  -- - Cache fill
  -- - Tablewalk
  --   L0 : Contexte, pas de comparaison d'adresses
  --   L1 : VA[31:24],   L2 : VA[31:18],   L3 : VA[31:12]
  --   A partir du cache PTP L0, on accède à la table sans d'abord chercher la
  --     table de contextes
  --   A partir du cache PTP L2, il faut indexer avec le numéro de page[17:12]
  --     pour avoir directement le PTE final L3

  -- On donne la priorité aux DATA, pour ne pas risquer de bloquer le proc.
  -- Pour les écritures, on peut poster.
  -- On accède de façon synchrone au bus externe, on rajoute donc 1WS

  -- Les bursts commencent toujours en Zéro
  
  -------------------------------------------------
  Sync_Ext:PROCESS (clk)
    VARIABLE fifo_v : type_ext_fifo;
    VARIABLE ext_fifo_push_v,ext_fifo_pop_v : std_logic;
  BEGIN
    IF rising_edge(clk) THEN
      ext_fifo_push_v:='0';
      ext_fifo_pop_v:='0';
      filling_end<='0';
      
      -------------------------------------------------
      -- Données relues et écritures en cache
      ext_dr<=ext_r.d;
      
      ext_dreq_data<=to_std_logic(ext_fifo.di=DI_DATA AND
        (ext_fifo.op=SINGLE OR ext_fifo.op=FILL) AND
         ext_fifo.va(NB_LINE+1 DOWNTO 2)=ext_fifo.al) AND ext_r.dreq;
      
      ext_dreq_inst<=to_std_logic(ext_fifo.di=DI_INST AND
        (ext_fifo.op=SINGLE OR ext_fifo.op=FILL) AND
         ext_fifo.va(NB_LINE+1 DOWNTO 2)=ext_fifo.al) AND ext_r.dreq;
      
      ext_dreq_tw<=to_std_logic(ext_fifo.di=DI_TW AND
        (ext_fifo.op=SINGLE OR ext_fifo.op=FILL) AND
         ext_fifo.va(NB_LINE+1 DOWNTO 2)=ext_fifo.al) AND ext_r.dreq;
      
      filldone<=to_std_logic(ext_fifo.va(NB_LINE+1 DOWNTO 2)=BURST_1);
      
      IF filling_end='1' THEN
        filling_d<='0';
        filling_i<='0';
      END IF;
      
      IF (ext_fifo.op=SINGLE OR ext_fifo.op=FILL) AND ext_r.dreq='1' THEN
        fill_va<=ext_fifo.va;           -- Cache Adress (VT)
        fill_pa<=ext_fifo.pa;           -- Cache Adress (PT)
        fill_ts<=ext_fifo.ts;           -- TLB Super
        ext_fifo.va(NB_LINE+1 DOWNTO 2)<=ext_fifo.va(NB_LINE+1 DOWNTO 2)+1;
        ext_fifo.pa(NB_LINE+1 DOWNTO 2)<=ext_fifo.pa(NB_LINE+1 DOWNTO 2)+1;
        IF ext_fifo.va(NB_LINE+1 DOWNTO 2)=BURST_1 OR ext_fifo.op=SINGLE THEN
          ext_fifo_pop_v:='1';
          filling_end<='1';
        END IF;
        -- BURST + DATA
        ext_dfill<=to_std_logic(ext_fifo.di=DI_DATA AND ext_fifo.op=FILL);
        filling_d<=to_std_logic(ext_fifo.di=DI_DATA AND ext_fifo.op=FILL);
        -- BURST + INST
        ext_ifill<=to_std_logic(ext_fifo.di=DI_INST AND ext_fifo.op=FILL);
        filling_i<=to_std_logic(ext_fifo.di=DI_INST AND ext_fifo.op=FILL);
      ELSE
        ext_dfill<='0';
        ext_ifill<='0';
      END IF;
      
      -------------------------------------------------
      IF (ext_lock=LDATA AND data_ext2_c.pw.lock='0') OR
         (ext_lock=LTW   AND tw_ext.pw.lock='0') THEN
        ext_lock<=LOFF;
        ext_w_i.lock<='0';
      END IF;
      
      -------------------------------------------------
      fifo_v:=(op=>data_ext2_c.op,di=>DI_DATA,ts=>data_ext2_c.ts,
               va=>data_ext2_c.va,pa=>data_ext2_c.pw.ah & data_ext2_c.pw.a,
               al=>data_ext2_c.va(NB_LINE+1 DOWNTO 2));
      
      -------------------------------------------------
      -- Machine à états
      CASE ext_etat IS
        WHEN sOISIF | sSINGLE | sFILL =>
          
          IF ext_pat_c='1' THEN
            -- Début d'un nouvel accès
            ext_burst<=(OTHERS => '0');
            
            IF pop_data_c='1' THEN
              fifo_v:=(op=>data_ext2_c.op,di=>DI_DATA,ts=>data_ext2_c.ts,
                     va=>data_ext2_c.va,pa=>data_ext2_c.pw.ah & data_ext2_c.pw.a,
                     al=>data_ext2_c.va(NB_LINE+1 DOWNTO 2));
              IF data_ext2_c.pw.lock='1' THEN
                ext_lock<=LDATA;
              END IF;
              
              CASE data_ext2_c.op IS
                WHEN SINGLE =>
                  -- Accès simple data
                  ext_etat<=sSINGLE;
                  ext_w_i<=data_ext2_c.pw;
                  ext_w_i.req<='1';
                  ext_fifo_push_v:=to_std_logic(data_ext2_c.pw.mode=PB_MODE_RD);
                WHEN OTHERS =>
                  -- Cache fill data
                  ext_etat<=sFILL;
                  ext_w_i<=data_ext2_c.pw;
                  ext_w_i.a<=data_ext2_c.pw.a;
                  ext_w_i.a(NB_LINE+1 DOWNTO 2)<=(OTHERS => '0');
                  ext_w_i.burst<=pb_blen(BLEN_DCACHE);
                  ext_w_i.req<='1';
                  fifo_v.va(NB_LINE+1 DOWNTO 2):=(OTHERS => '0');
                  fifo_v.pa(NB_LINE+1 DOWNTO 2):=(OTHERS => '0');
                  ext_fifo_push_v:=to_std_logic(data_ext2_c.pw.mode=PB_MODE_RD);
              END CASE;
              
            ELSIF pop_inst_c='1' THEN
              fifo_v:=(op=>inst_ext2_c.op,di=>DI_INST,ts=>inst_ext2_c.ts,
                     va=>inst_ext2_c.va,pa=>inst_ext2_c.pw.ah & inst_ext2_c.pw.a,
                     al=>inst_ext2_c.va(NB_LINE+1 DOWNTO 2));
              CASE inst_ext2_c.op IS
                WHEN SINGLE =>
                  -- Accès simple instruction
                  ext_etat<=sSINGLE;
                  ext_w_i<=inst_ext2_c.pw;
                  ext_w_i.req<='1';
                  ext_fifo_push_v:=to_std_logic(inst_ext2_c.pw.mode=PB_MODE_RD);
                WHEN OTHERS =>
                  -- Cache fill instruction
                  ext_etat<=sFILL;
                  ext_w_i<=inst_ext2_c.pw;
                  ext_w_i.a<=inst_ext2_c.pw.a;
                  ext_w_i.a(NB_LINE+1 DOWNTO 2)<=(OTHERS => '0');
                  ext_w_i.burst<=pb_blen(BLEN_ICACHE);
                  ext_w_i.req<='1';
                  fifo_v.va(NB_LINE+1 DOWNTO 2):=(OTHERS => '0');
                  fifo_v.pa(NB_LINE+1 DOWNTO 2):=(OTHERS => '0');
                  ext_fifo_push_v:=to_std_logic(inst_ext2_c.pw.mode=PB_MODE_RD);
              END CASE;
              
            ELSIF pop_tw_c='1' THEN
              ext_etat<=sSINGLE;
              ext_w_i<=tw_ext.pw;
              ext_w_i.req<='1';
              fifo_v:=(op=>tw_ext.op,di=>DI_TW,ts=>tw_ext.ts,
                       va=>tw_ext.pw.a,pa=>tw_ext.pw.ah & tw_ext.pw.a,
                       al=>tw_ext.pw.a(NB_LINE+1 DOWNTO 2));
              ext_fifo_push_v:=to_std_logic(tw_ext.pw.mode=PB_MODE_RD);
              IF tw_ext.pw.lock='1' THEN
                ext_lock<=LTW;
              END IF;
            ELSE
              ext_etat<=sOISIF;
              ext_w_i.req<='0';
            END IF;
            
          ELSIF ext_r.ack='1' AND ext_w_i.req='1' THEN
            -- Burst linéaire
            ext_burst<=ext_burst + 1;
            ext_w_i.a(NB_LINE+1 DOWNTO 2)<=ext_burst + 1;
            ext_w_i.burst<=PB_SINGLE;
            IF (ext_burst=BURST_1 AND ext_etat=sFILL) OR ext_etat=sSINGLE THEN
              ext_etat<=sOISIF;
              ext_w_i.req<='0';
            END IF;
          END IF;
      END CASE;
      
      ext_w_i.dack<='1';

      -------------------------------------------------
      -- FIFO Commandes
      IF ext_fifo_push_v='1' AND ext_fifo_pop_v='0' THEN
        -- Empile
        IF ext_fifo_lev<3 THEN
          ext_fifo_lev<=ext_fifo_lev+1;
        END IF;
        IF ext_fifo_lev=0 THEN
          ext_fifo<=fifo_v;
        ELSIF ext_fifo_lev=1 THEN
          ext_fifo_mem<=fifo_v;
        END IF;
        ext_fifo_mem2<=fifo_v;
        
      ELSIF ext_fifo_push_v='0' AND ext_fifo_pop_v='1' THEN
        -- Dépile
        ext_fifo<=ext_fifo_mem;
        ext_fifo_mem<=ext_fifo_mem2;
        ext_fifo_mem2<=fifo_v;
        IF ext_fifo_lev>0 THEN
          ext_fifo_lev<=ext_fifo_lev-1;
        END IF;
        
      ELSIF ext_fifo_push_v='1' AND ext_fifo_pop_v='1' THEN
        -- Empile & Dépile
        ext_fifo<=ext_fifo_mem;
        ext_fifo_mem<=ext_fifo_mem2;
        ext_fifo_mem2<=fifo_v;
        IF ext_fifo_lev=2 THEN
          ext_fifo_mem<=fifo_v;
        ELSIF ext_fifo_lev=1 THEN
          ext_fifo<=fifo_v;
        END IF;
      END IF;
      
      -------------------------------------------------
      IF reset_n='0' THEN
        ext_w_i.req<='0';
        ext_w_i.dack<='1';
        ext_etat<=sOISIF;
        ext_ifill<='0';
        ext_dfill<='0';
        filling_d<='0';
        filling_i<='0';
        ext_dreq_inst<='0';
        ext_lock<=LOFF;
        ext_fifo_lev<=0;
      END IF;        

    END IF;
  END PROCESS Sync_Ext;

  ext_w<=ext_w_i;

END ARCHITECTURE simple;
