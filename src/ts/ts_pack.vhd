--------------------------------------------------------------------------------
-- TEM : TS
-- Paquet TacusStation
--------------------------------------------------------------------------------
-- DO 9/2010
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

PACKAGE ts_pack IS
  -- Sélections décodages d'adresses
  TYPE type_sel IS RECORD
    ram     : std_logic;
    video   : std_logic;
    dma2    : std_logic;
    esp     : std_logic;
    lance   : std_logic;
    iommu   : std_logic;
    rom     : std_logic;
    ibram   : std_logic;
    kbm     : std_logic;
    sport   : std_logic;
    rtc     : std_logic;
    timer   : std_logic;
    inter   : std_logic;
    led     : std_logic;
    auxio0  : std_logic;
    auxio1  : std_logic;
    syscon  : std_logic;
    
    vide    : std_logic;
  END RECORD;

  --------------------------------------
  -- MAC EMI <-- LANCE
  TYPE type_mac_emi_w IS RECORD
    d        : unsigned(15 DOWNTO 0);
    push     : std_logic;               -- Impulsion écriture
    stp      : std_logic;               -- Start Packet
    enp      : std_logic;               -- End Packet
    len      : unsigned(11 DOWNTO 0);   -- Longueur
    crcgen   : std_logic;               -- Emission CRC
    clr      : std_logic;               -- Réinitialisation
  END RECORD;
  
  TYPE type_mac_emi_r IS RECORD
    fifordy  : std_logic;               -- FIFO rdy
    busy     : std_logic;
  END RECORD;
  
  -- MAC REC --> LANCE
  TYPE type_mac_rec_w IS RECORD
    pop      : std_logic;               -- Dépile mot
    padr     : unsigned(47 DOWNTO 0);   -- MAC Dest
    ladrf    : unsigned(63 DOWNTO 0);   -- Filtrage HASH
    clr      : std_logic;               -- Réinitialisation
  END RECORD;
  
  TYPE type_mac_rec_r IS RECORD
    d        : unsigned(15 DOWNTO 0);   -- Données reçues
    deof     : std_logic;               -- Bit EOF synchrone avec D
    fifordy  : std_logic;               -- FIFO suffisemment pleine
    len      : unsigned(11 DOWNTO 0);   -- Longueur dernière trame
    crcok    : std_logic;               -- CRC OK dernière trame
    eof      : std_logic;               -- Fin de trame détectée (pulse)
  END RECORD;

  TYPE type_oversig IS RECORD
    v0   : uv8;
    v1   : uv8;
    v2   : uv8;
    col  : std_logic;
    grad : uint2;
  END RECORD;
  
  --------------------------------------
  -- SCSI : MSG / CD / IO
  CONSTANT SCSI_MSG_IN   : unsigned(2 DOWNTO 0) := "111";
  CONSTANT SCSI_MSG_OUT  : unsigned(2 DOWNTO 0) := "110";
  CONSTANT SCSI_STATUS   : unsigned(2 DOWNTO 0) := "011";
  CONSTANT SCSI_COMMAND  : unsigned(2 DOWNTO 0) := "010";
  CONSTANT SCSI_DATA_IN  : unsigned(2 DOWNTO 0) := "001";
  CONSTANT SCSI_DATA_OUT : unsigned(2 DOWNTO 0) := "000";
  
  -- 00..1F : 6 octets
  CONSTANT OP_TEST_UNIT_READY        : uv8 := x"00";  --  6,obli,boot
  CONSTANT OP_REQUEST_SENSE          : uv8 := x"03";  --  6,obli,boot,cdrom
  CONSTANT OP_READ_6                 : uv8 := x"08";  --  6,obli
  CONSTANT OP_WRITE_6                : uv8 := x"0A";  --  6,obli
  CONSTANT OP_INQUIRY                : uv8 := x"12";  --  6,obli,boot
  CONSTANT OP_RESERVE                : uv8 := x"16";  --  6,obli,obsol
  CONSTANT OP_RELEASE                : uv8 := x"17";  --  6,obli,obsol
  CONSTANT OP_MODE_SENSE_6           : uv8 := x"1A";  --  6,boot
  CONSTANT OP_START_STOP_UNIT        : uv8 := x"1B";  --  6
  CONSTANT OP_SEND_DIAGNOSTIC        : uv8 := x"1D";  --  6,obli
  CONSTANT OP_ALLOW_MEDIUM_REMOVAL   : uv8 := x"1E";  --  6,boot,cdrom
  
  -- 20..5F : 10 octets
  CONSTANT OP_READ_CAPACITY          : uv8 := x"25";  -- 10,obli,boot
  CONSTANT OP_READ_10                : uv8 := x"28";  -- 10,obli,boot
  CONSTANT OP_WRITE_10               : uv8 := x"2A";  -- 10,obli,boot
  CONSTANT OP_VERIFY                 : uv8 := x"2F";  -- 10
  CONSTANT OP_SYNCHRONIZE_CACHE      : uv8 := x"35";  -- 10
  CONSTANT OP_READ_TOC               : uv8 := x"43";  -- 10, boot, cdrom
  CONSTANT OP_MODE_SENSE_10          : uv8 := x"5A";  -- 10
  CONSTANT OP_PERSISTENT_RESERVE_IN  : uv8 := x"5E";  -- 10
  CONSTANT OP_PERSISTENT_RESERVE_OUT : uv8 := x"5F";  -- 10
  
  -- A0..BF : 12 octets
  CONSTANT OP_REPORT_LUNS            : uv8 := x"A0";  -- 12, boot, SCSI-3
  CONSTANT OP_READ_12                : uv8 := x"A8";  -- 12
  CONSTANT OP_WRITE_12               : uv8 := x"AA";  -- 12
  
  CONSTANT OP_GET_CONFIGURATION      : uv8 := x"46";
  CONSTANT OP_SERVICE_ACTION_IN      : uv8 := x"00";
  
  -- STATUS
  CONSTANT STAT_GOOD          : uv8 := x"00";  -- Good
  CONSTANT STAT_CHECK         : uv8 := x"02";  -- Check Condition
  CONSTANT STAT_BUSY          : uv8 := x"08";  -- Busy
  
  CONSTANT STAT_INTERMEDIATE  : uv8 := x"10";  -- Intermediate / Good
  
  CONSTANT SENSE_NO_SENSE        : uv8 := x"00";
  CONSTANT SENSE_RECOVERED_ERROR : uv8 := x"01";
  CONSTANT SENSE_NOT_READY       : uv8 := x"02";
  CONSTANT SENSE_MEDIUM_ERROR    : uv8 := x"03";
  CONSTANT SENSE_HARDWARE_ERROR  : uv8 := x"04";
  CONSTANT SENSE_ILLEGAL_REQUEST : uv8 := x"05";
  CONSTANT SENSE_UNIT_ATTENTION  : uv8 := x"06";
  CONSTANT SENSE_DATA_PROTECT    : uv8 := x"07";
  CONSTANT SENSE_BLANK_CHECK     : uv8 := x"08";
  CONSTANT SENSE_VENDOR_SPECIFIC : uv8 := x"09";
  CONSTANT SENSE_COPY_ABORTED    : uv8 := x"0A";
  CONSTANT SENSE_ABORTED_COMMAND : uv8 := x"0B";
  CONSTANT SENSE_EQUAL           : uv8 := x"0C";
  CONSTANT SENSE_VOLUME_OVERFLOW : uv8 := x"0D";
  CONSTANT SENSE_MISCOMPARE      : uv8 := x"0E";
  CONSTANT SENSE_RESERVED        : uv8 := x"0F";
  
  TYPE type_scsi_w IS RECORD
   d       : uv8;        -- Données ctrl -> disque
   ack     : std_logic;
   bsy     : std_logic;  -- Activité sur le bus
   atn     : std_logic;  -- Attention
   did     : uv3;        -- Destination ID
   rst     : std_logic;  -- RESET
  END RECORD;
  
  TYPE type_scsi_r IS RECORD
   d     : uv8;                    -- Données disque -> ctrl
   req   : std_logic;
   phase : unsigned(2 DOWNTO 0);   -- MSG / CD / IO
   sel   : std_logic;
   d_pc  : uv10;
  END RECORD;

  TYPE type_sd_reg_w IS RECORD
    d   : uv32;
    wr0 : std_logic;
    wr1 : std_logic;
  END RECORD;
  
  TYPE type_sd_reg_r IS RECORD
    d0 : uv32;
    d1 : uv32;
  END RECORD;
  
  CONSTANT HWCONF_SP605    : uv8 :=x"01"; -- Xilinx SP605
  
  CONSTANT HWCONF_C5G      : uv8 :=x"11"; -- Terasic CycloneV GX
  CONSTANT HWCONF_MiSTer   : uv8 :=x"12"; -- Terasic DE10nano +  MiSTer
  
END PACKAGE ts_pack;

