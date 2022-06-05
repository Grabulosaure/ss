--------------------------------------------------------------------------------
-- TEM : TACUS
-- Interface debug/trace/emulateur
--------------------------------------------------------------------------------
-- DO 5/2011
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

-- CPU Debug port, SMP

-- CONTROL
-- 0     : RUN/STOP CPU(x)
-- 1     : 
-- 2     : RESET (shared)
-- 3     : STOPA (shared)
-- 4     : 
-- 5     : PPC (shared)
-- 6     : IBRK_ENA CPU(x)
-- 7     : DBRK_ENA CPU(x)

-- 11:8  : DEBUG_C :
--         (0) : SLOW/FAST UART
-- 13:12 : CPU SELECT
-- 15;14 : OPT[1:0]
-- 31:16 : <unused>

-- STATUS (for currently selected CPU)
-- 0     : DSTOP
-- 1     : 0
-- 2     : HALTERROR
-- 3     : 0
-- 4     : psr.s
-- 5     : psr.ps
-- 6     : psr.et
-- 7     : psr.ef
-- 8     : psr.icc.c
-- 9     : psr.icc.v
-- 10    : psr.icc.z
-- 11    : psr.icc.n
-- 15:12 : CPUEN
-- 19:16 : IRL
-- 22:20 : FCCV & FCC
-- 23    : TRAP.T
-- 31:24 : TRAP.TT

-- STATUS2
-- 7:0   : TBR.TT
-- 15:8  : HETRAP.TT
-- 31:16 : <unused>

--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

USE work.base_pack.ALL;
USE work.iu_pack.ALL;
USE work.plomb_pack.ALL;

ENTITY iu_debug_mp IS
  GENERIC (
    ADRS : uv4 :=x"0";
    CPU0 : boolean := true;
    CPU1 : boolean := false;
    CPU2 : boolean := false;
    CPU3 : boolean := false);
  PORT (
    -- Debug Link
    dl_w     : IN  type_dl_w;
    dl_r     : OUT type_dl_r;
    
    -- Port débug CPUs
    debug0_s : IN  type_debug_s;
    debug0_t : OUT type_debug_t;
    
    debug1_s : IN  type_debug_s;
    debug1_t : OUT type_debug_t;
    
    debug2_s : IN  type_debug_s;
    debug2_t : OUT type_debug_t;
    
    debug3_s : IN  type_debug_s;
    debug3_t : OUT type_debug_t;
    
    debug_c : OUT uv4;
    
    dreset  : OUT std_logic;            -- Reset généré par le débugger
    stopa   : OUT std_logic;            -- Arrêt des périphériques
    
    xstop   : IN  std_logic;

    -- Glo
    reset_n  : IN  std_logic;            -- Reset
    clk      : IN  std_logic             -- Horloge
    );
END ENTITY iu_debug_mp;

-------------------------------------------------------------------------------
ARCHITECTURE rtl OF iu_debug_mp IS
  CONSTANT CPUEN : uv4 :=to_std_logic(CPU3) & to_std_logic(CPU2) &
                         to_std_logic(CPU1) & to_std_logic(CPU0);
  
  -- Writes
  CONSTANT WR_CONTROL : uv4 := x"8";
  CONSTANT WR_OPCODE  : uv4 := x"9";
  CONSTANT WR_IBRK    : uv4 := x"A";
  CONSTANT WR_DBRK    : uv4 := x"B";

  CONSTANT WR_TEST    : uv4 := x"E";

  -- Reads
  CONSTANT RD_STATUS  : uv4 := x"1";
  CONSTANT RD_DATA    : uv4 := x"2";
  CONSTANT RD_PC      : uv4 := x"3";
  CONSTANT RD_NPC     : uv4 := x"4";
  CONSTANT RD_STATUS2 : uv4 := x"5";
  
  CONSTANT RD_TEST    : uv4 := x"6";
  
  SIGNAL opcode,status,status2 : uv32;
  SIGNAL control,control_mem : uv32;
  SIGNAL vazy : std_logic;
  SIGNAL run,stop : uv4;
  SIGNAL xstop_mem : std_logic;
  
  SIGNAL debug_s : type_debug_s;
  SIGNAL sel : uv2;
  SIGNAL controlx,controlx_mem : arr_uv8(0 TO 3);
  SIGNAL ibrk,dbrk : arr_uv32(0 TO 3);
  SIGNAL dreset_pre,dreset_pre2 : std_logic;
  SIGNAL test : uv32;
  
