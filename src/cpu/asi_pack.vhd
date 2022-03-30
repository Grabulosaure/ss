--------------------------------------------------------------------------------
-- TEM : TACUS
-- Définitions
--------------------------------------------------------------------------------
-- DO 2/2018
--------------------------------------------------------------------------------
-- SPARC ASI codes
--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;

PACKAGE asi_pack IS
  --------------------------------------
  CONSTANT ASI_RESERVED                           : uv8 := x"00";
--  CONSTANT ASI_UNASSIGNED_01       : uv8 := x"01";
--  CONSTANT ASI_UNASSIGNED_02       : uv8 := x"02"; -- SS Control Space : MXCC
  CONSTANT ASI_MMU_FLUSH_PROBE                    : uv8 := x"03"; --MMU
  CONSTANT ASI_MMU_REGISTER                       : uv8 := x"04"; --MMU
  CONSTANT ASI_MMU_DIAGNOSTIC_FOR_INSTRUCTION_TLB : uv8 := x"05"; --MMU
  CONSTANT ASI_MMU_DIAGNOSTIC_FOR_DATA_TLB        : uv8 := x"06"; --MMU
  CONSTANT ASI_MMU_DIAGNOSTIC_IO_TLB              : uv8 := x"07"; --MMU
  CONSTANT ASI_USER_INSTRUCTION                   : uv8 := x"08"; --CPU
  CONSTANT ASI_SUPER_INSTRUCTION                  : uv8 := x"09"; --CPU
  CONSTANT ASI_USER_DATA                          : uv8 := x"0A"; --CPU
  CONSTANT ASI_SUPER_DATA                         : uv8 := x"0B"; --CPU
  CONSTANT ASI_CACHE_TAG_INSTRUCTION              : uv8 := x"0C"; --CACHE
  CONSTANT ASI_CACHE_DATA_INSTRUCTION             : uv8 := x"0D"; --CACHE
  CONSTANT ASI_CACHE_TAG_DATA                     : uv8 := x"0E"; --CACHE
  CONSTANT ASI_CACHE_DATA_DATA                    : uv8 := x"0F"; --CACHE
  CONSTANT ASI_CACHE_FLUSH_LINE_COMBINED_PAGE     : uv8 := x"10"; --CACHE
  CONSTANT ASI_CACHE_FLUSH_LINE_COMBINED_SEGMENT  : uv8 := x"11"; --CACHE
  CONSTANT ASI_CACHE_FLUSH_LINE_COMBINED_REGION   : uv8 := x"12"; --CACHE
  CONSTANT ASI_CACHE_FLUSH_LINE_COMBINED_CONTEXT  : uv8 := x"13"; --CACHE
  CONSTANT ASI_CACHE_FLUSH_LINE_COMBINED_USER     : uv8 := x"14"; --CACHE
  CONSTANT ASI_CACHE_FLUSH_LINE_COMBINED_ANY      : uv8 := x"15"; --#CACHE
--  CONSTANT ASI_RESERVED_15                        : uv8 := x"15";
--  CONSTANT ASI_RESERVED_16                        : uv8 := x"16";
  CONSTANT ASI_BLOCK_COPY                         : uv8 := x"17"; --CACHE
  CONSTANT ASI_CACHE_FLUSH_LINE_INSTRUCTION_PAGE  : uv8 := x"18"; --CACHE
  CONSTANT ASI_CACHE_FLUSH_LINE_INSTRUCTION_SEGMENT : uv8 := x"19"; --CACHE
  CONSTANT ASI_CACHE_FLUSH_LINE_INSTRUCTION_REGION  : uv8 := x"1A"; --CACHE
  CONSTANT ASI_CACHE_FLUSH_LINE_INSTRUCTION_CONTEXT : uv8 := x"1B"; --CACHE
  CONSTANT ASI_CACHE_FLUSH_LINE_INSTRUCTION_USER  : uv8 := x"1C"; --CACHE
  CONSTANT ASI_CACHE_FLUSH_LINE_INSTRUCTION_ANY   : uv8 := x"1D"; --#CACHE
