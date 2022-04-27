--------------------------------------------------------------------------------
-- TEM : PLOMB
-- Trace SCSI
--------------------------------------------------------------------------------
-- DO 3/2018
--------------------------------------------------------------------------------
-- CONF :
--  0   : CLRIN
--  1   : CLROUT
--  3:2 : ACKREQ : 00 = Direct 01 = AcqReq 10 = Compress DIN/DOUT 11= Compress more
--  4   : ENA
--  6:5 : time div 0 / 4 / 16 / 256
--  7   : dump state

--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY std;
USE std.textio.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.plomb_pack.ALL;
USE work.ts_pack.ALL;

ENTITY dl_scsi IS
  GENERIC (
    ADRS : uv4;
    N    : natural :=9);
  PORT (
    -- Debug Link
    dl_w     : IN  type_dl_w;
    dl_r     : OUT type_dl_r;

    -- SCSI
    scsi_w   : IN  type_scsi_w;
    scsi_r   : IN  type_scsi_r;
    aux      : IN  uv10;
    timecode : IN  uv32;
    
    -- Global
    clk      : IN  std_logic;
    reset_na : IN  std_logic
    );
END ENTITY dl_scsi;

--##############################################################################

ARCHITECTURE rtl OF dl_scsi IS
  
  -- Writes
  CONSTANT WR_CONF  : uv4 :=x"8";
  
  -- Reads
  CONSTANT RD_CONF  : uv4 :=x"0";
  CONSTANT RD_PTR   : uv4 :=x"1";
  CONSTANT RD_DATA0 : uv4 :=x"2";
  CONSTANT RD_DATA1 : uv4 :=x"3";
  
  COMPONENT iram_dp IS
    GENERIC (
      N   : uint8;
      OCT : boolean);
    PORT (
      mem1_w    : IN  type_pvc_w;
      mem1_r    : OUT type_pvc_r;
      clk1      : IN  std_logic;
      reset1_na : IN  std_logic;
      mem2_w    : IN  type_pvc_w;
      mem2_r    : OUT type_pvc_r;
      clk2      : IN  std_logic;
      reset2_na : IN  std_logic);
  END COMPONENT iram_dp;
  
  SIGNAL a0_w,a1_w,b0_w,b1_w   : type_pvc_w;
  SIGNAL a0_r,a1_r,b0_r,b1_r   : type_pvc_r;
  SIGNAL sig,sig_d,sig_d2,sigr : uv64;
  SIGNAL diff : std_logic;
  
  SIGNAL cptin,cptout : unsigned(N-1 DOWNTO 0);
  SIGNAL clr_cptin : std_logic;
  SIGNAL conf_ena,conf_state : std_logic;
  SIGNAL conf_ackreq,conf_div : uv2;
  SIGNAL timediv : uv16;
  SIGNAL ackreq : std_logic;
  
