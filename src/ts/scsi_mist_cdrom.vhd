----*-vhdl-*--------------------------------------------------------------------
-- TEM : TS
-- SCSI <-> MIST/MISTER
--------------------------------------------------------------------------------
-- DO 2/2018
--------------------------------------------------------------------------------
-- Emulation CDROM SCSI
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
--             ____________________________
-- HD_RD/WR  _/                            \____________________
--                                        _______________
-- HD_ACK _______________________________/               \______
--
-- HDB_ADRS/DW/DR/WR --------------------[ DATA TRANSFER ]------
--
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.ts_pack.ALL;

ENTITY scsi_mist_cdrom IS
  GENERIC (
    SYSFREQ : natural :=50_000_000);
  PORT (
    scsi_w   : IN  type_scsi_w;
    scsi_r   : OUT type_scsi_r;
    id       : IN  unsigned(2 DOWNTO 0);
    busy     : OUT std_logic;
    
    -- Interface MISTER
    hd_lba   : OUT std_logic_vector(31 DOWNTO 0);
    hd_rd    : OUT std_logic;
    hd_wr    : OUT std_logic;
    hd_ack   : IN  std_logic;
    
    hdb_adrs : IN  std_logic_vector(7 DOWNTO 0);
    hdb_dw   : IN  std_logic_vector(15 DOWNTO 0);
    hdb_dr   : OUT std_logic_vector(15 DOWNTO 0);
    hdb_wr   : IN  std_logic;
    
    hd_size    : IN std_logic_vector(63 DOWNTO 0); -- Size in bytes
    hd_mounted : IN std_logic; -- Mounted 
    hd_ro      : IN std_logic; -- Read Only

    ssize      : IN std_logic; -- Sector Size 0=2048 1=512
    
    -- Global
    clk      : IN std_logic;
    reset_n  : IN std_logic
    );
END ENTITY scsi_mist_cdrom;

--##############################################################################

ARCHITECTURE rtl OF scsi_mist_cdrom IS

  CONSTANT STAT_SYSACE       : uv8 := x"00";

  CONSTANT INQ_VID : string(1 TO 8)  := "TACUS   ";
  CONSTANT INQ_PID : string(1 TO 16) := "CDROM     MISTER";
  CONSTANT INQ_RID : string(1 TO 4)  := "0.10";
  
  SIGNAL hd_wr_i,hd_rd_i : std_logic;
  
  SIGNAL ii_hilo : std_logic;
  SIGNAL ii_dw,ii_dr : uv8;
  SIGNAL ii_dr16 : uv16;
  SIGNAL ii_adrs : uv9;
  SIGNAL ii_adrsd : std_logic;
  
  SHARED VARIABLE mem0 : arr_uv8(0 TO 511);
  SHARED VARIABLE mem1 : arr_uv8(0 TO 511);
  ATTRIBUTE ramstyle : string;
  ATTRIBUTE ramstyle OF mem0,mem1 : VARIABLE IS "no_rw_check";
  
  SIGNAL hdb_hilo : std_logic;
  
  CONSTANT CMD_WR   : uv8 :=x"01"; -- Déclenche écriture
  CONSTANT CMD_RD   : uv8 :=x"02"; -- Déclenche lecture
  CONSTANT CMD_TOG  : uv8 :=x"04"; -- Alternance pifpaf
  CONSTANT CMD_WAIT : uv8 :=x"08"; -- Attente fin accès précédent
  CONSTANT CMD_CLR  : uv8 :=x"10"; -- ptr=0
  CONSTANT CMD_SET  : uv8 :=x"20"; -- ptr=-1
  CONSTANT CMD_LAST : uv8 :=x"40"; -- Test dernier secteur
  CONSTANT CMD_TOG2 : uv8 :=x"80";
  
  -- SCSI
  SIGNAL capacity_m : uv32;
  SIGNAL acc    : uv8;                    -- Registre Accumulateur
  SIGNAL cpt    : unsigned(11 DOWNTO 0);  -- Registre Comptage
  SIGNAL r_adrs : uv32;                   -- Adresse LBA
  SIGNAL r_len  : uv18;                   -- Nombre de secteurs
  SIGNAL r_message : uv8;
  SIGNAL r_lun : unsigned(2 DOWNTO 0);
  SIGNAL r_sense : uv8;
  SIGNAL r_lab : unsigned(9 DOWNTO 0);
  SIGNAL pc : natural RANGE 0 TO 1023;
  SIGNAL fifo : arr_uv8(0 TO 7);
  
  SIGNAL scsi_ack_delai : std_logic;
  SIGNAL nov : std_logic;
  SIGNAL scsi_r_i : type_scsi_r;
  CONSTANT REG_ACC       : uv8 := x"00";
  CONSTANT REG_ADRS0     : uv8 := x"02";
  CONSTANT REG_ADRS1     : uv8 := x"03";
  CONSTANT REG_ADRS2     : uv8 := x"04";
  CONSTANT REG_ADRS3     : uv8 := x"05";
  CONSTANT REG_LEN0      : uv8 := x"06";
  CONSTANT REG_LEN1      : uv8 := x"07";
  CONSTANT REG_CONTROL   : uv8 := x"08";
  CONSTANT REG_SENSE     : uv8 := x"09";
  CONSTANT REG_LUN_ADRS2 : uv8 := x"0A";
  CONSTANT REG_CAPA0     : uv8 := x"0B";
  CONSTANT REG_CAPA1     : uv8 := x"0C";
  CONSTANT REG_CAPA2     : uv8 := x"0D";
  CONSTANT REG_CAPA3     : uv8 := x"0E";
  
  CONSTANT Z : unsigned(1 DOWNTO 0) := "00";
  

