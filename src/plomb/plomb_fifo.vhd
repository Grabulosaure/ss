--------------------------------------------------------------------------------
-- TEM : PLOMB
-- FIFO
--------------------------------------------------------------------------------
-- DO 3/2008
--------------------------------------------------------------------------------
-- Modes :
--   DIRECT : Ne fait rien, transparent. Aucune FIFO.
--   COMB   : FIFO avec chemins combinatoires entre entrées et sorties, 0WS.
--   SYNC   : FIFO sans chemin combinatoire, 1WS.
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
--USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.plomb_pack.ALL;

ENTITY plomb_fifo IS
  GENERIC (
    PROF_W : positive :=2;              -- Profondeur de la FIFO côté W
    PROF_R : positive :=2;              -- Profondeur de la FIFO côté R
    MODE_W : enum_plomb_fifo :=SYNC;    -- Mode W
    MODE_R : enum_plomb_fifo :=SYNC);   -- Mode R
  PORT (
    -- Amont
    i_w      : IN  type_plomb_w;
    i_r      : OUT type_plomb_r;
    
    -- Aval
    o_w      : OUT type_plomb_w;
    o_r      : IN  type_plomb_r;

    -- Global
    clk      : IN std_logic;
    reset_n  : IN std_logic
    );
END ENTITY plomb_fifo;

--##############################################################################

ARCHITECTURE rtl OF plomb_fifo IS
  CONSTANT COMB_W : std_logic := to_std_logic(MODE_W=COMB);
  SIGNAL fifo_w : arr_plomb_w(0 TO PROF_W-1);
  SIGNAL lev_w : natural RANGE 0 TO PROF_W-1;
  SIGNAL vv_w : std_logic;
  SIGNAL notfull_w,i_ack : std_logic;
  
  CONSTANT COMB_R : std_logic := to_std_logic(MODE_R=COMB);
  SIGNAL fifo_r : arr_plomb_r(0 TO PROF_R-1);
  SIGNAL lev_r : natural RANGE 0 TO PROF_R-1;
  SIGNAL vv_r : std_logic;
  SIGNAL notfull_r,o_dack : std_logic;
BEGIN
  
  ------------------------------------------------------------------------------
  -- FIFO_W
  SyncW: PROCESS  (clk)
    VARIABLE push : boolean;
  BEGIN
    IF rising_edge(clk) THEN
      push:=(i_w.req='1' AND i_ack='1');
      
      IF push THEN
        fifo_w<=i_w & fifo_w(0 TO PROF_W-2);
      END IF;
      IF push AND (o_r.ack='0' OR (vv_w='0' AND MODE_W/=COMB)) THEN
        IF vv_w='1' THEN
          lev_w<=lev_w+1;
        END IF;
        vv_w<='1';
      ELSIF NOT push AND o_r.ack='1' THEN
        IF lev_w=0 THEN
          vv_w<='0';
        ELSE
          lev_w<=lev_w-1;
        END IF;
      END IF;

      IF reset_n = '0' THEN
        lev_w<=0;
        vv_w<='0';
      END IF;

    END IF;
  END PROCESS SyncW;
  
  CombW:PROCESS (fifo_w,lev_w,vv_w,i_w,o_dack)
  BEGIN
    IF MODE_W=DIRECT THEN
      o_w<=i_w;
    ELSE
      IF vv_w='0' AND MODE_W=COMB THEN
        o_w<=i_w;
      ELSE
        o_w<=fifo_w(lev_w);
      END IF;
      o_w.req<=vv_w OR (i_w.req AND COMB_W);
    END IF;
    o_w.dack<=o_dack;
  END PROCESS CombW;
  
  notfull_w<=to_std_logic((lev_w<PROF_W-1 AND PROF_W>1) OR
                          (vv_w='0' AND PROF_W=1));
  i_ack<=notfull_w OR (o_r.ack AND COMB_W) WHEN MODE_W/=DIRECT
            ELSE o_r.ack;
  
  ------------------------------------------------------------------------------
  -- FIFO_R
  SyncR: PROCESS  (clk)
    VARIABLE push : boolean;
  BEGIN
    IF rising_edge(clk) THEN
      push:=(o_r.dreq='1' AND o_dack='1');
      
      IF push THEN
        fifo_r<=o_r & fifo_r(0 TO PROF_R-2);
      END IF;
      IF push AND (i_w.dack='0' OR (vv_r='0' AND MODE_R/=COMB)) THEN
        IF vv_r='1' THEN
          lev_r<=lev_r+1;
        END IF;
        vv_r<='1';
      ELSIF NOT push AND i_w.dack='1' THEN
        IF lev_r=0 THEN
          vv_r<='0';
        ELSE
          lev_r<=lev_r-1;
        END IF;
      END IF;

      IF reset_n = '0' THEN
        lev_r<=0;
        vv_r<='0';
      END IF;

    END IF;
  END PROCESS SyncR;
  
  CombR:PROCESS (fifo_r,lev_r,vv_r,o_r,i_ack)
  BEGIN
    IF MODE_R=DIRECT THEN
      i_r<=o_r;
    ELSE
      IF vv_r='0' AND MODE_R=COMB THEN
        i_r<=o_r;
      ELSE
        i_r<=fifo_r(lev_r);
      END IF;
      i_r.dreq<=vv_r OR (o_r.dreq AND COMB_R);
    END IF;
    i_r.ack<=i_ack;
  END PROCESS CombR;
  
  notfull_r<=to_std_logic((lev_r<PROF_R-1 AND PROF_R>1) OR
                          (vv_r='0' AND PROF_R=1));
  o_dack<=notfull_r OR (i_w.dack AND COMB_R) WHEN MODE_R/=DIRECT
             ELSE i_w.dack;
  
  ------------------------------------------------------------------------------
END ARCHITECTURE rtl;
