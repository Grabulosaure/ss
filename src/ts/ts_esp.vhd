--------------------------------------------------------------------------------
-- TEM : TS
-- SCSI
--------------------------------------------------------------------------------
-- DO 1/2011
--------------------------------------------------------------------------------
-- NCR/AMD 53C9x SCSI ESP
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

--                  R          |           W
--  0 : Current Transfer LSB   | Transfer Count LSB
--  4 : Current Transfer MSB   | Transfer Count MSB
--  8 :                     FIFO Data
--  C :                     Command
-- 10 : Status                 | Destination ID
-- 14 : Interrupt status       | Timeout
-- 18 : Internal State         | Sync. Transfer Period
-- 1C : Current FIFO           | Sync. Offset
-- 20 :                   Control Reg 1
-- 24 :                        | Clock Factor
-- 28 :                        | Test Mode
-- 2C :                   Control Reg 2
-- 30 :                   Control Reg 3
-- 34 :
-- 38 :
-- 3C :                        | Data Alignment

-- La FIFO ne sert pas en mode DMA
-- <AVOIR> Vérifier FIFO, DMA,...

--------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.plomb_pack.ALL;
USE work.ts_pack.ALL;

ENTITY ts_esp IS
  GENERIC (
    ASI : uv8);
  PORT (
    sel    : IN  std_logic;
    w      : IN  type_pvc_w;
    r      : OUT type_pvc_r;
    
    pw     : OUT type_plomb_w;
    pr     : IN  type_plomb_r;

    scsi_w : OUT type_scsi_w;
    scsi_r : IN  type_scsi_r;
    
    int    : OUT std_logic;
    
    -- Partie DMA
    dma_esp_iena     : IN  std_logic;
    dma_esp_int      : OUT std_logic;
    dma_esp_reset    : IN  std_logic;
    dma_esp_write    : IN  std_logic;
    dma_esp_addr_w   : IN  uv32;
    dma_esp_addr_r   : OUT uv32;
    dma_esp_addr_maj : IN  std_logic;
    
    -- Global
    clk      : IN std_logic;
    reset_na : IN std_logic
    );
END ENTITY ts_esp;

--##############################################################################

