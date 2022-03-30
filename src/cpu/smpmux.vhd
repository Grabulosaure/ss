--------------------------------------------------------------------------------
-- TEM : TACUS
-- Contrôleur Multiprocesseur
--------------------------------------------------------------------------------
-- DO 9/2015
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

-- NO = 0 : IO
--      1 : CPU0
--      2 : CPU1
--      3 : CPU2
--      4 : CPU3

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

USE work.base_pack.ALL;
USE work.plomb_pack.ALL;
USE work.mcu_pack.ALL;

ENTITY smpmux IS
  GENERIC (
    NCPU      : natural :=1;      -- Nombre de procs
    PROF      : natural :=8);     -- FIFO retour datas
  PORT (
    smp0_w   : IN  type_smp;
    cpu0_w   : IN  type_plomb_w;
    cpu0_r   : OUT type_plomb_r;
    hit0     : IN  std_logic;     -- Cache hit
    hitx0    : OUT std_logic;
    cwb0     : IN  std_logic;     -- Cache hit, modified line, writeback ongoing
    last0    : IN  std_logic;     -- Last cycle of transaction
    sel0     : OUT std_logic;     -- Selected
    
    smp1_w   : IN  type_smp     :=SMP_ZERO;
    cpu1_w   : IN  type_plomb_w :=PLOMB_W_ZERO;
    cpu1_r   : OUT type_plomb_r;
    hit1     : IN  std_logic :='0'; -- Cache hit
    hitx1    : OUT std_logic;
    cwb1     : IN  std_logic :='0'; -- Cache hit, modified line, writeback ongoing
    last1    : IN  std_logic;     -- Last cycle of transaction
    sel1     : OUT std_logic;     -- Selected
    
    smp2_w   : IN  type_smp     :=SMP_ZERO;
    cpu2_w   : IN  type_plomb_w :=PLOMB_W_ZERO;
    cpu2_r   : OUT type_plomb_r;
    hit2     : IN  std_logic :='0'; -- Cache hit
    hitx2    : OUT std_logic;
    cwb2     : IN  std_logic :='0'; -- Cache hit, modified line, writeback ongoing
    last2    : IN  std_logic;     -- Last cycle of transaction
    sel2     : OUT std_logic;     -- Selected
    
    smp3_w   : IN  type_smp     :=SMP_ZERO;
    cpu3_w   : IN  type_plomb_w :=PLOMB_W_ZERO;
    cpu3_r   : OUT type_plomb_r;
    hit3     : IN  std_logic :='0'; -- Cache hit
    hitx3    : OUT std_logic;
    cwb3     : IN  std_logic :='0'; -- Cache hit, modified line, writeback ongoing
    last3    : IN  std_logic;     -- Last cycle of transaction
    sel3     : OUT std_logic;     -- Selected
    
    io_w     : IN  type_plomb_w :=PLOMB_W_ZERO;
    io_r     : OUT type_plomb_r;
    
    smp_r    : OUT type_smp;      -- Shared Bus Snooping
    
    mem_w    : OUT type_plomb_w;
    mem_r    : IN  type_plomb_r;
    
    reset_na : IN std_logic;
    clk      : IN std_logic
    );
END ENTITY smpmux;

