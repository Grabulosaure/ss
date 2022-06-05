--------------------------------------------------------------------------------
-- TEM
-- Video VGA
--------------------------------------------------------------------------------
-- DO 11/2010
--------------------------------------------------------------------------------
-- - DMA to framebuffer memory
-- - 1,2,4,8 bits per pixel
-- - Colours/BW
-- - Programmable resolution
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
USE work.vid_pack.ALL;

ENTITY vid IS
  GENERIC (
    BURSTLEN    : natural := 4;  -- Longueur accès burst
    FIFO_SIZE   : natural := 16; -- Taille FIFO pixels
    FIFO_AEC    : natural := 0; -- Nombre d'accès entre REQ et DACK
    ASI         : uv8);
  PORT (
    pw     : OUT type_plomb_w;
    pr     : IN  type_plomb_r;

    adr    : IN uv32;                   -- Adresse framebuffer 31:0
    adr_h  : IN uv4;                    -- Adresse framebuffer 35:32
    run    : IN std_logic;              -- RUN/STOP
    mode   : IN type_modeline;
    conf   : IN type_videoconf;
    
    -- Video
    vga_r    : OUT uv8;
    vga_g    : OUT uv8;
    vga_b    : OUT uv8;
    vga_de   : OUT std_logic;
    vga_hsyn : OUT std_logic;
    vga_vsyn : OUT std_logic;
    vga_hpos : OUT uint12;
    vga_vpos : OUT uint12;
    vga_clk  : IN  std_logic;
    vga_en   : IN  std_logic;           -- Clock enable
    
    -- Global
    clk      : IN std_logic;
    reset_n  : IN std_logic
    );
END ENTITY vid;

--##############################################################################

