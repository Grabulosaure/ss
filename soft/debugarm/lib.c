/* Debugger.
   Contrôle bas niveau

   DO 5/2011
*/

#include <stdint.h>
#include <stdio.h>
#include <fcntl.h>
#include "lib.h"

// Debug Link addresses
#define DL_CPU (0x00) // CPU
#define DL_ANA (0x10) // Logic Analyser

//--------------------------------------------------------------------
#define CPU_WR_CONTROL (0x8)
#define CPU_WR_OPCODE  (0x9)
#define CPU_WR_IBRK    (0xA)
#define CPU_WR_DBRK    (0xB)
#define CPU_WR_TEST    (0xE)

#define CPU_RD_STATUS  (0x1)
#define CPU_RD_DATA    (0x2)
#define CPU_RD_PC      (0x3)
#define CPU_RD_NPC     (0x4)
#define CPU_RD_STATUS2 (0x5)
#define CPU_RD_TEST    (0x6)

void dbg_resync()
{
   sp_puc(0xFF);
   sp_puc(0xFF);
   sp_puc(0xFF);
   sp_puc(0xFF);
   sp_puc(0xFF);
}


static inline void dbg_write(uint8_t c, uint32_t op)
{
    sp_puc(c);
    sp_puc(op & 255);
    sp_puc((op >> 8) & 255);
    sp_puc((op >> 16) & 255);
    sp_puc((op >> 24) & 255);
}

static inline uint32_t dbg_read(uint8_t c)
{
    uint32_t v;
    sp_puc(c);
    v = sp_gec();
    v = v | (sp_gec() << 8);
    v = v | (sp_gec() << 16);
    v = v | (sp_gec() << 24);
    return v;
}

static inline void dbg_read_c(uint8_t c)
{
    sp_puc(c);
}

static inline uint32_t dbg_read_d()
{
    uint32_t v;
    v = sp_gec();
    v = v | (sp_gec() << 8);
    v = v | (sp_gec() << 16);
    v = v | (sp_gec() << 24);
    return v;
}

static void dbg_write_op(uint32_t op)
{
     dbg_write(DL_CPU | CPU_WR_OPCODE, op);
}

static void dbg_write_ctrl(uint32_t cmd)
{
    dbg_write(DL_CPU | CPU_WR_CONTROL, cmd);
}

void dbg_write_ibrk(uint32_t a)
{
    dbg_write(DL_CPU | CPU_WR_IBRK, a);
}

void dbg_write_dbrk(uint32_t a)
{
    dbg_write(DL_CPU | CPU_WR_DBRK, a);
}

uint32_t dbg_read_data()
{
    return dbg_read(DL_CPU | CPU_RD_DATA);
}

uint32_t dbg_read_status()
{
    return dbg_read(DL_CPU | CPU_RD_STATUS);
}

uint32_t dbg_read_status2()
{
    return dbg_read(DL_CPU | CPU_RD_STATUS2);
}

uint32_t dbg_read_pc()
{
    return dbg_read(DL_CPU | CPU_RD_PC);
}

uint32_t dbg_read_npc()
{
    return dbg_read(DL_CPU | CPU_RD_NPC);
}

//--------------------------------------------------------------------
uint32_t ctrl[4],ctrlc = 0;


int cpu = 0; // Numéro CPU sélectionné.
uint32_t cop_pc[4], cop_npc[4], cop_r1[4], cop_r2[4], cop_r3[4], cop_psr[4];

/*
  CTRL(0)  : [PER-CPU] Stop=1, Run=0
  CTRL(1)  :
  CTRL(2)  : RESET
  CTRL(3)  : STOPA
  CTRL(4)  :
  CTRL(5)  : PPC (autorisation empilage fetch)
  CTRL(6)  : [PER-CPU] Inst Bkpt enable=1, disable=0
  CTRL(7)  : [PER-CPU] Data Bkpt enable=1, disable=0
 
  CTRL(8)  : FAST/SLOW

  CTRL(13-12) : CPU Select

  CTRL(14) : NoSup

  STAT(0)  : DSTOP : Stop=1, Run=0
  STAT(1)  :
  STAT(2)  :
  STAT(3)  : PSR.S
  STAT(4)  : PSR.PS
  STAT(5)  : PSR.ET
  STAT(6)  : PSR.EF
  STAT(7)  :

  sel<=control(13 DOWNTO 12);
                                   -- Arrêt périphériques
  debug_t.ena   <='1';
  debug_t.stop  <=stop;
  debug_t.run   <=run;
  debug_t.vazy  <=vazy;
  debug_t.op    <=opcode;
  debug_t.code  <=work.plomb_pack.PB_OK;
  debug_t.step  <=step; -- control(4) : step
  debug_t.ppc   <=control(5);
  debug_t.opt   <=control(15 DOWNTO 12);
     OPT(0) : Nosup
  debug_t.ib    <=ibrk;
  debug_t.db    <=dbrk;
  debug_t.ib_ena<=control(6);           -- Point d'arrêt instructions
  debug_t.db_ena<=control(7);           -- Point d'arrêt données
  aux_c         <=control(31 DOWNTO 16);

  debug_c       <=control(11 DOWNTO 8);

*/

