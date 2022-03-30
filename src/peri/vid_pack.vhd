--------------------------------------------------------------------------------
-- TEM
-- Video VGA
--------------------------------------------------------------------------------
-- DO 11/2010
--------------------------------------------------------------------------------
            
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

PACKAGE vid_pack IS
  
  TYPE type_modeline IS RECORD
--    dotclock   : real;
    hdisp      : natural range 0 to 4095;
    hsyncstart : natural range 0 to 4095;
    hsyncend   : natural range 0 to 4095;
    htotal     : natural range 0 to 4095;
    vdisp      : natural range 0 to 4095;
    vsyncstart : natural range 0 to 4095;
    vsyncend   : natural range 0 to 4095;
    vtotal     : natural range 0 to 4095;
    hsyncpol   : std_logic;  -- 0=-HSync 1=+HSync
    vsyncpol   : std_logic;  -- 0=-VSync 1=+VSync
  END RECORD type_modeline;

  --640  480  60 Hz  31.475 kHz   ModeLine "640x480" 25.18 640 656 752 800 480 490 492 525 -HSync -VSync
  CONSTANT MODELINE_640_480_60Hz_25MHz : type_modeline := (--25.18,
    640,656,752,800,480,490,492,525,'0','0');
  --640  480  73 Hz  37.8606 kHz  ModeLine "640x480" 31.50 640 664 704 832 480 489 492 520 -HSync -VSync
  --640  480  75 Hz  37.5 kHz     ModeLine "640x480" 31.50 640 656 720 840 480 481 484 500 -HSync -VSync
  --640  480  85 Hz  43.2692 kHz  ModeLine "640x480" 36.00 640 696 752 832 480 481 484 509 -HSync -VSync

  --800  600  56 Hz  35.1562 kHz  ModeLine "800x600" 36.00 800 824 896 1024 600 601 603 625 +HSync +VSync
  --800  600  60 Hz  37.8788 kHz  ModeLine "800x600" 40.00 800 840 968 1056 600 601 605 628 +HSync +VSync
  CONSTANT MODELINE_800_600_60Hz_40MHz : type_modeline := (--40.00,
    800,840,968,1056,600,601,605,628,'1','1');
  --800  600  72 Hz  48.0769 kHz  ModeLine "800x600" 50.00 800 856 976 1040 600 637 643 666 +HSync +VSync
  --800  600  75 Hz  46.875 kHz   ModeLine "800x600" 49.50 800 816 896 1056 600 601 604 625 +HSync +VSync
  --800  600  85 Hz  53.7214 kHz  ModeLine "800x600" 56.30 800 832 896 1048 600 601 604 631 +HSync +VSync
  
  --1024 768 60 Hz   48.3631 kHz  ModeLine "1024x768" 65.00 1024 1048 1184 1344 768 771 777 806 -HSync -VSync
  CONSTANT MODELINE_1024_768_60Hz_65MHz : type_modeline := (--65.00,
    1024,1048,1184,1344,768,771,777,806,'0','0');
  --1024 768 70 Hz   56.4759 kHz  ModeLine "1024x768" 75.00 1024 1048 1184 1328 768 771 777 806 -HSync -VSync

  --1152 864 60 Hz   53.7 kHz     Modeline "1152x864" 81.642 1152 1216 1336 1520 864 865 868 895 +HSync +VSync
  CONSTANT MODELINE_1152_864_60Hz_82MHz : type_modeline := (--81.642,
    1152,1216,1336,1520,864,865,868,895,'1','1');
  --1152 864 70 Hz   62.9948 kHz  ModeLine "1152x864" 96.76 1152 1224 1344 1536 864 865 868 900 -HSync +VSync
  --1152 864 75 Hz   67.5 kHz     ModeLine "1152x864" 108.00 1152 1216 1344 1600 864 865 868 900 +HSync +VSync
  --1152 864 85 Hz   77.4872 kHz  ModeLine "1152x864" 121.50 1152 1216 1344 1568 864 865 868 911 +HSync -VSync
  
  --1280 1024 60 Hz  63.981 kHz   ModeLine "1280x1024" 108.00 1280 1328 1440 1688 1024 1025 1028 1066 +HSync +VSync
  CONSTANT MODELINE_1280_1024_60Hz_108MHz : type_modeline := (--108.00,
    1280,1328,1440,1688,1024,1025,1028,1066,'1','1');
  --1280 1024 75 Hz  79.9763 kHz  ModeLine "1280x1024" 135.00 1280 1296 1440 1688 1024 1025 1028 1066 +HSync +VSync
  --1280 1024 85 Hz  91.1458 kHz  Modeline "1280x1024" 157.50 1280 1344 1504 1728 1024 1025 1028 1072 +HSync +VSync

  --1400 1050 60 Hz  64.8936 kHz  ModeLine "1400x1050" 122.00 1400 1488 1640 1880 1050 1052 1064 1082 +HSync +VSync
  --1400 1050 70 Hz  77.0408 kHz  ModeLine "1400x1050" 151.00 1400 1464 1656 1960 1050 1051 1054 1100 +HSync +VSync
  --1400 1050 75 Hz  81.4854 kHz  ModeLine "1400x1050" 155.80 1400 1464 1784 1912 1050 1052 1064 1090 +HSync +VSync
  --1400 1050 85 Hz  93.8776 kHz  ModeLine "1400x1050" 184.00 1400 1464 1656 1960 1050 1051 1054 1100 +HSync +VSync
  
  TYPE type_videoconf IS RECORD
    bpp : unsigned(2 DOWNTO 0);  -- 000=1bpp, 001=2bpp 010=4bpp 011=8bpp
    col : std_logic;             -- 0=NB, 1=Couleurs
    pal : unsigned(1 DOWNTO 0);  -- Mode palette
    hf  : std_logic;             -- Hautes Fréquences
  END RECORD type_videoconf;

  -- OVO -----------------------------------------
  FUNCTION ovb(i : std_logic) RETURN unsigned;
  FUNCTION ovh(h : unsigned)  RETURN unsigned;
  FUNCTION ovc(c : character) RETURN unsigned;
  FUNCTION ovs(s : string)    RETURN unsigned;
  
