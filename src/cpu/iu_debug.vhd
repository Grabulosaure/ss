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
-- RTS 5153
-- CPU Debug port

-- CONTROL
-- 0     : RUN/STOP
-- 1     : 
-- 2     : RESET
-- 3     : STOPA
-- 4     : 
-- 5     : PPC
-- 6     : IBRK_ENA CPU
-- 7     : DBRK_ENA CPU

-- 11:8  : DEBUG_C :
--         (0) : SLOW/FAST UART
-- 13:12 : Reserved for CPU select in MP mode.
-- 15;14 : OPT[1:0]
-- 31:16 : <unused>

-- STATUS
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
-- 15:12 : CPUEN (SMP)
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

ENTITY iu_debug IS
  GENERIC (
    ADRS : uv4 :=x"0"
    );
  PORT (
    -- Debug Link
    dl_w    : IN  type_dl_w;
    dl_r    : OUT type_dl_r;

    -- CPU
    debug_s : IN  type_debug_s;
    debug_t : OUT type_debug_t;
    debug_c : OUT uv4;
    
    dreset  : OUT std_logic;            -- Reset généré par le débugger
    stopa   : OUT std_logic;            -- Arrêt des périphériques
    
    xstop   : IN  std_logic;

    -- Glo
    reset_n  : IN  std_logic;            -- Reset
    clk      : IN  std_logic             -- Horloge
    );
END ENTITY iu_debug;

-------------------------------------------------------------------------------
ARCHITECTURE rtl OF iu_debug IS

  -- Writes
  CONSTANT WR_CONTROL : uv4 := x"8";
  CONSTANT WR_OPCODE  : uv4 := x"9";
  CONSTANT WR_IBRK    : uv4 := x"A";
  CONSTANT WR_DBRK    : uv4 := x"B";


  -- Reads
  CONSTANT RD_STATUS  : uv4 := x"1";
  CONSTANT RD_DATA    : uv4 := x"2";
  CONSTANT RD_PC      : uv4 := x"3";
  CONSTANT RD_NPC     : uv4 := x"4";
  CONSTANT RD_STATUS2 : uv4 := x"5";
  
  SIGNAL opcode,status,status2 : uv32;
  SIGNAL control,control_mem : uv32;
  SIGNAL vazy,run,stop : std_logic;
  SIGNAL xstop_mem : std_logic;
  
  SIGNAL dbrk,ibrk : uv32;
  SIGNAL dreset_pre,dreset_pre2 : std_logic;

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
            
          WHEN WR_OPCODE =>
            opcode<=dl_w.d;
            vazy<='1';
            
          WHEN WR_IBRK =>
            ibrk<=dl_w.d;
            
          WHEN WR_DBRK =>
            dbrk<=dl_w.d;

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

          ------------------------
          WHEN OTHERS =>
            dl_r.d<=x"0000_0000";
            
        END CASE;
        
      END IF;
      
      --------------------------------------
      control_mem<=control;
      xstop_mem<=xstop;
      
      stop<=(control(0) AND NOT control_mem(0)) OR
            (xstop AND NOT xstop_mem);
      run <=NOT control(0) AND control_mem(0);
      
      -------------------------------------
      dreset_pre2<=control(2);
      dreset_pre <=dreset_pre2;
      dreset     <=dreset_pre;

      IF reset_n='0' THEN
        control(31 DOWNTO 8)<=x"000000";
        control_mem(31 DOWNTO 8)<=x"000000";
        control(5 DOWNTO 0)<="000000";
        control_mem(5 DOWNTO 0)<="000000";
        stop<='0';
        run<='0';
        dl_r.rd<='0';
        dreset<='0';
        dreset_pre2<='0';
        dreset_pre<='0';
      END IF;      

    END IF;

  END PROCESS Coccinelle;

  -------------------------------------------------

  -- control(0) : Stop=1/Run=0
  stopa         <=control(3) AND (debug_s.dstop OR debug_s.halterror);
                                  -- Arrêt périphériques
  debug_t.ena   <='1';
  debug_t.stop  <=stop;
  debug_t.run   <=run;
  debug_t.vazy  <=vazy;
  debug_t.op    <=opcode;
  debug_t.code  <=work.plomb_pack.PB_OK;
  debug_t.ppc   <=control(5);
  debug_t.opt   <=control(15 DOWNTO 14);
  debug_t.ib    <=ibrk;
  debug_t.db    <=dbrk;
  debug_t.ib_ena<=control(6);           -- Point d'arrêt instructions
  debug_t.db_ena<=control(7);           -- Point d'arrêt données

  debug_c       <=control(11 DOWNTO 8);
  
  status(0)            <=debug_s.dstop;
  status(1)            <='0';
  status(2)            <=debug_s.halterror;
  status(3)            <='0';
  status(4)            <=debug_s.psr.s;
  status(5)            <=debug_s.psr.ps;
  status(6)            <=debug_s.psr.et;
  status(7)            <=debug_s.psr.ef;
  status(8)            <=debug_s.psr.icc.c;
  status(9)            <=debug_s.psr.icc.v;
  status(10)           <=debug_s.psr.icc.z;
  status(11)           <=debug_s.psr.icc.n;
  status(15 DOWNTO 12) <="0001";        -- CPUEN
  status(19 DOWNTO 16) <=debug_s.irl;
  status(22 DOWNTO 20) <=debug_s.fccv & debug_s.fcc;
  status(23)           <=debug_s.trap.t;
  status(31 DOWNTO 24) <=debug_s.trap.tt;
  
  status2(7  DOWNTO 0) <=debug_s.tbr.tt;
  status2(15 DOWNTO 8) <=debug_s.hetrap.tt;
  status2(31 DOWNTO 16)<=debug_s.stat;
  
END ARCHITECTURE rtl;