#define CTRL_STOP (1)
#define CTRL_RESET (4)
#define CTRL_STOPA (8)

#define CTRL_PPC   (32)
#define CTRL_IBRK  (64)
#define CTRL_DBRK  (128)
#define CTRL_FAST  (256)
#define CTRL_NOSUP (1<<12)

#define CTRL_OPT0  (1<<14)
#define CTRL_OPT1  (1<<15)

/* R0=0
   R1  ...  R7 = G1 ... G7
   R8  ... R15 = O0 ... O7
   R16 ... R23 = L0 ... L7
   R24 ... R31 = I0 ... I7 */

#define OR_R0_R0_R0  (0x80100000)       // OR R0,R0,R0
#define OR_R1_R1_R1  (0x80100000 | 1 | 1 << 14 | 1 << 25)       // OR R1,R1,R1
#define OR_R2_R2_R2  (0x80100000 | 2 | 2 << 14 | 2 << 25)       // OR R2,R2,R2
#define OR_R3_R3_R3  (0x80100000 | 3 | 3 << 14 | 3 << 25)       // OR R3,R3,R3

#define OR_R0_Imm_R0 (0x80102000)       // OR R0,SImm13,R0
#define SETHI_Imm_R0 (0x01000000)       // SETHI Imm22,R0
#define LD_R0_Imm_R0 (0xC0002000)       // LD [R0+SImm13],R0

#define STDA_R0_R0_R0  (0xC0B80000)     // STDA (00) R0,[R0+R0]
#define STA_R0_R0_R0   (0xC0A00000)     // STA (00) R0,[R0+R0]
#define STHA_R0_R0_R0  (0xC0B00000)     // STHA (00) R0,[R0+R0]
#define STBA_R0_R0_R0  (0xC0A80000)     // STBA (00) R0,[R0+R0]

#define LDDA_R0_R0_R0  (0xC0980000)     // LDDA (00) [R0+R0],R0
#define LDA_R0_R0_R0   (0xC0800000)     // LDA (00) [R0+R0],R0
#define LDUHA_R0_R0_R0 (0xC0900000)     // LDUHA (00) [R0+R0],R0
#define LDUBA_R0_R0_R0 (0xC0880000)     // LDUBA (00) [R0+R0],R0


#define ST_R0_R0_R0  (0xC0200000)       // ST R0,[R0+R0]
#define ST_R0_R0_Imm (0xC0202000)       // ST R0,[R0+SImm13]
#define JMPL_R0_R0   (0x81C00000)       // JMPL R0,R0

#define RDPSR_R0     (0x81480000)       // RDPSR R0
#define RDTBR_R0     (0x81580000)       // RDTBR R0
#define RDWIM_R0     (0x81500000)       // RDWIM R0
#define RDY_R0       (0x81400000)       // RDY R0

#define WRPSR_R0     (0x81880000)       // WRPSR R0
#define WRTBR_R0     (0x81980000)       // WRTBR R0
#define WRWIM_R0     (0x81900000)       // WRWIM R0
#define WRY_R0       (0x81800000)       // WRY R0

#define STFA_F0_R1   (0xC1A00081)     // STFA F0,[R0+R1]_04
//11_00000_110100_00000_0_00000100_00001 STFA F0,[R0+R1] 04

#define STFSRA_R1    (0xC1A80081)     // STFSRA [R0+R1]_04
//11_00000_110101_00000_0_00000100_00001 STFSRA [R0+R1] 04

#define LDFA_F0_R1   (0xC1800081)     // LDFA [R0+R1]_04
//11_00000_110000_00000_0_00000100_00001 LDFA [R0+R1]_04

#define STDFQA_R1   (0xC1B00081)     // STDFQA [R0+R1]_04

#define LDFSRA_R1   (0xC1880081)     // LDFSRA [R0+R1]_04


// Initialisation
void dbg_init()
{
    ctrlc = 0; // Shared CTRL[31:8]
    ctrl[0] = 0; // Per-CPU CTRL[7:0]
    ctrl[1] = 0;
    ctrl[2] = 0;
    ctrl[3] = 0;
    cpu = 0;
    dbg_write_ctrl(0x1000);
    dbg_write_ctrl(0x2000);
    dbg_write_ctrl(0x3000);
    dbg_write_ctrl(0x0000);
}

//-------------------------------------------------------------------------

void dbg_selcpu(int n)
{
    cpu = n&3;
    ctrlc = (ctrlc & ~0x3000) | (cpu<<12);
    dbg_write_ctrl(ctrlc | ctrl[cpu]);
}

uint dbg_getcpu()
{
    return cpu;
}

uint dbg_cpus()
{
    return (dbg_read_status() >> 12) & 15;
}