ARCHITECTURE rtl OF smpmux IS
  
  TYPE type_etat IS (sIDLE,sPRE,sHIT,sTRANS,sWBACK);
  SIGNAL etat,etat_c : type_etat;
  SUBTYPE type_no IS natural RANGE 0 TO 4;
  TYPE arr_fifo IS ARRAY(0 TO PROF-1) OF type_no;
  SIGNAL fifo : arr_fifo;
  SIGNAL level : natural RANGE 0 TO PROF;
  
  SIGNAL mem_w_l : type_plomb_w;
  SIGNAL no,no_c,not_c,nwback,nwback_c : type_no;
  
  SIGNAL lock_c,lock : std_logic;
  SIGNAL io_r_ack_l : std_logic;
  SIGNAL iocpt,iocpt_c : natural RANGE 0 TO PB_BLEN_MAX;

  SIGNAL xx_cpt : natural RANGE 0 TO 255;
  SIGNAL xx_max : std_logic;
  SIGNAL mlast,mlast_c : uv5;

  FUNCTION andlast(l : uv5) RETURN std_logic IS
    VARIABLE t : std_logic :='1';
  BEGIN
    t:=t AND l(0);
    t:=t AND l(1);
    t:=t AND (l(2) OR to_std_logic(NCPU=1));
    t:=t AND (l(3) OR to_std_logic(NCPU<=2));
    t:=t AND (l(4) OR to_std_logic(NCPU<=3));
    RETURN t;
  END FUNCTION;

  TYPE arr_uint2 IS ARRAY (natural RANGE <>) OF uint2;
  
  CONSTANT ROBIN4 : arr_uint2 := (
    0,1,2,3, -- 0000  
    0,0,0,0, -- 0001
    1,1,1,1, -- 0010
    1,0,0,0, -- 0011
    2,2,2,2, -- 0100
    2,2,0,0, -- 0101
    1,2,1,1, -- 0110
    1,2,0,0, -- 0111
    3,3,3,3, -- 1000
    3,3,3,0, -- 1001
    1,3,3,1, -- 1010
    1,3,3,0, -- 1011
    2,2,3,2, -- 1100
    2,2,3,0, -- 1101
    1,2,3,1, -- 1110
    1,2,3,0);-- 1111

  FUNCTION co(a : std_logic;
              b : std_logic;
              c : std_logic;
              d : std_logic;
              n : natural)  RETURN natural IS
    VARIABLE v : natural := 0;
  BEGIN
    v:=n;
    IF d='1' THEN v:=v+4;  END IF;
    IF c='1' THEN v:=v+8;  END IF;
    IF b='1' THEN v:=v+16; END IF;
    IF a='1' THEN v:=v+32; END IF;
    RETURN v;
  END FUNCTION;
  
