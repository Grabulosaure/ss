--------------------------------------------------------------------------------
-- TEM : TS
-- Interface PS2 + FIFO réception + Contrôle GPIO
--------------------------------------------------------------------------------
-- DO 10/2012
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
USE work.plomb_pack.ALL;
USE work.ts_pack.ALL;

ENTITY ts_ps2 IS
  GENERIC (
    SYSFREQ  : natural :=50_000_000;
    PROF     : natural :=15);
  PORT (
    gpio_i      : IN  unsigned(3 DOWNTO 0);
    gpio_o      : OUT unsigned(3 DOWNTO 0);
    gpio_en     : OUT unsigned(3 DOWNTO 0);
    
    di          : OUT uv8;
    dierr       : OUT std_logic;
    di_r        : IN  std_logic;
    do          : IN  uv8;
    do_w        : IN  std_logic;
    drdy        : OUT std_logic;
    dwdy        : OUT std_logic;
    
    clk         : IN  std_logic;
    reset_n     : IN  std_logic
    );
END ENTITY ts_ps2;

--##############################################################################

ARCHITECTURE rtl OF ts_ps2 IS

  SIGNAL ps2_di,ps2_do,ps2_cki,ps2_cko : std_logic;

  SIGNAL tx_data,rx_data : uv8;
  SIGNAL tx_req,tx_ack,rx_err,rx_val : std_logic;

  SIGNAL fifo_d : arr_uv8(0 TO PROF-1);
  SIGNAL fifo_e : unsigned(0 TO PROF-1);
  SIGNAL lev : natural RANGE 0 TO PROF;
  SIGNAL vv : std_logic;

  --SIGNAL cptdiv : unsigned(4 DOWNTO 0) :="00000";
  --  0 : 25
  --  1 : 12.5
  --  2 :  6.25
  --  3 :  3.125
BEGIN

  i_ps2: ENTITY work.ps2
    GENERIC MAP (
      SYSFREQ => SYSFREQ)
    PORT MAP (
      di       => ps2_di,
      do       => ps2_do,
      cki      => ps2_cki,
      cko      => ps2_cko,
      tx_data  => tx_data,
      tx_req   => tx_req,
      tx_ack   => tx_ack,
      rx_data  => rx_data,
      rx_err   => rx_err,
      rx_val   => rx_val,
      clk      => clk,
      reset_n  => reset_n);
  
  -----------------------------------------------
  -- GPIO(0) : DATA
  gpio_en(0)<='0';
  ps2_di<=gpio_i(0);
  
  -- GPIO(1) : CLOCK
  gpio_en(1)<='0';
  ps2_cki<=gpio_i(1);

  gpio_en(2)<='1';
  gpio_o(2)<=NOT ps2_do;
  
  gpio_en(3)<='1';
  gpio_o(3)<=NOT ps2_cko;
  
  -----------------------------------------------
  Truc: PROCESS (clk)
  BEGIN
    IF rising_edge(clk) THEN
      ------------------------------------------
      -- Réception
      IF rx_val='1' THEN
        -- Empile
        fifo_d<=rx_data & fifo_d(0 TO PROF-2);
        fifo_e<=rx_err  & fifo_e(0 TO PROF-2);
        IF vv='1' AND lev<PROF-1 THEN
          lev<=lev+1;
        END IF;
        vv<='1';
      ELSIF di_r='1' THEN
        -- Dépile
        IF lev>0 THEN
          lev<=lev-1;
        ELSE
          vv<='0';
        END IF;
      END IF;

      ------------------------------------------
      -- Emission
      IF do_w='1' THEN
        tx_data<=do(7 DOWNTO 0);
        tx_req<='1';
      END IF;
      IF tx_ack='1' THEN
        tx_req<='0';
      END IF;
      
      ------------------------------------------
      IF reset_n='0' THEN
        vv<='0';
        lev<=0;
      END IF;

    END IF;
  END PROCESS Truc;

  di   <=fifo_d(lev);
  dierr<=fifo_e(lev);
  drdy <=vv;
  dwdy <=NOT tx_req;
  
END ARCHITECTURE rtl;