ARCHITECTURE rtl OF vid IS
  CONSTANT N_LINE : natural := ilog2(BURSTLEN);
  
  TYPE arr_word IS ARRAY(natural RANGE <>) OF uv32;
  
  SIGNAL vfifo_ra,vfifo_wa,vfifo_lev : natural RANGE 0 TO FIFO_SIZE-1;
  SIGNAL vfifo : arr_word(0 TO FIFO_SIZE-1);

  SIGNAL dma_stopreq : std_logic; 
  SIGNAL vfifo_data : uv32;
  
  SIGNAL pw_i : type_plomb_w;

  TYPE enum_etat IS (sSTOP,sRUN,sRAZ,sRAZ2);
  SIGNAL etat  : enum_etat;
  SIGNAL dma_a : uv32;
  SIGNAL plomb_aec : natural RANGE 0 TO FIFO_AEC + BURSTLEN +1 + 1;
  
  SIGNAL pop,popsync,popsync2 : std_logic;
  SIGNAL raz,razsync,razsync2 : std_logic;

  ---------------------------------------------
  SIGNAL g_clk,g_en,g_reset_na,g_reset_na2 : std_logic;
  SIGNAL g_run,g_raz,g_razp : std_logic;
  SIGNAL g_data : uv32;
  SIGNAL g_pop  : std_logic;
  
  SIGNAL g_hdisp,g_hdisp2,g_vdisp : std_logic;
  SIGNAL g_hsync,g_vsync,g_de : std_logic;
  SIGNAL g_hcpt,g_vcpt : uint12;
  SIGNAL g_pixcpt : natural RANGE 0 TO 31;
  SIGNAL g_rad : uv32;
  
  TYPE type_col IS RECORD
    r : uv8;
    g : uv8;
    b : uv8;
  END RECORD type_col;
  TYPE arr_col IS ARRAY(natural RANGE <>) OF type_col;
  
  CONSTANT C_NOIR     : type_col := (x"00",x"00",x"00");
  CONSTANT C_BLEU     : type_col := (x"00",x"00",x"AA");
  CONSTANT C_VERT     : type_col := (x"00",x"AA",x"00");
  CONSTANT C_CYAN     : type_col := (x"00",x"AA",x"AA");
  CONSTANT C_ROUGE    : type_col := (x"AA",x"00",x"00");
  CONSTANT C_MAGENTA  : type_col := (x"AA",x"00",x"AA");
  CONSTANT C_BRUN     : type_col := (x"AA",x"55",x"00");
  CONSTANT C_JAUNE    : type_col := (x"AA",x"AA",x"00");
  CONSTANT C_CLAIR    : type_col := (x"AA",x"AA",x"AA");
  CONSTANT C_SOMBRE   : type_col := (x"55",x"55",x"55");
  CONSTANT C_BLEU2    : type_col := (x"55",x"55",x"FF");
  CONSTANT C_VERT2    : type_col := (x"55",x"FF",x"55");
  CONSTANT C_CYAN2    : type_col := (x"55",x"FF",x"FF");
  CONSTANT C_ROUGE2   : type_col := (x"FF",x"55",x"55");
  CONSTANT C_MAGENTA2 : type_col := (x"FF",x"55",x"FF");
  CONSTANT C_JAUNE2   : type_col := (x"FF",x"FF",x"55");
  CONSTANT C_BLANC    : type_col := (x"FF",x"FF",x"FF");

  SIGNAL g_col : type_col;
  
  ---------------------------------------------
  
  CONSTANT pal4 : arr_col(0 TO 15) := (
    C_NOIR     ,C_VERT     ,C_ROUGE    ,C_JAUNE    ,
    C_NOIR     ,C_CYAN     ,C_MAGENTA  ,C_BLANC    ,
    C_NOIR     ,C_CYAN     ,C_ROUGE    ,C_BLANC    ,
    C_NOIR     ,C_VERT     ,C_ROUGE    ,C_BLEU     );
  
  CONSTANT pal16 : arr_col(0 TO 15) := (
    C_NOIR     ,C_BLEU     ,C_VERT     ,C_CYAN     ,
    C_ROUGE    ,C_MAGENTA  ,C_BRUN     ,C_CLAIR    ,
    C_SOMBRE   ,C_BLEU2    ,C_VERT2    ,C_CYAN2    ,
    C_ROUGE2   ,C_MAGENTA2 ,C_JAUNE2   ,C_BLANC    );
    
  -- Calcul couleurs
  FUNCTION calc (
    CONSTANT data : uv8;
    CONSTANT conf : type_videoconf) RETURN type_col IS
    VARIABLE r,v,b : uv8;
  BEGIN
    CASE conf.bpp IS
      WHEN "000" =>
        -- 1bpp, noir et blanc
        v:=sext(data(7),8);
        RETURN (v,v,v);
        
      WHEN "001" =>
        -- 2bpp, 4couleurs d'après 4 palettes
        IF conf.col='1' THEN
          RETURN pal4(to_integer(conf.pal & data(7 DOWNTO 6)));
        ELSE
          v:=data(7 DOWNTO 6) & data(7 DOWNTO 6) &
              data(7 DOWNTO 6) & data(7 DOWNTO 6);
          RETURN (v,v,v);
        END IF;

      WHEN "010" =>
        -- 4bpp, 16 couleurs ou 16 niveaux de gris
        IF conf.col='1' THEN
          RETURN pal16(to_integer(data(7 DOWNTO 4)));
        ELSE
          r:=data(7 DOWNTO 4) & data(7 DOWNTO 4);
          v:=data(7 DOWNTO 4) & data(7 DOWNTO 4);
          b:=data(7 DOWNTO 4) & data(7 DOWNTO 4);
        END IF;
        RETURN (r,v,b);
        
      WHEN OTHERS =>
        -- 8bpp
        IF conf.col='1' THEN
          r:=data(7 DOWNTO 5) & data(7 DOWNTO 5) & data(7 DOWNTO 6);
          v:=data(4 DOWNTO 2) & data(4 DOWNTO 2) & data(4 DOWNTO 3);
          b:=data(1 DOWNTO 0) & data(1 DOWNTO 0) &
            data(1 DOWNTO 0) & data(1 DOWNTO 0);
          RETURN (r,v,b);
        ELSE
          RETURN (data(7 DOWNTO 0),data(7 DOWNTO 0),data(7 DOWNTO 0));
        END IF;
        
    END CASE;
  END FUNCTION calc;

  --------------------------------------
  CONSTANT PLOMB_W_INIT : type_plomb_w :=(
    a=>x"00000000",ah=>"0000",asi=>ASI,
    d=>x"00000000",be=>"1111",mode=>PB_MODE_RD,
    burst=>PB_SINGLE,cont=>'0',cache=>'0',lock=>'0',req=>'0',dack=>'1');

  CONSTANT ZERO : uv32 := x"00000000";
  
