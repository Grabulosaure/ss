--------------------------------------------------------------------------------
-- TEM : TACUS
-- Packet Unité Entière
--------------------------------------------------------------------------------
-- DO 4/2009
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
USE work.asi_pack.ALL;

PACKAGE iu_pack IS
  --------------------------------------
  -- Registres Unité entière

  -- R0=0
  -- R1  ...  R7 = G1 ... G7
  -- R8  ... R15 = O0 ... O7
  -- R16 ... R23 = L0 ... L7
  -- R24 ... R31 = I0 ... I7

  -- R15=O7 : Adresse retour sous-programme terminal (convention)
  -- R31=I7 : Adresse retour sous-programme non terminal (convention)
  -- R14=O6 : Stack Pointer (convention)
  -- R30=I6 : Frame Pointer (convention)
  -- R18=L2 : Sauvegarde nPC pendant les traps
  -- R17=L1 : Sauvegarde  PC pendant les traps

  --------------------------------------
  FUNCTION regad (
    r        : uint5;
    cwp      : unsigned(4 DOWNTO 0);
    NWINDOWS : natural) RETURN natural;

  --------------------------------------
  TYPE type_icc IS RECORD
    n : std_logic;    -- PSR 23
    z : std_logic;    -- PSR 22
    v : std_logic;    -- PSR 21
    c : std_logic;    -- PSR 20
  END RECORD;

  --(2-9)
  TYPE type_psr IS RECORD
                                         -- 31:28 : IU Implementation
                                         -- 27:24 : IU Version Number
    icc : type_icc;                      -- 23:20 : Integer Condition Codes
                                         -- 19:14 : Reservé
                                         -- 13    : Enable Coprocessor
    ef  : std_logic;                     -- 12    : Enable Floating Point
    pil : unsigned(3 DOWNTO 0);          -- 11:8  : Processor Interrupt Level
    s   : std_logic;                     --  7    : Supervisor
    ps  : std_logic;                     --  6    : Previous Supervisor
    et  : std_logic;                     --  5    : Trap Enable
    cwp : unsigned(4 DOWNTO 0);          --  4:0  : Current Window Pointer
  END RECORD;

  CONSTANT PSR_X : type_psr:=(('X','X','X','X'),'X',"XXXX",'X','X','X',"XXXXX");
  CONSTANT PSR_0 : type_psr:=(('0','0','0','0'),'0',"0000",'0','0','0',"00000");
   
  FUNCTION rdpsr (CONSTANT psr : type_psr;
                  CONSTANT IU_IMP_VERSION : uv8) RETURN unsigned;
  
  PROCEDURE wrpsr (VARIABLE psr      : OUT type_psr;
                   CONSTANT v        : IN  uv32;
                   CONSTANT fp       : IN  std_logic;
                   CONSTANT NWINDOWS : IN  natural);

  TYPE type_tbr IS RECORD
    tba : unsigned(31 DOWNTO 12);
    tt  : unsigned(11 DOWNTO 4);
  END RECORD;
  
  --############################################################################
  -- TRAPS
  
  TYPE type_trap IS RECORD
    t   : std_logic;
    tt  : uv8;
  END RECORD;
  
  -- (7.1)
  CONSTANT TT_NONE        : type_trap := ('0',x"02");  
  CONSTANT TT_RESET       : type_trap := ('1',x"00");  -- 1 : RESET, not a trap
  CONSTANT TT_DATA_STORE_ERROR         : type_trap := ('1',x"2B");  -- 2 : MMU
  CONSTANT TT_INST_ACCESS_MMU_MISS     : type_trap := ('1',x"3C");  -- 2 : MMU
  CONSTANT TT_INST_ACCESS_ERROR        : type_trap := ('1',x"21");  -- 3 : MMU
  CONSTANT TT_R_REGISTER_ACCESS_ERROR  : type_trap := ('1',x"20");  -- 4
  CONSTANT TT_INST_ACCESS_EXCEPTION    : type_trap := ('1',x"01");  -- 5 : MMU
  CONSTANT TT_PRIVILEGED_INSTRUCTION   : type_trap := ('1',x"03");  -- 6
  CONSTANT TT_ILLEGAL_INSTRUCTION      : type_trap := ('1',x"02");  -- 7
  CONSTANT TT_FP_DISABLED              : type_trap := ('1',x"04");  -- 8
  CONSTANT TT_CP_DISABLED              : type_trap := ('1',x"24");  -- 8
  CONSTANT TT_UNIMPLEMENTED_FLUSH      : type_trap := ('1',x"25");  -- 8
  CONSTANT TT_WATCHPOINT_DETECTED      : type_trap := ('1',x"0B");  -- 8
  CONSTANT TT_WINDOW_OVERFLOW          : type_trap := ('1',x"05");  -- 9
  CONSTANT TT_WINDOW_UNDERFLOW         : type_trap := ('1',x"06");  -- 9
  CONSTANT TT_MEM_ADDRESS_NOT_ALIGNED  : type_trap := ('1',x"07");  -- 10
  CONSTANT TT_FP_EXCEPTION             : type_trap := ('1',x"08");  -- 11
  CONSTANT TT_CP_EXCEPTION             : type_trap := ('1',x"28");  -- 11
  CONSTANT TT_DATA_ACCESS_ERROR        : type_trap := ('1',x"29");  -- 12 : MMU
  CONSTANT TT_DATA_ACCESS_MMU_MISS     : type_trap := ('1',x"2C");  -- 12 : MMU
  CONSTANT TT_DATA_ACCESS_EXCEPTION    : type_trap := ('1',x"09");  -- 13 : MMU
  CONSTANT TT_TAG_OVERFLOW             : type_trap := ('1',x"0A");  -- 14
  CONSTANT TT_DIVISION_BY_ZERO         : type_trap := ('1',x"2A");  -- 15
  
  CONSTANT TT_TRAP_INSTRUCTION: type_trap := ('1',x"80");  -- 80..FF : SW Trap
  
  CONSTANT TT_INTERRUPT_LEVEL_15       : type_trap := ('1',x"1F");  -- 17
  CONSTANT TT_INTERRUPT_LEVEL_14       : type_trap := ('1',x"1E");  -- 18
  CONSTANT TT_INTERRUPT_LEVEL_13       : type_trap := ('1',x"1D");  -- 19
  CONSTANT TT_INTERRUPT_LEVEL_12       : type_trap := ('1',x"1C");  -- 20
  CONSTANT TT_INTERRUPT_LEVEL_11       : type_trap := ('1',x"1B");  -- 21
  CONSTANT TT_INTERRUPT_LEVEL_10       : type_trap := ('1',x"1A");  -- 22
  CONSTANT TT_INTERRUPT_LEVEL_9        : type_trap := ('1',x"19");  -- 23
  CONSTANT TT_INTERRUPT_LEVEL_8        : type_trap := ('1',x"18");  -- 24
  CONSTANT TT_INTERRUPT_LEVEL_7        : type_trap := ('1',x"17");  -- 25
  CONSTANT TT_INTERRUPT_LEVEL_6        : type_trap := ('1',x"16");  -- 26
  CONSTANT TT_INTERRUPT_LEVEL_5        : type_trap := ('1',x"15");  -- 27
  CONSTANT TT_INTERRUPT_LEVEL_4        : type_trap := ('1',x"14");  -- 28
  CONSTANT TT_INTERRUPT_LEVEL_3        : type_trap := ('1',x"13");  -- 29
  CONSTANT TT_INTERRUPT_LEVEL_2        : type_trap := ('1',x"12");  -- 30
  CONSTANT TT_INTERRUPT_LEVEL_1        : type_trap := ('1',x"11");  -- 31
  -- Sur SparcV7 : "Illegal" est prioritaire par rapport à "Privileged"

  --############################################################################

  CONSTANT SIZE_W  : unsigned(1 DOWNTO 0) := "00";  -- Word
  CONSTANT SIZE_B  : unsigned(1 DOWNTO 0) := "01";  -- Byte
  CONSTANT SIZE_H  : unsigned(1 DOWNTO 0) := "10";  -- Half Word
  CONSTANT SIZE_D  : unsigned(1 DOWNTO 0) := "11";  -- Double Word
  
  CONSTANT LDST_UW : unsigned(2 DOWNTO 0) := "000";  -- Word
  CONSTANT LDST_UB : unsigned(2 DOWNTO 0) := "001";  -- Unsigned Byte
  CONSTANT LDST_UH : unsigned(2 DOWNTO 0) := "010";  -- Unsigned Half Word
  CONSTANT LDST_UD : unsigned(2 DOWNTO 0) := "011";  -- Double Word
  CONSTANT LDST_SW : unsigned(2 DOWNTO 0) := "100"; -- Signed Double <simpli>
  CONSTANT LDST_SB : unsigned(2 DOWNTO 0) := "101";  -- Signed   Byte
  CONSTANT LDST_SH : unsigned(2 DOWNTO 0) := "110";  -- Signed   Half Word
  CONSTANT LDST_SD : unsigned(2 DOWNTO 0) := "111"; -- Signed Double <simpli>

  -- Simplification decoder : UW=SW, UD=SD
  
  -- Code ASI vers MMU lors d'une instruction IFLUSH
  CONSTANT ASI_IFLUSH : uv8 := ASI_CACHE_FLUSH_LINE_COMBINED_ANY;
  
  --------------------------------------
  FUNCTION plomb_trap_inst (t : enum_plomb_code) RETURN type_trap;
  FUNCTION plomb_trap_data (t : enum_plomb_code) RETURN type_trap;
  
  --------------------------------------
  FUNCTION plomb_rd (
    a   : uv32;                         -- Adresse
    asi : uv8;                          -- ASI
    s   : unsigned(2 DOWNTO 0))         -- Size
    RETURN type_plomb_w;
  
  --------------------------------------
  FUNCTION plomb_wr (
    a   : uv32;                         -- Adresse
    asi : uv8;                          -- ASI
    s   : unsigned(2 DOWNTO 0);         -- Size
    d   : uv32)
    RETURN type_plomb_w;
    
  --############################################################################
  
  --------------------------------------
  TYPE type_fpu_debug_s IS RECORD
    fsr_tem  : unsigned(4 DOWNTO 0);
    fsr_ftt  : unsigned(2 DOWNTO 0);
    fsr_qne  : std_logic;
    fsr_aexc : unsigned(4 DOWNTO 0);
    fsr_cexc : unsigned(4 DOWNTO 0);
  END RECORD;
  CONSTANT FPU_DEBUG_S_X : type_fpu_debug_s := ("XXXXX","XXX",'X',
                                                "XXXXX","XXXXX");
  
  --------------------------------------
  -- Catégories d'instructions
  TYPE type_mode IS RECORD
    l : std_logic;                      -- Load
    s : std_logic;                      -- Store
    d : std_logic;                      -- Double
    j : std_logic;                      -- JMPL, RETT
    b : std_logic;                      -- Bicc, FBfcc
    f : std_logic;                      -- FPU
    m : std_logic;                      -- Integer MUL/DIV
  END RECORD;
  --                                      L   S   D   J   B   F   M
  CONSTANT CALC           : type_mode :=('0','0','0','0','0','0','0');
  CONSTANT MULDIV         : type_mode :=('0','0','0','0','0','0','1');
  
  CONSTANT LOAD           : type_mode :=('1','0','0','0','0','0','0');
  CONSTANT LOAD_DOUBLE    : type_mode :=('1','0','1','0','0','0','0');
  CONSTANT LOAD_STORE     : type_mode :=('1','1','0','0','0','0','0');
  CONSTANT STORE          : type_mode :=('0','1','0','0','0','0','0');
  CONSTANT STORE_DOUBLE   : type_mode :=('0','1','1','0','0','0','0');

  CONSTANT FPCALC         : type_mode :=('0','0','0','0','0','1','0');
  
  CONSTANT FPLOAD         : type_mode :=('1','0','0','0','0','1','0');
  CONSTANT FPLOAD_DOUBLE  : type_mode :=('1','0','1','0','0','1','0');
  CONSTANT FPSTORE        : type_mode :=('0','1','0','0','0','1','0');
  CONSTANT FPSTORE_DOUBLE : type_mode :=('0','1','1','0','0','1','0');
  
  CONSTANT JMPL           : type_mode :=('0','0','0','1','0','0','0');
  CONSTANT BRANCH         : type_mode :=('0','0','0','0','1','0','0');

  -- Arithmetic_Logic Mul_Div Load_Store Floating_Point
  --TYPE type_unit IS (AL,MD,LS,FP);
   
  -- Types d'instructions
  TYPE type_cat IS RECORD
    op        : uv32;
    mode      : type_mode;              -- Mode de l'instruction
    priv      : std_logic;              -- Privilegied
    sub       : std_logic;              -- R1-R2 au lieu de R1+R2
    size      : unsigned(2 DOWNTO 0);   -- Taille du transfert
    
    m_reg     : std_logic;              -- Modifie registre RD
    m_ry      : std_logic;              -- Modifie registre RY
    
    m_psr     : std_logic;              -- MàJ de PSR     : WRPSR
    m_psr_icc : std_logic;              -- MàJ de PSR.ICC
    m_psr_cwp : std_logic;              -- MàJ de PSR.CWP
    m_psr_s   : std_logic;              -- MàJ de PSR.s   : RETT
    m_wim     : std_logic;              -- MàJ de WIM
    m_tbr     : std_logic;              -- MàJ de TBR
    
    r_reg     : unsigned(1 TO 3);       -- Dépendances registres RS1,RS2,RD
    r_ry      : std_logic;              -- Dépend du registre Y
    r_psr_icc : std_logic;              -- Dépend d'ICC
    r_fcc     : std_logic;              -- FPU : Dépend des codes conditions
  END RECORD;

  -- r_freg :
  --   Dépendances des registres flottants lus
  -- m_fpr :
  --   Dépendances du registre flottant écrit
  -- f :
  --   Instruction qui doit attendre la fin des instructions FPU
  --   : LDFSR, STFSR, STDFQ

  -- On associe à chaque instruction une constante CAT_xxx
  -- Les champs <r_reg> sont à remplir "à la main"

  -- CAT_ALU est injecté dans le pipe de PIPE5, pour les traps...
  CONSTANT CAT_ALU : type_cat := (op=>x"00000000",
    mode =>CALC,priv=>'0',sub=>'0',size=>LDST_UW,
    m_reg=>'1',m_ry=>'0',
    m_psr=>'0',m_psr_icc=>'0',m_psr_cwp=>'0',m_psr_s=>'0',
    m_wim=>'0',m_tbr=>'0',r_reg=>"XXX",r_ry=>'0',r_psr_icc=>'0',r_fcc=>'0');

  --------------------------------------
  TYPE type_fpu_i IS RECORD
    -- Exécution instructions FPU OP
    cat         :   type_cat;
    pc          :   uv32;                 -- Adresse instruction (pour DFQ)
    req         :   std_logic;            -- Début nouvelle instruction FPOP
    wri         :   std_logic;            -- Complétion d'instruction
    tstop       :   std_logic;            -- TrapStop
    fxack       :   std_logic;            -- Acquittement TRAP FPU
    -- Load
    do_ack      :   std_logic;            -- Second accès instruction double
    -- Store
    di          :   uv32;                 -- Bus données entrées
    di_maj      :   std_logic;            -- Ecriture registre
    -- Debug
    dstop       :   std_logic;
    ver         :   unsigned(2 DOWNTO 0); -- FPU version
  END RECORD;

  TYPE type_fpu_o IS RECORD
    present     : std_logic;           -- FPU Présente
    -- Exécution instructions FPU OP
    rdy         : std_logic;           -- Prêt pour une nouvelle instruction
    fexc        : std_logic;           -- Requète TRAP FPU
    -- Load
    do          : uv32;                -- Bus données sorties
    -- Drapeaux de comparaison pour FBcc
    fcc         : unsigned(1 DOWNTO 0); -- Codes conditions
    fccv        : std_logic;            -- Validité codes condition
  END RECORD;

  CONSTANT FPU_DISABLE : type_fpu_o :=('0','0','0',x"00000000","00",'0');

  CONSTANT FPU_MP_NOCPU : type_fpu_i := (CAT_ALU,
                                        (OTHERS =>'X'),'0','0','0','0','0',
                                        (OTHERS =>'X'),'0','0',"XXX");
  
  --------------------------------------
  TYPE type_stat_s IS RECORD            -- Super8 STAT
    v1 : std_logic;
    v2 : std_logic;
    cat1 : type_cat;
    cat2 : type_cat;
    skip : std_logic;
    brok : std_logic;
    brerr : std_logic;
  END RECORD;
  
  -- Débug, simulation
  TYPE type_debug_s IS RECORD
    dstop     : std_logic;                      -- Arrêté pour débugger
    trap_stop : std_logic;
    halterror : std_logic;
    d         : uv32;                           -- Données relues pour débugger
    pc        : uv32;                           -- Registre PC
    npc       : uv32;                           -- Registre nPC
    psr       : type_psr;                       -- Registre PSR
    fcc       : unsigned(1 DOWNTO 0);           -- FPU Condition codes
    fccv      : std_logic;                      -- FPU Condition codes valid
    wim       : uv32;                           -- Registre WIM
    tbr       : type_tbr;                       -- Registre TBR
    ry        : uv32;                           -- Registre Y
    irl       : uv4;                            -- Interruptions
    trap      : type_trap;                      -- Déclenchement de trap
    hetrap    : type_trap;

    stat      : uv16;
  END RECORD;
  
  TYPE type_debug_t IS RECORD
    ena    : std_logic;                 -- Activation/autorisation debugger
    stop   : std_logic;                 -- Demande arrêt débugger (pulse)
    run    : std_logic;                 -- Demande redémarrage (pulse)
    vazy   : std_logic;                 -- Pousse une instruction (pulse)
    op     : uv32;                      -- Debugger Opcode
    code   : enum_plomb_code;           -- Plomb memory acces code
    ppc    : std_logic;                 -- Empile accès, modification PC
    opt    : uv2;                       -- No super
    ib     : uv32;                      -- Point d'arrêt instructions
    ib_ena : std_logic;                 -- Activation point d'arrêt instructions
    db     : uv32;                      -- Point d'arrêt données
    db_ena : std_logic;                 -- Activation point d'arrêt données
  END RECORD;
  
  CONSTANT DEBUG_T_DISABLED : type_debug_t := (
    '0','0','0','0',x"00000000",PB_OK,'0',"00",
    x"00000000",'0',x"00000000",'0');
  
  --############################################################################

  FUNCTION ld (
    s : unsigned(2 DOWNTO 0);   -- Size/Mode
    a : unsigned(1 DOWNTO 0);   -- Address
    d : unsigned(31 DOWNTO 0))  -- Data
    RETURN unsigned;
  
  --############################################################################

  PROCEDURE decode (
    CONSTANT op         : IN  uv32;
    CONSTANT IFLUSH     : IN  boolean;
    CONSTANT CASA       : IN  boolean;
    VARIABLE cat_o      : OUT type_cat;
    VARIABLE n_rd_o     : OUT uint5;
    VARIABLE n_rs1_o    : OUT uint5;
    VARIABLE n_rs2_o    : OUT uint5);
  
  --------------------------------------
  FUNCTION cwpfix (CONSTANT cwp      : IN unsigned(4 DOWNTO 0);
                   CONSTANT NWINDOWS : IN natural)
    RETURN unsigned;
  
  --------------------------------------
  FUNCTION cwpcalc (
    CONSTANT cwp       : IN unsigned(4 DOWNTO 0);
    CONSTANT m_psr_cwp : IN std_logic;
    CONSTANT trap      : IN std_logic;
    CONSTANT opcode    : IN uv32;
    CONSTANT NWINDOWS  : IN natural) RETURN unsigned;
  
  --------------------------------------
  PROCEDURE op_lsu (
    CONSTANT cat        : IN  type_cat;
    CONSTANT rd         : IN  uv32;
    CONSTANT sum        : IN  uv32;
    CONSTANT psr        : IN  type_psr;
    CONSTANT fexc       : IN  std_logic;
    CONSTANT IFLUSH     : IN  boolean;
    CONSTANT FPU_LDASTA : IN  boolean;
    CONSTANT CASA       : IN  boolean;
    VARIABLE data_w     : OUT type_plomb_w; -- Pipe Données     CPU -> MEM
    VARIABLE trap_o     : OUT type_trap);   -- Génération TRAP
  
  --------------------------------------
  --pragma synthesis_off
  PROCEDURE op_mdu_sim (
    CONSTANT cat         : IN  type_cat;  -- Fetch
    CONSTANT rs1         : IN  uv32;   -- Registre Source 1
    CONSTANT rs2         : IN  uv32;   -- Registre Source 2
    VARIABLE rd_o        : OUT uv32;   -- Registre Destination
    CONSTANT ry          : IN  uv32;   -- Registre Y
    VARIABLE ry_o        : OUT uv32;   -- Registre Y
    VARIABLE icc_o       : OUT type_icc;
    VARIABLE dz_o        : OUT std_logic);
  --pragma synthesis_on

  --------------------------------------
  PROCEDURE op_exe (
    CONSTANT cat         : IN  type_cat;
    CONSTANT pc          : IN  uv32;
    VARIABLE npc_o       : OUT uv32;
    VARIABLE npc_maj     : OUT std_logic;
    CONSTANT rs1         : IN  uv32;
    CONSTANT rs2         : IN  uv32;
    VARIABLE rd_o        : OUT uv32;
    VARIABLE sum_o       : OUT uv32;
    CONSTANT ry          : IN  uv32;
    VARIABLE ry_o        : OUT uv32;
    CONSTANT psr         : IN  type_psr;
    VARIABLE psr_o       : OUT type_psr;
    CONSTANT muldiv_rd   : IN  uv32;
    CONSTANT muldiv_ry   : IN  uv32;
    CONSTANT muldiv_icc  : IN  type_icc;
    CONSTANT muldiv_dz   : IN  std_logic;
    CONSTANT cwp         : IN  unsigned(4 DOWNTO 0);
    CONSTANT wim         : IN  unsigned;
    CONSTANT tbr         : IN  type_tbr;
    CONSTANT fexc        : IN  std_logic;
    VARIABLE trap_o      : OUT type_trap;
    CONSTANT MULDIV      : IN  boolean;
    CONSTANT IU_IMP_VERSION : IN uv8);
  
  --------------------------------------
  PROCEDURE op_dec(
    CONSTANT op          : IN  uv32;
    CONSTANT pc          : IN  uv32;
    VARIABLE npc_o       : OUT uv32;
    VARIABLE npc_maj     : OUT std_logic;
    CONSTANT psr         : IN  type_psr;
    CONSTANT fcc         : IN  unsigned(1 DOWNTO 0);
    CONSTANT fexc        : IN  std_logic;
    VARIABLE annul_o     : OUT std_logic);