/*
Prologue :
  JMPL   R0,R0 (MPC)         --> Sauve_PC
  JMPL   R0,R0               --> Sauve_nPC
  OR     R1,R1,R1            --> Sauve_R1
  OR     R2,R2,R2            --> Sauve_R2
  OR     R3,R3,R3            --> Sauve_R3

Epilogue :
  SETHI  Hi(Sauve_R2),R2
  OR     R2,Lo(Sauve_R2),R2  --> Restore R2

  SETHI  Hi(Sauve_PC),R1
  OR     R1,Lo(Sauve_PC),R1


  JMPL   R1,R0 (MPC,PPC)     --> Empile PC, restore PC

  SETHI  Hi(Sauve_nPC),R1
  OR     R1,Lo(Sauve_nPC),R1

  JMPL   R1,R0 (MPC,PPC)     --> Empile nPC, restore nPC

  SETHI  Hi(Sauve_R1),R1
  OR     R1,Lo(Sauve_R1),R1  --> Restore R1
*/
static void dbg_write_r1(uint32_t v);

// Prologue débug
void dbg_prologue()
{
    cop_pc[cpu] = dbg_read_pc();
    cop_npc[cpu] = dbg_read_npc();
    dbg_write_op(OR_R1_R1_R1);      // OR R1,R1,R1
    cop_r1[cpu] = dbg_read_data();
    dbg_write_op(OR_R2_R2_R2);      // OR R2,R2,R2
    cop_r2[cpu] = dbg_read_data();
    dbg_write_op(OR_R3_R3_R3);      // OR R3,R3,R3
    cop_r3[cpu] = dbg_read_data();
    dbg_write_op(RDPSR_R0 | 1 << 25);  // RDPSR R1
    cop_psr[cpu] = dbg_read_data();
//  dbg_write_r1(cop_psr[cpu] | 0x80);                   // Positionne PSR.S
//  dbg_write_op(WRPSR_R0 | 1);                     // WRPSR R1
}

// Epilogue débug
void dbg_epilogue()
{
    dbg_write_r1(cop_psr[cpu]);      // Positionne PSR.S
    dbg_write_op(WRPSR_R0 | 1); // WRPSR R1

    dbg_write_op(SETHI_Imm_R0 | (3 << 25) | (cop_r3[cpu] >> 10));    // SETHI cop_r3,R3
    dbg_write_op(OR_R0_Imm_R0 | (3 << 25) | (3 << 14) | (cop_r3[cpu] & 0x3FF));      // OR    R3,cop_r3,R3

    dbg_write_op(SETHI_Imm_R0 | (2 << 25) | (cop_r2[cpu] >> 10));    // SETHI cop_r2,R2
    dbg_write_op(OR_R0_Imm_R0 | (2 << 25) | (2 << 14) | (cop_r2[cpu] & 0x3FF));      // OR    R2,cop_r2,R2

    dbg_write_op(SETHI_Imm_R0 | (1 << 25) | (cop_pc[cpu] >> 10));    // SETHI cop_pc,R1
    dbg_write_op(OR_R0_Imm_R0 | (1 << 25) | (1 << 14) | (cop_pc[cpu] & 0x3FF));      // OR    R1,cop_pc[cpu],R1

    ctrlc = ctrlc | CTRL_PPC;
    dbg_write_ctrl(ctrlc | ctrl[cpu]);
    dbg_write_op(JMPL_R0_R0 | (1 << 14));       // JMPL R1,R0 [PPC]
    ctrlc = ctrlc & ~CTRL_PPC;
    dbg_write_ctrl(ctrlc | ctrl[cpu]);
    dbg_write_op(SETHI_Imm_R0 | (1 << 25) | (cop_npc[cpu] >> 10));   // SETHI cop_npc,R1
    dbg_write_op(OR_R0_Imm_R0 | (1 << 25) | (1 << 14) | (cop_npc[cpu] & 0x3FF));     // OR    R1,cop_npc,R1

    ctrlc = ctrlc | CTRL_PPC;
    dbg_write_ctrl(ctrlc | ctrl[cpu]);
    dbg_write_op(JMPL_R0_R0 | (1 << 14));       // JMPL R1,R0 [PPC]
    ctrlc = ctrlc & ~CTRL_PPC;
    dbg_write_ctrl(ctrlc | ctrl[cpu]);

    dbg_write_op(SETHI_Imm_R0 | (1 << 25) | (cop_r1[cpu] >> 10));    // SETHI cop_r1,R1
    dbg_write_op(OR_R0_Imm_R0 | (1 << 25) | (1 << 14) | (cop_r1[cpu] & 0x3FF));      // OR    R1,cop_r1,R1
}

//-------------------------------------------------------------------------
// Reset total
int dbg_hreset()
{
    sp_purge();
    ctrlc = ctrlc | CTRL_RESET;
    dbg_write_ctrl(ctrlc | ctrl[cpu]);
    ctrlc = ctrlc & ~CTRL_RESET;
    dbg_write_ctrl(ctrlc | ctrl[cpu]);
    return 0;
}

//Arrêt processeur
int dbg_stop()
{
    printf ("STOP :Purge\n");
    sp_purge();
    ctrl[cpu] = ctrl[cpu] | CTRL_STOP;
    ctrlc = ctrlc | CTRL_STOPA;
    printf ("STOP :WriteCtrl\n");
    dbg_write_ctrl(ctrlc | ctrl[cpu]);
    printf ("STOP :Prologeue\n");
    dbg_prologue();
    printf ("STOP :Fin\n");
    return 0;
}

