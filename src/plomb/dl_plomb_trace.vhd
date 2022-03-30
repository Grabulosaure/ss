--------------------------------------------------------------------------------
-- TEM : PLOMB
-- Trace
--------------------------------------------------------------------------------
-- DO 3/2011
--------------------------------------------------------------------------------
-- Trace. 512 entries

-- RD_DATA


-- <ajouter surveillance en direct des signaux>
-- <mode acquisition en continu, arrêt manuel>
-- Sélection pos. trig
-- Sélectiion brut/decode
-- Sélection mode trig :
--  - Ext [0:3]
--  - Adresse, RW, Amask
--  - Autres signaux
--  - Force trig manuel
-- Relecture paramètres traceur
-- Option SIG externes : 0 / 32 / 64
-- Relecture etat trig
-- Start/reset

-- <OFF>

-- start=1
--  <ENA> : Acquisitions en continu
-- trig
--  <mémorise CPT, ENA=1>
-- fin parcours
--  <OFF>

--------------------------------------------------
-- WRITES

-- SEL
--   Clear read Pointer

-- START
-- 0 : START
-- 1 : CLR

-- CONF
-- Il faut que toutes les sources sélectionnées soient actives
--  3:0  : Tsource
--    0  : Ext 0
--    1  : Ext 1
--    2  : Ext 2
--    3  : Ext 4
--    4  : Addrmask
--  6:5  : R/W = 00=Ignore, 01=Lecture seule 10=Ecriture seule
--    7  : SIGS
--   16  : 0=Brut   1=Norm (default)
--   17  : 0=NoDiff 1=Diff (default)
--   18  : ForceTrigMan.
-- 21:20 : POS : 00 = PRE 01= 50% 10 = POST

-- 31:24 : GPO(7:0)

--------------------------------------------------
-- LECTURES
-- PARM :
-- (constantes instantiation bloc)
--  7:0  : SIGS : 0=Sans 1=32bits 2=64bits
--  15:8 : PROF : 2=512
--  8    : ENAH

-- STAT :
--  1:0 :
--   0 = OFF
--   1 = Armé
--   2 = Acquisition en cours
--   3 = Fini
-- 31:16 = CPTIN

-- PTR : (provisoire)
--  15:0 : PTRIN
--  31:16 : PTROUT

-- ADDR :
--    ADDR / AMASK / SIGMASK
--    SIGMASK : 7;0 : DATA  23;16 : MASK
     
-- 512 enregistrements
-- 4 * 2ko
--   0 :  A[31:0]
--   1 : DW[31:0]
--   2 : Contôles
--   3 : DR[31:0]
--   4 : SIG[63:32]
--   5 : SIG[31:0]

--   31:28 : AH[35:32] / TimeCode(15:12)
--   27:16 : TimeCode(11:0)
--   15:14 : Burst
--   13:12 : MODE
--   11:8  : BE[0:3]
--    7:6  : "00"
--    5:0  : ASI


-- - Soit impulsion trig.
-- - Soit trig toujours actif, puis arrêt automatique après un délai.

--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY std;
USE std.textio.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.plomb_pack.ALL;

ENTITY dl_plomb_trace IS
  GENERIC (
    ADRS : uv4     :=x"4";
    SIGS : natural RANGE 0 TO 64;
    ENAH : boolean := true; -- true = Timecode[15 : 12] / false = AH[35 : 32]
    PROF : natural :=20);
  PORT (
    -- Debug Link
    dl_w     : IN  type_dl_w;
    dl_r     : OUT type_dl_r;
    
    -- PLOMB
    pw       : IN  type_plomb_w;
    pr       : IN  type_plomb_r;
    sig      : IN  unsigned(SIGS-1 DOWNTO 0);
    
    trig     : IN  uv4;
    trigo    : OUT std_logic;
    gpo      : OUT uv8;
    timecode : IN  uv32;
    astart   : IN std_logic;
    
    -- Global
    clk      : IN  std_logic;
    reset_na : IN  std_logic
    );
END ENTITY dl_plomb_trace;

--##############################################################################

