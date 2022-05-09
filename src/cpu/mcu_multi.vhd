--------------------------------------------------------------------------------
-- TEM : TACUS
-- Contrôleur MMU / Cache Multiprocesseurs
--------------------------------------------------------------------------------
-- DO 9/2015
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

-- <Simplifier wait_fill>

--  - Caches Séparés I et D.
--  - Direct map ou multivoies.
--  - VIVT/VIPT
--  - Write Through et Write Back
--  - Allocate / No allocate on Write

--  - Cohérence de cache. Snooping
--  - Tags cache à double port
--  - Tags mode PI.

--  - Si pas de MMU, pas de cache
--  - Caches pour un PTD L0, un PTD L2I et un PTD L2D

-- En Boot Mode, le cache instruction est désactivé.

-- 6 parties :
--  - Interface DATA
--  - Interface INSTRUCTION
--  - Registres MMU
--  - Bus externe
--  - Séquenceur Tablewalk
--  - Snooping

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
ARCHITECTURE multi OF mcu_mp IS
  
  CONSTANT BLEN_DCACHE : natural := CPUCONF(CPUTYPE).BLEN_DCACHE;
  CONSTANT BLEN_ICACHE : natural := CPUCONF(CPUTYPE).BLEN_ICACHE;
  CONSTANT NB_DCACHE   : natural := CPUCONF(CPUTYPE).NB_DCACHE;
  CONSTANT NB_ICACHE   : natural := CPUCONF(CPUTYPE).NB_ICACHE;
  CONSTANT NB_LINE     : natural := ilog2(BLEN_ICACHE);
  CONSTANT WAY_DCACHE  : natural := CPUCONF(CPUTYPE).WAY_DCACHE;
  CONSTANT WAY_ICACHE  : natural := CPUCONF(CPUTYPE).WAY_ICACHE;
  CONSTANT MMU_IMP_VERSION : uv8 := CPUCONF(CPUTYPE).MMU_IMP_VER;
  CONSTANT NB_CONTEXT  : natural := CPUCONF(CPUTYPE).NB_CONTEXT;
  CONSTANT L2TLB       : boolean := CPUCONF(CPUTYPE).L2TLB;
  
  -- MMU Général, registres
  SIGNAL mmu_cr_e : std_logic;       -- MMU Control Register(0)  MMU Enable
  SIGNAL mmu_cr_nf : std_logic;      -- MMU Control Register(1)  No Fault
                                     -- MMU Control Register(3..2) CPU MID
  SIGNAL mmu_cr_wb : std_logic;      -- MMU Control Register(4)  WriteBack enable
  SIGNAL mmu_cr_aw : std_logic;      -- MMU Control Register(5)  Allocate On Write enable
  SIGNAL mmu_cr_l2tlb : std_logic;   -- MMU Control Register(6)  L2 TLB cache
  SIGNAL mmu_cr_dce : std_logic;     -- MMU Control Register(8)  Data Cache Enable
  SIGNAL mmu_cr_ice : std_logic;     -- MMU Control Register(9)  Inst Cache Enable
  SIGNAL mmu_cr_bm : std_logic;      -- MMU Control Register(13) Boot Mode multi
  SIGNAL mmu_cr_dsnoop : std_logic;  -- MMU Control Register(14) Enable d-cache snooping
  SIGNAL mmu_cr_isnoop : std_logic;  -- MMU Control Register(14) Enable i-cache snooping
  
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
  SIGNAL dreg : uv32;
  SIGNAL mmu_l2tlbena : std_logic;
  
  ------------------------------------------------------------------------------
  -- DATA
  TYPE enum_data_etat IS (sOISIF,sREGISTRE,sCROSS,sCROSS_DATA,
                          sTABLEWALK,sEXT_READ,sWAIT_FILL,sWAIT_FILL2,
                          sWAIT_SHARE);
  SIGNAL data_etat_c,data_etat : enum_data_etat;

  -- Contrôles
  SIGNAL data_r_c : type_plomb_r;
  SIGNAL data2_w  : type_plomb_w;        -- Cycle 2
  SIGNAL data_na_c  : std_logic;         -- Acquitte l'accès
  SIGNAL data_clr_c : std_logic;        -- Fin d'accès écriture
  
  SIGNAL data_ext_c : type_ext;         -- Paramètres accès externe data
  
  SIGNAL data_ext_req_c,data_ext_rdy : std_logic;
  
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
  SIGNAL dcache_d_w,dcache_d2_w : arr_pvc_w(0 TO WAY_DCACHE-1);
  SIGNAL dcache_t_w,dcache_t2_w : arr_pvc_w(0 TO WAY_DCACHE-1);
  SIGNAL dcache_d_r,dcache_d2_r : arr_pvc_r(0 TO WAY_DCACHE-1);
  SIGNAL dcache_t_r,dcache_t2_r : arr_pvc_r(0 TO WAY_DCACHE-1);
  SIGNAL dcache_d_a : unsigned(NB_DCACHE-1 DOWNTO 2);
  SIGNAL dcache_d_dr,dcache_d2_dr : arr_uv32(0 TO WAY_DCACHE-1);
  SIGNAL dcache_d_dw,dcache_d2_dw : uv32;
  SIGNAL dcache_d_wr,dcache_d2_wr : arr_uv0_3(0 TO WAY_DCACHE-1);
  SIGNAL dcache_t_a : unsigned(NB_DCACHE-NB_LINE-1 DOWNTO 2);
  SIGNAL dcache_t_dr,dcache_t2_dr : arr_uv32(0 TO WAY_DCACHE-1);
  SIGNAL dcache_t_dw,dcache_t2_dw : arr_uv32(0 TO WAY_DCACHE-1);
  SIGNAL dcache_t_wr,dcache_t2_wr : uv0_3;
  SIGNAL dcache_t_mem : arr_uv32(0 TO WAY_DCACHE-1);
  SIGNAL dcache_tmux  : arr_uv32(0 TO WAY_DCACHE-1);
  SIGNAL dcache_blo_c : std_logic;
  SIGNAL dcache_cpt : natural RANGE 0 TO WAY_DCACHE-1;  -- Cpt. aléatoire
  SIGNAL dcache_t_a2,dcache_a_mem : unsigned(NB_DCACHE-NB_LINE-1 DOWNTO 2);
  
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
  SIGNAL icache_d_w,icache_d2_w : arr_pvc_w(0 TO WAY_ICACHE-1);
  SIGNAL icache_t_w,icache_t2_w : arr_pvc_w(0 TO WAY_ICACHE-1);
  SIGNAL icache_d_r,icache_d2_r : arr_pvc_r(0 TO WAY_ICACHE-1);
  SIGNAL icache_t_r,icache_t2_r : arr_pvc_r(0 TO WAY_ICACHE-1);
  SIGNAL icache_d_a : unsigned(NB_ICACHE-1 DOWNTO 2);
  SIGNAL icache_d_dr,icache_d2_dr : arr_uv32(0 TO WAY_ICACHE-1);
  SIGNAL icache_d_dw,icache_d2_dw : uv32;
  SIGNAL icache_d_wr,icache_d2_wr : arr_uv0_3(0 TO WAY_ICACHE-1);
  SIGNAL icache_t_a : unsigned(NB_ICACHE-NB_LINE-1 DOWNTO 2);
  SIGNAL icache_t_dr,icache_t2_dr : arr_uv32(0 TO WAY_ICACHE-1);
  SIGNAL icache_t_dw,icache_t2_dw : arr_uv32(0 TO WAY_ICACHE-1);
  SIGNAL icache_t_wr,icache_t2_wr : uv0_3;
  SIGNAL icache_t_mem : arr_uv32(0 TO WAY_ICACHE-1);
  SIGNAL icache_tmux  : arr_uv32(0 TO WAY_ICACHE-1);
  SIGNAL icache_blo_c : std_logic;
  SIGNAL icache_cpt : natural RANGE 0 TO WAY_ICACHE-1;  -- Cpt. aléatoire
  SIGNAL icache_t_a2,icache_a_mem : unsigned(NB_ICACHE-NB_LINE-1 DOWNTO 2);
  
  SIGNAL inst_txt : string(1 TO 9);
  
  --------------------------------------------------------
  -- TableWalker
  SIGNAL data_tw_req_c ,inst_tw_req_c  : std_logic;
  SIGNAL data_tw_rdy   ,inst_tw_rdy    : std_logic;
  
  SIGNAL tlb_mod_c : type_tlb;
  SIGNAL tw_ext : type_ext;
  SIGNAL tw_ext_req,tw_ext_ack : std_logic;
  
  SIGNAL tw_done_data : std_logic;     -- Tablewalk terminé
  SIGNAL tw_done_inst : std_logic;     -- Tablewalk terminé
  SIGNAL tw_pte    : uv32;             -- Données bus externe du tablewalk
  SIGNAL tw_err    : std_logic;        -- Erreur sur accès externe : Tablewalk
  SIGNAL tw_op     : enum_tw_op;
  SIGNAL tw_va     : uv32;
  
  SIGNAL mmu_tw_fault : std_logic;
  SIGNAL mmu_tw_ft  : unsigned(2 DOWNTO 0);  -- Fault Type
  SIGNAL mmu_tw_st  : uv2;              -- Niveau pagetable
  SIGNAL mmu_tw_di  : std_logic; -- 0=DATA 1=INST
  
  --------------------------------------------------------
  -- Bus Externe
  SIGNAL idcache_d2_a,idcache_t2_a : uv32;
  SIGNAL last_l : std_logic;
  
  SIGNAL ext_dreq_data : std_logic;  -- Données bus externes prêtes pour data
  SIGNAL ext_dreq_inst : std_logic;  -- Données bus externes prêtes pour inst
  SIGNAL ext_dreq_tw   : std_logic;  -- Données bus externes prêtes pour tw
  SIGNAL ext_pte_data : std_logic;      -- Tablewalk terminé
  SIGNAL ext_pte_inst : std_logic;      -- Tablewalk terminé
  SIGNAL ext_dr     : uv32;             -- Données bus externes vers IU
  CONSTANT BURST_0 : unsigned(NB_LINE-1 DOWNTO 0) := (OTHERS =>'0');
  
  -- Cache fill commandé par le bus externe
  SIGNAL ext_dfill,ext_ifill : std_logic;
  SIGNAL filling_d,filling_d2 : std_logic;
  SIGNAL filling_i,filling_i2 : std_logic;
  SIGNAL filldone : std_logic;

  SIGNAL fill_d : uv32;
  SIGNAL idcache_t_a  : uv32; -- Cache line/index depuis EXT
  
  SIGNAL dbusy,ibusy : std_logic;
  SIGNAL hitmaj : std_logic;
  SIGNAL xxx_dwthru,xxx_dwback,xxx_dreadlru : std_logic;
  SIGNAL xxx_dexr : uint8;
  SIGNAL xxx_dexmax : std_logic;
  
  --------------------------------------------------------
  COMPONENT iram IS
    GENERIC (
      N    : uint8;
      OCT  : boolean);
    PORT (
      mem_w    : IN  type_pvc_w;
      mem_r    : OUT type_pvc_r;
      clk      : IN  std_logic;
      reset_na : IN  std_logic);
  END COMPONENT iram;

  COMPONENT iram_dp IS
    GENERIC (
      N   : uint8;
      OCT : boolean);
    PORT (
      mem1_w    : IN  type_pvc_w;
      mem1_r    : OUT type_pvc_r;
      clk1      : IN  std_logic;
      reset1_na : IN  std_logic;
      mem2_w    : IN  type_pvc_w;
      mem2_r    : OUT type_pvc_r;
      clk2      : IN  std_logic;
      reset2_na : IN  std_logic);
  END COMPONENT iram_dp;
  
  COMPONENT iram_bi IS
    GENERIC (
      N   : uint8;
      OCT : boolean);
    PORT (
      mem1_w   : IN  type_pvc_w;
      mem1_r   : OUT type_pvc_r;
      mem2_w   : IN  type_pvc_w;
      mem2_r   : OUT type_pvc_r;
      clk      : IN  std_logic;
      reset_na : IN  std_logic);
  END COMPONENT iram_bi;
  
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
    
    dcache_d2_w(i).req<='1';
    dcache_d2_w(i).be <=dcache_d2_wr(i);
    dcache_d2_w(i).wr <=to_std_logic(dcache_d2_wr(i)/="0000");
    dcache_d2_w(i).a(31 DOWNTO NB_DCACHE)<=(OTHERS => '0');  -- Bourrage
    dcache_d2_w(i).a(NB_DCACHE-1 DOWNTO 0)<=idcache_d2_a(NB_DCACHE-1 DOWNTO 2) & "00";
    dcache_d2_w(i).dw <=dcache_d2_dw;
    dcache_d2_dr(i)<=dcache_d2_r(i).dr;
    
    i_dcache: iram_dp
      GENERIC MAP (
        N => NB_DCACHE, OCT=>true)
      PORT MAP (
        mem1_w    => dcache_d_w(i),
        mem1_r    => dcache_d_r(i),
        clk1      => clk,
        reset1_na => reset_na,
        mem2_w    => dcache_d2_w(i),
        mem2_r    => dcache_d2_r(i),
        clk2      => clk,
        reset2_na => reset_na);
        
  END GENERATE Gen_DCacheD;
  
  Gen_ICacheD: FOR i IN 0 TO WAY_ICACHE-1 GENERATE
    icache_d_w(i).req<='1';
    icache_d_w(i).be <=icache_d_wr(i);
    icache_d_w(i).wr <=to_std_logic(icache_d_wr(i)/="0000");
    icache_d_w(i).a(31 DOWNTO NB_ICACHE)<=(OTHERS => '0');  -- Bourrage
    icache_d_w(i).a(NB_ICACHE-1 DOWNTO 0)<=icache_d_a & "00";
    icache_d_w(i).dw <=icache_d_dw;
    icache_d_dr(i)<=icache_d_r(i).dr;

    icache_d2_w(i).req<='1';
    icache_d2_w(i).be <=icache_d2_wr(i);
    icache_d2_w(i).wr <=to_std_logic(icache_d2_wr(i)/="0000");
    icache_d2_w(i).a(31 DOWNTO NB_ICACHE)<=(OTHERS => '0');  -- Bourrage
    icache_d2_w(i).a(NB_ICACHE-1 DOWNTO 0)<=idcache_d2_a(NB_DCACHE-1 DOWNTO 2) & "00";
    icache_d2_w(i).dw <=icache_d2_dw;
    icache_d2_dr(i)<=icache_d2_r(i).dr;
    
    i_icache: iram_dp
      GENERIC MAP (
        N => NB_ICACHE, OCT=>true)
      PORT MAP (
        mem1_w    => icache_d_w(i),
        mem1_r    => icache_d_r(i),
        clk1      => clk,
        reset1_na => reset_na,
        mem2_w    => icache_d2_w(i),
        mem2_r    => icache_d2_r(i),
        clk2      => clk,
        reset2_na => reset_na);

  END GENERATE Gen_ICacheD;

  -----------------------------------------------------------------
  -- Tags
  -- Il y a NB_DCACHE / NB_LINE / 4 tags, de 32bits, par voie
  -- Il y a NB_ICACHE / NB_LINE / 4 tags, de 32bits, par voie

  -- Accès IU
  Gen_DCacheT: FOR i IN 0 TO WAY_DCACHE-1 GENERATE
    dcache_t_w(i).req<='1';
    dcache_t_w(i).be <=dcache_t_wr;
    dcache_t_w(i).wr <=to_std_logic(dcache_t_wr/="0000");
    dcache_t_w(i).a(31 DOWNTO NB_DCACHE-NB_LINE)<=(OTHERS => '0');  -- Bourrage
    dcache_t_w(i).a(NB_DCACHE-NB_LINE-1 DOWNTO 0)<=dcache_t_a & "00";
    dcache_t_w(i).dw <=dcache_t_dw(i);
    dcache_t_dr(i)<=dcache_t_r(i).dr;
  END GENERATE Gen_DCacheT;

  Gen_ICacheT: FOR i IN 0 TO WAY_ICACHE-1 GENERATE
    icache_t_w(i).req<='1';
    icache_t_w(i).be <=icache_t_wr;
    icache_t_w(i).wr <=to_std_logic(icache_t_wr/="0000");
    icache_t_w(i).a(31 DOWNTO NB_ICACHE-NB_LINE)<=(OTHERS => '0');  -- Bourrage
    icache_t_w(i).a(NB_ICACHE-NB_LINE-1 DOWNTO 0)<=icache_t_a & "00";
    icache_t_w(i).dw <=icache_t_dw(i);
    icache_t_dr(i)<=icache_t_r(i).dr;
  END GENERATE Gen_ICacheT;

  -- Accès snooping
  Gen_DCacheT2: FOR i IN 0 TO WAY_DCACHE-1 GENERATE
    dcache_t2_w(i).req<='1';
    dcache_t2_w(i).be <=dcache_t2_wr;
    dcache_t2_w(i).wr <=to_std_logic(dcache_t2_wr/="0000");
    dcache_t2_w(i).a(31 DOWNTO NB_DCACHE-NB_LINE)<=(OTHERS => '0');  -- Bourrage
    dcache_t2_w(i).a(NB_DCACHE-NB_LINE-1 DOWNTO 0)<=idcache_t2_a(NB_DCACHE-1 DOWNTO 2+NB_LINE) & "00";
    dcache_t2_w(i).dw <=dcache_t2_dw(i);
    dcache_t2_dr(i)<=dcache_t2_r(i).dr;
  END GENERATE Gen_DCacheT2;

  Gen_ICacheT2: FOR i IN 0 TO WAY_ICACHE-1 GENERATE
    icache_t2_w(i).req<='1';
    icache_t2_w(i).be <=icache_t2_wr;
    icache_t2_w(i).wr <=to_std_logic(icache_t2_wr/="0000");
    icache_t2_w(i).a(31 DOWNTO NB_ICACHE-NB_LINE)<=(OTHERS => '0');  -- Bourrage
    icache_t2_w(i).a(NB_ICACHE-NB_LINE-1 DOWNTO 0)<=idcache_t2_a(NB_DCACHE-1 DOWNTO 2+NB_LINE) & "00";
    icache_t2_w(i).dw <=icache_t2_dw(i);
    icache_t2_dr(i)<=icache_t2_r(i).dr;
  END GENERATE Gen_ICacheT2;

  Gem_DCacheT2: FOR i IN 0 TO WAY_DCACHE-1 GENERATE
    i_dcachetag:iram_dp
      GENERIC MAP (
        N => NB_DCACHE-NB_LINE, OCT=>false)
      PORT MAP (
        mem1_w    => dcache_t_w(i),
        mem1_r    => dcache_t_r(i),
        clk1      => clk,
        reset1_na => reset_na,
        mem2_w    => dcache_t2_w(i),
        mem2_r    => dcache_t2_r(i),
        clk2      => clk,
        reset2_na => reset_na
        );
  END GENERATE Gem_DCacheT2;

  Gem_ICacheT2: FOR i IN 0 TO WAY_ICACHE-1 GENERATE
    i_icachetag:iram_dp
      GENERIC MAP (
        N => NB_ICACHE-NB_LINE, OCT=>false)
      PORT MAP (
        mem1_w    => icache_t_w(i),
        mem1_r    => icache_t_r(i),
        clk1      => clk,
        reset1_na => reset_na,
        mem2_w    => icache_t2_w(i),
        mem2_r    => icache_t2_r(i),
        clk2      => clk,
        reset2_na => reset_na
        );
  END GENERATE Gem_ICacheT2;
  
  --###############################################################
  -- Interface bus de Données
  
  -- Process combinatoire bus DATA
  Comb_Data:PROCESS (data_etat,reset,dreg,
                     tw_op,tw_va,
                     data_tw_rdy,mmu_ctxr,mmu_cr_e,mmu_cr_dce,mmu_cr_nf,
                     data_w,data2_w,filling_d2,filldone,ext_dfill,
                     dcache_t_dr,dcache_d_dr,dcache_tmux,
                     dtlb,dtlb_hitv,dtlb_hit,data_jat,dtlb_mem,
                     ext_dr,ext_dreq_data,inst_dr,
                     tw_done_data,tw_err,tw_pte,dbusy,hitmaj,
                     cross_ack_c,data_ext_rdy) IS
    -- MMU
    VARIABLE us_v,ls_v,ls2_v : std_logic;   -- User/Super Load/Store
    VARIABLE c_v,m_v,s_v : std_logic;       -- Cachable Modified Supervisor
    VARIABLE wb_v,al_v : std_logic;         -- WriteBack / WriteAllocate
    VARIABLE ft_v : unsigned(2 DOWNTO 0);   -- Fault Type MMU
    VARIABLE pa_v : unsigned(35 DOWNTO 0);  -- Physical Address
    VARIABLE tlb_hit_v,tlb_inval_v : std_logic;     -- TLB Hit /éligible FLUSH
    VARIABLE tlb_hitv_v : std_logic;
    VARIABLE ig_v,ig2_v : std_logic;
    -- Cache
    VARIABLE tlb_sel_v      : type_tlb;  -- TLB sélectionné pour un flush
    VARIABLE cache_hit_v    : std_logic;
    VARIABLE cache_tag_v,cache_d_v : uv32;
    VARIABLE vcache_hit_v   : unsigned(0 TO WAY_DCACHE-1); -- Cache Hit
    VARIABLE nohit_v : natural RANGE 0 TO WAY_DCACHE-1;
    VARIABLE tags_v : arr_uv32(0 TO WAY_DCACHE-1); -- Tag cache fill
    VARIABLE rmaj_v : boolean;
    VARIABLE dreq_v : std_logic;
    VARIABLE dout_v : type_push;
    VARIABLE na_v,readlru_v,write_tag_v : std_logic;
    VARIABLE wthru_v,wback_v : std_logic;
    VARIABLE hist_v : uv8;
    VARIABLE hitv_v,hitm_v,hits_v : std_logic;
    
  BEGIN    
    -------------------------------------------------------------
    -- Recherche dans les TLBs pendant que les adresses sont positionnées (§1)
    IF NOT MMU_DIS THEN
      FOR I IN 0 TO N_DTLB-1 LOOP
        tlb_test(tlb_hit_v,tlb_inval_v,dtlb(I),data_w.a,data_w.asi(0),
                 mmu_ctxr,'0');
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
      wb_v:='0';
      al_v:='0';
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
      wb_v:='0';
      al_v:='0';
    ELSE
      -- MMU Normal
      tlb_trans(ft_v,pa_v,c_v,m_v,s_v,wb_v,al_v,
                tlb_sel_v,data2_w.a,ls2_v,us_v,'0');
    END IF;
    
    data_ft_c<=ft_v;                    -- FSR.FaultType
    data_at_c<=ls2_v & '0' & us_v;      -- FSR.AccessType
    
    -------------------------------------------------------------------------
    -- Test hit & flush cache (§2)
    -- FLUSH : Eligible pour un FLUSH.
    --         Le Write Back fonctionne seulement avec PT
    -- INVAL : Eligible pour une Invalidation
    cache_tag_v:=x"0000_0000";
    cache_d_v  :=x"0000_0000";
    FOR i IN 0 TO WAY_DCACHE-1 LOOP
      ptag_test(vcache_hit_v(i),ig_v,ig2_v,
                dcache_t_dr(i),pa_v,data2_w.asi,NB_DCACHE);
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
             
    ptag_decode(hitv_v,hitm_v,hits_v,cache_tag_v);
    
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
    
    wthru_v:='0';
    wback_v:='0';
    readlru_v:='0';
    write_tag_v:='0';
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
                  data_ext_c.twop<=PROBE;
                  IF dbusy='0' THEN
                    -- Ecriture FLUSH Purge un ou plusieurs TLB data et/ou code
                    -- Lecture PROBE Lit un TLB data, ou déclenche un Tablewalk
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
                  IF dbusy='0' THEN
                    -- Si accès atomique, force fill pour accès LOCK
                    IF ls2_v='1' THEN
                      data_ext_c.op<=FILLMOD;
                      data_ext_req_c<='1';
                      IF data_ext_rdy='1' THEN
                        data_etat_c<=sEXT_READ;
                        na_v:='1';
                      END IF;
                    --IF hits_v='1' AND ls2_v='1' THEN
                    --  -- Si SHARED and LOADSTORE => EXCLUSIVE FIRST
                    --  data_txt<="EXT_INVAL";
                    --  data_ext_req_c<='1';
                    --  data_ext_c.op<=EXCLUSIVE;
                    --  IF data_ext_rdy='1' THEN
                    --    data_etat_c<=sWAIT_SHARE;
                    --  END IF;
                    ELSE
                      dreq_v:='1';
                      na_v:=to_std_logic(WAY_DCACHE=1 OR NOT rmaj_v);
                      readlru_v:=NOT na_v;
                      data_clr_c<=NOT na_v;
                    END IF;
                  END IF;
                  data_txt<="CACHE_LEC";
                  
                  ---------------------------------
                ELSIF (mmu_cr_e='1' OR MMU_DIS) AND tlb_hitv_v='1' AND
                  ft_v=FT_NONE AND c_v='1' AND
                  mmu_cr_dce='1' AND cache_hit_v='0' AND ls_v='0' THEN
                  -- Cache fill pour une lecture
                  IF ls2_v='1' THEN
                    -- Si LOADSTORE => FILL EXCLUSIVE
                    data_ext_c.op<=FILLMOD;
                  ELSE
                    data_ext_c.op<=FILL;
                  END IF;
                  data_txt<="FILL READ";
                  IF dbusy='0' THEN
                    data_ext_req_c<='1';
                    IF data_ext_rdy='1' THEN
                      data_etat_c<=sEXT_READ;
                      na_v:='1';
                    END IF;
                  END IF;
                  
                --#####################################################
                --Ecritures
                ELSIF ls_v='1' AND ((mmu_cr_e='0' AND NOT MMU_DIS) OR
                    (tlb_hitv_v='1' AND ft_v=FT_NONE
                     AND m_v='1' AND mmu_cr_dce='0') OR
                    (tlb_hitv_v='1' AND ft_v=FT_NONE AND m_v='1'
                     AND c_v='0' AND mmu_cr_dce='1') OR
                    (tlb_hitv_v='1' AND ft_v=FT_NONE AND m_v='1' AND
                     c_v='1' AND mmu_cr_dce='1' AND cache_hit_v='0' AND
                     al_v='0')) THEN
                  -- Ecriture externe : Pas de cache, pas de MMU, non cacheable
                  -- ou pas dans le cache et "write without allocate"
                  data_ext_c.op<=SINGLE;
                  IF dbusy='0' THEN
                    data_ext_req_c<='1';
                    IF data_ext_rdy='1' THEN -- Ecriture postée
                      dout_v.code:=PB_OK;
                      dreq_v:='1';
                      data_clr_c<='1';
                    END IF;
                    data_txt<="ECRIT_EXT";
                  END IF;
                  
                  ---------------------------------
                ELSIF (mmu_cr_e='1' OR MMU_DIS) AND tlb_hitv_v='1' AND
                  ft_v=FT_NONE AND
                  m_v='1' AND c_v='1' AND mmu_cr_dce='1' AND cache_hit_v='1' AND
                  ls_v='1' THEN
                  -- Si écriture, on empêche l'acquittement data_r_c.ack du
                  -- second accès pendant le cycle zéro !
                  data_ext_c.op<=SINGLE;
                  IF dbusy='0' THEN
                    IF hits_v='1' THEN
                      -- Si SHARED, il faut d'abord inval. les autres caches
                      data_txt<="EXT_INVAL";
                      data_ext_req_c<='1';
                      data_ext_c.op<=EXCLUSIVE;
                      IF data_ext_rdy='1' THEN
                        data_etat_c<=sWAIT_SHARE;
                      END IF;
                      
                    ELSIF wb_v='0' THEN
                      -- Ecriture en cache et écriture externe (Write Through)
                      data_txt<="WRITE_TRU";
                      wthru_v:='1';
                      data_ext_req_c<='1';
                      IF data_ext_rdy='1' THEN -- Ecriture postée !
                        dreq_v:='1';
                        data_clr_c<='1';
                      END IF;
                      
                    ELSE
                      -- Ecriture en cache (Pour cache Write Back)
                      data_txt<="CACHE_WRI";
                      wback_v:='1';
                      dreq_v:='1';
                      data_clr_c<='1';
                    END IF;
                  END IF;
                  
                  ---------------------------------
                ELSIF ls_v='1' AND tlb_hitv_v='1' AND ft_v=FT_NONE AND m_v='1'
                  AND mmu_cr_dce='1' AND c_v='1'
                  AND cache_hit_v='0' AND al_v='1' THEN
                  data_ext_c.pw.mode<=PB_MODE_RD;
                  data_ext_c.op<=FILLMOD; -- RWITM
                  -- Cache fill avant une écriture, parceque
                  -- "write with allocate" et ligne non modifiée. RWITM
                  data_txt<="FILLWRITE";
                  IF dbusy='0' THEN
                    data_ext_req_c<='1';
                    IF data_ext_rdy='1' THEN
                      data_etat_c<=sWAIT_FILL;
                    END IF;
                  END IF;
                  
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
                dout_v.code:=PB_OK;
                IF dbusy='0' THEN
                  -- <AFAIRE> Sélection voie selon adresse...
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
                 ASI_CACHE_FLUSH_LINE_COMBINED_ANY |
                 ASI_CACHE_FLUSH_LINE_INSTRUCTION_PAGE |
                 ASI_CACHE_FLUSH_LINE_INSTRUCTION_SEGMENT |
                 ASI_CACHE_FLUSH_LINE_INSTRUCTION_REGION |
                 ASI_CACHE_FLUSH_LINE_INSTRUCTION_CONTEXT |
                 ASI_CACHE_FLUSH_LINE_INSTRUCTION_USER |
                 ASI_CACHE_FLUSH_LINE_INSTRUCTION_ANY =>
              -- Flush cache I&D. Write Back lignes modifiées puis invalidation
              
              -- Déclenche WBACK DATA.
              -- Les FLUSH ne purgent qu'une ligne à la fois !!!
              -- Broadcast flush vers les autres procs
              data_ext_c.op<=FLUSH;
              data_ext_c.pw.mode<=PB_MODE_RD;  -- Utile ?
              IF ls_v='1' THEN
                IF dbusy='0' THEN
                  data_ext_req_c<='1';
                  IF data_ext_rdy='1' THEN
                    dreq_v:='1';
                    na_v:='1';
                    dout_v.code:=PB_OK;
                  END IF;
                END IF;
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
              data_ext_c.op<=SINGLE;
              IF dbusy='0' THEN
                data_ext_req_c<='1';
                IF ls_v='0' THEN
                  -- Lecture
                  IF data_ext_rdy='1' THEN
                    data_etat_c<=sEXT_READ;
                    na_v:='1';
                  END IF;
                ELSE
                  -- Ecriture postée
                  IF data_ext_rdy='1' THEN
                    na_v:='1';
                    dreq_v:='1';
                  END IF;
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
        
        ----------------------------------------------------
      WHEN sWAIT_FILL =>
        -- Attente cache fill avant une écriture
        IF filldone='1' AND ext_dfill='1' THEN
          data_etat_c<=sWAIT_FILL2; 
        END IF;
        
      WHEN sWAIT_FILL2 =>
        IF dbusy='0' THEN
          wback_v:='1';
          dreq_v:='1';
          data_clr_c<='1';
          data_etat_c<=sOISIF;
        END IF;
        
        ----------------------------------------------------
      WHEN sWAIT_SHARE =>
        IF hitmaj='1' THEN
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
    tag_maj(tags_v,x"00000000",dcache_tmux,hist_v,readlru_v,wthru_v,wback_v,
            '0','0','0',nohit_v,0,0);
    
    dcache_d_a <=data2_w.a(NB_DCACHE-1 DOWNTO 2);
    dcache_d_dw<=data2_w.d;
    dcache_d_wr<=(OTHERS => "0000");
    dcache_t_a <=data2_w.a(NB_DCACHE-1 DOWNTO 2+NB_LINE);
    dcache_t_dw<=tags_v;
    dcache_t_wr<="0000";
    
    xxx_dwthru<=wthru_v;
    xxx_dwback<=wback_v;
    xxx_dreadlru<=readlru_v;
      
    IF wthru_v='1' OR wback_v='1' OR readlru_v='1' THEN
      -- Second cycle. écriture simple. On modifie les données pas les tags
      IF wthru_v='1' OR wback_v='1' THEN
        dcache_d_wr(nohit_v)<=data2_w.be;
      END IF;
      dcache_t_wr<="1111";
      
    ELSIF write_tag_v='1' THEN -- ASI spécial màj tags
      -- Second cycle. écriture tags. On modifie les tags, pas les données
      dcache_t_dw<=(OTHERS => data2_w.d);
      dcache_t_wr<="1111";
      
    ELSIF na_v='1' THEN
      -- Lecture data & tag
      dcache_d_a <=data_w.a(NB_DCACHE-1 DOWNTO 2);
      dcache_t_a <=data_w.a(NB_DCACHE-1 DOWNTO 2+NB_LINE);
      
    END IF;
    
  END PROCESS Comb_Data;
  
  data_r<=data_r_c;
  
  -------------------------------------------------------------------------
  -- Process synchrone bus DATA
  Sync_Data:PROCESS (clk, reset_na)
    VARIABLE tlb_trouve : std_logic;
    VARIABLE no : natural RANGE 0 TO N_DTLB-1;
    VARIABLE hist_maj_v : std_logic;
  BEGIN
    IF reset_na='0' THEN
      dtlb_cpt<=0;
      data_etat<=sOISIF;
      data2_w.req<='0';
      FOR I IN 0 TO N_DTLB-1 LOOP
        dtlb(I).v<='0';
      END LOOP;
      data_jat<='0';
      dtlb_twm<='0';
      dtlb_hist<=x"00";
    ELSIF rising_edge(clk) THEN

      IF (data_etat=sWAIT_SHARE) AND xxx_dexr<250 THEN
        xxx_dexr<=xxx_dexr+1;
      ELSE
        xxx_dexr<=0;
      END IF;
      xxx_dexmax<=to_std_logic(xxx_dexr=250);
      
      -------------------------------------------
      -- Conflit potentiel entre accès EXT et accès interne
      dbusy<=smp_r.busy
              AND to_std_logic(
                dcache_t_a(NB_DCACHE-NB_LINE-1 DOWNTO 2)=
                idcache_t2_a(NB_DCACHE-1 DOWNTO 2+NB_LINE));
      
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
      IF dcache_t2_wr="1111" AND -- <VERIFIER> <AVOIR> <Bus addresses>
        dcache_a_mem = idcache_t2_a(NB_DCACHE-NB_LINE-1 DOWNTO 2) THEN
        dcache_t_mem<=dcache_t2_dw;
      ELSIF dcache_blo_c='1' THEN
        dcache_t_mem<=dcache_t_dr;
        dcache_a_mem<=dcache_t_a2;
      END IF;
      
      dcache_t_a2<=dcache_t_a;
      
      -------------------------------------------
      -- Registres
      IF data_w.a(11 DOWNTO 8)=x"0" THEN
        -- MMU Control Register
        IF CPUTYPE=CPUTYPE_MS2 THEN
          dreg<=MMU_IMP_VERSION & x"00" &
                 mmu_cr_dsnoop & mmu_cr_bm & "00" &
                 "00" & mmu_cr_ice & mmu_cr_dce &
                 '0' & mmu_cr_l2tlb & "00" & --mmu_cr_wb &
                 to_unsigned(CPUID,2) & mmu_cr_nf & mmu_cr_e;
        ELSE
          dreg<=MMU_IMP_VERSION & x"00" &
                 xxx_dexmax & mmu_cr_dsnoop & mmu_cr_bm & '0' &