-- DEBUT Insertion Microcode
  TYPE enum_code IS (
        NOP,
        SET_MODE,
        LDS_I,
        LAB,
        TEST_BSY,
        RAZ_REG,
        TEST_ATN,
        SCSI_RD,
        TEST_EQ,
        GOTO,
        TEST_EQH,
        FIXLEN,
        TEST_ADRS,
        HD_CMD,
        LDCPT,
        INC_COUNT,
        HD_DR,
        SCSI_WR,
        LOOP_CPT,
        LOOP_SECCNT,
        TEST_LUN,
        TEST_EVPD,
        TEST_LEN,
        LDA_I,
        LDA_DBD,
        TEST_DBD,
        LDA_R,
        LDA_SECTOR,
        TEST_PC,
        SCSI_WR_A);

  TYPE type_microcode IS RECORD
    op  : enum_code;
    val : unsigned(9 DOWNTO 0);
  END RECORD;
  TYPE arr_microcode IS ARRAY(natural RANGE <>) OF type_microcode;

  CONSTANT microcode : arr_microcode :=(
        (NOP            ,Z&x"00"        ), 
        (SET_MODE       ,Z&"00000"&SCSI_MSG_OUT), 
        (NOP            ,Z&x"00"        ), 
        (NOP            ,Z&x"00"        ), 
        (LDS_I          ,Z&SENSE_NO_SENSE), 
        (LAB            ,to_unsigned(6,10)), 
        (TEST_BSY       ,Z&x"00"        ), 
        (RAZ_REG        ,Z&x"00"        ), 
        (NOP            ,Z&x"00"        ), 
        (LAB            ,to_unsigned(26,10)), 
        (TEST_ATN       ,Z&x"00"        ), 
        (SET_MODE       ,Z&"00000"&SCSI_MSG_OUT), 
        (NOP            ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (NOP            ,Z&x"00"        ), 
        (NOP            ,Z&x"00"        ), 
        (TEST_ATN       ,Z&x"00"        ), 
        (NOP            ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (NOP            ,Z&x"00"        ), 
        (LAB            ,to_unsigned(403,10)), 
        (TEST_EQ        ,Z&x"00"        ), 
        (LAB            ,to_unsigned(31,10)), 
        (SET_MODE       ,Z&"00000"&SCSI_COMMAND), 
        (NOP            ,Z&x"00"        ), 
        (GOTO           ,Z&x"00"        ), 
        (NOP            ,Z&x"00"        ), 
        (SET_MODE       ,Z&"00000"&SCSI_COMMAND), 
        (NOP            ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SCSI_RD        ,Z&REG_LUN_ADRS2), 
        (LAB            ,to_unsigned(62,10)), 
        (TEST_EQ        ,Z&OP_READ_6    ), 
        (LAB            ,to_unsigned(69,10)), 
        (TEST_EQ        ,Z&OP_READ_10   ), 
        (LAB            ,to_unsigned(158,10)), 
        (TEST_EQ        ,Z&OP_INQUIRY   ), 
        (LAB            ,to_unsigned(387,10)), 
        (TEST_EQ        ,Z&OP_TEST_UNIT_READY), 
        (TEST_EQ        ,Z&OP_START_STOP_UNIT), 
        (TEST_EQ        ,Z&OP_ALLOW_MEDIUM_REMOVAL), 
        (LAB            ,to_unsigned(243,10)), 
        (TEST_EQ        ,Z&OP_MODE_SENSE_6), 
        (LAB            ,to_unsigned(312,10)), 
        (TEST_EQ        ,Z&OP_MODE_SENSE_10), 
        (LAB            ,to_unsigned(322,10)), 
        (TEST_EQ        ,Z&OP_READ_CAPACITY), 
        (LAB            ,to_unsigned(351,10)), 
        (TEST_EQ        ,Z&OP_REQUEST_SENSE), 
        (LAB            ,to_unsigned(393,10)), 
        (TEST_EQ        ,Z&OP_SYNCHRONIZE_CACHE), 
        (LAB            ,to_unsigned(428,10)), 
        (TEST_EQH       ,Z&x"00"        ), 
        (LAB            ,to_unsigned(424,10)), 
        (TEST_EQH       ,Z&x"20"        ), 
        (TEST_EQH       ,Z&x"40"        ), 
        (LAB            ,to_unsigned(422,10)), 
        (TEST_EQH       ,Z&x"A0"        ), 
        (LAB            ,to_unsigned(418,10)), 
        (TEST_EQH       ,Z&x"80"        ), 
        (LAB            ,to_unsigned(434,10)), 
        (GOTO           ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ADRS1    ), 
        (SCSI_RD        ,Z&REG_ADRS0    ), 
        (SCSI_RD        ,Z&REG_LEN0     ), 
        (SCSI_RD        ,Z&REG_CONTROL  ), 
        (FIXLEN         ,Z&x"00"        ), 
        (LAB            ,to_unsigned(77,10)), 
        (GOTO           ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ADRS3    ), 
        (SCSI_RD        ,Z&REG_ADRS2    ), 
        (SCSI_RD        ,Z&REG_ADRS1    ), 
        (SCSI_RD        ,Z&REG_ADRS0    ), 
        (SCSI_RD        ,Z&REG_LEN1     ), 
        (SCSI_RD        ,Z&REG_LEN1     ), 
        (SCSI_RD        ,Z&REG_LEN0     ), 
        (SCSI_RD        ,Z&REG_CONTROL  ), 
        (LAB            ,to_unsigned(434,10)), 
        (TEST_ADRS      ,Z&x"00"        ), 
        (NOP            ,Z&x"00"        ), 
        (SET_MODE       ,Z&"00000"&SCSI_DATA_IN), 
        (NOP            ,Z&x"00"        ), 
        (HD_CMD         ,Z&(CMD_WAIT OR CMD_CLR OR CMD_RD)), 
        (LAB            ,to_unsigned(84,10)), 
        (LDCPT          ,Z&x"0F"        ), 
        (INC_COUNT      ,Z&x"00"        ), 
        (HD_CMD         ,Z&(CMD_WAIT OR CMD_TOG OR CMD_RD)), 
        (LAB            ,to_unsigned(88,10)), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (HD_DR          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LOOP_CPT       ,Z&x"00"        ), 
        (LAB            ,to_unsigned(84,10)), 
        (HD_CMD         ,Z&CMD_TOG2     ), 
        (LOOP_SECCNT    ,Z&x"00"        ), 
        (LAB            ,to_unsigned(403,10)), 
        (GOTO           ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SCSI_RD        ,Z&REG_ADRS0    ), 
        (SCSI_RD        ,Z&REG_LEN0     ), 
        (SCSI_RD        ,Z&REG_CONTROL  ), 
        (LAB            ,to_unsigned(435,10)), 
        (TEST_LUN       ,Z&x"00"        ), 
        (TEST_EVPD      ,Z&x"01"        ), 
        (TEST_LEN       ,Z&x"24"        ), 
        (NOP            ,Z&x"00"        ), 
        (SET_MODE       ,Z&"00000"&SCSI_DATA_IN), 
        (NOP            ,Z&x"00"        ), 
        (LDA_I          ,Z&x"05"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"80"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"02"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"02"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"1F"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"10"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_VID(1)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_VID(2)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_VID(3)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_VID(4)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_VID(5)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_VID(6)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_VID(7)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_VID(8)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_PID(1)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_PID(2)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_PID(3)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_PID(4)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_PID(5)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_PID(6)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_PID(7)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_PID(8)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_PID(9)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_PID(10)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_PID(11)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_PID(12)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_PID(13)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_PID(14)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_PID(15)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_PID(16)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_RID(1)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_RID(2)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_RID(3)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&to_unsigned(character'pos(INQ_RID(4)),8)), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LAB            ,to_unsigned(403,10)), 
        (GOTO           ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ADRS1    ), 
        (SCSI_RD        ,Z&REG_ADRS0    ), 
        (SCSI_RD        ,Z&REG_LEN0     ), 
        (SCSI_RD        ,Z&REG_CONTROL  ), 
        (NOP            ,Z&x"00"        ), 
        (SET_MODE       ,Z&"00000"&SCSI_DATA_IN), 
        (NOP            ,Z&x"00"        ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"01"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_DBD        ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LAB            ,to_unsigned(276,10)), 
        (TEST_DBD       ,Z&x"00"        ), 
        (LDA_I          ,Z&x"01"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_R          ,Z&REG_CAPA2    ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_R          ,Z&REG_CAPA1    ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_R          ,Z&REG_CAPA0    ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_SECTOR     ,Z&x"08"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LAB            ,to_unsigned(310,10)), 
        (TEST_PC        ,"01"&x"2A"     ), 
        (LDA_I          ,Z&x"2A"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"0E"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"02"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"C2"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"02"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"C2"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"02"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"C2"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"02"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"C2"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LAB            ,to_unsigned(403,10)), 
        (GOTO           ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ADRS1    ), 
        (SCSI_RD        ,Z&REG_ADRS0    ), 
        (SCSI_RD        ,Z&REG_LEN1     ), 
        (SCSI_RD        ,Z&REG_LEN1     ), 
        (SCSI_RD        ,Z&REG_LEN1     ), 
        (SCSI_RD        ,Z&REG_LEN1     ), 
        (SCSI_RD        ,Z&REG_LEN0     ), 
        (SCSI_RD        ,Z&REG_CONTROL  ), 
        (LAB            ,to_unsigned(247,10)), 
        (GOTO           ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ADRS3    ), 
        (SCSI_RD        ,Z&REG_ADRS2    ), 
        (SCSI_RD        ,Z&REG_ADRS1    ), 
        (SCSI_RD        ,Z&REG_ADRS0    ), 
        (SCSI_RD        ,Z&REG_LEN1     ), 
        (SCSI_RD        ,Z&REG_LEN1     ), 
        (SCSI_RD        ,Z&REG_LEN0     ), 
        (SCSI_RD        ,Z&REG_CONTROL  ), 
        (NOP            ,Z&x"00"        ), 
        (SET_MODE       ,Z&"00000"&SCSI_DATA_IN), 
        (NOP            ,Z&x"00"        ), 
        (LDA_R          ,Z&REG_CAPA3    ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_R          ,Z&REG_CAPA2    ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_R          ,Z&REG_CAPA1    ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_R          ,Z&REG_CAPA0    ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_SECTOR     ,Z&x"08"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LAB            ,to_unsigned(403,10)), 
        (GOTO           ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ADRS1    ), 
        (SCSI_RD        ,Z&REG_ADRS0    ), 
        (SCSI_RD        ,Z&REG_LEN0     ), 
        (SCSI_RD        ,Z&REG_CONTROL  ), 
        (NOP            ,Z&x"00"        ), 
        (SET_MODE       ,Z&"00000"&SCSI_DATA_IN), 
        (LAB            ,to_unsigned(435,10)), 
        (TEST_LEN       ,Z&x"07"        ), 
        (LAB            ,to_unsigned(368,10)), 
        (TEST_LUN       ,Z&x"00"        ), 
        (LDA_I          ,Z&x"F0"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_R          ,z&REG_SENSE    ), 
        (LAB            ,to_unsigned(373,10)), 
        (GOTO           ,Z&x"00"        ), 
        (LDA_I          ,Z&x"F0"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&SENSE_ILLEGAL_REQUEST), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_R          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDS_I          ,Z&SENSE_NO_SENSE), 
        (LAB            ,to_unsigned(403,10)), 
        (GOTO           ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ADRS1    ), 
        (SCSI_RD        ,Z&REG_ADRS0    ), 
        (SCSI_RD        ,Z&REG_LEN0     ), 
        (SCSI_RD        ,Z&REG_CONTROL  ), 
        (LAB            ,to_unsigned(403,10)), 
        (GOTO           ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ADRS3    ), 
        (SCSI_RD        ,Z&REG_ADRS2    ), 
        (SCSI_RD        ,Z&REG_ADRS1    ), 
        (SCSI_RD        ,Z&REG_ADRS0    ), 
        (SCSI_RD        ,Z&REG_LEN1     ), 
        (SCSI_RD        ,Z&REG_LEN1     ), 
        (SCSI_RD        ,Z&REG_LEN0     ), 
        (SCSI_RD        ,Z&REG_CONTROL  ), 
        (LAB            ,to_unsigned(403,10)), 
        (GOTO           ,Z&x"00"        ), 
        (NOP            ,Z&x"00"        ), 
        (SET_MODE       ,Z&"00000"&SCSI_STATUS), 
        (LAB            ,to_unsigned(6,10)), 
        (LDA_I          ,Z&STAT_GOOD    ), 
        (SCSI_WR_A      ,Z&REG_ACC      ), 
        (NOP            ,Z&x"00"        ), 
        (NOP            ,Z&x"00"        ), 
        (NOP            ,Z&x"00"        ), 
        (SET_MODE       ,Z&"00000"&SCSI_MSG_IN), 
        (LAB            ,to_unsigned(415,10)), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR_A      ,Z&REG_ACC      ), 
        (TEST_BSY       ,Z&x"01"        ), 
        (LAB            ,to_unsigned(6,10)), 
        (GOTO           ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (NOP            ,Z&x"00"        ), 
        (NOP            ,Z&x"00"        ), 
        (LDS_I          ,Z&SENSE_ILLEGAL_REQUEST), 
        (NOP            ,Z&x"00"        ), 
        (SET_MODE       ,Z&"00000"&SCSI_STATUS), 
        (LAB            ,to_unsigned(6,10)), 
        (LDA_I          ,Z&STAT_CHECK   ), 
        (SCSI_WR_A      ,Z&REG_ACC      ), 
        (LAB            ,to_unsigned(410,10)), 
        (GOTO           ,Z&x"00"        )); 

-- FIN Insertion Microcode

  SIGNAL code : type_microcode;
  
BEGIN

  -- RH : 12 00 25 00 12 : INQUIRY TEST_UNIT_READY READ_CAPACITY TEST_UNIT_READY INQUIRY

  -- Solaris 8 : 12 00 25 12 12 5A 5A 5A 12 5E

  -- NextSTEP : 12 00 25 00 12 1B 00 25     28 28 28 28 ....
  
  -- 00 = TEST UNIT READY
  -- 12 = INQUIRY
  -- 1B = OP START STOP UNIT
  -- 25 = READ CAPACITY
  -- 5A = MODE SENSE 10
  -- 5E = PERSISTANT RESERVE IN


  -- 12 00 00 c0 30 00
  --   => 05 80 02 00 1f 00 00 10
  --   5a 41 43 55 53 20 20 20
  --   43 44 52 4f 4d 20 20 20
  --   20 20 4d 49 53 54 45 52
  --   30 2e 31 30 00 00


  --  5A 00 2A c0 00 00 00 00 20 00
  --   => 00 01 80 08
  --      01 02 a3 9f
  --      00 00 08 00

  --   5a 00 2a c0 00 00 00 00 20 00
  --   => 00 01 80 08
  --      01 02 a3 9f
  --      00 00 08 00
    
  --   5a 00 2a c0 00 00 00 00 20 00
  --   => 00 01 80 08
  --      01 02 a3 9f
  --      00 00 08 00

  --   12 01 80 c0 14 00 /



  --   5e 00 00 c0 00 00 00 00 08 00 /

    

  
  --------------------------------------------------------
  

    
  
  
  


  



  
    


  -- %           LDA_I     Z&x"00"           -- reserved
  -- %           SCSI_WR   Z&REG_ACC -- 16 : 
  -- %           LDA_I     Z&x"00"           -- reserved
  -- %           SCSI_WR   Z&REG_ACC -- 17 : 
  -- %           LDA_I     Z&x"00"           -- reserved
  -- %           SCSI_WR   Z&REG_ACC -- 18 : 
  -- %           LDA_I     Z&x"00"           -- reserved
  -- %           SCSI_WR   Z&REG_ACC -- 19 :

    
    
  

      
  
  
  

  


-- <AFAIRE>
--   OP_REPORT_LUNS
--   OP_REQUEST_SENSE        obli,boot,cdrom
--   OP_ALLOW_MEDIUM_REMOVAL boot,cdrom
--   OP_SEND_DIAGNOSTIC      obli
--   OP_START_STOP_UNIT      
--   OP_RESERVE              obli,obsol
--   OP_RELEASE              obli,obsol
--   OP_VERIFY               
--   OP_SYNCHRONIZE_CACHE    
--   OP_READ_TOC             boot, cdrom
  
  ------------------------------------------------------------------------------
  -- Séquenceur
  Sequenceur: PROCESS (clk)
    VARIABLE vcmd : uv8;
    VARIABLE op_v  : enum_code;
    VARIABLE val_v : unsigned(9 DOWNTO 0);
    VARIABLE val8_v : uv8;
    VARIABLE halt_v : boolean;
    VARIABLE saut_v : boolean;
    VARIABLE sel_v : std_logic;
    VARIABLE pc_v : natural RANGE 0 TO 1023;
  BEGIN
    IF rising_edge(clk) THEN
      -------------------------------------------      
      op_v :=code.op;  -- Opcode
      val_v:=code.val; -- Valeur immédiate
      val8_v:=val_v(7 DOWNTO 0);
      -------------------------------------------      
      scsi_r_i.d<=acc;
      scsi_r_i.req<='0';
      sel_v:=to_std_logic(scsi_w.did=id);
      scsi_r_i.sel<=sel_v;
      
      scsi_r_i.d_pc<=to_unsigned(pc,10);

      -- READ CAPACITY returns the address of the last block, not the size.
      IF ssize='0' THEN
        capacity_m<=unsigned("00" & hd_size(40 DOWNTO 11)) -1; -- Last sector
      ELSE
        capacity_m<=unsigned(hd_size(40 DOWNTO 9)) -1; -- Last sector number
      END IF;
      
      -------------------------------------------
      halt_v:=false;
      saut_v:=false;
      
      CASE op_v IS
        ----------------------------------
        WHEN LDA_I =>
          -- Chargement registre ACC, immédiat
          acc<=val8_v;
          
        WHEN LDA_SECTOR =>
          IF ssize='1' THEN
            acc<=x"02"; -- 512 bytes 
          ELSE
            acc<=x"08"; -- 2048 bytes
          END IF;

        WHEN LDA_DBD =>
          -- DBD = Disable Block Descriptor
          IF r_adrs(19)='1' THEN
            acc<=x"00";
          ELSE
            acc<=x"08";
          END IF;
          
        WHEN LDCPT =>
          -- Affectation registre de comptage
          cpt<=x"0" & val8_v;
          
        WHEN LDS_I =>
          -- Affectation registre sense key
          r_sense<=val8_v;
          
        WHEN LDA_R =>
          -- Chargement registre ACC d'après registre
          val8_v(7 DOWNTO 4):=x"0";
          CASE val8_v IS
            WHEN REG_ADRS0 => acc<=r_adrs(7 DOWNTO 0);
            WHEN REG_ADRS1 => acc<=r_adrs(15 DOWNTO 8);
            WHEN REG_ADRS2 => acc<=r_adrs(23 DOWNTO 16);
            WHEN REG_ADRS3 => acc<=r_adrs(31 DOWNTO 24);
            WHEN REG_LEN1  => acc<=r_len(15 DOWNTO 8);
            WHEN REG_LEN0  => acc<=r_len(7 DOWNTO 0);
            WHEN REG_SENSE => acc<=r_sense;
            WHEN REG_CAPA0 => acc<=capacity_m(7  DOWNTO 0);
            WHEN REG_CAPA1 => acc<=capacity_m(15 DOWNTO 8);
            WHEN REG_CAPA2 => acc<=capacity_m(23 DOWNTO 16);
            WHEN REG_CAPA3 => acc<=capacity_m(31 DOWNTO 24);
            WHEN OTHERS    => acc<=r_len(7 DOWNTO 0);
          END CASE;
          
        WHEN RAZ_REG =>
          -- RAZ des registres <Utile ?>
          r_adrs<=x"00000000";
          r_len <="00" & x"0000";
          
        WHEN FIXLEN =>
          -- Si len 00 -->  len = 256
          IF r_len(7 DOWNTO 0)=x"00" THEN
            r_len<="00" & x"0100";
          END IF;
          
        WHEN LAB =>
          r_lab<=val_v;
          
        ----------------------------------
        WHEN HD_CMD =>
          -- Envoi commande
          IF val8_v(3)='0' OR (hd_wr_i='0' AND hd_rd_i='0' AND hd_ack='0') THEN
            --IF val8_v(6)='0' OR r_len/=x"0000" THEN -- not CMD_LAST
            IF r_len/=x"0000" THEN
              hd_wr_i<=hd_wr_i OR val8_v(0);
              hd_rd_i<=hd_rd_i OR val8_v(1);
              hd_lba<=std_logic_vector(r_adrs);
            END IF;
            
            ii_hilo  <=ii_hilo  XOR val8_v(7); -- TOG2
            IF val8_v(0)='1' THEN
              hdb_hilo<=ii_hilo;
            ELSE
              hdb_hilo<=hdb_hilo XOR val8_v(2); -- TOG
            END IF;
            
            IF val8_v(4)='1' THEN -- CMD_CLR
              ii_adrs<=(OTHERS =>'0');
              ii_hilo<='0';
              hdb_hilo<='0';
            END IF;
            IF val8_v(5)='1' THEN -- CMD_SET
              ii_adrs<=(OTHERS =>'1');
              ii_hilo<='0';
              hdb_hilo<='0';
            END IF;
            
          ELSE -- CMD_WAIT
            halt_v:=true;
          END IF;
          
        WHEN HD_DR =>
          -- Lecture octet
          acc<=ii_dr;
          ii_adrs<=ii_adrs+1;
          
        ----------------------------------
        WHEN SCSI_RD =>
          -- Copie données SCSI vers registre
          val8_v(7 DOWNTO 4):=x"0";
          CASE val8_v IS
            WHEN REG_ACC       => acc<=scsi_W.d;
            WHEN REG_ADRS0     => r_adrs(7 DOWNTO 0)<=scsi_w.d;
            WHEN REG_ADRS1     => r_adrs(15 DOWNTO 8)<=scsi_w.d;
            WHEN REG_ADRS2     => r_adrs(23 DOWNTO 16)<=scsi_w.d;
            WHEN REG_LUN_ADRS2 => r_lun<=scsi_w.d(7 DOWNTO 5);
                                  r_adrs(20 DOWNTO 16)<=scsi_w.d(4 DOWNTO 0);
            WHEN REG_ADRS3     => r_adrs(31 DOWNTO 24)<=scsi_w.d;
            WHEN REG_LEN1      => r_len(15 DOWNTO 8)<=scsi_w.d;
            WHEN REG_LEN0      => r_len(7 DOWNTO 0)<=scsi_w.d;
            WHEN OTHERS => NULL;
          END CASE;

          IF scsi_ack_delai='0' OR nov='1' THEN
            halt_v:=true;
          END IF;

          IF (scsi_w.ack='1' OR scsi_ack_delai='1') AND nov='0' THEN
            scsi_r_i.req<='0';
          ELSE
            scsi_r_i.req<=sel_v;
          END IF;
          
        WHEN SCSI_WR =>
          scsi_r_i.req<=sel_v;
          IF scsi_w.ack='0' THEN
            halt_v:=true;
          ELSIF scsi_r_i.req='1' THEN
            scsi_r_i.req<='0';
          END IF;

        WHEN SCSI_WR_A =>
          -- SCSI Write avec sortie si ATN
          IF scsi_w.atn='1' THEN
            scsi_r_i.req<='0';
            saut_v:=true;
          ELSE
            scsi_r_i.req<=sel_v;
            IF scsi_w.ack='0' THEN
              halt_v:=true;
            ELSIF scsi_r_i.req='1' THEN
              scsi_r_i.req<='0';
            END IF;
          END IF;

        WHEN INC_COUNT =>
          r_adrs<=r_adrs+x"0000_0001";
          r_len<=r_len - 1;
          
        ----------------------------------
        WHEN TEST_ADRS =>
          IF ssize='0' THEN
            -- 2048 bytes /sector mode
            r_adrs<=r_adrs(29 DOWNTO 0) & "00";
            r_len<=r_len(15 DOWNTO 0) & "00";
          END IF;
          saut_v:=(r_adrs>=capacity_m);

        WHEN TEST_PC =>
          -- Mode Sense Page Code
          saut_v:=(r_adrs(13 DOWNTO 8)=val8_v(5 DOWNTO 0)) XOR (val_v(8)='1');
          
        WHEN TEST_BSY =>
          saut_v:=(scsi_w.bsy=val8_v(0));
          
        WHEN TEST_ATN =>
          saut_v:=(scsi_w.atn=val8_v(0));

        WHEN TEST_EVPD =>
          saut_v:=(r_adrs(16)=val8_v(0));

        WHEN TEST_LUN =>
          saut_v:=(r_lun/="000");
          
        WHEN TEST_LEN =>
          saut_v:=(r_len(7 DOWNTO 0)<val8_v);
          
        WHEN TEST_EQ =>
          saut_v:=(acc=val8_v);

        WHEN TEST_EQH =>
          saut_v:=(acc(7 DOWNTO 5)=val8_v(7 DOWNTO 5));
          
        WHEN TEST_DBD =>
          saut_v:=(r_adrs(19)='1');
          
        WHEN GOTO   =>
          saut_v:=true;

        WHEN LOOP_CPT =>
          saut_v:=(cpt/="000000000000");
          cpt<=cpt-1;
          
        WHEN LOOP_SECCNT =>
          IF r_len/=0 THEN
            saut_v:=true;
          ELSE
            saut_v:=false;
          END IF;
          
        ----------------------------------
        WHEN SET_MODE =>
          -- Affectation discrets Mode d'après valeur immédiate
          scsi_r_i.phase<=val8_v(2 DOWNTO 0);
          
        WHEN NOP =>
          NULL;
          
      END CASE;
      
      -------------------------------------------
      IF scsi_w.bsy='0' AND scsi_w.did/=id THEN
        pc_v:=5;
      END IF;
      
      IF scsi_w.rst='1' THEN
        pc_v:=0;
        scsi_r_i.req<='0';
        halt_v:=false;
      ELSIF saut_v=true THEN
        pc_v:=to_integer(r_lab);
      ELSIF halt_v=false THEN
        pc_v:=pc+1;
      END IF;


      pc<=pc_v;
      code<=microcode(pc_v);
      
      nov<=to_std_logic(NOT halt_v);
      -------------------------------------------
      scsi_ack_delai<=scsi_w.ack;

      busy<=NOT to_std_logic(pc=6);   -- lab_debut
            
      IF hd_ack='1' THEN
        hd_wr_i<='0';
        hd_rd_i<='0';
      END IF;

      IF reset_n='0' THEN
        scsi_r_i.req<='0';
        nov<='0';
        hd_rd_i<='0';
        hd_wr_i<='0';
      END IF;

    END IF;
  END PROCESS Sequenceur;

  scsi_r<=scsi_r_i;

  hd_rd<=hd_rd_i;
  hd_wr<=hd_wr_i;

  ------------------------------------------------------------------------------
  SectorBuf0A:PROCESS(clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      hdb_dr(7 DOWNTO 0)<=
        std_logic_vector(mem0(to_integer(unsigned(hdb_hilo & hdb_adrs))));
      IF hdb_wr='1' THEN
        mem0(to_integer(unsigned(hdb_hilo & hdb_adrs))):=
          unsigned(hdb_dw(7 DOWNTO 0));
      END IF;
    END IF;
  END PROCESS SectorBuf0A;
  
  SectorBuf0B:PROCESS(clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      ii_dr16(7 DOWNTO 0)<=mem0(to_integer(ii_hilo & ii_adrs(8 DOWNTO 1)));
    END IF;
  END PROCESS SectorBuf0B;
  
  --------------------------------------
  SectorBuf1A:PROCESS(clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      hdb_dr(15 DOWNTO 8)<=
        std_logic_vector(mem1(to_integer(unsigned(hdb_hilo & hdb_adrs))));
      IF hdb_wr='1' THEN
        mem1(to_integer(unsigned(hdb_hilo & hdb_adrs))):=
          unsigned(hdb_dw(15 DOWNTO 8));
      END IF;
    END IF;
  END PROCESS SectorBuf1A;
  
  SectorBuf1B:PROCESS(clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      ii_dr16(15 DOWNTO 8)<=mem1(to_integer(ii_hilo & ii_adrs(8 DOWNTO 1)));
    END IF;
  END PROCESS SectorBuf1B;
  
  --------------------------------------
  ii_adrsd<=ii_adrs(0) WHEN rising_edge(clk);
  ii_dr<=ii_dr16(15 DOWNTO 8) WHEN ii_adrsd='1' ELSE ii_dr16(7 DOWNTO 0);
  
END ARCHITECTURE rtl;


