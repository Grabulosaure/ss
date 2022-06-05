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

-- <avec des bus I & D séparés, on pourrait avoir simultanément un WBACK data
--  et un fill instructions

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

USE work.base_pack.ALL;
USE work.plomb_pack.ALL;
USE work.asi_pack.ALL;
USE work.mcu_pack.ALL;
USE work.cpu_conf_pack.ALL;

--------------------------------------------------------------------------------

ENTITY mcu_multi_ext IS
  GENERIC (
    NB_LINE     : natural;
    BLEN_DCACHE : natural;
    WAY_DCACHE  : natural;
    NB_DCACHE   : natural;
    BLEN_ICACHE : natural;
    WAY_ICACHE  : natural;
    NB_ICACHE   : natural
    );
  PORT (
    -----------------------------------
    -- Requètes
    data_ext_c     : IN  type_ext;
    data_ext_req_c : IN  std_logic;
    data_ext_rdy   : OUT std_logic;
    ext_dreq_data  : OUT std_logic;
    
    inst_ext_c     : IN  type_ext;
    inst_ext_req_c : IN  std_logic;
    inst_ext_rdy   : OUT std_logic;
    ext_dreq_inst  : OUT std_logic;
    
    tw_ext         : IN  type_ext;
    tw_ext_req     : IN  std_logic;
    tw_ext_ack     : OUT std_logic;
    ext_dreq_tw    : OUT std_logic;
    
    ext_dr         : OUT uv32;
    hitmaj         : OUT std_logic;
    
    -----------------------------------
    ext_w : OUT type_plomb_w;
    ext_r : IN  type_plomb_r;
    
    -- Cohérence SMP
    smp_w : OUT type_smp;
    smp_r : IN  type_smp;
    
    sel   : IN  std_logic;
    cwb   : OUT std_logic;
    last  : OUT std_logic;
    hit   : OUT std_logic;
    hitx  : IN  std_logic;
    
    -----------------------------------
    -- Caches
    idcache_d2_a : OUT uv32;
    idcache_t2_a : OUT uv32;
    
    dcache_t2_dr : IN  arr_uv32(0 TO WAY_DCACHE-1);
    dcache_t2_dw : OUT arr_uv32(0 TO WAY_DCACHE-1);
    dcache_t2_wr : OUT uv0_3;
    
    dcache_d2_dr : IN  arr_uv32(0 TO WAY_DCACHE-1);
    dcache_d2_dw : OUT uv32;
    dcache_d2_wr : OUT arr_uv0_3(0 TO WAY_DCACHE-1);
    
    icache_t2_dr : IN  arr_uv32(0 TO WAY_ICACHE-1);
    icache_t2_dw : OUT arr_uv32(0 TO WAY_ICACHE-1);
    icache_t2_wr : OUT uv0_3;
    
    icache_d2_dr : IN  arr_uv32(0 TO WAY_ICACHE-1);
    icache_d2_dw : OUT uv32;
    icache_d2_wr : OUT arr_uv0_3(0 TO WAY_ICACHE-1);
    
    -----------------------------------
    filldone  : OUT std_logic;
    ext_dfill : OUT std_logic;
    ext_ifill : OUT std_logic;
    
    filling_d : OUT std_logic; -- Bloque pendant cache fill (après transfert)
    filling_i : OUT std_logic; -- Bloque pendant cache fill. Stream instructions
    
    mmu_cr_isnoop : IN std_logic;
    mmu_cr_dsnoop : IN std_logic;
    
    -----------------------------------
    clk      : IN  std_logic;
    reset_n  : IN  std_logic
    );
END ENTITY;