BEGIN
  
  ------------------------------------------------------------------------------
  Coccinelle:PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      --------------------------------------
      vazy<='0';
      dl_r.rd<='0';
      dl_r.d<=x"0000_0000";
      
      --------------------------------------
      IF dl_w.wr='1' AND dl_w.a=ADRS THEN
        CASE dl_w.op IS
          ------------------------
          WHEN WR_CONTROL =>
            control<=dl_w.d;
            IF dl_w.d(13 DOWNTO 12)="01" AND CPU1 THEN
              controlx(1)<=dl_w.d(7 DOWNTO 0);
              sel<="01";
            ELSIF dl_w.d(13 DOWNTO 12)="10" AND CPU2 THEN
              controlx(2)<=dl_w.d(7 DOWNTO 0);
              sel<="10";
            ELSIF dl_w.d(13 DOWNTO 12)="11" AND CPU3 THEN
              controlx(3)<=dl_w.d(7 DOWNTO 0);
              sel<="11";
            ELSE
              controlx(0)<=dl_w.d(7 DOWNTO 0);
              sel<="00";
            END IF;
            
          WHEN WR_OPCODE =>
            opcode<=dl_w.d;
            vazy<='1';
            
          WHEN WR_IBRK =>
            ibrk(to_integer(sel))<=dl_w.d;
            
          WHEN WR_DBRK =>
            dbrk(to_integer(sel))<=dl_w.d;
            
          WHEN WR_TEST =>
            test<=dl_w.d;
            
          ------------------------
          WHEN RD_STATUS =>
            dl_r.d<=status;
            dl_r.rd<='1';
            
          WHEN RD_STATUS2 =>
            dl_r.d<=status2;
            dl_r.rd<='1';
            
          WHEN RD_DATA =>
            dl_r.d<=debug_s.d;
            dl_r.rd<='1';
            
          WHEN RD_PC =>
            dl_r.d<=debug_s.pc(31 DOWNTO 2) & "00";
            dl_r.rd<='1';

          WHEN RD_NPC =>
            dl_r.d<=debug_s.npc(31 DOWNTO 2) & "00";
            dl_r.rd<='1';

          WHEN RD_TEST =>
            dl_r.d<=test;
            dl_r.rd<='1';
            
          ------------------------
          WHEN OTHERS =>
            dl_r.d<=x"0000_0000";
            
        END CASE;
        
      END IF;

      --------------------------------------
      control_mem<=control;
      controlx_mem<=controlx;
      
      xstop_mem<=xstop;
	  
      FOR I IN 0 TO 3 LOOP
          stop(I)<=(controlx(I)(0) AND NOT controlx_mem(I)(0)) OR
                    (xstop AND NOT xstop_mem);
          run(I) <=NOT controlx(I)(0) AND controlx_mem(I)(0);
      END LOOP;
      --------------------------------------
      dreset_pre2<=control(2);
      dreset_pre <=dreset_pre2;
      dreset     <=dreset_pre;

      IF reset_n='0' THEN
        control<=x"00000000";
        control_mem<=x"00000000";
        controlx<=(x"00",x"00",x"00",x"00");
        controlx_mem<=(x"00",x"00",x"00",x"00");
        stop<="0000";
        run <="0000";
        dreset<='0';
        dreset_pre2<='0';
        dreset_pre<='0';
      END IF;
    END IF;
  END PROCESS Coccinelle;

  debug_s<=debug1_s WHEN sel="01" AND CPU1 ELSE
           debug2_s WHEN sel="10" AND CPU2 ELSE
           debug3_s WHEN sel="11" AND CPU3 ELSE
           debug0_s;
  
  -------------------------------------------------
  
  -- control(0) : Stop=1/Run=0
  stopa         <=control(3) AND (debug_s.dstop OR debug_s.halterror);
                                  -- Arrêt périphériques
  debug0_t.ena   <='1';
  debug0_t.stop  <=stop(0);
  debug0_t.run   <=run(0);
  debug0_t.vazy  <=vazy AND to_std_logic(sel="00" OR CPUEN="0001");
  debug0_t.op    <=opcode;
  debug0_t.code  <=work.plomb_pack.PB_OK;
  debug0_t.ppc   <=control(5);
  debug0_t.opt   <=control(15 DOWNTO 14);
  debug0_t.ib    <=ibrk(0);
  debug0_t.db    <=dbrk(0);
  debug0_t.ib_ena<=controlx(0)(6);           -- Point d'arrêt instructions
  debug0_t.db_ena<=controlx(0)(7);           -- Point d'arrêt données

  debug1_t.ena   <='1';
  debug1_t.stop  <=stop(1);
  debug1_t.run   <=run(1);
  debug1_t.vazy  <=vazy AND to_std_logic(sel="01");
  debug1_t.op    <=opcode;
  debug1_t.code  <=work.plomb_pack.PB_OK;
  debug1_t.ppc   <=control(5);
  debug1_t.opt   <=control(15 DOWNTO 14);
  debug1_t.ib    <=ibrk(1);
  debug1_t.db    <=dbrk(1);
  debug1_t.ib_ena<=controlx(1)(6);
  debug1_t.db_ena<=controlx(1)(7);

  debug2_t.ena   <='1';
  debug2_t.stop  <=stop(2);
  debug2_t.run   <=run(2);
  debug2_t.vazy  <=vazy AND to_std_logic(sel="10");
  debug2_t.op    <=opcode;
  debug2_t.code  <=work.plomb_pack.PB_OK;
  debug2_t.ppc   <=control(5);
  debug2_t.opt   <=control(15 DOWNTO 14);
  debug2_t.ib    <=ibrk(2);
  debug2_t.db    <=dbrk(2);
  debug2_t.ib_ena<=controlx(2)(6);
  debug2_t.db_ena<=controlx(2)(7);

  debug3_t.ena   <='1';
  debug3_t.stop  <=stop(3);
  debug3_t.run   <=run(3);
  debug3_t.vazy  <=vazy AND to_std_logic(sel="11");
  debug3_t.op    <=opcode;
  debug3_t.code  <=work.plomb_pack.PB_OK;
  debug3_t.ppc   <=control(5);
  debug3_t.opt   <=control(15 DOWNTO 14);
  debug3_t.ib    <=ibrk(3);
  debug3_t.db    <=dbrk(3);
  debug3_t.ib_ena<=controlx(3)(6);
  debug3_t.db_ena<=controlx(3)(7);
  
  debug_c       <=control(11 DOWNTO 8);
  
  status(0)            <=debug_s.dstop;
  status(1)            <=sel(0); -- Provisoire
  status(2)            <=debug_s.halterror;
  status(3)            <=sel(1); -- Provisoire
  status(4)            <=debug_s.psr.s;
  status(5)            <=debug_s.psr.ps;
  status(6)            <=debug_s.psr.et;
  status(7)            <=debug_s.psr.ef;
  status(8)            <=debug_s.psr.icc.c;
  status(9)            <=debug_s.psr.icc.v;
  status(10)           <=debug_s.psr.icc.z;
  status(11)           <=debug_s.psr.icc.n;
  status(15 DOWNTO 12) <=CPUEN;
  status(19 DOWNTO 16) <=debug_s.irl;
  status(22 DOWNTO 20) <=debug_s.fccv & debug_s.fcc;
  status(23)           <=debug_s.trap.t;
  status(31 DOWNTO 24) <=debug_s.trap.tt;

  status2(7  DOWNTO 0) <=debug_s.tbr.tt;
  status2(15 DOWNTO 8) <=debug_s.hetrap.tt;
  status2(31 DOWNTO 16)<=debug_s.stat;
  
END ARCHITECTURE rtl;
