----*-vhdl-*--------------------------------------------------------------------
-- TEM : TS
-- SCSI <-> SD/MMC
--------------------------------------------------------------------------------
-- DO 2/2015
--------------------------------------------------------------------------------
-- Emulation disque dur SCSI
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

-- SD card :
--    - Acquiert   CMD,DATA[] au moment du front montant de CLK : Ts=Th<5ns
--    - Met à jour CMD,DATA[] après un front montant de CLK     : Tdo<14ns

--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.ts_pack.ALL;

ENTITY scsi_sd IS
  GENERIC (
    SYSFREQ : natural :=50_000_000);
  PORT (
    scsi_w   : IN  type_scsi_w;
    scsi_r   : OUT type_scsi_r;
    id       : IN  unsigned(2 DOWNTO 0);
    busy     : OUT std_logic;
    
    -- Interface SD
    sd_clk_o  : OUT std_logic;
    sd_clk_i  : IN  std_logic;
    
    sd_dat_o  : OUT uv4;
    sd_dat_i  : IN  uv4;
    sd_dat_en : OUT std_logic;
    
    sd_cmd_o  : OUT std_logic;
    sd_cmd_i  : IN  std_logic;
    sd_cmd_en : OUT std_logic;

    -- Registres
    reg_w     : IN   type_sd_reg_w;
    reg_r     : OUT  type_sd_reg_r;
    
    -- Global
    clk      : IN std_logic;
    reset_na : IN std_logic
    );
END ENTITY scsi_sd;

--##############################################################################

