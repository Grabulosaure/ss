--------------------------------------------------------------------------------
-- TEM : PLOMB
-- Multiplexeur : Plusieurs bus amont -> Un bus aval
--------------------------------------------------------------------------------
-- DO 3/2008
--------------------------------------------------------------------------------
-- Le premier port vi(0) est le plus prioritaire

-- Il y a une FIFO qui mémorise dans quel ordre les process sont servis pour
-- savoir a qui renvoyer les données lues.

-- Le même port est conservé tant qu'un burst est en cours.
--------------------------------------------------------------------------------
-- <AVOIR> Activation DACK avant REQ (bursts...)

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.plomb_pack.ALL;

ENTITY plomb_mux IS
  GENERIC (
    NB        : uint8 := 2;
    PROF      : uint8 := 4);
  PORT (
    -- Amont
    vi_w     : IN  arr_plomb_w(0 TO NB-1);
    vi_r     : OUT arr_plomb_r(0 TO NB-1);

    -- Aval
    o_w      : OUT type_plomb_w;
    o_r      : IN  type_plomb_r;
    
    -- Global
    clk      : IN std_logic;
    reset_n : IN std_logic
    );
END ENTITY plomb_mux;

--##############################################################################

ARCHITECTURE rtl OF plomb_mux IS

  SUBTYPE type_no IS natural RANGE 0 TO NB-1;
  SIGNAL no_c,noa_c,no_mem : type_no;
  SIGNAL aec,bec,loc : std_logic; -- Accès en cours, Burst en cours, Lock actif
  SIGNAL req_c : std_logic;
  SIGNAL cpt,blen : natural RANGE 0 TO PB_BLEN_MAX-1;
  TYPE arr_fifo IS ARRAY(0 TO PROF-1) OF type_no;
  SIGNAL level : natural RANGE 0 TO PROF;
  SIGNAL fifo : arr_fifo;
  
BEGIN
  
  -------------------------------------------------------------
  -- Identification de la source par priorité
  GenNo: PROCESS (vi_w) IS
    VARIABLE req_v : std_logic;
  BEGIN
    no_c<=0;
    req_v:='0';
    FOR I IN 0 TO NB-1 LOOP
      IF vi_w(I).req='1' AND req_v='0' THEN
        no_c<=I;
      END IF;
      req_v:=req_v OR vi_w(I).req;
    END LOOP;
    req_c<=req_v;
  END PROCESS GenNo;
  
  -------------------------------------------------------------
  -- Mémorise l'accès en cours, empile
  Sync: PROCESS (clk) IS
    VARIABLE push_v,pop_v : std_logic;
  BEGIN
    IF rising_edge(clk) THEN
      -- Accès en cours
      aec<=req_c AND NOT o_r.ack;
      
      -- Bursts
      IF vi_w(noa_c).req='1' AND o_r.ack='1' THEN
        IF bec='0' THEN
          blen<=pb_blen(vi_w(noa_c))-1;
          bec<=to_std_logic(is_burst(vi_w(noa_c)));
          cpt<=0;
        ELSE
          cpt<=cpt+1;
          IF cpt=blen-1 THEN
            bec<='0';
          END IF;
        END IF;
        
        IF vi_w(noa_c).lock='1' THEN
          loc<='1';
        END IF;
      END IF;
      
      IF vi_w(noa_c).lock='0' THEN
        loc<='0';
      END IF;
      
      -- Numéro de port
      IF aec='0' AND bec='0' AND loc='0' THEN
        no_mem<=noa_c;
      END IF;
      
      -- La FIFO stocke les numéros de port des accès avec retour
      push_v:=vi_w(noa_c).mode(1) AND vi_w(noa_c).req AND o_r.ack;
      pop_v:=o_r.dreq AND vi_w(fifo(0)).dack; -- AND to_std_logic(level/=0);
      
      -- FIFO
      IF pop_v='1' THEN
        fifo(0 TO PROF-2)<=fifo(1 TO PROF-1);
      END IF;
      IF push_v='1' AND pop_v='0' THEN
        -- Si empile
        fifo(level)<=noa_c;
        level<=level+1;
      ELSIF push_v='1' AND pop_v='1' AND level/=0 THEN
        -- Si empile et dépile
        fifo(level-1)<=noa_c;
      ELSIF push_v='0' AND pop_v='1' AND level/=0 THEN
        -- Si dépile
        level<=level-1;
      END IF;

      IF reset_n='0' THEN
        aec<='0';
        bec<='0';
        loc<='0';
        fifo<=(OTHERS => 0);
        level<=0;
        cpt<=0;
      END IF;
    END IF;
  END PROCESS Sync;
  
  -------------------------------------------------------------
  -- Numéro du port en cours
  noa_c<=no_mem WHEN aec='1' OR bec='1' OR loc='1' ELSE no_c;
  
  -------------------------------------------------------------
  GenOW: PROCESS (vi_w,noa_c,fifo,level) IS
  BEGIN
    o_w<=vi_w(noa_c);
    o_w.dack<=vi_w(fifo(0)).dack AND to_std_logic(level/=0);
  END PROCESS GenOW;
  
  GenVIR: PROCESS (o_r,noa_c,fifo,level) IS
  BEGIN
    FOR I IN 0 TO NB-1 LOOP
      vi_r(I)<=o_r;
      vi_r(I).dreq<='0';
      vi_r(I).ack<='0';
    END LOOP;
    vi_r(fifo(0)).dreq<=o_r.dreq AND to_std_logic(level/=0);
    vi_r(noa_c).ack<=o_r.ack;
  END PROCESS GenVIR;

  
END ARCHITECTURE rtl;