// Suite à un point d'arrêt, le proc s'est déjà arrêté.
//Il faut rearmer le bit STOP pour pouvoir redémarrer plus tard...
int dbg_stop_deja()
{
    ctrl[cpu] = ctrl[cpu] | CTRL_STOP;
    dbg_write_ctrl(ctrlc | ctrl[cpu]);
}

//Démarrage processeur
int dbg_run()
{
    dbg_epilogue();
    ctrl[cpu] = ctrl[cpu] & ~CTRL_STOP;
    dbg_write_ctrl(ctrlc | ctrl[cpu]);
    sp_purge();
    return 0;
}

void dbg_nosup(int nosup)
{
    if (nosup)
        ctrlc = ctrlc | CTRL_NOSUP;
    else
        ctrlc = ctrlc & ~CTRL_NOSUP;
    dbg_write_ctrl(ctrlc | ctrl[cpu]);
}

void dbg_opt0(int v)
{
    if (v)
        ctrlc = ctrlc | CTRL_OPT0;
    else
        ctrlc = ctrlc & ~CTRL_OPT0;
    dbg_write_ctrl(ctrlc | ctrl[cpu]);
}

void dbg_opt1(int v)
{
    if (v)
        ctrlc = ctrlc | CTRL_OPT1;
    else
        ctrlc = ctrlc & ~CTRL_OPT1;
    dbg_write_ctrl(ctrlc | ctrl[cpu]);
}

// Contrôle points d'arrêt
void dbg_ibrk(int ib)
{
    if (ib)
        ctrl[cpu] = ctrl[cpu] | CTRL_IBRK;
    else
        ctrl[cpu] = ctrl[cpu] & ~CTRL_IBRK;
    dbg_write_ctrl(ctrlc | ctrl[cpu]);
}

void dbg_dbrk(int db)
{
    if (db)
        ctrl[cpu] = ctrl[cpu] | CTRL_DBRK;
    else
        ctrl[cpu] = ctrl[cpu] & ~CTRL_DBRK;
    dbg_write_ctrl(ctrlc | ctrl[cpu]);
}

int dbg_ibrk_stat()
{
    return (ctrl[cpu] & CTRL_IBRK);
}

int dbg_dbrk_stat()
{
    return (ctrl[cpu] & CTRL_DBRK);
}

void dbg_uspeed(int v)
{
    if (v)
        ctrlc = ctrlc | CTRL_FAST;
    else
        ctrlc = ctrlc & ~CTRL_FAST;
    dbg_write_ctrl(ctrlc | ctrl[cpu]);
    sp_freq(v);
}

uint32_t dbg_read_reg(int n)
{
    if (n == 1)
        return cop_r1[cpu];
    if (n == 2)
        return cop_r2[cpu];
    if (n == 3)
        return cop_r3[cpu];
    dbg_write_op(OR_R0_R0_R0 | n | n << 14 | n << 25);      // OR Rn,Rn,Rn
    return dbg_read_data();
}

void dbg_write_reg(int n, uint32_t v)
{
    if (n == 1) {
        cop_r1[cpu] = v;
        return;
    }
    if (n == 2) {
        cop_r2[cpu] = v;
        return;
    }
    if (n == 3) {
        cop_r3[cpu] = v;
        return;
    }
    dbg_write_op(SETHI_Imm_R0 | (n << 25) | (v >> 10)); // SETHI Imm22,Rn
    dbg_write_op(OR_R0_Imm_R0 | (n << 25) | (n << 14) | (v & 0x3FF));   // OR    Rn,Imm,Rn
}

static void dbg_write_r1(uint32_t v)
{
    if ((v&0x3FF)==0)
        dbg_write_op(SETHI_Imm_R0 | (1 << 25) | (v >> 10)); // SETHI Imm22,R1
    else if ((v&&0xFFFFF000)==0)
        dbg_write_op(OR_R0_Imm_R0 | (1 << 25) | (0 << 14) | (v & 0xFFF));   // OR    R0,Imm,R1
    else {
        dbg_write_op(SETHI_Imm_R0 | (1 << 25) | (v >> 10)); // SETHI Imm22,R1
        dbg_write_op(OR_R0_Imm_R0 | (1 << 25) | (1 << 14) | (v & 0x3FF));   // OR    R1,Imm,R1
    }
}

static void dbg_write_r2(uint32_t v)
{
    if ((v&0x3FF)==0)
        dbg_write_op(SETHI_Imm_R0 | (2 << 25) | (v >> 10)); // SETHI Imm22,R2
    else if ((v&&0xFFFFF000)==0)
        dbg_write_op(OR_R0_Imm_R0 | (2 << 25) | (0 << 14) | (v & 0xFFF));   // OR    R0,Imm,R2
    else {
        dbg_write_op(SETHI_Imm_R0 | (2 << 25) | (v >> 10)); // SETHI Imm22,R2
        dbg_write_op(OR_R0_Imm_R0 | (2 << 25) | (2 << 14) | (v & 0x3FF));   // OR    R2,Imm,R2
    }
}

