--------------------------------------------------------------------------------
-- TEM : PLOMB
-- Sélecteur : Un Process -> Plusieurs bancs mémoire
--------------------------------------------------------------------------------
-- DO 3/2008
--------------------------------------------------------------------------------
-- Le numéro de port "NO" détermine le port à servir. C'est typiquement un
-- décodage d'adresses...

-- Il y a une FIFO qui mémorise l'ordre dans lequel les demandes de lectures
-- sont envoyées, pour savoir dans quel ordres les données doivent être reçues.
--------------------------------------------------------------------------------
-- <AFAIRE> Voir pour les burst

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

ENTITY plomb_sel IS
  GENERIC (
    NB   : uint8 := 2;
    PROF : uint8 := 4);
  PORT (
    -- Entrées
    i_w      : IN  type_plomb_w;
    i_r      : OUT type_plomb_r;
    no       : IN  natural RANGE 0 TO NB-1;
    
    -- Mémoire
    vo_w     : OUT arr_plomb_w(0 TO NB-1);
    vo_r     : IN  arr_plomb_r(0 TO NB-1);
        
    -- Global
    clk      : IN  std_logic;
    reset_n  : IN  std_logic
    );
END ENTITY plomb_sel;

--##############################################################################

ARCHITECTURE rtl OF plomb_sel IS
  SUBTYPE type_no IS natural RANGE 0 TO NB-1;
  TYPE arr_fifo IS ARRAY(0 TO PROF-1) OF type_no;
  SIGNAL level : natural RANGE 0 TO PROF;
  SIGNAL fifo : arr_fifo;
BEGIN
  
  -------------------------------------------------------------
  -- Mémorise l'accès en cours, empile
  Sync: PROCESS (clk) IS
    VARIABLE reqret_v : std_logic;
    VARIABLE dreq_v : std_logic;
  BEGIN
    IF rising_edge(clk) THEN
      reqret_v:=i_w.mode(1) AND i_w.req;  -- Accès avec retour
      dreq_v:=vo_r(fifo(0)).dreq;
      
      -- FIFO
      IF dreq_v='1' AND i_w.dack='1' THEN
        fifo(0 TO PROF-2)<=fifo(1 TO PROF-1);
      END IF;
      IF reqret_v='1' AND vo_r(no).ack='1' AND
        NOT (dreq_v='1' AND i_w.dack='1') THEN
        -- Si empile
        fifo(level)<=no;
        level<=level+1;
      ELSIF reqret_v='1' AND vo_r(no).ack='1' AND
        dreq_v='1' AND i_w.dack='1' AND level/=0 THEN
        -- Si empile et dépile
        fifo(level-1)<=no;
      ELSIF NOT (reqret_v='1' AND vo_r(no).ack='1') AND
        dreq_v='1' AND i_w.dack='1' AND level/=0 THEN
        -- Si dépile
        level<=level-1;
      END IF;

      IF reset_n='0' THEN
        fifo<=(OTHERS => 0);
        level<=0;
      END IF;
    END IF;
  END PROCESS Sync;

  -------------------------------------------------------------
  GenVOW:PROCESS (i_w,no,fifo) IS
  BEGIN
    FOR I IN 0 TO NB-1 LOOP
      vo_w(I)<=i_w;
      vo_w(I).req<='0';
      vo_w(I).dack<='0';
    END LOOP;
    vo_w(no).req<=i_w.req;
    vo_w(fifo(0)).dack<=i_w.dack;
  END PROCESS GenVOW;
  
  GenIR:PROCESS (vo_r,no,fifo) IS
  BEGIN
    i_r<=vo_r(fifo(0));
    i_r.ack<=vo_r(no).ack;
  END PROCESS GenIR;
  
END ARCHITECTURE rtl;
