--------------------------------------------------------------------------------
-- TEM : PLOMB
-- Définitions
--------------------------------------------------------------------------------
-- DO 10/2011
--------------------------------------------------------------------------------
-- Bus PLOMB & PVC
-- ASI Sparc & exceptions bus
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;

PACKAGE plomb_pack IS
  -- PVC
  TYPE type_pvc_w IS RECORD
    req : std_logic;
    be  : uv0_3;
    wr  : std_logic;
    a   : uv32;
    ah  : unsigned(35 DOWNTO 32);
    dw  : uv32;
  END RECORD;
  TYPE arr_pvc_w IS ARRAY(natural RANGE <>) OF type_pvc_w;
  
  TYPE type_pvc_r IS RECORD
    ack : std_logic;
    dr  : uv32;
  END RECORD;
  TYPE arr_pvc_r IS ARRAY(natural RANGE <>) OF type_pvc_r;
  
  --------------------------------------
  -- PLOMB
  CONSTANT PB_MODE_NOP    : unsigned(1 DOWNTO 0) := "00";
  CONSTANT PB_MODE_RD     : unsigned(1 DOWNTO 0) := "10";
  CONSTANT PB_MODE_WR     : unsigned(1 DOWNTO 0) := "01";
  CONSTANT PB_MODE_WR_ACK : unsigned(1 DOWNTO 0) := "11";
  -- <ATTENTION> On suppose que mode(1)=Acquittement et mode(0)=Ecriture
  
  -- Toutes les écritures de l'IU sont effectuées avec acquittement, parceque
  -- il faut attendre la réponse de la MMU, s'assurer que les accès ne sont pas
  -- invalides, et, le cas échéant, déclencher un TRAP.
  
  -- Mode de fonctionnement de l'interface PLOMB -> MEM.
  TYPE enum_plomb_pvc IS (R,W,RW);
  
  TYPE enum_plomb_code IS (PB_OK,PB_ERROR,PB_FAULT,PB_SPEC);
  
  SUBTYPE type_plomb_burst IS unsigned(1 DOWNTO 0);
  CONSTANT PB_SINGLE   : type_plomb_burst := "00";
  CONSTANT PB_BURST2   : type_plomb_burst := "01";
  CONSTANT PB_BURST4   : type_plomb_burst := "10";
  CONSTANT PB_BURST8   : type_plomb_burst := "11";
  CONSTANT PB_BURSTMAX : type_plomb_burst := "11";
  CONSTANT PB_BLEN_MAX : natural := 8;
  
  -- Bus PLOMB : Flux écritures/adresses/type d'accès
  TYPE type_plomb_w IS RECORD
    a     : uv32;                           -- Adresses
    ah    : unsigned(35 DOWNTO 32);         -- Poids forts adresses
    asi   : uv8;                            -- Address Space Identifier
    d     : uv32;                           -- Données à écrire
    be    : uv0_3;                          -- Byte Enables, Big Endian
    mode  : uv2;                            -- Type d'accès
    burst : type_plomb_burst;               -- Accès burst
    cont  : std_logic;                      -- Accès contigüs
    cache : std_logic;                      -- Cacheable
    lock  : std_logic;                      -- Lock
    req   : std_logic;                      -- Requète accès
    dack  : std_logic;                      -- Acquittement données
  END RECORD;
  TYPE arr_plomb_w IS ARRAY(natural RANGE <>) OF type_plomb_w;
  
  -- Bus PLOMB : Flux lectures
  TYPE type_plomb_r IS RECORD
    d     : uv32;                           -- Données lues
    code  : enum_plomb_code;                -- Code d'erreur
    ack   : std_logic;                      -- Acquittement accès
    dreq  : std_logic;     -- Requète données lues ou acquittement écriture.
  END RECORD;
  TYPE arr_plomb_r IS ARRAY(natural RANGE <>) OF type_plomb_r;
  
  --------------------------------------
  FUNCTION is_read (w : type_plomb_w) RETURN boolean;
  FUNCTION is_write(w : type_plomb_w) RETURN boolean;
  FUNCTION is_burst(w : type_plomb_w) RETURN boolean;
  FUNCTION pb_blen (b : type_plomb_burst) RETURN natural;
  FUNCTION pb_blen (w : type_plomb_w) RETURN natural;
  FUNCTION pb_blen (a :natural)       RETURN unsigned;
  --pragma synthesis_off
  FUNCTION pb_btxt (w : type_plomb_w) RETURN string;
  --pragma synthesis_on

  TYPE enum_plomb_fifo IS (SYNC,COMB,DIRECT);

  CONSTANT PLOMB_W_LEN : natural := 32+4+8+32+4+2+
                                    type_plomb_burst'length+1+1+1;
  CONSTANT PLOMB_R_LEN : natural := 32+2;
  
  SUBTYPE type_plomb_w_flat IS unsigned(0 TO PLOMB_W_LEN-1);
  TYPE arr_plomb_w_flat IS ARRAY(natural RANGE <>) OF type_plomb_w_flat;  
  SUBTYPE type_plomb_r_flat IS unsigned(0 TO PLOMB_R_LEN-1);
  TYPE arr_plomb_r_flat IS ARRAY(natural RANGE <>) OF type_plomb_r_flat;
  
    
  FUNCTION pb_code_conv(c : enum_plomb_code) RETURN unsigned;
  FUNCTION pb_code_conv(c : unsigned(1 DOWNTO 0)) RETURN enum_plomb_code;
  
  FUNCTION pb_flat(w : type_plomb_w) RETURN type_plomb_w_flat;
  FUNCTION pb_flat(r : type_plomb_r) RETURN type_plomb_r_flat;
  FUNCTION pb_flat(w : type_plomb_w_flat) RETURN type_plomb_w;
  FUNCTION pb_flat(r : type_plomb_r_flat) RETURN type_plomb_r;

  --------------------------------------
  -- DEBUG LINK
  TYPE type_dl_w IS RECORD
    a  : uv4;       -- Address
    op : uv4;       -- Operation
    d  : uv32;      -- Data Write
    wr : std_logic; -- Write data/op
  END RECORD;
  TYPE arr_dl_w IS ARRAY(natural RANGE <>) OF type_dl_w;
  
  TYPE type_dl_r IS RECORD
    d  : uv32;      -- Data read
    rd : std_logic; -- Read data
  END RECORD;
  TYPE arr_dl_r IS ARRAY(natural RANGE <>) OF type_dl_r;

  FUNCTION "OR"(a,b : type_dl_r) RETURN type_dl_r;
  