static void dbg_write_r3(uint32_t v)
{
    if ((v&0x3FF)==0)
        dbg_write_op(SETHI_Imm_R0 | (3 << 25) | (v >> 10)); // SETHI Imm22,R3
    else if ((v&&0xFFFFF000)==0)
        dbg_write_op(OR_R0_Imm_R0 | (3 << 25) | (0 << 14) | (v & 0xFFF));   // OR    R0,Imm,R3
    else {
        dbg_write_op(SETHI_Imm_R0 | (3 << 25) | (v >> 10)); // SETHI Imm22,R3
        dbg_write_op(OR_R0_Imm_R0 | (3 << 25) | (3 << 14) | (v & 0x3FF));   // OR    R3,Imm,R3
    }
}

uint32_t dbg_read_freg(int n)
{
    dbg_write_r1(0xC00);
    dbg_write_op(STFA_F0_R1 | (n << 25));       // STFA F0,[R0+R1]_04
    return dbg_read_mmureg(0xC00);
}

void dbg_write_freg(int n,uint32_t v)
{
    dbg_write_mmureg(0xC00,v);
    dbg_write_r1(0xC00);
    dbg_write_op(LDFA_F0_R1 | (n << 25));       // LDFA F0,[R0+R1]_04
}

void dbg_fpop(uint32_t opf,int rs1,int rs2,int rd)
{
    dbg_write_op(0x81A00000 | (rd << 25) | (rs1 << 14) | (rs2 << 0) | (opf << 5));
}

uint32_t dbg_read_fsr()
{
    dbg_write_r1(0xC00);
    dbg_write_op(STFSRA_R1);       // STFSRA [R0+R1]_04
    return dbg_read_mmureg(0xC00);
}

void dbg_write_fsr(uint32_t v)
{
    dbg_write_mmureg(0xC00,v);
    dbg_write_r1(0xC00);
    dbg_write_op(LDFSRA_R1); // LDFSRA [R0+R1]_04
}

uint32_t dbg_read_dfq()
{
    dbg_write_mmureg(0xC00,0);
    dbg_write_r1(0xC00);
    dbg_write_op(STDFQA_R1);       // STDFQA [R0+R1]_04
    return dbg_read_mmureg(0xC00);
}

uint32_t dbg_read_cop_psr()
{
    return cop_psr[cpu];
}

void dbg_write_cop_psr(uint32_t v)
{
    cop_psr[cpu] = v;
}

uint32_t dbg_read_cop_pc()
{
    return cop_pc[cpu];
}

uint32_t dbg_read_cop_npc()
{
    return cop_npc[cpu];
}

void dbg_write_cop_pc(uint32_t pc)
{
    cop_pc[cpu] = pc;
}

void dbg_write_cop_npc(uint32_t npc)
{
    cop_npc[cpu] = npc;
}

uint32_t dbg_read_tbr()
{
    dbg_write_op(RDTBR_R0 | 1 << 25);   // RDTBR R1
    dbg_write_op(OR_R1_R1_R1);          // OR R1,R1,R1
    return dbg_read_data();
}

void dbg_write_tbr(uint32_t v)
{
    dbg_write_r1(v);
    dbg_write_op(WRTBR_R0 | 1 << 14);   // WRPSR R1
}

uint32_t dbg_read_psr()
{
    dbg_write_op(RDPSR_R0 | 1 << 25);   // RDPSR R1
    dbg_write_op(OR_R1_R1_R1);          // OR R1,R1,R1
    return dbg_read_data();
}

void dbg_write_psr(uint32_t v)
{
    dbg_write_r1(v);
    dbg_write_op(WRPSR_R0 | 1 << 14);   // WRPSR R1
}

uint32_t dbg_read_wim()
{
    dbg_write_op(RDWIM_R0 | 1 << 25);   // RDWIM R1
    dbg_write_op(OR_R1_R1_R1);          // OR R1,R1,R1
    return dbg_read_data();
}

void dbg_write_wim(uint32_t v)
{
    dbg_write_r1(v);
    dbg_write_op(WRWIM_R0 | 1 << 14);   // WRWIM R1
}

uint32_t dbg_read_ry()
{
    dbg_write_op(RDY_R0 | 1 << 25);     // RDY R1
    dbg_write_op(OR_R1_R1_R1);          // OR R1,R1,R1
    return dbg_read_data();
}

void dbg_write_ry(uint32_t v)
{
    dbg_write_r1(v);
    dbg_write_op(WRY_R0 | 1 << 14);     // WRY R1
}

//-------------------------------------------------------------------------

