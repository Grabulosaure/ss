-------------------------------------------------------------------------------
-- TEM
-------------------------------------------------------------------------------
-- DO 1/2014
-------------------------------------------------------------------------------
-- Synth
-------------------------------------------------------------------------------

-- Fbit = Fclk / 16 * MUL / DIV

--      25MHz *  192 / 15625 = 19200b/s * 16
--      25MHz * 1152 / 15625 = 115200b/s * 16

-------------------------------------------------------------------------------
LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;

ENTITY synth IS
  GENERIC (
    FREQ  : natural; -- :=25000000;
    RATE  : natural -- :=115200
    );
  PORT (
    sync     : OUT std_logic;
    
    clk      : IN std_logic;
    reset_na : IN std_logic);
END ENTITY synth;

-------------------------------------------------------------------------------
ARCHITECTURE rtl OF synth IS

  -- Euclide !
  FUNCTION gcd (
    CONSTANT a  : natural;
    CONSTANT b  : natural) RETURN natural IS
  BEGIN
    IF b/=0 THEN
      RETURN gcd(b,a MOD b);
    ELSE
      RETURN a;
    END IF;
  END FUNCTION gcd;

  CONSTANT MUL : natural := RATE*16/gcd(FREQ,RATE*16);
  CONSTANT DIV : natural :=    FREQ/gcd(FREQ,RATE*16);
  SIGNAL acc   : integer RANGE -MUL TO DIV-MUL :=0;
BEGIN

  -------------------------------------------------
  ClockGen:PROCESS (clk, reset_na)
  BEGIN
    IF reset_na = '0' THEN
      sync<='0';
    ELSIF rising_edge(clk) THEN
      IF acc>0 THEN
        acc<=acc-MUL;
        sync<='0';
      ELSE
        acc<=acc+DIV-MUL;
        sync<='1';
      END IF;
    END IF;
  END PROCESS ClockGen;
  
END ARCHITECTURE rtl;