ARCHITECTURE rtl OF ts_esp IS
  
  CONSTANT CMD_NOP      : uv8:=x"00";  -- No Operation
  CONSTANT CMD_FLUSH    : uv8:=x"01";  -- Clear FIFO
  CONSTANT CMD_RESET    : uv8:=x"02";  -- Reset Device
  CONSTANT CMD_BUSRESET : uv8:=x"03";  -- Reset SCSI Bus
  CONSTANT CMD_IT       : uv8:=x"10";  -- Information Transfer
  CONSTANT CMD_ICCS     : uv8:=x"11";  -- Info. Command Complete Steps
  CONSTANT CMD_MSGACC   : uv8:=x"12";  -- Message Accepted
  CONSTANT CMD_PAD      : uv8:=x"18";  -- Transfer Pad bytes
  CONSTANT CMD_SATN     : uv8:=x"1A";  -- Set ATN
  CONSTANT CMD_SEL      : uv8:=x"41";  -- Select without ATN Steps
  CONSTANT CMD_SELATN   : uv8:=x"42";  -- Select with ATN Steps
  CONSTANT CMD_SELATNS  : uv8:=x"43";  -- Select with ATN and Stop Steps
  CONSTANT CMD_ENSEL    : uv8:=x"44";  -- Enable Selection/Reselection
  
  -- Registres
  SIGNAL rsel : std_logic;
  SIGNAL dr : uv32;
  CONSTANT FIFO_PROF : natural := 16;
  SIGNAL fifo_lev : natural RANGE 0 TO FIFO_PROF-1;
  SIGNAL fifo_vv : std_logic;
  TYPE arr_byte IS ARRAY(natural RANGE <>) OF uv8;
  SIGNAL fifoesp : arr_byte(0 TO FIFO_PROF-1);
  SIGNAL dest_id,dest_id2 : unsigned(2 DOWNTO 0);
  SIGNAL istate : unsigned(2 DOWNTO 0);  -- Internal State Reg(2:0)
  SIGNAL reg_cr1,reg_cr2,reg_cr3 : uv8;  -- Control regs
  SIGNAL scsi_ena   : std_logic;
  SIGNAL scsi_reset : std_logic;
  SIGNAL scsi_atn   : std_logic;
  SIGNAL scsi_bsy   : std_logic;
  SIGNAL scsi_reqack : std_logic;
  SIGNAL scsi_w_i : type_scsi_w;
  SIGNAL cmd_maj : std_logic;
  SIGNAL cmd,cmd_mem : uv8;
  SIGNAL mem_phase : unsigned(2 DOWNTO 0);
  SIGNAL mem_dja : std_logic;
  SIGNAL memcommand : std_logic;
  
  TYPE enum_state IS (sIDLE,
                      sINFO_TRANSFER,sINFO_TRANSFER_FIN,sINFO_TRANSFER_CHANGE,
                      sICCS,sICCS_BIS,sICCS_TER,
                      sSELECT,sSELECT_ATN,sSELECT_ATN2,
                      sSELECT_COMMAND,sSELECT_FIN,sNOSEL);
  SIGNAL state,state_pre : enum_state;
  SIGNAL fifo_acc : std_logic;
  
  -- Interruptions
  SIGNAL inter : std_logic;               -- Drapeau interruption
  SIGNAL int_rst  : std_logic;  -- Interrupt Status (7) : SCSI Reset
  SIGNAL int_disc : std_logic;  -- Interrupt Status (5) : Disconnected
  SIGNAL int_sr   : std_logic;  -- Interrupt Status (4) : Service Request
  SIGNAL int_so   : std_logic;  -- Interrupt Status (3) : Successful Operation
  -- <AFAIRE Service Request Interrupt>
  
  -- DMA
  SIGNAL dma_mode : std_logic;
  SIGNAL dma_finw : std_logic;
  SIGNAL dma_fin_pre,dma_dernier : std_logic;
  SIGNAL dma_a : uv32;
  SIGNAL dma_a_bis : uv2;
  SIGNAL dma_buf    : uv32;
  SIGNAL dma_buf_be : uv0_3;
  SIGNAL dma_req,dma_ack : std_logic;
  SIGNAL dma_rw : std_logic;
  SIGNAL dma_rrdy,dma_wfr : std_logic;
  SIGNAL dma_wrdy : std_logic;
  SIGNAL dma_dw,dma_dr : uv8;
  SIGNAL dma_ctc : uv16;  -- DMA Current Transfert Count Reg.
  SIGNAL dma_ctz : std_logic;
  SIGNAL dma_stc : uv16;  -- DMA Start Transfert Count Reg.
  SIGNAL dma_fin : std_logic;
  SIGNAL dma_maj_ctc : std_logic;
  SIGNAL pw_i_req : std_logic;
  
