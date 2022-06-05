--------------------------------------------------------------------------------
-- TEM : TS
-- TCX & CG3 Framebuffer
--------------------------------------------------------------------------------
-- DO 12/2010
--------------------------------------------------------------------------------
-- 1024 x 768 * 256 cols

----------------------------------------------------------
--  E_2000_0000 : Base SS10/20
--    5000_0000 : Base SS5
-- +   4xx_xxxx : TCX stippler
-- +   Cxx_xxxx : TCX stippler (raw)
-- +   6xx_xxxx : TCX blitter/filler
-- +   Exx_xxxx : TCX blitter/filler (raw)
-- +    20_0000 : Palette TCX (16 octs)
-- +    20_0004 : Palette TCX (16 octs)
-- +    30_0818 : TCX misc. ctrl
-- +    40_0000 : Palette CG3 (16 octs)
-- +    40_0004 : Palette CG3 (16 octs)
-- +    40_0010 : CG3 ctrl. / intr.
-- +    80_0000 : Framebuffer (2Mo) -> MAP -> 07E0_0000
----------------------------------------------------------
-- CG3 :
-- x10 : CTRL
--        [7]   = Enable Int
--        [6:0] = ?
-- x11 : STAT
--        [7]   = Read : Pending Int. Write : Clear int.
--        [6:5] = 11 : 1152_900_76 display <QEMU>
--        [4:1] = ?
--        [0]   = 1  : Colour

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
USE work.vid_pack.ALL;

ENTITY ts_tcx IS
  GENERIC (
    TCX_ACCEL : boolean := false;       -- TCX Acceleration
    ADR       : uv32;                   -- Base adress
    ADR_H     : uv4; 
    ASI       : uv8);
  PORT (
    sel      : IN  std_logic;
    w        : IN  type_pvc_w;          -- Registres
    r        : OUT type_pvc_r;
    
    pw       : OUT type_plomb_w;        -- Plomb pipe
    pr       : IN  type_plomb_r;        -- Plomb pipe

    -- Configuration
    vga_ctrl : IN  uv16;
    cg3      : IN  std_logic;  -- 0=TCX 1=CG3
    
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
    vga_en   : IN  std_logic;
    vga_on   : IN  std_logic;
    pal_clk  : OUT std_logic;
    pal_d    : OUT uv24;
    pal_a    : OUT uv8;
    pal_wr   : OUT std_logic;

    -- Conf
    int      : OUT std_logic;           -- CG3 Interrupt
    
    -- Global
    clk     : IN  std_logic;
    reset_n : IN  std_logic
    );
END ENTITY ts_tcx;

--##############################################################################

ARCHITECTURE rtl OF ts_tcx IS

  CONSTANT MODE  : type_modeline := MODELINE_1024_768_60Hz_65MHz;
  SIGNAL conf    : type_videoconf;
  
  SIGNAL vid_l : uv8;
  SIGNAL vid_hsyn,vid_vsyn : std_logic;
  SIGNAL vid_hpos,vid_vpos : uint12;
  SIGNAL vid_de  : std_logic;
  SIGNAL vga_run : std_logic;
  
  SIGNAL palw : std_logic;
  SIGNAL palrgb_wr,palrgb_rd : unsigned(23 DOWNTO 0);
  SIGNAL palidx,palidx2,palidx3 : uint8;
  SIGNAL palcyc : natural RANGE 0 TO 2;
  SIGNAL dr : uv32;

  TYPE arr_uv24 IS ARRAY(natural RANGE <>) OF unsigned(23 DOWNTO 0);
  SIGNAL vga_pal : arr_uv24(0 TO 255);
  ATTRIBUTE ramstyle : string;
  ATTRIBUTE ramstyle OF vga_pal : SIGNAL IS "no_rw_check";

  SIGNAL cg3_ctrl : uv8;
  SIGNAL cg3_clrint,cg3_setint,cg3_int : std_logic;
  SIGNAL vsync_sync,vsync_sync2,vsync_sync3 : std_logic;

  SIGNAL pal_dw : uv32;
  SIGNAL pal_be : uv0_3;

  SIGNAL vga_rgb  : unsigned(23 DOWNTO 0);
  SIGNAL vid_ad   : uint8;
  SIGNAL tcx_misc : uv32;

  SIGNAL vid_pw,acc_pw : type_plomb_w;
  SIGNAL vid_pr,acc_pr : type_plomb_r;
  SIGNAL vi_w : arr_plomb_w(0 TO 1);
  SIGNAL vi_r : arr_plomb_r(0 TO 1);
  SIGNAL acc_rad : unsigned(55 DOWNTO 0);
  SIGNAL acc_fifo : arr_uv32(0 TO 7);

  SIGNAL acc_berad : unsigned(6 DOWNTO 0);
  SIGNAL acc_fifobe : uv32;
  
  SIGNAL acc_src,acc_dst : unsigned(19 DOWNTO 0);
  SIGNAL acc_len         : unsigned(4 DOWNTO 0);
  SIGNAL acc_fill : uv8;
  SIGNAL acc_stip : uv32;
  SIGNAL acc_start : std_logic;

  SIGNAL acc_sec  : std_logic;
  SIGNAL acc_dptr : unsigned(4 DOWNTO 0);
  TYPE acc_etat_enum IS (sOISIF,sREAD,sREADWAIT,sBOURRE,sTURN,sWRITE);
  SIGNAL acc_etat : acc_etat_enum;
  SIGNAL acc_rd_fin,acc_rd_fin2 : std_logic;
  SIGNAL dreq_delay : std_logic;
  SIGNAL acc_push : std_logic;
  SIGNAL acc_wseq : natural RANGE 0 TO 3;
  SIGNAL acc_be : uv0_3;
  SIGNAL acc_bfill : std_logic;
  SIGNAL trans : std_logic;
  
