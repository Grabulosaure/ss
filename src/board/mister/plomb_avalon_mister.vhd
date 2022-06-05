--------------------------------------------------------------------------------
-- TEM : Cyclone V
-- Interface PLOMB -> Avalon_MM
--------------------------------------------------------------------------------
-- DO 4/2015
--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.plomb_pack.ALL;

ENTITY plomb_avalon64 IS
  GENERIC (
    RAMSIZE : natural :=0;
    HIMEM   : uv32 := x"00000000";
    N       : natural); -- Adresses
  PORT (
    -- PLOMB
    pw : IN  type_plomb_w;
    pr : OUT type_plomb_r;
    
    -- Avalon
    avl_waitrequest    : IN    std_logic;
    avl_readdata       : IN    std_logic_vector(63 DOWNTO 0);
    avl_readdatavalid  : IN    std_logic;
    avl_burstbegin     : OUT   std_logic;
    avl_burstcount     : OUT   std_logic_vector(7 DOWNTO 0);
    avl_writedata      : OUT   std_logic_vector(63 DOWNTO 0);
    avl_address        : OUT   std_logic_vector(N-4 DOWNTO 0);
    avl_write          : OUT   std_logic;
    avl_read           : OUT   std_logic;
    avl_byteenable     : OUT   std_logic_vector(7 DOWNTO 0);
    
    -- Global
    clk      : IN std_logic;
    reset_n  : IN std_logic
    );
END ENTITY plomb_avalon64;

-- A[31:3] -> avl_a[28:0]
-- A[2]    -> avl_hilo

--##############################################################################

ARCHITECTURE rtl OF plomb_avalon64 IS

  SIGNAL ack_c : std_logic;

  TYPE enum_state IS (sIDLE,sREAD,sWRITE);
  SIGNAL state,state_c : enum_state;
  SIGNAL wrack_mem,wrack_mem_c : std_logic;
  
  SIGNAL mem_be,mem_be_c : uv4;
  SIGNAL mem_d,mem_d_c: uv32;
  SIGNAL burstcpt,burstcpt_c : natural RANGE 0 TO PB_BLEN_MAX+1;
  SIGNAL burstlen,burstlen_c : natural RANGE 0 TO PB_BLEN_MAX+1;
  SIGNAL avl_address_c,avl_address_i :  std_logic_vector(N-4 DOWNTO 0);
  SIGNAL avl_burstcount_c,avl_burstcount_i : std_logic_vector(7 DOWNTO 0);
  
  ---------------------------------
  CONSTANT PROF : natural := 32;

  SIGNAL full         : std_logic;
  
  SIGNAL fifo_write   : unsigned(0 TO PROF-1);
  SIGNAL fifo_hilo    : unsigned(0 TO PROF-1);
  SIGNAL fifo_zone    : unsigned(0 TO PROF-1);
  SIGNAL fifo_dbl     : unsigned(0 TO PROF-1);
  SIGNAL fifo_lev     : natural RANGE 0 TO PROF-1;
  SIGNAL fifo_v       : std_logic;
  SIGNAL fifo_push_c  : std_logic;
  SIGNAL fifo_pop_c   : std_logic;
  SIGNAL writeo,hiloo : std_logic;
  SIGNAL zoneo,dblo   : std_logic;
  
  SIGNAL dfifo        : arr_uv64(0 TO PROF-1);
  SIGNAL dfifo_lev    : natural RANGE 0 TO PROF-1;
  SIGNAL dfifo_v      : std_logic;
  SIGNAL dfifo_push_c : std_logic;
  SIGNAL dfifo_pop_c  : std_logic;
  SIGNAL dato         : uv64;
  
  ---------------------------------
  SIGNAL zone,zone_c : std_logic;
  SIGNAL write_c,dbl_c,hilo_c : std_logic;
  SIGNAL double,double_c : std_logic;
  SIGNAL ddouble,ddouble_c : uv32;
