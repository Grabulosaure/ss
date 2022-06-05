----*-vhdl-*--------------------------------------------------------------------
-- TEM : TS
-- SCSI <-> MIST/MISTER
--------------------------------------------------------------------------------
-- DO 2/2018
--------------------------------------------------------------------------------
-- Emulation disque dur SCSI
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

ENTITY scsi_mist IS
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
    
    -- Global
    clk      : IN std_logic;
    reset_n  : IN std_logic
    );
END ENTITY scsi_mist;

--##############################################################################

ARCHITECTURE rtl OF scsi_mist IS

  CONSTANT STAT_SYSACE       : uv8 := x"00";

  CONSTANT INQ_VID : string(1 TO 8)  := "TACUS   ";
  CONSTANT INQ_PID : string(1 TO 16) := "Hard Disk MISTER";
  CONSTANT INQ_RID : string(1 TO 4)  := "0.10";
  
  SIGNAL hd_wr_i,hd_rd_i : std_logic;
  
  SIGNAL ii_wr,ii_wr0,ii_wr1,ii_hilo : std_logic;
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
  SIGNAL r_len  : uv16;                   -- Nombre de secteurs
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
  
  %  MICROCODE

  SIGNAL code : type_microcode;
  
BEGIN

  --------------------------------------------------------
  %-- RESET, adresse 0
  %reset:
  %           NOP       Z&x"00"
  %           SET_MODE  Z&"00000"&SCSI_MSG_OUT
  %           NOP       Z&x"00"
  %           NOP       Z&x"00"
  %           LDS_I     Z&SENSE_NO_SENSE  -- RAZ Sense Key
  %--------------------------------------------------------
  %-- Attente activité sur le BUS
  %           LAB       lab_debut
  %lab_debut:
  %           TEST_BSY  Z&x"00"
  %--------------------------------------------------------
  %-- Réception commande (6,10,12 octets)
  %           RAZ_REG   Z&x"00"               -- Remet à Zéro
  %           NOP       Z&x"00"
  %           LAB       lab_nomsg
  %           TEST_ATN  Z&x"00"
  %           SET_MODE  Z&"00000"&SCSI_MSG_OUT  -- Message avant la commande
  %           NOP       Z&x"00"
  %           SCSI_RD   Z&REG_ACC
  
  %-- Pour NextSTEP
  %           NOP       Z&x"00"
  %           NOP       Z&x"00"
  %           TEST_ATN  Z&x"00"
  %           NOP       Z&x"00"
  %           SCSI_RD   Z&REG_ACC       -- Lecture second octet message
  %           NOP       Z&x"00"
  %           LAB       lab_good
  %           TEST_EQ   Z&x"00"         -- Si Zéro : Abandonne : NextStep

  %           LAB       lab_opx       -- Sinon, on considère comme une commande
  %           SET_MODE  Z&"00000"&SCSI_COMMAND
  %           NOP       Z&x"00"
  %           GOTO      Z&x"00"
    
  %lab_nomsg: NOP       Z&x"00"
  %           SET_MODE  Z&"00000"&SCSI_COMMAND
  %           NOP       Z&x"00"
  
  %--------------------------------------------------------
  %-- Dispatch commandes
  %           SCSI_RD   Z&REG_ACC
  %           SCSI_RD   Z&REG_LUN_ADRS2   -- 1 : Lun [2:0] | Adrs[20:16]
  %lab_opx:
  %           LAB       lab_op_read_6
  %           TEST_EQ   Z&OP_READ_6
  %           LAB       lab_op_read_10
  %           TEST_EQ   Z&OP_READ_10
  %           LAB       lab_op_write_6
  %           TEST_EQ   Z&OP_WRITE_6
  %           LAB       lab_op_write_10
  %           TEST_EQ   Z&OP_WRITE_10
  %           LAB       lab_op_inquiry
  %           TEST_EQ   Z&OP_INQUIRY
  %           LAB       lab_op_test_unit_ready  -- Ne fait rien
  %           TEST_EQ   Z&OP_TEST_UNIT_READY
  %           TEST_EQ   Z&OP_START_STOP_UNIT
  %           TEST_EQ   Z&OP_ALLOW_MEDIUM_REMOVAL
  %           LAB       lab_op_mode_sense_6
  %           TEST_EQ   Z&OP_MODE_SENSE_6
  %           LAB       lab_op_read_capacity
  %           TEST_EQ   Z&OP_READ_CAPACITY
  %           LAB       lab_op_request_sense
  %           TEST_EQ   Z&OP_REQUEST_SENSE
  %           LAB       lab_op_synchronize_cache
  %           TEST_EQ   Z&OP_SYNCHRONIZE_CACHE
  %-- Sinon, la commande est inconnue !
  %           LAB       lab_err_6
  %           TEST_EQH  Z&x"00"
  %           LAB       lab_err_10
  %           TEST_EQH  Z&x"20"
  %           TEST_EQH  Z&x"40"
  %           LAB       lab_err_12
  %           TEST_EQH  Z&x"A0"
  %           LAB       lab_err_16
  %           TEST_EQH  Z&x"80"
  
  %           LAB       lab_error_address
  %           GOTO      Z&x"00"
  
  %--------------------------------------------------------
  %-- Commande READ_6 (08h)
  %lab_op_read_6:
  %           SCSI_RD   Z&REG_ADRS1       -- 2 : Adrs[15:8]
  %           SCSI_RD   Z&REG_ADRS0       -- 3 : Adrs[7:0]
  %           SCSI_RD   Z&REG_LEN0        -- 4 : Len[7:0]
  %           SCSI_RD   Z&REG_CONTROL     -- 5 : Control
  %           FIXLEN    Z&x"00"
  %           LAB       lab_read_op
  %           GOTO      Z&x"00"
  %-- Commande READ_10 (28h)
  %lab_op_read_10:
  %           SCSI_RD   Z&REG_ADRS3       -- 2 : Adrs[31:24]
  %           SCSI_RD   Z&REG_ADRS2       -- 3 : Adrs[23:16]
  %           SCSI_RD   Z&REG_ADRS1       -- 4 : Adrs[15:8]
  %           SCSI_RD   Z&REG_ADRS0       -- 5 : Adrs[7:0]
  %           SCSI_RD   Z&REG_LEN1        -- 6 : Ignore
  %           SCSI_RD   Z&REG_LEN1        -- 7 : Len[15:8]
  %           SCSI_RD   Z&REG_LEN0        -- 8 : Len[7:0]
  %           SCSI_RD   Z&REG_CONTROL     -- 9 : Control
  %lab_read_op:
  %           LAB       lab_error_address
  %           TEST_ADRS Z&x"00"
  %           NOP       Z&x"00"
  %           SET_MODE  Z&"00000"&SCSI_DATA_IN
  %           NOP       Z&x"00"
  %           HD_CMD    Z&(CMD_WAIT OR CMD_CLR OR CMD_RD)
  %           LAB       lab_read_loop
  %lab_read_loop:
  %           LDCPT     Z&x"0F"           -- 16 blocs de 32octets par secteur
  %           INC_COUNT Z&x"00"
  %           HD_CMD    Z&(CMD_WAIT OR CMD_TOG OR CMD_RD)
  %           LAB       lab_read_loop2
  %lab_read_loop2:
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 0
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 1
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 2
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 3
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 4
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 5
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 6
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 7
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 8
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 9
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 10
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 11
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 12
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 13
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 14
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 15
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 16
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 17
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 18
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 19
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 20
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 21
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 22
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 23
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 24
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 25
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 26
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 27
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 28
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 29
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 30
  %           HD_DR     Z&x"00"
  %           SCSI_WR   Z&REG_ACC         -- 31
  %-- Bouclage blocs par secteur
  %           LOOP_CPT  Z&x"00"
  %-- Bouclage secteurs
  %           LAB       lab_read_loop
  %           HD_CMD    Z&CMD_TOG2
  %           LOOP_SECCNT Z&x"00"

  %           LAB       lab_good
  %           GOTO      Z&x"00"

  %--------------------------------------------------------
  %-- Exécution commande WRITE_6 (0Ah)
  %lab_op_write_6:
  %           SCSI_RD   Z&REG_ADRS1       -- 2 : Adrs[15:8]
  %           SCSI_RD   Z&REG_ADRS0       -- 3 : Adrs[7:0]
  %           SCSI_RD   Z&REG_LEN0        -- 4 : Len[7:0]
  %           SCSI_RD   Z&REG_CONTROL     -- 5 : Control
  %           FIXLEN    Z&x"00"
  %           LAB       lab_write_op
  %           GOTO      Z&x"00"
  %-- Commande WRITE_10 (2Ah)
  %lab_op_write_10:
  %           SCSI_RD   Z&REG_ADRS3       -- 2 : Adrs[31:24]
  %           SCSI_RD   Z&REG_ADRS2       -- 3 : Adrs[23:16]
  %           SCSI_RD   Z&REG_ADRS1       -- 4 : Adrs[15:8]
  %           SCSI_RD   Z&REG_ADRS0       -- 5 : Adrs[7:0]
  %           SCSI_RD   Z&REG_LEN1        -- 6 : Ignore
  %           SCSI_RD   Z&REG_LEN1        -- 7 : Len[15:8]
  %           SCSI_RD   Z&REG_LEN0        -- 8 : Len[7:0]
  %           SCSI_RD   Z&REG_CONTROL     -- 9 : Control
  %lab_write_op:
  %           LAB       lab_error_address
  %           TEST_ADRS Z&x"00"
  %           NOP       Z&x"00"
  %           SET_MODE  Z&"00000"&SCSI_DATA_OUT
  %           NOP       Z&x"00"
  %           HD_CMD    Z&(CMD_WAIT OR CMD_SET)
  %           LAB       lab_write_loop
  %lab_write_loop:
  %           LDCPT     Z&x"0F"           -- 16 blocs de 32octets par secteur
  %           LAB       lab_write_loop2
  %lab_write_loop2:
  %           SCSI_RD   Z&REG_ACC         -- 0
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 1
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 2
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 3
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 4
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 5
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 6
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 7
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 8
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 9
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 10
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 11
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 12
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 13
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 14
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 15
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 16
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 17
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 18
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 19
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 20
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 21
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 22
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 23
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 24
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 25
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 26
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 27
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 28
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 29
  %           HD_DW     Z&x"00"
  %           SCSI_RD   Z&REG_ACC         -- 30
  %           HD_DW     Z&x"00"
  %           HD_CMDWAIT   Z&x"00"    
  %           SCSI_RD   Z&REG_ACC         -- 31
  %           HD_DW     Z&x"00"
  %-- Bouclage blocs par secteur
  %           LOOP_CPT  Z&x"00"
  %-- Bouclage secteurs