#define ASI_RESERVED                           0x00
//#define ASI_UNASSIGNED_01                      0x01
//#define ASI_UNASSIGNED_02                      0x02
#define ASI_MMU_FLUSH_PROBE                    0x03 //MMU
#define ASI_MMU_REGISTER                       0x04 //MMU
#define ASI_MMU_DIAGNOSTIC_FOR_INSTRUCTION_TLB 0x05 //MMU
#define ASI_MMU_DIAGNOSTIC_FOR_DATA_TLB        0x06 //MMU
#define ASI_MMU_DIAGNOSTIC_IO_TLB              0x07 //MMU
#define ASI_USER_INSTRUCTION                   0x08 //CPU
#define ASI_SUPER_INSTRUCTION                  0x09 //CPU
#define ASI_USER_DATA                          0x0A //CPU
#define ASI_SUPER_DATA                         0x0B //CPU
#define ASI_CACHE_TAG_INSTRUCTION              0x0C //CACHE
#define ASI_CACHE_DATA_INSTRUCTION             0x0D //CACHE
#define ASI_CACHE_TAG_DATA                     0x0E //CACHE
#define ASI_CACHE_DATA_DATA                    0x0F //CACHE
#define ASI_CACHE_FLUSH_LINE_COMBINED_PAGE     0x10 //CACHE
#define ASI_CACHE_FLUSH_LINE_COMBINED_SEGMENT  0x11 //CACHE
#define ASI_CACHE_FLUSH_LINE_COMBINED_REGION   0x12 //CACHE
#define ASI_CACHE_FLUSH_LINE_COMBINED_CONTEXT  0x13 //CACHE
#define ASI_CACHE_FLUSH_LINE_COMBINED_USER     0x14 //CACHE
#define ASI_CACHE_FLUSH_LINE_COMBINED_ANY      0x15 //#CACHE
//#define ASI_RESERVED_15                        0x15
//#define ASI_RESERVED_16                        0x16
#define ASI_BLOCK_COPY                         0x17 //CACHE
#define ASI_CACHE_FLUSH_LINE_INSTRUCTION_PAGE  0x18 //CACHE
#define ASI_CACHE_FLUSH_LINE_INSTRUCTION_SEGMENT 0x19 //CACHE
#define ASI_CACHE_FLUSH_LINE_INSTRUCTION_REGION  0x1A //CACHE
#define ASI_CACHE_FLUSH_LINE_INSTRUCTION_CONTEXT 0x1B //CACHE
#define ASI_CACHE_FLUSH_LINE_INSTRUCTION_USER  0x1C //CACHE
#define ASI_CACHE_FLUSH_LINE_INSTRUCTION_ANY   0x1D //#CACHE
//#define ASI_RESERVED_1D                        0x1D
//#define ASI_RESERVED_1E                        0x1E
#define ASI_BLOCK_FILL                         0x1F //CACHE
#define ASI_MMU_PHYSICAL                       0x20 //MMU

uint8_t dbg_read_asimem8(uint8_t asi, uint32_t a)
{
    dbg_write_r1(a);
    dbg_write_op(LDUBA_R0_R0_R0 | 1 | 1 << 25 | asi << 5); // LDUBA [R1],R1
    dbg_write_op(OR_R1_R1_R1);                             // OR R1,R1,R1
    return dbg_read_data();
}

uint16_t dbg_read_asimem16(uint8_t asi, uint32_t a)
{
    dbg_write_r1(a);
    dbg_write_op(LDUHA_R0_R0_R0 | 1 | 1 << 25 | asi << 5); // LDUHA [R1],R1
    dbg_write_op(OR_R1_R1_R1);                             // OR R1,R1,R1
    return dbg_read_data();
}

uint32_t dbg_read_asimem32(uint8_t asi, uint32_t a)
{
    dbg_write_r1(a);
    dbg_write_op(LDA_R0_R0_R0 | 1 | 2 << 25 | asi << 5);    // LDA (asi) [R1],R2
    dbg_write_op(OR_R2_R2_R2);                              // OR R2,R2,R2
    return dbg_read_data();
}

uint64_t dbg_read_asimem64(uint8_t asi, uint32_t a)
{
    uint64_t v;
    dbg_write_r1(a);
    dbg_write_op(LDDA_R0_R0_R0 | 1 | 2 << 25 | asi << 5);  // LDA [R1],R2
    dbg_write_op(OR_R2_R2_R2);                             // OR R2,R2,R2
    dbg_read_c(DL_CPU | CPU_RD_DATA);
    dbg_write_op(OR_R3_R3_R3);                             // OR R3,R3,R3
    dbg_read_c(DL_CPU | CPU_RD_DATA);
    v = dbg_read_d();
    v = v << 32 | dbg_read_d();
    return v;
}

void dbg_read_asimem(uint8_t asi, uint32_t a, void *p, unsigned len)
{
    uint32_t v, xlen;
    uint32_t aal,  off, lal;
    unsigned i, j, k;

    aal = a & ~7;
    off = a & 7;
    lal = (len +1) & ~7;

    for (k = 0; k < lal; k += 256) {
        xlen = len-k;
        if (xlen > 256)
            xlen = 256;
        for (i = 0; i < xlen; i += 8) {
            dbg_write_r1(aal + i + k);
            dbg_write_op(LDDA_R0_R0_R0 | 1 | 2 << 25 | asi << 5); // LDA [R1],R2
            dbg_write_op(OR_R2_R2_R2);                            // OR R2,R2,R2
            dbg_read_c(DL_CPU | CPU_RD_DATA);
            dbg_write_op(OR_R3_R3_R3);                            // OR R3,R3,R3
            dbg_read_c(DL_CPU | CPU_RD_DATA);
        }
        for (i = 0; i < xlen; i += 4) {
            v = dbg_read_d();
            for (j = i; (j < i + 4) && (j < xlen); j++) {
                if (j + k < off) continue;
                if (j + k > len) continue;
                ((char *)p)[j + k - off] = v >> 24;
//                ((char *)p)[j + k] = v >> 24;
	            v <<= 8;
            }
	    }
    }
}