ARCHITECTURE rtl OF dl_plomb_trace IS
  
  -- Writes
  CONSTANT WR_START : uv4 :=x"8";
  --CONSTANT WR_TRIG  : uv4 :=x"9";
  CONSTANT WR_SEL   : uv4 :=x"A";
  CONSTANT WR_CONF  : uv4 :=x"B";
  CONSTANT WR_ADDR  : uv4 :=x"C";

  -- Reads
  CONSTANT RD_DATA : uv4 :=x"1";
  CONSTANT RD_STAT : uv4 :=x"2";
  CONSTANT RD_PARM : uv4 :=x"3";
  --CONSTANT RD_CONF : uv4 :=x"5";

  SIGNAL pos : uv2;
  SIGNAL brut,diff : std_logic;
  SIGNAL tmask : uv8;
  SIGNAL ftrig,ftrig2 : std_logic; -- Force Trig
  SIGNAL trigx,trigx2 : std_logic;
  SIGNAL trig_addr,trig_amask : uv32;
  SIGNAL trig_sdat,trig_smask : uv8;
  SIGNAL cptmask : uint2;
  
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
  
  SIGNAL a1_w,a2_w,a3_w,a4_w,a5_w,a6_w : type_pvc_w;
  SIGNAL a1_r,a2_r,a3_r,a4_r,a5_r,a6_r : type_pvc_r;
  SIGNAL b1_w,b2_w,b3_w,b4_w,b5_w,b6_w : type_pvc_w;
  SIGNAL b1_r,b2_r,b3_r,b4_r,b5_r,b6_r : type_pvc_r;

  SIGNAL rpw : type_plomb_w;
  SIGNAL rpr : type_plomb_r;
  
  SIGNAL cpt,cpt_mem : unsigned(8 DOWNTO 0);
  SIGNAL ena,clr,acq,start,start2,stop,done : std_logic;
  SIGNAL state : uv2;

  TYPE arr_fifo IS ARRAY(0 TO PROF-1) OF unsigned(8 DOWNTO 0);
  SIGNAL level : natural RANGE 0 TO PROF;
  SIGNAL levv : std_logic;
  SIGNAL fifo : arr_fifo;
  SIGNAL sel : uv3;

  SIGNAL ptrout : unsigned(10 DOWNTO 2);
  SIGNAL incptrout,clrptrout : std_logic;

  SIGNAL mem_dr : uv32;

  SIGNAL sigi : uv64;
  
