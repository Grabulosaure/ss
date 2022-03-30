-------------------------------------------------------------------------------
-- TEM : TACUS
-- Packet Unité Flottante
--------------------------------------------------------------------------------
-- DO 9/2009
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

-- Le contenu des NaN n'est pas conservé.
-- Le signe des NaN n'est pas conservé pour une soustraction.

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

USE work.base_pack.ALL;
USE work.cpu_conf_pack.ALL;

PACKAGE fpu_pack IS
  -------------------------------------- 
  -- FSR Register : Version
  
  --###########################################################################

  TYPE type_fsr IS RECORD
    rd   : unsigned(1 DOWNTO 0);   -- 31:30 : Rounding direction
                                   -- 29:28 : Unused/Rounding precision
    tem  : unsigned(4 DOWNTO 0);   -- 27:23 : Trap Enable Mask
    ns   : std_logic;              -- 22    : Nonstandard FP
                                   -- 21:20 : Reserved
                                   -- 19:17 : Version
    ftt  : unsigned(2 DOWNTO 0);   -- 16:14 : Floating Point Trap Type
    qne  : std_logic;              -- 13    : Floating Point Queue Not Empty
                                   -- 12    : Unused
    fcc  : unsigned(1 DOWNTO 0);   -- 11:10 : Floating Point Condition Codes
    aexc : unsigned(4 DOWNTO 0);   -- 9:5   : FSR Accrued Exception
    cexc : unsigned(4 DOWNTO 0);   -- 4:0   : FSR Current Exception
  END RECORD;

  CONSTANT FSR_X : type_fsr :=
    ("XX","XXXXX",'X',"XXX",'X',"XX","XXXXX","XXXXX");
  
  -- NV | OF | UF | DZ | NX
  CONSTANT X_NV : natural := 4;
  CONSTANT X_OF : natural := 3;
  CONSTANT X_UF : natural := 2;
  CONSTANT X_DZ : natural := 1;
  CONSTANT X_NX : natural := 0;
  
  FUNCTION rdfsr(CONSTANT fsr : type_fsr;
                 CONSTANT FPU_VER : unsigned(2 DOWNTO 0)) RETURN unsigned;
  PROCEDURE wrfsr (VARIABLE fsr : OUT type_fsr;
                   CONSTANT v   : IN  uv32);

  SUBTYPE type_class IS unsigned(4 DOWNTO 0);
  
  --############################################################################
  -- Floating Point TRAPS    
  -- (4.1)
  CONSTANT FTT_NONE                         : unsigned(2 DOWNTO 0):="000";
  CONSTANT FTT_IEEE_754_EXCEPTION           : unsigned(2 DOWNTO 0):="001";
  CONSTANT FTT_UNFINISHED_FPOP              : unsigned(2 DOWNTO 0):="010";
  CONSTANT FTT_UNIMPLEMENTED_FPOP           : unsigned(2 DOWNTO 0):="011";
  CONSTANT FTT_SEQUENCE_ERROR               : unsigned(2 DOWNTO 0):="100";
  CONSTANT FTT_HARDWARE_ERROR               : unsigned(2 DOWNTO 0):="101";
  CONSTANT FTT_INVALID_FP_REGISTER          : unsigned(2 DOWNTO 0):="110";
  CONSTANT FTT_RESERVED                     : unsigned(2 DOWNTO 0):="111";

  -- Rounding directions
  CONSTANT RND_NEAREST : unsigned(1 DOWNTO 0) := "00";
  CONSTANT RND_ZERO    : unsigned(1 DOWNTO 0) := "01";
  CONSTANT RND_POS     : unsigned(1 DOWNTO 0) := "10";
  CONSTANT RND_NEG     : unsigned(1 DOWNTO 0) := "11";
  
  --############################################################################
  -- (2) : 0=ADD 1=SUB (1) 0=ADD_SUB_CMP 1=CONV (2) 0=Tout 1=CMPE
  FUNCTION conv_in(
    CONSTANT fs : uv64;
    CONSTANT sd : std_logic) RETURN unsigned;
  
  FUNCTION conv_out(
    CONSTANT fs : uv64;
    CONSTANT sd : std_logic) RETURN unsigned;

  CONSTANT FOP_ADD   : uv4 := "0000";
  CONSTANT FOP_SUB   : uv4 := "0100";
  CONSTANT FOP_CMP   : uv4 := "0110";
  CONSTANT FOP_CMPE  : uv4 := "0111";
  CONSTANT FOP_fTOi  : uv4 := "0010";
  CONSTANT FOP_iTOf  : uv4 := "0011";
  
  CONSTANT FOP_MUL   : uv4 := "1000";
  CONSTANT FOP_DIV   : uv4 := "1001";
  CONSTANT FOP_SQRT  : uv4 := "1010";
  CONSTANT FOP_fTOf  : uv4 := "1011";

  CONSTANT FOP_MOV   : uv4 := "1100";
  CONSTANT FOP_NEG   : uv4 := "1101";
  CONSTANT FOP_ABS   : uv4 := "1110";

  FUNCTION fop_string(CONSTANT fop : uv4) RETURN string;
  FUNCTION to_real (CONSTANT f : unsigned) RETURN real;
  
  PROCEDURE asc_mds_1(
    VARIABLE fs1_man   : OUT unsigned(51 DOWNTO 0);
    VARIABLE fs2_man   : OUT unsigned(51 DOWNTO 0);
    VARIABLE fs1_class : OUT type_class;
    VARIABLE fs2_class : OUT type_class;
    VARIABLE fs1_exp   : OUT unsigned(10 DOWNTO 0);
    VARIABLE fs2_exp   : OUT unsigned(10 DOWNTO 0);
    VARIABLE fs2_exp0  : OUT std_logic;
    CONSTANT fs1       : IN  uv64;
    CONSTANT fs2       : IN  uv64;
    CONSTANT fop       : IN  uv4;
    CONSTANT sd        : IN  std_logic);

  PROCEDURE asc_2(
    VARIABLE fhi_man   : OUT unsigned(55 DOWNTO 0);
    VARIABLE flo_man   : OUT unsigned(55 DOWNTO 0);
    VARIABLE fhi_s     : OUT std_logic;
    VARIABLE flo_s     : OUT std_logic;
    VARIABLE expo      : OUT unsigned(10 DOWNTO 0);
    VARIABLE diff      : OUT unsigned(12 DOWNTO 0);
    CONSTANT fs1_iman  : IN  unsigned(51 DOWNTO 0);
    CONSTANT fs2_iman  : IN  unsigned(51 DOWNTO 0);
    CONSTANT fs1_class : IN  type_class;
    CONSTANT fs2_class : IN  type_class;
    CONSTANT fs1_exp   : IN  unsigned(10 DOWNTO 0);
    CONSTANT fs2_exp   : IN  unsigned(10 DOWNTO 0);
    CONSTANT fs2_exp0  : IN  std_logic;
    CONSTANT fop       : IN  uv4;
    CONSTANT sd        : IN  std_logic;
    CONSTANT sdo       : IN  std_logic);

  PROCEDURE asc_3(
    VARIABLE addsub   : OUT unsigned(56 DOWNTO 0);
    VARIABLE nz       : OUT natural RANGE 0 TO 63;    
    VARIABLE fo_s     : OUT std_logic;
    VARIABLE nxf      : OUT std_logic;
    VARIABLE nvf      : OUT std_logic;
    CONSTANT diff     : IN  unsigned(12 DOWNTO 0);    
    CONSTANT fhi_man  : IN  unsigned(55 DOWNTO 0);
    CONSTANT flo_man  : IN  unsigned(55 DOWNTO 0);
    CONSTANT fhi_s    : IN  std_logic;
    CONSTANT flo_s    : IN  std_logic;
    CONSTANT fop      : IN  uv4);

  PROCEDURE asc_4(
    VARIABLE fs_man_o : OUT unsigned(53 DOWNTO 0);
    VARIABLE fcc      : OUT unsigned(1 DOWNTO 0);
    VARIABLE nxf_o    : OUT std_logic;
    VARIABLE sticky   : OUT std_logic;
    VARIABLE expo_o   : OUT unsigned(10 DOWNTO 0);
    VARIABLE fo_s_o   : OUT std_logic;
    CONSTANT expo     : IN  unsigned(10 DOWNTO 0);
    CONSTANT nz       : IN  natural RANGE 0 TO 63;
    CONSTANT addsub   : IN  unsigned(56 DOWNTO 0);
    CONSTANT fo_s     : IN  std_logic;
    CONSTANT nxf      : IN  std_logic;
    CONSTANT fhi_s    : IN  std_logic;
    CONSTANT flo_s    : IN  std_logic;
    CONSTANT fop      : IN  uv4;
    CONSTANT sd       : IN  std_logic;              -- 0=single 1=double
    CONSTANT rd       : IN  unsigned(1 DOWNTO 0));
  
  PROCEDURE mds_2(
    VARIABLE fs1_man   : OUT unsigned(53 DOWNTO 0);
    VARIABLE fs2_man   : OUT unsigned(52 DOWNTO 0);
    VARIABLE expo      : OUT unsigned(12 DOWNTO 0);
    CONSTANT fs1_iman  : IN  unsigned(51 DOWNTO 0);
    CONSTANT fs2_iman  : IN  unsigned(51 DOWNTO 0);
    CONSTANT fs1_class : IN  type_class;
    CONSTANT fs2_class : IN  type_class;
    CONSTANT fs1_exp   : IN  unsigned(10 DOWNTO 0);
    CONSTANT fs2_exp   : IN  unsigned(10 DOWNTO 0);
    CONSTANT fop       : IN  uv4;
    CONSTANT sd        : IN  std_logic);

  PROCEDURE mds_2_unf(
    VARIABLE fs1_man   : OUT unsigned(53 DOWNTO 0);
    VARIABLE fs2_man   : OUT unsigned(52 DOWNTO 0);
    VARIABLE expo      : OUT unsigned(12 DOWNTO 0);
    VARIABLE unf       : OUT std_logic;
    CONSTANT fs1_iman  : IN  unsigned(51 DOWNTO 0);
    CONSTANT fs2_iman  : IN  unsigned(51 DOWNTO 0);
    CONSTANT fs1_class : IN  type_class;
    CONSTANT fs2_class : IN  type_class;
    CONSTANT fs1_exp   : IN  unsigned(10 DOWNTO 0);
    CONSTANT fs2_exp   : IN  unsigned(10 DOWNTO 0);
    CONSTANT fop       : IN  uv4;
    CONSTANT sd        : IN  std_logic);
  
  PROCEDURE mds_3(
    VARIABLE fs1_man_o : OUT unsigned(53 DOWNTO 0);
    VARIABLE expo_o    : OUT unsigned(12 DOWNTO 0);
    CONSTANT fs1_man   : IN  unsigned(53 DOWNTO 0);
    CONSTANT expo      : IN  unsigned(12 DOWNTO 0);
    CONSTANT fop       : IN  uv4;
    CONSTANT sd        : IN  std_logic;           -- 0=FDIVs 1=FDIVd
    CONSTANT sdo       : IN  std_logic);

  PROCEDURE mds_4(
    VARIABLE fs_man_o : OUT unsigned(53 DOWNTO 0);
    VARIABLE expo_o   : OUT unsigned(12 DOWNTO 0);
    VARIABLE sticky_o : OUT std_logic;
    VARIABLE udf_o    : OUT std_logic;
    VARIABLE nxf_o    : OUT std_logic;
    CONSTANT fs_man : IN unsigned(53 DOWNTO 0);
    CONSTANT expo   : IN unsigned(12 DOWNTO 0);
    CONSTANT sticky : IN std_logic;
    CONSTANT sdo    : IN std_logic;
    CONSTANT ufm    : IN std_logic);
  
  PROCEDURE mds_4_unf(
    VARIABLE fs_man_o : OUT unsigned(53 DOWNTO 0);
    VARIABLE expo_o   : OUT unsigned(12 DOWNTO 0);
    VARIABLE sticky_o : OUT std_logic;
    VARIABLE udf_o    : OUT std_logic;
    VARIABLE nxf_o    : OUT std_logic;
    CONSTANT fs_man : IN unsigned(53 DOWNTO 0);
    CONSTANT expo   : IN unsigned(12 DOWNTO 0);
    CONSTANT sticky : IN std_logic;
    CONSTANT sdo    : IN std_logic;
    CONSTANT ufm    : IN std_logic);
  
  PROCEDURE arrondi_infzero(
    VARIABLE fo      : OUT uv64;
    VARIABLE ovf_o   : OUT std_logic;
    VARIABLE nxf_o   : OUT std_logic;
    CONSTANT fs_man  : IN  unsigned(53 DOWNTO 0);
    CONSTANT expo    : IN  unsigned(12 DOWNTO 0);
    CONSTANT sticky  : IN  std_logic;
    CONSTANT fo_s    : IN  std_logic;
    CONSTANT sdo     : IN  std_logic;              -- 0=single 1=double
    CONSTANT nxf     : IN  std_logic;
    CONSTANT fop     : IN  uv4;
    CONSTANT ufm     : IN  std_logic;
    CONSTANT rd      : IN  unsigned(1 DOWNTO 0);   -- Round Direction 
    CONSTANT mds     : IN  boolean);
  
  PROCEDURE test_special(
    VARIABLE fo_o      : OUT uv64;
    VARIABLE iii_o     : OUT uv32;
    VARIABLE fcc_o     : OUT unsigned(1 DOWNTO 0);
    VARIABLE nvf_o     : OUT std_logic;
    VARIABLE ovf_o     : OUT std_logic;
    VARIABLE udf_o     : OUT std_logic;
    VARIABLE dzf_o     : OUT std_logic;
    VARIABLE nxf_o     : OUT std_logic;
    CONSTANT fo        : IN  uv64;
    CONSTANT iii       : IN  uv32;
    CONSTANT fcc       : IN  unsigned(1 DOWNTO 0);
    CONSTANT nvf       : IN  std_logic;
    CONSTANT ovf       : IN  std_logic;
    CONSTANT udf       : IN  std_logic;
    CONSTANT nxf       : IN  std_logic;
    CONSTANT fs1_class : IN  type_class;
    CONSTANT fs2_class : IN  type_class;
    CONSTANT fop       : IN  uv4);
  
  -- Default Quiet NaN
  CONSTANT DOUBLE_QNaN : uv64 :="0" & "11111111111" &
    "1111111111111111111111111111111111111111111111111111";
  
  -- Default Signaling NaN
  CONSTANT DOUBLE_SNaN : uv64 :="0" & "11111111111" &
    "0111111111111111111111111111111111111111111111111111";
  
  -- +Infini
  CONSTANT DOUBLE_Infini : uv64 :="0" & "11111111111" &
    "0000000000000000000000000000000000000000000000000000";
  
  -- +0
  CONSTANT DOUBLE_Zero  : uv64 :="0" & "00000000000" &
    "0000000000000000000000000000000000000000000000000000";

  --############################################################################
  TYPE type_decode IS RECORD
    unimp : std_logic;      -- UnImplemented
    fop   : uv4;            -- FOP
    sdi   : std_logic;      -- IN  : 0=Single 1=Double
    sdo   : std_logic;      -- OUT : 0=Single 1=Double
    cmp   : std_logic;      -- Instructions de comparaison
    bin   : std_logic;      -- Unaire/Binaire
  END RECORD;
  
  FUNCTION fpu_decode(CONSTANT op : uv32) RETURN type_decode;
  
