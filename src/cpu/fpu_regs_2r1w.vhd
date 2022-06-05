--------------------------------------------------------------------------------
-- TEM : TACUS
-- FPU : Banque de registres 2R1W, 16 * 64bits. Ecriture par mots de 32bits
--------------------------------------------------------------------------------
-- DO 11/2009
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
USE work.iu_pack.ALL;

ENTITY fpu_regs_2r1w IS
  GENERIC (
    THRU     : boolean :=true;
    N        : natural);
  PORT (
    n_fs1    : IN  unsigned(N-1 DOWNTO 0);
    fs1      : OUT uv64;
    n_fs2    : IN  unsigned(N-1 DOWNTO 0);
    fs2      : OUT uv64;
    n_fd     : IN  unsigned(N-1 DOWNTO 0);
    fd       : IN  uv64;
    fd_maj   : IN  unsigned(0 TO 1);
    
    clk      : IN  std_logic
    );
END ENTITY fpu_regs_2r1w;

ARCHITECTURE rtl OF fpu_regs_2r1w IS
  ATTRIBUTE ramstyle : string;

--------------------------------------------------------------------------------
  SHARED VARIABLE mem1h,mem1l : arr_uv32(0 TO 2**N - 1) :=(OTHERS => x"00000000");
  SHARED VARIABLE mem2h,mem2l : arr_uv32(0 TO 2**N - 1) :=(OTHERS => x"00000000");
  
  ATTRIBUTE ramstyle OF mem1h : VARIABLE IS "M9K, no_rw_check";
  ATTRIBUTE ramstyle OF mem1l : VARIABLE IS "M9K, no_rw_check";
  ATTRIBUTE ramstyle OF mem2h : VARIABLE IS "M9K, no_rw_check";
  ATTRIBUTE ramstyle OF mem2l : VARIABLE IS "M9K, no_rw_check";
  
  SIGNAL fs1_i,fs2_i : uv64;
  SIGNAL fs1h_i,fs1l_i,fs2h_i,fs2l_i : uv32;
  SIGNAL fdh,fdl : uv32;
  
  SIGNAL fs10_direct,fs11_direct,fs20_direct,fs21_direct : std_logic;
  SIGNAL fd_mem : uv64;
    
BEGIN

  fdh<=fd(63 DOWNTO 32);
  fdl<=fd(31 DOWNTO 0);
  
  regfile1h: PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      IF fd_maj(0)='1' THEN
        mem1h(to_integer(n_fd)):=fdh;
      END IF;
      fs1h_i<=mem1h(to_integer(n_fs1));
    END IF;
  END PROCESS regfile1h;

  regfile1l: PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      IF fd_maj(1)='1' THEN
        mem1l(to_integer(n_fd)):=fdl;
      END IF;
      fs1l_i<=mem1l(to_integer(n_fs1));
    END IF;
  END PROCESS regfile1l;

  regfile2h: PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      IF fd_maj(0)='1' THEN
        mem2h(to_integer(n_fd)):=fdh;
      END IF;
      fs2h_i<=mem2h(to_integer(n_fs2));
    END IF;
  END PROCESS regfile2h;

  
  regfile2l: PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      IF fd_maj(1)='1' THEN
        mem2l(to_integer(n_fd)):=fdl;
      END IF;
      fs2l_i<=mem2l(to_integer(n_fs2));
    END IF;
  END PROCESS regfile2l;

  fs1_i<=fs1h_i & fs1l_i;
  fs2_i<=fs2h_i & fs2l_i;

  Direct: PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      fd_mem<=fd;

      IF fd_maj(0)='1' AND n_fd=n_fs1 THEN
        fs10_direct<='1';
      ELSE
        fs10_direct<='0';
      END IF;
      IF fd_maj(1)='1' AND n_fd=n_fs1 THEN
        fs11_direct<='1';
      ELSE
        fs11_direct<='0';
      END IF;
        
      IF fd_maj(0)='1' AND n_fd=n_fs2 THEN
        fs20_direct<='1';
      ELSE
        fs20_direct<='0';
      END IF;
      IF fd_maj(1)='1' AND n_fd=n_fs2 THEN
        fs21_direct<='1';
      ELSE
        fs21_direct<='0';
      END IF;
      
    END IF;
  END PROCESS Direct;
  
  fs1(63 DOWNTO 32)<=fd_mem(63 DOWNTO 32) WHEN fs10_direct='1' AND THRU
                     ELSE fs1_i(63 DOWNTO 32);
  fs1(31 DOWNTO 0) <=fd_mem(31 DOWNTO 0)  WHEN fs11_direct='1' AND THRU
                     ELSE fs1_i(31 DOWNTO 0);
  
  fs2(63 DOWNTO 32)<=fd_mem(63 DOWNTO 32) WHEN fs20_direct='1' AND THRU
                     ELSE fs2_i(63 DOWNTO 32);
  fs2(31 DOWNTO 0) <=fd_mem(31 DOWNTO 0)  WHEN fs21_direct='1' AND THRU
                     ELSE fs2_i(31 DOWNTO 0);
  
END ARCHITECTURE rtl;