void dbg_write_asimem8(uint8_t asi, uint32_t a, uint8_t v)
{
    dbg_write_r1(a);
    dbg_write_r2(v);
    dbg_write_op(STBA_R0_R0_R0 | 1 | 2 << 25 | asi << 5);  // STBA R2,[R1]
}

void dbg_write_asimem16(uint8_t asi, uint32_t a, uint16_t v)
{
    dbg_write_r1(a);
    dbg_write_r2(v);
    dbg_write_op(STHA_R0_R0_R0 | 1 | 2 << 25 | asi << 5);  // STHA R2,[R1]
}
void dbg_write_asimem32(uint8_t asi,uint32_t a, uint32_t v)
{
    dbg_write_r1(a);
    dbg_write_r2(v);
    dbg_write_op(STA_R0_R0_R0 | 1 | (2 << 25) | asi << 5); // STA (asi) R2,[R1]
}
void dbg_write_asimem64(uint8_t asi,uint32_t a, uint64_t v)
{
    dbg_write_r1(a);
    dbg_write_r2(v>>32LL);
    dbg_write_r3(v);
    dbg_write_op(STDA_R0_R0_R0 | 1 | (2 << 25) | asi << 5); // STDA (asi) R2,[R1]
}

//------------------------------------------------------------------------------
inline uint8_t dbg_read_pmem8(uint64_t a)
{
    return dbg_read_asimem8(ASI_MMU_PHYSICAL + ((a >> 32) & 15), a);
}

inline uint16_t dbg_read_pmem16(uint64_t a)
{
    return dbg_read_asimem16(ASI_MMU_PHYSICAL + ((a >> 32) & 15), a);
}

inline uint32_t dbg_read_pmem32(uint64_t a)
{
    return dbg_read_asimem32(ASI_MMU_PHYSICAL + ((a >> 32) & 15), a);
}

inline uint64_t dbg_read_pmem64(uint64_t a)
{
    return dbg_read_asimem64(ASI_MMU_PHYSICAL + ((a >> 32) & 15), a);
}

inline void dbg_read_pmem(uint64_t a, void *p, unsigned len)
{
    return dbg_read_asimem(ASI_MMU_PHYSICAL + ((a >> 32) & 15), a, p, len);
}

inline void dbg_write_pmem8(uint64_t a, uint8_t v)
{
    dbg_write_asimem8(ASI_MMU_PHYSICAL + ((a >> 32) & 15), a, v);
}

inline void dbg_write_pmem16(uint64_t a, uint16_t v)
{
    dbg_write_asimem16(ASI_MMU_PHYSICAL + ((a >> 32) & 15), a, v);
}

inline void dbg_write_pmem32(uint64_t a, uint32_t v)
{
    dbg_write_asimem32(ASI_MMU_PHYSICAL + ((a >> 32) & 15), a, v);
}

inline void dbg_write_pmem64(uint64_t a, uint64_t v)
{
    dbg_write_asimem64(ASI_MMU_PHYSICAL + ((a >> 32) & 15), a, v);
}

//--------------------------------------------------------------------------------
inline uint8_t dbg_read_vmem8(uint32_t a)
{
    return dbg_read_asimem8(ASI_SUPER_DATA, a);
}

inline uint16_t dbg_read_vmem16(uint32_t a)
{
    return dbg_read_asimem16(ASI_SUPER_DATA, a);
}

inline uint32_t dbg_read_vmem32(uint32_t a)
{
    return dbg_read_asimem32(ASI_SUPER_DATA, a);
}

inline uint32_t dbg_read_vmem32i(uint32_t a)
{
    return dbg_read_asimem32(ASI_SUPER_INSTRUCTION,a);
}

inline void dbg_read_vmem(uint32_t a, void *p, unsigned len)
{
    return dbg_read_asimem(ASI_SUPER_DATA, a, p, len);
}

inline void dbg_write_vmem8(uint32_t a, uint8_t v)
{
    dbg_write_asimem8(ASI_SUPER_DATA, a, v);
}

inline void dbg_write_vmem16(uint32_t a, uint16_t v)
{
    dbg_write_asimem16(ASI_SUPER_DATA, a, v);
}

inline void dbg_write_vmem32(uint32_t a, uint32_t v)
{
    dbg_write_asimem32(ASI_SUPER_DATA, a, v);
}

inline void dbg_write_vmem32i(uint32_t a, uint32_t v)
{
    dbg_write_asimem32(ASI_SUPER_INSTRUCTION,a,v);
}

//--------------------------------------------------------------------------------
// MMU Regs & Probe
inline uint32_t dbg_mmu_probe(uint32_t a)
{
    return dbg_read_asimem32(ASI_MMU_FLUSH_PROBE,a);
}

uint32_t dbg_read_mmureg(uint32_t a)
{
    return dbg_read_asimem32(ASI_MMU_REGISTER, a);
}

void dbg_write_mmureg(uint32_t a, uint32_t v)
{
    dbg_write_asimem32(ASI_MMU_REGISTER,a ,v);
}

//--------------------------------------------------------------------------------
// Cache flush
void dbg_flush(uint32_t a)
{
    dbg_write_asimem32(ASI_CACHE_FLUSH_LINE_COMBINED_ANY, a, 0);
}