--  %           HD_CMD    Z&(CMD_WAIT)
--  %           NOP       Z&x"00"
  %           HD_CMD    Z&(CMD_WR OR CMD_TOG OR CMD_TOG2)
  %           INC_COUNT Z&x"00"
  %           LAB       lab_write_loop
  %           LOOP_SECCNT Z&x"00"

  %           NOP       Z&x"00"
--  %           HD_CMD    Z&(CMD_WAIT)
--  %           NOP       Z&x"00"
--  %           NOP       Z&x"00"
  %           LAB       lab_good
  %           GOTO      Z&x"00"
    
  %--------------------------------------------------------
  %-- Exécution commande INQUIRY §8.2.5
  %lab_op_inquiry:
  %           SCSI_RD   Z&REG_ACC         -- 2 : Page Code
  %           SCSI_RD   Z&REG_ADRS0       -- 3 : Reserved
  %           SCSI_RD   Z&REG_LEN0        -- 4 : Allocation Length
  %           SCSI_RD   Z&REG_CONTROL     -- 5 : Control
  
  %           LAB       lab_error
  %           TEST_LUN  Z&x"00"
  %           TEST_EVPD Z&x"01"
  %           TEST_LEN  Z&x"24"
  %           NOP       Z&x"00"
  %           SET_MODE  Z&"00000"&SCSI_DATA_IN
  %           NOP       Z&x"00"
  %           LDA_I     Z&x"00"           -- Hard Disk
  %           SCSI_WR   Z&REG_ACC -- 0: Per. Qualifier[2;0] | DevType [4:0]
  %           LDA_I     Z&x"00"           -- Not Removable,
  %           SCSI_WR   Z&REG_ACC -- 1: RMB | Per. Modifier [6:0]
  %           LDA_I     Z&x"02"           -- SCSI-2
  %           SCSI_WR   Z&REG_ACC -- 2: ISO / ECMA / ANSI Version
  %           LDA_I     Z&x"00"           -- Response format=2
  %           SCSI_WR   Z&REG_ACC -- 3: AENC / TrmIOP / Response Format
  %           LDA_I     Z&x"1F"           -- 36-5 = 31
  %           SCSI_WR   Z&REG_ACC -- 4: Additional Length
  %           LDA_I     Z&x"00"
  %           SCSI_WR   Z&REG_ACC -- 5: Reserved
  %           LDA_I     Z&x"00"
  %           SCSI_WR   Z&REG_ACC -- 6: Reserved
  %           LDA_I     Z&x"10"           --SYNC=1
  %           SCSI_WR   Z&REG_ACC -- 7: RelAdr/ WBus/Sync/ Link/CmdQue/SftRe
  %           LDA_I     Z&to_unsigned(character'pos(INQ_VID(1)),8)
  %           SCSI_WR   Z&REG_ACC -- 8: Vendor ID
  %           LDA_I     Z&to_unsigned(character'pos(INQ_VID(2)),8)
  %           SCSI_WR   Z&REG_ACC -- 9: Vendor ID
  %           LDA_I     Z&to_unsigned(character'pos(INQ_VID(3)),8)
  %           SCSI_WR   Z&REG_ACC --10: Vendor ID
  %           LDA_I     Z&to_unsigned(character'pos(INQ_VID(4)),8)
  %           SCSI_WR   Z&REG_ACC --11: Vendor ID
  %           LDA_I     Z&to_unsigned(character'pos(INQ_VID(5)),8)
  %           SCSI_WR   Z&REG_ACC --12: Vendor ID
  %           LDA_I     Z&to_unsigned(character'pos(INQ_VID(6)),8)
  %           SCSI_WR   Z&REG_ACC --13: Vendor ID
  %           LDA_I     Z&to_unsigned(character'pos(INQ_VID(7)),8)
  %           SCSI_WR   Z&REG_ACC --14: Vendor ID
  %           LDA_I     Z&to_unsigned(character'pos(INQ_VID(8)),8)
  %           SCSI_WR   Z&REG_ACC --15: Vendor ID
  %           LDA_I     Z&to_unsigned(character'pos(INQ_PID(1)),8)
  %           SCSI_WR   Z&REG_ACC --16: Product ID
  %           LDA_I     Z&to_unsigned(character'pos(INQ_PID(2)),8)
  %           SCSI_WR   Z&REG_ACC --17: Product ID
  %           LDA_I     Z&to_unsigned(character'pos(INQ_PID(3)),8)
  %           SCSI_WR   Z&REG_ACC --18: Product ID
  %           LDA_I     Z&to_unsigned(character'pos(INQ_PID(4)),8)
  %           SCSI_WR   Z&REG_ACC --19: Product ID
  %           LDA_I     Z&to_unsigned(character'pos(INQ_PID(5)),8)
  %           SCSI_WR   Z&REG_ACC --20: Product ID
  %           LDA_I     Z&to_unsigned(character'pos(INQ_PID(6)),8)
  %           SCSI_WR   Z&REG_ACC --21: Product ID
  %           LDA_I     Z&to_unsigned(character'pos(INQ_PID(7)),8)
  %           SCSI_WR   Z&REG_ACC --22: Product ID
  %           LDA_I     Z&to_unsigned(character'pos(INQ_PID(8)),8)
  %           SCSI_WR   Z&REG_ACC --23: Product ID
  %           LDA_I     Z&to_unsigned(character'pos(INQ_PID(9)),8)
  %           SCSI_WR   Z&REG_ACC --24: Product ID
  %           LDA_I     Z&to_unsigned(character'pos(INQ_PID(10)),8)
  %           SCSI_WR   Z&REG_ACC --25: Product ID
  %           LDA_I     Z&to_unsigned(character'pos(INQ_PID(11)),8)
  %           SCSI_WR   Z&REG_ACC --26: Product ID
  %           LDA_I     Z&to_unsigned(character'pos(INQ_PID(12)),8)
  %           SCSI_WR   Z&REG_ACC --27: Product ID
  %           LDA_I     Z&to_unsigned(character'pos(INQ_PID(13)),8)
  %           SCSI_WR   Z&REG_ACC --28: Product ID
  %           LDA_I     Z&to_unsigned(character'pos(INQ_PID(14)),8)
  %           SCSI_WR   Z&REG_ACC --29: Product ID
  %           LDA_I     Z&to_unsigned(character'pos(INQ_PID(15)),8)
  %           SCSI_WR   Z&REG_ACC --30: Product ID
  %           LDA_I     Z&to_unsigned(character'pos(INQ_PID(16)),8)
  %           SCSI_WR   Z&REG_ACC --31: Product ID
  %           LDA_I     Z&to_unsigned(character'pos(INQ_RID(1)),8)
  %           SCSI_WR   Z&REG_ACC --32: Product Revision
  %           LDA_I     Z&to_unsigned(character'pos(INQ_RID(2)),8)
  %           SCSI_WR   Z&REG_ACC --33: Product Revision
  %           LDA_I     Z&to_unsigned(character'pos(INQ_RID(3)),8)
  %           SCSI_WR   Z&REG_ACC --34: Product Revision
  %           LDA_I     Z&to_unsigned(character'pos(INQ_RID(4)),8)

  %           SCSI_WR   Z&REG_ACC --35: Product Revision
  %--           TEST_LEN Z&x"25" lab_good
  %--           SUB_CPT     Z&x"24"         -- len=len-36
  %--           SUB_CPT     Z&x"23"         -- len=len-36
  %-- Padding jusqu'à LEN
  %--lab_padd_inquiry:
  %--           LDA_I    Z&x"00"
  %--           SCSI_WR  Z&REG_ACC
  %--           LOOP_SECCNT x"00" lab_padd_inquiry
  %           LAB       lab_good
  %           GOTO      Z&x"00"

  %--------------------------------------------------------
  %-- Exécution commande MODE_SENSE_6 §8.2.10, §8.3.3, §9.3.3
  %lab_op_mode_sense_6:
  %           SCSI_RD   Z&REG_ADRS1       -- 2 : PC
  %           SCSI_RD   Z&REG_ADRS0       -- 3 : Reserved
  %           SCSI_RD   Z&REG_LEN0        -- 4 : Allocation length
  %           SCSI_RD   Z&REG_CONTROL     -- 5 : Control
  %           NOP       Z&x"00"
  %           SET_MODE  Z&"00000"&SCSI_DATA_IN
  %           NOP       Z&x"00"
  %           LDA_I     Z&x"00"           -- MD_Len=0
  %           SCSI_WR   Z&REG_ACC -- 0 : Mode Data Length
  %           LDA_I     Z&x"00"           -- Type=0
  %           SCSI_WR   Z&REG_ACC -- 1 : Medium Type
  %           LDA_I     Z&x"00"           -- WP=0 : No Write Protect
  %           SCSI_WR   Z&REG_ACC -- 2 : WP | Res2 | DPOFUA | Res4
  %           LDA_I     Z&x"08"           -- BD_Len=8
  %           SCSI_WR   Z&REG_ACC -- 3 : Block Descriptor Length
  %           LDA_I     Z&x"00"           -- 0    
  %           SCSI_WR   Z&REG_ACC -- 4 : Block Descriptor : Density
  %           LDA_R     Z&REG_CAPA2
  %           SCSI_WR   Z&REG_ACC -- 5 : Block Descriptor : Num of blk[23:16]
  %           LDA_R     Z&REG_CAPA1
  %           SCSI_WR   Z&REG_ACC -- 6 : Block Descriptor : Num of blk[15:8]
  %           LDA_R     Z&REG_CAPA0
  %           SCSI_WR   Z&REG_ACC -- 7 : Block Descriptor : Num of blk[7:0]
  %           LDA_I     Z&x"00"           -- 0
  %           SCSI_WR   Z&REG_ACC -- 8 : Block Descriptor : Reserved
  %           LDA_I     Z&x"00"           -- 0
  %           SCSI_WR   Z&REG_ACC -- 9 : Block Descriptor : Block Len[23:16]
  %           LDA_I     Z&x"02"           -- 512 octets
  %           SCSI_WR   Z&REG_ACC --10 : Block Descriptor : Block Len[15:8]
  %           LDA_I     Z&x"00"           -- 0
  %           SCSI_WR   Z&REG_ACC --11 : Block Descriptor : Block Len[7:0]
  %           LAB       lab_good
  %           GOTO      Z&x"00"
  
  %--------------------------------------------------------
  %-- Exécution commande READ_CAPACITY §9.2.7
  %lab_op_read_capacity:
  %           SCSI_RD   Z&REG_ADRS3       -- 2 : Adrs[31:24]
  %           SCSI_RD   Z&REG_ADRS2       -- 3 : Adrs[23:16]
  %           SCSI_RD   Z&REG_ADRS1       -- 4 : Adrs[15:8]
  %           SCSI_RD   Z&REG_ADRS0       -- 5 : Adrs[7:0]
  %           SCSI_RD   Z&REG_LEN1        -- 6 : Reserved
  %           SCSI_RD   Z&REG_LEN1        -- 7 : Reserved
  %           SCSI_RD   Z&REG_LEN0        -- 8 : Reserved | PMI
  %           SCSI_RD   Z&REG_CONTROL     -- 9 : Control
  %           NOP       Z&x"00"
  %           SET_MODE  Z&"00000"&SCSI_DATA_IN
  %           NOP       Z&x"00"
  %           LDA_R     Z&REG_CAPA3
  %           SCSI_WR   Z&REG_ACC -- 0: Block Addr[31:24]
  %           LDA_R     Z&REG_CAPA2
  %           SCSI_WR   Z&REG_ACC -- 1: Block Addr[23:16]
  %           LDA_R     Z&REG_CAPA1
  %           SCSI_WR   Z&REG_ACC -- 2: Block Addr[15:8]
  %           LDA_R     Z&REG_CAPA0
  %           SCSI_WR   Z&REG_ACC -- 3: Block Addr[7:0]
  %           LDA_I     Z&x"00"
  %           SCSI_WR   Z&REG_ACC -- 4: Block Len[31:24]
  %           LDA_I     Z&x"00"
  %           SCSI_WR   Z&REG_ACC -- 5: Block Len[23:16]
  %           LDA_I     Z&x"02"
  %           SCSI_WR   Z&REG_ACC -- 6: Block Len[15:8]
  %           LDA_I     Z&x"00"
  %           SCSI_WR   Z&REG_ACC -- 7: Block Len[7:0]
  %           LAB       lab_good
  %           GOTO      Z&x"00"
  
  %--------------------------------------------------------
  %-- Exécution commande REQUEST_SENSE §8.2.14
  %lab_op_request_sense:
  %           SCSI_RD   Z&REG_ADRS1       -- 2 : Reserved
  %           SCSI_RD   Z&REG_ADRS0       -- 3 : Reserved
  %           SCSI_RD   Z&REG_LEN0        -- 4 : Allocation Length
  %           SCSI_RD   Z&REG_CONTROL     -- 5 : Control
  %           NOP       Z&x"00"
  %           SET_MODE  Z&"00000"&SCSI_DATA_IN
  %           LAB       lab_error
  %           TEST_LEN  Z&x"07"           -- Si alloc len est trop court...
  %           LAB       lab_reqsense_badlun
  %           TEST_LUN  Z&x"00"

  %           LDA_I     Z&x"F0"           -- 0: 70=Current Errors 80=Valid
  %           SCSI_WR   Z&REG_ACC
  %           LDA_I     Z&x"00"           -- 1: Segment Number
  %           SCSI_WR   Z&REG_ACC
  %           LDA_R     z&REG_SENSE       -- 2: Sense Key
  %           LAB       lab_reqsense
  %           GOTO      Z&x"00"
      
  %lab_reqsense_badlun:
  %           LDA_I     Z&x"F0"           -- 0: 70=Current Errors 80=Valid
  %           SCSI_WR   Z&REG_ACC
  %           LDA_I     Z&x"00"           -- 1: Segment Number
  %           SCSI_WR   Z&REG_ACC
  %           LDA_I     Z&SENSE_ILLEGAL_REQUEST -- 2: Sense Key
  %lab_reqsense:
  %           SCSI_WR   Z&REG_ACC
  %           LDA_I     Z&x"00"           -- 3: Information 0
  %           SCSI_WR   Z&REG_ACC
  %           LDA_I     Z&x"00"           -- 4: Information 1
  %           SCSI_WR   Z&REG_ACC
  %           LDA_R     Z&x"00"           -- 5: Information 2
  %           SCSI_WR   Z&REG_ACC
  %           LDA_I     Z&x"00"           -- 6: Information 3
  %           SCSI_WR   Z&REG_ACC
  %           LDA_I     Z&x"00"           -- 7: Additional sense lenght
  %           SCSI_WR   Z&REG_ACC
  %           LDS_I     Z&SENSE_NO_SENSE -- RAZ SENSE
  %           LAB       lab_good
  %           GOTO      Z&x"00"
  
  %--------------------------------------------------------
  %-- Exécution commande TEST_UNIT_READY : Toujours prêt
  %lab_op_test_unit_ready:
  %           SCSI_RD   Z&REG_ADRS1       -- 2 : Reserved
  %           SCSI_RD   Z&REG_ADRS0       -- 3 : Reserved
  %           SCSI_RD   Z&REG_LEN0        -- 4 : Reserved
  %           SCSI_RD   Z&REG_CONTROL     -- 5 : Control
  %           LAB       lab_good
  %           GOTO      Z&x"00"
  
  %--------------------------------------------------------
  %-- Commande SYNCHRONIZE_CACHE (35h)
  %lab_op_synchronize_cache:
  %           SCSI_RD   Z&REG_ADRS3       -- 2 : Adrs[31:24]
  %           SCSI_RD   Z&REG_ADRS2       -- 3 : Adrs[23:16]
  %           SCSI_RD   Z&REG_ADRS1       -- 4 : Adrs[15:8]
  %           SCSI_RD   Z&REG_ADRS0       -- 5 : Adrs[7:0]
  %           SCSI_RD   Z&REG_LEN1        -- 6 : Reserved
  %           SCSI_RD   Z&REG_LEN1        -- 7 : Len[15:8]
  %           SCSI_RD   Z&REG_LEN0        -- 8 : Len[7:0]
  %           SCSI_RD   Z&REG_CONTROL     -- 9 : Control
  %           LAB       lab_good
  %           GOTO      Z&x"00"
  
  %--------------------------------------------------------
  %-- Envoi Status
  %lab_good:  NOP       Z&x"00"
  %           SET_MODE  Z&"00000"&SCSI_STATUS
  %           LAB       lab_debut         -- Délai
  %           LDA_I     Z&STAT_GOOD
  %           SCSI_WR_A Z&REG_ACC
  %           NOP       Z&x"00"           -- Délai
  %           NOP       Z&x"00"           -- Délai

  %-- Envoi message final
  %lab_msgin:
  %           NOP       Z&x"00"
  %           SET_MODE  Z&"00000"&SCSI_MSG_IN
  %           LAB       lab_wait_bsy
  %           LDA_I     Z&x"00"           -- Message "Command Complete"
  %           SCSI_WR_A Z&REG_ACC
  %lab_wait_bsy:
  %           TEST_BSY  Z&x"01"
  %           LAB       lab_debut         -- Délai
  %           GOTO      Z&x"00"
  
  %--------------------------------------------------------
  %lab_err_16:
  %           SCSI_RD   Z&REG_ACC
  %           SCSI_RD   Z&REG_ACC
  %           SCSI_RD   Z&REG_ACC
  %           SCSI_RD   Z&REG_ACC
  %lab_err_12:
  %           SCSI_RD   Z&REG_ACC
  %           SCSI_RD   Z&REG_ACC
  %lab_err_10:
  %           SCSI_RD   Z&REG_ACC
  %           SCSI_RD   Z&REG_ACC
  %           SCSI_RD   Z&REG_ACC
  %           SCSI_RD   Z&REG_ACC
  %lab_err_6:
  %           SCSI_RD   Z&REG_ACC
  %           SCSI_RD   Z&REG_ACC
  %           SCSI_RD   Z&REG_ACC
  %           SCSI_RD   Z&REG_ACC
  %           NOP       Z&x"00"
  %           NOP       Z&x"00"

  %lab_error_address:
  %           LDS_I     Z&SENSE_ILLEGAL_REQUEST
  %lab_error:
  %           NOP       Z&x"00"
  %           SET_MODE  Z&"00000"&SCSI_STATUS
  %           LAB       lab_debut
  %           LDA_I     Z&STAT_CHECK
  %           SCSI_WR_A Z&REG_ACC       -- Délai
  %           LAB       lab_msgin
  %           GOTO      Z&x"00"

-- <AFAIRE>
--   OP_REPORT_LUNS
--   OP_REQUEST_SENSE        obli,boot,cdrom
--   OP_ALLOW_MEDIUM_REMOVAL boot,cdrom
--   OP_SEND_DIAGNOSTIC      obli
--   OP_START_STOP_UNIT      
--   OP_MODE_SENSE_10        
--   OP_RESERVE              obli,obsol
--   OP_RELEASE              obli,obsol
--   OP_VERIFY               
--   OP_SYNCHRONIZE_CACHE    
--   OP_READ_TOC             boot, cdrom
  
  ------------------------------------------------------------------------------
  -- Séquenceur
  Sequenceur: PROCESS (clk,reset_n)
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
      capacity_m<=unsigned(hd_size(40 DOWNTO 9)) -1; -- Last sector number
      ii_wr<='0';
      
      -------------------------------------------
      halt_v:=false;
      saut_v:=false;
      
      CASE op_v IS
        ----------------------------------
        WHEN LDA_I =>
          -- Chargement registre ACC, immédiat
          acc<=val8_v;

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
          r_len <=x"0000";

        WHEN FIXLEN =>
          -- Si len 00 -->  len = 256
          IF r_len(7 DOWNTO 0)=x"00" THEN
            r_len<=x"0100";
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

        WHEN HD_CMDWAIT =>
          IF (hd_wr_i='1' OR hd_rd_i='1' OR hd_ack='1') AND
            cpt="000000000000" THEN
            halt_v:=true;
          END IF;
          
        WHEN HD_DR =>
          -- Lecture octet
          acc<=ii_dr;
          ii_adrs<=ii_adrs+1;
          
        WHEN HD_DW =>
          -- Écriture octet
          ii_dw<=acc;
          ii_wr<='1';
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
          r_len<=r_len-x"0001";
          
        ----------------------------------
        WHEN TEST_ADRS =>
          saut_v:=(r_adrs>=capacity_m);
                   
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
          
        WHEN GOTO   =>
          saut_v:=true;

        WHEN LOOP_CPT =>
          saut_v:=(cpt/="000000000000");
          cpt<=cpt-1;
          
        WHEN LOOP_SECCNT =>
          IF r_len/=x"0000" THEN
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
  ii_wr0<=ii_wr AND NOT ii_adrs(0);
  ii_wr1<=ii_wr AND ii_adrs(0);
  
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
      IF ii_wr0='1' THEN
        mem0(to_integer(ii_hilo & ii_adrs(8 DOWNTO 1))):=ii_dw;
      END IF;
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
      IF ii_wr1='1' THEN
        mem1(to_integer(ii_hilo & ii_adrs(8 DOWNTO 1))):=ii_dw;
      END IF;
    END IF;
  END PROCESS SectorBuf1B;
  
  --------------------------------------
  ii_adrsd<=ii_adrs(0) WHEN rising_edge(clk);
  ii_dr<=ii_dr16(15 DOWNTO 8) WHEN ii_adrsd='1' ELSE ii_dr16(7 DOWNTO 0);
  
END ARCHITECTURE rtl;