ARCHITECTURE rtl OF scsi_sd IS

  CONSTANT STAT_SYSACE       : uv8 := x"00";

  CONSTANT INQ_VID : string(1 TO 8)  := "TACUS   ";
  CONSTANT INQ_PID : string(1 TO 16) := "Hard Disk SD/MMC";
  CONSTANT INQ_RID : string(1 TO 4)  := "0.10";

  -- SD/MMC : REGS
  CONSTANT SDFREQ : natural := SYSFREQ/200000/2-1;  -- 200kHz
  SIGNAL sdcpt : natural RANGE 0 TO SDFREQ;
  SIGNAL sd_tik : std_logic;
  
  SIGNAL sd_clk_is : std_logic;
  SIGNAL sd_cmd_is,sd_cmd_is2 : std_logic;
  SIGNAL sd_dat_is,sd_dat_is2 : uv4;

  SIGNAL rsd_datw : uv4;
  SIGNAL rsd_datr : uv4;
  SIGNAL rsd_cmdw : std_logic;
  SIGNAL rsd_cmdr : std_logic;
  SIGNAL rsd_daten,rsd_cmden : std_logic;
  SIGNAL rsd_cont ,rsd_cont_mem  : std_logic;
  SIGNAL rsd_pulse,rsd_pulse_mem,rsd_pulse_mem2 : std_logic;
  SIGNAL rsd_disk,rsd_reset,rsd_sd : std_logic;
  SIGNAL rsd_disks : uv2;
  SIGNAL rsd_busy : std_logic;
  SIGNAL rsd_freq,rsd_freq_pre : uv2;
  SIGNAL rsd_clk,rsd_clk_pst : std_logic;

  -- SD/MMC : Read/Write commands
  SIGNAL sd_clk : std_logic;
  SIGNAL dsd_req_wr  ,dsd_req_wr_mem   : std_logic;
  SIGNAL dsd_req_rd  ,dsd_req_rd_mem   : std_logic;
  SIGNAL dsd_req_stop,dsd_req_stop_mem : std_logic;
  
  SIGNAL dsd_fin  : std_logic;
  SIGNAL dsd_rw,dsd_stop : std_logic;   -- W=1 R=0
  SIGNAL dsd_adrs : uv32;
  SIGNAL dsd_hilo : std_logic;
  SIGNAL dsd_oct : uv8;
  SIGNAL dsd_dr,dsd_dw : uv8;
  SIGNAL dsd_push,dsd_pop : std_logic;
  SIGNAL dsd_data_rd,dsd_data_wr : std_logic;
  SIGNAL dsd_rad : unsigned(47 DOWNTO 0);
  SIGNAL dsd_crc7 : unsigned(6 DOWNTO 0);
  SIGNAL dsd_crc16_0,dsd_crc16_1,dsd_crc16_2,dsd_crc16_3 : uv16;
  SIGNAL dsd_cptc : natural RANGE 0 TO 48;
  SIGNAL dsd_cptd : natural RANGE 0 TO 512*2-1+16+20+2;
  
  TYPE type_cmd_etat IS (sOISIF,sCMD,sWAIT,sTURN,sRESP,sDATA);
  SIGNAL dsd_cmd_etat,dsd_cmd_etat_pre : type_cmd_etat;

  TYPE type_data_etat IS (sOISIF,sREAD1,sREAD2,sREAD3,sREAD4,
                          sWRITE1,sWRITE2,sWRITE3,sWRITE4,
                          sWRITE5,sWRITE6,sWRITE7,sWRITE8,sWRITE9);
  SIGNAL dsd_data_etat : type_data_etat;

  CONSTANT FIFOLEV : natural := 12;
  SIGNAL dsd_fifo : arr_uv8(0 TO FIFOLEV-1);
  SIGNAL dsd_fifo_lv : std_logic;
  SIGNAL dsd_fifo_lev : natural RANGE 0 TO FIFOLEV;
  SIGNAL dsd_fifo_dr,dsd_fifo_dw : uv8;
  SIGNAL dsd_fifo_empty,dsd_fifo_full : std_logic;
  
  CONSTANT SD_READ_BLOCK     : unsigned(5 DOWNTO 0):="010001";  -- 17
  CONSTANT SD_WRITE_BLOCK    : unsigned(5 DOWNTO 0):="011000";  -- 24
  CONSTANT SD_READ_MULTIPLE  : unsigned(5 DOWNTO 0):="010010";  -- 18 
  CONSTANT SD_WRITE_MULTIPLE : unsigned(5 DOWNTO 0):="011001";  -- 25
  CONSTANT SD_STOP_TRANS     : unsigned(5 DOWNTO 0):="001100";  -- 12
  
  -- SCSI
  SIGNAL capacity_m : uv32;
  SIGNAL acc,bcc: uv8;                    -- Registre Accumulateur
  SIGNAL cpt    : unsigned(11 DOWNTO 0);  -- Registre Comptage
  SIGNAL r_adrs : uv32;                   -- Adresse LBA
  SIGNAL r_len  : uv16;                   -- Nombre de secteurs
  SIGNAL r_message : uv8;
  SIGNAL r_lun : unsigned(2 DOWNTO 0);
  SIGNAL r_sense : uv8;
  SIGNAL r_lab : unsigned(9 DOWNTO 0);
  SIGNAL pc : natural RANGE 0 TO 1023;
  SIGNAL fifo : arr_uv8(0 TO 7);
  SIGNAL lev : natural RANGE 0 TO 7;
  SIGNAL hfull,empty : std_logic;
  SIGNAL push_sync,push_sync2 : std_logic;
  
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
        SD_CMDSTOP,
        TEST_EQH,
        FIXLEN,
        TEST_ADRS,
        SD_CMDRD,
        LDCPT,
        SD_RD,
        SCSI_WR,
        LOOP_CPT,
        LOOP_SECCNT,
        SD_CMDWR,
        SD_WR,
        SD_WR_LAST,
        LDA_I,
        SCSI_WR_A,
        SD_WR_B,
        TEST_LUN,
        TEST_EVPD,
        TEST_LEN,
        LDA_R);

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
        (LAB            ,to_unsigned(469,10)), 
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
        (SD_CMDSTOP     ,Z&x"01"        ), 
        (LAB            ,to_unsigned(65,10)), 
        (TEST_EQ        ,Z&OP_READ_6    ), 
        (LAB            ,to_unsigned(72,10)), 
        (TEST_EQ        ,Z&OP_READ_10   ), 
        (LAB            ,to_unsigned(159,10)), 
        (TEST_EQ        ,Z&OP_WRITE_6   ), 
        (LAB            ,to_unsigned(166,10)), 
        (TEST_EQ        ,Z&OP_WRITE_10  ), 
        (LAB            ,to_unsigned(270,10)), 
        (TEST_EQ        ,Z&OP_INQUIRY   ), 
        (LAB            ,to_unsigned(453,10)), 
        (TEST_EQ        ,Z&OP_TEST_UNIT_READY), 
        (TEST_EQ        ,Z&OP_START_STOP_UNIT), 
        (TEST_EQ        ,Z&OP_ALLOW_MEDIUM_REMOVAL), 
        (LAB            ,to_unsigned(355,10)), 
        (TEST_EQ        ,Z&OP_MODE_SENSE_6), 
        (LAB            ,to_unsigned(388,10)), 
        (TEST_EQ        ,Z&OP_READ_CAPACITY), 
        (LAB            ,to_unsigned(417,10)), 
        (TEST_EQ        ,Z&OP_REQUEST_SENSE), 
        (LAB            ,to_unsigned(459,10)), 
        (TEST_EQ        ,Z&OP_SYNCHRONIZE_CACHE), 
        (LAB            ,to_unsigned(486,10)), 
        (TEST_EQH       ,Z&x"00"        ), 
        (LAB            ,to_unsigned(482,10)), 
        (TEST_EQH       ,Z&x"20"        ), 
        (TEST_EQH       ,Z&x"40"        ), 
        (LAB            ,to_unsigned(480,10)), 
        (TEST_EQH       ,Z&x"A0"        ), 
        (LAB            ,to_unsigned(476,10)), 
        (TEST_EQH       ,Z&x"80"        ), 
        (LAB            ,to_unsigned(492,10)), 
        (GOTO           ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ADRS1    ), 
        (SCSI_RD        ,Z&REG_ADRS0    ), 
        (SCSI_RD        ,Z&REG_LEN0     ), 
        (SCSI_RD        ,Z&REG_CONTROL  ), 
        (FIXLEN         ,Z&x"00"        ), 
        (LAB            ,to_unsigned(80,10)), 
        (GOTO           ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ADRS3    ), 
        (SCSI_RD        ,Z&REG_ADRS2    ), 
        (SCSI_RD        ,Z&REG_ADRS1    ), 
        (SCSI_RD        ,Z&REG_ADRS0    ), 
        (SCSI_RD        ,Z&REG_LEN1     ), 
        (SCSI_RD        ,Z&REG_LEN1     ), 
        (SCSI_RD        ,Z&REG_LEN0     ), 
        (SCSI_RD        ,Z&REG_CONTROL  ), 
        (LAB            ,to_unsigned(492,10)), 
        (TEST_ADRS      ,Z&x"00"        ), 
        (NOP            ,Z&x"00"        ), 
        (SET_MODE       ,Z&"00000"&SCSI_DATA_IN), 
        (NOP            ,Z&x"00"        ), 
        (SD_CMDRD       ,Z&x"00"        ), 
        (LAB            ,to_unsigned(87,10)), 
        (LDCPT          ,Z&x"0F"        ), 
        (LAB            ,to_unsigned(89,10)), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (SD_RD          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LOOP_CPT       ,Z&x"00"        ), 
        (LAB            ,to_unsigned(87,10)), 
        (LOOP_SECCNT    ,Z&x"00"        ), 
        (SD_CMDSTOP     ,Z&x"00"        ), 
        (LAB            ,to_unsigned(469,10)), 
        (GOTO           ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ADRS1    ), 
        (SCSI_RD        ,Z&REG_ADRS0    ), 
        (SCSI_RD        ,Z&REG_LEN0     ), 
        (SCSI_RD        ,Z&REG_CONTROL  ), 
        (FIXLEN         ,Z&x"00"        ), 
        (LAB            ,to_unsigned(174,10)), 
        (GOTO           ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ADRS3    ), 
        (SCSI_RD        ,Z&REG_ADRS2    ), 
        (SCSI_RD        ,Z&REG_ADRS1    ), 
        (SCSI_RD        ,Z&REG_ADRS0    ), 
        (SCSI_RD        ,Z&REG_LEN1     ), 
        (SCSI_RD        ,Z&REG_LEN1     ), 
        (SCSI_RD        ,Z&REG_LEN0     ), 
        (SCSI_RD        ,Z&REG_CONTROL  ), 
        (LAB            ,to_unsigned(492,10)), 
        (TEST_ADRS      ,Z&x"00"        ), 
        (NOP            ,Z&x"00"        ), 
        (SET_MODE       ,Z&"00000"&SCSI_DATA_OUT), 
        (NOP            ,Z&x"00"        ), 
        (SD_CMDWR       ,Z&x"00"        ), 
        (LAB            ,to_unsigned(181,10)), 
        (LDCPT          ,Z&x"0F"        ), 
        (LAB            ,to_unsigned(183,10)), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR          ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SD_WR_LAST     ,Z&x"00"        ), 
        (LOOP_CPT       ,Z&x"00"        ), 
        (LAB            ,to_unsigned(181,10)), 
        (LOOP_SECCNT    ,Z&x"00"        ), 
        (NOP            ,Z&x"00"        ), 
        (NOP            ,Z&x"00"        ), 
        (SET_MODE       ,Z&"00000"&SCSI_STATUS), 
        (NOP            ,Z&x"00"        ), 
        (NOP            ,Z&x"00"        ), 
        (LDA_I          ,Z&STAT_GOOD    ), 
        (LAB            ,to_unsigned(6,10)), 
        (SCSI_WR_A      ,Z&REG_ACC      ), 
        (NOP            ,Z&x"00"        ), 
        (NOP            ,Z&x"00"        ), 
        (SET_MODE       ,Z&"00000"&SCSI_MSG_IN), 
        (NOP            ,Z&x"00"        ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR_A      ,Z&REG_ACC      ), 
        (SD_WR_B        ,Z&x"00"        ), 
        (NOP            ,Z&x"00"        ), 
        (SD_CMDSTOP     ,Z&x"00"        ), 
        (NOP            ,Z&x"00"        ), 
        (NOP            ,Z&x"00"        ), 
        (GOTO           ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ACC      ), 
        (SCSI_RD        ,Z&REG_ADRS0    ), 
        (SCSI_RD        ,Z&REG_LEN0     ), 
        (SCSI_RD        ,Z&REG_CONTROL  ), 
        (LAB            ,to_unsigned(493,10)), 
        (TEST_LUN       ,Z&x"00"        ), 
        (TEST_EVPD      ,Z&x"01"        ), 
        (TEST_LEN       ,Z&x"24"        ), 
        (NOP            ,Z&x"00"        ), 
        (SET_MODE       ,Z&"00000"&SCSI_DATA_IN), 
        (NOP            ,Z&x"00"        ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"02"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
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
        (LAB            ,to_unsigned(469,10)), 
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
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"08"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
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
        (LDA_I          ,Z&x"02"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LAB            ,to_unsigned(469,10)), 
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
        (LDA_I          ,Z&x"02"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LAB            ,to_unsigned(469,10)), 
        (GOTO           ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ADRS1    ), 
        (SCSI_RD        ,Z&REG_ADRS0    ), 
        (SCSI_RD        ,Z&REG_LEN0     ), 
        (SCSI_RD        ,Z&REG_CONTROL  ), 
        (NOP            ,Z&x"00"        ), 
        (SET_MODE       ,Z&"00000"&SCSI_DATA_IN), 
        (LAB            ,to_unsigned(493,10)), 
        (TEST_LEN       ,Z&x"07"        ), 
        (LAB            ,to_unsigned(434,10)), 
        (TEST_LUN       ,Z&x"00"        ), 
        (LDA_I          ,Z&x"F0"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR        ,Z&REG_ACC      ), 
        (LDA_R          ,z&REG_SENSE    ), 
        (LAB            ,to_unsigned(439,10)), 
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
        (LAB            ,to_unsigned(469,10)), 
        (GOTO           ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ADRS1    ), 
        (SCSI_RD        ,Z&REG_ADRS0    ), 
        (SCSI_RD        ,Z&REG_LEN0     ), 
        (SCSI_RD        ,Z&REG_CONTROL  ), 
        (LAB            ,to_unsigned(469,10)), 
        (GOTO           ,Z&x"00"        ), 
        (SCSI_RD        ,Z&REG_ADRS3    ), 
        (SCSI_RD        ,Z&REG_ADRS2    ), 
        (SCSI_RD        ,Z&REG_ADRS1    ), 
        (SCSI_RD        ,Z&REG_ADRS0    ), 
        (SCSI_RD        ,Z&REG_LEN1     ), 
        (SCSI_RD        ,Z&REG_LEN1     ), 
        (SCSI_RD        ,Z&REG_LEN0     ), 
        (SCSI_RD        ,Z&REG_CONTROL  ), 
        (LAB            ,to_unsigned(469,10)), 
        (GOTO           ,Z&x"00"        ), 
        (NOP            ,Z&x"00"        ), 
        (SET_MODE       ,Z&"00000"&SCSI_STATUS), 
        (LAB            ,to_unsigned(6,10)), 
        (LDA_I          ,Z&STAT_GOOD    ), 
        (SCSI_WR_A      ,Z&REG_ACC      ), 
        (LAB            ,to_unsigned(500,10)), 
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
        (LAB            ,to_unsigned(500,10)), 
        (GOTO           ,Z&x"00"        ), 
        (NOP            ,Z&x"00"        ), 
        (SET_MODE       ,Z&"00000"&SCSI_MSG_IN), 
        (LAB            ,to_unsigned(6,10)), 
        (LDA_I          ,Z&x"00"        ), 
        (SCSI_WR_A      ,Z&REG_ACC      ), 
        (NOP            ,Z&x"00"        ), 
        (NOP            ,Z&x"00"        ), 
        (GOTO           ,Z&x"00"        )); 