uint32_t dbg_read_dtag(uint32_t a)
{
    return dbg_read_asimem32(ASI_CACHE_TAG_DATA, a);
}

void dbg_write_dtag(uint32_t a, uint32_t v)
{
    dbg_write_asimem32(ASI_CACHE_TAG_DATA, a, v);
}

// Cache instruction tags
uint32_t dbg_read_itag(uint32_t a)
{
    return dbg_read_asimem32(ASI_CACHE_TAG_INSTRUCTION, a);
}

void dbg_write_itag(uint32_t a, uint32_t v)
{
    dbg_write_asimem32(ASI_CACHE_TAG_INSTRUCTION, a ,v);
}

//-------------------------------------------------------------------------

#define TRACE_WR_START (0x8)
#define TRACE_WR_SEL   (0xA)
#define TRACE_WR_CONF  (0xB)
#define TRACE_WR_ADDR  (0xC)

#define TRACE_RD_DATA  (0x1)
#define TRACE_RD_STAT  (0x2)
#define TRACE_RD_PARM  (0x3)

void dbg_trace_addr(uint8_t a,uint32_t ad,uint32_t adm,uint8_t s,uint8_t sm)
{
    dbg_read((a<<4) | TRACE_RD_STAT);
    dbg_write((a<<4) | TRACE_WR_ADDR,ad);
    dbg_write((a<<4) | TRACE_WR_ADDR,adm);
    dbg_write((a<<4) | TRACE_WR_ADDR,s | (sm<<16));
}

void dbg_trace_conf(uint8_t a,uint32_t v)
{
    dbg_write((a<<4) | TRACE_WR_CONF,v);
}

void dbg_trace_start(uint8_t a,uint32_t v)
{
    dbg_write((a<<4) | TRACE_WR_START,v);
}
uint32_t dbg_trace_stat(uint8_t a)
{
    return dbg_read((a<<4) | TRACE_RD_STAT);
}

uint32_t dbg_trace_parm(uint8_t a)
{
    return dbg_read((a<<4) | TRACE_RD_PARM);
}

void dbg_trace_read(uint8_t a,uint8_t p,uint32_t tab[],uint32_t len)
{
    
    dbg_write((a<<4) | TRACE_WR_SEL,p);
    
    for (int i=0;i<(len/2);i++) {
        for (int j=0;j<2;j++) {
            dbg_read_c((a<<4) | TRACE_RD_DATA);
        }
        for (int j=0;j<2;j++) {
            tab[i*2+j]=dbg_read_d();
        }
    }
    for (int i=(len/2)*2;i<len;i++) {
        tab[i]=dbg_read((a<<4) | TRACE_RD_DATA);
    }
    
    /*
    for (int i=0;i<len;i++) {
        tab[i]=dbg_read((a<<4) | TRACE_RD_DATA);
    }
    */
    
}

//-------------------------------------------------------------------------

#define SCSI_WR_CONF  (0x8)
#define SCSI_RD_CONF  (0x0)
#define SCSI_RD_PTR   (0x1)
#define SCSI_RD_DATA0 (0x2)
#define SCSI_RD_DATA1 (0x3)

static uint32_t scsi_conf;

void dbg_scsi_setup(uint8_t a,uint32_t v)
{
    scsi_conf=v;
    dbg_write((a<<4) | SCSI_WR_CONF,v);
}

uint32_t dbg_scsi_conf(uint8_t a)
{
    return dbg_read((a<<4) | SCSI_RD_CONF);
}

uint32_t dbg_scsi_ptr(uint8_t a)
{
    return dbg_read((a<<4) | SCSI_RD_PTR);
}

void dbg_scsi_read(uint8_t a,uint64_t tab[],uint32_t len)
{
    dbg_write((a<<4) | TRACE_WR_CONF,scsi_conf | 2);
    /*
    for (int i=0;i<len;i++) {
            if ((i&256)==0) printf ("(%4i)\n",i);
            tab[i]=dbg_read((a<<4) | SCSI_RD_DATA0);
            tab[i]|=(uint64_t)dbg_read((a<<4) | SCSI_RD_DATA1)<<32LL;
    }
    */
    /*
    for (int i=0;i<len/2;i++) {
            if ((i&256)==0) printf ("(%4i)\n",i);
            dbg_read_c((a<<4) | SCSI_RD_DATA0);
            dbg_read_c((a<<4) | SCSI_RD_DATA1);
            dbg_read_c((a<<4) | SCSI_RD_DATA0);
            dbg_read_c((a<<4) | SCSI_RD_DATA1);
            
            tab[i*2]=dbg_read_d();
            tab[i*2]|=(uint64_t)dbg_read_d()<<32LL;
            tab[i*2+1]=dbg_read_d();
            tab[i*2+1]|=(uint64_t)dbg_read_d()<<32LL;
    }
    */
    for (int i=0;i<len;i++) {
            if ((i&256)==0) printf ("(%4i)\r\n",i);
            dbg_read_c((a<<4) | SCSI_RD_DATA0);
            dbg_read_c((a<<4) | SCSI_RD_DATA1);
            
            tab[i]=dbg_read_d();
            tab[i]|=(uint64_t)dbg_read_d()<<32LL;
    }
         
}