--------------------------------------------------------------------------------
BEGIN

  -- Blocs
  i_iram_bi1: iram_dp
    GENERIC MAP (N => 11,OCT => false)
    PORT MAP (
      mem1_w   => a1_w,      mem1_r   => a1_r,
      clk1     => clk,       reset1_na => reset_na,
      mem2_w   => b1_w,      mem2_r   => b1_r,
      clk2     => clk,       reset2_na => reset_na);
    
  i_iram_bi2: iram_dp
    GENERIC MAP (N => 11,OCT => false)
    PORT MAP (
      mem1_w   => a2_w,      mem1_r   => a2_r,
      clk1     => clk,       reset1_na => reset_na,
      mem2_w   => b2_w,      mem2_r   => b2_r,
      clk2     => clk,       reset2_na => reset_na);
    
  i_iram_bi3: iram_dp
    GENERIC MAP (N => 11,OCT => false)
    PORT MAP (
      mem1_w   => a3_w,      mem1_r   => a3_r,
      clk1     => clk,       reset1_na => reset_na,
      mem2_w   => b3_w,      mem2_r   => b3_r,
      clk2     => clk,       reset2_na => reset_na);
    
  i_iram_bi4: iram_dp
    GENERIC MAP (N => 11,OCT => false)
    PORT MAP (
      mem1_w   => a4_w,      mem1_r   => a4_r,
      clk1     => clk,       reset1_na => reset_na,
      mem2_w   => b4_w,      mem2_r   => b4_r,
      clk2     => clk,       reset2_na => reset_na);

  GenSig0: IF SIGS>0 GENERATE
    i_iram_bi5: iram_dp
      GENERIC MAP (N => 11,OCT => false)
      PORT MAP (
        mem1_w   => a5_w,      mem1_r   => a5_r,
        clk1     => clk,       reset1_na => reset_na,
        mem2_w   => b5_w,      mem2_r   => b5_r,
        clk2     => clk,       reset2_na => reset_na);
  END GENERATE GenSig0;
  
  GenSig1:IF SIGS>32 GENERATE
    i_iram_bi6: iram_dp
      GENERIC MAP (N => 11,OCT => false)
      PORT MAP (
        mem1_w   => a6_w,      mem1_r   => a6_r,
        clk1     => clk,       reset1_na => reset_na,
        mem2_w   => b6_w,      mem2_r   => b6_r,
        clk2     => clk,       reset2_na => reset_na);
  END GENERATE GenSig1;
  
  --------------------------------------
  Reg:PROCESS(clk,reset_na,astart)
    VARIABLE bw : type_pvc_w;
    VARIABLE push,pusho,pop : std_logic;
    VARIABLE trig_v : std_logic;
  BEGIN
    IF reset_na='0' THEN
      cpt<="000000000";
      --ena<='0';
      level<=0;
      levv<='0';
      trigx<='0';
      trigx2<='0';
      ena<=astart;
               
    ELSIF rising_edge(clk) THEN
      rpw<=pw;
      rpr<=pr;
      IF brut='0' THEN
        --------------------------------------------------------------------
        -- Mode intelligent
        -- Pipe Write
        pusho:=rpw.req AND rpr.ack AND ena;
        bw.req:='1';
        bw.be:="1111";
        bw.wr:=ena;
        bw.a:="000000000000000000000" & cpt & "00";
        bw.ah:=x"0";
        bw.dw:=rpw.a;
        a1_w<=bw;      
        bw.dw:=rpw.d;
        a2_w<=bw;
        IF ENAH THEN
          bw.dw(31 DOWNTO 28):=rpw.ah;
        ELSE
          bw.dw(31 DOWNTO 28):=timecode(15 DOWNTO 12);
        END IF;
        bw.dw(27 DOWNTO 16):=timecode(11 DOWNTO 0);
        bw.dw(15 DOWNTO 14):=rpw.burst;
        bw.dw(13 DOWNTO 12):=rpw.mode;
        bw.dw(11 DOWNTO 8) :=rpw.be;
        bw.dw(7  DOWNTO 6) :="00";
        bw.dw(5  DOWNTO 0) :=rpw.asi(5 DOWNTO 0);
        a3_w<=bw;
        push:=pusho AND rpw.mode(1);
        
        bw.dw:=sigi(63 DOWNTO 32);
        a5_w<=bw;
        bw.dw:=sigi(31 DOWNTO 0);
        a6_w<=bw;

        -- Pipe Read
        pop :=rpr.dreq AND rpw.dack;
        a4_w.req<='1';
        a4_w.be<="1111";
        a4_w.wr<=pop;
        a4_w.a<="000000000000000000000" & fifo(level) & "00";
        a4_w.ah<=x"0";
        CASE rpr.code IS
          WHEN PB_OK =>
            a4_w.dw<=rpr.d;
          WHEN PB_ERROR =>
--          a4_w.dw<=x"BADC0DE" & x"1";
            a4_w.dw<=rpr.d;
            a4_w.dw(23 DOWNTO 20)<=x"1";
          WHEN PB_FAULT =>
--          a4_w.dw<=x"BADC0DE" & x"2";
            a4_w.dw<=rpr.d;
            a4_w.dw(23 DOWNTO 20)<=x"2";
          WHEN PB_SPEC  =>
--          a4_w.dw<=x"BADC0DE" & x"3";
            a4_w.dw<=rpr.d;
            a4_w.dw(23 DOWNTO 20)<=x"3";
        END CASE;
        
      ELSE
        --------------------------------------------------------------------
        -- Mode Brut
        pusho:=ena;
        push:=pusho;
        pop:='0';
        bw.req:='1';
        bw.be:="1111";
        bw.wr:=ena;
        bw.a:="000000000000000000000" & cpt & "00";
        bw.ah:=x"0";
        bw.dw:=rpw.a;
        a1_w<=bw;
        bw.dw:=rpw.d;
        a2_w<=bw;
        bw.dw(31 DOWNTO 28):=rpw.dack & rpr.dreq & rpr.ack & rpw.req;
        bw.dw(27 DOWNTO 16):=timecode(11 DOWNTO 0);
        bw.dw(15 DOWNTO 14):=rpw.burst;
        bw.dw(13 DOWNTO 12):=rpw.mode;
        bw.dw(11 DOWNTO 8) :=rpw.be;
        bw.dw(7  DOWNTO 6) :="00";
        bw.dw(5  DOWNTO 0) :=rpw.asi(5 DOWNTO 0);
        a3_w<=bw;
        CASE rpr.code IS
          WHEN PB_OK =>
            bw.dw:=rpr.d;
          WHEN PB_ERROR =>
--            bw.dw:=x"BADC0DE" & x"1";
            bw.dw:=rpr.d;
            bw.dw(23 DOWNTO 20):=x"1";
          WHEN PB_FAULT =>
