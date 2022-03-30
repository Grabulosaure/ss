--------------------------------------------------------------------------------
-- TEM : PLOMB
-- Test Bench
--------------------------------------------------------------------------------
-- DO 7/2007
--------------------------------------------------------------------------------
-- Simulation
-- Log access PLOMB
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY std;
USE std.textio.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.plomb_pack.ALL;

ENTITY plomb_log IS
  GENERIC (
    nom : string := "xx");
  PORT (
    -- Bus pipe RW
    w       : IN  type_plomb_w;
    r       : IN  type_plomb_r;
    
    -- Global
    clk      : IN std_logic;
    reset_na : IN std_logic
    );
END ENTITY plomb_log;

--##############################################################################

ARCHITECTURE beh OF plomb_log IS

  CONSTANT PROF : natural := 400;
  FILE fil : text OPEN write_mode IS "Plomb_" & nom & ".log";
  SIGNAL fifo : arr_plomb_w(0 TO PROF);
  SIGNAL level : natural RANGE 0 TO PROF;

--------------------------------------------------------------------------------
BEGIN
  --pragma synthesis_off

  Log:PROCESS(clk,reset_na)
    VARIABLE lout : line;
    VARIABLE t  : string(1 TO 8);
    VARIABLE co : character;
  BEGIN
    IF reset_na='0' THEN
      level<=0;
      
    ELSIF rising_edge(clk) THEN
      -- Lectures
      IF w.dack='1' AND r.dreq='1' THEN
        fifo(0 TO PROF-2)<=fifo(1 TO PROF-1);
        t:=To_HString(fifo(0).d);
        IF fifo(0).be(0)='0' THEN  t(1 TO 2):="--"; END IF;
        IF fifo(0).be(0)='X' THEN  t(1 TO 2):="XX"; END IF;
        IF fifo(0).be(1)='0' THEN  t(3 TO 4):="--"; END IF;
        IF fifo(0).be(1)='X' THEN  t(3 TO 4):="XX"; END IF;
        IF fifo(0).be(2)='0' THEN  t(5 TO 6):="--"; END IF;
        IF fifo(0).be(2)='X' THEN  t(5 TO 6):="XX"; END IF;
        IF fifo(0).be(3)='0' THEN  t(7 TO 8):="--"; END IF;
        IF fifo(0).be(3)='X' THEN  t(7 TO 8):="XX"; END IF;
        IF fifo(0).cont='1' THEN
          co:='+';
        ELSE
          co:=' ';
        END IF;
        IF fifo(0).mode=PB_MODE_WR_ACK THEN
          IF r.code=PB_OK THEN
            write (lout,string'("WRack(" & To_HString(fifo(0).asi) & ","
                                & To_HString(fifo(0).ah) & "."
                                & To_HString(fifo(0).a) & ")" & co & " "
                                & pb_btxt(fifo(0)) & "< "
                                & t --To_HString(fifo(0).d)
                                & "  " & time'image(now)
                                ));
          ELSE
            write (lout,string'("WRack(" & To_HString(fifo(0).asi) & ","
                                & To_HString(fifo(0).ah) & "."
                                & To_HString(fifo(0).a) & ")" & co & " "
                                & pb_btxt(fifo(0)) & "< "
                                & t --To_HString(fifo(0).d)
                                & "  " & time'image(now)
                                & "  " & enum_plomb_code'image(r.code)
                                ));
            
          END IF;
        ELSIF fifo(0).mode=PB_MODE_RD THEN
          IF r.code=PB_OK THEN
            write (lout,string'("RD   (" & To_HString(fifo(0).asi) & ","
                                & To_HString(fifo(0).ah) & "."
                                & To_HString(fifo(0).a) & ")" & co & " "
                                & pb_btxt(fifo(0)) & "> "
                                & To_HString(r.d)
                                & "  " & time'image(now)
                                ));
          ELSE
            write (lout,string'("RD   (" & To_HString(fifo(0).asi) & ","
                                & To_HString(fifo(0).ah) & "."
                                & To_HString(fifo(0).a) & ")" & co & " "
                                & pb_btxt(fifo(0)) & "> "
                                & To_HString(r.d)
                                & "  " & time'image(now)
                                & "  " & enum_plomb_code'image(r.code)
                                ));
          END IF;
          
        ELSE
          write (lout,string'("ERREUR " & time'image(now)
                            ));
        END IF;
        writeline (fil,lout);
      END IF;

      IF w.req='1' AND w.mode(1)='1' AND r.ack='1'
        AND NOT (w.dack='1' AND r.dreq='1') THEN
        -- Si empile
        fifo(level)<=w;
        level<=level+1;
      ELSIF w.req='1' AND w.mode(1)='1' AND r.ack='1'
        AND (w.dack='1' AND r.dreq='1') THEN
        -- Si empile et dépile
        fifo(level-1)<=w;
      ELSIF NOT (w.req='1' AND w.mode(1)='1' AND r.ack='1')
        AND (w.dack='1' AND r.dreq='1')
      THEN
        -- Si dépile
        IF level >0 THEN
          level<=level-1;
        END IF;
      END IF;
      -- Ecritures
      IF w.req='1' AND w.mode=PB_MODE_WR AND r.ack='1' THEN
        t:=To_HString(w.d);
        IF w.be(0)='0' THEN  t(1 TO 2):="--"; END IF;
        IF w.be(0)='X' THEN  t(1 TO 2):="XX"; END IF;
        IF w.be(1)='0' THEN  t(3 TO 4):="--"; END IF;
        IF w.be(1)='X' THEN  t(3 TO 4):="XX"; END IF;
        IF w.be(2)='0' THEN  t(5 TO 6):="--"; END IF;
        IF w.be(2)='X' THEN  t(5 TO 6):="XX"; END IF;
        IF w.be(3)='0' THEN  t(7 TO 8):="--"; END IF;
        IF w.be(3)='X' THEN  t(7 TO 8):="XX"; END IF;
        IF w.cont='1' THEN
          co:='+';
        ELSE
          co:=' ';
        END IF;
        write (lout,string'("WR   (" & To_HString(w.asi) & ","
                            & To_HString(w.ah) & "."
                            & To_HString(w.a) & ")" & co & " "
                            & pb_btxt(w) & "< "
                            & t--To_HString(w.d)
                            & "  " & time'image(now)
                            ));
        writeline (fil,lout);
      END IF;
      
    END IF;
  END PROCESS Log;

  --pragma synthesis_on
END ARCHITECTURE beh;