--  CONSTANT ASI_RESERVED_1D                        : uv8 := x"1D";
--  CONSTANT ASI_RESERVED_1E                        : uv8 := x"1E";
  CONSTANT ASI_BLOCK_FILL                         : uv8 := x"1F"; --CACHE
  CONSTANT ASI_MMU_PHYSICAL_PASS_THROUGH_20       : uv8 := x"20"; --MMU 
  CONSTANT ASI_MMU_PHYSICAL_PASS_THROUGH_21       : uv8 := x"21"; --MMU 
  CONSTANT ASI_MMU_PHYSICAL_PASS_THROUGH_22       : uv8 := x"22"; --MMU 
  CONSTANT ASI_MMU_PHYSICAL_PASS_THROUGH_23       : uv8 := x"23"; --MMU 
  CONSTANT ASI_MMU_PHYSICAL_PASS_THROUGH_24       : uv8 := x"24"; --MMU 
  CONSTANT ASI_MMU_PHYSICAL_PASS_THROUGH_25       : uv8 := x"25"; --MMU 
  CONSTANT ASI_MMU_PHYSICAL_PASS_THROUGH_26       : uv8 := x"26"; --MMU 
  CONSTANT ASI_MMU_PHYSICAL_PASS_THROUGH_27       : uv8 := x"27"; --MMU 
  CONSTANT ASI_MMU_PHYSICAL_PASS_THROUGH_28       : uv8 := x"28"; --MMU 
  CONSTANT ASI_MMU_PHYSICAL_PASS_THROUGH_29       : uv8 := x"29"; --MMU 
  CONSTANT ASI_MMU_PHYSICAL_PASS_THROUGH_2A       : uv8 := x"2A"; --MMU 
  CONSTANT ASI_MMU_PHYSICAL_PASS_THROUGH_2B       : uv8 := x"2B"; --MMU 
  CONSTANT ASI_MMU_PHYSICAL_PASS_THROUGH_2C       : uv8 := x"2C"; --MMU 
  CONSTANT ASI_MMU_PHYSICAL_PASS_THROUGH_2D       : uv8 := x"2D"; --MMU 
  CONSTANT ASI_MMU_PHYSICAL_PASS_THROUGH_2E       : uv8 := x"2E"; --MMU 
  CONSTANT ASI_MMU_PHYSICAL_PASS_THROUGH_2F       : uv8 := x"2F"; --MMU

  CONSTANT ASI_USER_INSTRUCTION_NOSPEC            : uv8 := x"28"; --CPU Ibus
  CONSTANT ASI_SUPER_INSTRUCTION_NOSPEC           : uv8 := x"29"; --CPU Ibus
  
  CONSTANT ASI_USER_INSTRUCTION_TABLEWALK         : uv8 := x"38"; --#MMU EXT
  CONSTANT ASI_SUPER_INSTRUCTION_TABLEWALK        : uv8 := x"39"; --#MMU EXT
  CONSTANT ASI_USER_DATA_TABLEWALK                : uv8 := x"3A"; --#MMU EXT
  CONSTANT ASI_SUPER_DATA_TABLEWALK               : uv8 := x"3B"; --#MMU EXT
  
  -- MMU MULTI :
  --  ASI(6)  = 1 : RWITM
  --  ASI(5:4)=01 : FLUSH

  FUNCTION asi_txt(asi : uv8) RETURN string;

END PACKAGE asi_pack;

PACKAGE BODY asi_pack IS

  TYPE arr_string16 IS ARRAY(natural RANGE <>) OF string(1 TO 16);
    CONSTANT asi_text : arr_string16(0 TO 63) :=(
    "RESERVED_00     ",    "UNASSIGNED_01   ", -- 00
    "UNASSIGNED_02   ",    "MMU_FLUSH_PROBE ", -- 02
    "MMU_REGISTER    ",    "MMU_DIA_INST_TLB", -- 04 
    "MMU_DIA_DATA_TLB",    "MMU_DIA_IO_TLB  ", -- 06
    "USER_INST       ",    "SUPER_INST      ", -- 08
    "USER_DATA       ",    "SUPER_DATA      ", -- 0A
    "TAG_INSTRUCTION ",    "DATA_INSTRUCTION", -- 0C
    "TAG_DATA        ",    "DATA_DATA       ", -- 0E
    "LINE_COMB_PAGE  ",    "LINE_COMB_SEG   ", -- 10
    "LINE_COMB_REG   ",    "LINE_COMB_CTXT  ", -- 12
    "LINE_COMB_USER  ",    "LINE_COMB_ANY   ", -- 14
    "RESERVED_16     ",    "BLOCK_COPY      ", -- 16
    "LINE_INST_PAGE  ",    "LINE_INST_SEG   ", -- 18
    "LINE_INST_REG   ",    "LINE_INST_CTXT  ", -- 1A
    "LINE_INST_USER  ",    "LINE_INST_ANY   ", -- 1C
    "RESERVED_1E     ",    "BLOCK_FILL      ", -- 1E
    "MMU_PHYS_20     ",    "MMU_PHYS_21     ", -- 20
    "MMU_PHYS_22     ",    "MMU_PHYS_23     ", -- 22
    "MMU_PHYS_24     ",    "MMU_PHYS_25     ", -- 24
    "MMU_PHYS_26     ",    "MMU_PHYS_27     ", -- 26
    "MMU_PHYS_28     ",    "MMU_PHYS_29     ", -- 28
    "MMU_PHYS_2A     ",    "MMU_PHYS_2B     ", -- 2A
    "MMU_PHYS_2C     ",    "MMU_PHYS_2D     ", -- 2C
    "MMU_PHYS_2E     ",    "MMU_PHYS_2F     ", -- 2E
    "RESERVED_30     ",    "RESERVED_31     ", -- 30
    "RESERVED_32     ",    "RESERVED_33     ", -- 32
    "RESERVED_34     ",    "RESERVED_35     ", -- 34
    "RESERVED_36     ",    "RESERVED_37     ", -- 36
    "TW_USER_INST    ",    "TW_SUPER_INST   ", -- 38
    "TW_USER_DATA    ",    "TW_SUPER_DATA   ", -- 3A
    "RESERVED_3C     ",    "RESERVED_3D     ", -- 3C
    "RESERVED_3E     ",    "RESERVED_3F     ");-- 3E
    
  FUNCTION asi_txt(asi : uv8) RETURN string IS
  BEGIN
    IF asi(7 DOWNTO 6)="00" THEN
      RETURN asi_text(to_integer(asi(5 DOWNTO 0)));
    ELSE
      RETURN "                ";
    END IF;
  END FUNCTION asi_txt;
  

END PACKAGE BODY asi_pack;