--                 '0' & mmu_cr_dsnoop & mmu_cr_bm & '0' &
                 "10" & mmu_cr_ice & mmu_cr_dce &
                 '0' & mmu_cr_l2tlb & "00" & --mmu_cr_wb &
                 to_unsigned(CPUID,2) & mmu_cr_nf & mmu_cr_e;
        END IF;
        
      ELSIF data_w.a(11 DOWNTO 8)=x"1" AND NOT MMU_DIS THEN
        -- Context Table Pointer Register
        dreg<=mmu_ctxtpr(35 DOWNTO 6) & "00";
        
      ELSIF data_w.a(11 DOWNTO 8)=x"2" AND NOT MMU_DIS THEN
        -- Context Register
        dreg(31 DOWNTO NB_CONTEXT)<=(OTHERS => '0');
        dreg(NB_CONTEXT-1 DOWNTO 0)<=mmu_ctxr;
        
      ELSIF data_w.a(11 DOWNTO 8)=x"3" AND NOT MMU_DIS THEN
        -- Fault Status Register, update on read
        dreg<="00000000000000" & MMU_FSR_EBE & mmu_fsr_l &
                   mmu_fsr_at & mmu_fsr_ft & mmu_fsr_fav & mmu_fsr_ow;
        
      ELSIF data_w.a(11 DOWNTO 8)=x"B" AND NOT MMU_DIS THEN
        -- Fault Status Register, no update
        dreg<="00000000000000" & MMU_FSR_EBE & mmu_fsr_l &
                   mmu_fsr_at & mmu_fsr_ft & mmu_fsr_fav & mmu_fsr_ow;
        
      ELSIF data_w.a(11 DOWNTO 8)=x"C" AND NOT MMU_DIS THEN
        -- Temp Register
        dreg<=mmu_tmpr;
        
      ELSIF data_w.a(11 DOWNTO 8)=x"D" AND NOT MMU_DIS THEN
        -- Sys Conf Register
        dreg<=SYSCONF;
        
      ELSIF data_w.a(11 DOWNTO 8)=x"4" AND NOT MMU_DIS THEN
        -- Fault Address Register
        dreg<=mmu_far & "00";
      ELSE
        -- MMU Control Register
       IF CPUTYPE=CPUTYPE_MS2 THEN
          dreg<=MMU_IMP_VERSION & x"00" &
                 mmu_cr_dsnoop & mmu_cr_bm & "0000" & mmu_cr_ice & mmu_cr_dce &
                 '0' & mmu_cr_l2tlb & "00" & --mmu_cr_wb &
                 to_unsigned(CPUID,2) & mmu_cr_nf & mmu_cr_e;
        ELSE
          dreg<=MMU_IMP_VERSION & x"00" &
                 '0' & mmu_cr_dsnoop & mmu_cr_bm & "0" &
                 "10" & mmu_cr_ice & mmu_cr_dce &
                 '0' & mmu_cr_l2tlb & "00" & ---mmu_cr_wb &
                 to_unsigned(CPUID,2) & mmu_cr_nf & mmu_cr_e;
        END IF;
          
      END IF;
      IF data_na_c='0' THEN
        dreg<=dreg;
      END IF;
      
      -------------------------------------------
      -- Machine à états
      data_etat<=data_etat_c;
    END IF;
  END PROCESS Sync_Data;
  
  dcache_tmux<=dcache_t_dr WHEN dcache_blo_c='1' ELSE dcache_t_mem;
  
  --###############################################################
  -- Interface bus d' Instructions

  -- Types d'accès :
  --   - Exécution code USER / SUPER
  --   - Bypass lecture et écriture code USER / SUPER
  --   - Bypass flush ICACHE (plus tard, aussi le probe contenu & tags)
  --   - Bypass flush ITLB
  
  Comb_Inst:PROCESS(inst_etat,reset,tw_op,inst_tw_rdy,
                    mmu_ctxr,mmu_cr_bm,mmu_cr_e,mmu_cr_ice,mmu_cr_nf,
                    inst_w,imux_w,imux2_w,data2_w,filling_i2,
                    ext_ifill,icache_t_dr,icache_d_dr,icache_tmux,
                    itlb,itlb_hitv,itlb_hit,inst_cont,
                    inst_jat,itlb_mem,imux2_cx,imux3_cx,
                    inst_ext_rdy,ext_dr,
                    ext_dreq_inst,tw_pte,tw_done_inst,tw_err,ibusy,
                    cross_req_c,cross) IS
    -- MMU
    VARIABLE us_v,ls_v : std_logic;         -- User/Super Load/Store
    VARIABLE c_v,m_v,s_v : std_logic;       -- Cachable Modified Super
    VARIABLE wb_v,al_v : std_logic;         -- WriteBack / WriteAllocate
    VARIABLE ft_v : unsigned(2 DOWNTO 0);   -- Fault Type MMU
    VARIABLE pa_v : unsigned(35 DOWNTO 0);  -- Physical Address
    VARIABLE tlb_hit_v,tlb_inval_v : std_logic;     -- TLB Hit /éligible FLUSH
    VARIABLE tlb_hitv_v : std_logic;
    VARIABLE ig_v,ig2_v : std_logic;
    
    -- Cache
    VARIABLE tlb_sel_v      : type_tlb;  -- TLB sélectionné pour un flush
    VARIABLE cache_hit_v    : std_logic;
    VARIABLE cache_tag_v,cache_d_v : uv32;
    VARIABLE vcache_hit_v   : unsigned(0 TO WAY_ICACHE-1); -- Cache HIT
    VARIABLE nohit_v : natural RANGE 0 TO WAY_DCACHE-1;
    VARIABLE tags_v : arr_uv32(0 TO WAY_ICACHE-1); -- Tag cache fill
    VARIABLE cross_v : std_logic;    
    VARIABLE rmaj_v : boolean;
    VARIABLE ireq_v : std_logic;
    VARIABLE iout_v : type_push;
    VARIABLE na_v,wthru_v,readlru_v,write_tag_v : std_logic;
    VARIABLE hist_v : uv8;
    
  BEGIN
    -------------------------------------------------------------
    -- Recherche dans les TLBs pendant que les adresses sont positionnées
    IF NOT MMU_DIS THEN
      FOR I IN 0 TO N_ITLB-1 LOOP
        tlb_test(tlb_hit_v,tlb_inval_v,itlb(I),imux_w.a,imux_w.asi(0),
                 mmu_ctxr,'0');
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
      wb_v:='0';
      al_v:='0';
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
      wb_v:='0';
      al_v:='0';
    ELSE
      -- MMU Normal
      tlb_trans(ft_v,pa_v,c_v,m_v,s_v,wb_v,al_v,
                tlb_sel_v,imux2_w.a,ls_v,us_v,'1');
    END IF;
    
    inst_ft_c<=ft_v;                    -- FSR.FaultType
    inst_at_c<=ls_v & '1' & us_v;       -- FSR.AccessType

    -------------------------------------------------------------------------
    -- Test hit & inval cache (§2)
    -- INVAL : Eligible pour une Invalidation
    -- Pas de write back pour les instructions, donc pas de FLUSH
    cache_tag_v:=x"0000_0000";
    cache_d_v  :=x"0000_0000";
    FOR i IN 0 TO WAY_ICACHE-1 LOOP
      ptag_test(vcache_hit_v(i),ig_v,ig2_v,
                icache_t_dr(i),pa_v,imux2_w.asi,NB_ICACHE);
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
    
    wthru_v:='0';
    readlru_v:='0';
    write_tag_v:='0';
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
                iout_v.cx:=imux2_cx;
                IF ls_v='1' THEN
                  ireq_v:='1';
                  na_v:='1';
                ELSE
                  inst_ext_c.twop<=PROBE;
                  IF ibusy='0' THEN
                    inst_tw_req_c<='1';
                    IF inst_tw_rdy='1' THEN
                      na_v:='1';
                      inst_etat_c<=sTABLEWALK;
                    END IF;
                  END IF;
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
                inst_ext_c.twop<=LS;
                inst_tw_req_c<='1';
                IF inst_tw_rdy='1' THEN
                  inst_etat_c<=sTABLEWALK;
                END IF;
                inst_txt<="TABLEWALK";
                
                ---------------------------------
              ELSIF mmu_cr_e='1' AND tlb_hitv_v='1' AND ft_v=FT_NONE AND
                m_v='0' AND ls_v='1' THEN
                -- Tablewalk pour positionner le bit Modified avant une écriture
                inst_ext_c.twop<=LS;
                inst_tw_req_c<='1';
                itlb_twm_c<='1';
                IF inst_tw_rdy='1' THEN
                  inst_etat_c<=sTABLEWALK;
                END IF;
                inst_txt<="TABLE_MOD";
                
                ---------------------------------
              ELSIF (mmu_cr_e='1' OR MMU_DIS) AND
                tlb_hitv_v='1' AND ft_v/=FT_NONE THEN
                -- Erreur d'accès : Violation de privilège ou de protection
                -- <AVOIR> Test 'No Fault' CR : Cas particulier pour ASI=09
                IF mmu_cr_nf='0' THEN -- MMU ERROR
                  iout_v.code:=PB_FAULT;
                ELSE
                  iout_v.code:=PB_OK;
                END IF;
                iout_v.cx:=imux2_cx;
                IF ibusy='0' THEN
                  mmu_fault_inst_acc_c<='1';
                  ireq_v:='1';
                  na_v:='1';
                END IF;
                inst_txt<="MMU_ERROR";

                --#####################################################
                --Lectures Cache
              ELSIF ls_v='0' AND ((mmu_cr_e='0' AND NOT MMU_DIS) OR
                 (tlb_hitv_v='1' AND ft_v=FT_NONE AND mmu_cr_ice='0') OR
                 (tlb_hitv_v='1' AND ft_v=FT_NONE AND mmu_cr_ice='1' AND
                  c_v='0')) THEN
                -- Lecture externe : Pas de cache, Pas de MMU ou non cacheable
                inst_ext_c.op<=SINGLE;
                inst_ext_req_c<='1';
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
                iout_v.cx:=imux2_cx;
                IF ibusy='0' THEN
                  ireq_v:='1';
                  na_v:=to_std_logic(WAY_ICACHE=1 OR NOT rmaj_v);
                  readlru_v:=NOT na_v;
                  inst_clr_c<=NOT na_v;
                END IF;
                inst_txt<="CACHE_LEC";
                
                ---------------------------------
              ELSIF (mmu_cr_e='1' OR MMU_DIS) AND tlb_hitv_v='1' AND
                ft_v=FT_NONE AND
                c_v='1' AND mmu_cr_ice='1' AND cache_hit_v='0' AND ls_v='0' THEN
                -- Cache fill pour une lecture
                inst_ext_c.op<=FILL;
                IF ibusy='0' THEN
                  inst_ext_req_c<='1';
                  IF inst_ext_rdy='1' THEN
                    inst_etat_c<=sEXT_READ;
                    na_v:='1';
                  END IF;
                END IF;
                inst_txt<="FILL READ";
                
                --#####################################################
                --Écritures Cache
              ELSIF ls_v='1' AND ((mmu_cr_e='0' AND NOT MMU_DIS) OR
                 (tlb_hitv_v='1' AND ft_v=FT_NONE
                               AND m_v='1' AND mmu_cr_ice='0') OR
                 (tlb_hitv_v='1' AND ft_v=FT_NONE AND m_v='1'
                               AND c_v='0' AND mmu_cr_ice='1') OR
                 (tlb_hitv_v='1' AND ft_v=FT_NONE AND m_v='1' AND c_v='1' AND
                  mmu_cr_ice='1' AND cache_hit_v='0')) THEN
                -- Ecriture externe : Pas de cache, pas de MMU, non cacheable
                -- ou pas dans le cache.
                inst_ext_c.op<=SINGLE;
                iout_v.cx:=imux2_cx;
                IF ibusy='0' THEN
                  inst_ext_req_c<='1';
                  IF inst_ext_rdy='1' THEN -- Ecriture postée
                    ireq_v:='1';
                    inst_clr_c<='1';
                  END IF;
                END IF;
                inst_txt<="ECRIT_EXT";
                
                ---------------------------------
              ELSIF (mmu_cr_e='1' OR MMU_DIS) AND tlb_hitv_v='1' AND
                ft_v=FT_NONE AND
                m_v='1' AND c_v='1' AND mmu_cr_ice='1' AND cache_hit_v='1' AND
                ls_v='1' THEN
                -- Ecriture en cache et écriture externe (Write Through)
                inst_ext_c.op<=SINGLE;
                iout_v.cx:=imux2_cx;
                IF ibusy='0' THEN
                  wthru_v:='1';
                  -- Si écriture, on empêche l'acquittement inst_r_c.ack du
                  -- second accès pendant le cycle zéro !               
                  inst_ext_req_c<='1';
                  IF inst_ext_rdy='1' THEN -- Ecriture postée !
                    ireq_v:='1';
                    inst_clr_c<='1';
                  END IF;
                END IF;
                inst_txt<="WRITE_TRU";
                
                ---------------------------------
              ELSE
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
                IF ibusy='0' THEN
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
                END IF;
              ELSE
                ireq_v:='1';
                na_v:='1';
              END IF;
              
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
      imux_w.req<=inst_w.req;
      imux_cx<='0';
    END IF;
    
    cross_c<=cross_v;
    inst_dr_c<=iout_v;
    inst_na_c<=na_v;
    
    -------------------------------------------------------------
    -- Contrôle bus cache, adresses & données à écrire
    -- Par défaut on fait une lecture en même temps que l'accès TAG.
    -- Si écriture ou inval, il faut faire l'écriture 1 cycle après
    
    -- Seulement Modif tags RD / WTHRU / INVAL
    tag_maj(tags_v,x"00000000",icache_tmux,hist_v,readlru_v,wthru_v,'0',
            '0','0','0',nohit_v,0,0);
    
    icache_d_a <=imux2_w.a(NB_ICACHE-1 DOWNTO 2);
    icache_d_dw<=imux2_w.d;
    icache_d_wr<=(OTHERS => "0000");
    icache_t_a <=imux2_w.a(NB_ICACHE-1 DOWNTO 2+NB_LINE);
    icache_t_dw<=tags_v;
    icache_t_wr<="0000";
      
    IF wthru_v='1' OR readlru_v='1' THEN
      -- Second cycle,écriture simple. On modifie les données, pas les tags
      IF wthru_v='1' THEN
        icache_d_wr(nohit_v)<=imux2_w.be;
      END IF;
      icache_t_wr<="1111";
      
    ELSIF write_tag_v='1' THEN -- ASI spécial màj tags
      -- Second cycle. écriture tags. On modifie les tags, pas les données
      icache_t_dw<=(OTHERS => imux2_w.d);
      icache_t_wr<="1111";

    ELSIF na_v='1' THEN
      -- Lecture data & tag
      icache_d_a <=imux_w.a(NB_ICACHE-1 DOWNTO 2);
      icache_t_a <=imux_w.a(NB_ICACHE-1 DOWNTO 2+NB_LINE);
      
    END IF;
    
  END PROCESS Comb_Inst;

  inst_r<=inst_r_c;
  
  -------------------------------------------------------------------------
  -- Process synchrone bus INST
  Sync_Inst:PROCESS (clk, reset_na)
    VARIABLE tlb_trouve : std_logic;
    VARIABLE no : natural RANGE 0 TO N_ITLB-1;
    VARIABLE hist_maj_v : std_logic;
  BEGIN
    IF reset_na='0' THEN
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
    ELSIF rising_edge(clk) THEN
      -------------------------------------------
      -- Accès en continu
      IF filldone='1' OR imux2_w.req='0' OR imux2_w.cont='0' OR
        ext_ifill='0' THEN
        inst_cont<='0';
      ELSIF ext_dreq_inst='1' THEN
        inst_cont<='1';
      END IF;
      
      -------------------------------------------
      -- Conflit potentiel entre accès EXT et accès interne
      ibusy<=smp_r.busy
              AND to_std_logic(
                icache_t_a(NB_ICACHE-NB_LINE-1 DOWNTO 2)=
                idcache_t2_a(NB_ICACHE-1 DOWNTO 2+NB_LINE));
      
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
      IF icache_t2_wr="1111" AND
        icache_a_mem = idcache_t2_a(NB_ICACHE-NB_LINE-1 DOWNTO 2) THEN
        icache_t_mem<=icache_t2_dw;
      ELSIF icache_blo_c='1' THEN
        icache_t_mem<=icache_t_dr;
        icache_a_mem<=icache_t_a2;
      END IF;

      icache_t_a2<=icache_t_a;
      
      -------------------------------------------
      -- Machine à états
      inst_etat<=inst_etat_c;
      cross<=cross_c;
    END IF;
  END PROCESS Sync_Inst;

  icache_tmux<=icache_t_dr WHEN icache_blo_c='1' ELSE icache_t_mem;  

  --###############################################################
  -- Gestion Registres MMU
  Sync_Regs:PROCESS (clk, reset_na)
  BEGIN
    IF reset_na='0' THEN
      mmu_cr_e<='0';
      mmu_cr_nf<='0';
      mmu_cr_dce<='0';
      mmu_cr_ice<='0';
      mmu_cr_l2tlb<='0';
      --mmu_cr_wb<='0';
