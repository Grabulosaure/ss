--------------------------------------------------------------------------------
-- TEM : TACUS
-- Packet MMU / Cache
--------------------------------------------------------------------------------
-- DO 2/2010
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

USE work.base_pack.ALL;
USE work.plomb_pack.ALL;

PACKAGE mcu_pack IS
  
  --############################################################################
  TYPE type_tlb_mode IS (LRU,CPT);
  CONSTANT N_DTLB : natural := 4;      -- Nombre de TLB données:      1,2,3,4
  CONSTANT N_ITLB : natural := 4;      -- Nombre de TLB instructions: 1,2,3,4
  
  CONSTANT DTLB_MODE : type_tlb_mode := LRU;
  CONSTANT ITLB_MODE : type_tlb_mode := LRU;
  
  -- Comportement du cache multivoie LRU après une lecture
  --   A  : On met à jour l'historique si la voie sélectionnée
  --      n'est pas la plus récente.
  --   B  : On met à jour l'historique si la voie sélectionnée
  --      est la plus ancienne
  --   N  : On ne met pas à jour l'historique après une lecture
  
  TYPE type_rcache_mode IS (A,B,N);
  
  CONSTANT LF_ICACHE : type_rcache_mode :=A;
  CONSTANT LF_DCACHE : type_rcache_mode :=A;
  
  -- CACHE
  -- Cache de 4ko, lignes de 4 * 32bits : DCACHE = 12, CLINE = 2 --> 256 lignes
  -- va[1:0]   : Sélection octet
  -- va[3:2]   : Mot dans la ligne
  -- va[11:4]  : Sélection de la ligne
  -- va[31:12] : Comparaison du tag
  
  --############################################################################
  
  -- MMU
  CONSTANT FT_NONE        : unsigned(2 DOWNTO 0) :="000"; -- No error
  CONSTANT FT_INVALID     : unsigned(2 DOWNTO 0) :="001"; -- Invalid address
  CONSTANT FT_PROTECTION  : unsigned(2 DOWNTO 0) :="010"; -- Protection error
  CONSTANT FT_PRIVILEGE   : unsigned(2 DOWNTO 0) :="011"; -- Privilege violation
  CONSTANT FT_TRANSLATION : unsigned(2 DOWNTO 0) :="100"; -- Translation error
  CONSTANT FT_ACCESS      : unsigned(2 DOWNTO 0) :="101"; -- Access bus error
  CONSTANT FT_INTERNAL    : unsigned(2 DOWNTO 0) :="110"; -- Internal error
  CONSTANT FT_RESERVED    : unsigned(2 DOWNTO 0) :="111"; -- Reserved

  CONSTANT ET_INVALID : unsigned(1 DOWNTO 0) := "00";  -- Invalide, non mappé
  CONSTANT ET_PTD     : unsigned(1 DOWNTO 0) := "01";  -- PTD
  CONSTANT ET_PTE     : unsigned(1 DOWNTO 0) := "10";  -- PTE
  CONSTANT ET_RESERVED: unsigned(1 DOWNTO 0) := "11";  -- Réservé (litte endian)

  CONSTANT PT_PAGE    : unsigned(2 DOWNTO 0) := "000";  -- MMU Probe Page
  CONSTANT PT_SEGMENT : unsigned(2 DOWNTO 0) := "001";  -- MMU Probe Segment
  CONSTANT PT_REGION  : unsigned(2 DOWNTO 0) := "010";  -- MMU Probe Region
  CONSTANT PT_CONTEXT : unsigned(2 DOWNTO 0) := "011";  -- MMU Probe Context
  CONSTANT PT_ENTIRE  : unsigned(2 DOWNTO 0) := "100";  -- MMU Probe Entire
  
  -- Translation Lookaside Buffer Entry
  TYPE type_tlb IS RECORD
    v    : std_logic;                   -- Valid
    va   : unsigned(31 DOWNTO 12);      -- Virtual Address
    st   : unsigned(1 DOWNTO 0);        -- Short Translation
    ctx  : uv16;                        -- Numéro de contexte
    acc  : unsigned(2 DOWNTO 0);        -- Access Protection bits
    --------------------------------------------------------------
    ppn  : unsigned(35 DOWNTO 12);      -- Physical Page Number
    c    : std_logic;                   -- Cacheable
    m    : std_logic;                   -- Modified
    wb   : std_logic;                   -- Write Back = 1, Through=0
    al   : std_logic;                   -- Write With Allocate=1, Without=0
  END RECORD;
  TYPE arr_tlb IS ARRAY(natural RANGE <>) OF type_tlb;
  
  CONSTANT TLB_ZERO : type_tlb := ('0',"00000000000000000000","00",x"0000",
                             "000","000000000000000000000000",'0','0','0','0');

  PROCEDURE tlb_test (
    VARIABLE hit   : OUT std_logic;             -- Correspondance trouvée
    VARIABLE flush : OUT std_logic;             -- 0=Accès normal 1=Flush
    CONSTANT tlb   : IN  type_tlb;              -- TLB à comparer
    CONSTANT va    : IN  uv32;                  -- Adresse virtuelle
    CONSTANT us    : IN  std_logic;             -- 0=User 1=Super
    CONSTANT ctx   : IN  unsigned;              -- Contexte
    CONSTANT aflush : IN std_logic);            -- Force flush
    
  PROCEDURE tlb_trans (
    VARIABLE ft   : OUT unsigned(2 DOWNTO 0);   -- Fault type
    VARIABLE pa   : OUT unsigned(35 DOWNTO 0);  -- Adresse physique
    VARIABLE c    : OUT std_logic;              -- Cacheable
    VARIABLE m    : OUT std_logic;              -- Modified
    VARIABLE s    : OUT std_logic;              -- Superviseur
    VARIABLE wb   : OUT std_logic;              -- Write Back=1 Thru=0
    VARIABLE al   : OUT std_logic;              -- Write WoAlloc=0 / WithAlloc=1
    CONSTANT tlb  : IN  type_tlb;               -- TLB à comparer
    CONSTANT va   : IN  uv32;                   -- Adresse virtuelle
    CONSTANT ls   : IN  std_logic;              -- 0=Load 1=Store
    CONSTANT us   : IN  std_logic;              -- 0=User 1=Super
    CONSTANT di   : IN  std_logic);             -- 0=Data 1=Instruction
  
  -- Translation d'adresses lorsque la MMU est totalement absente
  PROCEDURE cache_trans (
    VARIABLE ft   : OUT unsigned(2 DOWNTO 0);   -- Fault type
    VARIABLE pa   : OUT unsigned(35 DOWNTO 0);  -- Adresse physique
    VARIABLE c    : OUT std_logic;              -- Cacheable
    VARIABLE m    : OUT std_logic;              -- Modified
    VARIABLE wb   : OUT std_logic;              -- Write Thru=0 / Back=1
    VARIABLE al   : OUT std_logic;              -- Write WoAlloc=0 /WithAlloc=1
    CONSTANT va   : IN  uv32;                   -- Adresse virtuelle
    CONSTANT ls   : IN  std_logic;              -- 0=Load 1=Store
    CONSTANT us   : IN  std_logic;              -- 0=User 1=Super
    CONSTANT di   : IN  std_logic);             -- 0=Data 1=Instruction
  
  FUNCTION tlb_encode (
    CONSTANT pte : IN  uv32;             -- PTE en mémoire
    CONSTANT va  : IN  uv32;             -- Adresse virtuelle
    CONSTANT st  : IN  unsigned(1 DOWNTO 0);  -- Niveau de translation
    CONSTANT ctx : IN  unsigned;         -- Numéro de contexte
    CONSTANT m   : IN  std_logic;        -- 'Modified'
    CONSTANT wb  : IN  std_logic;        -- Write back
    CONSTANT al  : IN  std_logic)        -- Allocate on write
    RETURN type_tlb;
  
  PROCEDURE tablewalk_test (
    VARIABLE cont  : OUT std_logic;     -- 1=Continue TW, 0=Arrêt
    VARIABLE err   : OUT std_logic;     -- 1=Erreur, 0=Normal
    CONSTANT d     : IN  uv32;          -- Données lues : PTE ou PTD
    CONSTANT st    : IN  unsigned(1 DOWNTO 0);     -- Niveau du TW 0 -> 3
    CONSTANT probe : IN  std_logic;     -- 1=Probe, 0=Lecture/Ecriture
    CONSTANT pt    : IN  unsigned(2 DOWNTO 0));  -- Probe TYPE
  
  FUNCTION tlb_or (
    CONSTANT a : type_tlb;
    CONSTANT b : type_tlb) RETURN type_tlb;
  
  ------------------------------------------------------------------------------
  -- CACHE

  ---------------------------------------------------------------------
  -- VT : Tags Virtuels  ( >=4k/voie, 256 contextes)
  
  -- 31          12 11         4 3 2 1 0
  -- [ VA(31:12)  ] [ Contexte ] [H] S V
  --                                   V : Valide
  --                                 S   : Page Superviseur
  --                              H[1:0] : Historique pour multi-voies
  ---------------------------------------------------------------------
  -- PT : Tags Physiques ( >=4k/voie )
  
  -- 31                8 7     4 3 2 1 0
  -- [     VA(35:12)   ] [ ??? ] [H] M V
  --                                   V : Valide
  --                                 M   : Modifié (pour W-Back)
  --                              H[1:0] : Historique pour multi-voies
  --                           P         : Shared  (pour MESI)  
  ---------------------------------------------------------------------
  
  PROCEDURE vtag_test(
    VARIABLE hit        : OUT std_logic;            -- Cache hit
    VARIABLE inval      : OUT std_logic;            -- Hit, si inval
    CONSTANT tag        : IN  uv32;                 -- Entrée du cache à tester
    CONSTANT va         : IN  uv32;                 -- Adresse Virtuelle (VT)
    CONSTANT ctx        : IN  unsigned;             -- Contexte (VT)
    CONSTANT asi        : IN  uv8;                  -- ASI (pour codes flush)
    CONSTANT NB_CACHE   : IN  natural RANGE 0 TO 31; -- Taille cache (constante)
    CONSTANT NB_CONTEXT : IN natural;               -- Nombre de contextes
    CONSTANT MMU_DIS    : IN  boolean);             -- MMU=false, Cache seul=true
  
  PROCEDURE ptag_test(
    VARIABLE hit      : OUT std_logic;             -- Cache hit
    VARIABLE inval    : OUT std_logic;             -- Hit, si inval
    VARIABLE flush    : OUT std_logic;             -- Hit, si invalidation
    CONSTANT tag      : IN  uv32;                  -- Entrée du cache à tester
    CONSTANT pa       : IN  unsigned(35 DOWNTO 0); -- Adresse Physique (PT)
    CONSTANT asi      : IN  uv8;                   -- ASI (pour codes flush)
    CONSTANT NB_CACHE : IN  natural RANGE 0 TO 31); -- Taille cache (const)

  FUNCTION vtag_encode (
    CONSTANT va         : IN  uv32;                  -- Adresse Virtuelle (VT)
    CONSTANT ctx        : IN  unsigned;              -- Contexte          (VT)
    CONSTANT v          : IN  std_logic;             -- Valid
    CONSTANT s          : IN  std_logic;             -- Super             (VT)
    CONSTANT h          : IN  unsigned(1 DOWNTO 0);  -- Historique
    CONSTANT NB_CACHE   : IN natural;                -- Taille voie cache
    CONSTANT NB_CONTEXT : IN natural) RETURN unsigned; -- Nombre de contextes
  
  FUNCTION ptag_encode (
    CONSTANT pa        : IN  unsigned(35 DOWNTO 0); -- Adresse Physique  (PT)
    CONSTANT v         : IN  std_logic;             -- Valid
    CONSTANT m         : IN  std_logic;             -- Modif (pour WB)
    CONSTANT s         : IN  std_logic;             -- Shared
    CONSTANT h         : IN  unsigned(1 DOWNTO 0);  -- Historique
    CONSTANT NB_CACHE  : IN  natural) RETURN unsigned; -- Taille voie cache
  
  TYPE enum_mesi IS (M,E,S,I);
  
  PROCEDURE ptag_decode (
    VARIABLE v    : OUT std_logic;
    VARIABLE m    : OUT std_logic;
    VARIABLE s    : OUT std_logic;
    CONSTANT tag  : IN  uv32);

  FUNCTION ptag_mod (
    CONSTANT tag  : IN  uv32;
    CONSTANT v    : IN  std_logic;
    CONSTANT m    : IN  std_logic;
    CONSTANT s    : IN  std_logic) RETURN unsigned;

  FUNCTION ptag_decode (
    CONSTANT tag  : IN  uv32) RETURN enum_mesi;
  
  FUNCTION ptag_pa (
    CONSTANT tag      : IN uv32;
    CONSTANT pi       : IN uv32;
    CONSTANT NB_CACHE : IN natural) RETURN unsigned;

  FUNCTION tag_selfill (CONSTANT tag  : IN arr_uv32;
                        CONSTANT hist : IN uv8) RETURN natural;
  
  PROCEDURE tag_maj(
    VARIABLE tag_o   : OUT arr_uv32;        -- Tags mis à jour
    CONSTANT tagr    : IN  uv32;            -- Nouvelle valeur tag
    CONSTANT tag     : IN  arr_uv32;        -- Tags précédents
    CONSTANT hist    : IN  uv8;             -- Historique
    CONSTANT rd      : IN  std_logic;       -- 1=Lecture
    CONSTANT wthru   : IN  std_logic;       -- 1=Ecriture Write Thru
    CONSTANT wback   : IN  std_logic;       -- 1=Ecriture Write Back
    CONSTANT flush   : IN  std_logic;       -- 1=Flush
    CONSTANT fill    : IN  std_logic;       -- 1=FILL / DEFAULT
    CONSTANT inval   : IN  std_logic;       -- 1=Invalidation
    CONSTANT nohit   : IN  natural;         -- Numéro voie changée Write
    CONSTANT nofill  : IN  natural;         -- Numéro voie à remplir
    CONSTANT noflush : IN  natural);        -- Numéro voie à purger

  FUNCTION tag_mod(
    CONSTANT tag    : IN  arr_uv32;   -- Tags précédents
    CONSTANT nohit  : IN  natural) RETURN std_logic; -- Numéro voie
  
  FUNCTION ff1(CONSTANT hit : IN  unsigned) RETURN natural;
  
  ------------------------------------------------------------------------------
  -- LRU : Mise à jour historique
  FUNCTION lru_maj(
    CONSTANT i  : IN unsigned(7 DOWNTO 0);  -- Séquence précédente
    CONSTANT no : IN natural RANGE 0 TO 7; -- Nouveau plus récent
    CONSTANT nb : IN natural RANGE 1 TO 8) -- Nombre d'entrées
    RETURN unsigned;
  
  -- LRU: Recherche du plus ancien
  FUNCTION lru_old(
    CONSTANT i  : IN unsigned(7 DOWNTO 0);
    CONSTANT nb : IN natural RANGE 1 TO 8)  -- Nombre d'entrées
    RETURN natural;

  -- LRU: Recherche du plus récent
  FUNCTION lru_new(
    CONSTANT i  : IN uv8;
    CONSTANT nb : IN natural RANGE 1 TO 8)  -- Nombre d'entrées
    RETURN natural;

  -- LRU : Décision mise à jour après une lecture
  FUNCTION lru_rmaj (
    CONSTANT hist : uv8;
    CONSTANT no   : natural RANGE 0 TO 3;
    CONSTANT lf   : type_rcache_mode;
    CONSTANT nb   : natural RANGE 1 TO 8)
    RETURN boolean;

  ------------------------------------------------------------------------------
  -- Opération requise vers le contrôleur de bus externe :
  -- SINGLE   : Accès simple
  -- FILL     : Cache fill avant read
  -- FILLMOD  : Cache fill avant write, RWITM <MULTI>
  -- FLUSH    : Write Back / Flush <MULTI>
  -- EXCLUSIVE: Demande transition S->E en interne et S->I externe <MULTI>
  TYPE enum_ext_op IS (SINGLE,FILL,FILLMOD,FLUSH,EXCLUSIVE);
  
  -- LS       : Tablewalk, pour une lecture ou une écriture
  -- PROBE    : Tablewalk, pour un ASI_MMU_PROBE
  TYPE enum_tw_op IS (LS,PROBE);
  
  TYPE type_ext IS RECORD
    pw   : type_plomb_w; -- Accès externe
    op   : enum_ext_op;  -- Type d'opération accès externe
    twop : enum_tw_op;   -- Type d'opération Tablewalk
    twls : std_logic;    -- Load/Store pour Tablewalk (write pour atomiques...)
    ts   : std_logic;    -- Mode User/Super du TLB <SIMPLE> (pour cache VT)
    va   : uv32;         -- Adresse virtuelle pour tablewalk
  END RECORD;
  
  ------------------------------------------------------------------------------
  TYPE enum_dit IS (DI_DATA,DI_INST,DI_TW);
  
  -- Empilage des données à renvoyer.
  TYPE type_push IS RECORD
    code : enum_plomb_code;
    d    : uv32;
    cx   : std_logic;
  END RECORD;
  
  --TYPE type_mp_dop IS (NOP,TMOD,WBACK); A supprimer
  --TYPE type_mp_iop IS (NOP,TMOD); A supprimer
  
  TYPE type_smp IS RECORD
    req  : std_logic;   -- =1 : Premier cycle
    busy : std_logic;   -- =1 : Actif
    a    : uv32;        -- Adresse
    ah   : uv4;         -- Addresse
    op   : enum_ext_op; -- SINGLE / FILL / FILLMOD / FLUSH / EXCLSUIVE
    rw   : std_logic;   -- 0=Read 1=Write
    gbl  : std_logic;   -- Global (=Cacheable)
    dit  : enum_dit;
    lock : std_logic;
  END RECORD;

  CONSTANT SMP_ZERO : type_smp :=('0','0',x"00000000",x"0",
                                  SINGLE,'0','0',DI_DATA,'0');
  
  CONSTANT PLOMB_W_ZERO : type_plomb_w :=(
    x"00000000",x"0",x"00",x"00000000",x"0","00",PB_SINGLE,
    '0','0','0','0','0');
  
