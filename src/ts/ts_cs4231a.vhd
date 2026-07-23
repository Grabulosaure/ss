--------------------------------------------------------------------------------
-- TEM : TS
-- CS4231A-style audio codec (APC-style DMA playback, Solaris audiocs model)
--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE ieee.math_real.ALL;   -- elaboration-time gain-table computation only

LIBRARY work;
USE work.base_pack.ALL;
USE work.plomb_pack.ALL;
USE work.ts_pack.ALL;
USE work.asi_pack.ALL;

ENTITY ts_cs4231a IS
  GENERIC (
    SYSFREQ : natural := 50_000_000
  );
  PORT (
    sel      : IN  std_logic;
    w        : IN  type_pvc_w;
    r        : OUT type_pvc_r;

    -- DMA memory interface
    pw       : OUT type_plomb_w;
    pr       : IN  type_plomb_r;

    irq      : OUT std_logic;
    sample_l : OUT uv16;
    sample_r : OUT uv16;
    clk      : IN  std_logic;
    reset_n  : IN  std_logic
  );
END ENTITY ts_cs4231a;

ARCHITECTURE rtl OF ts_cs4231a IS

  --------------------------------------------------------------------------
  -- CS4231 core register model
  --------------------------------------------------------------------------
  CONSTANT NREG : natural := 32;
  TYPE reg_array_t IS ARRAY (0 TO NREG-1) OF uv8;

  SIGNAL regs      : reg_array_t := (OTHERS => (OTHERS => '0'));
  SIGNAL index_reg : uv8         := (OTHERS => '0');
  SIGNAL status    : uv8         := (OTHERS => '0');

  -- CS4231 state machine
  SIGNAL iar_init  : std_logic := '1';
  SIGNAL iar_mce   : std_logic := '0';
  SIGNAL iar_trd   : std_logic := '0';
  SIGNAL esi_aci   : std_logic := '0';

  TYPE init_state_t IS (INIT_RESET, INIT_WAIT, IDLE, MCE_SET, AUTO_CAL);
  SIGNAL init_state    : init_state_t := INIT_RESET;
  SIGNAL init_timer    : unsigned(18 DOWNTO 0) := (OTHERS => '0');
  SIGNAL iar_mce_prev  : std_logic := '0';

  CONSTANT RESET_CYCLES : unsigned(18 DOWNTO 0) := to_unsigned(250000, 19);
  CONSTANT CAL_CYCLES   : unsigned(18 DOWNTO 0) := to_unsigned(400000, 19);

  --------------------------------------------------------------------------
  -- APC DMA register model
  --------------------------------------------------------------------------
  SIGNAL dma_csr   : uv32 := (OTHERS => '0');

  -- Next Pointers (programmed by driver)
  SIGNAL dma_pnva  : uv32 := (OTHERS => '0');
  SIGNAL dma_pnc   : uv32 := (OTHERS => '0');

  --------------------------------------------------------------------------
  -- APC CSR bit constants / indices (from audio_4231.h)
  --------------------------------------------------------------------------
  CONSTANT APC_RESET_BIT   : integer := 0;
  CONSTANT PDMA_GO_BIT     : integer := 3;
  CONSTANT APC_P_ABORT_BIT : integer := 7;
  CONSTANT APC_CD_BIT      : integer := 10;
  CONSTANT APC_CX_BIT      : integer := 11;

  CONSTANT APC_PMIE_BIT    : integer := 12; 
  CONSTANT APC_PD_BIT      : integer := 13;
  CONSTANT APC_PM_BIT      : integer := 14;
  CONSTANT APC_PMI_BIT     : integer := 15; 
  CONSTANT APC_EIE_BIT     : integer := 16;
  CONSTANT APC_CIE_BIT     : integer := 17;
  CONSTANT APC_PIE_BIT     : integer := 18; 
  CONSTANT APC_IE_BIT      : integer := 19; 
  CONSTANT APC_EI_BIT      : integer := 20;
  CONSTANT APC_CI_BIT      : integer := 21;
  CONSTANT APC_PI_BIT      : integer := 22; 
  CONSTANT APC_IP_BIT      : integer := 23; 

  --------------------------------------------------------------------------
  -- DMA Playback Engine
  --------------------------------------------------------------------------
  TYPE dma_state_t IS (DMA_IDLE, DMA_READ_REQ, DMA_READ_WAIT, DMA_PROCESS);
  SIGNAL dma_state        : dma_state_t := DMA_IDLE;
  SIGNAL play_active      : std_logic := '0';
  
  SIGNAL current_addr     : uv32 := (OTHERS => '0');
  SIGNAL bytes_remaining  : unsigned(31 DOWNTO 0) := (OTHERS => '0');
  
  -- Sample FIFO.  Depth sets the DMA read-ahead buffer = how long the shared
  -- PLOMB/SDRAM bus can starve this (lowest-priority) master before the codec
  -- underruns.
  CONSTANT FIFO_DEPTH : natural := 64;
  CONSTANT FIFO_AW    : natural := 6;
  TYPE fifo_t IS ARRAY (0 TO FIFO_DEPTH-1) OF uv32;
  SIGNAL sample_fifo : fifo_t := (OTHERS => (OTHERS => '0'));
  SIGNAL fifo_wr_ptr : unsigned(FIFO_AW-1 DOWNTO 0) := (OTHERS => '0');
  SIGNAL fifo_rd_ptr : unsigned(FIFO_AW-1 DOWNTO 0) := (OTHERS => '0');
  SIGNAL fifo_full   : std_logic := '0';
  SIGNAL fifo_empty  : std_logic := '1';

  -- Sample rate: decoded from CS4231 register I8 bits [3:0] (C2SS + DIV).
  -- Codes from audio_4231.h (FS_8000=0x0, FS_5510=0x1, ... FS_6620=0xF);
  -- unused codes 0x8/0xA fall back to 8 kHz.
  TYPE arr_nat16 IS ARRAY(0 TO 15) OF natural;
  CONSTANT RATE_TBL : arr_nat16 :=
    (8000, 5510, 16000, 11025, 27420, 18900, 32000, 22050,
     8000, 37800, 8000, 44100, 48000, 33075, 9600, 6620);
  FUNCTION div_tbl_init RETURN arr_nat16 IS
    VARIABLE v : arr_nat16;
  BEGIN
    FOR i IN 0 TO 15 LOOP
      v(i) := SYSFREQ / RATE_TBL(i);
    END LOOP;
    RETURN v;
  END FUNCTION;
  CONSTANT DIV_TBL : arr_nat16 := div_tbl_init;

  --------------------------------------------------------------------------
  -- Output DAC gain / mute (CS4231 I6 = left, I7 = right; audio_4231.h
  -- LDACO/RDACO).  bits[5:0] = attenuation at 1.5 dB/step (0 = 0 dB, full);
  -- bit 7 = channel mute (LDACO_LDM / RDACO_RDM).  GAIN_TBL(atten) is the
  -- linear multiplier in Q15 (1.0 = 32768), i.e. 10^(-1.5*atten/20).  This is
  -- what makes the Solaris/NetBSD master volume slider and mute audible.
  --------------------------------------------------------------------------
  TYPE gain_tbl_t IS ARRAY(0 TO 63) OF unsigned(15 DOWNTO 0);
  FUNCTION gain_tbl_init RETURN gain_tbl_t IS
    VARIABLE t : gain_tbl_t;
    VARIABLE g : real;
  BEGIN
    FOR n IN 0 TO 63 LOOP
      g := EXP(real(n) * (-0.075) * MATH_LOG_OF_10);   -- 10^(-1.5*n/20)
      t(n) := to_unsigned(integer(round(g * 32768.0)), 16);
    END LOOP;
    RETURN t;
  END FUNCTION;
  CONSTANT GAIN_TBL : gain_tbl_t := gain_tbl_init;

  SIGNAL sample_rate_div : unsigned(15 DOWNTO 0) := to_unsigned(SYSFREQ / 8000, 16);
  SIGNAL sample_cnt      : unsigned(15 DOWNTO 0) := (OTHERS => '0');
  SIGNAL sample_tick     : std_logic := '0';
  
  -- Error tracking
  SIGNAL dma_error : std_logic := '0';
  
  -- Watchdog for a stalled DMA read.  On expiry the engine ABANDONS and
  -- retries the access -- a slow shared bus is not a fault, so it raises no
  -- EI and does not halt (see the DMA_READ_REQ / DMA_READ_WAIT timeout paths).
  -- Sized to swallow IOMMU TLB misses + PTE fetches with wide margin.
  SIGNAL req_timeout_cnt : unsigned(17 DOWNTO 0) := (OTHERS => '0');
  CONSTANT REQ_TIMEOUT_LIMIT : unsigned(17 DOWNTO 0) := to_unsigned(200000, 18);

  -- Audio format
  SIGNAL is_stereo    : std_logic := '0';
  SIGNAL is_16bit     : std_logic := '0';
  SIGNAL is_mulaw     : std_logic := '0';
  SIGNAL is_alaw      : std_logic := '0';
  SIGNAL is_16le      : std_logic := '0';   -- 16-bit little-endian

  --------------------------------------------------------------------------
  -- Internal signals
  --------------------------------------------------------------------------
  SIGNAL sample_l_i      : uv16 := (OTHERS => '0');
  SIGNAL sample_r_i      : uv16 := (OTHERS => '0');
  SIGNAL ack_i           : std_logic := '0';
  SIGNAL rdata           : uv32 := (OTHERS => '0');
  SIGNAL pw_i            : type_plomb_w;
  SIGNAL fifo_reset_req  : std_logic := '0';
  SIGNAL pipeline_empty_prev : std_logic := '1';

  FUNCTION extract_byte(dw : uv32; be : uv4) RETURN uv8 IS
    VARIABLE v : uv8;   -- normalises slice bounds to (7 downto 0)
  BEGIN
    IF be(0) = '1' THEN
      v := dw(31 DOWNTO 24);
    ELSIF be(1) = '1' THEN
      v := dw(23 DOWNTO 16);
    ELSIF be(2) = '1' THEN
      v := dw(15 DOWNTO 8);
    ELSE
      v := dw(7 DOWNTO 0);
    END IF;
    RETURN v;
  END FUNCTION;

  FUNCTION ulaw_expand(u_val : uv8) RETURN uv16 IS
    VARIABLE inv    : uv8;
    VARIABLE exp    : integer RANGE 0 TO 7;
    VARIABLE mant   : unsigned(3 DOWNTO 0);
    VARIABLE sample : unsigned(14 DOWNTO 0);
    VARIABLE res    : uv16;
  BEGIN
    inv  := NOT u_val;
    exp  := to_integer(unsigned(inv(6 DOWNTO 4)));
    mant := unsigned(inv(3 DOWNTO 0));
    -- ITU G.711: linear = ((mant*8 + 0x84) << exp) - 0x84, full scale
    -- +/-32124.  ('1' & mant & "100" = mant*8 + 0x84.).
    sample := shift_left(resize('1' & mant & unsigned'("100"), 15), exp);
    sample := sample - 132;
    IF inv(7) = '1' THEN
       res := uv16(0 - signed(resize(sample, 16)));
    ELSE
       res := uv16(resize(sample, 16));
    END IF;
    RETURN res;
  END FUNCTION;

  -- ITU G.711 A-law expand (Sun g711 alaw2linear), full scale +/-32256.
  FUNCTION alaw_expand(a_val : uv8) RETURN uv16 IS
    VARIABLE a    : uv8;
    VARIABLE seg  : integer RANGE 0 TO 7;
    VARIABLE t    : unsigned(15 DOWNTO 0);
    VARIABLE res  : uv16;
  BEGIN
    a   := a_val XOR x"55";
    seg := to_integer(unsigned(a(6 DOWNTO 4)));
    t   := resize(unsigned(a(3 DOWNTO 0)) & "0000", 16);
    IF seg = 0 THEN
      t := t + 8;
    ELSIF seg = 1 THEN
      t := t + 16#108#;
    ELSE
      t := t + 16#108#;
      t := shift_left(t, seg - 1);
    END IF;
    IF a(7) = '1' THEN                            -- A-law: sign bit set = +
      res := uv16(resize(signed(t), 16));
    ELSE
      res := uv16(0 - signed(t));
    END IF;
    RETURN res;
  END FUNCTION;

BEGIN

  --------------------------------------------------------------------------
  -- Top-level connections
  --------------------------------------------------------------------------
  irq      <= dma_csr(APC_IP_BIT);
  r.dr     <= rdata;
  r.ack    <= ack_i;
  pw       <= pw_i;

  fifo_empty <= '1' WHEN fifo_wr_ptr = fifo_rd_ptr ELSE '0';
  fifo_full  <= '1' WHEN (fifo_wr_ptr + 1) = fifo_rd_ptr ELSE '0';

  --------------------------------------------------------------------------
  -- Output DAC gain / mute.  Applies the CS4231 I6 (left) / I7 (right)
  -- output-control registers to the decoded sample stream: bit 7 mutes the
  -- channel, bits[5:0] attenuate via GAIN_TBL (Q15 multiply).  Registered so
  -- the multiply sits between two flops; volume/mute changes take effect on
  -- the next clock (imperceptible at audio rates).
  --------------------------------------------------------------------------
  Output_Gain: PROCESS(clk)
    VARIABLE pl, pr : signed(32 DOWNTO 0);
  BEGIN
    IF rising_edge(clk) THEN
      IF reset_n = '0' THEN
        sample_l <= (OTHERS => '0');
        sample_r <= (OTHERS => '0');
      ELSE
        IF regs(6)(7) = '1' THEN            -- LDACO_LDM: left mute
          sample_l <= (OTHERS => '0');
        ELSE
          pl := signed(sample_l_i) *
                signed('0' & GAIN_TBL(to_integer(regs(6)(5 DOWNTO 0))));
          sample_l <= unsigned(resize(shift_right(pl, 15), 16));
        END IF;
        IF regs(7)(7) = '1' THEN            -- RDACO_RDM: right mute
          sample_r <= (OTHERS => '0');
        ELSE
          pr := signed(sample_r_i) *
                signed('0' & GAIN_TBL(to_integer(regs(7)(5 DOWNTO 0))));
          sample_r <= unsigned(resize(shift_right(pr, 15), 16));
        END IF;
      END IF;
    END IF;
  END PROCESS Output_Gain;

  --------------------------------------------------------------------------
  -- Sample rate generator
  -- The codec consumes samples whenever PEN (I9 bit 0) is set, independent
  -- of the APC DMA GO bit: on the real hardware the codec keeps draining its
  -- FIFO after the driver pauses DMA, which is what makes ESI.PUR latch.
  -- apc_p_pause()/apc_p_stop() poll PUR and would spin 100 ms without this.
  --------------------------------------------------------------------------
  PROCESS(clk)
  BEGIN
    IF rising_edge(clk) THEN
      sample_tick <= '0';
      IF reset_n = '0' THEN
        sample_cnt  <= (OTHERS => '0');
      ELSE
        IF sample_cnt >= sample_rate_div - 1 THEN
          sample_cnt <= (OTHERS => '0');
          IF regs(9)(0) = '1' THEN      -- PEN
            sample_tick <= '1';
          END IF;
        ELSE
          sample_cnt <= sample_cnt + 1;
        END IF;
      END IF;
    END IF;
  END PROCESS;

  --------------------------------------------------------------------------
  -- Sample Output Engine
  --------------------------------------------------------------------------
  PROCESS(clk)
    VARIABLE sample_data : uv32;
  BEGIN
    IF rising_edge(clk) THEN
      IF reset_n = '0' THEN
        sample_l_i   <= (OTHERS => '0');
        sample_r_i   <= (OTHERS => '0');
        fifo_rd_ptr  <= (OTHERS => '0');
      ELSE
        IF fifo_reset_req = '1' THEN
          fifo_rd_ptr <= (OTHERS => '0');
        END IF;

        IF (sample_tick = '1') AND (fifo_empty = '0') THEN
          sample_data := sample_fifo(to_integer(fifo_rd_ptr));
          fifo_rd_ptr <= fifo_rd_ptr + 1;
          sample_l_i  <= sample_data(15 DOWNTO 0);
          sample_r_i  <= sample_data(31 DOWNTO 16);
        END IF;
      END IF;
    END IF;
  END PROCESS;

  --------------------------------------------------------------------------
  -- Unified DMA Controller & Register Master
  --------------------------------------------------------------------------
  PROCESS(clk)
    VARIABLE next_addr    : uv32;
    VARIABLE next_bytes   : unsigned(31 DOWNTO 0);
    VARIABLE fetched      : uv32;
    VARIABLE L8           : uv8;
    VARIABLE L16, R16     : uv16;
    VARIABLE bytes_used   : unsigned(2 DOWNTO 0);
    VARIABLE bytes_used32 : unsigned(31 DOWNTO 0);
    
    VARIABLE word_index    : integer RANGE 0 TO 15;
    VARIABLE is_read       : boolean;
    VARIABLE is_write      : boolean;
    VARIABLE byte_val      : uv8;
    VARIABLE idx           : integer;

    VARIABLE new_dma_csr   : uv32;
    VARIABLE csr_write_val : uv32;
    VARIABLE iar_val       : uv8;
    VARIABLE mce_falling   : std_logic;

    VARIABLE v_buf_finished : boolean;

    VARIABLE pipeline_empty : std_logic;
    VARIABLE pi_next        : std_logic;

    -- Same-cycle shadow of dma_error so W1C clears take effect before the
    -- EI re-assertion check in section 9 (SIGNAL assignments are next-cycle).
    VARIABLE v_dma_error    : std_logic;

  BEGIN
    IF rising_edge(clk) THEN
      IF reset_n = '0' THEN
        -- CS4231
        regs        <= (OTHERS => (OTHERS => '0'));
        index_reg   <= (OTHERS => '0');
        status      <= (OTHERS => '0');
        iar_init    <= '1';
        iar_mce     <= '0';
        iar_mce_prev<= '0';
        iar_trd     <= '0';
        esi_aci     <= '0';
        init_timer  <= (OTHERS => '0');
        init_state  <= INIT_RESET;

        is_stereo      <= '0';
        is_16bit       <= '0';
        is_mulaw       <= '0';
        is_alaw        <= '0';
        is_16le        <= '0';

        -- DMA / APC
        dma_csr   <= (OTHERS => '0');
        dma_pnva  <= (OTHERS => '0');
        dma_pnc   <= (OTHERS => '0');
        
        dma_state       <= DMA_IDLE;
        play_active     <= '0';
        current_addr    <= (OTHERS => '0');
        bytes_remaining <= (OTHERS => '0');
        fifo_reset_req  <= '0';
        fifo_wr_ptr     <= (OTHERS => '0');
        pipeline_empty_prev <= '1';
        
        dma_error       <= '0';
        req_timeout_cnt <= (OTHERS => '0');
        
        rdata  <= (OTHERS => '0');
        ack_i  <= '0';

        pw_i.req   <= '0';
        pw_i.dack  <= '1';
        pw_i.ah    <= x"F";
        pw_i.be    <= "0000";
        pw_i.mode  <= PB_MODE_RD;
        pw_i.burst <= PB_SINGLE;
        pw_i.cache <= '0';
        pw_i.lock  <= '0';
        pw_i.asi   <= ASI_SUPER_DATA;
        pw_i.cont  <= '0';
        pw_i.d     <= (OTHERS => '0');
        pw_i.a     <= (OTHERS => '0');

      ELSE
        -- defaults each cycle
        ack_i          <= '0';
        fifo_reset_req <= '0';

        pw_i.ah    <= x"F";
        pw_i.be    <= "1111";
        pw_i.mode  <= PB_MODE_RD;
        pw_i.burst <= PB_SINGLE;
        pw_i.cache <= '0';
        pw_i.lock  <= '0';
        pw_i.asi   <= ASI_SUPER_DATA;
        pw_i.cont  <= '0';
        pw_i.d     <= (OTHERS => '0');
        pw_i.dack  <= '1';
        pw_i.req   <= '0';
        pw_i.a     <= (OTHERS => '0');

        next_addr   := current_addr;
        next_bytes  := bytes_remaining;
        new_dma_csr := dma_csr;
        v_buf_finished := false;
        v_dma_error := dma_error;

        --------------------------------------------------------------------
        -- 1. CS4231 Init State Machine
        --------------------------------------------------------------------
        mce_falling  := iar_mce_prev AND NOT iar_mce;
        iar_mce_prev <= iar_mce;

        CASE init_state IS
          WHEN INIT_RESET =>
            iar_init   <= '1';
            esi_aci    <= '0';
            init_timer <= init_timer + 1;
            IF init_timer >= RESET_CYCLES THEN
              init_state  <= INIT_WAIT;
              init_timer  <= (OTHERS => '0');
            END IF;

          WHEN INIT_WAIT =>
            iar_init <= '0';
            esi_aci  <= '0';
            IF iar_mce = '1' THEN
              init_state <= MCE_SET;
            END IF;

          WHEN IDLE =>
            iar_init <= '0';
            esi_aci  <= '0';
            IF iar_mce = '1' THEN
              init_state <= MCE_SET;
            END IF;

          WHEN MCE_SET =>
            iar_init <= '0';
            esi_aci  <= '0';
            IF mce_falling = '1' THEN
              init_state  <= AUTO_CAL;
              init_timer  <= (OTHERS => '0');
            END IF;

          WHEN AUTO_CAL =>
            -- Real CS4231: autocalibration asserts only ACI (I11 bit 5);
            -- INIT (IAR bit 7) stays low and the register interface remains
            -- fully usable.
            iar_init   <= '0';
            esi_aci    <= '1';
            init_timer <= init_timer + 1;
            IF init_timer >= CAL_CYCLES THEN
              init_state  <= IDLE;
              iar_init    <= '0';
              esi_aci     <= '0';
              init_timer  <= (OTHERS => '0');
            END IF;
        END CASE;

        --------------------------------------------------------------------
        -- 2. Register Access Decode
        --------------------------------------------------------------------
        word_index := to_integer(unsigned(w.a(5 DOWNTO 2)));
        is_write   := (w.req = '1' AND w.wr = '1' AND sel = '1');
        is_read    := (w.req = '1' AND w.wr = '0' AND sel = '1');

        IF (w.req = '1' AND sel = '1') THEN
          ack_i <= '1';
        END IF;

        --------------------------------------------------------------------
        -- 3. Reads
        --------------------------------------------------------------------
        IF is_read THEN
          IF iar_init = '1' AND word_index <= 3 THEN
            rdata <= x"80808080";
          ELSE
            CASE word_index IS
              WHEN 0 =>  -- IAR
                iar_val := index_reg AND x"1F";
                IF iar_init = '1' THEN iar_val := iar_val OR x"80"; END IF;
                IF iar_mce  = '1' THEN iar_val := iar_val OR x"40"; END IF;
                IF iar_trd  = '1' THEN iar_val := iar_val OR x"20"; END IF;
                rdata <= iar_val & iar_val & iar_val & iar_val;

              WHEN 1 =>  -- IDR
                idx := to_integer(index_reg AND x"1F");
                IF idx = 16#19# THEN
                  byte_val := x"A0";
                ELSIF idx = 16#0B# THEN
                  byte_val := regs(idx);
                  IF esi_aci = '1' THEN
                    byte_val := byte_val OR x"20"; -- ACI
                  END IF;
                ELSE
                  IF idx < NREG THEN
                    byte_val := regs(idx);
                  ELSE
                    byte_val := x"00";
                  END IF;
                END IF;
                rdata <= byte_val & byte_val & byte_val & byte_val;

              WHEN 2 =>  -- codec STATUS
                byte_val := status;
                IF play_active = '1' THEN
                  byte_val := byte_val OR x"02";
                END IF;
                rdata <= byte_val & byte_val & byte_val & byte_val;
                -- CS4231 behavior: reading STATUS clears latched ESI underrun.
                regs(11)(6) <= '0';

              WHEN 4 =>  -- DMACSR
                rdata <= x"7E" & new_dma_csr(23 DOWNTO 0);

              WHEN 12 => rdata <= current_addr;                  -- DMAPVA (live)
              WHEN 13 => rdata <= uv32(bytes_remaining);         -- DMAPVC (live)
              WHEN 14 => rdata <= dma_pnva;                      -- DMAPNVA
              WHEN 15 => rdata <= dma_pnc;                       -- DMAPNC

              WHEN OTHERS =>
                rdata <= x"00000000";
            END CASE;
          END IF;
        END IF;

        --------------------------------------------------------------------
        -- 4. Writes (CS4231 regs, DMACSR, DMAP* regs)
        --------------------------------------------------------------------
        IF is_write THEN
          byte_val := extract_byte(w.dw, w.be);

          CASE word_index IS
            ------------------------------------------------------------------
            -- CS4231 IAR
            ------------------------------------------------------------------
            WHEN 0 =>
              index_reg <= byte_val AND x"1F";

              IF (byte_val AND x"40") /= x"00" THEN
                iar_mce <= '1';
              ELSE
                iar_mce <= '0';
              END IF;

              IF (byte_val AND x"20") /= x"00" THEN
                iar_trd <= '1';
              ELSE
                iar_trd <= '0';
              END IF;

            ------------------------------------------------------------------
            -- CS4231 IDR
            ------------------------------------------------------------------
            WHEN 1 =>
              IF iar_init = '0' THEN
                idx := to_integer(index_reg AND x"1F");
                IF idx < NREG AND idx /= 16#19# THEN
                  regs(idx) <= byte_val;

                  IF idx = 8 THEN  -- playback format (FSDF, I8)
                    is_stereo <= byte_val(4);   -- PDF_STEREO
                    -- Decode the 3-bit encoding field I8[7:5] explicitly.
                    -- The old is_mulaw<=I8(5) heuristic mis-routed A-law
                    -- (011) and ADPCM4 (101) through the u-law path.
                    is_16bit <= '0'; is_mulaw <= '0';
                    is_alaw  <= '0'; is_16le  <= '0';
                    CASE byte_val(7 DOWNTO 5) IS
                      WHEN "000" => NULL;                    -- LINEAR8 unsigned
                      WHEN "001" => is_mulaw <= '1';         -- ULAW8
                      WHEN "010" => is_16bit <= '1'; is_16le <= '1'; -- LIN16 LE
                      WHEN "011" => is_alaw  <= '1';         -- ALAW8
                      WHEN "110" => is_16bit <= '1';         -- LIN16 BE (native)
                      WHEN OTHERS => NULL;  -- ADPCM4(101)/reserved: LINEAR8 fallback
                    END CASE;
                    sample_rate_div <= to_unsigned(
                      DIV_TBL(to_integer(byte_val(3 DOWNTO 0))), 16);
                  END IF;
                END IF;
              END IF;

            ------------------------------------------------------------------
            -- CS4231 STATUS (W1C)
            ------------------------------------------------------------------
            WHEN 2 =>
              status <= status AND NOT byte_val;

            ------------------------------------------------------------------
            -- DMACSR (APC-style; PI/PMI/EI/CI are write-1-to-clear)
            ------------------------------------------------------------------
            WHEN 4 =>
              IF w.be = "1111" THEN
                csr_write_val := w.dw;

                -- Start from existing CSR
                new_dma_csr := dma_csr;

                -- Per-bit semantics:
                --  * PI/PMI/EI/CI are write-1-to-clear
                --  * PD/PM/CD/CX/IP are derived, ignore writes
                --  * All other bits (control) tracked directly from software
                FOR i IN 0 TO 23 LOOP
                  IF (i = APC_PD_BIT) OR
                     (i = APC_PM_BIT) OR
                     (i = APC_CD_BIT) OR
                     (i = APC_CX_BIT) OR
                     (i = APC_IP_BIT) THEN
                    -- derived fields, ignore direct writes
                    NULL;
                  ELSIF (i = APC_PI_BIT) OR
                        (i = APC_PMI_BIT) OR
                        (i = APC_EI_BIT) OR
                        (i = APC_CI_BIT) THEN
                    -- write-1-to-clear for interrupt causes
                    IF csr_write_val(i) = '1' THEN
                      new_dma_csr(i) := '0';
                    ELSE
                      new_dma_csr(i) := dma_csr(i);
                    END IF;
                  ELSE
                    -- normal read/write
                    new_dma_csr(i) := csr_write_val(i);
                  END IF;
                END LOOP;

                -- If software writes 1 to EI (W1C), drop the latched error
                -- so the interrupt line can deassert.
                -- v_dma_error is updated immediately so section 9 sees the
                -- cleared value in the same cycle (dma_error SIGNAL would not
                -- update until the next clock edge, causing EI to be
                -- re-asserted in section 9 despite the W1C write here).
                IF (dma_error = '1') AND
                   (csr_write_val(APC_EI_BIT) = '1') THEN
                  dma_error   <= '0';
                  v_dma_error := '0';
                END IF;
              END IF;

            ------------------------------------------------------------------
            -- DMAPVA / DMAPVC / DMAPNVA / DMAPNC
            ------------------------------------------------------------------
            WHEN 12 =>
              IF w.be = "1111" THEN
                next_addr := w.dw;
              END IF;

            WHEN 13 =>
              IF w.be = "1111" THEN
                next_bytes := unsigned(w.dw);
              END IF;

            WHEN 14 =>
              IF w.be = "1111" THEN
                dma_pnva <= w.dw;
              END IF;

            WHEN 15 =>
              IF w.be = "1111" THEN
                dma_pnc <= w.dw;
              END IF;

            WHEN OTHERS =>
              NULL;
          END CASE;
        END IF;

        --------------------------------------------------------------------
        -- 5. Auto-Promotion (PNVA/PNC -> live when current finished)
        --------------------------------------------------------------------
        IF (next_bytes = 0) THEN
          IF (dma_pnc /= x"00000000") THEN
            next_addr      := dma_pnva;
            next_bytes     := unsigned(dma_pnc);
            dma_pnc        <= (OTHERS => '0');
          END IF;
        END IF;

        --------------------------------------------------------------------
        -- 5b. Playback abort / pause (bit 7).  Flush the play pipe so PM /
        -- pipe-empty asserts for the driver's drain-poll.
        --------------------------------------------------------------------
        IF (new_dma_csr(APC_P_ABORT_BIT) = '1') AND
           (dma_csr(APC_P_ABORT_BIT) = '0') THEN
          next_bytes     := (OTHERS => '0');
          dma_pnc        <= (OTHERS => '0');
          fifo_reset_req <= '1';
          fifo_wr_ptr    <= (OTHERS => '0');
        END IF;

        --------------------------------------------------------------------
        -- 6. Playback Control
        -- DMA prefetch runs on PDMA_GO alone (real APC fills its pipe before
        -- the driver enables the codec).  The codec side (sample ticks, PUR)
        -- is gated by PEN in the sample-rate process.  
        --------------------------------------------------------------------
        play_active <= new_dma_csr(PDMA_GO_BIT);

        --------------------------------------------------------------------
        -- 7. DMA Engine
        --------------------------------------------------------------------
        CASE dma_state IS
          WHEN DMA_IDLE =>
            req_timeout_cnt <= (OTHERS => '0');
            -- Do not retry while a bus error is pending; software must
            -- acknowledge the error (W1C EI in DMACSR) before DMA resumes.
            IF (play_active = '1') AND (next_bytes > 0) AND
               (fifo_full = '0') AND (v_dma_error = '0') AND
               (new_dma_csr(APC_P_ABORT_BIT) = '0') THEN
              dma_state <= DMA_READ_REQ;
            END IF;

          WHEN DMA_READ_REQ =>
            pw_i.a   <= next_addr(31 DOWNTO 2) & "00";
            pw_i.req <= '1';
            IF pr.ack = '1' THEN
              pw_i.req  <= '0';
              dma_state <= DMA_READ_WAIT;
              req_timeout_cnt <= (OTHERS => '0');
            ELSIF req_timeout_cnt >= REQ_TIMEOUT_LIMIT THEN
              -- Bus request timed out (e.g. IOMMU TLB warmup took too long).
              -- Do NOT set dma_error here: a slow IOMMU miss is not a bus
              -- error, and treating it as one would trigger spurious EI
              -- interrupts and IRQ storms.  Just silently return to IDLE;
              -- DMA will retry on the next FIFO-empty slot.
              pw_i.req  <= '0';
              dma_state <= DMA_IDLE;
              req_timeout_cnt <= (OTHERS => '0');
            ELSE
              req_timeout_cnt <= req_timeout_cnt + 1;
            END IF;

          WHEN DMA_READ_WAIT =>
            pw_i.req <= '0';
            IF pr.dreq = '1' THEN
              req_timeout_cnt <= (OTHERS => '0');
              IF new_dma_csr(APC_P_ABORT_BIT) = '1' THEN
                -- Abort in progress: consume and discard the response.
                dma_state <= DMA_PROCESS;
              ELSIF pr.code /= PB_OK THEN
                -- Genuine bus error (bad translation, unmapped page, etc.).
                dma_error   <= '1';   -- latches EI once; cleared by W1C ack
                v_dma_error := '1';
                dma_state   <= DMA_PROCESS;
              ELSE
                fetched := pr.d;

              IF is_16bit = '1' THEN
                IF is_stereo = '1' THEN
                  L16        := fetched(31 DOWNTO 16);
                  R16        := fetched(15 DOWNTO 0);
                  bytes_used := "100"; -- 4 bytes
                ELSE
                  IF next_addr(1) = '0' THEN
                    L16 := fetched(31 DOWNTO 16);
                  ELSE
                    L16 := fetched(15 DOWNTO 0);
                  END IF;
                  R16        := L16;
                  bytes_used := "010"; -- 2 bytes
                END IF;
                -- The samples were extracted big-endian (byte at the lower
                -- address = MSB).  For PDF_LINEAR16LE swap the two bytes of
                -- each 16-bit sample.
                IF is_16le = '1' THEN
                  L16 := L16(7 DOWNTO 0) & L16(15 DOWNTO 8);
                  R16 := R16(7 DOWNTO 0) & R16(15 DOWNTO 8);
                END IF;
              ELSE
                CASE next_addr(1 DOWNTO 0) IS
                  WHEN "00" => L8 := fetched(31 DOWNTO 24);
                  WHEN "01" => L8 := fetched(23 DOWNTO 16);
                  WHEN "10" => L8 := fetched(15 DOWNTO 8);
                  WHEN OTHERS => L8 := fetched(7 DOWNTO 0);
                END CASE;

                IF is_mulaw = '1' THEN
                  L16 := ulaw_expand(L8);
                ELSIF is_alaw = '1' THEN
                  L16 := alaw_expand(L8);
                ELSE
                  -- PDF_LINEAR8 is unsigned offset-binary (0x80 = zero):
                  -- flip the MSB to get signed, replicate the byte into
                  -- the low bits for full-scale span.
                  L16 := (L8 XOR x"80") & L8;
                END IF;

                R16        := L16;
                bytes_used := "001"; -- 1 byte
              END IF;

              IF fifo_full = '0' THEN
                sample_fifo(to_integer(fifo_wr_ptr)) <= R16 & L16;
                fifo_wr_ptr <= fifo_wr_ptr + 1;
              END IF;

              bytes_used32 := to_unsigned(to_integer(bytes_used), 32);
              next_addr    := next_addr + bytes_used32;

              IF next_bytes > bytes_used32 THEN
                next_bytes := next_bytes - bytes_used32;
              ELSE
                next_bytes := (OTHERS => '0');
                v_buf_finished := true;
              END IF;

              dma_state <= DMA_PROCESS;
              END IF;  -- Error check
            ELSIF req_timeout_cnt >= REQ_TIMEOUT_LIMIT THEN
              -- Response delayed far beyond expectation (extreme bus
              -- contention).  Abandon THIS read and retry the same address
              dma_state       <= DMA_IDLE;
              req_timeout_cnt <= (OTHERS => '0');
            ELSE
              req_timeout_cnt <= req_timeout_cnt + 1;
            END IF;

          WHEN DMA_PROCESS =>
            dma_state <= DMA_IDLE;
        END CASE;

        --------------------------------------------------------------------
        -- 8. Pipe Empty / Drained Status (PM/PD)
        --------------------------------------------------------------------
        IF (next_bytes = 0) AND (dma_pnc = x"00000000") AND (fifo_empty = '1') THEN
          pipeline_empty := '1';
        ELSE
          pipeline_empty := '0';
        END IF;

        -- PD (Playback Next VA dirty) should reflect that the PN registers
        -- are free for software to reload, independent of pipe empty.
        -- Set when no pending buffer is queued; clear once SW programs PN*.
        IF dma_pnc = x"00000000" THEN
          new_dma_csr(APC_PD_BIT) := '1';
        ELSE
          new_dma_csr(APC_PD_BIT) := '0';
        END IF;

        -- PM (Play pipe empty) only when both current and pending are empty
        -- and the output FIFO has drained.
        IF pipeline_empty = '1' THEN
          new_dma_csr(APC_PM_BIT) := '1';
        ELSE
          new_dma_csr(APC_PM_BIT) := '0';
        END IF;

        -- Capture engine is not implemented, which means its next-VA
        -- registers are always free and its pipe is always empty.  The
        -- Solaris driver polls CD before starting record (apc_r_start) and
        -- CX after aborting it (apc_r_stop / apc_intr); leaving these at 0
        -- made every record-side call spin for the full 100 ms
        -- CS4231_TIMEOUT with interrupts effectively stalled.
        new_dma_csr(APC_CD_BIT) := '1';
        new_dma_csr(APC_CX_BIT) := '1';

        --------------------------------------------------------------------
        -- 9. Interrupt Cause bits (PI / PMI / EI / CI) and Global (IP)
        --------------------------------------------------------------------
        -- PI is latched: set on events, cleared only when SW writes 1 (W1C).
        pi_next := new_dma_csr(APC_PI_BIT);
        -- Generate PI at playback terminal-count boundaries.
        IF v_buf_finished = true THEN
          pi_next := '1';
        END IF;
        new_dma_csr(APC_PI_BIT) := pi_next;
        -- PMI is latched when the playback pipeline drains (PM 0->1 transition).
        -- It stays set until software acknowledges DMACSR (W1C), matching APC.
        -- Not latched while P_ABORT is flushing the pipe: the driver aborts
        -- with interrupts intentionally left enabled in the ISR shutdown path.
        IF (new_dma_csr(PDMA_GO_BIT) = '1') AND
           (regs(9)(0) = '1') AND
           (new_dma_csr(APC_P_ABORT_BIT) = '0') AND
           (pipeline_empty_prev = '0') AND
           (pipeline_empty = '1') THEN
          new_dma_csr(APC_PMI_BIT) := '1';
        END IF;
        
        -- Set EI (error interrupt) if DMA encountered a bus error.
        -- Use v_dma_error (VARIABLE) so that a W1C clear in section 4 this
        -- same cycle is visible here; the dma_error SIGNAL would still read
        -- '1' until the next clock edge, causing EI to be re-asserted and
        -- producing an IRQ storm.
        IF v_dma_error = '1' THEN
          new_dma_csr(APC_EI_BIT) := '1';
        END IF;

        -- CI is not currently asserted from HW in this model.

        -- Global interrupt pending (IP) derived only from causes+enables
        -- If EI is set (bus error), do NOT set IP unless EIE is enabled
        IF (new_dma_csr(APC_IE_BIT) = '1') AND
           ( (new_dma_csr(APC_PI_BIT)  = '1' AND new_dma_csr(APC_PIE_BIT)  = '1') OR
             (new_dma_csr(APC_CI_BIT)  = '1' AND new_dma_csr(APC_CIE_BIT)  = '1') OR
             (new_dma_csr(APC_EI_BIT)  = '1' AND new_dma_csr(APC_EIE_BIT)  = '1') OR
             (new_dma_csr(APC_PMI_BIT) = '1' AND new_dma_csr(APC_PMIE_BIT) = '1') ) THEN
          new_dma_csr(APC_IP_BIT) := '1';
        ELSE
          new_dma_csr(APC_IP_BIT) := '0';
        END IF;

        --------------------------------------------------------------------
        -- 10. CS4231 ESI.PUR (Playback underrun)
        -- sample_tick already implies PEN=1; underrun happens whenever the
        -- codec wants a sample and the FIFO is dry, regardless of DMA GO
        -- (this is what apc_p_pause/apc_p_stop poll for after clearing GO).
        --------------------------------------------------------------------
        IF (sample_tick = '1') AND (fifo_empty = '1') THEN
          regs(11)(6) <= '1';  -- PUR bit in ESI (I11)
        END IF;

        --------------------------------------------------------------------
        -- 11. Soft Reset (APC_RESET_BIT)
        --------------------------------------------------------------------
        IF new_dma_csr(APC_RESET_BIT) = '1' THEN
          -- Reset DMA state
          new_dma_csr        := (OTHERS => '0');
          dma_state          <= DMA_IDLE;
          play_active        <= '0';
          fifo_reset_req     <= '1';
          fifo_wr_ptr        <= (OTHERS => '0');
          dma_error          <= '0';
          v_dma_error        := '0';
          req_timeout_cnt    <= (OTHERS => '0');
          next_addr          := (OTHERS => '0');
          next_bytes         := (OTHERS => '0');
          dma_pnva           <= (OTHERS => '0');
          dma_pnc            <= (OTHERS => '0');
          pipeline_empty     := '1';
        END IF;

        --------------------------------------------------------------------
        -- 12. Commit live counters and CSR, update FIFO edge detector
        --------------------------------------------------------------------
        current_addr    <= next_addr;
        bytes_remaining <= next_bytes;
        dma_csr         <= new_dma_csr;
        pipeline_empty_prev <= pipeline_empty;
      END IF;
    END IF;
  END PROCESS;

END ARCHITECTURE rtl;