BEGIN

  rsel<=w.req AND sel;
  
  Sync: PROCESS (clk,reset_na)
    VARIABLE vcmd : uv8;
    VARIABLE fifo_push_v,fifo_pop_v : std_logic;
    VARIABLE fifo_reg_push_v,fifo_reg_pop_v : std_logic;
    VARIABLE fifo_scsi_push_v,fifo_scsi_pop_v : std_logic;
    VARIABLE fifo_dw_v : uv8;
    VARIABLE cmd_v : uv8;
  BEGIN
    IF reset_na='0' THEN
      fifo_lev<=0;
      fifo_vv<='0';
      scsi_atn<='0';
      scsi_bsy<='0';
      cmd<=CMD_NOP;
    ELSIF rising_edge(clk) THEN
      -------------------------------------------------------
      --  0 : Current Transfer LSB   | Transfer Count LSB
      IF rsel='1' AND w.a(6 DOWNTO 2)="00000" THEN
        IF w.be(0)='1' AND w.wr='1' THEN
          dma_stc(7 DOWNTO 0)<=w.dw(31 DOWNTO 24);
        END IF;
        dr<=dma_ctc(7 DOWNTO 0) & x"000000";
      END IF;
      
      --  4 : Current Transfer MSB   | Transfer Count MSB
      IF rsel='1' AND w.a(6 DOWNTO 2)="00001" THEN
        IF w.be(0)='1' AND w.wr='1' THEN
          dma_stc(15 DOWNTO 8)<=w.dw(31 DOWNTO 24);
        END IF;
        dr<=dma_ctc(15 DOWNTO 8) & x"000000";
      END IF;
      
      --  8 :                     FIFO Data
      fifo_reg_pop_v:='0';
      fifo_reg_push_v:='0';
      IF rsel='1' AND w.a(6 DOWNTO 2)="00010" THEN
        IF w.be(0)='1' AND w.wr='1' THEN
          fifo_reg_push_v:='1';
        END IF;
        IF w.be(0)='1' AND w.wr='0' THEN
          fifo_reg_pop_v:='1';
        END IF;
        dr<=fifoesp(fifo_lev) & x"000000";
      END IF;
      
      --  C :                     Command
      cmd_maj<='0';
      IF rsel='1' AND w.a(6 DOWNTO 2)="00011" THEN
        IF w.be(0)='1' AND w.wr='1' THEN
          cmd<=w.dw(31 DOWNTO 24);
          cmd_maj<='1';
        END IF;
        dr<=cmd & x"000000";
      END IF;
      
      -- 10 : Status                 | Destination ID
      --  R : 2:0 : SCSI Phase <QEMU>
      --  R :   3 : Group Code Valid <non>
      --  R :   4 : Count To Zero <QEMU>
      --  R :   5 : Parity Error <non>
      --  R :   6 : Illegal Operation Error <non>
      --  R :   7 : Interrupt <QEMU>
      --  W : 2:0 : SCSI Destination <QEMU>
      --  W : 7:3 : Réservé <non>
      IF rsel='1' AND w.a(6 DOWNTO 2)="00100" THEN
        IF w.be(0)='1' AND w.wr='1' THEN
          dest_id<=w.dw(26 DOWNTO 24);
        END IF;
        dr<=inter & "00" & dma_fin & '0' & scsi_r.phase &
             x"000000";
      END IF;
      
      -- 14 : Interrupt status       | Timeout
      --  R :   0 : Selected <non>
      --  R :   1 : Selected with Attention <non>
      --  R :   2 : Reselected <non>
      --  R :   3 : Successful Operation <QEMU>
      --  R :   4 : Service Request <QEMU>
      --  R :   5 : Disconnected <QEMU>
      --  R :   6 : Invalid Command <non>
      --  R :   7 : SCSI Reset <QEMU>
      --  W : 7:0 : SCSI Timeout <non>
      IF rsel='1' AND w.a(6 DOWNTO 2)="00101" THEN
        IF w.be(0)='1' AND w.wr='0' THEN
          -- RAZ interruptions sur Lecture
          int_rst<='0';
          int_disc<='0';
          int_sr<='0';
          int_so<='0';
          inter<='0';
          istate<="100";
        END IF;
        dr<=int_rst & '0' & int_disc & int_sr & int_so & "000" & x"000000";
      END IF;
      
      -- 18 : Internal State         | Sync. Transfer Period
      --  R : 2:0 : Internal State = 0/4 <QEMU>
      --  R :   3 : SOF <non>
      --  R : 7:4 : Réservé <non>
      --  W : 4:0 : Sync Transfer period <non>
      --  W : 7:5 : Réservé <non>
      IF rsel='1' AND w.a(5 DOWNTO 2)="00110" THEN
        dr<="00000" & istate & x"000000";
      END IF;
      
      -- 1C : Current FIFO           | Sync. Offset
      --  R : 4:0 : Current FIFO = 0/2 <QEMU>
      --  R : 7:5 : Internal state = 0 <non>
      --  W : 3:0 : Sync Offset <non>
      --  W : 7:4 : Réservé <non>
      IF rsel='1' AND w.a(5 DOWNTO 2)="00111" THEN
        IF fifo_vv='0' THEN
          dr<=istate & "00000" & x"000000";
        ELSE
          dr<=istate & to_unsigned(fifo_lev+1,5) & x"000000";
        END IF;
        
      END IF;
      
      -- 20 :                   Control Reg 1
      -- RW : 2:0 : Chip ID <non>
      -- RW :   3 : Self Test <non>
      -- RW :   4 : Parity Error <non>
      -- RW :   5 : Parity Test <non>
      -- RW :   6 : Disable interrupt on SCSI Reset <QEMU>
      -- RW :   7 : Extended timing <non>
      IF rsel='1' AND w.a(5 DOWNTO 2)="01000" THEN
        IF w.be(0)='1' AND w.wr='1' THEN
          reg_cr1<=w.dw(31 DOWNTO 24);
        END IF;
        dr<=reg_cr1 & x"000000";
      END IF;
      
      -- 24 :                        | Clock Factor
      --  W : 2:0 : Clock factor <non>
      
      -- 28 :                        | Test Mode
      --  W :   0 : Forced target <non>
      --  W :   1 : Forced initiator <non>
      --  W :   2 : Forced high-Z <non>
      
      -- 2C :                   Control Reg 2
      -- <non>
      IF rsel='1' AND w.a(5 DOWNTO 2)="01011" THEN
        IF w.be(0)='1' AND w.wr='1' THEN
          reg_cr2<=w.dw(31 DOWNTO 24);
        END IF;
        dr<=(reg_cr2 AND x"FD") & x"000000";
      END IF;
      
      -- 30 :                   Control Reg 3
      -- <non>
      IF rsel='1' AND w.a(5 DOWNTO 2)="01100" THEN
        IF w.be(0)='1' AND w.wr='1' THEN
          reg_cr3<=w.dw(31 DOWNTO 24);
        END IF;
        dr<=reg_cr3 & x"000000";
      END IF;
      
      -- 34 :
      -- Rien
      -- <TEST>
      IF rsel='1' AND w.a(5 DOWNTO 2)="01101" THEN
        dr<="000000" & scsi_r.d_pc &
             "00000" & dest_id &
             scsi_w_i.bsy & scsi_w_i.atn & "00" &
             '0' & scsi_r.phase;
      END IF;
      -- <TEST>
      
      -- 38 :
      -- Rien
      
      -- 3C :                        | Data Alignment
      -- Bof

      ----------------------------------------------------
      -- FIFO
      -- IO=0 : MSG_OUT, COMMAND, DATA_OUT (Data: ESP -> Disque)
      -- IO=1 : MSG_IN, STATUS, DATA_IN    (Data: ESP <- Disque)
      fifo_scsi_pop_v:=NOT dma_mode AND fifo_acc AND
                       NOT scsi_r.phase(0);
      fifo_scsi_push_v:=NOT dma_mode AND fifo_acc AND
                        scsi_r.phase(0);
      
      fifo_pop_v:=fifo_reg_pop_v OR fifo_scsi_pop_v;
      fifo_push_v:=fifo_reg_push_v OR fifo_scsi_push_v;
      
      fifo_dw_v:=mux(fifo_reg_push_v,w.dw(31 DOWNTO 24), scsi_r.d);
      IF fifo_push_v='1' THEN
        fifoesp<=fifo_dw_v & fifoesp(0 TO FIFO_PROF-2);
      END IF;
      IF fifo_push_v='1' AND fifo_pop_v='0' THEN
        -- Empile
        IF fifo_vv='1' THEN
          fifo_lev<=fifo_lev+1;
        END IF;
        fifo_vv<='1';
      ELSIF fifo_pop_v='1' AND fifo_push_v='0' THEN
        -- Dépile
        IF fifo_lev=0 THEN
          fifo_vv<='0';
        ELSE
          fifo_lev<=fifo_lev-1;
        END IF;
      END IF;
      
      ----------------------------------------------------
      -- Traitement commandes
      dma_maj_ctc<='0';
      scsi_reset<='0';
      
      CASE state IS
        WHEN sIDLE =>
          scsi_ena<='0';
          mem_dja<='0';
          IF cmd_maj='1' THEN
            dma_mode<=cmd(7);
            dma_maj_ctc<=cmd(7);
            cmd_v:=cmd;
            cmd_v(7):='0';
            cmd_mem<='0' & cmd(6 DOWNTO 0);
            
            CASE cmd_v IS
              WHEN CMD_NOP      =>
                -- No Operation
                NULL;
                
              WHEN CMD_FLUSH    =>
                -- Flush FIFO
                fifo_lev<=0;
                fifo_vv<='0';