--      mmu_cr_aw<='0';
      mmu_cr_bm<=to_std_logic(BOOTMODE);
      mmu_fsr_ow<='0';
      mmu_fsr_ft<=FT_NONE;
      mmu_fsr_fav<='0';
      
    ELSIF rising_edge(clk) THEN
      -------------------------------------------

--        MicroSparc2                 SuperSparc                 TEMLIB
--  0      EN : Enable MMU            EN : Enable MMU            EN
--  1      NF : No Fault              NF : No Fault              NF
--  2       ----                      ----                       MID : CPU num
--  3       ----                      ----                       MID : CPU num 
--  4       ----                      ----                       WB  : Write Back Enable
--  5       ----                      ----                       AW  : Allocate On Write
--  6       ----                      ----                       L2TLB : L2 TLB cache ena
--  7     SA :  Store Allocate        PSO : Partial Store Ordering
--  8     DE :  Data Cache Enable     DE : Data Cache Enable    DE : Data Cache Enable
--  9     IE :  Inst Cache Enable     IE : Inst Cache Enable    IE : Inst Cache Enable
-- 10      RC : Refresh control       SB : Store Buffer
-- 11      RC                         mb : Mbus Mode = 1 si no MXCC
-- 12      RC                         PE : Parity Enable
-- 13      RC                         BT : Boot Mode            BM : Boot Mode (multi)
-- 14     BM : Boot Mode              SE : Snoop Enable         BM : Boot Mode (simple) / Snoop Ena
-- 15     AC : Alternate Cacheabli    AC : Alternate Cacheabli
-- 16     AP : Graphic page mode      TC : TW cacheable
-- 17     PC : Parity Control         ----
-- 18     PE : Parity Enable          ----
-- 19     PMC : Page Mode Control     ----
-- 20     PMC : (DRAM)                ----
-- 21     BF : Branch Folding         ----
-- 22     WP : Watchpoint enable      ----
-- 23     ST : Soft Tablewalk         ----

      -- Registres MMU
      -- Ecriture MMU Control Register
      IF CPUTYPE=CPUTYPE_MS2 THEN
        IF mmu_cr_maj='1' THEN
          mmu_cr_e     <=data2_w.d(0) AND NOT to_std_logic(MMU_DIS);
          mmu_cr_nf    <=data2_w.d(1);
          mmu_cr_wb    <=data2_w.d(4);
          mmu_cr_aw    <=data2_w.d(5);
          mmu_cr_l2tlb <=data2_w.d(6) AND to_std_logic(L2TLB);
          mmu_cr_dce   <=data2_w.d(8) AND cachena;
          mmu_cr_ice   <=data2_w.d(9) AND cachena;
          mmu_cr_bm    <=data2_w.d(14) AND to_std_logic(BOOTMODE);
          mmu_cr_dsnoop<=data2_w.d(15) AND cachena; -- <SUPPRIMER> Monoproc unioqement
          mmu_cr_isnoop<=data2_w.d(15) AND cachena; -- <SUPPRIMER> Monoproc unioqement
        END IF;
      ELSE -- SS
        IF mmu_cr_maj='1' THEN
          mmu_cr_e     <=data2_w.d(0) AND NOT to_std_logic(MMU_DIS);
          mmu_cr_nf    <=data2_w.d(1);
          mmu_cr_wb    <=data2_w.d(4);
          mmu_cr_aw    <=data2_w.d(5);
          mmu_cr_l2tlb <=data2_w.d(6) AND to_std_logic(L2TLB);
          mmu_cr_dce   <=data2_w.d(8) AND cachena;
          mmu_cr_ice   <=data2_w.d(9) AND cachena;
          mmu_cr_bm    <=data2_w.d(13) AND to_std_logic(BOOTMODE);
          mmu_cr_dsnoop<=data2_w.d(14) AND cachena;
          mmu_cr_isnoop<=data2_w.d(14) AND cachena;
        END IF;
      END IF;
      
      mmu_cr_wb <= wback;
      mmu_cr_aw <= '0'; --aow;
      
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
        IF mmu_tw_ft/=FT_INVALID OR mmu_tw_di='0' OR mmu_fsr_fav='0' THEN
          mmu_fclass<=WALK;
          mmu_fsr_l<=mmu_tw_st;           -- Level / Short Translation
          IF mmu_tw_di='0' THEN
            mmu_fsr_at<=data_at_c;
          ELSE
            mmu_fsr_at<=inst_at_c;
          END IF;
          mmu_fsr_ft<=mmu_tw_ft;             -- Fault Type
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
    END IF;
  END PROCESS Sync_Regs;
  
  --###############################################################
  -- Tablewalk
  i_mcu_tw: ENTITY work.mcu_tw
    GENERIC MAP (
      NB_CONTEXT => NB_CONTEXT,
      WBSIZE     => WBSIZE,
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
      tw_ext_ack     => tw_ext_ack,
      ext_dreq_tw    => ext_dreq_tw,
      ext_dr         => ext_dr,
      mmu_cr_nf      => mmu_cr_nf,
      mmu_cr_l2tlb   => mmu_l2tlbena,
      mmu_cr_wb      => mmu_cr_wb,
      mmu_cr_aw      => mmu_cr_aw,
      mmu_ctxtpr     => mmu_ctxtpr,
      mmu_ctxtpr_maj => mmu_ctxtpr_maj,
      mmu_ctxr       => mmu_ctxr,
      mmu_ctxr_maj   => mmu_ctxr_maj,
      mmu_tw_fault   => mmu_tw_fault,
      mmu_tw_ft      => mmu_tw_ft,
      mmu_tw_st      => mmu_tw_st,
      mmu_tw_di      => mmu_tw_di,
      reset_na       => reset_na,
      clk            => clk);

  mmu_l2tlbena <= mmu_cr_l2tlb AND l2tlbena;
  
  --###############################################################
  
  i_mcu_multi_ext: ENTITY work.mcu_multi_ext
    generic map (
      NB_LINE     => NB_LINE,
      BLEN_DCACHE => BLEN_DCACHE,
      WAY_DCACHE  => WAY_DCACHE,
      NB_DCACHE   => NB_DCACHE,
      BLEN_ICACHE => BLEN_ICACHE,
      WAY_ICACHE  => WAY_ICACHE,
      NB_ICACHE   => NB_ICACHE)
    port map (
      data_ext_c     => data_ext_c,
      data_ext_req_c => data_ext_req_c,
      data_ext_rdy   => data_ext_rdy,
      ext_dreq_data  => ext_dreq_data,
      inst_ext_c     => inst_ext_c,
      inst_ext_req_c => inst_ext_req_c,
      inst_ext_rdy   => inst_ext_rdy,
      ext_dreq_inst  => ext_dreq_inst,
      tw_ext         => tw_ext,
      tw_ext_req     => tw_ext_req,
      tw_ext_ack     => tw_ext_ack,
      ext_dreq_tw    => ext_dreq_tw,
      ext_dr         => ext_dr,
      hitmaj         => hitmaj,
      ext_w          => ext_w,
      ext_r          => ext_r,
      smp_w          => smp_w,
      smp_r          => smp_r,
      sel            => sel,
      cwb            => cwb,
      last           => last_l,
      hit            => hit,
      hitx           => hitx,
      idcache_d2_a   => idcache_d2_a,
      idcache_t2_a   => idcache_t2_a,
      dcache_t2_dr   => dcache_t2_dr,
      dcache_t2_dw   => dcache_t2_dw,
      dcache_t2_wr   => dcache_t2_wr,
      dcache_d2_dr   => dcache_d2_dr,
      dcache_d2_dw   => dcache_d2_dw,
      dcache_d2_wr   => dcache_d2_wr,
      icache_t2_dr   => icache_t2_dr,
      icache_t2_dw   => icache_t2_dw,
      icache_t2_wr   => icache_t2_wr,
      icache_d2_dr   => icache_d2_dr,
      icache_d2_dw   => icache_d2_dw,
      icache_d2_wr   => icache_d2_wr,
      filldone       => filldone,
      ext_dfill      => ext_dfill,
      ext_ifill      => ext_ifill,
      filling_d      => filling_d,
      filling_i      => filling_i,
      mmu_cr_isnoop  => mmu_cr_isnoop,
      mmu_cr_dsnoop  => mmu_cr_dsnoop,
      clk            => clk,
      reset_na       => reset_na);
      
  --###############################################################
  last<=last_l;

END ARCHITECTURE multi;
  
-- On empile DATA avec du retard parceque on n'a pas le bus
-- PAT est déclenché alors que ext_fifo_lev est toujours à zéro.
-- On arrète le FILL avant qu'il ne soit fini