BEGIN

  avl_address<=avl_address_c;
  avl_burstcount<=avl_burstcount_c;
  
  Comb:PROCESS(pw,mem_d,mem_be,wrack_mem,burstcpt,burstlen,
               avl_address_i,avl_burstcount_i,
               avl_waitrequest,zone,full,state) IS
    VARIABLE zone_v : std_logic;
    VARIABLE blen_v : natural RANGE 0 TO PB_BLEN_MAX;
  BEGIN
    ------------------------------------
    state_c<=state;
    avl_burstbegin<='0';
    avl_read<='0';
    avl_write<='0';
    mem_d_c <=mem_d;
    mem_be_c<=mem_be;
    avl_writedata <=std_logic_vector(mem_d)  & std_logic_vector(pw.d);
    avl_byteenable<=std_logic_vector(mem_be) & std_logic_vector(pw.be);
    fifo_push_c<='0';
    wrack_mem_c<=wrack_mem;
    burstcpt_c<=burstcpt;
    burstlen_c<=burstlen;
    zone_c<=zone;
    write_c<='0';
    dbl_c<='0';
    ack_c<='0';

    avl_address_c<=avl_address_i;
    avl_burstcount_c<=avl_burstcount_i;
    
    ------------------------------------
    blen_v:=pb_blen(pw);
    IF RAMSIZE=0 THEN
      zone_v:='0';
    ELSIF to_integer(pw.a(31 DOWNTO 20))>=RAMSIZE AND
      (pw.a AND x"1FFF_FFFF")<HIMEM THEN
      zone_v:='1';
    ELSE
      zone_v:='0';
    END IF;
    hilo_c<=pw.a(2);
    
    ------------------------------------
    CASE state IS
      WHEN sIDLE =>
        avl_address_c<=std_logic_vector(pw.a(N-1 DOWNTO 3));
        CASE blen_v IS
          WHEN 4      => avl_burstcount_c<=x"02";
          WHEN 8      => avl_burstcount_c<=x"04";
          WHEN OTHERS => avl_burstcount_c<=x"01";
        END CASE;
        burstcpt_c<=0;
        burstlen_c<=blen_v;
        zone_c<=zone_v;
        wrack_mem_c<='0';
        
        IF full='0' AND pw.req='1' THEN
          IF blen_v=1 AND is_write(pw) THEN
            -- Write single
            avl_burstbegin<='1';
            avl_writedata <=std_logic_vector(pw.d) & std_logic_vector(pw.d);
            avl_byteenable<=std_logic_vector(mux(pw.a(2),"0000" & pw.be,
                                                 pw.be & "0000"));
            avl_write<='1';
            ack_c<=NOT avl_waitrequest;
            fifo_push_c<=NOT avl_waitrequest AND to_std_logic(pw.mode=PB_MODE_WR_ACK);
            wrack_mem_c<=to_std_logic(pw.mode=PB_MODE_WR_ACK);
            dbl_c<='0';
            write_c<='1';
            
          ELSIF blen_v>1 AND is_write(pw) THEN
            -- Write burst
            state_c<=sWRITE;
            ack_c<='1';
            fifo_push_c<=to_std_logic(pw.mode=PB_MODE_WR_ACK);
            mem_d_c <=pw.d;
            mem_be_c<=pw.be;
            dbl_c<='1';
            write_c<='1';
            burstcpt_c<=1;
          ELSIF blen_v=1 THEN
            -- Read single
            IF avl_waitrequest='0' THEN
              ack_c<='1';
              fifo_push_c<='1';
            END IF;
            avl_read<='1';
            dbl_c<='0';
            write_c<='0';
            avl_burstbegin<='1';
            burstcpt_c<=1;
          ELSE
            -- Read burst
            IF avl_waitrequest='0' THEN
              state_c<=sREAD;
              ack_c<='1';
              fifo_push_c<='1';
            END IF;
            avl_read<='1';
            dbl_c<='1';
            write_c<='0';
            avl_burstbegin<='1';
            burstcpt_c<=1;
          END IF;
        END IF;
        
      WHEN sWRITE =>
        write_c<='1';
        dbl_c<='1';
        IF pw.req='1' OR reset_n='0' THEN
          mem_d_c <=pw.d;
          mem_be_c<=pw.be;
          IF burstcpt MOD 2=1 THEN
            avl_write<='1';
            IF avl_waitrequest='0' THEN
              ack_c<=reset_n;
              fifo_push_c<=wrack_mem;
              burstcpt_c<=burstcpt+1;
              IF burstcpt=burstlen-1 THEN
                state_c<=sIDLE;
              END IF;
            END IF;
            IF burstcpt=1 THEN
              avl_burstbegin<='1';
            END IF;
          ELSE
            ack_c<='1';
            fifo_push_c<=wrack_mem;
            burstcpt_c<=burstcpt+1;
          END IF;
        END IF;
        
      WHEN sREAD =>
        write_c<='0';
        dbl_c<='1';
        ack_c<=NOT full;
        hilo_c<=to_std_logic(burstcpt MOD 2 =1);
        IF pw.req='1' AND full='0' THEN
          fifo_push_c<='1';
          burstcpt_c<=burstcpt+1;
          IF burstcpt=burstlen-1 THEN
            state_c<=sIDLE;
          END IF;
        END IF;
    END CASE;
    ------------------------------------
  END PROCESS Comb;
  
  ------------------------------------------------------------------
  Sync: PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      state<=state_c;
      mem_d <=mem_d_c;
      mem_be<=mem_be_c;
      wrack_mem<=wrack_mem_c;
      burstcpt<=burstcpt_c;
      burstlen<=burstlen_c;
      avl_burstcount_i<=avl_burstcount_c;
      avl_address_i<=avl_address_c;
      double<=double_c;
      ddouble<=ddouble_c;
      
      -------------------------------------------------
      IF fifo_push_c='1' THEN
        fifo_write<=write_c & fifo_write(0 TO PROF-2);
        fifo_hilo <=hilo_c  & fifo_hilo(0 TO PROF-2);
        fifo_zone <=zone_c  & fifo_zone(0 TO PROF-2);
        fifo_dbl  <=dbl_c   & fifo_dbl (0 TO PROF-2);
      END IF;
      IF fifo_push_c='1' AND fifo_pop_c='0' THEN
        IF fifo_v='1' THEN
          fifo_lev<=fifo_lev+1;
        END IF;
        fifo_v<='1';
      ELSIF fifo_push_c='0' AND fifo_pop_c='1' THEN
        IF fifo_lev=0 THEN
          fifo_v<='0';
        ELSE
          fifo_lev<=fifo_lev-1;
        END IF;
      END IF;
      
      -------------------------------------------------
      IF dfifo_push_c='1' THEN
        dfifo<=unsigned(avl_readdata) & dfifo(0 TO PROF-2);
      END IF;
      IF dfifo_push_c='1' AND dfifo_pop_c='0' THEN
        IF dfifo_v='1' THEN
          dfifo_lev<=dfifo_lev+1;
        END IF;
        dfifo_v<='1';
      ELSIF dfifo_push_c='0' AND dfifo_pop_c='1' THEN
        IF dfifo_lev=0 THEN
          dfifo_v<='0';
        ELSE
          dfifo_lev<=dfifo_lev-1;
        END IF;
      END IF;
      
      -------------------------------------------------
      IF fifo_lev>=15 OR dfifo_lev>=11 THEN
        full<='1';
      ELSE
        full<='0';
      END IF;
      
      -------------------------------------------------
      IF reset_n='0' AND state/=sWRITE THEN
        fifo_v<='0';
        fifo_lev<=0;
        dfifo_v<='0';
        dfifo_lev<=0;
        state<=sIDLE;
      END IF;        

    END IF;
  END PROCESS Sync;
  
  writeo<=fifo_write(fifo_lev); -- 0=Read    1=Write 
  hiloo <=fifo_hilo (fifo_lev); -- 0=[63:32] 1=[31:0]
  zoneo <=fifo_zone (fifo_lev); -- 0=RAM     1=Void
  dblo  <=fifo_dbl  (fifo_lev); -- 0=Single  1=Both used

  dato <=dfifo(dfifo_lev);
  
  ------------------------------------------------------------------
  CombRead:PROCESS(dfifo_v,hiloo,dblo,ack_c,dato,
                   avl_readdata,avl_readdatavalid,
                   ddouble,double,zoneo,
                   writeo,pw,fifo_v)
    VARIABLE dr_v : uv64;
  BEGIN

    --sélection donnée : soit reçues si fifo vide
    --  soit fifo.
    --  push/pop....

    -- ? Si nouvelles données reçues : empile
    -- ? Si nouvelles données reçues ou FIFO data non vide ou double
    --   ? Si la commande postée est un READ
    --     ? Soit c'est un read single
    --       - Dépile double si double=1 => double=0
    --       - Dépile data
    --     ? Soit c'est un read burst
    --       - Dépile double si double=1 => double=0
    --       - Dépile data. double=1, copie partie basse
    -- ? Si commande postée est WRITE
    --  - Dépile commande

    IF dfifo_v='1' THEN
      dr_v:=dato;
    ELSE
      dr_v:=unsigned(avl_readdata);
    END IF;
    
    double_c <='0';
    ddouble_c<=ddouble;
    dfifo_pop_c <='0';
    dfifo_push_c<=avl_readdatavalid;
    fifo_pop_c<='0';
    pr.dreq<='0';
    pr.code<=PB_OK;
    pr.ack<=ack_c;
    IF double='1' THEN
      pr.d<=ddouble;
    ELSE
      pr.d<=mux(hiloo,dr_v(31 DOWNTO 0),dr_v(63 DOWNTO 32));
    END IF;
    
    -- READ
    IF avl_readdatavalid='1' OR double='1' OR dfifo_v='1' THEN
      IF writeo='0' AND fifo_v='1' THEN
        pr.dreq<='1';
        IF pw.dack='1' THEN
          fifo_pop_c<='1';
          ddouble_c<=dr_v(31 DOWNTO 0);
          double_c<='0';
        END IF;
        
        IF dblo='0' THEN
          dfifo_pop_c<=pw.dack;
          IF double='1' THEN -- Impossible
            pr.d<=ddouble;
          ELSE
            pr.d<=mux(hiloo,dr_v(31 DOWNTO 0),dr_v(63 DOWNTO 32));
          END IF;
        ELSE
          IF double='1' THEN
            pr.d<=ddouble;
          ELSE
            pr.d<=mux(hiloo,dr_v(31 DOWNTO 0),dr_v(63 DOWNTO 32));
            double_c<=pw.dack;
            dfifo_pop_c<=pw.dack;
          END IF;
        END IF;
      END IF;
      IF zoneo='1' THEN
        pr.d<=x"0000_0000";
      END IF;
      
      -- WRITE_ACK
      IF writeo='1' AND fifo_v='1' THEN
        pr.dreq<='1';
        fifo_pop_c<=pw.dack;
      END IF;
    END IF;
    
  END PROCESS CombRead;
  
END ARCHITECTURE rtl;