--                fifo(0)<=x"00";
                int_rst<='0';
                int_disc<='0';
                int_sr<='0';
                int_so<='1';  -- Successful Operation (?)
                istate<="000";
                
              WHEN CMD_RESET    =>
                -- Chip RESET
                scsi_atn<='0';
                scsi_bsy<='0';
                fifo_lev<=0;
                fifo_vv<='0';
--                fifo(0)<=x"00";
                int_rst<='0';
                int_disc<='0';
                int_sr<='0';
                int_so<='0';
                inter<='0';
                istate<="000";
                --s->rregs[ESP_TCHI] = TCHI_FAS100A; // Indicate fas100a
                --reg_cr1<=x"07";         -- Control Reg 1 : Chip ID=7
          
              WHEN CMD_BUSRESET =>
                -- Bus RESET
                scsi_atn<='0';
                scsi_bsy<='0';
                int_rst<='1';
                inter<=NOT reg_cr1(6); 
                scsi_reset<='1';
                
              WHEN CMD_IT       =>
                -- Information Transfer
                scsi_atn<='0';
                state<=sINFO_TRANSFER;
                
              WHEN CMD_ICCS     =>
                -- Initiator Command Complete Steps
                state<=sICCS;
                
              WHEN CMD_MSGACC   =>
                -- Message Accepted
                -- On suppose qu'il y a une déconnexion à l'issue de cette
                -- commande.
                fifo_lev<=0;
                fifo_vv<='0';
                int_rst<='0';
                int_disc<='1';
                int_sr<='0';
                int_so<='0';
                inter<='1';
                istate<="000";
                
              WHEN CMD_PAD =>
                -- Transfert Pad Bytes
                -- Similaire à Information Transfer, mais avec des zéros
                scsi_atn<='0';
                state<=sINFO_TRANSFER;
                
              WHEN CMD_SATN     =>
                -- Set ATN
                scsi_atn<='1';
                
              WHEN CMD_SEL      =>
                -- Select without ATN
                -- Transfert d'une commande
                --scsi_atn<='0';
                state<=sSELECT;
                dest_id2<=dest_id;
                
              WHEN CMD_SELATN   =>
                -- Select with ATN
                -- Transfert d'un octet de message, puis une commande
                --scsi_atn<='1';
                state<=sSELECT;
                dest_id2<=dest_id;
                
              WHEN CMD_SELATNS  =>
                -- Select with ATN and Stop Steps
                -- Transfert d'un octet de message
                --scsi_atn<='1';
                state<=sSELECT;
                dest_id2<=dest_id;
                
              WHEN CMD_ENSEL    =>
                -- Enable selection
                int_rst<='0';
                int_disc<='0';
                int_sr<='0';
                int_so<='0';
                
              WHEN OTHERS => NULL;
            END CASE;
          END IF;

          -------------------------------------------------------------
        WHEN sINFO_TRANSFER =>
          -- Comande CMD_IT
          -- Les transferts ont lieu :
          --  - Soit avec le DMA
          --  - Soit avec la FIFO
          -- La fin de la commande :
          --  - Soit le comptage est fini
          --  - Soit la phase a changé et il y a un REQ
          --  - Fin de message
          IF ((dma_mode='1' AND dma_fin='1' AND dma_fin_pre='0') OR
              (dma_mode='0' AND fifo_vv='0')) AND scsi_ena='1' THEN
            state<=sINFO_TRANSFER_FIN;
            scsi_ena<='0';
          ELSIF scsi_r.phase/=mem_phase AND mem_dja='1' THEN
            state<=sINFO_TRANSFER_CHANGE;
            scsi_ena<='0';
          ELSE
            scsi_ena<='1';
          END IF;
          IF scsi_r.req='1' THEN
            mem_phase<=scsi_r.phase;
            mem_dja<='1';
          END IF;

        WHEN sINFO_TRANSFER_FIN =>
          scsi_atn<='0';
          scsi_ena<='0';
          state<=sIDLE;
          int_rst<='0';
          int_disc<='0';
          int_sr<='1';
          int_so<='0';
          inter<='1';          -- Déclenche interruption

        WHEN sINFO_TRANSFER_CHANGE =>
          -- On attend qu'il y ait réellement une nouvelle donnée
          IF scsi_r.req='1' THEN
            state<=sINFO_TRANSFER_FIN;
          END IF;
          -------------------------------------------------------------
        WHEN sICCS =>
          -- Initiator Command Complete Steps
          -- On attend "Status" suivi de "Message-IN"
          scsi_bsy<='1';
          scsi_atn<='0';
          scsi_ena<='1';
          IF scsi_r.req='1' AND scsi_w_i.ack='1' THEN
            state<=sICCS_BIS;
          END IF;

        WHEN sICCS_BIS =>
          IF scsi_r.req='1' AND scsi_w_i.ack='1' THEN
            state<=sICCS_TER;
          END IF;

        WHEN sICCS_TER =>
          scsi_bsy<='0';
          scsi_atn<='0';
          scsi_ena<='0';
          state<=sIDLE;
          int_rst<='0';
          int_disc<='0';
          int_sr<='0';
          int_so<='1';
          inter<='1';          -- Déclenche interruption
          
          -------------------------------------------------------------
        WHEN sSELECT =>
          -- Select With ATN / Without ATN / With ATN and Stop
          istate<="000";
          memcommand<='0';

          IF state_pre=sSELECT THEN -- Attente propagation .did -> .sel
            IF scsi_r.sel='0' THEN
              -- Timeout : Aucune cible sélectionnée ...
              state<=sNOSEL;
            ELSE
              scsi_bsy<='1';
              IF cmd_mem=CMD_SELATN OR cmd_mem=CMD_SELATNS THEN
                scsi_atn<='1';
                state<=sSELECT_ATN;
              ELSE
                scsi_atn<='0';
                state<=sSELECT_COMMAND;
              END IF;
            END IF;
          END IF;
          
        WHEN sSELECT_ATN =>
          state<=sSELECT_ATN2;
          
        WHEN sSELECT_ATN2 =>
          -- Octet message au début
          scsi_ena<='1';
          memcommand<='0';

          IF scsi_r.req='1' AND scsi_w_i.ack='1' THEN
            IF cmd_mem=CMD_SELATNS THEN
              istate<="001";
              state<=sSELECT_FIN;
            ELSE
              scsi_atn<='0';
              state<=sSELECT_COMMAND;
            END IF;
          END IF;

        WHEN sSELECT_COMMAND =>
          -- Bloc de commande
          IF scsi_r.phase=SCSI_COMMAND THEN
            memcommand<='1';
          END IF;
          IF (dma_mode='1' AND dma_fin='1') OR
             (dma_mode='0' AND fifo_vv='0') THEN
            state<=sSELECT_FIN;
            scsi_ena<='0';
            istate<="100";
          ELSIF scsi_r.phase/=SCSI_COMMAND AND memcommand='1' THEN
            state<=sSELECT_FIN;
            scsi_ena<='0';
            istate<="011";
          ELSE
            scsi_ena<='1';
          END IF;

        WHEN sSELECT_FIN =>
          scsi_ena<='0';
          state<=sIDLE;
          int_rst<='0';
          int_disc<='0';
          int_sr<='1'; --int_sr<='0'; 
          int_so<='1';
          inter<='1';          -- Déclenche interruption

        WHEN sNOSEL =>
          -- Destination ID vers personne
          scsi_ena<='0';
          state<=sIDLE;
          int_rst<='0';
          int_disc<='1';                -- Disconnected
          int_sr<='0';
          int_so<='0';
          inter<='1';          -- Déclenche interruption

          -------------------------------------------------------------
      END CASE;

      state_pre<=state;
      -- RESET Synchrone
      IF dma_esp_reset='1' THEN
        state<=sIDLE;
        state_pre<=sIDLE;
        int_rst<='0';
        int_disc<='0';
        int_sr<='0';
        int_so<='0';
        inter<='0';
        scsi_atn<='0';
        scsi_reset<='0';
      END IF;
      
      int<=inter AND dma_esp_iena;
    END IF;
  END PROCESS Sync;
  
  -- Relectures registres
  R_Gen:PROCESS(w,dr,sel)
  BEGIN
    r.ack<=w.req AND sel;
    r.dr<=dr;
  END PROCESS R_Gen;

  dma_esp_int<=inter;
  
  ------------------------------------------------------------------------------
  -- SCSI
  -- scsi_r.req / scsi_w.ack : Accès SCSI
  
  -- Selon la phase, on peut inhiber les requètes d'accès SCSI
  
  -- scsi_ena : Autorisation des accès SCSI
  
  -- fifo_acc : Accès vers FIFO
  fifo_acc<=mux(dma_rw,
                -- SCSI -> ESP
                scsi_ena AND scsi_r.req AND scsi_w_i.ack AND NOT dma_mode,
                -- ESP -> SCSI
                scsi_ena AND scsi_reqack AND NOT dma_mode);
  
  scsi_w_i.d<=mux(dma_mode,dma_dr,fifoesp(fifo_lev));
  scsi_w_i.ack<=scsi_ena AND (dma_ack OR NOT dma_mode);
  -- busy signale l'activité sur le bus
  scsi_w_i.bsy<=scsi_bsy;
  -- atn  signale une phase de commande au début au au milieu
  scsi_w_i.atn<=scsi_atn;
  scsi_w_i.did<=dest_id2;
  scsi_w_i.rst<=scsi_reset;

  scsi_w_i.d_state<="0000" WHEN state=sIDLE ELSE
                    "0001" WHEN state=sINFO_TRANSFER ELSE
                    "0010" WHEN state=sINFO_TRANSFER_FIN ELSE
                    "0011" WHEN state=sINFO_TRANSFER_CHANGE ELSE
                    "0100" WHEN state=sICCS ELSE
                    "0101" WHEN state=sICCS_BIS ELSE
                    "0110" WHEN state=sICCS_TER ELSE
                    "0111" WHEN state=sSELECT ELSE
                    "1000" WHEN state=sSELECT_ATN ELSE
                    "1001" WHEN state=sSELECT_ATN2 ELSE
                    "1010" WHEN state=sSELECT_COMMAND ELSE
                    "1011" WHEN state=sSELECT_FIN ELSE
                    "1100" WHEN state=sNOSEL ELSE
                    "1111";
  scsi_w<=scsi_w_i;

  dma_dw<=scsi_r.d;
  
  ------------------------------------------------------------------------------
  -- Plomb DMA