-- FIN Insertion Microcode

  SIGNAL code : type_microcode;
  
BEGIN

  --------------------------------------------------------
  

    
  
  
  


  
 
  


  
  

      
  
  
  



  
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
  Sequenceur: PROCESS (clk,reset_na)
    VARIABLE vcmd : uv8;
    VARIABLE op_v  : enum_code;
    VARIABLE val_v : unsigned(9 DOWNTO 0);
    VARIABLE val8_v : uv8;
    VARIABLE halt_v : boolean;
    VARIABLE saut_v : boolean;
    VARIABLE sel_v : std_logic;
    VARIABLE pc_v : natural RANGE 0 TO 1023;
  BEGIN
    IF reset_na='0' THEN
      scsi_r_i.req<='0';
      nov<='0';
      dsd_req_stop<='0';
      dsd_req_rd<='0';
      dsd_req_wr<='0';

    ELSIF rising_edge(clk) THEN
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
      
      dsd_pop<='0';
      dsd_push<='0';
      dsd_req_wr<='0';
      dsd_req_rd<='0';
      dsd_req_stop<='0';
      
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
        WHEN SD_CMDWR =>
          -- Envoi commande write
          dsd_req_wr<=nov;
          halt_v:=(dsd_fin='0' OR dsd_stop='1');
          
        WHEN SD_CMDRD =>
          -- Envoi commande read
          dsd_req_rd<=nov;
          halt_v:=(dsd_fin='0' OR dsd_stop='1');
          
        WHEN SD_CMDSTOP =>
          -- Envoi commande stop transmission
          IF val8_v(0)='0' THEN
            dsd_req_stop<=nov;
            halt_v:=false;
          ELSE
            halt_v:=(dsd_stop='1' OR dsd_req_stop_mem='1');
          END IF;
          
        WHEN SD_RD =>
          -- Lecture octet
          dsd_pop<=NOT dsd_fifo_empty;
          halt_v:=(dsd_fifo_empty='1');
          acc<=dsd_fifo_dr;
          
        WHEN SD_WR =>
          -- Ecriture octet
          dsd_push<=NOT dsd_fifo_full;
          -- Soit premier cycle, soit premier cycle où la FIFO n'est pas pleine
          halt_v:=(dsd_fifo_full='1');
          dsd_fifo_dw<=acc;

        WHEN SD_WR_LAST =>
          IF r_len/=x"0001" OR cpt/="000000000000" THEN
            dsd_push<=NOT dsd_fifo_full;
            -- Soit premier cycle, soit premier cycle où la FIFO n'est pas pleine
            halt_v:=(dsd_fifo_full='1');
            dsd_fifo_dw<=acc;
          END IF;

        WHEN SD_WR_B =>
          -- Ecriture octet
          dsd_push<=NOT dsd_fifo_full;
          -- Soit premier cycle, soit premier cycle où la FIFO n'est pas pleine
          halt_v:=(dsd_fifo_full='1');
          dsd_fifo_dw<=bcc;
          
        ----------------------------------
        WHEN SCSI_RD =>
          -- Copie données SCSI vers registre
          val8_v(7 DOWNTO 4):=x"0";
          bcc<=scsi_w.d;
          CASE val8_v IS
            WHEN REG_ACC       => acc<=scsi_w.d;
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
          r_adrs<=r_adrs+x"0000_0001";
          r_len<=r_len-x"0001";
          IF r_len/=x"0001" THEN
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
      IF scsi_w.rst='1' OR rsd_reset='1' THEN
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
      
    END IF;
  END PROCESS Sequenceur;

  scsi_r<=scsi_r_i;

  -----------------------------------------
  -- Resynchro
  sd_dat_is<=sd_dat_i WHEN rising_edge(sd_clk_i);
  sd_cmd_is<=sd_cmd_i WHEN rising_edge(sd_clk_i);
  
  ------------------------------------------------------------------------------
  -- Interface SD/MMC

  -- REG0
  -- -----------------------------------
  --       |     WR    |     RD
  -- -----------------------------------
  --   3:0 |  DATA_W   >  DATA_W
  --     4 |   CMD_W   >   CMD_W
  --     5
  --     6 |  DATA_EN  >  DATA_EN
  --     7 |   CMD_EN  >   CMD_EN
  -- -----------------------------------
  --  11:8 |           |  DATA_R sync
  --    12 |           |   CMD_R sync
  --    13 |     CONT  >  CONT    : Horloge continue 200kHz
  --    14 |   PULSE   |  0       : Impulsion horloge
  --    15 |           |  BUSY    : Impulsion en cours
  -- -----------------------------------
  --    16 |    DISK   >  DISK    : 0 = Regs, 1 = SCSI DISK
  --    17 |   RESET   > RESET    : RESET séquenceur SCSI
  --    18 |    SD     > SD       : 0 = SDHC  1 = SD
  -- 21:20 |    FREQ   >  FREQ    : Fréquence communications SD 0=lo 1=hi
  -- 22    | SYSACE_EN | SYSACE_EN : SysACE enable (DMAUX) DISKS(0)
  -- 23    | SD_EN     | SD_EN     : SD     enable (DMAUX) DISKS(1)
  -- -----------------------------------
  -- 27:24 |           |  DATA_R async
  --    28 |           |   CMD_R async
  -- 31:29 | DID       |           : SCSI select drive
  -- -----------------------------------

  -- REG1
  -- -----------------------------------
  -- SCSI : "READ CAPACITY" : N° last sector

  -----------------------------------------
  SDreg: PROCESS (clk,reset_na) IS
  BEGIN
    IF reset_na='0' THEN
      rsd_reset<='1';
      rsd_disk<='0';
      sdcpt<=0;
      rsd_pulse_mem<='0';
      rsd_pulse_mem2<='0';
      rsd_cont_mem<='0';
      rsd_clk<='0';
      sd_tik<='0';
      
    ELSIF rising_edge(clk) THEN
      -----------------------------------------
      -- Horloges
      IF rsd_freq(0)='1' THEN
        sdcpt<=0;
        sd_tik<='1';
      ELSIF sdcpt=SDFREQ OR rsd_freq_pre/=rsd_freq THEN
        sdcpt<=0;
        sd_tik<='1';
      ELSE
        sdcpt<=sdcpt+1;
        sd_tik<='0';
      END IF;

      IF sd_tik='1' AND rsd_cont='1' AND rsd_cont_mem='0' THEN
          rsd_cont_mem<='1';
      ELSIF sd_tik='1' AND rsd_cont='0' AND rsd_cont_mem='1' THEN
        IF rsd_clk='1' THEN
          rsd_cont_mem<='0';
        END IF;
      END IF;
      
      IF sd_tik='1' AND rsd_cont_mem='1' THEN
        rsd_clk<=NOT rsd_clk;
      ELSIF sd_tik='1' AND rsd_pulse_mem2='1' THEN
        rsd_pulse_mem<='0';
        rsd_pulse_mem2<='0';
        rsd_clk<='0';
      ELSIF sd_tik='1' AND rsd_pulse_mem='1' THEN
        rsd_pulse_mem2<='1';
        rsd_clk<='1';
        
      ELSIF rsd_pulse='1' THEN
        rsd_pulse_mem<='1';
      END IF;
      
      -----------------------------------------
      -- Resynchro
      sd_clk_is<=sd_clk;
      sd_dat_is2<=sd_dat_is;
      sd_cmd_is2<=sd_cmd_is;

      rsd_clk_pst<=rsd_clk;
      
      -----------------------------------------
      -- Echantillonnage sur front CLK
      IF rsd_clk_pst='0' AND rsd_clk='1' THEN
        -- Acquiert DATAR juste avant le front montant.
        rsd_cmdr<=sd_cmd_is;
        rsd_datr<=sd_dat_is;
      END IF;
      
      -----------------------------------------
      -- REG0
      rsd_pulse<='0';
      rsd_freq_pre<=rsd_freq;
      
      IF reg_w.wr0='1' THEN
        rsd_datw  <=reg_w.d(3 DOWNTO 0);
        rsd_cmdw  <=reg_w.d(4);
        rsd_daten <=reg_w.d(6);
        rsd_cmden <=reg_w.d(7);
        rsd_cont  <=reg_w.d(13);
        rsd_pulse <=reg_w.d(14);
        rsd_disk  <=reg_w.d(16);
        rsd_reset <=reg_w.d(17);
        rsd_sd    <=reg_w.d(18);
        rsd_freq  <=reg_w.d(21 DOWNTO 20);
        rsd_disks <=reg_w.d(23 DOWNTO 22);
      END IF;
      
      -----------------------------------------
      -- REG1
      IF reg_w.wr1='1' THEN
        capacity_m<=reg_w.d;
      END IF;
      
    END IF;
  END PROCESS SDreg;

  rsd_busy<=rsd_pulse_mem OR rsd_pulse_mem2;

  ------------------------------------------------------------------------------
  reg_r.d0<=
    "000" & sd_cmd_is2 & sd_dat_is2 &
    rsd_disks & rsd_freq & '0' & rsd_sd & rsd_reset & rsd_disk &
    rsd_busy & '0' & rsd_cont & rsd_cmdr & rsd_datr &
    rsd_cmden & rsd_daten & '0' & rsd_cmdw & rsd_datw;

  reg_r.d1<=capacity_m;
  
  ------------------------------------------------------------------------------
  dsd_adrs<=r_adrs;
  dsd_fifo_empty<=NOT dsd_fifo_lv;
  dsd_fifo_full <=to_std_logic(dsd_fifo_lev>FIFOLEV-4);
  dsd_fifo_dr<=dsd_fifo(dsd_fifo_lev);

  sd_clk_o<=sd_clk;
  
  -- Automate commandes lectures/ecritures SD/MMC
  SDcommand: PROCESS (clk,reset_na) IS
    VARIABLE d4_v : uv4;

    --------------------------------------------
    FUNCTION crc7 (
      CONSTANT d   : IN std_logic;
      CONSTANT crc : IN unsigned(6 DOWNTO 0)) RETURN unsigned IS
      VARIABLE c : unsigned(6 DOWNTO 0);
    BEGIN
      c(0):=crc(6) XOR d;
      c(1):=crc(0);
      c(2):=crc(1);
      c(3):=crc(2) XOR crc(6) XOR d;
      c(4):=crc(3);
      c(5):=crc(4);
      c(6):=crc(5);
      RETURN c;
    END;

    FUNCTION crc16 (
      CONSTANT d   : IN std_logic;
      CONSTANT crc : IN unsigned(15 DOWNTO 0)) RETURN unsigned IS
      VARIABLE c : unsigned(15 DOWNTO 0);
    BEGIN
      c(0) :=crc(15) XOR d;
      c(1) :=crc(0);
      c(2) :=crc(1);
      c(3) :=crc(2);
      c(4) :=crc(3);
      c(5) :=crc(4) XOR crc(15) XOR d;
      c(6) :=crc(5);
      c(7) :=crc(6);
      c(8) :=crc(7);
      c(9) :=crc(8);
      c(10):=crc(9);
      c(11):=crc(10);
      c(12):=crc(11) XOR crc(15) XOR d;
      c(13):=crc(12);
      c(14):=crc(13);
      c(15):=crc(14);
      RETURN c;
    END;
    --------------------------------------------
    VARIABLE c7_v : unsigned(6 DOWNTO 0);
    VARIABLE prim_v : boolean;
    VARIABLE push_v,pop_v,flush_v : std_logic;
    --------------------------------------------
  BEGIN
    IF reset_na='0' THEN
      dsd_fifo_lev<=0;
      dsd_fifo_lv<='0';
      dsd_req_stop_mem<='0';
      dsd_req_rd_mem<='0';
      dsd_req_wr_mem<='0';
    ELSIF rising_edge(clk) THEN
      prim_v:=(dsd_cmd_etat/=dsd_cmd_etat_pre);
      
      dsd_fin<='0';
      dsd_data_rd<='0';
      dsd_data_wr<='0';
      dsd_cmd_etat_pre<=dsd_cmd_etat;
      push_v:='0';
      pop_v:='0';
      flush_v:='0';
      
      dsd_req_wr_mem  <=dsd_req_wr_mem   OR dsd_req_wr;
      dsd_req_rd_mem  <=dsd_req_rd_mem   OR dsd_req_rd;
      dsd_req_stop_mem<=dsd_req_stop_mem OR dsd_req_stop;
      
      -------------------------------------------------------------------
      -- Machine à états commandes
      CASE dsd_cmd_etat IS
        WHEN sOISIF =>
          IF rsd_disk='0' THEN
            sd_clk   <=rsd_clk;
            sd_cmd_o <=rsd_cmdw;
            sd_cmd_en<=rsd_cmden;
          ELSE
            sd_clk   <='0';
            sd_cmd_en<='0';
            sd_cmd_o <='1';
          END IF;

          dsd_rad(47)<='0';                    -- Start bit
          dsd_rad(46)<='1';                    -- Trasmission bit
          -- ADRS : 0 = SDHC 1 = SD
          dsd_rad(39 DOWNTO 8)<=
            mux(rsd_sd,dsd_adrs(22 DOWNTO 0) & "000000000",dsd_adrs);
          dsd_cptc<=48;
          dsd_crc7<="0000000";
          dsd_stop<='0';
          
          IF dsd_req_stop='1' OR dsd_req_stop_mem='1' THEN
            dsd_stop<='1';
            dsd_rad(45 DOWNTO 40)<=SD_STOP_TRANS;
            dsd_cmd_etat<=sCMD;
            sd_cmd_en<='1';
            dsd_req_stop_mem<='0';
          ELSIF dsd_req_wr='1' OR dsd_req_wr_mem='1' THEN
            dsd_rw<='1';
            dsd_rad(45 DOWNTO 40)<=SD_WRITE_MULTIPLE;
            dsd_cmd_etat<=sCMD;
            sd_cmd_en<='1';
            dsd_req_wr_mem<='0';
          ELSIF dsd_req_rd='1' OR dsd_req_rd_mem='1' THEN
            dsd_rw<='0';
            dsd_rad(45 DOWNTO 40)<=SD_READ_MULTIPLE;
            dsd_cmd_etat<=sCMD;
            sd_cmd_en<='1';
            dsd_req_rd_mem<='0';
          END IF;
          flush_v:='1';
          
        WHEN sCMD =>
          IF sd_tik='1' THEN
            sd_clk<=NOT sd_clk;
            IF sd_clk='1' THEN
              -- Changement commandes sur front descendant.
              sd_cmd_o<=dsd_rad(47);
              dsd_rad<=dsd_rad(46 DOWNTO 0) & '1';
              c7_v:=crc7(dsd_rad(47),dsd_crc7);
              dsd_crc7<=c7_v;
              IF dsd_cptc=9 THEN
                dsd_rad(47 DOWNTO 40)<=c7_v & '1';
              END IF;
              IF dsd_cptc/=0 THEN
                dsd_cptc<=dsd_cptc-1;
              ELSE
                dsd_cmd_etat<=sWAIT;
              END IF;
            END IF;
          END IF;
          flush_v:='1';
          
        WHEN sWAIT =>
          -- Attente réponse
          sd_cmd_en<='0';
          dsd_cptc<=46;
          IF prim_v AND dsd_rw='0' AND dsd_stop='0' THEN
            dsd_data_rd<='1';
          END IF;
          IF sd_tik='1' THEN
            sd_clk<=NOT sd_clk;
            IF sd_clk_is='1' THEN
              dsd_cmd_etat<=sTURN;
            END IF;
          END IF;
          flush_v:='1';

        WHEN sTURN =>
          IF sd_tik='1' THEN
            sd_clk<=NOT sd_clk;
            IF sd_clk_is='1' THEN
              IF sd_cmd_is2='0' THEN
                -- Start bit réponse
                dsd_cmd_etat<=sRESP;
              END IF;
            END IF;
          END IF;
          flush_v:='1';
          
        WHEN sRESP =>
          -- Réception réponse commande read ou write
          IF sd_tik='1' THEN
            IF NOT ((dsd_rw='0' AND dsd_fifo_full='1'  AND sd_clk='0') OR
                    (dsd_rw='1' AND dsd_fifo_empty='1' AND sd_clk='0' AND
                     dsd_data_etat=sWRITE4)) OR dsd_stop='1'
            THEN
              sd_clk<=NOT sd_clk;
            END IF;
          END IF;
          IF sd_tik='1' AND sd_clk_is='1' THEN
            dsd_rad<=dsd_rad(46 DOWNTO 0) & sd_cmd_is2;
            IF dsd_cptc>0 THEN
              dsd_cptc<=dsd_cptc-1;
            ELSE
              IF dsd_stop='1' THEN
                IF sd_dat_is2(0)='1' THEN
                  dsd_cmd_etat<=sOISIF;
                  dsd_fin<='1';
                END IF;
              ELSE
                dsd_cmd_etat<=sDATA;
                dsd_fin<='1';
              END IF;
            END IF;
          END IF;
          flush_v:=dsd_stop;
          
        WHEN sDATA =>
          -- Attente fin réception datas
          IF sd_tik='1' THEN
            --  Si FIFO pleine, arrête horloge
            IF NOT ((dsd_rw='0' AND dsd_fifo_full='1'  AND sd_clk='0') OR
                    (dsd_rw='1' AND dsd_fifo_empty='1' AND sd_clk='0' AND
                     dsd_data_etat=sWRITE4)) OR dsd_req_stop_mem='1' THEN
              sd_clk<=NOT sd_clk;
            END IF;
          END IF;
          IF prim_v AND dsd_rw='1' AND dsd_stop='0' THEN
            dsd_data_wr<='1';
          END IF;
          
          IF dsd_req_stop_mem='1' AND
            dsd_data_etat/=sWRITE4 AND dsd_data_etat/=sWRITE5 AND
            dsd_data_etat/=sWRITE6 AND dsd_data_etat/=sWRITE7 AND
            dsd_data_etat/=sWRITE8 AND
            dsd_data_etat/=sREAD3  AND dsd_data_etat/=sREAD4  THEN
            dsd_cmd_etat<=sOISIF;
          END IF;
          
      END CASE;

      -------------------------------------------------------------------
      -- Machine à états données
      CASE dsd_data_etat IS
        WHEN sOISIF =>
          IF dsd_data_rd='1' THEN
            dsd_data_etat<=sREAD1;
          ELSIF dsd_data_wr='1' THEN
            dsd_data_etat<=sWRITE1;
          END IF;
          IF rsd_disk='0' THEN
            sd_dat_o <=rsd_datw;
            sd_dat_en<='0';
          END IF;
          
          -----------------------------------------------
        WHEN sREAD1 =>
          dsd_cptd<=0;
          dsd_hilo<='0';
          dsd_crc16_0<=x"0000";
          dsd_crc16_1<=x"0000";
          dsd_crc16_2<=x"0000";
          dsd_crc16_3<=x"0000";
          IF sd_tik='1' AND sd_clk_is='1' THEN         -- Montant
            IF sd_dat_is2(0)='0' THEN
              dsd_data_etat<=sREAD2;
            END IF;
          END IF;
          IF dsd_stop='1' THEN
            dsd_data_etat<=sOISIF;
          END IF;
          
        WHEN sREAD2 =>
          IF sd_tik='1' AND sd_clk_is='1' THEN
            dsd_oct<=dsd_oct(3 DOWNTO 0) & sd_dat_is2;
            push_v:=dsd_hilo;
            dsd_hilo<=NOT dsd_hilo;
            dsd_cptd<=dsd_cptd+1;
            IF dsd_cptd=512 * 2  THEN
              dsd_data_etat<=sREAD3;
            END IF;
          END IF;
          IF dsd_stop='1' THEN
            dsd_data_etat<=sOISIF;
          END IF;
          
        WHEN sREAD3 =>
          IF sd_tik='1' AND sd_clk_is='1' THEN
            dsd_oct<=dsd_oct(3 DOWNTO 0) & sd_dat_is2;
            dsd_cptd<=dsd_cptd+1;
            dsd_hilo<=NOT dsd_hilo;
            IF dsd_cptd=512 * 2 + 16 THEN
              dsd_data_etat<=sREAD4;
            END IF;
          END IF;
          IF dsd_stop='1' THEN
            dsd_data_etat<=sOISIF;
          END IF;
          
        WHEN sREAD4 =>
          IF sd_tik='1' AND sd_clk_is='1' THEN
            dsd_data_etat<=sREAD1;
          END IF;
          IF dsd_stop='1' THEN
            dsd_data_etat<=sOISIF;
          END IF;
          
          -----------------------------------------------
        WHEN sWRITE1 =>
          dsd_cptd<=0;
          dsd_hilo<='0';
          dsd_crc16_0<=x"0000";
          dsd_crc16_1<=x"0000";
          dsd_crc16_2<=x"0000";
          dsd_crc16_3<=x"0000";
          IF sd_tik='1' AND sd_clk='1' THEN
            dsd_data_etat<=sWRITE2;
          END IF;
          
        WHEN sWRITE2 =>
          IF sd_tik='1' AND sd_clk='1' THEN
            dsd_data_etat<=sWRITE3;
          END IF;
          
        WHEN sWRITE3 =>                 -- START bit
          IF sd_tik='1' AND sd_clk='1' THEN
            dsd_data_etat<=sWRITE4;
            sd_dat_en<='1';
            sd_dat_o<="0000";
          END IF;
          
        WHEN sWRITE4 =>                 -- DATA
          IF sd_tik='1' AND sd_clk='1' THEN
            d4_v:=mux(dsd_hilo,dsd_fifo_dr(3 DOWNTO 0),dsd_fifo_dr(7 DOWNTO 4));
            sd_dat_o<=d4_v;
            IF dsd_fifo_empty='0' THEN
              dsd_hilo<=NOT dsd_hilo;
              dsd_cptd<=dsd_cptd+1;
              dsd_crc16_0<=crc16(d4_v(0),dsd_crc16_0);
              dsd_crc16_1<=crc16(d4_v(1),dsd_crc16_1);
              dsd_crc16_2<=crc16(d4_v(2),dsd_crc16_2);
              dsd_crc16_3<=crc16(d4_v(3),dsd_crc16_3);
              pop_v:=dsd_hilo;
            END IF;
            IF dsd_cptd=512*2-1 THEN
              dsd_data_etat<=sWRITE5;
            END IF;
          END IF;

        WHEN sWRITE5 =>                 -- CRC & stop
          IF sd_tik='1' AND sd_clk='1' THEN
            sd_dat_o(0)<=dsd_crc16_0(15);
            sd_dat_o(1)<=dsd_crc16_1(15);
            sd_dat_o(2)<=dsd_crc16_2(15);
            sd_dat_o(3)<=dsd_crc16_3(15);
            dsd_crc16_0(15 DOWNTO 1)<=dsd_crc16_0(14 DOWNTO 0);
            dsd_crc16_1(15 DOWNTO 1)<=dsd_crc16_1(14 DOWNTO 0);
            dsd_crc16_2(15 DOWNTO 1)<=dsd_crc16_2(14 DOWNTO 0);
            dsd_crc16_3(15 DOWNTO 1)<=dsd_crc16_3(14 DOWNTO 0);
            dsd_cptd<=dsd_cptd+1;
            IF dsd_cptd=512*2-1 +16 THEN
              dsd_data_etat<=sWRITE6;
            END IF;
          END IF;

        WHEN sWRITE6 =>                 -- CRC & stop
          IF sd_tik='1' AND sd_clk='1' THEN
            sd_dat_o<="1111";
            dsd_data_etat<=sWRITE7;
          END IF;

        WHEN sWRITE7 =>                 -- Ignore réponse CRC check
          IF sd_tik='1' AND sd_clk_is='1' THEN
            sd_dat_en<='0';
            dsd_cptd<=dsd_cptd+1;
            IF dsd_cptd=512*2-1 +16 +20 THEN
              dsd_data_etat<=sWRITE8;
            END IF;
          END IF;

        WHEN sWRITE8 =>                 -- Attente fin busy
          IF sd_tik='1' AND sd_clk_is='1' THEN
            IF sd_dat_is2(0)='1' THEN
              dsd_data_etat<=sWRITE9;
            END IF;
          END IF;
          
        WHEN sWRITE9 =>
          IF sd_tik='1' AND sd_clk_is='1' THEN
            IF dsd_fifo_empty='0' THEN
              dsd_data_etat<=sWRITE1;
            END IF;
          END IF;
          IF dsd_stop='1' THEN
            dsd_data_etat<=sOISIF;
          END IF;
          
          -----------------------------------------------
      END CASE;
      
      IF rsd_reset='1' THEN
        dsd_cmd_etat<=sOISIF;
        dsd_data_etat<=sOISIF;
      END IF;
      
      -------------------------------------------------------------------
      -- FIFO
      IF dsd_push='1' THEN
        dsd_fifo<=dsd_fifo_dw & dsd_fifo(0 TO FIFOLEV-2);
      END IF;
      IF push_v='1' THEN
        dsd_fifo<=unsigned'(dsd_oct(3 DOWNTO 0) & sd_dat_is2) &
                   dsd_fifo(0 TO FIFOLEV-2);
      END IF;

      IF (dsd_push OR push_v)='1' AND (dsd_pop OR pop_v)='0' THEN
        dsd_fifo_lv<='1';
        IF dsd_fifo_lv='1' THEN
          dsd_fifo_lev<=dsd_fifo_lev+1;
        END IF;
      ELSIF (dsd_push OR push_v)='0' AND (dsd_pop OR pop_v)='1' THEN
        IF dsd_fifo_lev>0 THEN
          dsd_fifo_lev<=dsd_fifo_lev-1;
        ELSE
          dsd_fifo_lv<='0';
        END IF;
      END IF;
      
      IF flush_v='1' THEN
        dsd_fifo_lv<='0';
        dsd_fifo_lev<=0;
      END IF;
      
    END IF;
  END PROCESS SDcommand;

END ARCHITECTURE rtl;


