--------------------------------------------------------------------------------
-- TEM : TACUS
-- Unité flottante
--------------------------------------------------------------------------------
-- DO 11/2009
--------------------------------------------------------------------------------
-- Entité
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

-- DECODAGE
-- La FPU fait le décodage en parallèle avec IU
-- Elle indique <RDY> si elle est prête pour l'instruction décodée.
-- Pour gérer l'annulation des instructions en cas de trap IU, un signal <VAL>
-- signale quand l'instruction flottante est sure d'être exécutée.
--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

USE std.textio.ALL;

USE work.base_pack.ALL;
USE work.iu_pack.ALL;

ENTITY  fpu IS
  GENERIC (
    TECH     : natural);
  PORT (
    i        : IN  type_fpu_i;
    o        : OUT type_fpu_o;
    
    -- Général
    reset    : IN std_logic;             -- Reset synchrone   
    reset_n  : IN std_logic;             -- Reset
    clk      : IN std_logic              -- Horloge
    
    ---- Exéxution instructions FPU OP
    --cat      : IN  type_cat;
    --a        : IN  uv32;                -- Adresse instruction (pour DFQ)
    
    --req      : IN  std_logic;           -- Début nouvelle instruction FPOP
    --rdy      : OUT std_logic;           -- Prêt pour une nouvelle instruction
    --val      : IN  std_logic;           -- Autorise les instructions en cours
    --tstop    : IN  std_logic;           -- TrapStop
    --fexc     : OUT std_logic;           -- Requète TRAP FPU
    --fxack    : IN  std_logic;           -- Acquittement TRAP FPU
    
    --present  : OUT std_logic;           -- FPU Présente
    ---- Load
    --do       : OUT uv32;                -- Bus données sorties
    --do_ack   : IN  std_logic;           -- Second accès instruction double
    ---- Store
    --di       : IN  uv32;                -- Bus données entrées
    --di_maj   : IN  std_logic;           -- Ecriture registre
    
    ---- Drapeaux de comparaison pour FBcc
    --fcc      : OUT unsigned(1 DOWNTO 0); -- Codes conditions
    --fccv     : OUT std_logic;            -- Validité codes condition

    ---- Debug
    --dstop    : IN  std_logic;
    --fpu_debug_s : OUT type_fpu_debug_s;
    
    );
END ENTITY fpu;
