--------------------------------------------------------------------------------
-- TEM : TACUS
-- Configurations CPU
--------------------------------------------------------------------------------
-- DO 8/2011
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

USE work.base_pack.ALL;

PACKAGE cpu_conf_pack IS

  TYPE type_cpuconf IS RECORD
    -- CPU : IU
    NWINDOWS     : natural;               -- Register windows
    MULDIV       : boolean;               -- True = Integer MUL/DIV (SparcV8)
    IFLUSH       : boolean;               -- IFLUSH instruction
    CASA         : boolean;               -- CASA instruction
    IU_IMP_VER   : uv8;                   -- PSR.IMPL/VER

    -- CPU : FPU
    FPU_VER      : unsigned(2 DOWNTO 0);  -- Version

    -- CPU : MMU
    MMU_IMP_VER  : uv8;                   -- MSR.IMPL/VER
    NB_CONTEXT   : natural;              -- Nombre de bits de contexte
    
    -- CPU : Cache
    NB_ICACHE    : natural;       -- I-Cache size/way =2^N bytes
    WAY_ICACHE   : natural;       -- I-Cache ways 1,2,3,4
    BLEN_ICACHE  : natural;       -- I-Cache burst length, 32bits words
    IPTAG        : boolean;       -- false=VT, true=PT
    
    NB_DCACHE    : natural;       -- D-Cache size/way =2^N bytes
    WAY_DCACHE   : natural;       -- D-Cache ways 1,2,3,4
    BLEN_DCACHE  : natural;       -- D-Cache burst length, 32bits words
    DPTAG        : boolean;       -- false=VT, true=PT

    L2TLB        : boolean;       -- true=Enable Level 2 TLB cache
    NB_L2TLB     : natural;       -- Number of L2TLB entries 2**NB_L2TLB
    N_PTD_L2     : natural;       -- Number of cached Level 2 PTD entries I&D
    
    -- Sun4m : IOMMU
    IOMMU_VER    : uv8;           -- IOMMU IMPL/VER
  END RECORD;

  TYPE arr_cpuconf IS ARRAY (natural RANGE <>) OF type_cpuconf;

  -- On dit qu'un tag passe sur 32bits, il faut que NB_DCACHE >= NB_CONTEXT+3
  -- On dit qu'un tag passe sur 32bits, il faut que NB_ICACHE >= NB_CONTEXT+3

  --------------------------------------------------------------
  -- MicroSPARC-II = Fujitsu MB86904 = Sun STP1012 "Swift"
  -- 256 Contextes
  --  8k D-Cache, 16bytes/line. Direct map. VIVT.
  -- 16k I-Cache, 32bytes/line. Direct map. VIVT. Write Through with Allocate
  -- Pas de "flash clear" des caches.
  
  CONSTANT CONF_MicroSparcII_multi : type_cpuconf := (
    NWINDOWS    => 8,
    MULDIV      => true,
    IFLUSH      => true,
    CASA        => true,
    IU_IMP_VER  => x"04",
    
    FPU_VER     => "100",
    MMU_IMP_VER => x"04",
    NB_CONTEXT  => 8,
    
    NB_ICACHE   => 12,
    WAY_ICACHE  => 4,
    BLEN_ICACHE => 8,
    IPTAG       => false, --true,
    
    NB_DCACHE   => 12,
    WAY_DCACHE  => 4,
    BLEN_DCACHE => 8,
    DPTAG       => false, --true,
    
    L2TLB       => true,
    NB_L2TLB    => 7,
    N_PTD_L2    => 3,
    
    IOMMU_VER   => x"04"
    );
  
  CONSTANT CONF_MicroSparcII_direct : type_cpuconf := (
    NWINDOWS    => 8,
    MULDIV      => true,
    IFLUSH      => true,
    CASA        => true,
    IU_IMP_VER  => x"04",
    
    FPU_VER     => "100",
    MMU_IMP_VER => x"04",
    NB_CONTEXT  => 8,
    
    NB_ICACHE   => 12,                  -- Direct map, 8K I
    WAY_ICACHE  => 1,
    BLEN_ICACHE => 8,
    IPTAG       => true,
    
    NB_DCACHE   => 12,                  -- Direct map, 8K D
    WAY_DCACHE  => 1,
    BLEN_DCACHE => 8,
    DPTAG       => true,
    
    L2TLB       => true,
    NB_L2TLB    => 7,
    N_PTD_L2    => 3,
    
    IOMMU_VER   => x"04"
    );
  
  CONSTANT CONF_SuperSparc : type_cpuconf := (
    NWINDOWS    => 8,
    MULDIV      => true,
    IFLUSH      => true,
    CASA        => true,
    IU_IMP_VER  => x"40",
    
    FPU_VER     => "000",
    MMU_IMP_VER => x"01",
    NB_CONTEXT  => 8,
    
    NB_ICACHE   => 12,
    WAY_ICACHE  => 4,
    BLEN_ICACHE => 8,
    IPTAG       => true,
    
    NB_DCACHE   => 12,
    WAY_DCACHE  => 4,
    BLEN_DCACHE => 8,
    DPTAG       => true,
    
    L2TLB       => true,
    NB_L2TLB    => 7,
    N_PTD_L2    => 2,
    
    IOMMU_VER   => x"04"
    );
  
  CONSTANT CPUCONF : arr_cpuconf (0 TO 1) := (
    CONF_MicroSparcII_multi,
    CONF_SuperSparc);

  CONSTANT CPUTYPE_MS2 : natural :=0;
  CONSTANT CPUTYPE_SS  : natural :=1;
  
  -- Cy7C601 : IU_IMP_VER =>x"11"
  -- Cy7C604 : MMU_IMP_VER =>x"10"
  -- Cy7C605 : MMU_IMP_VER =>x"1F"
  
  -- Nombre de contextes de la MMU
  -- Cy7C604      = 12 bits
  -- MicroSparc   = 6 bits
  -- MicroSparcII = 8 bits
  -- UltraSparc   = 13 bits
  
  -- MicroSparcII : IOMMU_VER = x"04", MASK_REV=x"26/22/11..."
  
  -- SuperSparc   : IU_IMP_VER  x"40", FPU_VER="000" MMU_VER = x"01"
  
  CONSTANT FPU_LDASTA : boolean := true;
  
  CONSTANT IOMMU_MASK_REV : uv8 := x"26";  -- 26