END PACKAGE iu_pack;
--------------------------------------------------------------------------------

PACKAGE BODY iu_pack IS

  --############################################################################
  
  --------------------------------------
  -- Register bank addressing. Aliasing when CWP=NWINDOWS-1
  FUNCTION regad (
    r        : uint5;
    cwp      : unsigned(4 DOWNTO 0);
    NWINDOWS : natural) RETURN natural IS
    VARIABLE o,v : natural RANGE 0 TO NWINDOWS*16+16;
  BEGIN
    v:=r;
    IF v<8 THEN
      o:=v;
    ELSE
      o:=16*to_integer(cwpfix(cwp,NWINDOWS)) + v;
    END IF;
    IF o<NWINDOWS*16+8 THEN
      RETURN o;
    ELSE
      RETURN o - NWINDOWS*16;
    END IF;
  END FUNCTION regad;
  
  --------------------------------------
  -- Assemblage registre PSR
  FUNCTION rdpsr (CONSTANT psr : type_psr;
                  CONSTANT IU_IMP_VERSION : uv8) RETURN unsigned IS
  BEGIN
    RETURN IU_IMP_VERSION &
      psr.icc.n & psr.icc.z & psr.icc.v & psr.icc.c &
      "000000" & '0' &
      psr.ef & psr.pil & psr.s & psr.ps & psr.et & psr.cwp;
  END FUNCTION rdpsr;
  
  --------------------------------------
  -- Décomposition registre PSR
  PROCEDURE wrpsr (VARIABLE psr      : OUT type_psr;
                   CONSTANT v        : IN  uv32;
                   CONSTANT fp       : IN  std_logic;
                   CONSTANT NWINDOWS : IN  natural) IS
  BEGIN
    psr.icc.n:=v(23);
    psr.icc.z:=v(22);
    psr.icc.v:=v(21);
    psr.icc.c:=v(20);
    psr.ef   :=v(12) AND fp;
    psr.pil  :=v(11 DOWNTO 8);
    psr.s    :=v(7);
    psr.ps   :=v(6);
    psr.et   :=v(5);
    psr.cwp  :=cwpfix(v(4 DOWNTO 0),NWINDOWS);
  END PROCEDURE wrpsr;
  
  --------------------------------------
  -- Test des codes conditions entiers
  -- Pour sauts conditionnels Bicc, Traps conditionnels Ticc
  FUNCTION icc_test (
    c : type_icc;
    t : uv4)
    RETURN std_logic IS
  BEGIN
    CASE t IS
      WHEN "0000" =>  RETURN '0';                  -- BN   : Never
      WHEN "0001" =>  RETURN c.z;                  -- BE   : Equal
      WHEN "0010" =>  RETURN c.z OR (c.n XOR c.v); -- BLE  : Less or Equal
      WHEN "0011" =>  RETURN c.n XOR c.v;          -- BL   : Less
      WHEN "0100" =>  RETURN c.c OR c.z;     -- BLEU : Less or Equal, Unsigned
      WHEN "0101" =>  RETURN c.c;                  -- BCS  : Carry Set
      WHEN "0110" =>  RETURN c.n;                  -- BNEG : Negative
      WHEN "0111" =>  RETURN c.v;                  -- BVS  : Overflow Set
      WHEN "1000" =>  RETURN '1';                  -- BA   : Always
      WHEN "1001" =>  RETURN NOT c.z;              -- BNE  : Not Equal
      WHEN "1010" =>  RETURN NOT (c.z OR (c.n XOR c.v)); -- BG   : Greater
      WHEN "1011" =>  RETURN NOT (c.n XOR c.v);    -- BGE  : Greater or Equal
      WHEN "1100" =>  RETURN NOT (c.c OR c.z);     -- BGU  : Greater, Unsigned
      WHEN "1101" =>  RETURN NOT c.c;              -- BCC  : Carry Cleared
      WHEN "1110" =>  RETURN NOT c.n;              -- BPOS : Positive
      WHEN "1111" =>  RETURN NOT c.v;              -- BVC  : Overflow Clear
      WHEN OTHERS =>  RETURN 'X';
    END CASE;
  END FUNCTION icc_test;

  --------------------------------------
  -- Test des codes conditions flottants
  -- Pour sauts conditionnels FBfcc,
  FUNCTION fcc_test (
    c : uv2;
    t : uv4)
    RETURN std_logic IS
    VARIABLE u,l,g,e : std_logic;
  BEGIN
    e:=to_std_logic(c="00");                    -- = Equal
    l:=to_std_logic(c="01");                    -- < Less
    g:=to_std_logic(c="10");                    -- > Greater
    u:=to_std_logic(c="11");                    -- Unordered
    CASE t IS
      WHEN "0000" =>  RETURN '0';         -- FBN   : Never
      WHEN "0001" =>  RETURN u OR l OR g; -- FBNE  : Not Equal
      WHEN "0010" =>  RETURN l OR g;      -- FBLG  : Less or Greater
      WHEN "0011" =>  RETURN u OR l;      -- FBUL  : Unordered or Less
      WHEN "0100" =>  RETURN l;           -- FBL   : Less
      WHEN "0101" =>  RETURN u OR g;      -- FBUG  : Unordered or Greater
      WHEN "0110" =>  RETURN g;           -- FBG   : Greater
      WHEN "0111" =>  RETURN u;           -- FBU   : Unordered
      WHEN "1000" =>  RETURN '1';         -- FBA   : Always
      WHEN "1001" =>  RETURN e;           -- FBE   : Equal
      WHEN "1010" =>  RETURN u OR e;      -- FBUE  : Unordered or Equal
      WHEN "1011" =>  RETURN g OR e;      -- FBGE  : Greater or Equal
      WHEN "1100" =>  RETURN u OR g OR e; -- FBUGE : Unord. or Greater or Equal
      WHEN "1101" =>  RETURN l OR e;      -- FBLE  : Less or Equal
      WHEN "1110" =>  RETURN u OR l OR e; -- FBULE : Unordered or Less or Equal
      WHEN "1111" =>  RETURN l OR g OR e; -- FBO   : Ordered 
      WHEN OTHERS =>  RETURN 'X';
    END CASE;
  END FUNCTION fcc_test;
  
  --############################################################################
  
  --------------------------------------
  -- Vérifie l'alignement des LOAD/STORE
  FUNCTION align (
    s : unsigned(2 DOWNTO 0);   -- Sign/Size
    a : unsigned(2 DOWNTO 0))   -- Address
    RETURN boolean IS
  BEGIN
    IF s(1 DOWNTO 0)=SIZE_D THEN          -- Double
      RETURN a(0)='0' AND a(1)='0' AND a(2)='0';
    ELSIF s(1 DOWNTO 0)=SIZE_W THEN       -- Word
      RETURN a(0)='0' AND a(1)='0';
    ELSIF s(1 DOWNTO 0)=SIZE_H THEN       -- Half
      RETURN a(0)='0';
    ELSE                                  -- Byte
      RETURN true;
    END IF;
  END FUNCTION align;

  --------------------------------------
  -- Aiguillage bus LOAD
  -- Tailles 8/16/32bits et extensions de signe
  CONSTANT CX_32 : uv32 := (OTHERS => 'X');
  FUNCTION ld (
    s : unsigned(2 DOWNTO 0);   -- Sign/Sizen
    a : unsigned(1 DOWNTO 0);   -- Address
    d : unsigned(31 DOWNTO 0))  -- Data
    RETURN unsigned IS
  BEGIN
    IF s=LDST_UB THEN                  -- Unsigned Byte
      IF    a="00" THEN RETURN uext(d(31 DOWNTO 24),32);
      ELSIF a="01" THEN RETURN uext(d(23 DOWNTO 16),32);
      ELSIF a="10" THEN RETURN uext(d(15 DOWNTO 8),32);
      ELSIF a="11" THEN RETURN uext(d( 7 DOWNTO 0),32);
      ELSE              RETURN CX_32;
      END IF;
    ELSIF s=LDST_SB THEN                  -- Signed Byte
      IF    a="00" THEN RETURN sext(d(31 DOWNTO 24),32);
      ELSIF a="01" THEN RETURN sext(d(23 DOWNTO 16),32);
      ELSIF a="10" THEN RETURN sext(d(15 DOWNTO 8),32);
      ELSIF a="11" THEN RETURN sext(d( 7 DOWNTO 0),32);
      ELSE              RETURN CX_32;
      END IF;
    ELSIF s=LDST_UH THEN  
      IF    a(1)='0' THEN RETURN uext(d(31 DOWNTO 16),32);
      ELSIF a(1)='1' THEN RETURN uext(d(15 DOWNTO 0),32);
      ELSE                RETURN CX_32;
      END IF;
    ELSIF s=LDST_SH THEN                  -- Signed Half Word
      IF    a(1)='0' THEN RETURN sext(d(31 DOWNTO 16),32);
      ELSIF a(1)='1' THEN RETURN sext(d(15 DOWNTO 0),32);
      ELSE                RETURN CX_32;
      END IF;
    ELSE                                  -- Word
      RETURN d;
    END IF;
  END FUNCTION ld;
  
  --------------------------------------
  -- Aiguillage bus STORE
  FUNCTION st (
    s : unsigned(2 DOWNTO 0);   -- Sign/Size
    r : unsigned(31 DOWNTO 0))  -- Register
    RETURN unsigned IS
  BEGIN
    IF s(1 DOWNTO 0)=SIZE_W OR s(1 DOWNTO 0)=SIZE_D THEN  -- Word
      RETURN r;
    ELSIF s(1 DOWNTO 0)=SIZE_H THEN                       -- Half
      RETURN r(15 DOWNTO 0) & r(15 DOWNTO 0);
    ELSE --IF s(1 DOWNTO 0)=SIZE_B THEN                   -- Byte
      RETURN r(7 DOWNTO 0) & r(7 DOWNTO 0) & r(7 DOWNTO 0) & r(7 DOWNTO 0);
    END IF;
  END FUNCTION st;
  
  --------------------------------------
  -- Sélection Byte Enable
  FUNCTION ldst_be (
    s : unsigned(2 DOWNTO 0);  -- Sign/Size
    a : unsigned(1 DOWNTO 0))  -- Address
    RETURN unsigned IS
  BEGIN
    IF s(1 DOWNTO 0)=SIZE_W OR s(1 DOWNTO 0)=SIZE_D THEN  -- Word
      RETURN "1111";
    ELSIF s(1 DOWNTO 0)=SIZE_H THEN           -- Half
      IF a(1)='0' THEN
        RETURN "1100";
      ELSE
        RETURN "0011";
      END IF;
    ELSE --IF s(1 DOWNTO 0)=SIZE_B THEN       -- Byte
      IF a="00"    THEN RETURN "1000";
      ELSIF a="01" THEN RETURN "0100";
      ELSIF a="10" THEN RETURN "0010";
      ELSIF a="11" THEN RETURN "0001";
      ELSE              RETURN "XXXX";
      END IF;
    END IF;
  END FUNCTION ldst_be;
  
  --------------------------------------
  -- Initialise le bus PLOMB pour une lecture
  FUNCTION plomb_rd (
    a   : uv32;                 -- Adresse
    asi : uv8;                  -- ASI
    s   : unsigned(2 DOWNTO 0)) -- Sign/Size
    RETURN type_plomb_w IS
      VARIABLE v : type_plomb_w;
  BEGIN
    v.a:=a;
    v.ah:=x"0";
    v.asi:=asi;
    v.d:=(OTHERS => 'X');
    v.be:=ldst_be(s,a(1 DOWNTO 0));
    v.mode:=PB_MODE_RD;
    v.burst:=PB_SINGLE;
    v.cont:='0';
    v.cache:='0';
    v.lock:='0';
    v.req:='0';                         -- Initialisé ailleurs
    v.dack:='0';                        -- Initialisé ailleurs
    RETURN v;
  END FUNCTION plomb_rd;

  --------------------------------------
  -- Initialise le bus PLOMB pour une écriture
  FUNCTION plomb_wr (
    a   : uv32;                 -- Adresse
    asi : uv8;                  -- ASI
    s   : unsigned(2 DOWNTO 0); -- Sign/Size
    d   : uv32)
    RETURN type_plomb_w IS
      VARIABLE v : type_plomb_w;
  BEGIN
    v.a:=a;
    v.ah:=x"0";
    v.asi:=asi;
    v.d:=st(s,d);
    v.be:=ldst_be(s,a(1 DOWNTO 0));
    v.mode:=PB_MODE_WR_ACK;
    v.burst:=PB_SINGLE;
    v.cont:='0';
    v.cache:='0';
    v.lock:='0';
    v.req:='0';                         -- Initialisé ailleurs
    v.dack:='0';                        -- Initialisé ailleurs
    RETURN v;
  END FUNCTION plomb_wr;
  --------------------------------------
  