END PACKAGE plomb_pack;

--------------------------------------------------------------------------------

PACKAGE BODY plomb_pack IS

  --------------------------------------
  FUNCTION pb_code_conv(c : enum_plomb_code) RETURN unsigned IS
  BEGIN
    CASE c IS
      WHEN PB_OK    => RETURN "00";
      WHEN PB_ERROR => RETURN "01";
      WHEN PB_FAULT => RETURN "10";
      WHEN PB_SPEC  => RETURN "11";
    END CASE;
  END;
  
  FUNCTION pb_code_conv(c : unsigned(1 DOWNTO 0)) RETURN enum_plomb_code IS
  BEGIN
    CASE c IS
      WHEN "01"   => RETURN PB_ERROR;
      WHEN "10"   => RETURN PB_FAULT;
      WHEN "11"   => RETURN PB_SPEC;
      WHEN OTHERS => RETURN PB_OK;
    END CASE;
  END;
  
  FUNCTION pb_flat(w : type_plomb_w) RETURN type_plomb_w_flat IS
  BEGIN
    RETURN w.d & w.be & w.mode & w.burst & w.a & w.ah & w.asi &  
      w.cont & w.cache & w.lock;
    --RETURN w.a & w.ah & w.asi & w.d & w.be & w.mode & w.burst &
    --  w.cont & w.cache & w.lock;
  END;
  
  FUNCTION pb_flat(r : type_plomb_r) RETURN type_plomb_r_flat IS
  BEGIN
    RETURN r.d & pb_code_conv(r.code);
  END;
  
  FUNCTION pb_flat(w : type_plomb_w_flat) RETURN type_plomb_w IS
  BEGIN
    RETURN type_plomb_w'(d  =>w(0 TO 31),
                         be =>w(32 TO 35),
                         mode=>w(36 TO 37),
                         burst=>w(38 TO 39),
                         a  =>w(40 TO 71),
                         ah =>w(72 TO 75),
                         asi=>w(76 TO 83),
                         cont=>w(84),cache=>w(85),lock=>w(86),
                         req=>'X',dack=>'X');
    --RETURN type_plomb_w'(a  =>w(0 TO 31),
    --                     ah =>w(32 TO 35),
    --                     asi=>w(36 TO 43),
    --                     d  =>w(44 TO 75),
    --                     be =>w(76 TO 79),
    --                     mode=>w(80 TO 81),
    --                     burst=>w(82 TO 83),
    --                     cont=>w(84),cache=>w(85),lock=>w(86),
    --                     req=>'X',dack=>'X');
  END;

  FUNCTION pb_flat(r : type_plomb_r_flat) RETURN type_plomb_r IS
  BEGIN
    RETURN type_plomb_r'(d=>r(0 TO 31),code=>pb_code_conv(r(32 TO 33)),
                         ack=>'X',dreq=>'X');
  END;

  --------------------------------------
  FUNCTION is_read(w : type_plomb_w) RETURN boolean IS
  BEGIN
    RETURN w.mode="10";
  END FUNCTION is_read;
  
  FUNCTION is_write(w : type_plomb_w) RETURN boolean IS
  BEGIN
    RETURN w.mode(0)='1';
  END FUNCTION is_write;
  
  FUNCTION is_burst(w : type_plomb_w) RETURN boolean IS
  BEGIN
    RETURN w.burst/="00";
  END FUNCTION is_burst;
  
  FUNCTION pb_blen(b : type_plomb_burst) RETURN natural IS
  BEGIN
    CASE b IS
      WHEN PB_BURST2  => RETURN 2;
      WHEN PB_BURST4  => RETURN 4;
      WHEN PB_BURST8  => RETURN 8;
      WHEN OTHERS     => RETURN 1;
    END CASE;
  END FUNCTION pb_blen;

  FUNCTION pb_blen(w : type_plomb_w) RETURN natural IS
  BEGIN
    RETURN pb_blen(w.burst);
  END FUNCTION pb_blen;

  FUNCTION pb_blen(a :natural) RETURN unsigned IS
  BEGIN
    CASE a IS
      WHEN 1  => RETURN PB_SINGLE;
      WHEN 2  => RETURN PB_BURST2;
      WHEN 4  => RETURN PB_BURST4;
      WHEN 8  => RETURN PB_BURST8;
      WHEN OTHERS =>
        REPORT "Longueur BURST invalide" SEVERITY failure;
        RETURN "00";
    END CASE;
  END FUNCTION pb_blen;
  
  --pragma synthesis_off
  FUNCTION pb_btxt(w : type_plomb_w) RETURN string IS
  BEGIN
    CASE w.burst IS
      WHEN PB_BURST2  => RETURN "B2 ";
      WHEN PB_BURST4  => RETURN "B4 ";
      WHEN PB_BURST8  => RETURN "B8 ";
      WHEN OTHERS     => RETURN "   ";
    END CASE;
  END FUNCTION pb_btxt;
  --pragma synthesis_on
  
  FUNCTION "OR"(a,b : type_dl_r) RETURN type_dl_r IS
    VARIABLE v : type_dl_r;
  BEGIN
    v.d :=a.d  OR b.d;
    v.rd:=a.rd OR b.rd;
    RETURN v;
  END FUNCTION;
  
END PACKAGE BODY plomb_pack;