--  CONSTANT IOMMU_MASK_REV : uv8 := x"23";  -- 26
  
  --------------------------------------------------------------
  -- BSD Compatibility flag
  --   MUST   be enabled  for NetBSD/OpenBSD compatibility
  --   SHOULD be disabled for Linux
  CONSTANT BSD_MODE : boolean := true;
  
  --############################################################################
  TYPE type_tech IS RECORD
    mul  : natural;
    div  : natural;
    fmul : natural;
    fdiv : natural;
  END RECORD type_tech;
  
  TYPE arr_tech IS ARRAY (natural RANGE <>) OF type_tech;

  CONSTANT ITECH_SPARTAN6 : type_tech:=(
    2,0,0,0);

  CONSTANT ITECH_CYCLONE5 : type_tech:=(
    2,0,1,0);
  
  CONSTANT TECHS : arr_tech (0 TO 1) := (
    ITECH_SPARTAN6,
    ITECH_CYCLONE5);

  CONSTANT TECH_SPARTAN6 : natural := 0;
  CONSTANT TECH_CYCLONE5 : natural := 1;

  CONSTANT TECH_SIM      : natural := 0;
  
  
  --------------------------------------------------------------
  -- IU : MULDIV
  
  -- MUL : Instructions SMUL, UMUL, SMULcc, UMULcc. Sparc V8
  --   0 : Série, 1 bit par cycle,
  --   2 : Multiplieur 17x17, calcul en 4 cycles
  --   7 : Simulation.

  -- DIV : Instructions SDIV, UDIV, SDIVcc, UDIVcc. Sparc V8
  --   0 : Série sans récupération. 1 bit par cycle
  --   7 : Simulation.
  
  --FPU : MULDIV
  --                                     SIMPLE        DOUBLE

  -- FMUL_MODE :
  --  0 : 17x17 multipliers. for Spartan6    1             2
  --  1 : Direct multiplication. CycloneV    1             1
  
  -- FDIV_MODE :
  --  0 : Non Restoring      DIV/SQRT       25            54
  --  1 : SRT Radix 2        DIV/SQRT       27            56
  --  2 : SRT Radix 4        DIV/SQRT       14            29
  
  --############################################################################

END PACKAGE cpu_conf_pack;