END PACKAGE vid_pack;



--------------------------------------------------------------------------------

PACKAGE BODY vid_pack IS

  -- OVO -----------------------------------------
  FUNCTION ovb(i : std_logic) RETURN unsigned IS
  BEGIN
    RETURN "0000" & i;
  END FUNCTION;
  
  FUNCTION ovh(h : unsigned) RETURN unsigned IS
    VARIABLE n : natural :=(h'length+3)/4;
    VARIABLE t : unsigned(h'length-1+3 DOWNTO 0) :="000" & h;
    VARIABLE o : unsigned(n*5-1 DOWNTO 0);
  BEGIN
    FOR i IN n-1 DOWNTO 0 LOOP
      o(i*5+4 DOWNTO i*5):='0' & t(i*4+3 DOWNTO i*4);
    END LOOP;
    RETURN o;
  END FUNCTION ovh;
  
  FUNCTION ovc(c : character) RETURN unsigned IS
  BEGIN
    CASE c IS
      WHEN '0' => RETURN "00000";
      WHEN '1' => RETURN "00001";
      WHEN '2' => RETURN "00010";
      WHEN '3' => RETURN "00011";
      WHEN '4' => RETURN "00100";
      WHEN '5' => RETURN "00101";
      WHEN '6' => RETURN "00110";
      WHEN '7' => RETURN "00111";
      WHEN '8' => RETURN "01000";
      WHEN '9' => RETURN "01001";
      WHEN 'A' => RETURN "01010";
      WHEN 'B' => RETURN "01011";
      WHEN 'C' => RETURN "01100";
      WHEN 'D' => RETURN "01101";
      WHEN 'E' => RETURN "01110";
      WHEN 'F' => RETURN "01111";
      WHEN ' ' => RETURN "10000";
      WHEN '=' => RETURN "10001";
      WHEN '+' => RETURN "10010";
      WHEN '-' => RETURN "10011";
      WHEN '<' => RETURN "10100";
      WHEN '>' => RETURN "10101";
      WHEN '^' => RETURN "10110";
      WHEN 'v' => RETURN "10111";
      WHEN '(' => RETURN "11000";
      WHEN ')' => RETURN "11001";
      WHEN ':' => RETURN "11010";
      WHEN '.' => RETURN "11011";
      WHEN ',' => RETURN "11100";
      WHEN '?' => RETURN "11101";
      WHEN '|' => RETURN "11110";
      WHEN '#' => RETURN "11111";
      WHEN OTHERS => RETURN "10000";
    END CASE;
  END FUNCTION ovc;
  
  FUNCTION ovs(s : string) RETURN unsigned IS
    VARIABLE r : unsigned(0 TO s'length*5-1);
    VARIABLE j : natural :=0;
  BEGIN
    FOR i IN s'RANGE LOOP
      r(j TO j+4) :=ovc(s(i));
      j:=j+5;
    END LOOP;
    RETURN r;
  END FUNCTION ovs;
  -- OVO -----------------------------------------
 
END PACKAGE BODY vid_pack;