BEGIN

  vga_run <=vga_ctrl(0) OR vga_on;
  conf.bpp<="011";
  conf.hf <='0'; 
  conf.col<='0';
  conf.pal<="00";
  
  -------------------------------------------------------------
  Gen_ACCEL: IF TCX_ACCEL GENERATE
    i_plomb_mux: ENTITY work.plomb_mux
      GENERIC MAP (
        NB        => 2,
        PROF      => 32)
      PORT MAP (
        vi_w    => vi_w,
        vi_r    => vi_r,
        o_w     => pw,
        o_r     => pr,
        clk     => clk,
        reset_n => reset_n);

    vi_w(0)<=vid_pw;
    vi_w(1)<=acc_pw;
    vid_pr<=vi_r(0);
    acc_pr<=vi_r(1);
  END GENERATE Gen_ACCEL;

  Gen_NoACCEL: IF NOT TCX_ACCEL GENERATE
    pw<=vid_pw;
    vid_pr<=pr;
  END GENERATE Gen_NoACCEL;
  
  i_vid: ENTITY work.vid
    GENERIC MAP (
      BURSTLEN    => 8,
      FIFO_SIZE   => 128,
      FIFO_AEC    => 16,
      ASI         => ASI)
      --BURSTLEN    => 8,
      --FIFO_SIZE   => 64,
      --FIFO_AEC    => 15)
      --BURSTLEN    => 8,
      --FIFO_SIZE   => 32,
      --FIFO_AEC    => 7)
    PORT MAP (
      pw       => vid_pw,
      pr       => vid_pr,
      adr      => ADR,
      adr_h    => ADR_H,
      run      => vga_run,
      mode     => MODE,
      conf     => conf,
      vga_r    => vid_l,
      vga_g    => OPEN,
      vga_b    => OPEN,
      vga_de   => vid_de,
      vga_hsyn => vid_hsyn,
      vga_vsyn => vid_vsyn,
      vga_hpos => vid_hpos,
      vga_vpos => vid_vpos,
      vga_clk  => vga_clk,
      vga_en   => vga_en,
      clk      => clk,
      reset_n  => reset_n);
  
  -------------------------------------------------------------
  Delai:PROCESS (vga_clk) IS
    VARIABLE a : uint8;
  BEGIN
    IF rising_edge(vga_clk) THEN
      vga_hsyn<=vid_hsyn AND vga_run;
      vga_vsyn<=vid_vsyn AND vga_run;
      vga_de  <=vid_de   AND vga_run;
      vga_hpos<=vid_hpos;
      vga_vpos<=vid_vpos;
    END IF;

  END PROCESS Delai;
  
  -------------------------------------------------------------  
  --Palette:PROCESS (vga_clk) IS
  --  VARIABLE a : uint8;
  --BEGIN
  --  IF rising_edge(vga_clk) THEN
  --    a:=to_integer(vid_l);
  --    vga_r<=vga_pal(a)(23 DOWNTO 16);
  --    vga_g<=vga_pal(a)(15 DOWNTO 8);
  --    vga_b<=vga_pal(a)(7  DOWNTO 0);
  --  END IF;
  --END PROCESS Palette;

  --Palette_RW:PROCESS(clk) IS
  --BEGIN
  --  IF rising_edge(clk) THEN
  --    palrgb_rd<=vga_pal(palidx3)(23 DOWNTO 0);
  --    IF palw='1' THEN
  --      vga_pal(palidx3)<=x"00" & palrgb_wr;
  --    END IF;
  --  END IF;
  --END PROCESS Palette_RW;
  
  vid_ad<=to_integer(vid_l);
  
  Palette:PROCESS (vga_clk) IS
  BEGIN
    IF rising_edge(vga_clk) THEN
      vga_rgb<=vga_pal(vid_ad);
    END IF;
  END PROCESS Palette;
  
  vga_r<=vga_rgb(23 DOWNTO 16);
  vga_g<=vga_rgb(15 DOWNTO 8);
  vga_b<=vga_rgb(7  DOWNTO 0);

  Palette_RW:PROCESS(clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      palrgb_rd<=vga_pal(palidx3);
      IF palw='1' THEN
        vga_pal(palidx3)<=palrgb_wr;
      END IF;
    END IF;
  END PROCESS Palette_RW;

  -------------------------------------------------------------
  pal_clk<=clk;
  pal_wr <=palw;
  pal_a  <=to_unsigned(palidx3,8);
  pal_d  <=palrgb_wr;
  
  -------------------------------------------------------------
  Regs: PROCESS (clk)
  BEGIN
    IF rising_edge(clk) THEN
      palw<='0';
      dr<=x"00000000";
      cg3_clrint<='0';
      IF (pal_be(0) OR pal_be(1) OR pal_be(2) OR pal_be(3))='0' AND
        (acc_etat=sOISIF OR NOT TCX_ACCEL) AND acc_start='0' THEN
        trans<='0';
      END IF;
      
      -------------------------------------------------------------
      -- 02x_xx00 / 4x_xx00 : Palette : Index
      IF sel='1' AND w.req='1' AND w.a(5 DOWNTO 2)="0000" AND
        ((w.a(27 DOWNTO 20)=x"02" AND cg3='0') OR
         (w.a(27 DOWNTO 20)=x"04" AND cg3='1')) AND trans='0' THEN
        IF w.be(0)='1' AND w.wr='1' THEN
          palidx<=to_integer(w.dw(31 DOWNTO 24));
          palcyc<=0;
        END IF;
        dr<=to_unsigned(palidx,8) & x"000000";
      END IF;

      -------------------------------------------------------------
      -- 030_x818 : TCX : THC_MISC reg.
      IF sel='1' AND w.req='1' AND w.a(27 DOWNTO 20)=x"03" AND
        w.a(11 DOWNTO 2)="1000000110" AND cg3='0' AND  trans='0' THEN
        IF w.be(0)='1' AND w.wr='1' THEN
          tcx_misc<=w.dw;
        END IF;
        dr<=tcx_misc OR x"0200_0000";               -- Colours display
      END IF;
      
      -------------------------------------------------------------
      -- 2x_xx04 / 4x_xx04 : Palette : Colour
      -- <AVOIR> Minimum 4 cycles pour écriture 32bits
      -- <AVOIR> Minimum 2 cycles pour relecture palette
      IF pal_be(0)='1' THEN
        IF palcyc=2 THEN
          palcyc<=0;
          palw<='1';
          palidx<=(palidx+1) MOD 256;
        ELSE
          palcyc<=palcyc+1;
        END IF;
        palrgb_wr<=palrgb_wr(15 DOWNTO 0) & pal_dw(31 DOWNTO 24);
      END IF;
      pal_be<=pal_be(1 TO 3) & '0';
      pal_dw <=pal_dw(23 DOWNTO 0) & pal_dw(7 DOWNTO 0);

      IF sel='1' AND w.req='1' AND w.a(5 DOWNTO 2)="0001" AND
        ((w.a(27 DOWNTO 20)=x"02" AND cg3='0') OR
         (w.a(27 DOWNTO 20)=x"04" AND cg3='1')) AND trans='0' THEN
        IF w.wr='1' THEN
          pal_be<=w.be;
          IF w.a(21)='1' THEN
            pal_be(1 TO 3)<="000";      -- TCX : 8bits !
          END IF;
          pal_dw<=w.dw;
        ELSE
          IF palcyc=2 THEN
            palcyc<=0;
            palidx<=(palidx+1) MOD 256;
          ELSE
            palcyc<=palcyc+1;
          END IF;
        END IF;
        IF palcyc=0 THEN
          dr<=palrgb_rd(23 DOWNTO 16) & x"000000";
        ELSIF palcyc=1 THEN
          dr<=palrgb_rd(15 DOWNTO 8) & x"000000";
        ELSE
          dr<=palrgb_rd(7 DOWNTO 0) & x"000000";
        END IF;
      END IF;
      
      -------------------------------------------------------------
      -- 04x_xx10 : CG3 : Control | Status | CurStart | CurEnd
      IF sel='1' AND w.req='1' AND w.a(5 DOWNTO 2)="0100" AND
        w.a(27 DOWNTO 20)=x"04" AND cg3='1' AND trans='0' THEN
        IF w.be(0)='1' AND w.wr='1' THEN
          cg3_ctrl<=w.dw(31 DOWNTO 24);
        END IF;
        IF w.be(1)='1' AND w.wr='1' THEN
          cg3_clrint<=w.dw(23);
        END IF;
        dr<=cg3_ctrl & cg3_int & "1100001" & x"0000";
        trans<='1';
      END IF;

      -------------------------------------------------------------
      -- 4xx_xxxx / Cxx_xxxx : STIPPLER
      -- 4xx_xxx0/8 : D[7:0] : Couleur STIPPLER
      -- 4xx_xxx4/C : Motif 32bits
      acc_start<='0';
      IF sel='1' AND w.req='1' AND w.a(2)='1' AND
        (w.a(27 DOWNTO 24)=x"4" OR w.a(27 DOWNTO 24)=x"C") AND
         trans='0' AND TCX_ACCEL THEN
        acc_dst<=w.a(22 DOWNTO 3);
        acc_src<=w.dw(19 DOWNTO 0); -- Inutile
        acc_bfill<='1';
        acc_len<="11111";
        acc_stip<=w.dw(31 DOWNTO 0);
        acc_start<=w.be(0) AND w.wr;
        trans<='1';
      END IF;
      
      IF sel='1' AND w.req='1' AND w.a(2)='0' AND
        (w.a(27 DOWNTO 24)=x"4" OR w.a(27 DOWNTO 24)=x"C") AND trans='0' THEN
        acc_fill<=w.dw(7 DOWNTO 0);
        trans<='1';
      END IF;
      
      -------------------------------------------------------------
      -- 6xx_xxxx / Exx_xxxx : BLIT / FILL
      -- 6xx_xxx0/8 : D[7:0] : Couleur FILL
      -- 6xx_xxx4/C : D[31:24]=LEN-1 D[19:0]=Source A[22:3]=Destination
      --              source=FFFFFF : FILL
      IF sel='1' AND w.req='1' AND w.a(2)='1' AND
        (w.a(27 DOWNTO 24)=x"6" OR w.a(27 DOWNTO 24)=x"E") AND
        trans='0' AND TCX_ACCEL THEN
        acc_dst<=w.a(22 DOWNTO 3);
        acc_src<=w.dw(19 DOWNTO 0);
        acc_bfill<=to_std_logic(w.dw(23 DOWNTO 16)=x"FF");
        acc_stip<=x"FFFFFFFF";
        acc_len<=w.dw(28 DOWNTO 24);
        acc_start<=w.be(0) AND w.wr;
        trans<='1';
      END IF;
      
      IF sel='1' AND w.req='1' AND w.a(2)='0' AND
        (w.a(27 DOWNTO 24)=x"6" OR w.a(27 DOWNTO 24)=x"E") AND trans='0' THEN
        acc_fill<=w.dw(7 DOWNTO 0);
        trans<='1';
      END IF;
      
      -------------------------------------------------------------
      cg3_int<=((cg3_int OR cg3_setint) AND NOT cg3_clrint)
                AND cg3 AND cg3_ctrl(7);

      -------------------------------------------------------------
      IF reset_n='0' THEN
        palidx<=0;
        palw<='0';
        palcyc<=0;
      END IF;
      -------------------------------------------------------------
    END IF;
  END PROCESS Regs;

  -- Relectures
  R_Gen:PROCESS(w,dr,sel,trans)
  BEGIN
    r.ack<=w.req AND sel AND NOT trans;
    r.dr<=dr;
  END PROCESS R_Gen;

  -------------------------------------------------------------
  int<=cg3_int;

  palidx2<=palidx  WHEN rising_edge(clk);
  palidx3<=palidx2 WHEN rising_edge(clk);

  vsync_sync<=vid_vsyn WHEN rising_edge(clk);  -- <ASYNC>
  vsync_sync2<=vsync_sync WHEN rising_edge(clk);
  vsync_sync3<=vsync_sync2 WHEN rising_edge(clk);
  
  cg3_setint<=vsync_sync2 AND NOT vsync_sync3 WHEN rising_edge(clk);

  -------------------------------------------------------------
  -- Accélérateur
  GenAccelProcess: IF TCX_ACCEL GENERATE
  
  Accel:PROCESS (clk) IS
    VARIABLE fsrc_v,fdst_v : unsigned(5 DOWNTO 0);
    VARIABLE deca_v : unsigned(1 DOWNTO 0);
    VARIABLE shift_v,push_v : std_logic;
    VARIABLE be_v : uv0_3;
    VARIABLE mux_v,fifoin_v : uv32;
    VARIABLE fifobein_v : uv4;
    VARIABLE rd_act_v,rd_deb_v,rd_fin_v : std_logic;
    VARIABLE wr_act_v,wr_deb_v,wr_fin_v : std_logic;
    VARIABLE ibourre_v : std_logic;
  BEGIN
    IF rising_edge(clk) THEN

      -- Adresses de fin
      fsrc_v:=('0' & acc_src(4 DOWNTO 0))+acc_len;
      fdst_v:=('0' & acc_dst(4 DOWNTO 0))+acc_len;
      -----------------------------------------------------
      -- Machine à états. Accès PLOMB
      acc_pw.req<='0';
      ibourre_v:='0';
      
      CASE acc_etat IS
        WHEN sOISIF =>
          acc_fifobe<=acc_stip;
          acc_pw.req<='0';
          acc_pw.burst<=PB_BURST8;
          acc_dptr<="00000"; -- Compte les transferts de données
          acc_sec<='0';
          acc_wseq<=0;
          
          IF acc_bfill='1' THEN
            acc_pw.mode<=PB_MODE_WR;
            acc_pw.a<=ADR(31 DOWNTO 20) & acc_dst(19 DOWNTO 5) & "00000";
          ELSE
            acc_pw.mode<=PB_MODE_RD;
            acc_pw.a<=ADR(31 DOWNTO 20) & acc_src(19 DOWNTO 5) & "00000";
          END IF;
          IF acc_start='1' THEN
            IF acc_bfill='1' THEN
              acc_etat<=sWRITE; -- FILL
            ELSE
              acc_etat<=sREAD;  -- BLIT
            END IF;
          END IF;
          
        WHEN sREAD =>
          acc_pw.req<='1';
          IF acc_pr.ack='1' AND acc_pw.req='1' THEN
            acc_pw.a<=acc_pw.a+4;
            acc_pw.burst<=PB_SINGLE;
          END IF;
          IF acc_pr.ack='1' AND acc_pw.req='1' AND
            acc_pw.a(4 DOWNTO 2)="111" THEN
            IF fsrc_v(5)='0' OR acc_sec='1' THEN
              acc_etat<=sREADWAIT;
              acc_pw.req<='0';
            ELSE
              acc_pw.burst<=PB_BURST8;
              acc_sec<='1';
            END IF;
          END IF;
          IF acc_pr.dreq='1' THEN
            acc_dptr<=acc_dptr+1;
          END IF;
          
        WHEN sREADWAIT =>
          acc_sec<='0';
          IF (acc_dptr=8  AND fsrc_v(5)='0') OR acc_dptr=16 THEN
            -- Toutes les données de 1 ou 2 burst ont étés transférées.
            IF fsrc_v(5)='0' AND (fsrc_v(4 DOWNTO 2)/="111" OR
                                  acc_src(4 DOWNTO 2)/="000") THEN
              acc_etat<=sBOURRE;
              ibourre_v:='1';
            ELSE
              acc_dptr<="00000";
              acc_etat<=sWRITE;
              IF acc_rd_fin='1' AND acc_src(1 DOWNTO 0)/="00" THEN
                acc_etat<=sTURN;
                ibourre_v:='1';
              END IF;
            END IF;
          END IF;
          acc_pw.a<=ADR(31 DOWNTO 20) & acc_dst(19 DOWNTO 5) & "00000";
          acc_pw.burst<=PB_BURST8;
          acc_pw.mode<=PB_MODE_WR;
          IF acc_pr.dreq='1' THEN
            acc_dptr<=acc_dptr+1;
          END IF;
          
        WHEN sBOURRE =>
          IF acc_dptr(2 DOWNTO 0)=acc_src(4 DOWNTO 2) THEN
            acc_dptr<="00000";
            acc_etat<=sWRITE;
            IF acc_rd_fin2='1' AND acc_src(1 DOWNTO 0)/="00" THEN
              acc_etat<=sTURN;
            END IF;
          ELSE
            acc_dptr<=acc_dptr+1;
          END IF;

        WHEN sTURN =>
          -- Lors de lectures désalignées, il faut un cycle de plus
          -- pour transférer du RAD vers la FIFO.
          acc_etat<=sWRITE;
          
        WHEN sWRITE =>
          IF acc_wseq/=3 THEN
            acc_wseq<=acc_wseq+1;
          END IF;
          IF acc_wseq>=1 THEN
            acc_pw.req<='1';
          END IF;
          IF acc_pr.ack='1' AND acc_pw.req='1' THEN
            acc_pw.a<=acc_pw.a+4;
            acc_pw.burst<=PB_SINGLE;
          END IF;
          
          IF acc_pr.ack='1' AND acc_pw.req='1' AND
            acc_pw.a(4 DOWNTO 2)="111" THEN
            IF (fdst_v(5)='0' OR acc_sec='1') THEN
              acc_etat<=sOISIF;
              acc_pw.req<='0';
            ELSE
              acc_pw.burst<=PB_BURST8;
              acc_sec<='1';
            END IF;
          END IF;
          IF (acc_pr.ack='1' AND acc_pw.req='1') OR acc_wseq<=1 THEN
            acc_dptr<=acc_dptr+1;
          END IF;
          
      END CASE;

      -----------------------------------------------------
      -- Lectures : ACT pendant 8 cycles, pour remplir exactement le buffer
      rd_act_v:='0';
      IF acc_dptr(3 DOWNTO 0)>=('0' & acc_src(4 DOWNTO 2)) AND
        acc_dptr(3 DOWNTO 0)<=(('1' & acc_src(4 DOWNTO 2))-1) THEN
        rd_act_v:='1';
      END IF;
      rd_deb_v:='0';
      IF acc_dptr(3 DOWNTO 0)=('0' & acc_src(4 DOWNTO 2)) THEN
        rd_deb_v:='1';
      END IF;
      rd_fin_v:='0';
      IF acc_dptr(3 DOWNTO 0)=(('1' & acc_src(4 DOWNTO 2))-1) THEN
        rd_fin_v:='1';
      END IF;

      acc_rd_fin2<=rd_fin_v;
      IF acc_pr.dreq='1' THEN
        acc_rd_fin<=rd_fin_v;
      END IF;
      
      -- Ecriture : ACT pendant qu'il y a des données à écrire
      wr_act_v:='0';
      IF acc_dptr(3 DOWNTO 0)>=('0' & acc_dst(4 DOWNTO 2)) AND
        acc_dptr(3 DOWNTO 0)<=fdst_v(5 DOWNTO 2) THEN
        wr_act_v:='1';
      END IF;
      wr_deb_v:='0';
      IF acc_dptr(3 DOWNTO 0)=('0' & acc_dst(4 DOWNTO 2)) THEN
        wr_deb_v:='1';
      END IF;
      wr_fin_v:='0';
      IF acc_dptr(3 DOWNTO 0)=fdst_v(5 DOWNTO 2) THEN
        wr_fin_v:='1';
      END IF;
      
      -----------------------------------------------------
      -- Décalage
      push_v:='0';
      IF acc_etat=sWRITE THEN
        -- Ecritures
        deca_v:=acc_dst(1 DOWNTO 0);
        IF acc_wseq<=1 THEN
          shift_v:=wr_act_v;
          push_v :=wr_act_v;
        ELSE
          shift_v:=acc_pr.ack AND acc_pw.req AND wr_act_v;
          push_v :=acc_pr.ack AND acc_pw.req AND wr_act_v;
        END IF;
        IF wr_act_v='1' THEN
          be_v:="1111";
        ELSE
          be_v:="0000";
        END IF;
        IF wr_deb_v='1'  THEN
          CASE acc_dst(1 DOWNTO 0) IS
            WHEN "00"   => be_v:="1111";
            WHEN "01"   => be_v:="0111";
            WHEN "10"   => be_v:="0011";
            WHEN OTHERS => be_v:="0001";
          END CASE;
        END IF;
        IF wr_fin_v='1'  THEN
          CASE fdst_v(1 DOWNTO 0) IS
            WHEN "11"   => be_v:=be_v AND "1111";
            WHEN "10"   => be_v:=be_v AND "1110";
            WHEN "01"   => be_v:=be_v AND "1100";
            WHEN OTHERS => be_v:=be_v AND "1000";
          END CASE;
        END IF;

      ELSE
        -- Lectures
        deca_v:=NOT (acc_src(1 DOWNTO 0)-1);
        shift_v:=acc_pr.dreq;
        IF acc_src(1 DOWNTO 0)="00" THEN
          push_v:=acc_pr.dreq AND rd_act_v;
        ELSE
          push_v:=acc_pr.dreq AND rd_act_v AND NOT rd_deb_v;
        END IF;
        IF acc_etat=sBOURRE OR (acc_rd_fin='1' AND rd_fin_v='0' AND
                                (acc_pr.dreq='1' OR ibourre_v='1') AND
                                acc_src(1 DOWNTO 0)/="00") THEN
          push_v:='1';
          shift_v:='1';
        END IF;
        be_v:="1111";
        
      END IF;
      
      -----------------------------------------------------
      -- Multiplexeurs
      IF acc_etat=sWRITE THEN
        mux_v:=acc_fifo(7);
      ELSE
        mux_v:=acc_pr.d;
      END IF;
      
      IF shift_v='1' THEN
        acc_rad  <=acc_rad(23 DOWNTO 0) & mux_v;
        acc_berad<=acc_berad(2 DOWNTO 0) & acc_fifobe(31 DOWNTO 28);
      END IF;
      
      IF deca_v="00" THEN
        fifoin_v:=acc_rad(31 DOWNTO 0);
        fifobein_v:=acc_berad(3 DOWNTO 0);
      ELSIF deca_v="01" THEN
        fifoin_v:=acc_rad(39 DOWNTO 8);
        fifobein_v:=acc_berad(4 DOWNTO 1);
      ELSIF deca_v="10" THEN
        fifoin_v:=acc_rad(47 DOWNTO 16);
        fifobein_v:=acc_berad(5 DOWNTO 2);
      ELSE
        fifoin_v:=acc_rad(55 DOWNTO 24);
        fifobein_v:=acc_berad(6 DOWNTO 3);
      END IF;
      
      -----------------------------------------------------
      -- Registre à décalage
      acc_push<=push_v;
      IF acc_etat/=sWRITE THEN
        push_v:=acc_push;
      END IF;
      
      IF push_v='1' THEN
        acc_fifo<=fifoin_v & acc_fifo(0 TO 6);
      END IF;
      IF push_v='1' AND acc_etat=sWRITE THEN
        acc_fifobe<=acc_fifobe(27 DOWNTO 0) & "XXXX";
      END IF;
      
      -----------------------------------------------------
      -- Données de sortie
      acc_pw.dack<='1';
      acc_pw.ah<=ADR_H;
      acc_pw.asi<=ASI;
      acc_pw.cont<='0';

      IF acc_etat=sWRITE THEN
        IF acc_wseq<=1 OR (acc_pr.ack='1' AND acc_pw.req='1') THEN
          IF acc_bfill='1' THEN
            acc_pw.d<=acc_fill & acc_fill & acc_fill & acc_fill;
          ELSE
            acc_pw.d<=fifoin_v;
          END IF;
          acc_be<=be_v;
          acc_pw.be<=acc_be AND fifobein_v;
        END IF;
      ELSE
        acc_pw.be<="1111";
      END IF;

      -----------------------------------------------------
      IF reset_n='0' THEN
        acc_pw.req<='0';
        acc_pw.dack<='1';
        acc_pw.cache<='0';
        acc_pw.lock<='0';
        acc_etat<=sOISIF;
      END IF;
      -----------------------------------------------------
    END IF;
  END PROCESS Accel;
  
  END GENERATE GenAccelProcess;
  
END ARCHITECTURE rtl;