-- <TT_INST_ACCESS_ERROR>
-- A peremptory error exception occurred on an instruction access
-- (for example, a parity error on an instruction cache access).

-- <TT_INST_ACCESS_EXCEPTION>
-- A blocking error exception occurred on an instruction access
-- (for example, an MMU indicated that the page was invalid or read-protected).

-- <TT_DATA_ACCESS_ERROR>
-- A peremptory error exception occurred on a load/store data access from/TO
-- memory (for example, a parity error on a data cache access, or an
-- uncorrectable ECC memory error).

-- <TT_DATA_ACCESS_EXCEPTION>
-- A blocking error exception occurred on a load/store data access.
-- (for example, an MMU indicated that the page was invalid or write-protected).

  --------------------------------------
  -- Conversion code PLOMB --> trap SPARC
  FUNCTION plomb_trap_inst(t : enum_plomb_code) RETURN type_trap IS
  BEGIN
    CASE t IS
      WHEN PB_OK =>
        RETURN TT_NONE;
      WHEN PB_ERROR =>
        RETURN TT_INST_ACCESS_ERROR;
      WHEN PB_FAULT =>
        RETURN TT_INST_ACCESS_EXCEPTION;
      WHEN PB_SPEC =>
        RETURN TT_NONE;
    END CASE;
  END FUNCTION plomb_trap_inst;

  FUNCTION plomb_trap_data(t : enum_plomb_code) RETURN type_trap IS
  BEGIN
    CASE t IS
      WHEN PB_OK =>
        RETURN TT_NONE;
      WHEN PB_ERROR =>
        RETURN TT_DATA_ACCESS_ERROR;
      WHEN PB_FAULT =>
        RETURN TT_DATA_ACCESS_EXCEPTION;
      WHEN PB_SPEC =>
        RETURN TT_NONE;
    END CASE;
  END FUNCTION plomb_trap_data;

  --############################################################################

  CONSTANT CAT_LOAD : type_cat := (op=>x"00000000",
    mode =>LOAD,priv=>'0',sub=>'0',size=>LDST_UW,
    m_reg=>'1',m_ry=>'0',
    m_psr=>'0',m_psr_icc=>'0',m_psr_cwp=>'0',m_psr_s=>'0',
    m_wim=>'0',m_tbr=>'0',r_reg=>"XXX",r_ry=>'0',r_psr_icc=>'0',r_fcc=>'0');
  
  CONSTANT CAT_FPLOAD : type_cat := (op=>x"00000000",
    mode =>FPLOAD,priv=>'0',sub=>'0',size=>LDST_UW,
    m_reg=>'0',m_ry=>'0',
    m_psr=>'0',m_psr_icc=>'0',m_psr_cwp=>'0',m_psr_s=>'0',
    m_wim=>'0',m_tbr=>'0',r_reg=>"XXX",r_ry=>'0',r_psr_icc=>'0',r_fcc=>'0');
  
  CONSTANT CAT_STORE : type_cat := (op=>x"00000000",
    mode =>STORE,priv=>'0',sub=>'0',size=>LDST_UW,
    m_reg=>'0',m_ry=>'0',
    m_psr=>'0',m_psr_icc=>'0',m_psr_cwp=>'0',m_psr_s=>'0',
    m_wim=>'0',m_tbr=>'0',r_reg=>"XXX",r_ry=>'0',r_psr_icc=>'0',r_fcc=>'0');
  
  CONSTANT CAT_FPSTORE : type_cat := (op=>x"00000000",
    mode =>FPSTORE,priv=>'0',sub=>'0',size=>LDST_UW,
    m_reg=>'0',m_ry=>'0',
    m_psr=>'0',m_psr_icc=>'0',m_psr_cwp=>'0',m_psr_s=>'0',
    m_wim=>'0',m_tbr=>'0',r_reg=>"XXX",r_ry=>'0',r_psr_icc=>'0',r_fcc=>'0');

  CONSTANT CAT_LOAD_STORE : type_cat := (op=>x"00000000",
    mode =>LOAD_STORE,priv=>'0',sub=>'0',size=>LDST_UW,
    m_reg=>'0',m_ry=>'0',
    m_psr=>'0',m_psr_icc=>'0',m_psr_cwp=>'0',m_psr_s=>'0',
    m_wim=>'0',m_tbr=>'0',r_reg=>"XXX",r_ry=>'0',r_psr_icc=>'0',r_fcc=>'0');
  
  CONSTANT CAT_JMPL : type_cat := (op=>x"00000000",
    mode =>JMPL,priv=>'0',sub=>'0',size=>LDST_UW,
    m_reg=>'1',m_ry=>'0',
    m_psr=>'0',m_psr_icc=>'0',m_psr_cwp=>'0',m_psr_s=>'0',
    m_wim=>'0',m_tbr=>'0',r_reg=>"XXX",r_ry=>'0',r_psr_icc=>'0',r_fcc=>'0');
  
  CONSTANT CAT_RETT : type_cat := (op=>x"00000000",
    mode =>JMPL,priv=>'1',sub=>'0',size=>LDST_UW,
    m_reg=>'0',m_ry=>'0',
    m_psr=>'0',m_psr_icc=>'0',m_psr_cwp=>'1',m_psr_s=>'1',
    m_wim=>'0',m_tbr=>'0',r_reg=>"XXX",r_ry=>'0',r_psr_icc=>'0',r_fcc=>'0');

  CONSTANT CAT_TICC : type_cat := (op=>x"00000000",
    mode =>CALC,priv=>'0',sub=>'0',size=>LDST_UW,
    m_reg=>'0',m_ry=>'0',
    m_psr=>'0',m_psr_icc=>'0',m_psr_cwp=>'0',m_psr_s=>'0',
    m_wim=>'0',m_tbr=>'0',r_reg=>"XXX",r_ry=>'0',r_psr_icc=>'1',r_fcc=>'0');
  
  CONSTANT CAT_MULDIV : type_cat := (op=>x"00000000",
    mode =>MULDIV,priv=>'0',sub=>'0',size=>LDST_UW,
    m_reg=>'1',m_ry=>'1',
    m_psr=>'0',m_psr_icc=>'0',m_psr_cwp=>'0',m_psr_s=>'0',
    m_wim=>'0',m_tbr=>'0',r_reg=>"XXX",r_ry=>'0',r_psr_icc=>'0',r_fcc=>'0');
  
  CONSTANT CAT_BRANCH : type_cat := (op=>x"00000000",
    mode =>BRANCH,priv=>'0',sub=>'0',size=>LDST_UW,
    m_reg=>'0',m_ry=>'0',
    m_psr=>'0',m_psr_icc=>'0',m_psr_cwp=>'0',m_psr_s=>'0',
    m_wim=>'0',m_tbr=>'0',r_reg=>"XXX",r_ry=>'0',r_psr_icc=>'X',r_fcc=>'X');
  
  CONSTANT CAT_FPU : type_cat := (op=>x"00000000", -- FPU calc, comparaisons
    mode =>FPCALC,priv=>'0',sub=>'0',size=>LDST_UW,
    m_reg=>'0',m_ry=>'0',
    m_psr=>'0',m_psr_icc=>'0',m_psr_cwp=>'0',m_psr_s=>'0',
    m_wim=>'0',m_tbr=>'0',r_reg=>"000",r_ry=>'0',r_psr_icc=>'0',r_fcc=>'0');
  
  --------------------------------------
  -- Grand Décodage Universel
  PROCEDURE decode (
    CONSTANT op         : IN  uv32;
    CONSTANT IFLUSH     : IN  boolean;
    CONSTANT CASA       : IN  boolean;
    VARIABLE cat_o      : OUT type_cat;
    VARIABLE n_rd_o     : OUT uint5;
    VARIABLE n_rs1_o    : OUT uint5;
    VARIABLE n_rs2_o    : OUT uint5) IS
    ALIAS op_op  : unsigned(31 DOWNTO 30) IS op(31 DOWNTO 30);
    ALIAS op_op2 : unsigned(24 DOWNTO 22) IS op(24 DOWNTO 22);
    ALIAS op_op3 : unsigned(24 DOWNTO 19) IS op(24 DOWNTO 19);
    ALIAS op_rd  : unsigned(29 DOWNTO 25) IS op(29 DOWNTO 25);
    ALIAS op_rs1 : unsigned(18 DOWNTO 14) IS op(18 DOWNTO 14);
    ALIAS op_rs2 : unsigned(4 DOWNTO 0)   IS op(4 DOWNTO 0);
    ALIAS op_imm : std_logic IS op(13);
    ALIAS op_fpu : unsigned(13 DOWNTO 5)  IS op(13 DOWNTO 5);
    VARIABLE use_rs1,use_rs2 : std_logic;
  BEGIN
    ----------------
    cat_o:=CAT_ALU;
    n_rd_o:=to_integer(op_rd);
    n_rs1_o:=to_integer(op_rs1);
    n_rs2_o:=to_integer(op_rs2);
    
    use_rs1:='1'; --NOT test (op.rs1,"00000");
    use_rs2:=NOT op_imm; -- NOT test (op.rs2,"00000") AND NOT op.i;
    ----------------
    
    CASE op_op IS
      WHEN "00" =>
        CASE op_op2 IS
          WHEN "000" =>       -- UNIMP : Unimplemented instruction
            cat_o:=CAT_ALU;
            
          WHEN "001" =>
            -- SparcV9 BPcc : Integer Condi. Branch with Prediction
            cat_o:=CAT_ALU;
            
          WHEN "010" =>       -- Bicc : Integer Condi. Branch
            cat_o:=CAT_BRANCH;
            cat_o.r_psr_icc:='1';
            cat_o.r_fcc:='0';
            cat_o.r_reg:="000";
            
          WHEN "011" =>       -- SparcV9 : BPr
            cat_o:=CAT_ALU;
            
          WHEN "100" =>       -- SETHI : Set High 22 bits of REGISTER
            cat_o:=CAT_ALU;
            cat_o.r_reg:="000";
            
          WHEN "101" =>
            -- SparcV9 FBPfcc : Floating Point Condi. Branch with Prediction
            cat_o:=CAT_ALU;
            
          WHEN "110" =>       -- FBfcc : Floating Point Condi. Branch
            cat_o:=CAT_BRANCH;
            cat_o.r_psr_icc:='0';
            cat_o.r_fcc:='1';
            cat_o.r_reg:="000";
            
          WHEN "111" =>       -- CBccc : Coprocessor Condi. Branch
            cat_o:=CAT_ALU;
            
          WHEN OTHERS =>
            cat_o:=CAT_ALU;

        END CASE;
      WHEN "01" =>               -- CALL
        cat_o:=CAT_BRANCH;
        cat_o.r_psr_icc:='0';
        cat_o.r_fcc:='0';
        cat_o.r_reg:="000";
        cat_o.m_reg:='1';
        n_rd_o:=15;   -- R15=O7 fixé comme adresse de retour de sous-programme
        
      WHEN "10" =>               -- Arith/Logic/FPU
        CASE op_op3 IS
          WHEN "000000" |                   -- ADD
               "000001" |                   -- AND
               "000010" |                   -- OR
               "000011" =>                  -- XOR
            cat_o:=CAT_ALU;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';

          WHEN "000100" |                   -- SUB
               "000101" |                   -- ANDN
               "000110" |                   -- ORN
               "000111" =>                  -- XNOR
            cat_o:=CAT_ALU;
            cat_o.sub:='1';
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            
          WHEN "001000" =>                  -- ADDX
            cat_o:=CAT_ALU;
            cat_o.r_psr_icc:='1';
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            
          WHEN "001001" =>                  -- SparcV9 : Multiply
            cat_o:=CAT_ALU;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            
          WHEN "001010" |                   -- UMUL
               "001011" =>                  -- SMUL
            cat_o:=CAT_MULDIV;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            
          WHEN "001100" =>                  -- SUBX
            cat_o:=CAT_ALU;
            cat_o.sub:='1';
            cat_o.r_psr_icc:='1';
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            
          WHEN "001101" =>                  -- Sparc V9 : Divide
            cat_o:=CAT_ALU;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            
          WHEN "001110" |                   -- UDIV
               "001111" =>                  -- SDIV
            cat_o:=CAT_MULDIV;
            cat_o.r_ry:='1';
            cat_o.m_ry:='0';
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            
          WHEN "010000" |                   -- ADDcc
               "010001" |                   -- ANDcc
               "010010" |                   -- ORcc
               "010011" =>                  -- XORcc
            cat_o:=CAT_ALU;
            cat_o.m_psr_icc:='1';
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            
          WHEN "010100" |                   -- SUBcc
               "010101" |                   -- ANDNcc
               "010110" |                   -- ORNcc
               "010111" =>                  -- XNORcc
            cat_o:=CAT_ALU;
            cat_o.sub:='1';
            cat_o.m_psr_icc:='1';
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            
          WHEN "011000" =>                  -- ADDXcc
            cat_o:=CAT_ALU;
            cat_o.m_psr_icc:='1';
            cat_o.r_psr_icc:='1';
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            
          WHEN "011001" =>                  -- Invalide
            cat_o:=CAT_ALU;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            
          WHEN "011010" |                   -- UMULcc
               "011011" =>                  -- SMULcc
            cat_o:=CAT_MULDIV;
            cat_o.m_psr_icc:='1';
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            
          WHEN "011100" =>                  -- SUBXcc
            cat_o:=CAT_ALU;
            cat_o.sub:='1';
            cat_o.m_psr_icc:='1';
            cat_o.r_psr_icc:='1';
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            
          WHEN "011101" =>                  -- Sparc V8E : DIVScc
            cat_o:=CAT_ALU;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            
          WHEN "011110" |                   -- UDIVcc
               "011111" =>                  -- SDIVcc
            cat_o:=CAT_MULDIV;
            cat_o.r_ry:='1';
            cat_o.m_ry:='0';
            cat_o.m_psr_icc:='1';
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            
          WHEN "100000" |                   -- TADDcc
               "100010" =>                  -- TADDccTV
            cat_o:=CAT_ALU;
            cat_o.m_psr_icc:='1';
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            
          WHEN "100001" |                   -- TSUBcc
               "100011" =>                  -- TSUBccTV
            cat_o:=CAT_ALU;
            cat_o.sub:='1';
            cat_o.m_psr_icc:='1';
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            
          WHEN "100100" =>                  -- MULScc : Multiply Step
            cat_o:=CAT_ALU;
            cat_o.m_psr_icc:='1';
            cat_o.r_psr_icc:='1';
            cat_o.m_ry:='1';
            cat_o.r_ry:='1';
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.sub:='1';             -- Opt
            
          WHEN "100101" =>                  -- SLL
            cat_o:=CAT_ALU;
            cat_o.sub:='1';
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            
          WHEN "100110" =>                  -- SRL
            cat_o:=CAT_ALU;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            
          WHEN "100111" =>                  -- SRA
            cat_o:=CAT_ALU;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            
          WHEN "101000" =>                  -- RDY
            cat_o:=CAT_ALU;
            cat_o.r_reg:="000";
            cat_o.r_ry:='1';
            
          WHEN "101001" =>                  -- RDPSR (PRIV)
            cat_o:=CAT_ALU;
            cat_o.priv:='1'; -- Privilegied
            cat_o.r_reg:="000";
            cat_o.r_psr_icc:='1';
            
          WHEN "101010" =>                  -- RDWIM (PRIV)
            cat_o:=CAT_ALU;
            cat_o.priv:='1'; -- Privilegied
            cat_o.r_reg:="000";

          WHEN "101011" =>                  -- RDTBR (PRIV)      
            cat_o:=CAT_ALU;
            cat_o.priv:='1'; -- Privilegied
            cat_o.r_reg:="000";

          WHEN "101100" |   -- Sparc V9 : Move Integer Condition
               "101101" |   -- Sparc V9 : Signed Divide 64bits
               "101110" |   -- Sparc V9 : Population Count
               "101111" =>  -- Sparc V9 : Move Integer Condition
            cat_o:=CAT_ALU;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            
          WHEN "110000" =>                  -- WRASR/WRY
            cat_o:=CAT_ALU;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.m_reg:='0';
            cat_o.m_ry:='1';
            
          WHEN "110001" =>                  -- WRPSR (PRIV)
            cat_o:=CAT_ALU;
            cat_o.priv:='1'; -- Privilegied
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.m_reg:='0';
            cat_o.m_psr:='1';

          WHEN "110010" =>                  -- WRWIM (PRIV)
            cat_o:=CAT_ALU;
            cat_o.priv:='1'; -- Privilegied
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.m_reg:='0';
            cat_o.m_wim:='1';

          WHEN "110011" =>                  -- WRTBR (PRIV)
            cat_o:=CAT_ALU;
            cat_o.priv:='1'; -- Privilegied
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.m_reg:='0';
            cat_o.m_tbr:='1';
            
          WHEN "110100" =>                  -- FPOP1
            cat_o:=CAT_FPU;
            cat_o.sub:='1';             -- Opt
            
          WHEN "110101" =>                  -- FPOP2 (FCMP)
            cat_o:=CAT_FPU;
            cat_o.sub:='1';             -- Opt
            
          WHEN "110110" |                   -- CPOP1
               "110111" =>                  -- CPOP2
            cat_o:=CAT_ALU;

          WHEN "111000" =>                  -- JMPL : Jump And Link
            cat_o:=CAT_JMPL;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            
          WHEN "111001" =>                  -- RETT (PRIV)
            cat_o:=CAT_RETT;
            cat_o.priv:='1'; -- Privilegied
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            
          WHEN "111010" =>                  -- Ticc (B.27)
            cat_o:=CAT_TICC;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            
          WHEN "111011" =>                  -- IFLUSH
            IF IFLUSH THEN
              cat_o:=CAT_STORE;
              cat_o.r_reg:=use_rs1 & use_rs2 & '0';
              cat_o.size :=LDST_UW;
            ELSE
              cat_o:=CAT_ALU;
              cat_o.r_reg:=use_rs1 & use_rs2 & '0';
              cat_o.size :=LDST_UW;
            END IF;
            
          WHEN "111100" |                   -- SAVE (B.20)
               "111101" =>                  -- RESTORE (B.20)
            cat_o:=CAT_ALU;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.m_psr_cwp:='1';
            
          WHEN "111110" |                   -- Invalide <INVALID>
               "111111" =>                  -- Invalide <INVALID>
            cat_o:=CAT_ALU;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.m_psr_cwp:='1';
            
          WHEN OTHERS => NULL;
        END CASE;
        
      WHEN "11" => -- Load/Store
        CASE op_op3 IS
            ----------------------------
          WHEN "000000" => -- LD : Load Word
            cat_o:=CAT_LOAD;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_UW;
            
          WHEN "000001" => -- LDUB : Load Unsigned Byte
            cat_o:=CAT_LOAD;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_UB;
            
          WHEN "000010" => -- LDUH : Load Unsigned Half Word
            cat_o:=CAT_LOAD;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_UH;
            
          WHEN "000011" => -- LDD : Load DoubleWord
            cat_o:=CAT_LOAD;
            cat_o.mode :=LOAD_DOUBLE;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_UD;
            ----------------------------
          WHEN "000100" => -- ST
            cat_o:=CAT_STORE;
            cat_o.r_reg:=use_rs1 & use_rs2 & '1';
            cat_o.size :=LDST_UW;
            
          WHEN "000101" => -- STB
            cat_o:=CAT_STORE;
            cat_o.r_reg:=use_rs1 & use_rs2 & '1';
            cat_o.size :=LDST_UB;
            
          WHEN "000110" => -- STH
            cat_o:=CAT_STORE;
            cat_o.r_reg:=use_rs1 & use_rs2 & '1';
            cat_o.size :=LDST_UH;

          WHEN "000111" => -- STD
            cat_o:=CAT_STORE;
            cat_o.mode:=STORE_DOUBLE;
            cat_o.r_reg:=use_rs1 & use_rs2 & '1';
            cat_o.size :=LDST_UD;
            ----------------------------
          WHEN "001000" | -- SparcV9 : LDSW : Load Signed Word <INVALID>
               "101000" => -- <INVALID>
            cat_o:=CAT_LOAD;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_SW;
            
          WHEN "001001" | -- LDSB : Load Signed Byte
               "101001" => -- <INVALID>
            cat_o:=CAT_LOAD;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_SB;
            
          WHEN "001010" | -- LDSH : Load Signed Half Word
               "101010" => -- <INVALID>
            cat_o:=CAT_LOAD;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_SH;
            
          WHEN "001011" | -- SparcV9 : LDX : Load Extended Word <INVALID>
               "101011" => -- <INVALID>
            cat_o:=CAT_LOAD;
            cat_o.mode:=LOAD_DOUBLE;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_SD;
            ----------------------------
          WHEN "001100" | -- Invalide <INVALID>
               "101100" => -- <INVALID>
            cat_o:=CAT_LOAD_STORE;
            cat_o.r_reg:=use_rs1 & use_rs2 & '1';
            cat_o.size :=LDST_UB;
            
          WHEN "001101" | -- LDSTUB : Atomic Load/Store Unsigned Byte
               "101101" => -- SparcV9 : PREFETCH <INVALID>
            cat_o:=CAT_LOAD_STORE;
            cat_o.r_reg:=use_rs1 & use_rs2 & '1';
            cat_o.size :=LDST_UB;
            
          WHEN "001110" | -- SparcV9 : STX : Store Extended Word <INVALID>
               "101110" => -- <INVALID>
            cat_o:=CAT_LOAD_STORE;
            cat_o.r_reg:=use_rs1 & use_rs2 & '1';
            cat_o.size :=LDST_UW;
            
          WHEN "001111" | -- SWAP : Swap register with Memory
               "101111" => -- <INVALID>
            cat_o:=CAT_LOAD_STORE;
            cat_o.r_reg:=use_rs1 & use_rs2 & '1';
            cat_o.size :=LDST_UW;
            ----------------------------
          WHEN "010000" => -- LDA : Load Word from Alternate Space (PRIV)
            cat_o:=CAT_LOAD;
            cat_o.priv:='1'; -- Privilegied
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_UW;
            
          WHEN "010001" => -- LDUBA : Load Unsigned Byte from Alt. Space (PRIV)
            cat_o:=CAT_LOAD;
            cat_o.priv:='1'; -- Privilegied
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_UB;
            
          WHEN "010010" => -- LDUHA : Load Uns. HalfWord from Alt. Space (PRIV)
            cat_o:=CAT_LOAD;
            cat_o.priv:='1'; -- Privilegied
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_UH;
            
          WHEN "010011" => -- LDDA : Load Double Word from Alt. Space (PRIV)
            cat_o:=CAT_LOAD;
            cat_o.priv:='1'; -- Privilegied
            cat_o.mode:=LOAD_DOUBLE;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_UD;
            ----------------------------
          WHEN "010100" => -- STA : Store Word into Alt. Space (PRIV)
            cat_o:=CAT_STORE;
            cat_o.priv:='1'; -- Privilegied
            cat_o.r_reg:=use_rs1 & use_rs2 & '1';
            cat_o.size :=LDST_UW;
            
          WHEN "010101" => -- STBA : Store Byte into Alt. Space (PRIV)
            cat_o:=CAT_STORE;
            cat_o.priv:='1'; -- Privilegied
            cat_o.r_reg:=use_rs1 & use_rs2 & '1';
            cat_o.size :=LDST_UB;
            
          WHEN "010110" =>  -- STHA : Store Half Word into Alt. Space (PRIV)
            cat_o:=CAT_STORE;
            cat_o.priv:='1'; -- Privilegied
            cat_o.r_reg:=use_rs1 & use_rs2 & '1';
            cat_o.size :=LDST_UH;
            
          WHEN "010111" => -- STDA : Store DoubleWord into Alt. Space (PRIV)
            cat_o:=CAT_STORE;
            cat_o.priv:='1'; -- Privilegied
            cat_o.mode:=STORE_DOUBLE;
            cat_o.r_reg:=use_rs1 & use_rs2 & '1';
            cat_o.size :=LDST_UD;
            ----------------------------
          WHEN "011000" | -- SparcV9 : LDSWA : Load Signed Word into Alt. Space
               "111000" => -- <INVALID>
            -- On pourrait copier LDA
            cat_o:=CAT_LOAD; -- <INVALID>
            cat_o.priv:='1'; -- Privilegied
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_SW;
            
          WHEN "011001" | -- LDSBA : Load Signed Byte from Alt. Space (PRIV)
               "111001" => -- <INVALID>
            cat_o:=CAT_LOAD;
            cat_o.priv:='1'; -- Privilegied
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_SB;
            
          WHEN "011010" | -- LDSHA : Load Sig. Half Word from Alt. Space (PRIV)
               "111010" => -- <INVALID>
            cat_o:=CAT_LOAD;
            cat_o.priv:='1'; -- Privilegied
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_SH;
            
          WHEN "011011" | -- SparcV9 : LDXA : Load Ext Word from Alt. Space <INVALID>
               "111011" => -- <INVALID>
            cat_o:=CAT_LOAD;
            cat_o.priv:='1'; -- Privilegied
            cat_o.mode:=LOAD_DOUBLE;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_SD;
            ----------------------------
          WHEN "011100" | -- Invalide <INVALID>
               "111100" => -- SparcV9 & LEON : CASA
            cat_o:=CAT_LOAD_STORE;
            cat_o.priv:='1'; -- Privilegied
            cat_o.r_reg:=use_rs1 & use_rs2 & '1';
            IF CASA THEN
              cat_o.priv:=to_std_logic(op(12 DOWNTO 5)/=ASI_USER_DATA);
            END IF;
            cat_o.size :=LDST_UW;

          WHEN "011101" | -- LDSTUBA : Atomic Load/Store Uns. Byte in Alt. Space (PRIV)
               "111101" => -- SparcV9 : PREFETCHA <INVALID>
            cat_o:=CAT_LOAD_STORE;
            cat_o.priv:='1'; -- Privilegied
            cat_o.r_reg:=use_rs1 & use_rs2 & '1';
            cat_o.size :=LDST_UB;
            
          WHEN "011110" | -- SparcV9 : STXA :Store Ext. Word from Alt. <INVALID>
               "111110" => -- SparcV9 : CASXA <INVALID>
            cat_o:=CAT_LOAD_STORE;
            cat_o.priv:='1'; -- Privilegied
            cat_o.r_reg:=use_rs1 & use_rs2 & '1';
            cat_o.size :=LDST_UW;
            
          WHEN "011111" | -- SWAPA : Swap reg. with mem. in Alt. Space (PRIV)
               "111111" => -- <INVALID>
            cat_o:=CAT_LOAD_STORE;
            cat_o.priv:='1'; -- Privilegied
            cat_o.r_reg:=use_rs1 & use_rs2 & '1';
            cat_o.size :=LDST_UW;
            ----------------------------
          WHEN "100000" => -- LDF : Load Floating Point
            cat_o:=CAT_FPLOAD;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_UW;
            
          WHEN "100001" => -- LDFSR : Load Floating Point State Register
            cat_o:=CAT_FPLOAD;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_UW;
            
          WHEN "100010" => -- SparcV9 : LDQF : Load Quad Floating Pnt <INVALID>
            cat_o:=CAT_FPLOAD;
            cat_o.mode:=FPLOAD_DOUBLE;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_UD;
            
          WHEN "100011" => -- LDDF : Load Double Floating Point
            cat_o:=CAT_FPLOAD;
            cat_o.mode:=FPLOAD_DOUBLE;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_UD;
            ----------------------------
          WHEN "100100" => -- STF : Store Floating Point
            cat_o:=CAT_FPSTORE;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_UW;
            
          WHEN "100101" => -- STFSR : Store Floating Point State Register
            cat_o:=CAT_FPSTORE;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_UW;
            
          WHEN "100110" => -- STDFQ : Store Double Floating Point Queue
            cat_o:=CAT_FPSTORE;
            cat_o.mode:=FPSTORE_DOUBLE;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_UD;
            
          WHEN "100111" => -- STDF : Store Double Floating Point
            cat_o:=CAT_FPSTORE;
            cat_o.mode:=FPSTORE_DOUBLE;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_UD;
            ----------------------------
            -- 101000 .. 101111 : Invalid
            ----------------------------
          WHEN "110000" => -- LDFA : V9 Load FP from Alt. Space [LDC]
            cat_o:=CAT_FPLOAD;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_UW;
            
          WHEN "110001" =>  --  LDFSRA Load FP State from Alt. State [LDCSR]
            cat_o:=CAT_FPLOAD;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_UW;

          WHEN "110010" => --  <INVALID> Coprocessor
            cat_o:=CAT_FPLOAD;
            cat_o.mode:=FPLOAD_DOUBLE;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_UD;
            
          WHEN "110011" => -- LDDFA : V9 Load Double FP from Alt. Space [LDDC]
            cat_o:=CAT_FPLOAD;
            cat_o.mode:=FPLOAD_DOUBLE;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_UD;
            ----------------------------
          WHEN "110100" => -- STFA : V9 Store FP from Alt. Space [STC]
            cat_o:=CAT_FPSTORE;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_UW;
            
           WHEN "110101" => -- "STFSRA" : Store FP state from Alt. Space [STCSR]
            cat_o:=CAT_FPSTORE;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_UW;
            
           WHEN "110110" => -- "STDFQA" : Store FP queue from Alt. State [STDCQ]
            cat_o:=CAT_FPSTORE;
            cat_o.mode:=FPSTORE_DOUBLE;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_UD;
            
           WHEN "110111" => -- STDFA : V9 Store Double FP from Alt. Space [STDC]
            cat_o:=CAT_FPSTORE;
            cat_o.mode:=FPSTORE_DOUBLE;
            cat_o.r_reg:=use_rs1 & use_rs2 & '0';
            cat_o.size :=LDST_UD;
            ----------------------------
            -- 111000 .. 111111 : Invalid
            ----------------------------
          WHEN OTHERS => NULL;
        END CASE;
        
      WHEN OTHERS =>
        cat_o:=CAT_ALU;
        
    END CASE;
    cat_o.op:=op;
    
  END PROCEDURE decode;
  
  --############################################################################
  
  --------------------------------------
  -- Troncature CWP selon NWINDOWS
  FUNCTION cwpfix (CONSTANT cwp      : IN unsigned(4 DOWNTO 0);
                   CONSTANT NWINDOWS : IN natural)
    RETURN unsigned IS
    VARIABLE v : unsigned(4 DOWNTO 0);
  BEGIN
    IF NWINDOWS<=4 THEN
      v:="000" & cwp(1 DOWNTO 0);
    ELSIF NWINDOWS<=8 THEN
      v:="00" & cwp(2 DOWNTO 0);
    ELSIF NWINDOWS<=16 THEN
      v:='0' & cwp(3 DOWNTO 0);
    ELSE
      v:=cwp;
    END IF;
    RETURN v;
  END FUNCTION cwpfix;

  --------------------------------------
  -- Calcul CWP
  FUNCTION cwpcalc (
    CONSTANT cwp       : IN unsigned(4 DOWNTO 0);
    CONSTANT m_psr_cwp : IN std_logic;
    CONSTANT trap      : IN std_logic;
    CONSTANT opcode    : IN uv32;
    CONSTANT NWINDOWS  : IN natural) RETURN unsigned IS
    VARIABLE cwp_v     : unsigned(4 DOWNTO 0);
  BEGIN
    -- Anticipe le futur PSR.CWP
    IF m_psr_cwp='1' OR trap='1' THEN
      IF opcode(19)='0' OR trap='1' THEN
        -- SAVE ou Trap
        IF cwp=0 THEN
          cwp_v:=to_unsigned(NWINDOWS-1,5);
        ELSE
          cwp_v:=cwp-1;
        END IF;
        cwp_v:=cwpfix(cwp_v,NWINDOWS);
      ELSE
        -- RESTORE ou RETT
        IF cwp=NWINDOWS-1 THEN
          cwp_v:="00000";
        ELSE
          cwp_v:=cwp+1;
        END IF;
        cwp_v:=cwpfix(cwp_v,NWINDOWS);
      END IF;
    ELSE
      cwp_v:=cwp;
    END IF;
    RETURN cwp_v;
  END FUNCTION cwpcalc;
  
  --------------------------------------
  PROCEDURE shift (
    VARIABLE o   : OUT unsigned(31 DOWNTO 0);
    CONSTANT rs1 : IN unsigned(31 DOWNTO 0);
    CONSTANT rs2 : IN unsigned(4 DOWNTO 0);
    CONSTANT op  : IN unsigned(5 DOWNTO 0)) IS
    VARIABLE deca : natural RANGE 0 TO 64;
    VARIABLE vec,vec2 : unsigned(63 DOWNTO 0);
    VARIABLE dex : unsigned(4 DOWNTO 0);
  BEGIN
      --WHEN "100101" =>                  -- SLL
      --WHEN "100110" =>                  -- SRL
      --WHEN "100111" =>                  -- SRA
    dex:=rs2(4 DOWNTO 0);
    --IF op(1)='0' THEN -- Inversion par .sub
    --  dex:=NOT dex;
    --END IF;
    vec(63 DOWNTO 32):=(OTHERS => (rs1(31) AND op(0) AND op(1)));
    vec(31 DOWNTO 0):=rs1;
    vec2:=vec;
    IF dex(0)='1' THEN
      vec2:=vec2(0) & vec2(63 DOWNTO 1);
    END IF;
    IF dex(1)='1' THEN
      vec2:=vec2(1 DOWNTO 0) & vec2(63 DOWNTO 2);
    END IF;
    IF dex(2)='1' THEN
      vec2:=vec2(3 DOWNTO 0) & vec2(63 DOWNTO 4);
    END IF;
    IF dex(3)='1' THEN
      vec2:=vec2(7 DOWNTO 0) & vec2(63 DOWNTO 8);
    END IF;
    IF dex(4)='1' THEN
      vec2:=vec2(15 DOWNTO 0) & vec2(63 DOWNTO 16);
    END IF;
    
    IF op(1)='1' THEN
      -- Décalage à droite
      o:=vec2(31 DOWNTO 0);
    ELSE
      -- Décalage à gauche
      o:=vec2(0) & vec2(63 DOWNTO 33);
    END IF;

  END PROCEDURE shift;
  
  --------------------------------------
  -- Opérations arithmético/logiques
  PROCEDURE op_alu (
    CONSTANT cat         : IN  type_cat;
    CONSTANT pc          : IN  uv32;       -- Decode/Sauts
    VARIABLE npc_o       : OUT uv32;       -- Decode/Sauts
    VARIABLE npc_maj     : OUT std_logic;  -- Mise à jour de nPC pendant EXEC
    CONSTANT rs1         : IN  uv32;       -- Registre Source 1
    CONSTANT rs2         : IN  uv32;       -- Registre Source 2
    VARIABLE rd_o        : OUT uv32;       -- Registre Destination
    VARIABLE sum_o       : OUT uv32;
    CONSTANT ry          : IN  uv32;       -- Registre Y
    VARIABLE ry_o        : OUT uv32;       -- Registre Y
    CONSTANT psr         : IN  type_psr;
    VARIABLE psr_o       : OUT type_psr;
    CONSTANT muldiv_rd   : IN  uv32;
    CONSTANT muldiv_ry   : IN  uv32;
    CONSTANT muldiv_icc  : IN  type_icc;
    CONSTANT muldiv_dz   : IN  std_logic;
    CONSTANT cwp         : IN  unsigned(4 DOWNTO 0);
    CONSTANT wim         : IN  unsigned;
    CONSTANT tbr         : IN  type_tbr;
    VARIABLE trap_o      : OUT type_trap;
    CONSTANT MULDIV      : IN  boolean;
    CONSTANT IU_IMP_VERSION : IN uv8) IS
    VARIABLE rs2l        : uv32;
    VARIABLE shi,rd_ot   : uv32;
    VARIABLE t           : std_logic;
    VARIABLE psr_o_cwp   : unsigned(4 DOWNTO 0);
    VARIABLE addsub      : uv32;
    VARIABLE addsubx     : unsigned(32 DOWNTO 0);
    VARIABLE carry       : std_logic;
    VARIABLE op1,op2     : uv32;
    ALIAS op_op3  : unsigned(24 DOWNTO 19) IS cat.op(24 DOWNTO 19);
    ALIAS op_cond : unsigned(28 DOWNTO 25) IS cat.op(28 DOWNTO 25);
  BEGIN
    ----------------
    IF op_op3(24)='0' AND op_op3(22)='1' AND cat.op(30)='0' THEN
      -- ADDX, ADDXcc, SUBX, SUBXcc
      carry:=psr.icc.c;
    ELSE
      carry:='0';
    END IF;
    
    IF cat.sub='0' THEN
      --AND, ANDcc, OR, ORcc, XOR, XORcc, WRY, WRPSR, WRWIM, WRTBR
      rs2l:=rs2;
      addsubx:=(rs1 & '1') + (rs2l & carry);
    ELSE
      --ANDN, ANDNcc, ORN, ORNcc, XORN, XORNcc, SUB, SUBcc
      rs2l:=NOT rs2;
      addsubx:=(rs1 & '1') + (rs2l & NOT carry);
    END IF;
    
    addsub:=addsubx(32 DOWNTO 1);
    trap_o:=TT_NONE;
    ----------------
    shift(shi,rs1,rs2l(4 DOWNTO 0),op_op3);
    
    rd_ot:=addsub;                      -- Défaut
    psr_o:=psr;
    npc_maj:='0';
    npc_o:=addsub;
    psr_o.icc.v:='0';
    psr_o.icc.c:='0';
    ----------------
    
    CASE op_op3 IS
      WHEN "000000" |                   -- ADD
           "010000" |                   -- ADDcc
           "001000" |                   -- ADDX
           "011000" =>                  -- ADDXcc
        psr_o.icc.v:=(rs1(31) AND rs2l(31) AND NOT addsub(31)) OR
                      (NOT rs1(31) AND NOT rs2l(31) AND addsub(31));
        psr_o.icc.c:=(rs1(31) AND rs2(31)) OR
                      (NOT addsub(31) AND (rs1(31) OR rs2(31)));
        
      WHEN "000100" |                   -- SUB
           "010100" |                   -- SUBcc
           "001100" |                   -- SUBX
           "011100" =>                  -- SUBXcc
        psr_o.icc.v:=(rs1(31) AND rs2l(31) AND NOT addsub(31)) OR
                      (NOT rs1(31) AND NOT rs2l(31) AND addsub(31));
        psr_o.icc.c:=(NOT rs1(31) AND rs2(31)) OR
                      (addsub(31) AND (NOT rs1(31) OR rs2(31)));

      WHEN "000001" |                   -- AND
           "010001" |                   -- ANDcc
           "000101" |                   -- ANDN
           "010101" =>                  -- ANDNcc
        rd_ot:=rs1 AND rs2l;
        psr_o.icc.v:='0';
        psr_o.icc.c:='0';
        
      WHEN "000010" |                   -- OR
           "010010" |                   -- ORcc
           "000110" |                   -- ORN
           "010110" =>                  -- ORNcc
        rd_ot:=rs1 OR rs2l;
        psr_o.icc.v:='0';
        psr_o.icc.c:='0';
        
      WHEN "000011" |                   -- XOR
           "010011" |                   -- XORcc
           "000111" |                   -- XNOR
           "010111" =>                  -- XNORcc
        rd_ot:=rs1 XOR rs2l;
        psr_o.icc.v:='0';
        psr_o.icc.c:='0';        
        
      WHEN "001001" =>                  -- SparcV9 : Multiply
        trap_o:=TT_ILLEGAL_INSTRUCTION;

      WHEN "001010" |                   -- UMUL
           "001011" |                   -- SMUL
           "001110" |                   -- UDIV
           "001111" =>                  -- SDIV
        IF NOT MULDIV THEN
          trap_o:=TT_ILLEGAL_INSTRUCTION;
        ELSIF muldiv_dz='1' THEN
          trap_o:=TT_DIVISION_BY_ZERO;
        END IF;
        rd_ot:=muldiv_rd;
        psr_o.icc.v:=muldiv_icc.v;
        psr_o.icc.c:=muldiv_icc.c;
        
      WHEN "001101" =>                  -- Sparc V9 : Divide
        trap_o:=TT_ILLEGAL_INSTRUCTION;
        
      WHEN "011001" =>                  -- Invalide
        trap_o:=TT_ILLEGAL_INSTRUCTION;
        
      WHEN "011010" |                   -- UMULcc
           "011011" |                   -- SMULcc
           "011110" |                   -- UDIVcc
           "011111" =>                  -- SDIVcc
        IF NOT MULDIV THEN
          trap_o:=TT_ILLEGAL_INSTRUCTION;
        ELSIF muldiv_dz='1' THEN
          trap_o:=TT_DIVISION_BY_ZERO;
        END IF;
        rd_ot:=muldiv_rd;
        psr_o.icc.v:=muldiv_icc.v;
        psr_o.icc.c:=muldiv_icc.c;
        
      WHEN "011101" =>                  -- Sparc V8E : DIVScc
        trap_o:=TT_ILLEGAL_INSTRUCTION;
        -- <AFAIRE> : Coder le DIV séquentiel.
       
      WHEN "100000" =>                  -- TADDcc
        rd_ot:=addsub; --rs1 + rs2;
        psr_o.icc.v:=(rs1(31) AND rs2l(31) AND NOT addsub(31)) OR
                      (NOT rs1(31) AND NOT rs2l(31) AND addsub(31)) OR
                      (rs1(1) OR rs1(0) OR rs2(1) OR rs2(0));
        psr_o.icc.c:=(rs1(31) AND rs2(31)) OR
                      (NOT addsub(31) AND (rs1(31) OR rs2(31)));
        
      WHEN "100001" =>                  -- TSUBcc
        rd_ot:=addsub; --rs1 - rs2;
        psr_o.icc.v:=(rs1(31) AND rs2l(31) AND NOT addsub(31)) OR
                      (NOT rs1(31) AND NOT rs2l(31) AND addsub(31)) OR
                      (rs1(1) OR rs1(0) OR rs2(1) OR rs2(0));
        psr_o.icc.c:=(NOT rs1(31) AND rs2(31)) OR
                      (addsub(31) AND (NOT rs1(31) OR rs2(31)));
        
      WHEN "100010" =>                  -- TADDccTV
        rd_ot:=addsub; --rs1 + rs2;
        t:=(rs1(31) AND rs2l(31) AND NOT addsub(31)) OR
                      (NOT rs1(31) AND NOT rs2l(31) AND addsub(31)) OR
                      (rs1(1) OR rs1(0) OR rs2(1) OR rs2(0));
        psr_o.icc.v:=t;
        psr_o.icc.c:=(rs1(31) AND rs2(31)) OR (NOT addsub(31) AND
                                               (rs1(31) OR rs2(31)));
        IF t='1' THEN
          trap_o:=TT_TAG_OVERFLOW;
        END IF;
        
      WHEN "100011" =>                  -- TSUBccTV
        rd_ot:=addsub; --rs1 - rs2;
        t:=(rs1(31) AND rs2l(31) AND NOT addsub(31)) OR
                      (NOT rs1(31) AND NOT rs2l(31) AND addsub(31)) OR
                      (rs1(1) OR rs1(0) OR rs2(1) OR rs2(0));
        psr_o.icc.v:=t;
        psr_o.icc.c:=(NOT rs1(31) AND rs2(31)) OR (addsub(31) AND
                                                   (NOT rs1(31) OR rs2(31)));
        IF t='1' THEN
          trap_o:=TT_TAG_OVERFLOW;
        END IF;
        
      WHEN "100100" =>                  -- MULScc : Multiply Step
        op1:=(psr.icc.n XOR psr.icc.v) & rs1(31 DOWNTO 1);
        op2:=mux(ry(0),rs2,x"00000000");
        rd_ot:=op1 + op2;
        psr_o.icc.v:=(op1(31) AND op2(31) AND NOT rd_ot(31))
                OR (NOT op1(31) AND NOT op2(31) AND rd_ot(31));
        psr_o.icc.c:=(op1(31) AND op2(31)) OR
                  (NOT rd_ot(31) AND (op1(31) OR op2(31)));
        
      WHEN "100101" =>                  -- SLL
        rd_ot:=shi;
        
      WHEN "100110" =>                  -- SRL
        rd_ot:=shi;
        
      WHEN "100111" =>                  -- SRA
        rd_ot:=shi;
        
      WHEN "101000" =>                  -- RDY
        -- SparcV7 ne reconnait pas les registres ASR, il n'y a que le reg. Y
        rd_ot:=ry;
        
      WHEN "101001" =>                  -- RDPSR (PRIV)
        rd_ot:=rdpsr(psr,IU_IMP_VERSION);
        
      WHEN "101010" =>                  -- RDWIM (PRIV)
        rd_ot:=uext(wim,32);
        
      WHEN "101011" =>                  -- RDTBR (PRIV)      
        rd_ot:=tbr.tba & tbr.tt & "0000";
        
      WHEN "101100" =>                  -- Sparc V9 : Move Integer Condition
        trap_o:=TT_ILLEGAL_INSTRUCTION;
        
      WHEN "101101" =>                  -- Sparc V9 : Signed Divide 64bits
        trap_o:=TT_ILLEGAL_INSTRUCTION;
        
      WHEN "101110" |                   -- Sparc V9 : Population Count
           "101111" =>                  -- Sparc V9 : Move Integer Condition
        rd_ot:=muldiv_rd;
        trap_o:=TT_ILLEGAL_INSTRUCTION;
        
      WHEN "110000" =>                  -- WRASR/WRY
        -- SparcV7 ne reconnait pas les registres ASR, seulement le registre Y
        -- <AVOIR> WRY est un cas particulier, Y est aussi ecrit par les MUL/DIV
        rd_ot:=rs1 XOR rs2l;
        -- Copy TADDcc : Simplification decoder
        psr_o.icc.v:=(rs1(31) AND rs2l(31) AND NOT addsub(31)) OR
                      (NOT rs1(31) AND NOT rs2l(31) AND addsub(31)) OR
                      (rs1(1) OR rs1(0) OR rs2(1) OR rs2(0));
        psr_o.icc.c:=(rs1(31) AND rs2(31)) OR
                      (NOT addsub(31) AND (rs1(31) OR rs2(31)));
        
      WHEN "110001" =>                  -- WRPSR (PRIV)
        rd_ot:=rs1 XOR rs2l;
        -- Copy TSUBcc : Simplification decoder
        psr_o.icc.v:=(rs1(31) AND rs2l(31) AND NOT addsub(31)) OR
                      (NOT rs1(31) AND NOT rs2l(31) AND addsub(31)) OR
                      (rs1(1) OR rs1(0) OR rs2(1) OR rs2(0));
        psr_o.icc.c:=(NOT rs1(31) AND rs2(31)) OR
                      (addsub(31) AND (NOT rs1(31) OR rs2(31)));
        
      WHEN "110010" =>                  -- WRWIM (PRIV)
        rd_ot:=rs1 XOR rs2l;
        -- Copy TADDccTV
        t:=(rs1(31) AND rs2l(31) AND NOT addsub(31)) OR
                      (NOT rs1(31) AND NOT rs2l(31) AND addsub(31)) OR
                      (rs1(1) OR rs1(0) OR rs2(1) OR rs2(0));
        psr_o.icc.v:=t;
        psr_o.icc.c:=(rs1(31) AND rs2(31)) OR (NOT addsub(31) AND
                                               (rs1(31) OR rs2(31)));
        
      WHEN "110011" =>                  -- WRTBR (PRIV)
        rd_ot:=rs1 XOR rs2l;
        -- Copy TSUBccTV
        t:=(rs1(31) AND rs2l(31) AND NOT addsub(31)) OR
                      (NOT rs1(31) AND NOT rs2l(31) AND addsub(31)) OR
                      (rs1(1) OR rs1(0) OR rs2(1) OR rs2(0));
        psr_o.icc.v:=t;
        psr_o.icc.c:=(NOT rs1(31) AND rs2(31)) OR (addsub(31) AND
                                                   (NOT rs1(31) OR rs2(31)));
        
      WHEN "110100" =>                  -- FPOP1
        -- Remplacé par l'unité flottante. Copie MULSCC
        op1:=(psr.icc.n XOR psr.icc.v) & rs1(31 DOWNTO 1);
        op2:=mux(ry(0),rs2,x"00000000");
        rd_ot:=op1 + op2;
        psr_o.icc.v:=(op1(31) AND op2(31) AND NOT addsub(31))
                OR (NOT op1(31) AND NOT op2(31) AND addsub(31));
        psr_o.icc.c:=(op1(31) AND op2(31)) OR
                  (NOT addsub(31) AND (op1(31) OR op2(31)));
        
      WHEN "110101" =>                  -- FPOP2
        -- Remplacé par l'unité flottante. Copie SLL
        rd_ot:=shi;
        
      WHEN "110110" =>                  -- CPOP1. Invalide.
        rd_ot:=shi;
        trap_o:=TT_CP_DISABLED;

      WHEN "110111" =>                  -- CPOP2
        rd_ot:=shi;
        trap_o:=TT_CP_DISABLED;

      WHEN "111000" =>                  -- JMPL : Jump And Link
        rd_ot:=pc;
        npc_maj:='1';
        IF addsub(1 DOWNTO 0)/="00" THEN
          trap_o:=TT_MEM_ADDRESS_NOT_ALIGNED;
        END IF;
        -- Pour sortir d'un trap, il faut faire la séquence JMPL/RETT qui permet
        -- aussi de sortir du mode superviseur. Il faut tenir compte de l'effet
        -- du RETT sur la zone mémoire de retour (USER_CODE ou SUPER_CODE), donc
        -- interdire le préfetch après un JMPL.
        -- C'est du grand n'importe quoi ce truc.
        
      WHEN "111001" =>                  -- RETT (PRIV)
        psr_o_cwp:=cwp;
        psr_o.cwp:=psr_o_cwp;
        npc_maj:='1';
        -- <Le déclenchement de TRAP pendant un RETT est assez fumeux>
        IF addsub(1 DOWNTO 0)/="00" THEN
          trap_o:=TT_MEM_ADDRESS_NOT_ALIGNED;
        ELSIF wim(to_integer(psr_o_cwp))='1' THEN
          trap_o:=TT_WINDOW_UNDERFLOW;
        END IF;
        psr_o.s:=psr.ps;
        psr_o.et:='1';
        
      WHEN "111010" =>                  -- Ticc (B.27)
        IF icc_test(psr.icc,op_cond)='1' THEN
          trap_o.t:=TT_TRAP_INSTRUCTION.t;
          trap_o.tt:=TT_TRAP_INSTRUCTION.tt + uext(rd_ot(6 DOWNTO 0),8);
        END IF;
        -- <AFAIRE> Revoir sémantique, compatibilité SparcV9
        
      WHEN "111011" =>                  -- IFLUSH
        -- L'instruction IFLUSH est éventuellement gérée côté MDU
        trap_o:=TT_UNIMPLEMENTED_FLUSH;
        
      WHEN "111100" =>                  -- SAVE (B.20)
        psr_o_cwp:=cwp;
        psr_o.cwp:=psr_o_cwp;
        IF wim(to_integer(psr_o_cwp))='1' THEN
          trap_o:=TT_WINDOW_OVERFLOW;
        END IF;
        
      WHEN "111101" =>                  -- RESTORE (B.20)
        psr_o_cwp:=cwp;
        psr_o.cwp:=psr_o_cwp;
        IF wim(to_integer(psr_o_cwp))='1' THEN
          trap_o:=TT_WINDOW_UNDERFLOW;
        END IF;
        
      WHEN "111110" |                  -- Invalide
           "111111" =>                 -- Invalide
        rd_ot:=muldiv_rd;
        trap_o:=TT_ILLEGAL_INSTRUCTION;
      
      WHEN OTHERS => NULL;
    END CASE;

    sum_o:=addsub;
    rd_o:=rd_ot;
    psr_o.icc.n:=rd_ot(31);
    psr_o.icc.z:=to_std_logic(rd_ot=x"00000000");
    
    IF op_op3(24 DOWNTO 23)="00" THEN
      ry_o:=muldiv_ry;
    ELSIF op_op3(24 DOWNTO 23)="01" THEN
      ry_o:=muldiv_ry;
    ELSIF op_op3(24 DOWNTO 23)="10" THEN
      ry_o:=rs1(0) & ry(31 DOWNTO 1);
    ELSE
      ry_o:=rs1 XOR rs2l;
    END IF;
    
  END PROCEDURE op_alu;
  
  --------------------------------------
  -- Opérations multiplication/division pour simulation
  --pragma synthesis_off
  PROCEDURE op_mdu_sim (
    CONSTANT cat         : IN  type_cat;
    
    CONSTANT rs1         : IN  uv32;   -- Registre Source 1
    CONSTANT rs2         : IN  uv32;   -- Registre Source 2
    VARIABLE rd_o        : OUT uv32;   -- Registre Destination
    CONSTANT ry          : IN  uv32;   -- Registre Y
    VARIABLE ry_o        : OUT uv32;   -- Registre Y
    VARIABLE icc_o       : OUT type_icc;
    VARIABLE dz_o        : OUT std_logic) IS
    VARIABLE op1,op2 : uv32;
    VARIABLE rd_ot : uv32;
    VARIABLE t : std_logic;
    VARIABLE tmp64 : unsigned(63 DOWNTO 0);
    ALIAS op_op3 : unsigned(24 DOWNTO 19) IS cat.op(24 DOWNTO 19);
  BEGIN
    dz_o:='0';
    ----------------
    CASE op_op3 IS
      WHEN "001010" =>                  -- UMUL
        tmp64:=unsigned(unsigned(rs1) * unsigned(rs2));
        ry_o:=tmp64(63 DOWNTO 32);
        rd_ot:=tmp64(31 DOWNTO 0);
        
      WHEN "001011" =>                  -- SMUL
        tmp64:=unsigned(signed(rs1) * signed(rs2));
        ry_o:=tmp64(63 DOWNTO 32);
        rd_ot:=tmp64(31 DOWNTO 0);
        
      WHEN "001110" =>                  -- UDIV
        IF rs2=x"00000000" THEN
          dz_o:='1';
        ELSE
          tmp64:=unsigned(unsigned'(ry & rs1) / unsigned(uext(rs2,64)));
          t:=NOT to_std_logic(tmp64(63 DOWNTO 32)=x"00000000");
          IF t='1' THEN
            rd_ot:=x"FFFFFFFF";
          ELSE
            rd_ot:=tmp64(31 DOWNTO 0);
          END IF;
        END IF;
 
      WHEN "001111" =>                  -- SDIV
        IF rs2=x"00000000" THEN
          dz_o:='1';
        ELSE
          tmp64:=unsigned(signed(unsigned'(ry & rs1)) / signed(sext(rs2,64))); 
          t:=NOT (to_std_logic(tmp64(63 DOWNTO 31)=x"00000000" & '0')
               OR to_std_logic(tmp64(63 DOWNTO 31)=x"FFFFFFFF" & '1'));
          IF t='1' THEN
            IF tmp64(63)='0' THEN
              rd_ot:=x"7FFFFFFF";
            ELSE
              rd_ot:=x"80000000";
            END IF;
          ELSE
            rd_ot:=tmp64(31 DOWNTO 0);
          END IF;
        END IF;
        
      WHEN "011010" =>                  -- UMULcc
        tmp64:=unsigned(unsigned(rs1) * unsigned(rs2));
        ry_o:=tmp64(63 DOWNTO 32);
        rd_ot:=tmp64(31 DOWNTO 0);
        icc_o.n:=rd_ot(31);
        icc_o.z:=to_std_logic(rd_ot=x"00000000");
        icc_o.v:='0';
        icc_o.c:='0';
        
      WHEN "011011" =>                  -- SMULcc
        tmp64:=unsigned(signed(rs1) * signed(rs2));
        ry_o:=tmp64(63 DOWNTO 32);
        rd_ot:=tmp64(31 DOWNTO 0);
        icc_o.n:=rd_ot(31);
        icc_o.z:=to_std_logic(rd_ot=x"00000000");
        icc_o.v:='0';
        icc_o.c:='0';
       
      WHEN "011110" =>                  -- UDIVcc
        IF rs2=x"00000000" THEN
          dz_o:='1';
        ELSE
          tmp64:=unsigned(unsigned'(ry & rs1) / unsigned(uext(rs2,64)));
          t:=NOT to_std_logic(tmp64(63 DOWNTO 32)=x"00000000");
          IF t='1' THEN
            rd_ot:=x"FFFFFFFF";
          ELSE
            rd_ot:=tmp64(31 DOWNTO 0);
          END IF;
        END IF;
        icc_o.n:=rd_ot(31);
        icc_o.z:=to_std_logic(rd_ot=x"00000000");
        icc_o.v:=t;
        icc_o.c:='0';
        
      WHEN "011111" =>                  -- SDIVcc
        IF rs2=x"00000000" THEN
          dz_o:='1';
        ELSE
          tmp64:=unsigned(signed(unsigned'(ry & rs1)) / signed(sext(rs2,64))); 
          t:=NOT (to_std_logic(tmp64(63 DOWNTO 31)=x"00000000" & '0')
               OR to_std_logic(tmp64(63 DOWNTO 31)=x"FFFFFFFF" & '1'));
          IF t='1' THEN
            IF tmp64(63)='0' THEN
              rd_ot:=x"7FFFFFFF";
            ELSE
              rd_ot:=x"80000000";
            END IF;
          ELSE
            rd_ot:=tmp64(31 DOWNTO 0);
          END IF;
        END IF;
        icc_o.n:=rd_ot(31);
        icc_o.z:=to_std_logic(rd_ot=x"00000000");
        icc_o.v:=t;
        icc_o.c:='0';
                
      WHEN OTHERS => NULL;
    END CASE;

    rd_o:=rd_ot;
  END PROCEDURE op_mdu_sim;
  --pragma synthesis_on

  --------------------------------------
  -- Opérations load/store unit
  PROCEDURE op_lsu (
    CONSTANT cat        : IN  type_cat;
    CONSTANT rd         : IN  uv32;
    CONSTANT sum        : IN  uv32;
    CONSTANT psr        : IN  type_psr;
    CONSTANT fexc       : IN  std_logic;
    CONSTANT IFLUSH     : IN  boolean;
    CONSTANT FPU_LDASTA : IN  boolean;
    CONSTANT CASA       : IN  boolean;
    VARIABLE data_w     : OUT type_plomb_w;   -- Pipe Données     CPU -> MEM
    VARIABLE trap_o     : OUT type_trap) IS   -- Génération TRAP
    VARIABLE asi        : uv8;
    VARIABLE ali        : boolean;
    ALIAS op_op3 : unsigned(24 DOWNTO 19) IS cat.op(24 DOWNTO 19);
    ALIAS op_imm : std_logic IS cat.op(13);
    ALIAS op_asi : unsigned(12 DOWNTO 5) IS cat.op(12 DOWNTO 5);
  BEGIN
    asi:=mux(psr.s,ASI_SUPER_DATA,ASI_USER_DATA);
    data_w:=plomb_rd(sum,asi,cat.size);
    data_w.d:=st(cat.size,rd);
    
    trap_o:=TT_NONE;
    -- Les instructions avec accès mémoire DATA peuvent aussi déclencher des
    -- exceptions MMU --> TT_DATA_ACCESS_EXCEPTION...
    ali:=align(cat.size,sum(2 DOWNTO 0));
  
    CASE op_op3 IS
      WHEN "000000" |         -- LD : Load Word
           "000001" |         -- LDUB : Load Unsigned Byte
           "000010" |         -- LDUH : Load Unsigned Half Word
           "000011" |         -- LDD : Load DoubleWord
           "001001" |         -- LDSB : Load Signed Byte
           "001010" =>        -- LDSH : Load Signed Half Word
        data_w:=plomb_rd(sum,asi,cat.size);
        IF NOT ali THEN
          trap_o:=TT_MEM_ADDRESS_NOT_ALIGNED;
        END IF;
    
      WHEN "000100" |         -- ST
           "000101" |         -- STB
           "000110" |         -- STH
           "000111" =>        -- STD
        data_w:=plomb_wr(sum,asi,cat.size,rd);
        IF NOT ali THEN
          trap_o:=TT_MEM_ADDRESS_NOT_ALIGNED;
        END IF;
    
      WHEN "001000" =>        -- SparcV9 : LDSW : Load Signed Word
        -- On pourrait copier LD
        trap_o:=TT_ILLEGAL_INSTRUCTION;
    
      WHEN "001011" =>        -- SparcV9 : LDX : Load Extended Word : 64bits
        trap_o:=TT_ILLEGAL_INSTRUCTION;
    
      WHEN "001100" =>        -- Invalide
        trap_o:=TT_ILLEGAL_INSTRUCTION;

      WHEN "001101" =>        -- LDSTUB : Atomic Load/Store Unsigned Byte
        data_w:=plomb_rd(sum,asi,cat.size);
        data_w.lock:='1';
        data_w.d:=st(cat.size,x"FFFFFFFF");
        IF NOT ali THEN
          trap_o:=TT_MEM_ADDRESS_NOT_ALIGNED;
        END IF;
    
      WHEN "001110" => -- SparcV9 : STX : Store Extended Word : 64bits
        trap_o:=TT_ILLEGAL_INSTRUCTION;
  
      WHEN "001111" => -- SWAP : Swap register with Memory
        data_w:=plomb_rd(sum,asi,cat.size);
        data_w.lock:='1';
        data_w.d:=st(cat.size,rd);
        IF NOT ali THEN
          trap_o:=TT_MEM_ADDRESS_NOT_ALIGNED;
        END IF;
    
      WHEN "010000" |  -- LDA   : Load Word from Alternate Space (PRIV)
           "010001" |  -- LDUBA : Load Unsigned Byte from Alternate Space
           "010010" |  -- LDUHA : Load Unsigned HalfWord from Alt. Space
           "010011" |  -- LDDA  : Load Double Word from Alt. Space (PRIV)
           "011001" |  -- LDSBA : Load Signed Byte from Alt. Space (PRIV)
           "011010" => -- LDSHA : Load Signed Half Word from Alt. Space (PRIV)
        data_w:=plomb_rd(sum,op_asi,cat.size);
        IF op_imm='1' THEN
          trap_o:=TT_ILLEGAL_INSTRUCTION;
        ELSIF NOT ali THEN
          trap_o:=TT_MEM_ADDRESS_NOT_ALIGNED;
        END IF;
    
      WHEN "010100" |  -- STA  : Store Word into Alternate Space (PRIV)
           "010101" |  -- STBA : Store Byte into Alternate Space (PRIV)
           "010110" |  -- STHA : Store Half Word into Alt. Space (PRIV)
           "010111" => -- STDA : Store DoubleWord into Alt. Space (PRIV)
        data_w:=plomb_wr(sum,op_asi,cat.size,rd);
        IF op_imm='1' THEN
          trap_o:=TT_ILLEGAL_INSTRUCTION;
        ELSIF NOT ali THEN
          trap_o:=TT_MEM_ADDRESS_NOT_ALIGNED;
        END IF;
  
      WHEN "011000" => -- SparcV9 : LDSWA : Load Signed Word into Alt. Space
        -- On pourrait copier LDA
        trap_o:=TT_ILLEGAL_INSTRUCTION;
    
      WHEN "011011" =>
        -- SparcV9 : LDXA : Load Extended Word from Alt. Space : 64bit
        trap_o:=TT_ILLEGAL_INSTRUCTION;

      WHEN "011100" => -- Invalide
        trap_o:=TT_ILLEGAL_INSTRUCTION;

      WHEN "011101" =>
        -- LDSTUBA : Atomic Load/Store Unsigned Byte in Alt. Space (PRIV)
        data_w:=plomb_rd(sum,op_asi,cat.size);
        data_w.lock:='1';
        data_w.d:=st(cat.size,x"FFFFFFFF");
        IF op_imm='1' THEN
          trap_o:=TT_ILLEGAL_INSTRUCTION;
        ELSIF NOT ali THEN
          trap_o:=TT_MEM_ADDRESS_NOT_ALIGNED;
        END IF;
    
      WHEN "011110" => -- SparcV9 : STXA : Store Ext. Word from Alt. Space
        trap_o:=TT_ILLEGAL_INSTRUCTION;
  
      WHEN "011111" => -- SWAPA : Swap reg. with mem. in Alt. Space (PRIV)
        data_w:=plomb_rd(sum,op_asi,cat.size);
        data_w.lock:='1';
        data_w.d:=st(cat.size,rd);
        IF op_imm='1' THEN
          trap_o:=TT_ILLEGAL_INSTRUCTION;
        ELSIF NOT ali THEN
          trap_o:=TT_MEM_ADDRESS_NOT_ALIGNED;
        END IF;
    
      WHEN "100000" |  -- LDF : Load Floating Point
           "100001" |  -- LDFSR : Load Floating Point State Register
           "100011" => -- LDDF : Load Double Floating Point
        data_w:=plomb_rd(sum,asi,cat.size);
        IF NOT ali THEN
          trap_o:=TT_MEM_ADDRESS_NOT_ALIGNED;
        END IF;
    
      WHEN "100010" => -- SparcV9 : LDQF : Load Quad Floating Point
        trap_o:=TT_ILLEGAL_INSTRUCTION;
    
      WHEN "100100" |  -- STF : Store Floating Point
           "100101" |  -- STFSR : Store Floating Point State Register
           "100111" => -- STDF : Store Double Floating Point
        data_w:=plomb_wr(sum,asi,cat.size,rd);
        IF NOT ali THEN
          trap_o:=TT_MEM_ADDRESS_NOT_ALIGNED;
        END IF;
    
      WHEN "100110" => -- STDFQ : Store Double Floating Point Queue (PRIV)
        -- SparcV8 (B.5)
        -- <AFAIRE> Traitement STDFQ, traps...
        -- Priorités : 'privilegied' > 'fp_disabled' > 'fp_exception'
        data_w:=plomb_wr(sum,asi,cat.size,rd);
        IF NOT ali THEN
          trap_o:=TT_MEM_ADDRESS_NOT_ALIGNED;
        END IF;
        
      WHEN "101000" |  -- Invalide
           "101001" |  -- Invalide
           "101010" |  -- Invalide
           "101011" |  -- Invalide
           "101100" |  -- Invalide
           "101101" |  -- SparcV9 : PREFETCH
           "101110" |  -- Invalide
           "101111" => -- Invalide
        trap_o:=TT_ILLEGAL_INSTRUCTION;

      WHEN "110000" |  -- LDFA : V9 Load Floating Point from Alt. Space [LDC]
           "110001" |  -- "LDFSRA" : Load FP State from Alt. State [LDCSR]
           "110011" => -- LDDFA : V9 Load Double FP from Alt. Space [LDDC]
        data_w:=plomb_rd(sum,op_asi,cat.size);
        IF FPU_LDASTA THEN
          IF op_imm='1' THEN
            trap_o:=TT_ILLEGAL_INSTRUCTION;
          ELSIF NOT ali THEN
            trap_o:=TT_MEM_ADDRESS_NOT_ALIGNED;
          END IF;
        ELSE
          trap_o:=TT_CP_DISABLED;
        END IF;
    
      WHEN "110010" => -- Invalide
        trap_o:=TT_ILLEGAL_INSTRUCTION;
        -- SparcV9 : LDQFA : Load Quad Floating Point from Alt. Space
        
      WHEN "110100" |  -- STFA : V9 Store Floating Point from Alt. Space [STC]
           "110101" |  -- "STFSRA" : Store FP state from Alt. Space  [STCSR]
           "110111" => -- STDFA : V9 Store Double FP from Alt. Space [STDC]
        IF FPU_LDASTA THEN
          data_w:=plomb_wr(sum,op_asi,cat.size,rd);
          IF op_imm='1' THEN
            trap_o:=TT_ILLEGAL_INSTRUCTION;
          ELSIF NOT ali THEN
            trap_o:=TT_MEM_ADDRESS_NOT_ALIGNED;
          END IF;
        ELSE
          trap_o:=TT_CP_DISABLED;
        END IF;
    
      WHEN "110110" =>  -- "STDFQA" : Store FP queue from Alt. State [STDCQ]
        IF FPU_LDASTA THEN
          data_w:=plomb_wr(sum,op_asi,cat.size,rd);
          IF op_imm='1' THEN
            trap_o:=TT_ILLEGAL_INSTRUCTION;
          ELSIF NOT ali THEN
            trap_o:=TT_MEM_ADDRESS_NOT_ALIGNED;
          END IF;
        ELSE
          trap_o:=TT_CP_DISABLED;
        END IF;
    
      WHEN "111000" => -- Invalide
        trap_o:=TT_ILLEGAL_INSTRUCTION;

      WHEN "111001" => -- Invalide
        trap_o:=TT_ILLEGAL_INSTRUCTION;

      WHEN "111010" => -- Invalide
        trap_o:=TT_ILLEGAL_INSTRUCTION;

      WHEN "111011" => -- IFLUSH
        data_w:=plomb_wr(sum,ASI_IFLUSH,cat.size,rd);
        IF cat.op(31 DOWNTO 30)="10" AND IFLUSH THEN
          -- Instruction IFLUSH   : 10_____111011
        ELSE
          -- Instruction Invalide ; 11_____111011
          trap_o:=TT_ILLEGAL_INSTRUCTION;
        END IF;
    
      WHEN "111100" => -- SparcV9 : CASA
        --CASA [RS1],RS2, RD:
        --  IF [RS1]=RS2
        --    RD=[RS1], [RS1]=RD : swap
        --  ELSE
        --    RD=[RS1]
        IF CASA THEN
          data_w:=plomb_rd(sum,op_asi,cat.size);
          data_w.lock:='1';
          data_w.d:=st(cat.size,rd);
          IF op_imm='1' THEN
            trap_o:=TT_ILLEGAL_INSTRUCTION;
          ELSIF NOT ali THEN
            trap_o:=TT_MEM_ADDRESS_NOT_ALIGNED;
          END IF;
        ELSE
          trap_o:=TT_ILLEGAL_INSTRUCTION;
        END IF;

      WHEN "111101" => -- SparcV9 : PREFETCHA
        trap_o:=TT_ILLEGAL_INSTRUCTION;

      WHEN "111110" => -- SparcV9 : CASXA
        trap_o:=TT_ILLEGAL_INSTRUCTION;
    
      WHEN "111111" => -- Invalide
        trap_o:=TT_ILLEGAL_INSTRUCTION;
    
      WHEN OTHERS => NULL;
    END CASE;
    
  END PROCEDURE op_lsu;
          
  --------------------------------------
  -- Operations ALU (niveau pipe exe)
  PROCEDURE op_exe (
    CONSTANT cat         : IN  type_cat;
    CONSTANT pc          : IN  uv32;
    VARIABLE npc_o       : OUT uv32;
    VARIABLE npc_maj     : OUT std_logic;
    CONSTANT rs1         : IN  uv32;
    CONSTANT rs2         : IN  uv32;
    VARIABLE rd_o        : OUT uv32;
    VARIABLE sum_o       : OUT uv32;
    CONSTANT ry          : IN  uv32;    -- Registre Y
    VARIABLE ry_o        : OUT uv32;    -- Registre Y
    CONSTANT psr         : IN  type_psr;
    VARIABLE psr_o       : OUT type_psr;
    CONSTANT muldiv_rd   : IN  uv32;
    CONSTANT muldiv_ry   : IN  uv32;
    CONSTANT muldiv_icc  : IN  type_icc;
    CONSTANT muldiv_dz   : IN  std_logic;
    CONSTANT cwp         : IN  unsigned(4 DOWNTO 0);
    CONSTANT wim         : IN  unsigned;
    CONSTANT tbr         : IN  type_tbr;
    CONSTANT fexc        : IN  std_logic;
    VARIABLE trap_o      : OUT type_trap;
    CONSTANT MULDIV      : IN  boolean;
    CONSTANT IU_IMP_VERSION : IN uv8) IS
    ALIAS op_op     : unsigned(31 DOWNTO 30) IS cat.op(31 DOWNTO 30);
    ALIAS op_op2    : unsigned(24 DOWNTO 22) IS cat.op(24 DOWNTO 22);
    ALIAS op_imm22  : unsigned(21 DOWNTO 0)  IS cat.op(21 DOWNTO 0);
    ALIAS op_disp30 : unsigned(29 DOWNTO 0)  IS cat.op(29 DOWNTO 0);
    VARIABLE npc_alu_maj : std_logic;
    VARIABLE trap_alu_o : type_trap;
  BEGIN
    npc_maj:='0';
    trap_o:=TT_NONE;
    op_alu(cat,pc,npc_o,npc_alu_maj,rs1,rs2,rd_o,sum_o,
           ry,ry_o,psr,psr_o,muldiv_rd,muldiv_ry,muldiv_icc,muldiv_dz,
           cwp,wim,tbr,trap_alu_o,MULDIV,IU_IMP_VERSION);
    
    CASE op_op IS
      WHEN "00" =>
        CASE op_op2 IS
          WHEN "000" => -- UNIMP : Unimplemented instruction
            trap_o:=TT_ILLEGAL_INSTRUCTION;
            
          WHEN "001" => -- SparcV9 BPcc : Integer Cond. Branch with Prediction
            trap_o:=TT_ILLEGAL_INSTRUCTION;
            
          --WHEN "010" => -- Bicc : Integer Conditional Branch
          --  op_bicc  (op,pc,npc_o,npc_maj,psr,annul_o);
            
          WHEN "011" => -- SparcV9 : BPr
            trap_o:=TT_ILLEGAL_INSTRUCTION;
            
          WHEN "100" => -- SETHI : Set High 22 bits of REGISTER
            rd_o:=op_imm22 & "0000000000";
            
          WHEN "101" => -- SparcV9 FBPfcc : FP Cond. Branch with Prediction
            trap_o:=TT_ILLEGAL_INSTRUCTION;
            
          --WHEN "110" => -- FBfcc : Floating Point Conditional Branch
          --  IF psr.ef='0' THEN
          --    trap_o:=TT_FP_DISABLED;
          --  ELSIF fexc='1' THEN
          --    trap_o:=TT_FP_EXCEPTION;
          --  END IF;
          -- FP_DISABLED/FP_EXCEPTION -> IU
            
          WHEN "111" => -- CBccc : Coprocessor Conditional Branch
            trap_o:=TT_CP_DISABLED;
            trap_o:=TT_ILLEGAL_INSTRUCTION;
            
          WHEN OTHERS =>
            NULL;
            
        END CASE;
      WHEN "01" =>               -- CALL
      --  npc_o:=pc+(op_disp30 & "00");
      --  npc_maj:='1';
        rd_o:=pc;

      WHEN "10" =>               -- Arith/Logic/FPU
        npc_maj:=npc_alu_maj;
        trap_o:=trap_alu_o;
        
      --WHEN "11" =>               -- Load/Store
        -- Instructions LSU traitées séparément
        
      WHEN OTHERS =>
        NULL;
    END CASE;
    
  END PROCEDURE op_exe;

  --------------------------------------
  -- Instruction Bicc
  PROCEDURE op_bicc (
    CONSTANT op          : IN  uv32; -- Opcode Instruction
    VARIABLE npc_maj     : OUT std_logic;
    CONSTANT icc         : IN  type_icc;   -- Execute
    VARIABLE annul_o     : OUT std_logic) IS  -- Annulation instruction suivante
    ALIAS op_annul : std_logic IS op(29);
    ALIAS op_cond  : unsigned(28 DOWNTO 25) IS op(28 DOWNTO 25);
  BEGIN
    -- Bicc : Integer Conditional Branch
    IF op_cond="1000" THEN             -- Branch Always
      npc_maj:='1';
      annul_o:=op_annul;
    ELSIF icc_test(icc,op_cond)='1' THEN
      npc_maj:='1';
      annul_o:='0';
    ELSE
      npc_maj:='0';
      annul_o:=op_annul;
    END IF;
  END PROCEDURE op_bicc;
  
  --------------------------------------
  -- Instruction FBfcc
  PROCEDURE op_fbfcc (
    CONSTANT op          : IN  uv32;  -- Opcode Instruction
    VARIABLE npc_maj     : OUT std_logic;
    CONSTANT fcc         : IN  unsigned(1 DOWNTO 0);
    VARIABLE annul_o     : OUT std_logic) IS  -- Annulation instruction suivante
    ALIAS op_annul : std_logic IS op(29);
    ALIAS op_cond  : unsigned(28 DOWNTO 25) IS op(28 DOWNTO 25);
  BEGIN
    -- Bicc : Integer Conditional Branch
    IF op_cond="1000" THEN              -- Branch Always
      npc_maj:='1';
      annul_o:=op_annul;
    ELSIF fcc_test(fcc,op_cond)='1' THEN
      npc_maj:='1';
      annul_o:='0';
    ELSE
      npc_maj:='0';
      annul_o:=op_annul;
    END IF;
  END PROCEDURE op_fbfcc;

  --------------------------------------
  -- Instructions de saut traitées au niveau DECODE
  PROCEDURE op_dec(
    CONSTANT op          : IN  uv32;
    CONSTANT pc          : IN  uv32;
    VARIABLE npc_o       : OUT uv32;
    VARIABLE npc_maj     : OUT std_logic;
    CONSTANT psr         : IN  type_psr;
    CONSTANT fcc         : IN  unsigned(1 DOWNTO 0);
    CONSTANT fexc        : IN  std_logic;
    VARIABLE annul_o     : OUT std_logic
    ) IS
    ALIAS op_op     : unsigned(31 DOWNTO 30) IS op(31 DOWNTO 30);
    ALIAS op_op2    : unsigned(24 DOWNTO 22) IS op(24 DOWNTO 22);
    ALIAS op_imm22  : unsigned(21 DOWNTO 0)  IS op(21 DOWNTO 0);
    ALIAS op_disp30 : unsigned(29 DOWNTO 0) IS op(29 DOWNTO 0);
    VARIABLE off : uv32;
  BEGIN
    off:=sext(op_imm22 & "00",32);
    npc_maj:='0';
    annul_o:='0';
    CASE op_op IS
      WHEN "00" =>
        CASE op_op2 IS
          WHEN "010" => -- Bicc : Integer Conditional Branch
            op_bicc (op,npc_maj,psr.icc,annul_o);
            
          WHEN "110" => -- FBfcc : Floating Point Conditional Branch
            -- Les traps FPU sont traités ailleurs
            op_fbfcc(op,npc_maj,fcc,annul_o);
            
          WHEN OTHERS =>
            NULL;
        END CASE;
      WHEN "01" =>               -- CALL
        off:=(op_disp30 & "00");
        npc_maj:='1';
        
      WHEN OTHERS =>
        NULL;
    END CASE;
    npc_o:=pc + off;
  END PROCEDURE op_dec;

  --############################################################################

END PACKAGE BODY iu_pack;