BEGIN
  
  hitx0<=hit1 OR hit2 OR hit3 WHEN NCPU=4 ELSE
         hit1 OR hit2         WHEN NCPU=3 ELSE
         hit1                 WHEN NCPU=2 ELSE
         '0';
  
  hitx1<=hit0 OR hit2 OR hit3 WHEN NCPU=4 ELSE
         hit0 OR hit2         WHEN NCPU=3 ELSE
         hit0                 WHEN NCPU=2 ELSE
         '0';
  
  hitx2<=hit0 OR hit1 OR hit3 WHEN NCPU=4 ELSE
         hit0 OR hit1         WHEN NCPU=3 ELSE
         '0';
  
  hitx3<=hit0 OR hit1 OR hit2 WHEN NCPU=4 ELSE
         '0';
  
  sel0<='1' WHEN no_c=1 ELSE '0';
  sel1<='1' WHEN no_c=2 ELSE '0';
  sel2<='1' WHEN no_c=3 ELSE '0';
  sel3<='1' WHEN no_c=4 ELSE '0';
  
  -------------------------------------------------------------------------
  Comb:PROCESS(etat,smp0_w,smp1_w,smp2_w,smp3_w,
               cpu0_w,cpu1_w,cpu2_w,cpu3_w,io_w,
               mem_r,lock,no,cwb0,cwb1,cwb2,cwb3,
               last0,last1,last2,last3,mem_w_l,
               io_r_ack_l,iocpt,nwback,fifo)
    VARIABLE smp_w_v,smpio_v : type_smp;
    VARIABLE reqena_v,req_v,io_last_v,last_v : std_logic;
    VARIABLE no_v,not_v : natural RANGE  0 TO 4;
  BEGIN

    smpio_v:=(req=>io_w.req,busy=>io_w.req,a=>io_w.a,ah=>io_w.ah,
              op=>SINGLE,rw=>to_std_logic(is_write(io_w)),
              gbl=>'1',dit=>DI_DATA,lock=>'0');
              
    smp_w_v:=smpio_v;
    nwback_c<=nwback;
    no_v:=no;
    no_c<=no;
    not_v:=no;
    
    io_last_v:='0';
    iocpt_c<=iocpt;
    IF io_w.req='1' AND io_r_ack_l='1' THEN
      IF iocpt=0 THEN
        io_last_v:=to_std_logic(pb_blen(io_w)=1);
        iocpt_c<=pb_blen(io_w)-1;
      ELSE
        io_last_v:=to_std_logic(iocpt=1);
        iocpt_c<=iocpt-1;
      END IF;
    ELSIF no/=0 AND etat/=sIDLE THEN
      io_last_v:='1';
    END IF;
    
    etat_c<=etat;
    mlast_c<=mlast;
    last_v :='0';
    
    CASE etat IS
      -----------------------------
      WHEN sIDLE =>
        -- Nouvel accès
        IF lock='1' THEN
          no_v:=no;
        ELSE
          IF NCPU=1 THEN
            no_v:=ROBIN4(co('0','0',smp0_w.req,smpio_v.req,no));
          ELSIF NCPU=2 THEN
            no_v:=ROBIN4(co('0',smp1_w.req,smp0_w.req,smpio_v.req,no));
          ELSIF NCPU=3 THEN
            no_v:=ROBIN4(co(smp2_w.req,smp1_w.req,smp0_w.req,smpio_v.req,no));
          ELSE
            IF smpio_v.req='1' THEN
              no_v:=0;
            ELSIF smp0_w.req='1' THEN
              no_v:=1;
            ELSIF smp1_w.req='1' AND NCPU>=2 THEN
              no_v:=2;
            ELSIF smp2_w.req='1' AND NCPU>=3 THEN
              no_v:=3;
            ELSIF smp3_w.req='1' AND NCPU>=4 THEN
              no_v:=4;
            END IF;
          END IF;
        END IF;
        no_c<=no_v;
        not_v:=no_v;
        
        CASE no_v IS
          WHEN 0      => req_v:=smpio_v.req;
          WHEN 1      => req_v:=smp0_w.req;
          WHEN 2      => req_v:=smp1_w.req;
          WHEN 3      => req_v:=smp2_w.req;
          WHEN 4      => req_v:=smp3_w.req;
          WHEN OTHERS => req_v:='0';
        END CASE;
        
        reqena_v:='0';
        mlast_c<="00000";
        IF req_v='1' THEN
          etat_c<=sPRE;
        END IF;
        
        -----------------------------
      WHEN sPRE =>
        reqena_v:='0';
        etat_c<=sHIT;
        
        -----------------------------
      WHEN sHIT =>
        reqena_v:='0';
        IF cwb0='1' OR (cwb1='1' AND NCPU>=2) OR
           (cwb2='1' AND NCPU>=3) OR (cwb3='1' AND NCPU>=4) THEN
          etat_c<=sWBACK;
        ELSE
          etat_c<=sTRANS;
        END IF;
        mlast_c<=mlast OR (last3 & last2 & last1 & last0 & io_last_v);
        
        nwback_c<=1;
        -- Si 2 WBACK nécessaires,
        --  D'abord écriture ligne remplacée
        --  Puis writeback de l'autre CPU.
        IF NCPU=2 THEN
          IF cwb0='1' AND cwb1='1' THEN
            nwback_c<=mux(no=1,1,2);
          ELSIF cwb1='1' THEN
            nwback_c<=2;
          END IF;
        END IF;
        
        IF NCPU=3 THEN
          IF cwb0='1' AND cwb1='1' THEN
            nwback_c<=mux(no=1,1,2);
          ELSIF cwb0='1' AND cwb2='1' THEN
            nwback_c<=mux(no=1,1,3);
          ELSIF cwb1='1' AND cwb2='1' THEN
            nwback_c<=mux(no=2,2,3);
          ELSIF cwb1='1' THEN
            nwback_c<=2;
          ELSIF cwb2='1' THEN
            nwback_c<=3;
          END IF;
        END IF;
        
        IF NCPU=4 THEN
          IF cwb0='1' AND cwb1='1' THEN
            nwback_c<=mux(no=1,1,2);
          ELSIF cwb0='1' AND cwb2='1' THEN
            nwback_c<=mux(no=1,1,3);
          ELSIF cwb0='1' AND cwb3='1' THEN
            nwback_c<=mux(no=1,1,4);
          ELSIF cwb1='1' AND cwb2='1' THEN
            nwback_c<=mux(no=2,2,3);
          ELSIF cwb1='1' AND cwb3='1' THEN
            nwback_c<=mux(no=2,2,4);
          ELSIF cwb2='1' AND cwb3='1' THEN
            nwback_c<=mux(no=3,3,4);
          ELSIF cwb1='1' THEN
            nwback_c<=2;
          ELSIF cwb2='1' THEN
            nwback_c<=3;
          ELSIF cwb3='1' THEN
            nwback_c<=4;
          END IF;
        END IF;
        
      -----------------------------
      WHEN sTRANS =>
        reqena_v:='1';
        mlast_c<=mlast OR (last3 & last2 & last1 & last0 & io_last_v);
        last_v:=andlast(mlast OR (last3 & last2 & last1 & last0 & io_last_v));
        
        IF last_v='1' THEN
          etat_c<=sIDLE;
        END IF;
        
      -- WHEN sWAIT =>
      --   mlast_c<=mlast OR (last3 & last2 & last1 & last0 & io_last_v);
      --   last_v:=andlast(mlast OR (last3 & last2 & last1 & last0 & io_last_v));
        
      --   reqena_v:='0';
      --   IF last_v='1' THEN
      --     etat_c<=sIDLE;
      --   END IF;
        
      -----------------------------
      WHEN sWBACK =>
        not_v:=nwback;
        reqena_v:='1';
        mlast_c<=mlast OR (last3 & last2 & last1 & last0 & io_last_v);
        last_v:=andlast(mlast OR (last3 & last2 & last1 & last0 & io_last_v));
        
        IF cwb0='0' AND (cwb1='0' OR NCPU<2) AND
           (cwb2='0' OR NCPU<3) AND (cwb3='0' OR NCPU<4) THEN
          -- Après la fin du burst WBACK
          etat_c<=sTRANS;
        END IF;
        
        IF cwb0='1' AND
          (cwb1='0' OR NCPU<2) AND
          (cwb2='0' OR NCPU<3) AND
          (cwb3='0' OR NCPU<4) THEN
          nwback_c<=1;
        END IF;
        IF cwb0='0' AND
          (cwb1='1' AND NCPU>=2) AND
          (cwb2='0' OR NCPU<3) AND
          (cwb3='0' OR NCPU<4) THEN
          nwback_c<=2;
        END IF;
        IF cwb0='0' AND
          (cwb1='0' AND NCPU>=3) AND
          (cwb2='1' AND NCPU>=3) AND
          (cwb3='0' OR NCPU<4) THEN
          nwback_c<=3;
        END IF;
        IF cwb0='0' AND
          (cwb1='0' AND NCPU=4) AND
          (cwb2='0' AND NCPU=4) AND
          (cwb3='1' OR NCPU=4) THEN
          nwback_c<=4;
        END IF;
        
    END CASE;
    
    -------------------------------------------
    CASE no_v IS
      WHEN 1      => smp_w_v:=smp0_w;
      WHEN 2      => smp_w_v:=smp1_w;
      WHEN 3      => smp_w_v:=smp2_w;
      WHEN 4      => smp_w_v:=smp3_w;
      WHEN OTHERS => smp_w_v:=smpio_v;
    END CASE;
    
    smp_r<=smp_w_v;
    IF etat/=sIDLE THEN
      smp_r.req<='0';
    END IF;
    smp_r.busy<=smp_w_v.req OR to_std_logic(etat/=sIDLE);
    IF mem_w_l.lock='1' AND mem_w_l.req='1' AND mem_r.ack='1' THEN
      lock_c<='1';
    ELSIF mem_w_l.lock='0' THEN
      lock_c<='0';
    ELSE
      lock_c<=lock;
    END IF;
    
    -------------------------------------------
    cpu0_r<=mem_r;
    cpu1_r<=mem_r;
    cpu2_r<=mem_r;
    cpu3_r<=mem_r;
    io_r  <=mem_r;
    
    cpu0_r.ack<='0';
    cpu1_r.ack<='0';
    cpu2_r.ack<='0';
    cpu3_r.ack<='0';
    io_r.ack  <='0';
    io_r_ack_l<='0';
    
    CASE not_v IS
      WHEN 1      => mem_w_l<=cpu0_w; mem_w_l.req<=cpu0_w.req AND reqena_v;
      WHEN 2      => mem_w_l<=cpu1_w; mem_w_l.req<=cpu1_w.req AND reqena_v;
      WHEN 3      => mem_w_l<=cpu2_w; mem_w_l.req<=cpu2_w.req AND reqena_v;
      WHEN 4      => mem_w_l<=cpu3_w; mem_w_l.req<=cpu3_w.req AND reqena_v;
      WHEN OTHERS => mem_w_l<=io_w;   mem_w_l.req<=io_w.req   AND reqena_v;
    END CASE;
    CASE not_v IS
      WHEN 1      => cpu0_r.ack<=mem_r.ack AND reqena_v;
      WHEN 2      => cpu1_r.ack<=mem_r.ack AND reqena_v;
      WHEN 3      => cpu2_r.ack<=mem_r.ack AND reqena_v;
      WHEN 4      => cpu3_r.ack<=mem_r.ack AND reqena_v;
      WHEN OTHERS => io_r.ack  <=mem_r.ack AND reqena_v;
                     io_r_ack_l<=mem_r.ack AND reqena_v;
    END CASE;
    
    not_c<=not_v;
    
    -------------------------------------------
    cpu0_r.dreq<='0';
    cpu1_r.dreq<='0';
    cpu2_r.dreq<='0';
    cpu3_r.dreq<='0';
    io_r.dreq<='0';
    
    mem_w_l.dack<='0';
    CASE fifo(0) IS
      WHEN 1 =>
        cpu0_r.dreq <=mem_r.dreq;
        mem_w_l.dack<=cpu0_w.dack;
      WHEN 2 =>
        cpu1_r.dreq <=mem_r.dreq;
        mem_w_l.dack<=cpu1_w.dack;
      WHEN 3 =>
        cpu2_r.dreq <=mem_r.dreq;
        mem_w_l.dack<=cpu2_w.dack;
      WHEN 4 =>
        cpu3_r.dreq <=mem_r.dreq;
        mem_w_l.dack<=cpu3_w.dack;
      WHEN OTHERS =>
        io_r.dreq<=mem_r.dreq;
        mem_w_l.dack<=io_w.dack;
    END CASE;
    
  END PROCESS Comb;

  mem_w<=mem_w_l;
  -------------------------------------------------------------------------
  Seq:PROCESS(clk,reset_na)
    VARIABLE push_v,pop_v : std_logic;
  BEGIN
    IF reset_na='0' THEN
      etat<=sIDLE;
      level<=0;
      iocpt<=0;
      
    ELSIF rising_edge(clk) THEN
      etat<=etat_c;
      
      no<=no_c;
      nwback<=nwback_c;
      lock<=lock_c;
      mlast<=mlast_c;
      
      iocpt<=iocpt_c;
      -------------------------------------------
      push_v:=mem_w_l.req AND mem_r.ack AND mem_w_l.mode(1);
      pop_v :=mem_r.dreq AND mem_w_l.dack;
      
      -- FIFO
      IF pop_v='1' THEN
        fifo(0 TO PROF-2)<=fifo(1 TO PROF-1);
      END IF;
      IF push_v='1' AND pop_v='0' THEN
        -- Si empile
        fifo(level)<=not_c;
        level<=level+1;
      ELSIF push_v='1' AND pop_v='1' AND level/=0 THEN
        -- Si empile et dépile
        fifo(level-1)<=not_c;
      ELSIF push_v='0' AND pop_v='1' AND level/=0 THEN
        -- Si dépile
        level<=level-1;
      END IF;


      IF etat/=sIDLE THEN
        if xx_cpt<240 THEN
          xx_cpt<=xx_cpt+1;
        END IF;
      ELSE
        xx_cpt<=0;
      END IF;

      xx_max<=to_std_logic(xx_cpt>=128);
      IF xx_max='1' THEN
        etat<=sIDLE;
      END IF;
      
    END IF;
  END PROCESS Seq;

END ARCHITECTURE rtl;


-- IDLE
--  - REQ=1 -> PRE
-- req_o=0

-- PRE
-- - HIT=1 -> HIT, req_o=0
-- - HIT=0 & burst  & ack -> TRANS, req_o=1
-- - HIT=0 & !burst & ack -> IDLE

-- HIT
-- - CWB=1 -> WBACK, req_o=0
-- - CWB=0 -> TRANS, req_o=1

-- TRANS
-- req_o=1.
-- - Fin burst -> IDLE

-- WBACK
-- Select CWB
-- req_o=req_i
-- - Fin burst -> TRANS