BEGIN
  
  ------------------------------------------------------------------------------
  -- Plomb DMA burst
  Plombage:PROCESS(clk)
    VARIABLE ptr : unsigned(N_LINE-1 DOWNTO 0);
    VARIABLE pop_v : std_logic;
  BEGIN
    IF rising_edge(clk) THEN
      pw_i<=PLOMB_W_INIT;
      pw_i.ah<=adr_h;

      ---------------------------------------------
      -- Pipe adresses
      IF pw_i.req='1' AND pr.ack='0' THEN
        -- Attente
        pw_i<=pw_i;
      ELSIF pw_i.req='0' OR pr.ack='1' THEN
        -- Fin d'accès
        IF dma_stopreq='1' AND
          dma_a(N_LINE+1 DOWNTO 2)=ZERO(N_LINE+1 DOWNTO 2) THEN
          pw_i.req<='0';
        ELSE
          pw_i<=PLOMB_W_INIT;
          pw_i.req<='1';
          pw_i.a<=dma_a;
          IF dma_a(N_LINE+1 DOWNTO 2)=ZERO(N_LINE+1 DOWNTO 2) THEN
            pw_i.burst<=pb_blen(BURSTLEN);
          ELSE
            pw_i.burst<=PB_SINGLE;
          END IF;
          dma_a<=dma_a+4;
        END IF;
      END IF;

      ---------------------------------------------
      -- Pipe data, FIFO
      pop_v:=popsync2 XOR popsync;
      IF pr.dreq='1' THEN
        vfifo(vfifo_wa)<=pr.d;
        vfifo_wa<=(vfifo_wa+1) MOD FIFO_SIZE;
      END IF;
      IF pop_v='1' THEN
        vfifo_ra<=(vfifo_ra+1) MOD FIFO_SIZE;
      END IF;
      IF pr.dreq='1' AND pop='0' THEN
        vfifo_lev<=vfifo_lev+1;
      ELSIF pr.dreq='0' AND pop='1' AND vfifo_lev>0 THEN
        vfifo_lev<=vfifo_lev-1;
      END IF;

      IF vfifo_lev>FIFO_SIZE-FIFO_AEC-BURSTLEN OR
         plomb_aec>=FIFO_AEC-BURSTLEN THEN
        dma_stopreq<='1';
      ELSE
        dma_stopreq<='0';
      END IF;

      ---------------------------------------------
      -- Comptage PLOMB
      IF pw_i.req='1' AND pr.ack='1' AND NOT pr.dreq='1' THEN
        plomb_aec<=plomb_aec+1;
      ELSIF NOT (pw_i.req='1' AND pr.ack='1') AND pr.dreq='1' THEN
        plomb_aec<=plomb_aec-1;
      END IF;
      
      ---------------------------------------------
      -- Etat d'affichage
      CASE etat IS
        WHEN sSTOP =>
          -- Arrêté, pas d'image
          dma_stopreq<='1';
          IF run='1' THEN
            etat<=sRUN;
          END IF;
          
        WHEN sRUN =>
          IF run='0' THEN
            etat<=sSTOP;
          END IF;
          IF raz='1' THEN
            etat<=sRAZ;
          END IF;
          
        WHEN sRAZ =>
          dma_stopreq<='1';
          IF plomb_aec=0 AND dma_stopreq='1' AND 
            dma_a(N_LINE+1 DOWNTO 2)=ZERO(N_LINE+1 DOWNTO 2) THEN
            etat<=sRAZ2;
            vfifo_lev<=0;
            vfifo_ra<=0;
            vfifo_wa<=0;
          END IF;
          
        WHEN sRAZ2 =>
          dma_stopreq<='1';
          dma_a<=adr;
          etat<=sRUN;
      END CASE;
      
      IF reset_n='0' THEN
        etat<=sSTOP;
        pw_i<=PLOMB_W_INIT;
        pw_i.ah<=adr_h;
        plomb_aec<=0;
        vfifo_lev<=0;
        vfifo_ra<=0;
        vfifo_wa<=0;
        dma_stopreq<='1';
        dma_a<=x"00100000";
      END IF;
    END IF;
  END PROCESS Plombage;
  
  pw<=pw_i;
  
  vfifo_data<=vfifo(vfifo_ra);
  
  ------------------------------------------------------------------------------
  -- Resync
  Sync: PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      -----------------------------------------------
      -- Signaux VGA -> Interne
      popsync<=g_pop;
      popsync2<=popsync;
      razsync<=g_raz;
      razsync2<=razsync;
      pop<=popsync2 XOR popsync;
      raz<=razsync2 XOR razsync;
		
      IF reset_n='0' THEN
        pop<='0';
        raz<='0';
        popsync<='0';
        popsync2<='0';
        razsync<='0';
        razsync2<='0';
		END IF;
    END IF;
  END PROCESS Sync;

  GenGRESET: PROCESS (g_clk, reset_n) IS
  BEGIN
    IF reset_n='0' THEN
      g_reset_na<='0';
      g_reset_na2<='0';
    ELSIF rising_edge(g_clk) THEN
      g_reset_na2<='1';
      g_reset_na<=g_reset_na2;
    END IF;
  END PROCESS GenGRESET;
    
  SyncG: PROCESS (g_clk, g_reset_na) IS
  BEGIN
    IF g_reset_na='0' THEN
      g_run<='0';
    ELSIF rising_edge(g_clk) THEN
      -- Signaux Interne -> VGA
      g_run<=run;
    END IF;
  END PROCESS SyncG;
  
  ------------------------------------------------------------------------------
  g_clk<=vga_clk;
  g_en <=vga_en;
  
  GenVideo: PROCESS (g_clk, g_reset_na) IS
  BEGIN
    IF g_reset_na = '0' THEN
      g_raz<='0';
      g_pop<='0';
      g_hsync<='0';
      g_vsync<='0';
      g_hdisp<='1';
      g_vdisp<='1';
    ELSIF rising_edge(g_clk) THEN
      IF g_en='1' THEN
        ---------------------------------------------
        -- Formattage image
        IF g_run='0' THEN
          g_hcpt<=0;
          g_vcpt<=0;
        ELSE
          IF g_hcpt=mode.htotal-1 THEN
            g_hcpt<=0;
            g_hdisp<='1';
            IF g_vcpt=mode.vtotal-1 THEN
              g_vcpt<=0;
              g_vdisp<='1';
            ELSE
              g_vcpt<=g_vcpt+1;
            END IF;
          ELSE
            g_hcpt<=g_hcpt+1;
          END IF;
        END IF;
        IF g_hcpt=mode.hdisp-1 THEN
          g_hdisp<='0';
        END IF;
        IF g_vcpt=mode.vdisp THEN
          g_vdisp<='0';
          g_razp<='1';
          IF g_razp='0' THEN
            g_raz<=NOT g_raz;
          ELSE
            g_raz<=g_raz;
          END IF;
        ELSE
          g_razp<='0';
          g_raz<=g_raz;
        END IF;
        IF g_hcpt=mode.hsyncstart THEN
          g_hsync<='1';
        ELSIF g_hcpt=mode.hsyncend THEN
          g_hsync<='0';
        END IF;
        IF g_vcpt=mode.vsyncstart THEN
          g_vsync<='1';
        ELSIF g_vcpt=mode.vsyncend THEN
          g_vsync<='0';
        END IF;
        ------------------
        -- Sérialisation pixels
        IF g_hdisp='1' AND g_vdisp='1' THEN
          CASE conf.bpp IS
            WHEN "000" =>
              -- 1bpp
              IF g_pixcpt=31 THEN
                g_pixcpt<=0;
                g_pop<=NOT g_pop;
                g_rad<=vfifo_data;
              ELSE
                g_pixcpt<=g_pixcpt+1;
                g_rad<=g_rad(30 DOWNTO 0) & vfifo_data(0);
              END IF;
            WHEN "001" =>
              -- 2bpp
              IF g_pixcpt=15 THEN
                g_pixcpt<=0;
                g_rad<=vfifo_data;
              ELSE
                g_pixcpt<=g_pixcpt+1;
                g_rad<=g_rad(29 DOWNTO 0) & vfifo_data(1 DOWNTO 0);
              END IF;
              IF g_pixcpt=15 THEN
                g_pop<=NOT g_pop;
              END IF;

            WHEN "010" =>
              -- 4bpp
              IF g_pixcpt=7 THEN
                g_pixcpt<=0;
                g_rad<=vfifo_data;
              ELSE
                g_pixcpt<=g_pixcpt+1;
                g_rad<=g_rad(27 DOWNTO 0) & vfifo_data(3 DOWNTO 0);
              END IF;
              IF g_pixcpt=7 THEN
                g_pop<=NOT g_pop;
              END IF;
              
            WHEN OTHERS =>
              -- 8bpp
              IF g_pixcpt=3 THEN
                g_pixcpt<=0;
                g_rad<=vfifo_data;
              ELSE
                g_pixcpt<=g_pixcpt+1;
                g_rad<=g_rad(23 DOWNTO 0) & vfifo_data(7 DOWNTO 0);
              END IF;
              IF (g_pixcpt=3 AND conf.hf='0') OR
                (g_pixcpt=2 AND conf.hf='1') THEN
                g_pop<=NOT g_pop;
              END IF;
          END CASE;
        ELSE
          CASE conf.bpp(1 DOWNTO 0) IS
            WHEN "00" => g_pixcpt<=31;
            WHEN "01" => g_pixcpt<=15;
            WHEN "10" => g_pixcpt<=7;
            WHEN OTHERS => g_pixcpt<=3;
          END CASE;
        END IF;
        
        g_hdisp2<=g_hdisp;
        IF g_hdisp2='1' AND g_vdisp='1' THEN
          g_col<=calc(g_rad(31 DOWNTO 24),conf);
          g_de <='1';
        ELSE
          g_col<=C_NOIR;
          g_de <='0';
        END IF;
      END IF;
    END IF;
  END PROCESS GenVideo;

  vga_r<=g_col.r;
  vga_g<=g_col.g;
  vga_b<=g_col.b;
  vga_de<=g_de;
  vga_hsyn<=g_hsync XOR mode.hsyncpol;
  vga_vsyn<=g_vsync XOR mode.vsyncpol;
  vga_hpos<=g_hcpt;
  vga_vpos<=g_vcpt;

END ARCHITECTURE rtl;