--  adresse : dma_a
--  nombre  : dma_ctc
--  données écriture : dma_dw(8 bits)
--  données lecture  : dma_dr(8 bits)
--  accès : dma_req / dma_ack
--  direction : dma_rw

  dma_rw   <=scsi_r.phase(0);         -- IO=0 --> Mem READ
  
  -- dma_req / dma_ack : Accès vers DMA
  dma_req  <=scsi_ena AND scsi_r.req AND dma_mode;
  
  dma_ack<=dma_req AND dma_rrdy AND NOT dma_fin WHEN dma_rw='0' ELSE
            dma_req AND dma_wrdy;
  
  -- Fin de burst lorsque le compteur passe de 0000 à FFFF, sauf le premier !
  dma_fin<='1' WHEN dma_ctc=x"0000" AND dma_ctz='1' ELSE '0';
  dma_finw<='1' WHEN dma_ctc=x"0001" ELSE '0';

  -- plomb : pw / pr
  pw.a<=dma_a(31 DOWNTO 2) & "00";
  pw.ah<=x"F";
  pw.asi<=ASI;
  pw.d<=dma_buf;
  pw.mode<=mux(dma_rw,PB_MODE_WR,PB_MODE_RD);
  pw.be<=mux(dma_rw,dma_buf_be,"1111");
  pw.burst<=PB_SINGLE;
  pw.cache<='0';
  pw.lock<='0';
  pw.cont<='0';
  pw.req<=pw_i_req;
  pw.dack<='1';

  Sync_DMA:PROCESS(clk,reset_na)
  BEGIN
    IF reset_na='0' THEN
      dma_wfr<='0';
      dma_rrdy<='0';
      pw_i_req<='0';
      dma_wrdy<='0';
    ELSIF rising_edge(clk) THEN
      scsi_reqack<=scsi_w_i.ack AND scsi_r.req;
      
      -- Bus lectures
      IF dma_a_bis="00" THEN
        dma_dr<=dma_buf(31 DOWNTO 24);
      ELSIF dma_a_bis="01" THEN
        dma_dr<=dma_buf(23 DOWNTO 16);
      ELSIF dma_a_bis="10" THEN
        dma_dr<=dma_buf(15 DOWNTO 8);
      ELSE
        dma_dr<=dma_buf(7 DOWNTO 0);
      END IF;
      dma_a_bis<=dma_a(1 DOWNTO 0);

      -- Comptage accès
      IF dma_req='1' AND dma_ack='1' THEN
        dma_a(1 DOWNTO 0)<=dma_a(1 DOWNTO 0)+1;
        dma_ctc<=dma_ctc-1;
        dma_ctz<='1';
      END IF;
      IF dma_maj_ctc='1' THEN
        dma_ctc<=dma_stc;
        dma_ctz<='0';
      END IF;
      
      IF dma_esp_addr_maj='1' THEN
        dma_a<=dma_esp_addr_w;
        dma_wrdy<='1';
        dma_buf_be<="0000";
      END IF;

      IF dma_rw='0' THEN
        -- Lectures
        IF dma_req='1' AND dma_a(1 DOWNTO 0)="11" THEN
          -- En fin de ligne, on force à 0
          dma_rrdy<='0';
        END IF;
        IF dma_req='1' AND dma_rrdy='0' AND dma_wfr='0' THEN
          pw_i_req<='1';
        END IF;
        IF pr.ack='1' AND pw_i_req='1' THEN
          dma_wfr<='1';                 -- Wait For Read
        END IF;
      ELSE
        -- Ecritures
        IF dma_req='1' AND dma_ack='1' THEN
          IF dma_a(1 DOWNTO 0)="00" THEN
            dma_buf(31 DOWNTO 24)<=dma_dw;
            dma_buf_be(0)<='1';
          ELSIF dma_a(1 DOWNTO 0)="01" THEN
            dma_buf(23 DOWNTO 16)<=dma_dw;
            dma_buf_be(1)<='1';
          ELSIF dma_a(1 DOWNTO 0)="10" THEN
            dma_buf(15 DOWNTO 8)<=dma_dw;
            dma_buf_be(2)<='1';
          ELSE
            dma_buf(7 DOWNTO 0)<=dma_dw;
            dma_buf_be(3)<='1';
          END IF;
        END IF;
        IF dma_req='1' AND dma_ack='1' AND
          (dma_a(1 DOWNTO 0)="11" OR dma_finw='1') THEN
          dma_wrdy<='0';
          pw_i_req<='1';
        END IF;
      END IF;
      
      IF pr.dreq='1' THEN
        dma_wfr<='0';
        dma_rrdy<='1';                -- Il y a des données
        dma_buf<=pr.d;
      END IF;
      
      IF pr.ack='1' AND pw_i_req='1' THEN
        dma_wrdy<=dma_rw;
        pw_i_req<='0';
        dma_a(31 DOWNTO 2)<=dma_a(31 DOWNTO 2)+1;
        dma_buf_be<="0000";
      END IF;
      
      IF dma_fin='1' OR scsi_ena='0' THEN
        dma_rrdy<='0';
      END IF;
      
      dma_fin_pre<=dma_fin;
      
    END IF;
  END PROCESS Sync_DMA;

  dma_esp_addr_r<=dma_a;
  
END ARCHITECTURE rtl;