--------------------------------------------------------------------------------
BEGIN

  -- Bloc
  i_iram_b0: iram_dp
    GENERIC MAP (N => N+2,OCT => false)
    PORT MAP (
      mem1_w   => a0_w,     mem1_r    => a0_r,
      clk1     => clk,      reset1_na => reset_na,
      mem2_w   => b0_w,     mem2_r    => b0_r,
      clk2     => clk,      reset2_na => reset_na);

  i_iram_b1: iram_dp
    GENERIC MAP (N => N+2,OCT => false)
    PORT MAP (
      mem1_w   => a1_w,     mem1_r    => a1_r,
      clk1     => clk,      reset1_na => reset_na,
      mem2_w   => b1_w,     mem2_r    => b1_r,
      clk2     => clk,      reset2_na => reset_na);
  
  --------------------------------------
  Reg:PROCESS(clk,reset_na)
    VARIABLE ack_v,req_v : std_logic;
  BEGIN
    IF reset_na='0' THEN
      
    ELSIF rising_edge(clk) THEN
      
      --------------------------------------------------------------------
      IF conf_ackreq="00" THEN
        ack_v:=scsi_w.ack AND scsi_r.req;
        req_v:=scsi_w.ack AND scsi_r.req;
      ELSE
        ack_v:=scsi_w.ack;
        req_v:=scsi_r.req;
      END IF;
      sig( 7 DOWNTO  0)<=scsi_w.d;
      sig(15 DOWNTO  8)<=ack_v & req_v & scsi_w.rst & scsi_w.did & scsi_w.atn & scsi_w.bsy;
      sig(23 DOWNTO 16)<=scsi_r.d;
      sig(31 DOWNTO 24)<=aux(3 DOWNTO 0) & scsi_r.sel & scsi_r.phase;
      
      sig(47 DOWNTO 32)<=scsi_r.d_pc(9 DOWNTO 0) & aux(9 DOWNTO 4);
      sig(63 DOWNTO 48)<=timediv;

      sig_d <=sig;
      sig_d2<=sig_d;
      diff<=to_std_logic(sig_d(47 DOWNTO 0)/=sig(47 DOWNTO 0));
      ackreq<=sig(15) AND sig(14);
      
      --------------------------------------------------------------------
      a0_w.be<="1111";
      a0_w.a<=x"0000_0000";
      a0_w.a(N+1 DOWNTO 2)<=cptin;
      a0_w.ah<=x"0";
      a0_w.wr<=diff;
      a0_w.dw<=sig_d(31 DOWNTO 0);
      a1_w.be<="1111";
      a1_w.a<=x"0000_0000";
      a1_w.a(N+1 DOWNTO 2)<=cptin;
      a1_w.ah<=x"0";
      a1_w.wr<=diff;
      a1_w.dw<=sig_d(63 DOWNTO 32);

      a0_w.req<=diff;
      a1_w.req<=diff;
      IF conf_ena='1' THEN
        IF (conf_ackreq(1)='0' AND diff='1') OR
          
          (conf_ackreq="10" AND ackreq='1' AND
           (sig_d(26 DOWNTO 24)=SCSI_DATA_IN OR
            sig_d(26 DOWNTO 24)=SCSI_DATA_OUT)) OR

          (conf_ackreq="11" AND
           (sig_d2(31 DOWNTO 24)/=sig_d(31 DOWNTO 24) OR  -- state / sel / phase
            sig_d2(13 DOWNTO  8)/=sig_d(13 DOWNTO  8))) OR  -- rst / did / atn / bsy
            
          (conf_ackreq(1)='1' AND diff='1' AND
           sig_d(26 DOWNTO 24)/=SCSI_DATA_IN AND
           sig_d(26 DOWNTO 24)/=SCSI_DATA_OUT)

        THEN
          cptin<=cptin+1;
        END IF;
      END IF;
      IF clr_cptin='1' THEN
        cptin<=(OTHERS =>'0');
      END IF;
      
      --------------------------------------------------------------------
      b0_w.be<="1111";
      b0_w.a<=x"0000_0000";
      b0_w.a(N+1 DOWNTO 2)<=cptout;
      b0_w.ah<=x"0";
      b0_w.wr<='0';
      b0_w.dw<=x"0000_0000";
      b1_w.be<="1111";
      b1_w.a<=x"0000_0000";
      b1_w.a(N+1 DOWNTO 2)<=cptout;
      b1_w.ah<=x"0";
      b1_w.wr<='0';
      b1_w.dw<=x"0000_0000";
      b0_w.req<='1';
      b1_w.req<='1';
      sigr<=b1_r.dr & b0_r.dr;
    END IF;
  END PROCESS Reg;
  
  --------------------------------------
  Glo:PROCESS(clk,reset_na) IS
    VARIABLE wrmem_v : std_logic;
  BEGIN
    IF reset_na='0' THEN
      
    ELSIF rising_edge(clk) THEN
      clr_cptin<='0';
      dl_r.rd<='0';
      dl_r.d <=x"0000_0000";
      
      --------------------------------------------
      IF dl_w.wr='1' AND dl_w.a=ADRS THEN
        CASE dl_w.op IS
          ------------------------
          WHEN WR_CONF =>
            clr_cptin<=dl_w.d(0);
            IF dl_w.d(1)='1' THEN
              cptout<=(OTHERS =>'0');
            END IF;
            conf_ackreq<=dl_w.d(3 DOWNTO 2);
            conf_ena   <=dl_w.d(4);
            conf_div   <=dl_w.d(6 DOWNTO 5);
            conf_state <=dl_w.d(7);
            
            ------------------------
          WHEN RD_CONF =>
            dl_r.rd<='1';
            dl_r.d<=to_unsigned(N,32);
            
          WHEN RD_PTR  =>
            dl_r.rd<='1';
            dl_r.d<=x"0000_0000";
            dl_r.d(N-1 DOWNTO 0)<=cptin;
            dl_r.d(N+15 DOWNTO 16)<=cptout;
            
          WHEN RD_DATA0 =>
            dl_r.rd<='1';
            dl_r.d<=sigr(31 DOWNTO 0);
            
          WHEN RD_DATA1 =>
            dl_r.rd<='1';
            dl_r.d<=sigr(63 DOWNTO 32);
            cptout<=cptout+1;
            
          WHEN OTHERS =>
            dl_r.d<=x"0000_0000";
            
        END CASE;
        
      END IF;
      --------------------------------------------
      CASE conf_div IS
        WHEN "01" => timediv<=timecode(17 DOWNTO 2);
        WHEN "10" => timediv<=timecode(19 DOWNTO 4);
        WHEN "11" => timediv<=timecode(23 DOWNTO 8);
        WHEN OTHERS => timediv<=timecode(15 DOWNTO 0);
      END CASE;
    END IF;
  END PROCESS Glo;
  
END ARCHITECTURE rtl;