END PACKAGE fpu_pack;
--------------------------------------------------------------------------------

PACKAGE BODY fpu_pack IS

  --############################################################################
  CONSTANT ZERO : uv64:=x"00000000_00000000";
  
  --------------------------------------
  -- Assemblage registre FSR
  FUNCTION rdfsr(CONSTANT fsr : type_fsr;
                 CONSTANT FPU_VER : unsigned(2 DOWNTO 0))
    RETURN unsigned IS
  BEGIN
    RETURN fsr.rd & "00" & fsr.tem & fsr.ns & "00" & FPU_VER &
      fsr.ftt & fsr.qne & '0' & fsr.fcc & fsr.aexc & fsr.cexc;
  END FUNCTION rdfsr;
  
  --------------------------------------
  -- Décomposition registre FSR
  PROCEDURE wrfsr(VARIABLE fsr : OUT type_fsr;
                   CONSTANT v   : IN  uv32) IS
  BEGIN
    fsr.rd   :=v(31 DOWNTO 30);
    fsr.tem  :=v(27 DOWNTO 23);
    fsr.ns   :=v(22);
    fsr.ftt  :=v(16 DOWNTO 14);
    fsr.qne  :=v(13);
    fsr.fcc  :=v(11 DOWNTO 10);
    fsr.aexc :=v(9 DOWNTO 5);
    fsr.cexc :=v(4 DOWNTO 0);
  END PROCEDURE wrfsr;
  
  --############################################################################
  
  --------------------------------------------------------------
  FUNCTION enc(CONSTANT a : unsigned(1 DOWNTO 0)) RETURN unsigned IS
  BEGIN
    CASE a IS
      WHEN "00" => RETURN "10";
      WHEN "01" => RETURN "01";
      WHEN "10" => RETURN "00";
      WHEN OTHERS => RETURN "00";
    END CASE;
  END FUNCTION enc;
  
  FUNCTION clzi(
    CONSTANT n : IN natural;
    CONSTANT i : IN unsigned) RETURN unsigned IS
    VARIABLE v : unsigned(i'length-1 DOWNTO 0):=i;  
  BEGIN
    IF v(n-1+n)='0' THEN
      RETURN (v(n-1+n) AND v(n-1)) & '0' & v(2*n-2 DOWNTO n);
    ELSE
      RETURN (v(n-1+n) AND v(n-1)) & NOT v(n-1) & v(n-2 DOWNTO 0);
    END IF;
  END FUNCTION clzi;
  
  --FUNCTION clz32 (CONSTANT v : unsigned(0 TO 31)) RETURN unsigned IS
  --  VARIABLE e : unsigned(0 TO 31);     -- 32
  --  VARIABLE a : unsigned(0 TO 8*3-1);  -- 24
  --  VARIABLE b : unsigned(0 TO 4*4-1);  -- 16
  --  VARIABLE c : unsigned(0 TO 2*5-1);  -- 10
  --BEGIN
  --  FOR i IN 0 TO 15 LOOP e(i*2 TO i*2+1):=enc(v(i*2 TO i*2+1));  END LOOP;
  --  FOR i IN 0 TO 7  LOOP a(i*3 TO i*3+2):=clzi(2,e(i*4 TO i*4+3)); END LOOP;
  --  FOR i IN 0 TO 3  LOOP b(i*4 TO i*4+3):=clzi(3,a(i*6 TO i*6+5)); END LOOP;
  --  FOR i IN 0 TO 1  LOOP c(i*5 TO i*5+4):=clzi(4,b(i*8 TO i*8+7)); END LOOP;
  --  RETURN clzi(5,c(0 TO 9));
  --END FUNCTION clz32;
    
  FUNCTION clz64 (CONSTANT v : unsigned(0 TO 63)) RETURN unsigned IS
    VARIABLE e : unsigned(0 TO 63);     -- 64
    VARIABLE a : unsigned(0 TO 16*3-1); -- 48
    VARIABLE b : unsigned(0 TO 8*4-1);  -- 32
    VARIABLE c : unsigned(0 TO 4*5-1);  -- 20
    VARIABLE d : unsigned(0 TO 2*6-1);  -- 12
  BEGIN
    FOR i IN 0 TO 31 LOOP e(i*2 TO i*2+1):=enc(v(i*2 TO i*2+1));  END LOOP;
    FOR i IN 0 TO 15 LOOP a(i*3 TO i*3+2):=clzi(2,e(i*4 TO i*4+3)); END LOOP;
    FOR i IN 0 TO 7  LOOP b(i*4 TO i*4+3):=clzi(3,a(i*6 TO i*6+5)); END LOOP;
    FOR i IN 0 TO 3  LOOP c(i*5 TO i*5+4):=clzi(4,b(i*8 TO i*8+7)); END LOOP;
    FOR i IN 0 TO 1  LOOP d(i*6 TO i*6+5):=clzi(5,c(i*10 TO i*10+9)); END LOOP;
    RETURN clzi(6,d(0 TO 11));
  END FUNCTION clz64;




  --------------------------------------------------------------
  FUNCTION clzx32(CONSTANT v : unsigned(0 TO 31)) RETURN unsigned IS
    VARIABLE a0,a1,a2,a3 : std_logic;
    VARIABLE mx : unsigned(0 TO 7);
    VARIABLE ah : unsigned(1 DOWNTO 0);
    VARIABLE al : unsigned(2 DOWNTO 0);
  BEGIN
    a0:=v_or(v(0 TO 7));
    a1:=v_or(v(8 TO 15));
    a2:=v_or(v(16 TO 23));
    a3:=v_or(v(24 TO 31));
    -----------------------
    IF    a0='1' THEN  ah:="00"; mx:=v(0 TO 7);
    ELSIF a1='1' THEN  ah:="01"; mx:=v(8 TO 15);
    ELSIF a2='1' THEN  ah:="10"; mx:=v(16 TO 23);
    ELSE               ah:="11"; mx:=v(24 TO 31);
    END IF;
    -----------------------
    IF    mx(0)='1' THEN al:="000";
    ELSIF mx(1)='1' THEN al:="001";
    ELSIF mx(2)='1' THEN al:="010";
    ELSIF mx(3)='1' THEN al:="011";
    ELSIF mx(4)='1' THEN al:="100";
    ELSIF mx(5)='1' THEN al:="101";
    ELSIF mx(6)='1' THEN al:="110";
    ELSIF mx(7)='1' THEN al:="111";
    END IF;           
    IF ah="11" AND a3='0' THEN
      RETURN "100000";
    ELSE
      RETURN '0' & ah & al;
    END IF;
  END FUNCTION clzx32;

  FUNCTION clzx64(CONSTANT v : unsigned(0 TO 63)) RETURN unsigned IS
    VARIABLE hi,lo : unsigned(5 DOWNTO 0);
  BEGIN
    hi:=clzx32(v(0 TO 31));
    lo:=clzx32(v(32 TO 63));
    IF hi(5)='1' AND lo(5)='1' THEN
      RETURN "10" & lo(4 DOWNTO 0);
    ELSIF hi(5)='1' THEN
      RETURN "01" & lo(4 DOWNTO 0);
    ELSE
      RETURN '0' & hi;
    END IF;
    
  END FUNCTION clzx64;
  
  --------------------------------------------------------------


  
  -- Comptage de Zéros à gauche
  FUNCTION clz(CONSTANT v : unsigned) RETURN natural IS
    VARIABLE vv : unsigned(0 TO 63);
  BEGIN
    vv:=x"FFFFFFFFFFFFFFFF";
    vv(0 TO v'length-1):=v;
    RETURN to_integer(clz64(vv));
    --RETURN to_integer(clzx64(vv));
  END FUNCTION clz;

  -- Comptage de Zéros à gauche (version itérative)
  FUNCTION clz_loop(CONSTANT v : unsigned) RETURN natural IS
    VARIABLE vv : unsigned(0 TO v'length-1) := v;
  BEGIN
    FOR I IN 0 TO vv'high LOOP
      IF vv(I)='1' THEN
        RETURN I;
      END IF;
    END LOOP;
    RETURN vv'length;
  END FUNCTION clz_loop;
  

  --------------------------------------------------------------
  -- Addition / Soustraction
  FUNCTION sub_add(
    CONSTANT a : unsigned;
    CONSTANT b : unsigned;
    CONSTANT s : std_logic)               -- 0 : A+B, 1 : A-B
    RETURN unsigned IS
    VARIABLE ta,tb,tc : unsigned(a'length DOWNTO 0);
  BEGIN
    tc:=(OTHERS => s);
    ta:=a & '1';
    tb:=(b & '0') XOR tc;
    ta:=ta+tb;
    RETURN ta(a'length DOWNTO 1);
  END FUNCTION sub_add;
  
  --------------------------------------------------------------  
  -- Conversion format
  FUNCTION conv_in(
    CONSTANT fs : uv64;
    CONSTANT sd : std_logic)
    RETURN unsigned IS
  BEGIN
    IF sd='0' THEN
      RETURN fs(63) & "000" & fs(62 DOWNTO 32) & ZERO(28 DOWNTO 0);
    ELSE
      RETURN fs;
    END IF;
  END FUNCTION conv_in;

  FUNCTION conv_out(
    CONSTANT fs : uv64;
    CONSTANT sd : std_logic)
    RETURN unsigned IS
    VARIABLE d : unsigned (63 DOWNTO 0);
  BEGIN
    d(63):=fs(63);
    IF sd='0' THEN
      d(62 DOWNTO 55):=fs(59 DOWNTO 52);
      d(54 DOWNTO 0):=fs(51 DOWNTO 29) & fs(31 DOWNTO 0);
    ELSE
      d(62 DOWNTO 52):=fs(62 DOWNTO 52);
      d(51 DOWNTO 0):=fs(51 DOWNTO 0);
    END IF;
    RETURN d;
  END conv_out;

  FUNCTION to01(CONSTANT a : std_logic)
    RETURN std_logic IS
  BEGIN
    IF a='1' THEN
      RETURN '1';
    ELSE
      RETURN '0';
    END IF;
  END to01;
  
  -- Classification de flottants
  FUNCTION class(
    CONSTANT fs : uv64;
    CONSTANT sd : std_logic) RETURN unsigned IS
    VARIABLE v : type_class;
  BEGIN
    v(4):=to01(fs(63));
    v(3):=mux(sd,to_std_logic(fs(62 DOWNTO 52)="11111111111"),
                 to_std_logic(fs(59 DOWNTO 52)="11111111"));
    v(2):=mux(sd,to_std_logic(fs(62 DOWNTO 52)="00000000000"),
                 to_std_logic(fs(59 DOWNTO 52)="00000000"));
    v(1):=to01(fs(51));
    v(0):=to01(v_or(fs(50 DOWNTO 0)));
    RETURN v;
  END FUNCTION class;
  
  -- Scalaire : -0---
  -- SNaN     : -1-01
  -- QNaN     : -1-11
  -- PInf     : 01-00
  -- MInf     : 11-00
  -- PZero    : 0-100
  -- MZero    : 1-100

  -- Prédicats
  FUNCTION is_nan(CONSTANT v : type_class) RETURN boolean IS
  BEGIN    RETURN (v(3) AND (v(0) OR v(1)))='1';  END;

  FUNCTION is_qnan(CONSTANT v : type_class) RETURN boolean IS
  BEGIN    RETURN (v(3) AND v(1))='1';  END;

  FUNCTION is_snan(CONSTANT v : type_class) RETURN boolean IS
  BEGIN    RETURN (v(3) AND NOT v(1) AND v(0))='1';  END;

  FUNCTION is_scal(CONSTANT v : type_class) RETURN boolean IS
  BEGIN    RETURN (NOT v(3))='1';  END;

  FUNCTION is_inf(CONSTANT v : type_class) RETURN boolean IS
  BEGIN    RETURN (v(3) AND NOT v(1) AND NOT v(0))='1';  END;

  FUNCTION is_pinf(CONSTANT v : type_class) RETURN boolean IS
  BEGIN    RETURN (NOT v(4) AND v(3) AND NOT v(1) AND NOT v(0))='1';  END;

  FUNCTION is_minf(CONSTANT v : type_class) RETURN boolean IS
  BEGIN    RETURN (v(4) AND v(3) AND NOT v(1) AND NOT v(0))='1';  END;

  FUNCTION is_zero(CONSTANT v : type_class) RETURN boolean IS
  BEGIN    RETURN v(2 DOWNTO 0)="100";  END;

  --############################################################################
  -- Zéros et infinis :
  -- - Vrai Zéro           : 0 * X     = 0
  -- - Zéro ou dénormalisé : eps * eps = 0
  -- - Vrai Infini         : Inf * X   = Inf
  -- - Infini ou max       : max * max = Inf
  
  -- Correction/détection zero et infinis
  PROCEDURE test_inf_zero(
    VARIABLE fs_man_o : OUT unsigned(54 DOWNTO 0);
    VARIABLE expo_o   : OUT unsigned(12 DOWNTO 0);
    VARIABLE ovf      : OUT std_logic;  -- Overflow
    CONSTANT fs_man   : IN unsigned(54 DOWNTO 0);
    CONSTANT expo     : IN unsigned(12 DOWNTO 0);    
    CONSTANT s        : IN std_logic;   -- Signe
    CONSTANT tz       : IN boolean;     -- Test Zero
    CONSTANT sd       : IN std_logic;   -- Simple/Double
    CONSTANT rd       : IN unsigned(1 DOWNTO 0)) IS  -- Rounding Direction
  BEGIN
    ovf:='0';
    fs_man_o:=fs_man;
    expo_o:=expo;
    
    IF (sd='0' AND (expo(8)='1'  OR expo(7 DOWNTO 0)="11111111")) OR
       (sd='1' AND (expo(11)='1' OR expo(10 DOWNTO 0)="11111111111")) THEN
      -- Positif, overflow
      ovf:='1';
      IF (s='0' AND (rd=RND_NEG OR rd=RND_ZERO)) OR
         (s='1' AND (rd=RND_POS OR rd=RND_ZERO)) THEN
        -- On interdit la génération d'un infini à partir de scalaires...
        fs_man_o(53 DOWNTO 0):=(OTHERS => '1');
        expo_o:="1111111111110";
      ELSE
        fs_man_o(53 DOWNTO 0):=(OTHERS => '0');
        expo_o:="1111111111111";
      END IF;
    ELSIF fs_man(54 DOWNTO 53)="00" THEN
      -- Résultat dénormalisé
      expo_o:="0000000000000";
      
      IF tz AND
        ((s='0' AND rd=RND_POS) OR (s='1' AND rd=RND_NEG)) AND
        ((sd='1' AND fs_man(52 DOWNTO 1) =ZERO(51 DOWNTO 0)) OR
         (sd='0' AND fs_man(52 DOWNTO 30)=ZERO(22 DOWNTO 0))) THEN
        -- On interdit la génération de zéro dans les modes +Inf et -Inf
        fs_man_o(1):='1';
        IF sd='0' THEN
          fs_man_o(30):='1';
        END IF;
      END IF;
    END IF;
    
  END PROCEDURE test_inf_zero;

 --############################################################################
  
  --Simple :
  --    63  62.............55 54..........32 31.................0
  --  [ S ] [    Exposant   ] [  Mantisse  ] [    xxxxxxxxx     ]

  -- Après conversion :
  --    63  62.....60 59........52 51..........29 28............0
  --  [ S ] [ 0 0 0 ] [ Exposant ] [  Mantisse  ] [    xxxxx    ]

  --Double :
  --    63  62..................52 51...........................0
  --  [ S ] [       Exposant     ] [           Mantisse         ]

  -- 66665555 55555544 44444444 33333333 33222222 22221111 11111100 00000000
  -- 32109876 54321098 76543210 98765432 10987654 32109876 54321098 76543210
  -- SIMPLE
  -- seeeeeee emmmmmmm mmmmmmmm mmmmmmmm
  -- DOUBLE
  -- seeeeeee eeeemmmm mmmmmmmm mmmmmmmm mmmmmmmm mmmmmmmm mmmmmmmm mmmmmmmm

  -- UNDERFLOW, aïe aïe aïe !
  ----------------------------
  -- Si UFM=0 : Untrapped Underflow
  --   On active le flag si :
  --  + Avant l'arrondi, le résultat V est 0 < V < plus_petit_nombre_normalisé
  -- ET Le résultat après l'arrondi est inexact

  -- Si UFM=1 : Trapped Underflow
  --   On active le flag si :
  --  + Avant l'arrondi, le résultat V est 0 < V < plus_petit_nombre_normalisé
  
  --############################################################################

  --UltraSparc Architecture 2005, Privilegied Mode, §.8.5.1
  --|-------|-------|-------|-------|-------|-------|-------|-------|-------|--
  --|       |  -Inf |  -N2  |  -0   |  +0   |  +N2  |  +Inf | QNaN2 | SNaN2 |RS2
  -----------------------------------------------------------------------------
  --|  -Inf |  RS1    RS1     RS1     RS1     RS1    QNaN,NV  RS2    RS2,NV |
  --|  -N1  |  RS2   <add>   <add>   <add>   <add>    RS2     RS2    RS2,NV |
  --|  -0   |  RS2   <add>   <add>   <add>   <add>    RS2     RS2    RS2,NV |
  --|  +0   |  RS2   <add>   <add>   <add>   <add>    RS2     RS2    RS2,NV |
  --|  +N1  |  RS2   <add>   <add>   <add>   <add>    RS2     RS2    RS2,NV |
  --|  +Inf | QNaN,NV RS1     RS1     RS1     RS1     RS2     RS2    RS2,NV |
  --| QNaN1 |  RS1    RS1     RS1     RS1     RS1     RS1     RS2    RS2,NV |
  --| SNaN1 | RS1,NV  RS1,NV  RS1,NV  RS1,NV  RS1,NV  RS1,NV  RS1,NV RS2,NV |
  ---------------------------------------------------------------------------
  --|  RS1  |
  --            Les SNaN doivent être transformés en QNaN
    
  --UltraSparc Architecture 2005, Privilegied Mode, §.8.5.6
  --|-------|-------|-------|-------|-------|-------|-------|-------|-------|--
  --|       |  -Inf |  -N2  |  -0   |  + 0  |  +N2  |  +Inf | QNaN2 | SNaN2 |RS2
  -----------------------------------------------------------------------------
  --|  -Inf |   0      1       1       1       1      1      3,nv     3,NV  |
  --|  -N1  |   2    <cmp>   <cmp>   <cmp>   <cmp>    1      3,nv     3,NV  |
  --|  -0   |   2    <cmp>   <cmp>   <cmp>   <cmp>    1      3,nv     3,NV  |
  --|  +0   |   2    <cmp>   <cmp>   <cmp>   <cmp>    1      3,nv     3,NV  |
  --|  +N1  |   2    <cmp>   <cmp>   <cmp>   <cmp>    1      3,nv     3,NV  |
  --|  +Inf |   2      2       2       2       2      0      3,nv     3,NV  |
  --| QNaN1 | 3,nv   3,nv    3,nv    3,nv    3,nv    3,nv    3,nv     3,NV  |
  --| SNaN1 | 3,NV   3,NV    3,NV    3,NV    3,NV    3,NV    3,nv     3,NV  |
  ---------------------------------------------------------------------------
  --|  RS1  |
  --  0 : =         1 : <         2 : >         3 : Unordered
  
  -- FADDs  : OF,UF,NX,NV (+Inf-Inf)
  -- FADDd  : OF,UF,NX,NV (+Inf-Inf)
  -- FSUBs  : OF,UF,NX,NV (+Inf-Inf)
  -- FSUBd  : OF,UF,NX,NV (+Inf-Inf)
  -- FCMPs  : NV si SNaN
  -- FCMPd  : NV si SNaN
  -- FCMPEs : NV si SNaN ou QNaN
  -- FCMPEd : NV si SNaN ou QNaN
  -- FsTOi : NV,NX
  -- FdTOi : NV,NX
  -- FiTOs : NX
  -- FiTOd : 0
   
  PROCEDURE asc_mds_1(
    VARIABLE fs1_man   : OUT unsigned(51 DOWNTO 0);
    VARIABLE fs2_man   : OUT unsigned(51 DOWNTO 0);
    VARIABLE fs1_class : OUT type_class;
    VARIABLE fs2_class : OUT type_class;
    VARIABLE fs1_exp   : OUT unsigned(10 DOWNTO 0);
    VARIABLE fs2_exp   : OUT unsigned(10 DOWNTO 0);
    VARIABLE fs2_exp0  : OUT std_logic;
    CONSTANT fs1       : IN  uv64;
    CONSTANT fs2       : IN  uv64;
    CONSTANT fop       : IN  uv4;
    CONSTANT sd        : IN  std_logic) IS              -- 0=single 1=double
    VARIABLE fs1_t,fs2_t : uv64;
    VARIABLE fs1_class_t,fs2_class_t : type_class;
  BEGIN
    -- Initialisation, conversion
    fs1_t:=conv_in(fs1,sd);
    fs1_man:=fs1_t(51 DOWNTO 0);
    fs1_exp:=fs1_t(62 DOWNTO 52);
    
    fs1_class_t:=class(fs1_t,sd);
    fs1_class:=fs1_class_t;
    IF fs1_class_t(2)='1' THEN -- Si dénorm. EXP=1
      fs1_exp(0):='1';
    END IF;
    
    fs2_t:=conv_in(fs2,sd);
    IF fop=FOP_SUB OR fop=FOP_CMP OR fop=FOP_CMPE OR fop=FOP_NEG THEN
      fs2_t(63):=NOT fs2(63);
    ELSIF fop=FOP_ABS THEN
      fs2_t(63):='0';
    ELSE
      fs2_t(63):=fs2(63);
    END IF;
    fs2_man:=fs2_t(51 DOWNTO 0);
    fs2_exp:=fs2_t(62 DOWNTO 52);
    
    fs2_class_t:=class(fs2_t,sd);
    fs2_class:=fs2_class_t;
    fs2_exp0:=fs2_t(52); -- On garde la valeur d'origine pour iTOf
    IF fs2_class_t(2)='1' THEN -- Si dénorm. EXP=1
      fs2_exp(0):='1';
    END IF;
    
  END PROCEDURE asc_mds_1;
  
  PROCEDURE asc_2(
    VARIABLE fhi_man   : OUT unsigned(55 DOWNTO 0);
    VARIABLE flo_man   : OUT unsigned(55 DOWNTO 0);
    VARIABLE fhi_s     : OUT std_logic;
    VARIABLE flo_s     : OUT std_logic;
    VARIABLE expo      : OUT unsigned(10 DOWNTO 0);
    VARIABLE diff      : OUT unsigned(12 DOWNTO 0);
    CONSTANT fs1_iman  : IN  unsigned(51 DOWNTO 0);
    CONSTANT fs2_iman  : IN  unsigned(51 DOWNTO 0);
    CONSTANT fs1_class : IN  type_class;
    CONSTANT fs2_class : IN  type_class;
    CONSTANT fs1_exp   : IN  unsigned(10 DOWNTO 0);
    CONSTANT fs2_exp   : IN  unsigned(10 DOWNTO 0);
    CONSTANT fs2_exp0  : IN  std_logic;
    CONSTANT fop       : IN  uv4;
    CONSTANT sd        : IN  std_logic;
    CONSTANT sdo       : IN  std_logic) IS              -- 0=single 1=double
    VARIABLE fhi_man_v,flo_man_v : unsigned(55 DOWNTO 0);
    VARIABLE fhi_v,flo_v : unsigned(51 DOWNTO 0);
    VARIABLE fhi_class,flo_class : type_class;
    VARIABLE diff_v,diff2_v : unsigned(12 DOWNTO 0);
  BEGIN
    -- Recherche du plus grand exposant
    IF fop=FOP_fTOi THEN      -- FsTOi, FdTOi
      fhi_v:=ZERO(51 DOWNTO 0);
      fhi_s:='0';
      fhi_class:="00100";
      flo_v:=fs2_iman;
      flo_s:=fs2_class(4);
      flo_class:=fs2_class;
      expo:=fs1_exp;
      IF sd='0' THEN
        diff_v:="0000010011110" - fs2_exp; --  128 + 30 - exp
      ELSE
        diff_v:="0010000011110" - fs2_exp; -- 1024 + 30 - exp
      END IF;
    ELSIF fop=FOP_iTOf THEN   -- FiTOs, FiTOd
      fhi_v:=ZERO(51 DOWNTO 0);
      fhi_s:='0';
      fhi_class:="00" & NOT fs2_class(4) & "00";
      -- <AVOIR> Utile ?? pourquoi pas 00000 ?
      flo_v:=fs2_class(4) & fs2_exp(7 DOWNTO 1) & fs2_exp0 &
             fs2_iman(51 DOWNTO 29) & ZERO(19 DOWNTO 0);
      flo_s:=fs2_class(4);
      flo_class:="00100";
      IF sdo='0' THEN
        expo:="00010011111"; --  128 + 31
      ELSE
        expo:="10000011111"; -- 1024 + 31
      END IF;
      diff_v:="0000000000000";
    ELSIF fs1_exp>=fs2_exp THEN
      fhi_v:=fs1_iman;
      fhi_s:=fs1_class(4);
      fhi_class:=fs1_class;
      flo_v:=fs2_iman;
      flo_s:=fs2_class(4);
      flo_class:=fs2_class;
      expo:=fs1_exp;
      diff_v:="00" & (fs1_exp-fs2_exp);
    ELSE
      fhi_v:=fs2_iman;
      fhi_s:=fs2_class(4);
      fhi_class:=fs2_class;
      flo_v:=fs1_iman;
      flo_s:=fs1_class(4);
      flo_class:=fs1_class;
      expo:=fs2_exp;
      diff_v:="00" & (fs2_exp-fs1_exp);
    END IF;
    
    -- Renormalisation mantisse, extension G / R / S
    fhi_man_v:=NOT fhi_class(2) & fhi_v & "000";
    flo_man_v:=NOT flo_class(2) & flo_v & "000";

    diff2_v:=diff_v;
    -- Décalage mantisse du plus petit, avec sticky bit
    IF v_or(diff_v(11 DOWNTO 6))='1' THEN
      diff2_v(5 DOWNTO 3):="111";
--      flo_man_v:=ZERO(54 DOWNTO 0) & v_or(flo_man_v);
    END IF;
    
    IF diff2_v(5)='1' THEN
      flo_man_v:=ZERO(31 DOWNTO 0) & flo_man_v(55 DOWNTO 33) &
                  v_or(flo_man_v(32 DOWNTO 0));
    END IF;
    IF diff2_v(4)='1' THEN
      flo_man_v:=x"0000" & flo_man_v(55 DOWNTO 17) &
                  v_or(flo_man_v(16 DOWNTO 0));
    END IF;
    IF diff2_v(3)='1' THEN
      flo_man_v:=x"00" & flo_man_v(55 DOWNTO 9) & v_or(flo_man_v(8 DOWNTO 0));
    END IF;
    IF diff2_v(2)='1' THEN
      flo_man_v:="0000" & flo_man_v(55 DOWNTO 5) & v_or(flo_man_v(4 DOWNTO 0));
    END IF;
    IF diff2_v(1)='1' THEN
      flo_man_v:="00" & flo_man_v(55 DOWNTO 3) & v_or(flo_man_v(2 DOWNTO 0));
    END IF;
    IF diff2_v(0)='1' THEN
      flo_man_v:='0' & flo_man_v(55 DOWNTO 2) & v_or(flo_man_v(1 DOWNTO 0));
    END IF;

    fhi_man:=fhi_man_v;
    flo_man:=flo_man_v;
    diff:=diff_v;
    
  END PROCEDURE asc_2;

  PROCEDURE asc_3(
    VARIABLE addsub   : OUT unsigned(56 DOWNTO 0);
    VARIABLE nz       : OUT natural RANGE 0 TO 63;    
    VARIABLE fo_s     : OUT std_logic;
    VARIABLE nxf      : OUT std_logic;
    VARIABLE nvf      : OUT std_logic;
    CONSTANT diff     : IN  unsigned(12 DOWNTO 0);    
    CONSTANT fhi_man  : IN  unsigned(55 DOWNTO 0);
    CONSTANT flo_man  : IN  unsigned(55 DOWNTO 0);
    CONSTANT fhi_s    : IN  std_logic;
    CONSTANT flo_s    : IN  std_logic;
    CONSTANT fop      : IN  uv4) IS
    VARIABLE addsub_p,addsub_n,addsub_o : unsigned(56 DOWNTO 0);
    VARIABLE flo_man_v : unsigned(55 DOWNTO 0);
    VARIABLE addsubx  : unsigned(57 DOWNTO 0);
    VARIABLE neg : std_logic;
  BEGIN
    flo_man_v:=flo_man;
    IF fop=FOP_fTOi THEN      -- FsTOi, FdTOi
      flo_man_v(23 DOWNTO 0):=ZERO(23 DOWNTO 0);
    END IF;

    -- Addition/Soustraction
    IF fhi_s=flo_s THEN
      addsub_p:=('0' & fhi_man(55 DOWNTO 0)) + ('0' & flo_man_v(55 DOWNTO 0));
    ELSE
      addsub_p:=('0' & fhi_man(55 DOWNTO 0)) - ('0' & flo_man_v(55 DOWNTO 0));
    END IF;
    addsub_n:= ('0' & flo_man_v(55 DOWNTO 0)) - ('0' & fhi_man(55 DOWNTO 0));
    
    nvf:='0';
    nxf:='0';

    IF fop=FOP_iTOf THEN
      addsub_o:=addsub_p;
      fo_s:=flo_s;
    ELSIF fop=FOP_fTOi THEN
      addsub_o:=addsub_p;
      fo_s:=flo_s;
      addsub_o(56):='1'; -- Force CLZ=0
      -- FsTOi, FdTOi
      IF diff="0000000000000" AND flo_s='1' THEN
        -- Cas de 0x80000000 : Ecrêtage, déclencher un NV si /=0
        addsub_o(55 DOWNTO 24):=x"8000_0000";
        nvf:=v_or(flo_man_v(54 DOWNTO 24));
        nxf:='0';
      ELSIF diff(12)='1' AND flo_s='1' THEN
        -- Overflow neg
        addsub_o(55 DOWNTO 24):=x"8000_0000";
        nvf:='1';
        nxf:='0';
      ELSIF (diff(12)='1' OR diff="0000000000000") AND flo_s='0' THEN
        -- Overflow pos
        addsub_o(55 DOWNTO 24):=x"7FFF_FFFF";
        nvf:='1';
        nxf:='0';
      ELSE
        nvf:='0';
        nxf:=v_or(flo_man(23 DOWNTO 0));
      END IF;
    ELSIF addsub_p(56)='1' AND fhi_s/=flo_s THEN
      addsub_o:=addsub_n;
      fo_s:=flo_s;
    ELSE
      addsub_o:=addsub_p;
      fo_s:=fhi_s;
    END IF;
    
    addsub:=addsub_o;
    nz:=clz(addsub_o(56 DOWNTO 2));
    
  END PROCEDURE asc_3;

  PROCEDURE asc_4(
    VARIABLE fs_man_o : OUT unsigned(53 DOWNTO 0);
    VARIABLE fcc      : OUT unsigned(1 DOWNTO 0);
    VARIABLE nxf_o    : OUT std_logic;
    VARIABLE sticky   : OUT std_logic;
    VARIABLE expo_o   : OUT unsigned(10 DOWNTO 0);
    VARIABLE fo_s_o   : OUT std_logic;
    CONSTANT expo     : IN  unsigned(10 DOWNTO 0);
    CONSTANT nz       : IN  natural RANGE 0 TO 63;
    CONSTANT addsub   : IN  unsigned(56 DOWNTO 0);
    CONSTANT fo_s     : IN  std_logic;
    CONSTANT nxf      : IN  std_logic;
    CONSTANT fhi_s    : IN  std_logic;
    CONSTANT flo_s    : IN  std_logic;
    CONSTANT fop      : IN  uv4;
    CONSTANT sd       : IN  std_logic;              -- 0=single 1=double
    CONSTANT rd       : IN  unsigned(1 DOWNTO 0)) IS   -- Round Direction    
    VARIABLE addsub_v : unsigned(56 DOWNTO 0);
    VARIABLE deca_v : unsigned(5 DOWNTO 0);
    VARIABLE expo2_v : unsigned(11 DOWNTO 0);
  BEGIN
    addsub_v:=addsub;
    IF ((nz>=26 AND sd='0') OR nz=55) AND fop/=FOP_iTOf THEN
      -- Zéro de chez zéro
      IF rd=RND_NEG AND (fhi_s='1' OR flo_s='1') THEN
        fo_s_o:='1';
      ELSE
        fo_s_o:=fhi_s AND flo_s;
      END IF;
      fcc:="00";
    ELSE
      fo_s_o:=fo_s;
      fcc:=NOT fo_s & fo_s;
    END IF;
    
    deca_v:=to_unsigned(nz,6);
    expo2_v:=('0' & expo) - deca_v;
    IF expo2_v(11)='1' THEN
      deca_v:=expo(5 DOWNTO 0);
      expo_o:="00000000000";
    ELSE
      expo_o:=expo2_v(10 DOWNTO 0)+1;
    END IF;
    
    addsub_v:=unsigned(shift_left(unsigned(addsub_v),to_integer(deca_v)));
    --IF deca_v(5)='1' THEN
    --  addsub_v:=addsub_v(56-32 DOWNTO 0) & x"0000_0000";
    --END IF;
    --IF deca_v(4)='1' THEN
    --  addsub_v:=addsub_v(56-16 DOWNTO 0) & x"0000";
    --END IF;
    --IF deca_v(3)='1' THEN
    --  addsub_v:=addsub_v(56-8 DOWNTO 0) & x"00";
    --END IF;
    --IF deca_v(2)='1' THEN
    --  addsub_v:=addsub_v(56-4 DOWNTO 0) & x"0";
    --END IF;
    --IF deca_v(1)='1' THEN
    --  addsub_v:=addsub_v(56-2 DOWNTO 0) & "00";
    --END IF;
    --IF deca_v(0)='1' THEN
    --  addsub_v:=addsub_v(56-1 DOWNTO 0) & '0';
    --END IF;
    
    -- <AFAIRE> Calcul Underflow !
    addsub_v(2):=addsub_v(2) OR addsub_v(1) OR addsub_v(0);
    
    IF sd='0' THEN
      addsub_v(2):=addsub_v(2) OR v_or(addsub_v(31 DOWNTO 3));
    END IF;
    
    IF fop/=FOP_fTOi THEN
      IF sd='1' THEN
        nxf_o:=addsub_v(2) OR addsub_v(3);
      ELSE
        nxf_o:=addsub_v(2) OR addsub_v(32);
      END IF;
    ELSE
      nxf_o:=nxf;
    END IF;
    
    fs_man_o:=addsub_v(56 DOWNTO 3);
    sticky:=addsub_v(2);
    
  END PROCEDURE asc_4;
   
  --############################################################################

  --UltraSparc Architecture 2005, Privilegied Mode, §.8.5.3
  --|-------|-------|-------|-------|-------|-------|-------|-------|-------|--
  --|       |  -Inf |  -N2  |  -0   |  +0   |  +N2  |  +Inf | QNaN2 | SNaN2 |RS2
  -----------------------------------------------------------------------------
  --|  -Inf |  +Inf   +Inf   QNaN,NV QNaN,NV  -Inf     -Inf    RS2   RS2,NV |
  --|  -N1  |  +Inf   <mul>    +0      -0     <mul>    -Inf    RS2   RS2,NV |
  --|  -0   | QNaN,NV +0       +0      -0     -0     QNaN,NV   RS2   RS2,NV |
  --|  +0   | QNaN,NV -0       -0      +0     +0     QNaN,NV   RS2   RS2,NV |
  --|  +N1  |  -Inf   <mul>    -0      +0     <mul>    +Inf    RS2   RS2,NV |
  --|  +Inf |  -Inf   -Inf   QNaN,NV QNaN,NV  +Inf     +Inf    RS2   RS2,NV |
  --| QNaN1 |   RS1    RS1    RS1     RS1      RS1     RS1     RS2   RS2,NV |
  --| SNaN1 | RS1,NV  RS1,NV  RS1,NV  RS1,NV  RS1,NV  RS1,NV  RS1,NV RS2,NV |
  ---------------------------------------------------------------------------
  --|  RS1  |
  
  --UltraSparc Architecture 2005, Privilegied Mode, §.8.5.4
  --|-------|-------|-------|-------|-------|-------|-------|-------|-------|--
  --|       |  -Inf |  -N2  |  -0   |  + 0  |  +N2  |  +Inf | QNaN2 | SNaN2 |RS2
  -----------------------------------------------------------------------------
  --|  -Inf | QNaN,NV +Inf    +Inf    -Inf    -Inf   QNaN,NV   RS2   RS2,NV |
  --|  -N1  |  +0     <div>  +Inf,DZ -Inf,DZ  <div>    -0      RS2   RS2,NV |
  --|  -0   |  +0      +0    QNaN,NV QNaN,NV   -0      -0      RS2   RS2,NV |
  --|  +0   |  -0      -0    QNaN,NV QNaN,NV   +0      +0      RS2   RS2,NV |
  --|  +N1  |  -0     <div>  -Inf,DZ +Inf,DZ  <div>    +0      RS2   RS2,NV |
  --|  +Inf | QNaN,NV -Inf    -Inf     +Inf   +Inf   QNaN,NV   RS2   RS2,NV |
  --| QNaN1 |   RS1    RS1    RS1     RS1      RS1     RS1     RS2   RS2,NV |
  --| SNaN1 | RS1,NV  RS1,NV  RS1,NV  RS1,NV  RS1,NV  RS1,NV  RS1,NV RS2,NV |
  ---------------------------------------------------------------------------
  --|  RS1  |

  --UltraSparc Architecture 2005, Privilegied Mode, §.8.5.5
  --|-------|-------|-------|-------|-------|-------|-------|-------|-------|--
  --|       |  -Inf |  -N2  |  -0   |  +0   |  +N2  |  +Inf | QNaN  | SNaN  |RS
  -----------------------------------------------------------------------------
  --|       |QNaN,NV QNaN,NV   -0      +0     <sqrt>   +Inf   QNaN   QNaN,NV|
  ---------------------------------------------------------------------------

  --            Les SNaN doivent être transformés en QNaN
  -- FsTOd : NV si SNaN
  -- FdTOs : OF,UF,NX,NV si SNaN
  -- FMULs : OF,UF,NV,NX
  -- FMULd : OF,UF,NV,NX
  -- FDIVs : OF,UF,DZ,NV,NX
  -- FDIVd : OF,UF,DZ,NV,NX
  -- FSQRTs : NV,NX
  -- FSQRTd : NV,NX

  PROCEDURE mds_2(
    VARIABLE fs1_man   : OUT unsigned(53 DOWNTO 0);
    VARIABLE fs2_man   : OUT unsigned(52 DOWNTO 0);
    VARIABLE expo      : OUT unsigned(12 DOWNTO 0);
    CONSTANT fs1_iman  : IN  unsigned(51 DOWNTO 0);
    CONSTANT fs2_iman  : IN  unsigned(51 DOWNTO 0);
    CONSTANT fs1_class : IN  type_class;
    CONSTANT fs2_class : IN  type_class;
    CONSTANT fs1_exp   : IN  unsigned(10 DOWNTO 0);
    CONSTANT fs2_exp   : IN  unsigned(10 DOWNTO 0);
    CONSTANT fop       : IN  uv4;
    CONSTANT sd        : IN  std_logic) IS          -- 0=FDIVs 1=FDIVd
    VARIABLE expo_v : unsigned(12 DOWNTO 0);
    VARIABLE fs1_man_v : unsigned(52 DOWNTO 0);
    VARIABLE fs2_man_v : unsigned(52 DOWNTO 0);
    VARIABLE fs1_deca_v,fs2_deca_v : unsigned(12 DOWNTO 0);    
  BEGIN
    -- Extraction, rajout 0 ou 1 en tête de la mantisse --> 23bit
    IF fop=FOP_MUL THEN
      fs1_man_v:=NOT fs1_class(2) & fs1_iman;
      fs2_man_v:=NOT fs2_class(2) & fs2_iman;
      expo_v:=("00" & fs1_exp) + ("00" & fs2_exp);
    ELSIF fop=FOP_DIV THEN
      fs1_man_v:=NOT fs1_class(2) & fs1_iman;
      fs2_man_v:=NOT fs2_class(2) & fs2_iman;
      expo_v:=("00" & fs1_exp) - ("00" & fs2_exp);
    ELSE
      fs1_man_v:=NOT fs2_class(2) & fs2_iman;
      fs2_man_v:='1' & fs2_iman;
      expo_v:="00" & fs2_exp;
    END IF;
    
    -- Décale << jusqu'à ce que le MSB = 1, traitement dénormalisés
    fs1_deca_v:=to_unsigned(clz(fs1_man_v),13);
    fs2_deca_v:=to_unsigned(clz(fs2_man_v),13);
    
    IF 1=1 THEN
      fs1_man_v:=shift_left(fs1_man_v,to_integer(fs1_deca_v));
      fs2_man_v:=shift_left(fs2_man_v,to_integer(fs2_deca_v));
    END IF;

    IF 0=1 THEN
      IF fs1_man_v(52 DOWNTO 21)=x"0000_0000" THEN
        fs1_man_v:=fs1_man_v(20 DOWNTO 0) & x"0000_0000";
      END IF;
      IF fs1_man_v(52 DOWNTO 37)=x"0000" THEN
        fs1_man_v:=fs1_man_v(36 DOWNTO 0) & x"0000";
      END IF;
      IF fs1_man_v(52 DOWNTO 45)=x"00" THEN
        fs1_man_v:=fs1_man_v(44 DOWNTO 0) & x"00";
      END IF;
      IF fs1_man_v(52 DOWNTO 49)="0000" THEN
        fs1_man_v:=fs1_man_v(48 DOWNTO 0) & "0000";
      END IF;
      IF fs1_man_v(52 DOWNTO 51)="00" THEN
        fs1_man_v:=fs1_man_v(50 DOWNTO 0) & "00";
      END IF;
      IF fs1_man_v(52)='0' THEN
        fs1_man_v:=fs1_man_v(51 DOWNTO 0) & '0';
      END IF;

      -- <AVOIR> Encodage direct décalages avec détection de zéros
      IF fs2_man_v(52 DOWNTO 21)=x"0000_0000" THEN
        fs2_man_v:=fs2_man_v(20 DOWNTO 0) & x"0000_0000";
      END IF;
      IF fs2_man_v(52 DOWNTO 37)=x"0000" THEN
        fs2_man_v:=fs2_man_v(36 DOWNTO 0) & x"0000";
      END IF;
      IF fs2_man_v(52 DOWNTO 45)=x"00" THEN
        fs2_man_v:=fs2_man_v(44 DOWNTO 0) & x"00";
      END IF;
      IF fs2_man_v(52 DOWNTO 49)="0000" THEN
        fs2_man_v:=fs2_man_v(48 DOWNTO 0) & "0000";
      END IF;
      IF fs2_man_v(52 DOWNTO 51)="00" THEN
        fs2_man_v:=fs2_man_v(50 DOWNTO 0) & "00";
      END IF;
      IF fs2_man_v(52)='0' THEN
        fs2_man_v:=fs2_man_v(51 DOWNTO 0) & '0';
      END IF;
    END IF;
 
    expo_v:=expo_v - fs1_deca_v;
    IF fop=FOP_MUL THEN
      expo_v:=expo_v - fs2_deca_v;
    ELSE
      expo_v:=expo_v + fs2_deca_v;
    END IF;
    expo:=expo_v;
    
    fs1_man:=fs1_man_v & '0';
    fs2_man:=fs2_man_v;
  END PROCEDURE mds_2;

  PROCEDURE mds_2_unf(
    VARIABLE fs1_man   : OUT unsigned(53 DOWNTO 0);
    VARIABLE fs2_man   : OUT unsigned(52 DOWNTO 0);
    VARIABLE expo      : OUT unsigned(12 DOWNTO 0);
    VARIABLE unf       : OUT std_logic;
    CONSTANT fs1_iman  : IN  unsigned(51 DOWNTO 0);
    CONSTANT fs2_iman  : IN  unsigned(51 DOWNTO 0);
    CONSTANT fs1_class : IN  type_class;
    CONSTANT fs2_class : IN  type_class;
    CONSTANT fs1_exp   : IN  unsigned(10 DOWNTO 0);
    CONSTANT fs2_exp   : IN  unsigned(10 DOWNTO 0);
    CONSTANT fop       : IN  uv4;
    CONSTANT sd        : IN  std_logic) IS          -- 0=FDIVs 1=FDIVd
    VARIABLE expo_v : unsigned(12 DOWNTO 0);
    VARIABLE fs1_man_v : unsigned(52 DOWNTO 0);
    VARIABLE fs2_man_v : unsigned(52 DOWNTO 0);
  BEGIN
    -- Extraction, rajout 0 ou 1 en tête de la mantisse --> 23bit
    IF fop=FOP_MUL THEN
      fs1_man_v:=NOT fs1_class(2) & fs1_iman;
      fs2_man_v:=NOT fs2_class(2) & fs2_iman;
      expo_v:=("00" & fs1_exp) + ("00" & fs2_exp);
    ELSIF fop=FOP_DIV THEN
      fs1_man_v:=NOT fs1_class(2) & fs1_iman;
      fs2_man_v:=NOT fs2_class(2) & fs2_iman;
      expo_v:=("00" & fs1_exp) - ("00" & fs2_exp);
    ELSE
      fs1_man_v:=NOT fs2_class(2) & fs2_iman;
      fs2_man_v:='1' & fs2_iman;
      expo_v:="00" & fs2_exp;
    END IF;

    unf:=to_std_logic(
      (fs1_man_v(52)='0' AND NOT is_zero(fs1_class)
       AND (fop=FOP_MUL OR fop=FOP_DIV)) OR
      (fs2_man_v(52)='0' AND NOT is_zero(fs2_class)));
    
    expo:=expo_v;
    fs1_man:=fs1_man_v & '0';
    fs2_man:=fs2_man_v;
  END PROCEDURE mds_2_unf;
  
  PROCEDURE mds_3(
    VARIABLE fs1_man_o : OUT unsigned(53 DOWNTO 0);
    VARIABLE expo_o    : OUT unsigned(12 DOWNTO 0);
    CONSTANT fs1_man   : IN  unsigned(53 DOWNTO 0);
    CONSTANT expo      : IN  unsigned(12 DOWNTO 0);
    CONSTANT fop       : IN  uv4;
    CONSTANT sd        : IN  std_logic;           -- 0=FDIVs 1=FDIVd
    CONSTANT sdo       : IN  std_logic) IS        -- 0=FMULs 1=FMULd/FsMULd
    VARIABLE modu : unsigned(12 DOWNTO 0);
  BEGIN
    fs1_man_o:=fs1_man;
    
    -- Correction exposant
    IF fop=FOP_DIV THEN
      IF sd='1' THEN      -- FDIVd
        modu:="0001111111111";   -- 1023
      ELSE                            -- FDIVs
        modu:="0000001111111";   -- 127
      END IF;
      expo_o:=expo+modu;
      fs1_man_o:='0' & fs1_man(53 DOWNTO 1);
      
    ELSIF fop=FOP_MUL THEN
      IF sd='0' AND sdo='0' THEN      -- FMULs
        modu:="1111110000010";   -- 8066 = 8192-127 +1
      ELSIF sd='0' AND sdo='1' THEN   -- FsMULd
        modu:="0001100000010";   -- 770 = 1023-127-127 +1
      ELSE                            -- FMULd
        modu:="1110000000010";   -- 7170 = 8192-1023 +1
      END IF;
      expo_o:=expo+modu;
      
    ELSIF fop=FOP_SQRT THEN
      IF expo(0)='1' THEN
        IF sd='1' THEN
          modu:="0001000000000";
        ELSE
          modu:="0000001000000";
        END IF;
        fs1_man_o:='0' & fs1_man(53 DOWNTO 1);
      ELSE
        IF sd='1' THEN
          modu:="0000111111111";
        ELSE
          modu:="0000000111111";
        END IF;
      END IF;
      
      expo_o:=(expo(12) & expo(12 DOWNTO 1))+modu;
      
    ELSE -- fop=FOP_fTOf
      IF sd='1' THEN
        -- Double --> Simple
        IF expo>"0010001111110" THEN --1150 : Overflow
          expo_o:="0100000000000";
          fs1_man_o:=(OTHERS => '0');
        ELSIF expo<="0001101101000" THEN --872 : Underflow
          expo_o:="0000000000001";
          fs1_man_o:=(OTHERS => '0');
        ELSE
          expo_o:=expo + "1110010000001"; -- 7297 = 8192-1023+127 + 1
        END IF;
      ELSE
        -- Simple --> Double
        expo_o:=expo + "0001110000001";  -- 897 = 1023-127+1
      END IF;
    END IF;

  END PROCEDURE mds_3;
  
  PROCEDURE mds_4(
    VARIABLE fs_man_o : OUT unsigned(53 DOWNTO 0);
    VARIABLE expo_o   : OUT unsigned(12 DOWNTO 0);
    VARIABLE sticky_o : OUT std_logic;
    VARIABLE udf_o    : OUT std_logic;
    VARIABLE nxf_o    : OUT std_logic;
    CONSTANT fs_man : IN unsigned(53 DOWNTO 0);
    CONSTANT expo   : IN unsigned(12 DOWNTO 0);
    CONSTANT sticky : IN std_logic;
    CONSTANT sdo    : IN std_logic;
    CONSTANT ufm    : IN std_logic) IS
    VARIABLE sticky_v,sticky_t : std_logic;
    VARIABLE fs_man_v : unsigned(53 DOWNTO 0);
    VARIABLE udf_v,nxf_v : std_logic;
    VARIABLE expo_v,emod : unsigned(12 DOWNTO 0);
  BEGIN
    sticky_v:=sticky;
    fs_man_v:=fs_man;
    expo_v:=expo;
    
    IF expo_v(12)='1' OR expo_v=ZERO(12 DOWNTO 0) THEN
      -- Si l'exposant est négatif, on génère un dénormalisé, décalage >>
      -- (cela n'arrive jamais avec SQRT...)
      emod:=expo_v-2;

      IF emod(11 DOWNTO 6)/="111111" THEN
        sticky_v:=sticky_v OR v_or(fs_man_v(53 DOWNTO 0));
        fs_man_v:=ZERO(53 DOWNTO 0);
      END IF;
      
      IF emod(5)='0' THEN
        sticky_v:=sticky_v OR v_or(fs_man_v(31 DOWNTO 0));
        fs_man_v:=x"00000000" & fs_man_v(53 DOWNTO 32);
      END IF;

      IF emod(4)='0' THEN
        sticky_v:=sticky_v OR v_or(fs_man_v(15 DOWNTO 0));
        fs_man_v:=x"0000" & fs_man_v(53 DOWNTO 16);
      END IF;

      CASE emod(3 DOWNTO 2) IS
        WHEN "10" =>
          sticky_v:=sticky_v OR v_or(fs_man_v(3 DOWNTO 0));
          fs_man_v:="0000" & fs_man_v(53 DOWNTO 4);
        WHEN "01" =>
          sticky_v:=sticky_v OR v_or(fs_man_v(7 DOWNTO 0));
          fs_man_v:="00000000" & fs_man_v(53 DOWNTO 8);          
        WHEN "00" =>
          sticky_v:=sticky_v OR v_or(fs_man_v(11 DOWNTO 0));
          fs_man_v:="000000000000" & fs_man_v(53 DOWNTO 12);
        WHEN OTHERS =>
          NULL;
      END CASE;
        
      --IF emod(3)='0' THEN
      --  sticky_v:=sticky_v OR v_or(fs_man_v(7 DOWNTO 0));
      --  fs_man_v:="00000000" & fs_man_v(53 DOWNTO 8);
      --END IF;

      --IF emod(2)='0' THEN
      --  sticky_v:=sticky_v OR v_or(fs_man_v(3 DOWNTO 0));
      --  fs_man_v:="0000" & fs_man_v(53 DOWNTO 4);
      --END IF;
      
      CASE emod(1 DOWNTO 0) IS
        WHEN "10" =>
          sticky_v:=sticky_v OR fs_man_v(0);
          fs_man_v:='0' & fs_man_v(53 DOWNTO 1);
        WHEN "01" =>
          sticky_v:=sticky_v OR v_or(fs_man_v(1 DOWNTO 0));
          fs_man_v:="00" & fs_man_v(53 DOWNTO 2);
        WHEN "00" =>
          sticky_v:=sticky_v OR v_or(fs_man_v(2 DOWNTO 0));
          fs_man_v:="000" & fs_man_v(53 DOWNTO 3);
        WHEN OTHERS =>
          NULL;
      END CASE;
      
      --IF emod(1)='0' THEN
      --  sticky_v:=sticky_v OR v_or(fs_man_v(1 DOWNTO 0));
      --  fs_man_v:="00" & fs_man_v(53 DOWNTO 2);
      --END IF;
      
      --IF emod(0)='0' THEN
      --  sticky_v:=sticky_v OR fs_man_v(0);
      --  fs_man_v:='0' & fs_man_v(53 DOWNTO 1);
      --END IF;
      
      expo_v:="0000000000001";

    END IF;
    
    IF sdo='0' THEN
      sticky_v:=sticky_v OR v_or(fs_man_v(28 DOWNTO 0));
      nxf_v:=sticky_v OR fs_man_v(29);
    ELSE
      nxf_v:=sticky_v OR fs_man_v(0);
    END IF;
    
    IF expo_v="0000000000001" AND
      fs_man_v/=ZERO(53 DOWNTO 0) AND fs_man_v(53)='0' THEN
      udf_v:='1';
    ELSE
      udf_v:='0';
    END IF;
    udf_o:=
      (udf_v AND nxf_v AND NOT ufm) OR (udf_v AND ufm); -- Underflow type 'W'

    fs_man_o:=fs_man_v;
    expo_o:=expo_v;
    sticky_o:=sticky_v;
    nxf_o:=nxf_v;
    
  END PROCEDURE mds_4;
  
  PROCEDURE mds_4_unf(
    VARIABLE fs_man_o : OUT unsigned(53 DOWNTO 0);
    VARIABLE expo_o   : OUT unsigned(12 DOWNTO 0);
    VARIABLE sticky_o : OUT std_logic;
    VARIABLE udf_o    : OUT std_logic;
    VARIABLE nxf_o    : OUT std_logic;
    CONSTANT fs_man : IN unsigned(53 DOWNTO 0);
    CONSTANT expo   : IN unsigned(12 DOWNTO 0);
    CONSTANT sticky : IN std_logic;
    CONSTANT sdo    : IN std_logic;
    CONSTANT ufm    : IN std_logic) IS
    VARIABLE sticky_v,sticky_t : std_logic;
    VARIABLE fs_man_v : unsigned(53 DOWNTO 0);
    VARIABLE udf_v,nxf_v : std_logic;
    VARIABLE expo_v : unsigned(12 DOWNTO 0);
  BEGIN
    sticky_v:=sticky;
    fs_man_v:=fs_man;
    expo_v:=expo;
    
    IF sdo='0' THEN
      sticky_v:=sticky_v OR v_or(fs_man_v(28 DOWNTO 0));
      nxf_v:=sticky_v OR fs_man_v(29);
    ELSE
      nxf_v:=sticky_v OR fs_man_v(0);
    END IF;
    
    IF expo_v="0000000000001" AND
      fs_man_v/=ZERO(53 DOWNTO 0) AND fs_man_v(53)='0' THEN
      udf_v:='1';
    ELSE
      udf_v:='0';
    END IF;
    udf_o:=
      (udf_v AND nxf_v AND NOT ufm) OR (udf_v AND ufm); -- Underflow type 'W'

    fs_man_o:=fs_man_v;
    expo_o:=expo_v;
    sticky_o:=sticky_v;
    nxf_o:=nxf_v;
    
  END PROCEDURE mds_4_unf;

  --############################################################################
  -- Arrondi
  --
  --  Guard . Round Sticky | Nearest |   Zero  |   +Inf  |   -Inf  |
  -- ---------------------------------------------------------------
  --       0.   0    0     |   0     |     0   |     0   |     0   |
  --       0.   0    1     |   0     |     0   |+1 si pos|+1 si neg|
  --       0.   1    0     |   0     |     0   |+1 si pos|+1 si neg|
  --       0.   1    1     |   +1    |     0   |+1 si pos|+1 si neg|
  --       1.   0    0     |   0     |     0   |     0   |     0   |
  --       1.   0    1     |   0     |     0   |+1 si pos|+1 si neg|
  --       1.   1    0     |   +1    |     0   |+1 si pos|+1 si neg|
  --       1.   1    1     |   +1    |     0   |+1 si pos|+1 si neg|
  
  FUNCTION arrondi(
    CONSTANT s   : IN std_logic;          -- Signe
    CONSTANT grs : IN unsigned(2 DOWNTO 0);  -- G / R / S
    CONSTANT rd  : IN unsigned(1 DOWNTO 0))  -- Rounding Direction
    RETURN std_logic IS
    VARIABLE r : std_logic := '0';
  BEGIN
    CASE rd IS
      WHEN RND_NEAREST =>
        RETURN (grs(1) AND grs(0)) OR (grs(2) AND grs(1));
      WHEN RND_ZERO =>
        RETURN '0';
      WHEN RND_POS =>
        RETURN NOT s AND (grs(1) OR grs(0));
      WHEN RND_NEG =>
        RETURN s AND (grs(1) OR grs(0));
      WHEN OTHERS =>
        RETURN 'X';
    END CASE;
  END FUNCTION arrondi;

  -- Arrondi
  PROCEDURE arr(
    VARIABLE fs_man_o : OUT unsigned(54 DOWNTO 0);
    VARIABLE expo_o   : OUT unsigned(12 DOWNTO 0);
    CONSTANT fs_man   : IN unsigned(53 DOWNTO 0);
    CONSTANT expo     : IN unsigned(12 DOWNTO 0);
    CONSTANT sticky   : IN std_logic;
    CONSTANT s        : IN std_logic;
    CONSTANT sd       : IN std_logic;
    CONSTANT rd       : IN unsigned(1 DOWNTO 0)) IS
    VARIABLE fs_man_v : unsigned(54 DOWNTO 0);
    VARIABLE add_v   : unsigned(54 DOWNTO 0);
    VARIABLE grs_v : unsigned(2 DOWNTO 0);
  BEGIN
    fs_man_v:='0' & fs_man;
    
    IF sd='1' THEN
      grs_v:=fs_man_v(1 DOWNTO 0) & sticky;
    ELSE
      grs_v:=fs_man_v(30 DOWNTO 29) & sticky;
    END IF;
    
    add_v:=ZERO(54 DOWNTO 0);    
    IF arrondi(s,grs_v,rd)='1' THEN
      IF sd='1' THEN
        add_v(1):='1';
      ELSE
        add_v(30):='1';
      END IF;
    END IF;
    fs_man_v:=fs_man_v + add_v;
    fs_man_o:=fs_man_v;
    expo_o:=expo + (ZERO(12 DOWNTO 1) & fs_man_v(54));
    
  END PROCEDURE arr;  
  
  --------------------------------------------------------------------
  PROCEDURE arrondi_infzero(
    VARIABLE fo      : OUT uv64;
    VARIABLE ovf_o   : OUT std_logic;
    VARIABLE nxf_o   : OUT std_logic;
    CONSTANT fs_man  : IN  unsigned(53 DOWNTO 0);
    CONSTANT expo    : IN  unsigned(12 DOWNTO 0);
    CONSTANT sticky  : IN  std_logic;
    CONSTANT fo_s    : IN  std_logic;
    CONSTANT sdo     : IN  std_logic;              -- 0=single 1=double
    CONSTANT nxf     : IN  std_logic;
    CONSTANT fop     : IN  uv4;
    CONSTANT ufm     : IN  std_logic;
    CONSTANT rd      : IN  unsigned(1 DOWNTO 0);   -- Round Direction 
    CONSTANT mds     : IN  boolean) IS             -- F=ADDSUB T=MULDIV
    VARIABLE fs_man_v : unsigned(54 DOWNTO 0);
    VARIABLE expo_v   : unsigned(12 DOWNTO 0);
    VARIABLE ovf_v,nxf_v : std_logic;
    
  BEGIN
    -- Arrondi
    arr(fs_man_v,expo_v,
        fs_man,expo,sticky,fo_s,sdo,rd);

    -- Test infinis
    test_inf_zero(fs_man_v,expo_v,ovf_v,
                  fs_man_v,expo_v,fo_s,mds,sdo,rd);
    IF fop/=FOP_fTOi THEN
      ovf_o:=ovf_v;
      nxf_o:=nxf OR ovf_v;
    ELSIF fop=FOP_CMP OR fop=FOP_CMPE THEN
      -- Les comparaisons ne génèrent que 'Invalid'
      ovf_o:='0';
      nxf_o:='0';
    ELSE
      ovf_o:='0';
      nxf_o:=nxf;
    END IF;

    fo:=fo_s & expo_v(10 DOWNTO 0) & fs_man_v(52 DOWNTO 1);
    
  END PROCEDURE arrondi_infzero;  
  
  --------------------------------------------------------------------
  PROCEDURE test_special(
    VARIABLE fo_o      : OUT uv64;
    VARIABLE iii_o     : OUT uv32;
    VARIABLE fcc_o     : OUT unsigned(1 DOWNTO 0);
    VARIABLE nvf_o     : OUT std_logic;
    VARIABLE ovf_o     : OUT std_logic;
    VARIABLE udf_o     : OUT std_logic;
    VARIABLE dzf_o     : OUT std_logic;
    VARIABLE nxf_o     : OUT std_logic;
    CONSTANT fo        : IN  uv64;
    CONSTANT iii       : IN  uv32;
    CONSTANT fcc       : IN  unsigned(1 DOWNTO 0);
    CONSTANT nvf       : IN  std_logic;
    CONSTANT ovf       : IN  std_logic;
    CONSTANT udf       : IN  std_logic;
    CONSTANT nxf       : IN  std_logic;
    CONSTANT fs1_class : IN  type_class;
    CONSTANT fs2_class : IN  type_class;
    CONSTANT fop       : IN  uv4) IS
  BEGIN
    nvf_o:='0';
    ovf_o:='0';
    udf_o:='0';
    nxf_o:='0';
    dzf_o:='0';
    
    IF fs2_class(4)='0' THEN
      iii_o:=x"7FFF_FFFF";
    ELSE
      iii_o:=x"8000_0000";
    END IF;

    -- Test cas exceptionnels
    IF is_snan(fs2_class) AND fop/=FOP_iTOf THEN
      fcc_o:="11";
      nvf_o:='1';
      fo_o:=fs2_class(4) & DOUBLE_QNaN(62 DOWNTO 0);
    ELSIF is_snan(fs1_class) AND fop/=FOP_fTOi AND fop/=FOP_iTOf AND
      fop/=FOP_SQRT AND fop/=FOP_fTOf THEN
      fcc_o:="11";
      nvf_o:='1';
      fo_o:=fs1_class(4) & DOUBLE_QNaN(62 DOWNTO 0);
    ELSIF is_qnan(fs2_class) AND fop/=FOP_iTOf THEN
      fcc_o:="11";
      nvf_o:=to_std_logic(fop=FOP_CMPE);
      IF fop=FOP_fTOi THEN
        nvf_o:='1';
      END IF;
      fo_o:=fs2_class(4) & DOUBLE_QNaN(62 DOWNTO 0);
    ELSIF is_qnan(fs1_class) AND fop/=FOP_fTOi AND fop/=FOP_iTOf AND
      fop/=FOP_SQRT AND fop/=FOP_fTOf THEN
      fcc_o:="11";
      nvf_o:=to_std_logic(fop=FOP_CMPE);
      fo_o:=fs1_class(4) & DOUBLE_QNaN(62 DOWNTO 0);
    ELSIF ((is_PInf(fs1_class) AND is_MInf(fs2_class)) OR
          (is_MInf(fs1_class) AND is_PInf(fs2_class))) AND
          (fop=FOP_ADD OR fop=FOP_SUB OR fop=FOP_CMP OR fop=FOP_CMPE) THEN
      -- + Inf - Inf = QNaN
      fcc_o:="00";
      nvf_o:='1';
      fo_o:=fs1_class(4) & DOUBLE_QNaN(62 DOWNTO 0);
    ELSIF is_inf(fs1_class) AND
      (fop=FOP_ADD OR fop=FOP_SUB OR fop=FOP_CMP OR fop=FOP_CMPE) THEN
      -- Infini +/- Scalaire
      fcc_o:=NOT fs1_class(4) & fs1_class(4);
      nvf_o:='0';
      fo_o:=fs1_class(4) & DOUBLE_INFINI(62 DOWNTO 0);
    ELSIF is_inf(fs2_class) AND
      (fop=FOP_ADD OR fop=FOP_SUB OR fop=FOP_CMP OR fop=FOP_CMPE) THEN
      -- Scalaire +/- Infini
      fcc_o:=NOT fs2_class(4) & fs2_class(4);
      nvf_o:=to_std_logic(fop=FOP_fTOi);
      fo_o:=fs2_class(4) & DOUBLE_INFINI(62 DOWNTO 0);
    ELSIF (is_inf(fs1_class)  AND is_inf(fs2_class)  AND fop=FOP_DIV) OR
          (is_zero(fs1_class) AND is_zero(fs2_class) AND fop=FOP_DIV) OR
      -- Infini / Infini = QNaN, 0 / 0 = QNaN
          (is_zero(fs1_class) AND is_inf(fs2_class) AND fop=FOP_MUL) OR
          (is_zero(fs2_class) AND is_inf(fs1_class) AND fop=FOP_MUL) THEN
      -- Zero * Infini = QNaN
      nvf_o:='1';
      fo_o:=(fs1_class(4) XOR fs2_class(4)) & DOUBLE_QNaN(62 DOWNTO 0);
    ELSIF fs2_class(4)='1' AND NOT is_zero(fs2_class) AND fop=FOP_SQRT THEN
      -- Racine d'un nombre négatif : QNaN
      nvf_o:='1';
      fo_o:=fs2_class(4) & DOUBLE_QNaN(62 DOWNTO 0);
    ELSIF (is_scal(fs1_class) AND is_inf(fs2_class) AND fop=FOP_DIV) OR
      -- Scalaire / Infini = Zero
          (is_zero(fs1_class) AND NOT is_zero(fs2_class) AND fop=FOP_DIV) OR
          (is_zero(fs1_class) AND NOT is_inf(fs2_class) AND fop=FOP_MUL) OR
          (is_zero(fs2_class) AND NOT is_inf(fs1_class) AND fop=FOP_MUL) THEN
      -- Multiplication de Zéro, Division de Zéro
      fo_o:=(fs1_class(4) XOR fs2_class(4)) & DOUBLE_Zero(62 DOWNTO 0);
    ELSIF ((is_inf(fs1_class) OR is_inf(fs2_class)) AND fop=FOP_MUL) OR
          (is_inf(fs1_class) AND fop=FOP_DIV) THEN
        -- Infini / Scalaire = Infini,  Infini * Scalaire = Infini
      fo_o:=(fs1_class(4) XOR fs2_class(4)) & DOUBLE_INFINI(62 DOWNTO 0);
    ELSIF is_zero(fs2_class) AND fop=FOP_DIV THEN
        -- Division par zéro
      dzf_o:='1';
      fo_o:=(fs1_class(4) XOR fs2_class(4)) & DOUBLE_INFINI(62 DOWNTO 0);
    ELSIF is_zero(fs2_class) AND fop=FOP_SQRT THEN
      -- Racine de zéro
      fo_o:=fs2_class(4) & DOUBLE_Zero(62 DOWNTO 0);
    ELSIF is_pinf(fs2_class) AND fop=FOP_SQRT THEN
      -- Racine de l'infini
      fo_o:=DOUBLE_Infini;
    ELSIF is_zero(fs2_class) AND fop=FOP_fTOf THEN
      -- Conversion zero
      fo_o:=fs2_class(4) & DOUBLE_Zero(62 DOWNTO 0);
    ELSIF is_inf(fs2_class) AND fop=FOP_fTOf THEN
      -- Conversion infini
      fo_o:=fs2_class(4) & DOUBLE_Infini(62 DOWNTO 0);
    ELSE
      fo_o:=fo;
      fcc_o:=fcc;
      nvf_o:=nvf;
      ovf_o:=ovf;
      udf_o:=udf;
      nxf_o:=nxf;
      iii_o:=iii;
    END IF;
    
  END PROCEDURE test_special;

  --############################################################################

  -- Décodage d'instructions
  FUNCTION fpu_decode(CONSTANT op : uv32) RETURN type_decode IS
    VARIABLE v : type_decode;
    VARIABLE opx : unsigned(3 DOWNTO 0);
  BEGIN
    IF op(19)='0' THEN
      CASE op(12 DOWNTO 5) IS
        WHEN "00000001" => v.unimp:='0'; --FMOVs
        WHEN "00000010" => v.unimp:='1'; --FMOVd       SparcV9
        WHEN "00000011" => v.unimp:='1'; --FMOVq  QUAD SparcV9
        WHEN "00000101" => v.unimp:='0'; --FNEGs
        WHEN "00000110" => v.unimp:='1'; --FNEGd       SparcV9
        WHEN "00000111" => v.unimp:='1'; --FNEGq  QUAD SparcV9
        WHEN "00001001" => v.unimp:='0'; --FABSs
        WHEN "00001010" => v.unimp:='1'; --FABSd       SparcV9
        WHEN "00001011" => v.unimp:='1'; --FABSq  QUAD SparcV9
        WHEN "00101001" => v.unimp:='0'; --FSQRTs
        WHEN "00101010" => v.unimp:='0'; --FSQRTd
        WHEN "00101011" => v.unimp:='1'; --FSQRTq QUAD
        WHEN "01000001" => v.unimp:='0'; --FADDs
        WHEN "01000010" => v.unimp:='0'; --FADDd
        WHEN "01000011" => v.unimp:='1'; --FADDq  QUAD
        WHEN "01000101" => v.unimp:='0'; --FSUBs
        WHEN "01000110" => v.unimp:='0'; --FSUBd
        WHEN "01000111" => v.unimp:='1'; --FSUBq  QUAD
        WHEN "01001001" => v.unimp:='0'; --FMULs
        WHEN "01001010" => v.unimp:='0'; --FMULd
        WHEN "01001011" => v.unimp:='1'; --FMULq  QUAD
        WHEN "01001101" => v.unimp:='0'; --FDIVs
        WHEN "01001110" => v.unimp:='0'; --FDIVd
        WHEN "01001111" => v.unimp:='1'; --FDIVq  QUAD
        WHEN "01101001" => v.unimp:='0'; --FsMULd
        WHEN "01101110" => v.unimp:='1'; --FdMULq QUAD
        WHEN "11000100" => v.unimp:='0'; --FiTOs
        WHEN "11000110" => v.unimp:='0'; --FdTOs
        WHEN "11000111" => v.unimp:='1'; --FqTOs  QUAD
        WHEN "11001000" => v.unimp:='0'; --FiTOd
        WHEN "11001001" => v.unimp:='0'; --FsTOd
        WHEN "11001011" => v.unimp:='1'; --FqTOd  QUAD
        WHEN "11001100" => v.unimp:='1'; --FiTOq  QUAD
        WHEN "11001101" => v.unimp:='1'; --FsTOq  QUAD
        WHEN "11001110" => v.unimp:='1'; --FdTOq  QUAD
        WHEN "11010001" => v.unimp:='0'; --FsTOi
        WHEN "11010010" => v.unimp:='0'; --FdTOi
        WHEN "11010011" => v.unimp:='1'; --FqTOi  QUAD
        WHEN OTHERS     => v.unimp:='1';
      END CASE;
    ELSE
      CASE op(12 DOWNTO 5) IS
        WHEN "01010001" => v.unimp:='0'; --FCMPs
        WHEN "01010010" => v.unimp:='0'; --FCMPd
        WHEN "01010011" => v.unimp:='1'; --FCMPq  QUAD
        WHEN "01010101" => v.unimp:='0'; --FCMPEs
        WHEN "01010110" => v.unimp:='0'; --FCMPEd
        WHEN "01010111" => v.unimp:='1'; --FCMPEq QUAD
        WHEN OTHERS     => v.unimp:='1';
      END CASE;
    END IF;
    
    v.cmp:=op(19);
    v.sdi:=op(6);
    v.sdo:=(op(6) AND NOT op(12)) OR (op(10) AND op(11)) OR (op(8) AND op(12));
    
    IF op(6)='0' AND op(5)='0' THEN
      v.fop:=FOP_iTOf;
    ELSIF op(12)='1' AND op(7)='0' AND op(8)='0' THEN
      v.fop:=FOP_fTOi;
    ELSIF op(12)='1' AND (op(7)='1' OR op(8)='1') THEN
      v.fop:=FOP_fTOf;
    ELSIF op(19)='1' AND op(7)='0' THEN
      v.fop:=FOP_CMP;
    ELSIF op(19)='1' AND op(7)='1' THEN
      v.fop:=FOP_CMPE;
    ELSE
      opx:=op(11 DOWNTO 10) & op(8 DOWNTO 7);
      CASE opx IS
        WHEN "0000" => v.fop:=FOP_MOV;
        WHEN "0001" => v.fop:=FOP_NEG;
        WHEN "0010" => v.fop:=FOP_ABS;
        WHEN "0011" => v.fop:=FOP_NEG;   -- Invalid
        WHEN "0100" => v.fop:=FOP_fTOi;
        WHEN "0101" => v.fop:=FOP_fTOf;
        WHEN "0110" => v.fop:=FOP_SQRT;
        WHEN "0111" => v.fop:=FOP_iTOf;
        WHEN "1000" => v.fop:=FOP_ADD;
        WHEN "1001" => v.fop:=FOP_SUB;
        WHEN "1010" => v.fop:=FOP_MUL;
        WHEN "1011" => v.fop:=FOP_DIV;
        WHEN "1100" => v.fop:=FOP_MUL;   -- Invalid
        WHEN "1101" => v.fop:=FOP_MUL;   -- Invalid
        WHEN "1110" => v.fop:=FOP_MUL;
        WHEN OTHERS => v.fop:=FOP_MUL;
      END CASE;
    END IF;
    v.bin:=to_std_logic(op(12 DOWNTO 11)="01");
    
    RETURN v;
  END FUNCTION fpu_decode;

  --------------------------------------
  FUNCTION fop_string(CONSTANT fop : uv4) RETURN string IS
    VARIABLE s : string(1 TO 4);
  BEGIN
    CASE fop IS
      WHEN FOP_ADD  => s:="ADD ";
      WHEN FOP_SUB  => s:="SUB ";
      WHEN FOP_CMP  => s:="CMP ";
      WHEN FOP_CMPE => s:="CMPE";
      WHEN FOP_fTOi => s:="fTOi";
      WHEN FOP_iTOf => s:="iTOf";
      WHEN FOP_MUL  => s:="MUL ";
      WHEN FOP_DIV  => s:="DIV ";
      WHEN FOP_SQRT => s:="SQRT";
      WHEN FOP_fTOf => s:="fTOf";
      WHEN FOP_MOV  => s:="MOV ";
      WHEN FOP_NEG  => s:="NEG ";
      WHEN FOP_ABS  => s:="ABS ";                      
      WHEN OTHERS   => s:="????";
    END CASE;
    RETURN s;
  END FUNCTION;

  --------------------------------------
  FUNCTION to_real (CONSTANT f : unsigned) RETURN real IS
    VARIABLE f_s : std_logic;
    VARIABLE f_e : unsigned(10 DOWNTO 0);
    VARIABLE f_m : unsigned(22 DOWNTO 0);
    VARIABLE v : real;
    VARIABLE e : integer;
    VARIABLE ff : unsigned(f'length -1 DOWNTO 0) :=f;
  BEGIN

    IF f'length=32 THEN
      f_s:=ff(31);
      f_e:="000" & ff(30 DOWNTO 23);
      f_m:=ff(22 DOWNTO 0);
      IF f_e="00000000000" THEN
        v:=0.0;
      ELSE
        v:=real(to_integer('1' & f_m));
        v:=v * 2.0 ** (to_integer(f_e)-127-23);
        IF f_s='1' THEN
          v:=-v;
        END IF;
      END IF;
    ELSE
      f_s:=ff(63);
      f_e:=ff(62 DOWNTO 52);
      f_m:=ff(51 DOWNTO 29);
      IF f_e="00000000000" THEN
        v:=0.0;
      ELSE
        v:=real(to_integer('1' & f_m));
        e:=to_integer(f_e)-1023;
        IF e>-126 AND e<126 THEN
          v:=v * 2.0 ** (e-23);
        ELSIF e>0 THEN
          v:=1.234567e38;
        ELSE
          v:=1.234567e-38;
        END IF;
        IF f_s='1' THEN
          v:=-v;
        END IF;
      END IF;
    END IF;
    
    RETURN v;
  END FUNCTION to_real;
  
  
END PACKAGE BODY fpu_pack;
