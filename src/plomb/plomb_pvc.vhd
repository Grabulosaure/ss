--------------------------------------------------------------------------------
-- TEM : PLOMB
-- Interface bus PLOMB --> bus PVC
--------------------------------------------------------------------------------
-- DO 5/2007
--------------------------------------------------------------------------------
-- MODE :
--   R  : Read-Only
--   W  : Write-Only
--   RW : Read/Write
--------------------------------------------------------------------------------
--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

-- <AFAIRE> Optimiser. Revoir. Supprimer MODE

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.plomb_pack.ALL;

ENTITY plomb_pvc IS
  GENERIC (
    MODE : enum_plomb_pvc :=RW);
  PORT (
    -- PLOMB
    bus_w    : IN  type_plomb_w;
    bus_r    : OUT type_plomb_r;
    
    -- Mémoire
    mem_w    : OUT type_pvc_w;
    mem_r    : IN  type_pvc_r;
    
    -- Global
    clk      : IN std_logic;
    reset_na : IN std_logic
    );
END ENTITY plomb_pvc;

--##############################################################################

ARCHITECTURE rtl OF plomb_pvc IS
  
  SIGNAL retour,vv,busy : std_logic;
  SIGNAL lev : natural RANGE 0 TO 3;
  SIGNAL fifo : arr_uv32(0 TO 3);
  SIGNAL mem_w_l,mem_cop : type_pvc_w;
  
BEGIN
  
  PROCESS(clk,reset_na) IS
  BEGIN
    IF reset_na='0' THEN
      busy<='0';
    ELSIF rising_edge(clk) THEN
      IF bus_w.req='1' AND mem_r.ack='0' AND busy='0' THEN
        busy<='1';
        mem_cop.a <=bus_w.a;
        mem_cop.ah<=bus_w.ah;
        mem_cop.be<=bus_w.be;
        mem_cop.dw<=bus_w.d;
        mem_cop.wr<=bus_w.mode(0);
      ELSIF busy='1' AND mem_r.ack='1' THEN
        busy<='0';
      END IF;
      mem_cop.req<='1';
    END IF;
  END PROCESS;
  
  mem_w_l.req<=bus_w.req OR busy;
  mem_w_l.a  <=bus_w.a       WHEN busy='0' ELSE mem_cop.a;
  mem_w_l.ah <=bus_w.ah      WHEN busy='0' ELSE mem_cop.ah;
  mem_w_l.be <=bus_w.be      WHEN busy='0' ELSE mem_cop.be;
  mem_w_l.dw <=bus_w.d       WHEN busy='0' ELSE mem_cop.dw;
  mem_w_l.wr <=bus_w.mode(0) WHEN busy='0' ELSE mem_cop.wr;
  
  bus_r.ack<=NOT busy;
  bus_r.d<=mux(vv,fifo(lev),mem_r.dr);
  bus_r.code<=PB_OK;
  bus_r.dreq<=retour OR vv;
  
  SyncFIFO: PROCESS(clk, reset_na)
    VARIABLE push,pop : boolean;
  BEGIN
    IF reset_na = '0' THEN
      lev<=0;
      vv<='0';
      retour<='0';
      
    ELSIF rising_edge(clk) THEN
      push:=(retour='1');
      pop :=(bus_w.dack='1');
      IF push THEN
        fifo(0 TO 3)<=mem_r.dr & fifo(0 TO 2);
      END IF;
      IF push AND NOT pop THEN
        IF vv='1' THEN
          lev<=lev+1;
        END IF;
        vv<='1';
      ELSIF pop AND NOT push THEN
        IF lev=0 THEN
          vv<='0';
        ELSE
          lev<=lev-1;
        END IF;
      END IF;
      
      retour<=mem_w_l.req AND mem_r.ack AND NOT mem_w_l.wr;
      
    END IF;
  END PROCESS SyncFIFO;
  
  mem_w<=mem_w_l;
  
END ARCHITECTURE rtl;