END PACKAGE mcu_pack;

--------------------------------------------------------------------------------

PACKAGE BODY mcu_pack IS
  
  --############################################################################

  CONSTANT LRU2_01 : std_logic := '0';
  CONSTANT LRU2_10 : std_logic := '1';
  
  -- LRU2: Mise à jour de la séquence LRU
  PROCEDURE lru2_maj(
    VARIABLE seq_o : OUT std_logic;
    CONSTANT acc   : IN  std_logic;
    CONSTANT seq   : IN  std_logic) IS
  BEGIN
    IF acc='1' THEN
      seq_o:=LRU2_01;
    ELSE
      seq_o:=LRU2_10;
    END IF;
  END lru2_maj;

  -- LRU2: Recherche du plus ancien
  FUNCTION lru2_old(
    CONSTANT seq   : IN  std_logic) RETURN std_logic IS
  BEGIN
    RETURN seq;
  END lru2_old;

  -- LRU2: Recherche du plus récent
  FUNCTION lru2_new(
    CONSTANT seq   : IN  std_logic) RETURN std_logic IS
  BEGIN
    RETURN NOT seq;
  END lru2_new;
  
  --------------------------------------
  CONSTANT LRU3_012 : unsigned(2 DOWNTO 0):="000";  -- 0
  CONSTANT LRU3_021 : unsigned(2 DOWNTO 0):="001";  -- 1
  CONSTANT LRU3_102 : unsigned(2 DOWNTO 0):="010";  -- 2
  CONSTANT LRU3_120 : unsigned(2 DOWNTO 0):="011";  -- 3
  CONSTANT LRU3_201 : unsigned(2 DOWNTO 0):="100";  -- 4
  CONSTANT LRU3_210 : unsigned(2 DOWNTO 0):="101";  -- 5

  TYPE arr_lru3 IS ARRAY(natural RANGE <>) OF unsigned(2 DOWNTO 0);
  CONSTANT LRU3S : arr_lru3(0 TO 31) := (
    -- 0:00     1:01     2:10     XXX
    LRU3_120,LRU3_021,LRU3_012,LRU3_012,   -- LRU3_012
    LRU3_210,LRU3_021,LRU3_012,LRU3_012,   -- LRU3_021
    LRU3_120,LRU3_021,LRU3_102,LRU3_102,   -- LRU3_102
    LRU3_120,LRU3_201,LRU3_102,LRU3_102,   -- LRU3_120
    LRU3_210,LRU3_201,LRU3_012,LRU3_012,   -- LRU3_201
    LRU3_210,LRU3_201,LRU3_102,LRU3_102,   -- LRU3_210
    LRU3_210,LRU3_201,LRU3_012,LRU3_012,   -- XXX
    LRU3_210,LRU3_201,LRU3_102,LRU3_102);  -- XXX

  TYPE arr_lru3m IS ARRAY(natural RANGE <>) OF unsigned(1 DOWNTO 0);
  CONSTANT MRU3S : arr_lru3m(0 TO 7) := (
    "10","01",                             -- LRU3_012, LRU3_021
    "10","00",                             -- LRU3_102, LRU3_120
    "01","00",                             -- LRU3_201, LRU3_210
    "01","00");                            -- XXX     , XXX
  
  -- LRU3: Mise à jour de la séquence LRU
  PROCEDURE lru3_maj(
    VARIABLE seq_o : OUT unsigned(2 DOWNTO 0);
    CONSTANT acc   : IN  unsigned(1 DOWNTO 0);
    CONSTANT seq   : IN  unsigned(2 DOWNTO 0)) IS
    VARIABLE v : unsigned(4 DOWNTO 0);
  BEGIN
    seq_o:=LRU3S(to_integer(seq & acc));
  END;

  -- LRU3: Recherche du plus ancien
  FUNCTION lru3_old(
    CONSTANT seq   : IN  unsigned(2 DOWNTO 0))
    RETURN unsigned IS
  BEGIN
    RETURN seq(2 DOWNTO 1);
  END;

  -- LRU3: Recherche du plus récent
  FUNCTION lru3_new(
    CONSTANT seq   : IN  unsigned(2 DOWNTO 0)) RETURN unsigned IS
  BEGIN
    RETURN MRU3S(to_integer(seq));
  END;

  --------------------------------------
  CONSTANT LRU4_0231 : unsigned(4 DOWNTO 0) := "00001";  -- 0
  CONSTANT LRU4_0321 : unsigned(4 DOWNTO 0) := "00101";  -- 1
  CONSTANT LRU4_0132 : unsigned(4 DOWNTO 0) := "00010";  -- 2
  CONSTANT LRU4_0312 : unsigned(4 DOWNTO 0) := "00110";  -- 3
  CONSTANT LRU4_0123 : unsigned(4 DOWNTO 0) := "00011";  -- 4
  CONSTANT LRU4_0213 : unsigned(4 DOWNTO 0) := "00111";  -- 5
  CONSTANT LRU4_1230 : unsigned(4 DOWNTO 0) := "01000";  -- 6
  CONSTANT LRU4_1320 : unsigned(4 DOWNTO 0) := "01100";  -- 7
  CONSTANT LRU4_1032 : unsigned(4 DOWNTO 0) := "01010";  -- 8
  CONSTANT LRU4_1302 : unsigned(4 DOWNTO 0) := "01110";  -- 9
  CONSTANT LRU4_1023 : unsigned(4 DOWNTO 0) := "01011";  -- 10
  CONSTANT LRU4_1203 : unsigned(4 DOWNTO 0) := "01111";  -- 11
  CONSTANT LRU4_2130 : unsigned(4 DOWNTO 0) := "10000";  -- 12
  CONSTANT LRU4_2310 : unsigned(4 DOWNTO 0) := "10100";  -- 13
  CONSTANT LRU4_2031 : unsigned(4 DOWNTO 0) := "10001";  -- 14
  CONSTANT LRU4_2301 : unsigned(4 DOWNTO 0) := "10101";  -- 15
  CONSTANT LRU4_2013 : unsigned(4 DOWNTO 0) := "10011";  -- 16
  CONSTANT LRU4_2103 : unsigned(4 DOWNTO 0) := "10111";  -- 17
  CONSTANT LRU4_3120 : unsigned(4 DOWNTO 0) := "11000";  -- 18
  CONSTANT LRU4_3210 : unsigned(4 DOWNTO 0) := "11100";  -- 19
  CONSTANT LRU4_3021 : unsigned(4 DOWNTO 0) := "11001";  -- 20
  CONSTANT LRU4_3201 : unsigned(4 DOWNTO 0) := "11101";  -- 21
  CONSTANT LRU4_3012 : unsigned(4 DOWNTO 0) := "11010";  -- 22
  CONSTANT LRU4_3102 : unsigned(4 DOWNTO 0) := "11110";  -- 23
  
  TYPE arr_lru4 IS ARRAY(natural RANGE <>) OF unsigned(4 DOWNTO 0);
  CONSTANT LRU4S : arr_lru4(0 TO 127) := (
    -- 0:00      1:01      2:10      3:11
    LRU4_2310,LRU4_0231,LRU4_0312,LRU4_0213,  -- 00000 <rien>
    LRU4_2310,LRU4_0231,LRU4_0312,LRU4_0213,  -- 00001 LRU_0231
    LRU4_1320,LRU4_0321,LRU4_0132,LRU4_0123,  -- 00010 LRU_0132
    LRU4_1230,LRU4_0231,LRU4_0132,LRU4_0123,  -- 00011 LRU_0123
    LRU4_3210,LRU4_0321,LRU4_0312,LRU4_0213,  -- 00100 <rien>
    LRU4_3210,LRU4_0321,LRU4_0312,LRU4_0213,  -- 00101 LRU_0321
    LRU4_3120,LRU4_0321,LRU4_0312,LRU4_0123,  -- 00110 LRU_0312
    LRU4_2130,LRU4_0231,LRU4_0132,LRU4_0213,  -- 00111 LRU_0213
    LRU4_1230,LRU4_2301,LRU4_1302,LRU4_1203,  -- 01000 LRU_1230
    LRU4_1230,LRU4_2301,LRU4_1302,LRU4_1203,  -- 01001 <rien>
    LRU4_1320,LRU4_0321,LRU4_1032,LRU4_1023,  -- 01010 LRU_1032
    LRU4_1230,LRU4_0231,LRU4_1032,LRU4_1023,  -- 01011 LRU_1023
    LRU4_1320,LRU4_3201,LRU4_1302,LRU4_1203,  -- 01100 LRU_1320
    LRU4_1320,LRU4_3201,LRU4_1302,LRU4_1203,  -- 01101 <rien>
    LRU4_1320,LRU4_3021,LRU4_1302,LRU4_1023,  -- 01110 LRU_1302
    LRU4_1230,LRU4_2031,LRU4_1032,LRU4_1203,  -- 01111 LRU_1203
    LRU4_2130,LRU4_2301,LRU4_1302,LRU4_2103,  -- 10000 LRU_2130
    LRU4_2310,LRU4_2031,LRU4_0312,LRU4_2013,  -- 10001 LRU_2031
    LRU4_2130,LRU4_2031,LRU4_0132,LRU4_2013,  -- 10010 <rien>
    LRU4_2130,LRU4_2031,LRU4_0132,LRU4_2013,  -- 10011 LRU_2013
    LRU4_2310,LRU4_2301,LRU4_3102,LRU4_2103,  -- 10100 LRU_2310
    LRU4_2310,LRU4_2301,LRU4_3012,LRU4_2013,  -- 10101 LRU_2301
    LRU4_2130,LRU4_2031,LRU4_1032,LRU4_2103,  -- 10110 <rien>
    LRU4_2130,LRU4_2031,LRU4_1032,LRU4_2103,  -- 10111 LRU_2103
    LRU4_3120,LRU4_3201,LRU4_3102,LRU4_1203,  -- 11000 LRU_3120
    LRU4_3210,LRU4_3021,LRU4_3012,LRU4_0213,  -- 11001 LRU_3021
    LRU4_3120,LRU4_3021,LRU4_3012,LRU4_0123,  -- 11010 LRU_3012
    LRU4_3120,LRU4_3021,LRU4_3012,LRU4_0123,  -- 11011 <rien>
    LRU4_3210,LRU4_3201,LRU4_3102,LRU4_2103,  -- 11100 LRU_3210
    LRU4_3210,LRU4_3201,LRU4_3012,LRU4_2013,  -- 11101 LRU_3201
    LRU4_3120,LRU4_3021,LRU4_3102,LRU4_1023,  -- 11110 LRU_3102
    LRU4_3120,LRU4_3021,LRU4_3102,LRU4_1023); -- 11111 <rien>
    
  -- LRU4: Mise à jour de la séquence LRU
  PROCEDURE lru4_maj(
    VARIABLE seq_o : OUT unsigned(4 DOWNTO 0);
    CONSTANT acc   : IN  unsigned(1 DOWNTO 0);
    CONSTANT seq   : IN  unsigned(4 DOWNTO 0)) IS
  BEGIN
    seq_o:=LRU4S(to_integer(seq & acc));
    seq_o(1 DOWNTO 0):=acc;
  END;

  -- LRU4: Recherche du plus ancien
  FUNCTION lru4_old(
    CONSTANT seq   : IN  unsigned(4 DOWNTO 0))
    RETURN unsigned IS
  BEGIN
    RETURN seq(4 DOWNTO 3);
  END;
  
  -- LRU4: Recherche du plus récent
  FUNCTION lru4_new(
    CONSTANT seq   : IN  unsigned(4 DOWNTO 0)) RETURN unsigned IS
  BEGIN
    RETURN seq(1 DOWNTO 0);
  END;
  
  --------------------------------------
  -- PLRU 5 ... 8
  -- 0   1   2   3   4   5   6   7
  --   3       4       5       6
  --       1               2  
  --               0
  --
  PROCEDURE plru8_maj(
    VARIABLE seq_o : OUT unsigned(6 DOWNTO 0);
    CONSTANT acc   : IN  unsigned(2 DOWNTO 0);
    CONSTANT seq   : IN  unsigned(6 DOWNTO 0)) IS
  BEGIN
    CASE acc IS
      WHEN "000" => seq_o:=(seq AND "1110100") OR "0000000";
      WHEN "001" => seq_o:=(seq AND "1110100") OR "0001000";
      WHEN "010" => seq_o:=(seq AND "1101100") OR "0000010";
      WHEN "011" => seq_o:=(seq AND "1101100") OR "0010010";
      WHEN "100" => seq_o:=(seq AND "1011010") OR "0000001";
      WHEN "101" => seq_o:=(seq AND "1011010") OR "0100001";
      WHEN "110" => seq_o:=(seq AND "0111010") OR "0000101";
      WHEN OTHERS=> seq_o:=(seq AND "0111010") OR "1000101";
    END CASE;
  END;
  
  -- PLRU8: Recherche du plus ancien
  FUNCTION plru8_old(seq   : IN  unsigned(6 DOWNTO 0)) RETURN unsigned IS
  BEGIN
    IF seq(0)='1' THEN
      IF seq(1)='1' THEN
        IF seq(3)='1' THEN RETURN "000"; ELSE RETURN "001"; END IF;
      ELSE
        IF seq(4)='1' THEN RETURN "010"; ELSE RETURN "011"; END IF;
      END IF;
    ELSE
      IF seq(2)='1' THEN
        IF seq(5)='1' THEN RETURN "100"; ELSE RETURN "101"; END IF;
      ELSE
        IF seq(6)='1' THEN RETURN "110"; ELSE RETURN "111"; END IF;
      END IF;
    END IF;
  END;

  FUNCTION plru5_old(seq   : IN  unsigned(6 DOWNTO 0)) RETURN unsigned IS
  BEGIN RETURN plru8_old(seq OR "0100100"); END;
  
  FUNCTION plru6_old(seq   : IN  unsigned(6 DOWNTO 0)) RETURN unsigned IS
  BEGIN  RETURN plru8_old(seq OR "0000100"); END;

  FUNCTION plru7_old(seq   : IN  unsigned(6 DOWNTO 0)) RETURN unsigned IS
  BEGIN RETURN plru8_old(seq OR "1000000"); END;
  
  -- PLRU8: Recherche du plus récent
  FUNCTION plru8_new(seq   : IN  unsigned(6 DOWNTO 0)) RETURN unsigned IS
  BEGIN
    IF seq(0)='0' THEN
      IF seq(1)='0' THEN
        IF seq(3)='0' THEN RETURN "000"; ELSE RETURN "001"; END IF;
      ELSE
        IF seq(4)='0' THEN RETURN "010";  ELSE RETURN "011"; END IF;
      END IF;
    ELSE
      IF seq(2)='0' THEN
        IF seq(5)='0' THEN RETURN "100"; ELSE RETURN "101"; END IF;
      ELSE
        IF seq(6)='0' THEN RETURN "110"; ELSE RETURN "111"; END IF;
      END IF;
    END IF;
  END plru8_new;
  
  FUNCTION plru5_new(seq   : IN  unsigned(6 DOWNTO 0)) RETURN unsigned IS
  BEGIN RETURN plru8_new(seq AND "1011011"); END FUNCTION;

  FUNCTION plru6_new(seq   : IN  unsigned(6 DOWNTO 0)) RETURN unsigned IS
  BEGIN RETURN plru8_new(seq AND "1111011"); END FUNCTION;

  FUNCTION plru7_new(seq   : IN  unsigned(6 DOWNTO 0)) RETURN unsigned IS
  BEGIN RETURN plru8_new(seq AND "0111111"); END FUNCTION;
  
  --------------------------------------
  -- LRU: Mise à jour de la séquence LRU
  FUNCTION lru_maj(
    CONSTANT i : IN unsigned(7 DOWNTO 0);  -- Séquence précédente
    CONSTANT no : IN natural RANGE 0 TO 7; -- Nouveau plus récent
    CONSTANT nb : IN natural RANGE 1 TO 8) -- Nombre d'entrées
    RETURN unsigned IS
    VARIABLE n : uv3;
    VARIABLE o : uv8;
  BEGIN
    o:=x"00";
    n:=to_unsigned(no,3);
    CASE nb IS
      WHEN 1 =>
        o(0):='0';
      WHEN 2 =>
        lru2_maj(o(0),n(0),i(0));
      WHEN 3 =>
        lru3_maj(o(2 DOWNTO 0),n(1 DOWNTO 0),i(2 DOWNTO 0));
      WHEN 4 =>
        lru4_maj(o(4 DOWNTO 0),n(1 DOWNTO 0),i(4 DOWNTO 0));
      WHEN 5 TO 8 =>
        plru8_maj(o(6 DOWNTO 0),n,i(6 DOWNTO 0));
      WHEN OTHERS =>
        REPORT "LRU Invalide : "& integer'image(nb) SEVERITY failure;
    END CASE;
    RETURN o;
  END lru_maj;
  
  -- LRU: Recherche du plus ancien
  FUNCTION lru_old(
    CONSTANT i  : IN uv8;
    CONSTANT nb : IN natural RANGE 1 TO 8)  -- Nombre d'entrées
    RETURN natural IS
  BEGIN
    CASE nb IS
      WHEN 1 =>
        RETURN 0;
      WHEN 2 =>
        IF lru2_old(i(0))='0' THEN
          RETURN 0;
        ELSE
          RETURN 1;
        END IF;
      WHEN 3 =>
        RETURN to_integer(lru3_old(i(2 DOWNTO 0)));
      WHEN 4 =>
        RETURN to_integer(lru4_old(i(4 DOWNTO 0)));
      WHEN 5 =>
        RETURN to_integer(plru5_old(i(6 DOWNTO 0)));
      WHEN 6 =>
        RETURN to_integer(plru6_old(i(6 DOWNTO 0)));
      WHEN 7 =>
        RETURN to_integer(plru7_old(i(6 DOWNTO 0)));
      WHEN 8 =>
        RETURN to_integer(plru8_old(i(6 DOWNTO 0)));
    END CASE;
  END lru_old;
  
  -- LRU: Recherche du plus récent
  FUNCTION lru_new(
    CONSTANT i  : IN uv8;
    CONSTANT nb : IN natural RANGE 1 TO 8)  -- Nombre d'entrées
    RETURN natural IS
  BEGIN
    CASE nb IS
      WHEN 1 =>
        RETURN 0;
      WHEN 2 =>
        IF lru2_new(i(0))='0' THEN
          RETURN 0;
        ELSE
          RETURN 1;
        END IF;
      WHEN 3 =>
        RETURN to_integer(lru3_new(i(2 DOWNTO 0)));
      WHEN 4 =>
        RETURN to_integer(lru4_new(i(4 DOWNTO 0)));
      WHEN 5 =>
        RETURN to_integer(plru5_new(i(6 DOWNTO 0)));
      WHEN 6 =>
        RETURN to_integer(plru6_new(i(6 DOWNTO 0)));
      WHEN 7 =>
        RETURN to_integer(plru7_new(i(6 DOWNTO 0)));
      WHEN 8 =>
        RETURN to_integer(plru8_new(i(6 DOWNTO 0)));
    END CASE;
  END lru_new;

  -- LRU : Décision mise à jour après une lecture
  FUNCTION lru_rmaj (
    CONSTANT hist : uv8;
    CONSTANT no   : natural RANGE 0 TO 3;
    CONSTANT lf   : type_rcache_mode;
    CONSTANT nb   : natural RANGE 1 TO 8)
    RETURN boolean IS
  BEGIN
      CASE lf IS
        WHEN A => RETURN (no/=lru_new(hist,nb));
        WHEN B => RETURN (no= lru_old(hist,nb));
        WHEN N => RETURN false;
      END CASE;
  END FUNCTION lru_rmaj;
  
  --############################################################################
  -- MMU

  -- Recherche/Sélection TLB
  PROCEDURE tlb_test(
    VARIABLE hit   : OUT std_logic;         -- Correspondance trouvée
    VARIABLE flush : OUT std_logic;         -- A purger, si flush
    CONSTANT tlb   : IN  type_tlb;          -- TLB à comparer
    CONSTANT va    : IN  uv32;              -- Adresse virtuelle
    CONSTANT us    : IN  std_logic;         -- 0=User 1=Super
    CONSTANT ctx   : IN  unsigned;          -- Contexte
    CONSTANT aflush : IN std_logic) IS      -- Force flush
    ALIAS    pt    : unsigned(2 DOWNTO 0) IS va(10 DOWNTO 8);
  BEGIN
    -- HIT ----------------------------------------
    CASE tlb.st IS
      WHEN "00" =>                      -- 4Go, level 0
        hit:='1';
      WHEN "01" =>                      -- 16Mo, level 1
        hit:=to_std_logic(tlb.va(31 DOWNTO 24)=va(31 DOWNTO 24));
      WHEN "10" =>                      -- 256ko, level 2
        hit:=to_std_logic(tlb.va(31 DOWNTO 18)=va(31 DOWNTO 18));
      WHEN OTHERS =>                    -- 4ko, level 3
        hit:=to_std_logic(tlb.va(31 DOWNTO 12)=va(31 DOWNTO 12));
    END CASE;
    
    -- Super acces
    -- En mode super, on peut ignorer le numéro de contexte seulement si le
    -- type d'accès est 110 ou 111
    IF tlb.ctx(ctx'range)/=ctx AND
      (us='0' OR (tlb.acc/="110" AND tlb.acc/="111")) THEN
      hit:='0';
    END IF;
    
    -- FLUSH -----------------------------------------
    CASE pt IS
      WHEN PT_PAGE =>
        flush:=to_std_logic((tlb.acc>="110" OR tlb.ctx(ctx'range)=ctx) AND
                            tlb.va(31 DOWNTO 12)=va(31 DOWNTO 12) AND
                            tlb.st="11"); -- Level 3
        
      WHEN PT_SEGMENT =>
        flush:=to_std_logic((tlb.acc>="110" OR tlb.ctx(ctx'range)=ctx) AND
                            tlb.va(31 DOWNTO 18)=va(31 DOWNTO 18) AND
                            (tlb.st="11" OR tlb.st="10")); -- Level 3 & 2
       
      WHEN PT_REGION =>
        flush:=to_std_logic((tlb.acc>="110" OR tlb.ctx(ctx'range)=ctx) AND
                            tlb.va(31 DOWNTO 24)=va(31 DOWNTO 24) AND
                            (tlb.st="11" OR tlb.st="10" OR tlb.st="01")); --L321
        
      WHEN PT_CONTEXT =>
        flush:=to_std_logic(tlb.acc<="101" AND tlb.ctx(ctx'range)=ctx);

      WHEN OTHERS => --PT_ENTIRE =>
        flush:='1';
    END CASE;

    IF aflush='1' THEN
      flush:='1';
    END IF;
    
    -- HITFLUSH
    IF tlb.v='0' THEN
      hit:='0';
      flush:='0';
    END IF;
  END PROCEDURE tlb_test;
  
  -- Translation d'adresses d'après un TLB, protection accès
  PROCEDURE tlb_trans (
    VARIABLE ft   : OUT unsigned(2 DOWNTO 0);   -- Fault type
    VARIABLE pa   : OUT unsigned(35 DOWNTO 0);  -- Adresse physique
    VARIABLE c    : OUT std_logic;              -- Cacheable
    VARIABLE m    : OUT std_logic;              -- Modified
    VARIABLE s    : OUT std_logic;              -- Superviseur
    VARIABLE wb   : OUT std_logic;              -- Write Thru=0 / Back=1
    VARIABLE al   : OUT std_logic;              -- Write WoAlloc=0 / WithAlloc=1
    CONSTANT tlb  : IN  type_tlb;               -- TLB à comparer
    CONSTANT va   : IN  uv32;                   -- Adresse virtuelle
    CONSTANT ls   : IN  std_logic;              -- 0=Load 1=Store
    CONSTANT us   : IN  std_logic;              -- 0=User 1=Super
    CONSTANT di   : IN  std_logic) IS           -- 0=Data 1=Instruction
  BEGIN
    -- Génération adresse physique
    CASE tlb.st IS
      WHEN "00" =>                      -- 4Go
        pa:=tlb.ppn(35 DOWNTO 32) & va(31 DOWNTO 0);
      WHEN "01" =>                      -- 16Mo
        pa:=tlb.ppn(35 DOWNTO 24) & va(23 DOWNTO 0);
      WHEN "10" =>                      -- 256ko
        pa:=tlb.ppn(35 DOWNTO 18) & va(17 DOWNTO 0);
      WHEN OTHERS =>                    -- 4ko
        pa:=tlb.ppn(35 DOWNTO 12) & va(11 DOWNTO 0);
    END CASE;
    
    -- Test validité                          User | Super
    ft:=FT_NONE;
    s:='0';
    CASE tlb.acc IS
      WHEN "000" =>                        -- R    |  R    | Data
        IF ls='1' OR di='1' THEN
          ft:=FT_PROTECTION;
        END IF;
      WHEN "001" =>                        -- RW   |  RW   | Data
        IF di='1' THEN
          ft:=FT_PROTECTION;
        END IF;
      WHEN "010" =>                        -- R X  |  R X  | Data & Code
        IF ls='1' THEN
          ft:=FT_PROTECTION;
        END IF;
      WHEN "011" =>                        -- RWX  |  RWX  | Data & Code
        NULL;
      WHEN "100" =>                        --   X  |    X  | Code
        IF di='0' OR ls='1' THEN
          ft:=FT_PROTECTION;
        END IF;
      WHEN "101" =>                        -- R    |  RW   | Data
        IF di='1' OR (ls='1' AND us='0') THEN
          ft:=FT_PROTECTION;
        END IF;
      WHEN "110" =>                        --      |  R X  | Data & Code
        IF ls='1' AND us='1' THEN
          ft:=FT_PROTECTION;
        ELSIF us='0' THEN
          ft:=FT_PRIVILEGE;
        END IF;
        s:='1';
      WHEN "111" =>                        --      |  RWX  | Data & Code
        IF us='0' THEN
          ft:=FT_PRIVILEGE;
        END IF;
        s:='1';
      WHEN OTHERS => NULL;
    END CASE;

    c :=tlb.c;
    m :=tlb.m;
    wb:=tlb.wb;
    al:=tlb.al;
  END PROCEDURE tlb_trans;
  
  -- Conversion PTE --> TLB (suite à un TableWalk)
  FUNCTION tlb_encode (
    CONSTANT pte : IN uv32;            -- PTE en mémoire
    CONSTANT va  : IN uv32;            -- Adresse virtuelle
    CONSTANT st  : IN unsigned(1 DOWNTO 0);  -- Niveau de translation
    CONSTANT ctx : IN unsigned;        -- Numéro de contexte
    CONSTANT m   : IN std_logic;       -- 'Modified'
    CONSTANT wb  : IN std_logic;
    CONSTANT al  : IN std_logic) RETURN type_tlb IS
    VARIABLE t : type_tlb;
  BEGIN
    t.v:='1';
    t.va:=va(31 DOWNTO 12);
    t.st:=st;
    t.ctx(ctx'range):=ctx;
    t.acc:=pte(4 DOWNTO 2);
    t.ppn:=pte(31 DOWNTO 8);
    t.c  :=pte(7);
    t.m  :=pte(6) OR m;
    t.wb :=wb;
    t.al :=al;
    RETURN t;
  END FUNCTION tlb_encode;
  
  -- Tablewalk Test (SparcV8 reference, Table H-4)
  -- Décision suite du tablewalk, selon le contenu de la table
  -- <AVOIR> En fait, seul le PT_ENTIRE est réellement obligatoire 
  PROCEDURE tablewalk_test (
    VARIABLE cont  : OUT std_logic;     -- 1=Continue TW, 0=Arrêt
    VARIABLE err   : OUT std_logic;     -- 1=Erreur, 0=Normal
    CONSTANT d     : IN  uv32;          -- Données lues : PTE ou PTD
    CONSTANT st    : IN  unsigned(1 DOWNTO 0);     -- Niveau du TW 0 -> 3
    CONSTANT probe : IN  std_logic;     -- 1=Probe, 0=Lecture/Ecriture
    CONSTANT pt    : IN  unsigned(2 DOWNTO 0)) IS  -- Probe TYPE
    ALIAS et : unsigned(1 DOWNTO 0) IS d(1 DOWNTO 0);  -- Entry Type
  BEGIN

    IF pt=PT_PAGE AND probe='1' THEN
      -- Page Probe
      IF et=ET_PTD AND st/="11" THEN
        cont:='1';
        err:='0';
      ELSIF (et=ET_PTE OR et=ET_INVALID) AND st="11" THEN
        cont:='0';
        err:='0';
      ELSE
        cont:='0';
        err:='1';
      END IF;
      
    ELSIF pt=PT_SEGMENT AND probe='1' THEN
      -- Segment Probe
      IF et=ET_PTD AND st/="10" THEN
        cont:='1';
        err:='0';
      ELSIF et/=ET_RESERVED AND st="10" THEN
        cont:='0';
        err:='0';
      ELSE
        cont:='0';
        err:='1';
      END IF;
      
    ELSIF pt=PT_REGION AND probe='1' THEN
      -- Region Probe
      IF et=ET_PTD AND st/="01" THEN
        cont:='1';
        err:='0';
      ELSIF et/=ET_RESERVED AND st="01" THEN
        cont:='0';
        err:='0';
      ELSE
        cont:='0';
        err:='1';
      END IF;
      
    ELSIF pt=PT_CONTEXT AND probe='1' THEN
      -- Context Probe
      IF et=ET_PTD AND st/="00" THEN
        cont:='1';
        err:='0';
      ELSIF et/=ET_RESERVED AND st="00" THEN
        cont:='0';
        err:='0';
      ELSE
        cont:='0';
        err:='1';
      END IF;
      
    ELSE --IF pt=PT_ENTIRE OR probe='0' THEN
      -- Entire Probe, ou accès normal
      IF et=ET_PTD AND st/="11" THEN
        cont:='1';
        err:='0';
      ELSIF et=ET_PTE THEN
        cont:='0';
        err:='0';
      ELSE
        cont:='0';
        err:='1';
      END IF;
    END IF;

  END tablewalk_test;
  
  FUNCTION tlb_or (
    CONSTANT a : type_tlb;
    CONSTANT b : type_tlb) RETURN type_tlb IS
    VARIABLE v : type_tlb;
  BEGIN
    v.v  :=a.v   OR b.v;
    v.va :=a.va  OR b.va;
    v.st :=a.st  OR b.st;
    v.ctx:=a.ctx OR b.ctx;
    v.acc:=a.acc OR b.acc;
    v.ppn:=a.ppn OR b.ppn;
    v.c  :=a.c   OR b.c;
    v.m  :=a.m   OR b.m;
    v.wb :=a.wb  OR b.wb;
    v.al :=a.al  OR b.al;
    RETURN v;
  END FUNCTION tlb_or;
  
  --############################################################################
  -- CACHE

  CONSTANT TAG_V  : natural := 0; -- Valid
  CONSTANT TAG_S  : natural := 1; -- Supervisor
  CONSTANT TAG_M  : natural := 1; -- Modified (w-back)
  CONSTANT TAG_SH : natural := 4; -- Shared (mp)
  
  -- Translation d'adresses lorsque la MMU est totalement absente
  PROCEDURE cache_trans (
    VARIABLE ft   : OUT unsigned(2 DOWNTO 0);   -- Fault type
    VARIABLE pa   : OUT unsigned(35 DOWNTO 0);  -- Adresse physique
    VARIABLE c    : OUT std_logic;              -- Cacheable
    VARIABLE m    : OUT std_logic;              -- Modified
    VARIABLE wb   : OUT std_logic;              -- Write Thru=0 / Back=1
    VARIABLE al   : OUT std_logic;              -- Write WoAlloc=0 /WithAlloc=1
    CONSTANT va   : IN  uv32;                   -- Adresse virtuelle
    CONSTANT ls   : IN  std_logic;              -- 0=Load 1=Store
    CONSTANT us   : IN  std_logic;              -- 0=User 1=Super
    CONSTANT di   : IN  std_logic) IS           -- 0=Data 1=Instruction
  BEGIN
    ft:=FT_NONE;
    pa:="0000" & va;
    -- 0000000 .. 7FFFFFFF : Cacheable
    -- 8000000 .. FFFFFFFF : Non Cacheable
    IF va(31)='0' THEN
      c:='1';
    ELSE
      c:='0';
    END IF;
    -- Il faut M=1 pour supprimer le Tablewalk
    m:='1';
    wb:='0';
    al:='0';
  END PROCEDURE cache_trans;
  
  --------------------------------------
  FUNCTION vtag_encode (
    CONSTANT va         : IN  uv32;                  -- Adresse Virtuelle (VT)
    CONSTANT ctx        : IN  unsigned;              -- Contexte          (VT)
    CONSTANT v          : IN  std_logic;             -- Valid
    CONSTANT s          : IN  std_logic;             -- Super             (VT)
    CONSTANT h          : IN  unsigned(1 DOWNTO 0);  -- Historique
    CONSTANT NB_CACHE   : IN natural;                -- Taille voie cache
    CONSTANT NB_CONTEXT : IN natural) RETURN unsigned IS -- Nombre de contextes
    VARIABLE tag        : uv32;
  BEGIN
    
    tag(31 DOWNTO NB_CACHE):=va(31 DOWNTO NB_CACHE);
    tag(NB_CONTEXT+3 DOWNTO 4):=ctx(NB_CONTEXT-1 DOWNTO 0);
    tag(TAG_V):=v;
    tag(TAG_S):=s;
    tag(3 DOWNTO 2):=h;
    RETURN tag;
  END FUNCTION;
  
  --------------------------------------
  FUNCTION ptag_encode (
    CONSTANT pa        : IN  unsigned(35 DOWNTO 0); -- Adresse Physique  (PT)
    CONSTANT v         : IN  std_logic;             -- Valid
    CONSTANT m         : IN  std_logic;             -- Modif (pour WB)
    CONSTANT s         : IN  std_logic;             -- Shared
    CONSTANT h         : IN  unsigned(1 DOWNTO 0);  -- Historique
    CONSTANT NB_CACHE  : IN  natural) RETURN unsigned IS -- Taille voie cache
    VARIABLE tag       : uv32;
  BEGIN
    tag(31 DOWNTO NB_CACHE-4):=pa(35 DOWNTO NB_CACHE);
    tag(TAG_V):=v;
    tag(TAG_M):=m;
    tag(TAG_SH):=s;
    tag(3 DOWNTO 2):=h;
    tag(7 DOWNTO 5):="000";
    RETURN tag;
  END FUNCTION;

  FUNCTION ptag_pa (
    CONSTANT tag : IN uv32;
    CONSTANT pi  : IN uv32;
    CONSTANT NB_CACHE : IN natural) RETURN unsigned IS
    VARIABLE v : unsigned(35 DOWNTO 0);
  BEGIN
    v(35 DOWNTO NB_CACHE):=tag(31 DOWNTO NB_CACHE-4);
    v(NB_CACHE-1 DOWNTO 0):=pi(NB_CACHE-1 DOWNTO 0);
    RETURN v;
  END FUNCTION ptag_pa;
  
  --------------------------------------
  -- Test hit cache
  PROCEDURE vtag_test(
    VARIABLE hit        : OUT std_logic;            -- Cache hit
    VARIABLE inval      : OUT std_logic;            -- Hit, si inval
    CONSTANT tag        : IN uv32;                  -- Entrée du cache à tester
    CONSTANT va         : IN uv32;                  -- Adresse Virtuelle
    CONSTANT ctx        : IN unsigned;              -- Contexte
    CONSTANT asi        : IN uv8;                   -- ASI (pour codes flush)
    CONSTANT NB_CACHE   : IN natural RANGE 0 TO 31; -- Taille cache (constante)
    CONSTANT NB_CONTEXT : IN natural;               -- Nombre de contextes
    CONSTANT MMU_DIS    : IN boolean) IS            -- MMU=false, Cache seul=true
    ALIAS asi20 : unsigned(2 DOWNTO 0) IS asi(2 DOWNTO 0);
  BEGIN
    IF tag(31 DOWNTO NB_CACHE)=va(31 DOWNTO NB_CACHE)
      AND (tag(NB_CONTEXT+3 DOWNTO 4)=ctx OR MMU_DIS OR tag(TAG_S)='1')
      AND tag(TAG_V)='1' THEN
      hit:='1';
    ELSE
      hit:='0';
    END IF;
    
    inval:='0';
    CASE asi20 IS
      WHEN "000" =>                     -- Page flush
        IF (tag(TAG_S)='1' OR tag(NB_CONTEXT+3 DOWNTO 4)=ctx OR MMU_DIS) AND
          tag(31 DOWNTO 12)=va(31 DOWNTO 12) THEN
          inval:='1';
        END IF;
        
      WHEN "001" =>                     -- Segment flush
        IF (tag(TAG_S)='1' OR tag(NB_CONTEXT+3 DOWNTO 4)=ctx OR MMU_DIS) AND
          tag(31 DOWNTO 18)=va(31 DOWNTO 18) THEN
          inval:='1';
        END IF;
        
      WHEN "010" =>                     -- Region flush
        IF (tag(TAG_S)='1' OR tag(NB_CONTEXT+3 DOWNTO 4)=ctx OR MMU_DIS) AND
          tag(31 DOWNTO 24)=va(31 DOWNTO 24) THEN
          inval:='1';
        END IF;
        
      WHEN "011" =>                     -- Context flush
        IF tag(TAG_S)='0' AND (tag(NB_CONTEXT+3 DOWNTO 4)=ctx OR MMU_DIS) THEN
          inval:='1';
        END IF;
        
      WHEN "100" =>                     -- User flush
        IF tag(TAG_S)='0' THEN
          inval:='1';
        END IF;
        
      WHEN OTHERS =>                    -- Any flush
        inval:='1';
    END CASE;
    inval:='1';                                 -- <PROVISOIRE>
  END PROCEDURE vtag_test;
  
  --------------------------------------
  -- Test hit cache
  PROCEDURE ptag_test(
    VARIABLE hit      : OUT std_logic;             -- Cache hit
    VARIABLE inval    : OUT std_logic;             -- Hit, si inval
    VARIABLE flush    : OUT std_logic;             -- Hit, si invalidation
    CONSTANT tag      : IN  uv32;                  -- Entrée du cache à tester
    CONSTANT pa       : IN  unsigned(35 DOWNTO 0); -- Adresse Physique (PT)
    CONSTANT asi      : IN  uv8;                   -- ASI (pour codes flush)
    CONSTANT NB_CACHE : IN  natural RANGE 0 TO 31) IS -- Taille cache (const)
    ALIAS asi20 : unsigned(2 DOWNTO 0) IS asi(2 DOWNTO 0);
  BEGIN
    IF tag(31 DOWNTO NB_CACHE-4)=pa(35 DOWNTO NB_CACHE) AND tag(TAG_V)='1' THEN
      hit:='1';
    ELSE
      hit:='0';
    END IF;
    
    CASE asi20 IS
      WHEN "000" =>                     -- Page flush
        IF tag(31 DOWNTO 12-4)=pa(35 DOWNTO 12) THEN
          inval:='1';
        END IF;
        
      WHEN "001" =>                     -- Segment flush
        IF tag(31 DOWNTO 18-4)=pa(35 DOWNTO 18) THEN
          inval:='1';
        END IF;
        
      WHEN "010" =>                     -- Region flush
        IF tag(31 DOWNTO 24-4)=pa(35 DOWNTO 24) THEN
          inval:='1';
        END IF;
        
      WHEN "011" =>                     -- Context flush
        inval:='1';
        
      WHEN "100" =>                     -- User flush
        inval:='1';
        
      WHEN OTHERS =>                    -- Any flush
        inval:='1';
    END CASE;
    inval:='1';        -- <PROVISOIRE>
    flush:=tag(TAG_M); -- <PROVISOIRE>
  END PROCEDURE ptag_test;

  --------------------------------------
  -- Lecture bit "Modified" d'un ptag
  PROCEDURE ptag_decode (
    VARIABLE v    : OUT std_logic;
    VARIABLE m    : OUT std_logic;
    VARIABLE s    : OUT std_logic;
    CONSTANT tag  : IN  uv32) IS
  BEGIN
    v :=tag(TAG_V);
    m :=tag(TAG_M);
    s :=tag(TAG_SH);
  END PROCEDURE ptag_decode;
  
  FUNCTION ptag_decode (
    CONSTANT tag  : IN  uv32) RETURN enum_mesi IS
  BEGIN
    IF tag(TAG_V)='0' THEN return I; END IF;
    IF tag(TAG_M)='1' THEN return M; END IF;
    IF tag(TAG_S)='1' THEN return S; END IF;
    return E;
  END FUNCTION ptag_decode;
  
  FUNCTION ptag_mod (
    CONSTANT tag  : IN  uv32;
    CONSTANT v    : IN  std_logic;
    CONSTANT m    : IN  std_logic;
    CONSTANT s    : IN  std_logic) RETURN unsigned IS
    VARIABLE t : uv32 :=tag;
  BEGIN
    t(TAG_V):=v;
    t(TAG_M):=m;
    t(TAG_SH):=s;
    RETURN t;
  END FUNCTION ptag_mod;
  
  --------------------------------------
  FUNCTION tag_selfill (CONSTANT tag  : IN arr_uv32;
                        CONSTANT hist : IN uv8) RETURN natural IS
    VARIABLE tr : std_logic;
    VARIABLE no : natural RANGE 0 TO tag'high;
  BEGIN
    tr:='0';
    FOR i IN 0 TO tag'high LOOP
      IF tag(i)(TAG_V)='0' THEN
        no:=i;
        tr:='1';
      END IF;
    END LOOP;
    IF tr='0' THEN
      no:=lru_old(hist,tag'high+1);
    END IF;
    RETURN no;
  END tag_selfill;
  
  --------------------------------------
  PROCEDURE tag_maj(
    VARIABLE tag_o   : OUT arr_uv32;        -- Tags mis à jour
    CONSTANT tagr    : IN  uv32;            -- Nouvelle valeur tag
    CONSTANT tag     : IN  arr_uv32;        -- Tags précédents
    CONSTANT hist    : IN  uv8;             -- Historique
    CONSTANT rd      : IN  std_logic;       -- 1=Lecture
    CONSTANT wthru   : IN  std_logic;       -- 1=Ecriture Write Thru
    CONSTANT wback   : IN  std_logic;       -- 1=Ecriture Write Back
    CONSTANT flush   : IN  std_logic;       -- 1=Flush
    CONSTANT fill    : IN  std_logic;       -- 1=FILL/DEFAULT
    CONSTANT inval   : IN  std_logic;       -- 1=Invalidation
    CONSTANT nohit   : IN  natural;         -- Numéro voie changée Write
    CONSTANT nofill  : IN  natural;         -- Numéro voie à remplir
    CONSTANT noflush : IN  natural) IS      -- Numéro voie à purger
    VARIABLE tagv    : arr_uv32(0 TO tag'high);
    VARIABLE no      : natural RANGE 0 TO tag'high; --Numéro voie sélectionnée
    VARIABLE histo   : uv8;
  BEGIN
    tagv:=tag;
    
    IF rd='1' OR wthru='1' OR wback='1' THEN
      -- Read / Write
      no:=nohit;
      IF wback='1' THEN
        tagv(nohit)(TAG_M):='1';
--        tagv(nohit)(TAG_S):='0';
      END IF;
      tagv(nohit)(TAG_V):='1';
    ELSIF flush='1' THEN
      -- Flush
      no:=noflush;
      tagv(noflush)(TAG_V):='0';
      tagv(noflush)(TAG_M):='0';
--      tagv(noflush)(TAG_S):='0';
    ELSIF fill='1' THEN
      -- Fill
      no:=nofill;
      tagv(nofill):=tagr;
    END IF;
    histo:=lru_maj(hist,no,tag'high+1);
    
    FOR i IN 0 TO tag'high LOOP
      tagv(i)(3 DOWNTO 2):=histo(i*2+1 DOWNTO i*2);
    END LOOP;
    
    IF inval='1' THEN
      FOR i IN 0 TO tag'high LOOP
        tagv(i)(TAG_V):='0';
      END LOOP;
    END IF;
    tag_o:=tagv;
  END PROCEDURE tag_maj;
  
  FUNCTION tag_mod(
    CONSTANT tag    : IN  arr_uv32;   -- Tags précédents
    CONSTANT nohit  : IN  natural) RETURN std_logic IS  -- Numéro voie
  BEGIN
    RETURN tag(nohit)(TAG_M);
  END FUNCTION tag_mod;

  --------------------------------------
  -- Find first 1
  FUNCTION ff1(CONSTANT hit : IN  unsigned) RETURN natural IS
    VARIABLE no : natural RANGE 0 TO hit'high;
  BEGIN
    no:=0;
    FOR i IN 0 TO hit'high LOOP
      IF hit(i)='1' THEN
        no:=i;
      END IF;
    END LOOP;
    RETURN no;
  END ff1;
  
  --############################################################################
  
END PACKAGE BODY mcu_pack;