ARCHITECTURE multi OF mcu_multi_ext IS

  CONSTANT BURST_1 : unsigned(NB_LINE-1 DOWNTO 0) := (OTHERS =>'1');

  SIGNAL dcache_wr,icache_wr : std_logic;
  SIGNAL smp_w_l,cur_acc : type_smp;
  SIGNAL ext_acc : type_ext;
  
  SIGNAL tw_ext_ack_l : std_logic;
  
  SIGNAL data_ext_reqm,pop_data_c : std_logic;
  SIGNAL data_ext_mem,data_ext2_c : type_ext;

  SIGNAL inst_ext_reqm,pop_inst_c : std_logic;
  SIGNAL inst_ext_mem,inst_ext2_c : type_ext;
  
  SIGNAL filling_end : std_logic;
  SIGNAL idcache_fill_a : uv32;
  SIGNAL ext_dr_l : uv32;
  SIGNAL ext_reqack_delay : std_logic;
  SIGNAL dcache_dr_mem : uv32;
  
  TYPE enum_ext_lock IS (OFF,DATA,TW);
  SIGNAL ext_lock : enum_ext_lock;
  
  SIGNAL last_c,ready_c,done_c : std_logic;
  
  TYPE enum_rd_fifo_op IS (SINGLE,FILL);
  
  TYPE type_rd_fifo IS RECORD
    op  : enum_rd_fifo_op;               -- Type d'opération accès externe
    dit : enum_dit;                      -- Data Inst TableWalk
    pa  : unsigned(35 DOWNTO 0);         -- Adresse physique
    al  : unsigned(NB_LINE+1 DOWNTO 2);  -- Poids faibles addresses
    no  : natural RANGE 0 TO WAY_DCACHE-1;
  END RECORD;

  SIGNAL rd_fifo_dw_c : type_rd_fifo;
  SIGNAL rd_fifo,rd_fifo_mem,rd_fifo_mem2 : type_rd_fifo;
  SIGNAL rd_fifo_lev : natural RANGE 0 TO 3;
  SIGNAL rd_fifo_push_c : std_logic;
  
  TYPE enum_state IS (sIDLE,sPRE,sHIT,sWAIT_WBACK,
                      sWBACK,sFILL,sSINGLE,sWAIT);
  SIGNAL state,state_c : enum_state;
  SIGNAL ext_a,ext_a_c : uv36;
  SIGNAL wb_no,wb_no_c,fill_no : natural RANGE 0 TO WAY_DCACHE-1;
  SIGNAL dno_c,dno : natural RANGE 0 TO WAY_DCACHE-1;
  SIGNAL ino_c,ino : natural RANGE 0 TO WAY_ICACHE-1;
  
  SIGNAL ext_w_c,ext_w_l : type_plomb_w;
  SIGNAL wb_a,wb_a_c : uv36;
  TYPE enum_mop IS (NOP,SINGLE,FILL);
  SIGNAL mop_c,mop : enum_mop;
  SIGNAL tagmaj_c,tagmaj : std_logic;
  
  SIGNAL dcache_t2_dw_c : arr_uv32(0 TO WAY_DCACHE-1);
  SIGNAL icache_t2_dw_c : arr_uv32(0 TO WAY_ICACHE-1);
  
  SIGNAL mem_asi,mem_asi_c : uv8;
  SIGNAL mem_pa,mem_pa_c : uv36;
  SIGNAL mem_dno,mem_dno_c : natural RANGE 0 TO WAY_DCACHE-1;
  