--            bw.dw:=x"BADC0DE" & x"2";
            bw.dw:=rpr.d;
            bw.dw(23 DOWNTO 20):=x"2";
          WHEN PB_SPEC =>
--            bw.dw:=x"BADC0DE" & x"3";
            bw.dw:=rpr.d;
            bw.dw(23 DOWNTO 20):=x"3";
        END CASE;
        a4_w<=bw;

        bw.dw:=sigi(63 DOWNTO 32);
        a5_w<=bw;
        bw.dw:=sigi(31 DOWNTO 0);
        a6_w<=bw;
      END IF;
      --------------------------------------------------------------------
      sigi<=(OTHERS =>'0');
      sigi(SIGS-1 DOWNTO 0)<=sig;
      
      IF clr='1' THEN
        cpt<="000000000";
        level<=0;
        levv<='0';
        ena<='0';
        acq<='0';
        done<='0';
      ELSIF pusho='1' THEN
        cpt<=cpt+1;
      END IF;
      
      --------------------------------------------------------------------
      -- FIFO
      IF push='1' THEN
        fifo<=cpt & fifo(0 TO PROF-2);
      END IF;
      IF push='1' AND pop='0' THEN
        IF levv='1' THEN
          level<=level+1;
        END IF;
        levv<='1';
      ELSIF push='0' AND pop='1' THEN
        IF level=0 THEN
          levv<='0';
        ELSE
          level<=level-1;
        END IF;
      END IF;
      
      --------------------------------------------------------------------
      --    0  : Ext 0
      --    1  : Ext 1
      --    2  : Ext 2
      --    3  : Ext 3
      --    4  : Addrmask
      --  6:5  : R/W = 00=Ignore, 01=Lecture seule 10=Ecriture seule
      --   18  : ForceTrigMan.
      trig_v:=ena;
      IF tmask(0)='1' THEN
        trig_v:=trig_v AND trig(0);
      END IF;
      IF tmask(1)='1' THEN
        trig_v:=trig_v AND trig(1);
      END IF;
      IF tmask(2)='1' THEN
        trig_v:=trig_v AND trig(2);
      END IF;
      IF tmask(3)='1' THEN
        trig_v:=trig_v AND trig(3);
      END IF;
      IF tmask(4)='1' THEN 
        trig_v:=trig_v AND to_std_logic((pw.a AND trig_amask) = trig_addr) AND
                 pw.req;
      END IF;
      IF tmask(6 DOWNTO 5)="01" THEN
        trig_v:=trig_v AND to_std_logic(is_read(pw));
      END IF;
      IF tmask(6 DOWNTO 5)="10" THEN
        trig_v:=trig_v AND to_std_logic(is_write(pw));
      END IF;
      IF tmask(6 DOWNTO 5)="11" THEN
        trig_v:='0';
      END IF;
      IF tmask(7)='1' THEN
        trig_v:=trig_v AND
                 to_std_logic((sigi(7 DOWNTO 0) AND trig_smask)=trig_sdat);
      END IF;
      trig_v:=trig_v OR ftrig;

      trigx<=trig_v;
      trigx2<=trigx;
        
      --------------------------------------------------------------------
      IF start='1' THEN
        ena<='1';
        acq<='0';
        done<='0';
      END IF;
      IF stop='1' THEN
        ena<='0';
        acq<='0';
        done<='0';
      END IF;
      
      IF trigx='1' AND trigx2='0' AND ena='1' THEN
        acq<='1';
        cpt_mem<=cpt;
      END IF;
      
      IF pos="00" AND acq='1' THEN
        -- PRE : Tous les échantillons sont avant le trig
        ena<='0';
        done<='1';
      ELSIF pos="01" AND acq='1' AND cpt=(NOT cpt_mem(8) & cpt_mem(7 DOWNTO 0))
      THEN
        -- 50% : Moitié/Moitié
        ena<='0';
        done<='1';
      ELSIF pos="10" AND acq='1' AND
        cpt=(NOT cpt_mem(8 DOWNTO 2) & cpt_mem(1 DOWNTO 0)) THEN
        -- POST : Echantillons a partir du trig
        ena<='0';
        done<='1';
      END IF;
      
      --------------------------------------------------------------------
      IF done='1' THEN
        state<="11";
      ELSIF acq='1' THEN
        state<="10";
      ELSIF ena='1' THEN
        state<="01";
      ELSE
        state<="00";
      END IF;
      --------------------------------------------------------------------

    END IF;
  END PROCESS Reg;

  trigo<=trigx;
  
  --------------------------------------
  Glo:PROCESS(clk,reset_na,astart) IS
    VARIABLE wrmem_v : std_logic;
  BEGIN
    IF reset_na='0' THEN
      IF astart='1' THEN
        --   ftrig2<='1';
        ftrig2<='0';
        start2<='1';
        tmask<=x"60";
      ELSE
        ftrig2<='0';
        start2<='0';
      END IF;
      brut<='0';
    ELSIF rising_edge(clk) THEN
      dl_r.d<=x"0000_0000";
      dl_r.rd<='0';
      incptrout<='0';
      clrptrout<='0';
      clr<='0';
      ftrig2<='0';
      start2<='0';
      ftrig<=ftrig2;
      start<=start2;
      stop<='0';
      
      --------------------------------------------
      IF dl_w.wr='1' AND dl_w.a=ADRS THEN
        CASE dl_w.op IS
          ------------------------
          WHEN WR_SEL =>
            sel<=dl_w.d(2 DOWNTO 0);
            clrptrout<='1';
            cptmask<=0;

          WHEN WR_START =>
            start2<=dl_w.d(0);
            clr  <=dl_w.d(1);
            ftrig2<=dl_w.d(2);
            stop <=dl_w.d(3);
            cptmask<=0;
            
          WHEN WR_CONF =>
            cptmask<=0;
            tmask<=dl_w.d(7 DOWNTO 0);
            brut <=NOT dl_w.d(16);
            diff <=dl_w.d(17);

            pos  <=dl_w.d(21 DOWNTO 20);
            gpo  <=dl_w.d(31 DOWNTO 24);

          WHEN WR_ADDR =>
            CASE cptmask IS
              WHEN 0 => trig_addr <=dl_w.d; cptmask<=1;
              WHEN 1 => trig_amask<=dl_w.d; cptmask<=2;
              WHEN 2 => trig_sdat <=dl_w.d(7 DOWNTO 0);
                        trig_smask<=dl_w.d(23 DOWNTO 16); cptmask<=3;
              WHEN OTHERS => NULL;
            END CASE;
            
          ------------------------
          WHEN RD_DATA =>
            dl_r.rd<='1';
            dl_r.d<=mem_dr;
            incptrout<='1';
            cptmask<=0;
            
          WHEN RD_STAT =>
            dl_r.rd<='1';
            dl_r.d<=uext(cpt,16) & to_unsigned(level,4) &
                    x"00" & "00" & state;
            cptmask<=0;
            
          WHEN RD_PARM =>
            dl_r.rd<='1';
            dl_r.d<=x"000" & "000" & to_std_logic(ENAH) &
                   x"02" & to_unsigned(SIGS,8);
            cptmask<=0;
            
          WHEN OTHERS =>
            cptmask<=0;
            
          ------------------------
        END CASE;
      END IF;
        
      --------------------------------------------
      CASE sel IS
        WHEN "000"  => mem_dr<=b1_r.dr;
        WHEN "001"  => mem_dr<=b2_r.dr;
        WHEN "010"  => mem_dr<=b3_r.dr;
        WHEN "011"  => mem_dr<=b4_r.dr;
        WHEN "100"  => mem_dr<=mux((SIGS>0) ,b5_r.dr,b1_r.dr);
        WHEN "101"  => mem_dr<=mux((SIGS>32),b6_r.dr,b1_r.dr);
        WHEN OTHERS => mem_dr<=b1_r.dr;
      END CASE;
          
      --------------------------------------------
      IF clrptrout='1' THEN
        ptrout<=(OTHERS =>'0');
      ELSIF incptrout='1' THEN
        ptrout<=ptrout+1;
      END IF;
        
    END IF;
  END PROCESS Glo;

  -- Relectures
  Comb:PROCESS(ptrout)
    VARIABLE bw : type_pvc_w;
  BEGIN
    bw.req:='1';
    bw.be:="1111";
    bw.wr:='0';
    bw.a(10 DOWNTO 0) :=ptrout & "00";
    bw.ah:=x"0";
    bw.dw:=x"00000000";
    b1_w<=bw;
    b2_w<=bw;
    b3_w<=bw;
    b4_w<=bw;
    b5_w<=bw;
    b6_w<=bw;
  
  END PROCESS Comb;

END ARCHITECTURE rtl;