BEGIN

  --###############################################################
  -- Mémorisation accès I/D
  
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
  
  ready_c<=done_c OR NOT smp_w_l.req;
  
  Carl:PROCESS(ready_c,ext_lock,tw_ext_req,
               data_ext_req_c,data_ext_reqm,
               inst_ext_req_c,inst_ext_reqm) IS
  BEGIN
    tw_ext_ack_l<='0';
    pop_data_c<='0';
    pop_inst_c<='0';
    IF ready_c='1' THEN
      IF ext_lock=DATA THEN
        pop_data_c<=data_ext_req_c OR data_ext_reqm;
      ELSIF ext_lock=TW THEN
        tw_ext_ack_l  <=tw_ext_req;
      ELSIF tw_ext_req='1' THEN
        tw_ext_ack_l  <='1';
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
  
  inst_ext2_c<=inst_ext_c WHEN inst_ext_reqm='0' ELSE inst_ext_mem;
  data_ext2_c<=data_ext_c WHEN data_ext_reqm='0' ELSE data_ext_mem;
  
  data_ext_rdy<=NOT data_ext_reqm;
  inst_ext_rdy<=NOT inst_ext_reqm;
  
  -- mémorise un accès I et un accès D avec bypass zéro délai
  -- sortie synchrone smp_w
  -- dépile l'accès accepté sur  SMP_W
  -- pop_data / pop_inst / tw_ext_ack / : Accepte transfert

  tw_ext_ack<=tw_ext_ack_l;
  
  --###############################################################
  -- Requètes "SMP"
  
  SyncSMP:PROCESS(clk) IS
    VARIABLE acc_v : type_ext;
    VARIABLE new_v : boolean;
    VARIABLE dit_v : enum_dit;
    
  BEGIN
    IF rising_edge(clk) THEN
      IF done_c='1' THEN
        smp_w_l.req<='0';
        smp_w_l.busy<='0';
      END IF;
      
      new_v:=false;
      IF pop_data_c='1' THEN
        -- Requète DATA
        acc_v:=data_ext2_c;
        dit_v:=DI_DATA;
        new_v:=true;
      ELSIF pop_inst_c='1' THEN
        -- Requète INST
        acc_v:=inst_ext2_c;
        dit_v:=DI_INST;
        new_v:=true;
      ELSIF tw_ext_ack_l='1' THEN
        -- Requète TW
        acc_v:=tw_ext;
        dit_v:=DI_TW;
        new_v:=true;
      END IF;
      
      IF new_v THEN
        ext_acc<=acc_v;
        smp_w_l.op<=acc_v.op;
        smp_w_l.a <=acc_v.pw.a;
        smp_w_l.ah<=acc_v.pw.ah;
        smp_w_l.lock<=acc_v.pw.lock;
        smp_w_l.gbl <=acc_v.pw.cache;
        smp_w_l.rw <=to_std_logic(is_write(acc_v.pw));
        smp_w_l.dit<=dit_v;
        smp_w_l.req<='1';
        smp_w_l.busy<='1';
      END IF;
      
      IF sel='1' AND smp_w_l.req='1' THEN
        cur_acc<=smp_w_l; -- <AVOIR> CUR_ACC utilisé seulement WBACK...
      END IF;
      
      IF acc_v.pw.lock='1' AND pop_data_c='1' THEN
        ext_lock<=DATA;
      ELSIF acc_v.pw.lock='1' AND tw_ext_ack_l='1' THEN
        ext_lock<=TW;
      ELSIF ext_lock=DATA AND data_ext2_c.pw.lock='0' THEN
        ext_lock<=OFF;
        smp_w_l.lock<='0';
        ext_acc.pw.lock<='0';
      ELSIF ext_lock=TW AND tw_ext.pw.lock='0' THEN
        ext_lock<=OFF;
        smp_w_l.lock<='0';
        ext_acc.pw.lock<='0';
      END IF;

      IF reset_n='0' THEN
        ext_lock<=OFF;
        smp_w_l.req<='0';
        smp_w_l.busy<='0';
      END IF;      

    END IF;
  END PROCESS;
  
  -- Si SEL & SMP_REQ=1 : La requète en cours est acceptée sur le bus
  -- On mémorise.
  -- On bloque jusqu'à la fin
  
  smp_w<=smp_w_l;
  ext_w<=ext_w_l;
  
  --###############################################################
  -- Génère sorties HIT, CWB
  
  Comb:PROCESS(
    smp_r,sel,cur_acc,dcache_t2_dr,icache_t2_dr,
    dcache_d2_dr,rd_fifo_lev,mop,
    ext_reqack_delay,dcache_dr_mem,ext_w_c,
    ext_a,state,wb_a,wb_no,hitx,dno,ino,dno_c,ino_c,
    mmu_cr_dsnoop,mmu_cr_isnoop,
    mem_dno,mem_pa,mem_asi,
    ext_acc,ext_w_l,ext_r,tagmaj,smp_w_l) IS
    VARIABLE dhit_v : std_logic;
    VARIABLE dvms_v : uv3;
    VARIABLE dno_v   : natural RANGE 0 TO WAY_DCACHE-1;
    VARIABLE dcache_hit_v : unsigned(0 TO WAY_DCACHE-1); -- Cache Hit
    VARIABLE dmesi_v : enum_mesi;
    VARIABLE dhist_v : uv8;
    VARIABLE ihit_v : std_logic;
    VARIABLE iv_v,im_v,is_v : std_logic;
    VARIABLE ino_v  : natural RANGE 0 TO WAY_ICACHE-1;
    VARIABLE icache_hit_v : unsigned(0 TO WAY_ICACHE-1); -- Cache Hit
    VARIABLE ihist_v : uv8;
    
    TYPE enum_src IS (DATA,INST,TW,EXT);
    VARIABLE src_v : enum_src;
    VARIABLE dmod_v,imod_v,dwb_v : boolean;
    VARIABLE mop_v : enum_mop;
    VARIABLE pa_v : uv36;
    VARIABLE ig_v,ig2_v : std_logic;
    VARIABLE dtag_v,itag_v : uv32;
    
  BEGIN
    
    pa_v:=smp_r.ah & smp_r.a;
    
    -------------------------------------------------------
    dno_v:=0;
    FOR i IN 0 TO WAY_DCACHE-1 LOOP
      ptag_test(dcache_hit_v(i),ig_v,ig2_v,
                dcache_t2_dr(i),pa_v,x"00",NB_DCACHE);
      IF dcache_hit_v(i)='1' THEN
        dno_v:=i;
      END IF;
    END LOOP;
    dhit_v:=v_or(dcache_hit_v) AND mmu_cr_dsnoop;
    
    -- Si pas de hit, sélection LRU de la ligne à évincer
    dhist_v:=x"00";
    FOR i IN 0 TO WAY_DCACHE-1 LOOP
      dhist_v(i*2+1 DOWNTO i*2):=dcache_t2_dr(i)(3 DOWNTO 2);
    END LOOP;
    IF dhit_v='0' THEN
      dno_v:=tag_selfill(dcache_t2_dr,dhist_v);
    END IF;
    
    dtag_v:=dcache_t2_dr(dno_v);
    ptag_decode(dvms_v(2),dvms_v(1),dvms_v(0),dtag_v);
    dmesi_v:=ptag_decode(dtag_v);
    
    -------------------------------------------------------
    ino_v:=0;
    FOR i IN 0 TO WAY_ICACHE-1 LOOP
      ptag_test(icache_hit_v(i),ig_v,ig2_v,
                icache_t2_dr(i),pa_v,x"00",NB_ICACHE);
      IF icache_hit_v(i)='1' THEN
        ino_v:=i;
      END IF;
    END LOOP;
    ihit_v:=v_or(icache_hit_v) AND mmu_cr_isnoop;
    
    -- Si pas de hit, sélection LRU de la ligne à évincer
    ihist_v:=x"00";
    FOR i IN 0 TO WAY_ICACHE-1 LOOP
      ihist_v(i*2+1 DOWNTO i*2):=icache_t2_dr(i)(3 DOWNTO 2);
    END LOOP;
    IF ihit_v='0' THEN
      ino_v:=tag_selfill(icache_t2_dr,ihist_v);
    END IF;
    
    itag_v:=icache_t2_dr(ino_v);
    ptag_decode(iv_v,im_v,is_v,itag_v); -- IM & IS : Ignore
    
    ---------------------------------------------------------
    IF sel='0' THEN
      src_v:=EXT;
    ELSIF smp_r.dit=DI_DATA THEN
      src_v:=DATA;
    ELSIF smp_r.dit=DI_INST THEN
      src_v:=INST;
    ELSE -- TW
      src_v:=TW;
    END IF;
    
    --------------------------------------------------
    -- Paramètres
    -- op    : Type accès
    -- dmesi : MESI
    -- iv    : EI
    -- src   : EXT,DATA,INST,TW
    
    -- dwb_v   : Requète WBACK
    -- mop_v   : NOP,SINGLE,FILL
    
    -- VMS : M=110  E=100  S=101  I=0__
    
    -- On séquence WBACK -> FILL
    -- On ne démarre un nouveau WBACK que s'il n'y a pas de FILL en attente
    -- (mux bus adresses)
    
    ----------------------------------------------
    -- Parties :
    -- - Pousse accès demandé SMP_W
    -- - Décodage SMP_R, décision opération
    -- - Machine à états accès externes EXT_W : SINGLE,FILL,FLUSH,...
    -- - FIFO relecture. Pousse données relues.
    
    mop_c<=mop;
    mop_v:=NOP;    -- NOP,SINGLE,FILL
    dwb_v:=false;  -- Déclenche WBACK
    dmod_v:=false; 
    imod_v:=false;
    
    dno_c<=dno;
    ino_c<=ino;
    
    IF smp_r.gbl='0' AND src_v=EXT THEN
      NULL; -- Ignore accès externes non globaux
    ELSE
      CASE smp_r.op IS
        ------------------------------------------
        WHEN SINGLE => -- Read / Write Single or IO burst (non cached)
          IF dmesi_v=M AND dhit_v='1' THEN
            dwb_v:=true; -- >WBACK
          END IF;
          IF src_v/=EXT THEN
            mop_v:=SINGLE;
          END IF;
          IF smp_r.rw='0' THEN -- Read Single or IO burst (non cached)
            IF dmesi_v=M AND dhit_v='1' THEN
              dvms_v:="100"; dmod_v:=true; -- >E
            END IF;
          ELSE -- Write Single
            IF src_v=DATA THEN
              IF (dmesi_v=M OR dmesi_v=S) and dhit_v='1' THEN
                dvms_v:="100"; dmod_v:=true; -- >E
              END IF;
            ELSE -- EXT / INST / TB
              IF dmesi_v/=I AND dhit_v='1' THEN
                dvms_v:="000"; dmod_v:=true; -- >I
              END IF;
            END IF;
            IF iv_v='1' AND ihit_v='1' AND src_v/=INST THEN
              iv_v:='0'; imod_v:=true; -- >I
            END IF;
          END IF;
          
        ------------------------------------------
        WHEN FILL => -- Fill Read
          IF dmesi_v=M AND (dhit_v='1' OR src_v=DATA) THEN
            dwb_v:=true; -- >WBACK
          END IF;
          CASE src_v IS
            WHEN EXT =>
              IF (dmesi_v=M OR dmesi_v=E) AND dhit_v='1' THEN
                dvms_v:="101"; dmod_v:=true; -- >S
              END IF;
            WHEN DATA =>
              dvms_v:="10" & (hitx OR ihit_v); dmod_v:=true; -- >E/S
              mop_v:=FILL; -- >FILL
            WHEN INST =>
              IF (dmesi_v=M OR dmesi_v=E) AND dhit_v='1' THEN
                dvms_v:="101"; dmod_v:=true; -- >S
              END IF;
              mop_v:=FILL; -- >FILL
              iv_v:='1'; -- >V
              imod_v:=true;
            WHEN OTHERS => NULL;
          END CASE;
          
        ------------------------------------------
        WHEN FILLMOD => -- Fill Write
          IF dmesi_v=M AND (dhit_v='1' OR src_v=DATA) THEN
            dwb_v:=true; -- >WBACK
          END IF;
          IF src_v=EXT THEN
            IF dmesi_v/=I AND dhit_v='1' THEN
              dvms_v:="000"; dmod_v:=true; -- >I
            END IF;
          ELSE -- DATA
            mop_v:=FILL; -- >FILL
--            dvms_v:="100"; dmod_v:=true; -- >E
            dvms_v:="110"; dmod_v:=true; -- >E -- <ESSAI>
          END IF;
          IF iv_v='1' AND ihit_v='1' THEN
            iv_v:='0'; imod_v:=true; -- >I
          END IF;
          
        ------------------------------------------
        WHEN FLUSH =>
          IF dmesi_v=M AND dhit_v='1' THEN
            dwb_v:=true; -- >WBACK
          END IF;
          IF dmesi_v/=I AND dhit_v='1' THEN
            dvms_v:="000"; dmod_v:=true; -- >I
          END IF;
          IF iv_v='1' AND ihit_v='1' THEN
            iv_v:='0'; imod_v:=true; -- >I
          END IF;
          
        ------------------------------------------
        WHEN EXCLUSIVE =>
          IF dmesi_v=M AND dhit_v='1' THEN
            dwb_v:=true; -- >WBACK
          END IF;
          IF dmesi_v/=I AND dhit_v='1' THEN
            IF src_v=EXT THEN
              dvms_v:="000"; dmod_v:=true; -- >I
            ELSE -- DATA
              dvms_v:="100"; dmod_v:=true; -- >E
            END IF;
          END IF;
          IF iv_v='1' AND ihit_v='1' THEN
            iv_v:='0'; imod_v:=true; -- >I
          END IF;
          
        ------------------------------------------
      END CASE;
    END IF;
    
    rd_fifo_push_c<='0';
    ----------------------------------------------
    cwb<=to_std_logic(dwb_v) AND mmu_cr_dsnoop; -- Write back
    hit<=dhit_v OR ihit_v;
    
    ----------------------------------------------
    -- Mise à jour tags
    dcache_t2_dw_c<=dcache_t2_dr;
    icache_t2_dw_c<=icache_t2_dr;
    
    dcache_t2_dw_c(dno)<=ptag_mod(
      dcache_t2_dr(dno),dvms_v(2),dvms_v(1),dvms_v(0));
    icache_t2_dw_c(ino)<=ptag_mod(
      icache_t2_dr(ino),iv_v,'0','0');
      
    -- Mise à jour tag complet DATA. MàJ LRU
    IF mop_v=FILL AND src_v=DATA THEN
      dtag_v:=ptag_encode(ext_a,
                  dvms_v(2),dvms_v(1),dvms_v(0),"00",NB_DCACHE);
      dcache_t2_dw_c(dno)<=dtag_v;
      dhist_v:=lru_maj(dhist_v,dno,WAY_DCACHE);
      FOR i IN 0 TO WAY_DCACHE-1 LOOP
        dcache_t2_dw_c(i)(3 DOWNTO 2)<=dhist_v(i*2+1 DOWNTO i*2);
      END LOOP;
    END IF;
    
    -- Mise à jour tag complet INST. MàJ LRU
    IF mop_v=FILL AND src_v=INST THEN
      itag_v:=ptag_encode(ext_a,
                  iv_v,'0','0',"00",NB_ICACHE);
      icache_t2_dw_c(ino)<=itag_v;
      ihist_v:=lru_maj(ihist_v,ino,WAY_ICACHE);
      FOR i IN 0 TO WAY_DCACHE-1 LOOP
        icache_t2_dw_c(i)(3 DOWNTO 2)<=ihist_v(i*2+1 DOWNTO i*2);
      END LOOP;
    END IF;
        
    tagmaj_c<='0';
    
    dcache_t2_wr<=(OTHERS => tagmaj AND to_std_logic(dmod_v));
    icache_t2_wr<=(OTHERS => tagmaj AND to_std_logic(imod_v));
    
    ----------------------------------------------
    ext_a_c<=ext_a;
    state_c<=state;
    wb_a_c<=wb_a;
    wb_no_c<=wb_no;
    idcache_t2_a<=smp_r.a;
    ext_w_c<=ext_w_l;
    rd_fifo_dw_c<=(op=>FILL,dit=>smp_w_l.dit,
                   pa=>ext_acc.pw.ah & ext_acc.pw.a,
                   al=>ext_acc.pw.a(NB_LINE+1 DOWNTO 2),
                   no=>mux(smp_w_l.dit=DI_DATA,dno_c,ino_c));
    
    last_c<='0';
    done_c<='0';
    hitmaj<='0';
    
    ----------------------------------------------
    CASE state IS
      WHEN sIDLE =>
        IF smp_r.req='1' THEN
          state_c<=sPRE;
        END IF;
        ext_w_c.req<='0';
        ext_w_c.lock<=ext_acc.pw.lock;
        
        -- REQ avec 2 cyles de retard sur WBACK
        -- 1 mémoire dcache_DR si stall
        -- incrémente WB_A
        
        ------------------------------------------
      WHEN sPRE =>
        ext_a_c<=smp_r.ah & smp_r.a;
        dno_c<=dno_v;
        ino_c<=ino_v;
        mop_c<=mop_v;
        pa_v:=ptag_pa(dcache_t2_dr(dno_v),smp_r.a,NB_DCACHE);
        wb_a_c<=pa_v;
        wb_a_c(NB_LINE+1 DOWNTO 2)<=(OTHERS => '0');
        state_c<=sHIT;
        last_c<='0';
        
      WHEN sHIT =>
        ext_a_c<=smp_r.ah & smp_r.a;
        dno_c<=dno_v;
        ino_c<=ino_v;
        mop_c<=mop_v;
        pa_v:=ptag_pa(dcache_t2_dr(dno_v),smp_r.a,NB_DCACHE);
        wb_a_c<=pa_v;
        wb_a_c(NB_LINE+1 DOWNTO 2)<=(OTHERS => '0');
        tagmaj_c<='1';
        mem_dno_c<=dno_v;
        mem_pa_c <=pa_v;
        mem_asi_c<=ext_acc.pw.asi;
        hitmaj <= sel;
        last_c<='0';
        
        IF dwb_v THEN
          IF rd_fifo_lev=0 THEN
            -- Attente que la FIFO relecture soit vide, parceque
            -- il faut contrôler le bus d'adresses pour les lectures DATA
            state_c<=sWBACK;
            wb_no_c<=dno_v;
            ext_w_c.a<=pa_v(31 DOWNTO 0);
            ext_w_c.ah<=pa_v(35 DOWNTO 32);
            ext_w_c.a(NB_LINE+1 DOWNTO 2)<=(OTHERS => '0');
            -- Poids faibles selon addresses ext
            -- Poids forts selon tag
            ext_w_c.asi<=ext_acc.pw.asi;
            ext_w_c.d<=dcache_d2_dr(dno_v);
            ext_w_c.be<=(OTHERS =>'1');
            ext_w_c.mode<=PB_MODE_WR;
            ext_w_c.burst<=pb_blen(BLEN_DCACHE);
            ext_w_c.cont<='0';
            ext_w_c.cache<='1';
            ext_w_c.lock<='0';
            ext_w_c.req<='0';
            ext_w_c.dack<='1';
          ELSE
            state_c<=sWAIT_WBACK;
          END IF;
          
        ELSIF mop_v=FILL THEN
          state_c<=sFILL;
          ext_w_c<=ext_acc.pw;
          ext_w_c.a(NB_LINE+1 DOWNTO 2)<=(OTHERS => '0');
          ext_w_c.req<='1';
          ext_w_c.mode<=PB_MODE_RD;
          ext_w_c.burst<=pb_blen(BLEN_DCACHE);
          ext_w_c.dack<='1';
          rd_fifo_dw_c.op<=FILL;
          -- <AVOIR> <Mettre partout>
          rd_fifo_dw_c.pa(NB_LINE+1 DOWNTO 2)<=(OTHERS => '0');
          rd_fifo_push_c<='1';
          
        ELSIF mop_v=SINGLE THEN
          state_c<=sSINGLE;
          ext_w_c<=ext_acc.pw;
          ext_w_c.req<='1';
          ext_w_c.dack<='1';
          rd_fifo_dw_c.op<=SINGLE;
          rd_fifo_push_c<=to_std_logic(is_read(ext_acc.pw));
          
        ELSE
          state_c<=sWAIT;
          --done_c<=sel;
          
        END IF;
        
        ------------------------------------------
      WHEN sWAIT_WBACK =>
        cwb<='1';
        IF rd_fifo_lev=0 THEN
          -- Attente que la FIFO relecture soit vide, parceque
          -- il faut contrôler le bus d'adresses pour les lectures DATA
          state_c<=sWBACK;
          wb_no_c<=mem_dno;
          ext_w_c.a<=mem_pa(31 DOWNTO 0);
          ext_w_c.ah<=mem_pa(35 DOWNTO 32);
          ext_w_c.a(NB_LINE+1 DOWNTO 2)<=(OTHERS => '0');
          -- Poids faibles selon addresses ext
          -- Poids forts selon tag
          ext_w_c.asi<=mem_asi;
          ext_w_c.d<=dcache_d2_dr(mem_dno);
          ext_w_c.be<=(OTHERS =>'1');
          ext_w_c.mode<=PB_MODE_WR;
          ext_w_c.burst<=pb_blen(BLEN_DCACHE);
          ext_w_c.cont<='0';
          ext_w_c.cache<='1';
          ext_w_c.lock<='0';
          ext_w_c.req<='0';
          ext_w_c.dack<='1';
        END IF;
        
        ------------------------------------------
      WHEN sWBACK =>
        cwb<='1';
        IF ext_w_l.req='0' OR ext_r.ack='1' THEN
          wb_a_c(NB_LINE+1 DOWNTO 2)<=wb_a(NB_LINE+1 DOWNTO 2)+1;
          IF ext_reqack_delay='1' THEN
            ext_w_c.d<=dcache_d2_dr(wb_no);
          ELSE
            ext_w_c.d<=dcache_dr_mem;
          END IF;
        END IF;

        IF ext_w_l.req='1' AND ext_r.ack='1' THEN
          ext_w_c.a(NB_LINE+1 DOWNTO 2)<=ext_w_l.a(NB_LINE+1 DOWNTO 2) + 1;
          ext_w_c.burst<=PB_SINGLE;
        END IF;
        
        ext_w_c.req<=to_std_logic(wb_a(NB_LINE+1 DOWNTO 2)>=1) OR ext_w_l.req;
        ext_w_c.mode<=PB_MODE_WR;
        
        IF ext_w_l.a(NB_LINE+1 DOWNTO 2)=BURST_1 AND ext_r.ack='1' THEN
          cwb<='0';
          ext_w_c.req<='0';
          
          IF mop=SINGLE AND sel='1' THEN
            state_c<=sSINGLE;
            ext_w_c<=ext_acc.pw;
            ext_w_c.req<='1';
            ext_w_c.dack<='1';
            rd_fifo_dw_c.op<=SINGLE;
            rd_fifo_push_c<=NOT cur_acc.rw;
            
          ELSIF mop=FILL AND sel='1' THEN
            state_c<=sFILL;
            ext_w_c<=ext_acc.pw;
            ext_w_c.a(NB_LINE+1 DOWNTO 2)<=(OTHERS => '0');
            ext_w_c.req<='1';
            ext_w_c.dack<='1';
            ext_w_c.mode<=PB_MODE_RD;
            ext_w_c.burst<=pb_blen(BLEN_DCACHE);
            rd_fifo_dw_c.op<=FILL;
            rd_fifo_dw_c.pa(NB_LINE+1 DOWNTO 2)<=(OTHERS => '0');
            rd_fifo_push_c<='1';
            
          ELSE
            state_c<=sIDLE;
            last_c<='1';
            
          END IF;
        END IF;
        
        ------------------------------------------
      WHEN sFILL =>
        cwb<='0';
        ext_w_c.d<=dcache_d2_dr(wb_no);
        ext_w_c.req<='1'; -- 1 cycle délai relecture data
        IF ext_w_l.req='1' AND ext_r.ack='1' THEN
          ext_w_c.a(NB_LINE+1 DOWNTO 2)<=ext_w_l.a(NB_LINE+1 DOWNTO 2) + 1;
          ext_w_c.burst<=PB_SINGLE;
          IF ext_w_l.a(NB_LINE+1 DOWNTO 2)=BURST_1 THEN
            ext_w_c.req<='0';
            state_c<=sIDLE;
            last_c<='1';
            done_c<='1';
          END IF;
        END IF;
        
        ------------------------------------------
      WHEN sSINGLE => -- Read/Write Single
        cwb<='0';
        IF ext_r.ack='1' THEN
          ext_w_c.req<='0';
          state_c<=sIDLE;
          last_c<='1';
          done_c<='1';
        END IF;
        
        ------------------------------------------
      WHEN sWAIT =>
        cwb<='0';
        state_c<=sIDLE;
        last_c<='1';
        done_c<=sel;
        
        ------------------------------------------
    END CASE;
  END PROCESS; -- Comb

  last<=last_c;
  
  ---------------------------------------------------------
  CacheWR:PROCESS (dcache_wr,icache_wr,fill_no) IS
  BEGIN
    dcache_d2_wr<=(OTHERS =>"0000");
    dcache_d2_wr(fill_no)<=(OTHERS => dcache_wr);
    icache_d2_wr<=(OTHERS =>"0000");
    icache_d2_wr(fill_no)<=(OTHERS => icache_wr);
  END PROCESS;
  
  idcache_d2_a<=wb_a(31 DOWNTO 0) WHEN state=sWBACK ELSE
                 idcache_fill_a;
  
  dcache_d2_dw<=ext_dr_l;
  icache_d2_dw<=ext_dr_l;
  
  ext_dr<=ext_dr_l;
  
  ---------------------------------------------------------
  Seq:PROCESS (clk) IS
    VARIABLE rd_fifo_pop_v : std_logic;
    
  BEGIN
    IF rising_edge(clk) THEN
      ----------------------------------------------
      state<=state_c;
      ext_w_l<=ext_w_c;
      wb_no<=wb_no_c;
      wb_a <=wb_a_c;
      ext_a<=ext_a_c;
      tagmaj<=tagmaj_c;
      dno<=dno_c;
      ino<=ino_c;
      mop<=mop_c;

      mem_dno<=mem_dno_c;
      mem_pa <=mem_pa_c;
      mem_asi<=mem_asi_c;
      
      dcache_t2_dw<=dcache_t2_dw_c;
      icache_t2_dw<=icache_t2_dw_c;
      ----------------------------------------------
      IF ext_reqack_delay='1' THEN
        dcache_dr_mem<=dcache_d2_dr(dno);
      END IF;
      
      ext_reqack_delay<=NOT ext_w_l.req OR ext_r.ack;
      
      ----------------------------------------------
      ext_dr_l<=ext_r.d;
      
      ext_dreq_data<=ext_r.dreq AND to_std_logic(
        rd_fifo.dit=DI_DATA AND rd_fifo.pa(NB_LINE+1 DOWNTO 2)=rd_fifo.al);
      
      ext_dreq_inst<=ext_r.dreq AND to_std_logic(
        rd_fifo.dit=DI_INST AND rd_fifo.pa(NB_LINE+1 DOWNTO 2)=rd_fifo.al);
      
      ext_dreq_tw<=ext_r.dreq AND to_std_logic(
        rd_fifo.dit=DI_TW AND rd_fifo.pa(NB_LINE+1 DOWNTO 2)=rd_fifo.al);
      
      filldone<=to_std_logic(rd_fifo.pa(NB_LINE+1 DOWNTO 2)=BURST_1);
      
      ---------------------------------------
      -- Copie données lues
      IF filling_end='1' THEN
        filling_d<='0';
        filling_i<='0';
      END IF;

      dcache_wr<='0';
      icache_wr<='0';
      rd_fifo_pop_v:='0';
      
      IF rd_fifo_lev/=0 AND ext_r.dreq='1' THEN
        -- Cache fill : Copies des données du bus EXT vers le cache
        rd_fifo.pa(NB_LINE+1 DOWNTO 2)<=rd_fifo.pa(NB_LINE+1 DOWNTO 2)+1;
        IF rd_fifo.pa(NB_LINE+1 DOWNTO 2)=BURST_1 OR rd_fifo.op=SINGLE THEN
          rd_fifo_pop_v:='1';
          filling_end<='1';
        END IF;
        
        dcache_wr<=to_std_logic(rd_fifo.dit=DI_DATA AND rd_fifo.op=FILL);
        icache_wr<=to_std_logic(rd_fifo.dit=DI_INST AND rd_fifo.op=FILL);
        idcache_fill_a<=rd_fifo.pa(31 DOWNTO 0);
        
        filling_d<=to_std_logic(rd_fifo.dit=DI_DATA AND rd_fifo.op=FILL);
        filling_i<=to_std_logic(rd_fifo.dit=DI_INST AND rd_fifo.op=FILL);
        
        ext_dfill<=to_std_logic(rd_fifo.dit=DI_DATA AND rd_fifo.op=FILL);
        ext_ifill<=to_std_logic(rd_fifo.dit=DI_INST AND rd_fifo.op=FILL);
      ELSE
        ext_dfill<='0';
        ext_ifill<='0';
      END IF;
      
      fill_no<=rd_fifo.no;
      
      ---------------------------------------
      -- FIFO Commandes
      IF rd_fifo_push_c='1' AND rd_fifo_pop_v='0' THEN
        -- Empile
        IF rd_fifo_lev<3 THEN
          rd_fifo_lev<=rd_fifo_lev+1;
        END IF;
        IF rd_fifo_lev=0 THEN
          rd_fifo<=rd_fifo_dw_c;
        ELSIF rd_fifo_lev=1 THEN
          rd_fifo_mem<=rd_fifo_dw_c;
        END IF;
        rd_fifo_mem2<=rd_fifo_dw_c;
        
      ELSIF rd_fifo_push_c='0' AND rd_fifo_pop_v='1' THEN
        -- Dépile
        rd_fifo     <=rd_fifo_mem;
        rd_fifo_mem <=rd_fifo_mem2;
        rd_fifo_mem2<=rd_fifo_dw_c;
        
        IF rd_fifo_lev>0 THEN
          rd_fifo_lev<=rd_fifo_lev-1;
        END IF;
        
      ELSIF rd_fifo_push_c='1' AND rd_fifo_pop_v='1' THEN
        -- Empile & Dépile
        rd_fifo     <=rd_fifo_mem;
        rd_fifo_mem <=rd_fifo_mem2;
        rd_fifo_mem2<=rd_fifo_dw_c;
        IF rd_fifo_lev=2 THEN
          rd_fifo_mem<=rd_fifo_dw_c;
        ELSIF rd_fifo_lev=1 THEN
          rd_fifo<=rd_fifo_dw_c;
        END IF;
      END IF;

      -------------------------------------------------
      IF reset_n='0' THEN
        rd_fifo_lev<=0;
        state<=sIDLE;
      END IF;        

    END IF;
  END PROCESS;
  
END ARCHITECTURE multi;
