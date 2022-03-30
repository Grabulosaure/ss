/* Debugger.
   Commandes

   DO 5/2011
*/

#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <termios.h>
#include <stdarg.h>
#include <fcntl.h>
#include <poll.h>
#include <ctype.h>

#include "lib.h"
typedef int (FUNC) (unsigned p,int argc,char *argv[]);

#define ANSI_DEFAULT "\033[0m"

#define ANSI_ROUGE "\033[31;1m"
#define ANSI_VERT  "\033[32;1m"
#define ANSI_BLEU  "\033[34;1m"
#define ANSI_JAUNE "\033[33;1m"

#define ANSI_BACK "\033[D \033[D"

#define MMM (65536L*65536L)
#define AHI(x) ((uint32_t)((x) >> 32))
#define ALO(x) ((uint32_t)((x) & 0xFFFFFFFF))


#define MMUREG_CONTROL 0x000
#define MMUREG_CTPR    0x100
#define MMUREG_CTXR    0x200
#define MMUREG_FSTAT   0xB00
#define MMUREG_FADR    0x400
#define MMUREG_TMP     0xC00
#define MMUREG_SYSCONF 0xD00
#define MMUREG_ALO0    0xE00
#define MMUREG_AHI0    0xF00
#define MMUREG_ALO1    0x1E00
#define MMUREG_AHI1    0x1F00
#define MMUREG_ALO2    0x2E00
#define MMUREG_AHI2    0x2F00

#define MMUREG_ACM     0x1C00
#define MMUREG_ACP     0x2C00
#define MMUREG_ACO     0x3C00

char *FCCS[] = { "'00 ='", "'01 <'", "'10 >'", "'11 U'" };

char *TRAPTXTS[] = { "Reset",   //0
    "Instruction Access Exception",     //1
    "Illegal Instruction",      //2
    "Privilegied Instruction",  //3
    "FP Disabled",              //4
    "Window Overflow",          //5
    "Window Underflow",         //6
    "Address not aligned",      //7
    "FP Exception",             //8
    "Data Access Exception",    //9
    "Tag Overflow",             //10
    "Watchpoint detected",      //11
    "Trap_C",                   //12
    "Trap_D",                   //13
    "Trap_E",                   //14
    "Trap_F",                   //15
    "Trap_10",                  //16
    "Interrupt Level 1",        //17
    "Interrupt Level 2",        //18
    "Interrupt Level 3",        //19
    "Interrupt Level 4 (SCSI)", //20
    "Interrupt Level 5",        //21
    "Interrupt Level 6 (Ethernet)",     //22
    "Interrupt Level 7",        //23
    "Interrupt Level 8",        //24
    "Interrupt Level 9",        //25
    "Interrupt Level 10 (SYS Timer)",   //26
    "Interrupt Level 11",       //27
    "Interrupt Level 12 (Serial)",      //28
    "Interrupt Level 13",       //29
    "Interrupt Level 14 (CPU Timer)",   //30
    "Interrupt Level 15",       //31
    "Register access error",    //32 = 0x20
    "Instruction access error", //33 = 0x21
    "Trap_22",                  //34
    "Trap_23",                  //35
    "CP Disabled",              //36 = 0x24
    "Unimplemented flush",      //37 = 0x25
    "Trap_26",                  //38
    "Trap_27",                  //39
    "CP Exception",             //40 = 0x28
    "Data Access Error",        //41 = 0x29
    "Division by zero",         //42 = 0x2A
    "Data Store Error",         //43 = 0x2B
    "Data Access MMU Miss",     //44 = 0x2C
    "Trap_2D",                  //45
    "Trap_2E",                  //46
    "Trap_2F",                  //47
    "Trap_30",                  //48
    "Trap_31",                  //49
    "Trap_32",                  //50
    "Trap_33",                  //51
    "Trap_34",                  //52
    "Trap_35",                  //53
    "Trap_36",                  //54
    "Trap_37",                  //55
    "Trap_38",                  //56
    "Trap_39",                  //57
    "Trap_3A",                  //58
    "Trap_3B",                  //59
    "Instruction Access MMU Miss",      //60 = 0x3C
    "Trap_3D",                  //61
    "Trap_3E",                  //62
    "Trap_3F"
};                              //63


//--------------------------------------------------------------------

struct hwdef {
    uint64_t iommu_base, slavio_base;
    uint64_t intctl_base, counter_base, nvram_base, ms_kb_base, serial_base;
    uint64_t trace_base, aux1_base;
    unsigned long fd_offset, aux2_offset;
    uint64_t dma_base, esp_base, le_base;
    uint64_t tcx_base;
    int intr_ncpu;
    int mid_offset;
    int machine_id_low, machine_id_high;
};

/* SS-5 */
const struct hwdef MAP_SS5 =
    {
        .trace_base   = 0x40000000,
        .intctl_base  = 0x71e00000,
        .iommu_base   = 0x10000000,
        .tcx_base     = 0x50000000,
        .slavio_base  = 0x71000000,
        .ms_kb_base   = 0x71000000,
        .serial_base  = 0x71100000,
        .nvram_base   = 0x71200000,
        .fd_offset    = 0x00400000,
        .counter_base = 0x71d00000,
        .intr_ncpu    = 1,
        .aux1_base    = 0x71900000,
        .aux2_offset  = 0x00910000,
        .dma_base     = 0x78400000,
        .esp_base     = 0x78800000,
        .le_base      = 0x78c00000,
        .mid_offset   = 0,
        .machine_id_low = 32,
        .machine_id_high = 63
    };


/* SS-10, SS-20 */
const struct hwdef MAP_SS20 =
    {
        .trace_base   = 0xd00000000ULL,
        .intctl_base  = 0xff1400000ULL,
        .iommu_base   = 0xfe0000000ULL,
        .tcx_base     = 0xe20000000ULL,
        .slavio_base  = 0xff1000000ULL,
        .ms_kb_base   = 0xff1000000ULL,
        .serial_base  = 0xff1100000ULL,
        .nvram_base   = 0xff1200000ULL,
        .fd_offset    = 0x00700000, // 0xff1700000ULL,
        .counter_base = 0xff1300000ULL,
        .intr_ncpu    = 4,
        .aux1_base    = 0xff1800000ULL,
        .aux2_offset  = 0x00a01000, // 0xff1a01000ULL,
        .dma_base     = 0xef0400000ULL,
        .esp_base     = 0xef0800000ULL,
        .le_base      = 0xef0c00000ULL,
        .mid_offset   = 8,
        .machine_id_low = 64,
        .machine_id_high = 65
    };

struct hwdef map = 
    {
        .trace_base   = 0x40000000,
        .intctl_base  = 0x71e00000,
        .iommu_base   = 0x10000000,
        .tcx_base     = 0x50000000,
        .slavio_base  = 0x71000000,
        .ms_kb_base   = 0x71000000,
        .serial_base  = 0x71100000,
        .nvram_base   = 0x71200000,
        .fd_offset    = 0x00400000,
        .counter_base = 0x71d00000,
        .intr_ncpu    = 1,
        .aux1_base    = 0x71900000,
        .aux2_offset  = 0x00910000,
        .dma_base     = 0x78400000,
        .esp_base     = 0x78800000,
        .le_base      = 0x78c00000,
        .mid_offset   = 0,
        .machine_id_low = 32,
        .machine_id_high = 63
    };

//--------------------------------------------------------------------

struct break_t dbrk[4],ibrk[4];

//--------------------------------------------------------------------

inline char co(char c)
{
    if (c >= 0x20 && c <= 0xf0)
        return c;
    else
        return '.';
}


/*
  +nnn : Decimal
  -nnn : Decimal
  [0..F] : Hex
  Symbol

*/
int hex(char c)
{
  if (c>='0' && c<='9') return c-'0';
  if (c>='a' && c<='f') return c-'a'+10;
  if (c>='A' && c<='F') return c-'A'+10;
  return -1;
}

char *regs[] = { "G0",  "R0",  "G1",  "R1",  "G2",  "R2",  "G3",  "R3",
                 "G4",  "R4",  "G5",  "R5",  "G6",  "R6",  "G7",  "R7",
                 "O0",  "R8",  "O1",  "R9",  "O2", "R10",  "O3", "R11",
                 "O4", "R12",  "O5", "R13",  "O6", "R14",  "O7", "R15",
                 "L0", "R16",  "L1", "R17",  "L2", "R18",  "L3", "R19",
                 "L4", "R20",  "L5", "R21",  "L6", "R22",  "L7", "R23",
                 "I0", "R24",  "I1", "R25",  "I2", "R26",  "I3", "R27",
                 "I4", "R28",  "I5", "R29",  "I6", "R30",  "I7", "R31"};
                 
int parsereg(char *s,uint32_t *pv)
{
    unsigned i;
    char t[5];
    if (dbg_running())
        return -1;
    
    for (i=0;s[i] && i<5;i++) t[i]=toupper(s[i]);
    t[i]=0;
    if (i==5)
        return -1;

    for (i=0;i<64;i++) {
        if (!strcmp(t,regs[i])) {
            *pv=dbg_read_reg(i/2);
            return 0;
        }
    }

    if (!strcmp(t,"SP")) {
        *pv=dbg_read_reg(14); // = O6
        return 0;
    }
    if (!strcmp(t,"FP")) {
        *pv=dbg_read_reg(30); // = I6
        return 0;
    }
    if (!strcmp(t,"PSR")) {
        *pv=dbg_read_cop_psr();
        return 0;
    }
    if (!strcmp(t,"WIM")) {
        *pv=dbg_read_wim();
        return 0;
    }
    if (!strcmp(t,"TBR")) {
        *pv=dbg_read_tbr();
        return 0;
    }
    if (!strcmp(t,"RY")) {
        *pv=dbg_read_ry();
        return 0;
    }
    if (!strcmp(t,"PC")) {
        *pv=dbg_read_cop_pc();
        return 0;
    }
    if (!strcmp(t,"NPC")) {
        *pv=dbg_read_cop_npc();
        return 0;
    }
    if (!strcmp(t,"FSR")) {
        *pv=dbg_read_fsr();
        return 0;
    }
    
    return -1;    
    
}

int parseint64(char *s,uint64_t *pv)
{
    unsigned i;
    int ishex;
    uint64_t r=0;
    uint32_t r32;
  
    if (*s=='+') {
        // Postive decimal
        *pv=atoll(&s[1]);
        return 0;
    } else if (*s=='-') {
        // Negative decimal
        *pv=-atoll(&s[1]);
        return 0;    
    }
  
    ishex=1;
    for (i=0;s[i];i++) {
        if (hex(s[i])<0) {
            ishex=0;
            break;
        }
    }
  
    if (ishex) {
        // Hexadecimal number
        for (i=0;s[i];i++) {
            r=(r<<4LL) | (uint64_t)hex(s[i]);
        }
        *pv=r;
        return 0;
    }

    if (*s=='$') {
        // Register
        i=parsereg(&s[1],&r32);
        *pv=r32;
        return i;
    
    }
  
    // What else, maybe a symbol ?
    i=symbolt(s,&r32);
    *pv=r32;
  
    return i;
}

int parseint32(char *s,uint32_t *pv)
{
    unsigned i;
    int ishex;
    uint32_t r=0;
    if (*s=='+') {
        // Postive decimal
        *pv=atol(&s[1]);
        return 0;
    } else if (*s=='-') {
        // Negative decimal
        *pv=-atol(&s[1]);
        return 0;
    }
  
    ishex=1;
    for (i=0;s[i];i++) {
        if (hex(s[i])<0) {
            ishex=0;
            break;
        }
    }
  
    if (ishex) {
        // Hexadecimal number
        for (i=0;s[i];i++) {
            r=(r<<4L) | (uint32_t)hex(s[i]);
        }
        *pv=r;
        return 0;
    }

    if (*s=='$') {
        // Register
        return parsereg(&s[1],pv);
    }
    // What else, maybe a symbol ?
    return symbolt(s,pv);
}

//####################################################################

int testchar()
{
    fd_set rfds;
    struct timeval tv;
    int retval;
    FD_ZERO(&rfds);
    FD_SET(0, &rfds);
    tv.tv_sec = 0;
    tv.tv_usec = 0;
    retval = select(1, &rfds, NULL, NULL, &tv);

    if (retval > 0)
        return 1;
    return 0;
}


//####################################################################
void disas_pc()
{
    uint32_t opcode, pc, npc;
    char ctxt[200];
    pc = (int) dbg_read_cop_pc();
    npc = (int) dbg_read_cop_npc();

    opcode = dbg_read_vmem32(pc);
    disassemble(ctxt, opcode, pc);
    uprintf("PC = %08X     nPC = %08X\n", (int) pc, (int) npc);
    uprintf("     %08X : %08X : %s\n", (int) pc,
            (int) opcode , ctxt);
}

// Calcul de la prochaine instruction pour pas à pas
uint32_t next_pc(uint32_t op, uint32_t pc, uint32_t npc, unsigned nzvc,
                 unsigned fcc)
{
    unsigned n, z, v, c;
    unsigned e, l, g, u;
    unsigned b, a;
    unsigned cond, ann;
    int imm;
    n = (nzvc >> 3) & 1;
    z = (nzvc >> 2) & 1;
    v = (nzvc >> 1) & 1;
    c = (nzvc) & 1;
    cond = (op >> 25) & 0x0F;
    a = (op >> 29) & 1;

    imm = BIF(op, 21, 0);
    if (BIK(op, 21))
        imm = imm - (1 << 22);

    if ((op & 0xC1C00000) == 0x00800000) {
//    uprintf ("BRANCH Bicc\n");
        // Bicc
        switch (cond) {
        case 0:                // BN
            b = 0;
            break;
        case 1:                // BE
            b = z;
            break;
        case 2:                // BLE
            b = z | (n ^ v);
            break;
        case 3:                // BL
            b = n ^ v;
            break;
        case 4:                // BLEU
            b = c | z;
            break;
        case 5:                // BCS
            b = c;
            break;
        case 6:                // BNEG
            b = n;
            break;
        case 7:                // BVS
            b = v;
            break;
        case 8:                // BA
            if ((a & 1) == 1) {
                // BA,A : La prochaine instruction exécutée est la destination du saut
                return pc + imm * 4;
            }
            b = 1;
            break;
        case 9:                // BNE
            b = ~z;
            break;
        case 10:               // BG
            b = ~(z | (n ^ v));
            break;
        case 11:               // BGE
            b = ~(n ^ v);
            break;
        case 12:               // BGU
            b = ~(c | z);
            break;
        case 13:               // BCC
            b = ~c;
            break;
        case 14:               // BPOS
            b = ~n;
            break;
        case 15:               // BVC
            b = ~v;
            break;
        }
        b &= 1;
        a &= 1;
        if (b == 0 && a == 1)
            return npc + 4;
        else
            return npc;

    } else if ((op & 0xC1C00000) == 0x01800000) {
        //  FBfcc
        e = ((fcc & 3) == 0) ? 1 : 0;
        l = ((fcc & 3) == 1) ? 1 : 0;
        g = ((fcc & 3) == 2) ? 1 : 0;
        u = ((fcc & 3) == 3) ? 1 : 0;

        switch (cond) {
        case 0:                // FBN   : Never
            b = 0;
            break;
        case 1:                // FBNE  : Not Equal
            b = u | l | g;
            break;
        case 2:                // FBLG  : Less or Greater
            b = l | g;
            break;
        case 3:                // FBUL  : Unordered or Less
            b = u | l;
            break;
        case 4:                // FBL   : Less
            b = l;
            break;
        case 5:                // FBUG  : Unordered or Greater
            b = u | g;
            break;
        case 6:                // FBG   : Greater
            b = g;
            break;
        case 7:                // FBU   : Unordered
            b = u;
            break;
        case 8:                // FBA   : Always
            if ((a & 1) == 1) {
                // BA,A : La prochaine instruction exécutée est la destination du saut
                return pc + imm * 4;
            }
            b = 1;
            break;
        case 9:                // FBE   : Equal
            b = e;
            break;
        case 10:               // FBUE  : Unordered or Equal
            b = u | e;
            break;
        case 11:               // FBGE  : Greater or Equal
            b = g | e;
            break;
        case 12:               // FBUGE : Unord. or Greater or Equal
            b = u | g | e;
            break;
        case 13:               // FBLE  : Less or Equal
            b = l | e;
            break;
        case 14:               // FBULE : Unordered or Less or Equal
            b = u | l | e;
            break;
        case 15:               // FBO   : Ordered 
            b = l | g | e;
            break;
        }
        b &= 1;
        a &= 1;
        if (b == 0 && a == 1)
            return npc + 4;
        else
            return npc;
    } else {
        return npc;

    }

}

//####################################################################
int brut64=0;

int cmd_help(unsigned p,int argc,char *argv[]);
extern int fin;

int cmd_quit(unsigned p,int argc,char *argv[])
{
    done = 1;
    fin = 1;
    return 0;
}

//####################################################################
int cmd_cpu(unsigned p,int argc,char *argv[])
{
    uint32_t v;
    int t = 0;
    uint m;

    m = dbg_cpus();
    uprintf ("CPUs : %c%c%c%c\n",(m&8)?'#':'.',(m&4)?'#':'.',
             (m&2)?'#':'.',(m&1)?'#':'.');

    if (argc>1)
        t = parseint32(argv[1],&v);
    if (t || argc<2) {
        m = dbg_getcpu();
        uprintf ("CPUs : Sel : %i\n",m);
        return 0;
    }
    
    uprintf ("CPUs : Select = %i\n",v);
    if (m & (1<<v)) {
        dbg_selcpu(v);
    } else {
        uprintf ("Error\n");
    }
    return 0;
}

int cmd_uart(unsigned p,int argc,char *argv[])
{
    dbg_uspeed(p);
    return 0;
}

extern void sp_brk(int v);
int cmd_brut(unsigned p,int argc,char *argv[])
{
    brut64=p;
    return 0;
}

int cmd_stop(unsigned p,int argc,char *argv[])
{
    if (!dbg_stop())
        saved[dbg_getcpu()] = 1;
    dbg_dbrk(0);
    uprintf("\n" ANSI_ROUGE);
    disas_pc();
    return 0;
}

int cmd_run(unsigned p,int argc,char *argv[])
{
    if (dbrk[dbg_getcpu()].v) dbg_dbrk(1);
    if (!dbg_run())
        saved[dbg_getcpu()] = 0;
    return 0;
}

int cmd_runstop(unsigned p,int argc,char *argv[])
{
    if (!dbg_run())
        saved[dbg_getcpu()] = 0;
    if (!dbg_stop())
        saved[dbg_getcpu()] = 1;        
    return 0;
}

int cmd_stoprun(unsigned p,int argc,char *argv[])
{
    if (!dbg_run())
        saved[dbg_getcpu()] = 0;
    if (!dbg_stop())
        saved[dbg_getcpu()] = 1;        
    return 0;
}

// Pas à pas avec breakpoints
int cmd_step(unsigned p,int argc,char *argv[])
{
    uint32_t opcode, pc, npc, nn, stat;
    unsigned nzvc, fcc;

    stat = dbg_read_status();
    nzvc = (stat >> 8) & 15;
    fcc = (stat >> 20) & 7;
    pc = (int) dbg_read_cop_pc();
    npc = (int) dbg_read_cop_npc();

    opcode = dbg_read_vmem32(pc);
    nn = next_pc(opcode, pc, npc, nzvc, fcc);

    dbg_write_ibrk(nn);
    dbg_ibrk(1);
    dbg_dbrk(0);

    stepbrk[dbg_getcpu()] = 1;
    if (!dbg_run())
        saved[dbg_getcpu()] = 0;
    return 0;
}

// Pas à pas avec breakpoints, traverse les CALL
int cmd_stepc(unsigned p,int argc,char *argv[])
{
    uint32_t opcode, pc, npc, nn, stat;
    unsigned nzvc, fcc;

    stat = dbg_read_status();
    nzvc = (stat >> 8) & 15;
    fcc = (stat >> 20) & 7;
    pc = (int) dbg_read_cop_pc();
    npc = (int) dbg_read_cop_npc();

    opcode = dbg_read_vmem32(pc);
    nn = next_pc(opcode, pc, npc, nzvc, fcc);
    if (((opcode & 0xFFF80000) == 0x9FC00000) ||
        ((opcode & 0xC0000000) == 0x40000000)) {
        // Instruction Call
        // CALL Direct   : 01vv vvvv  vvvv vvvv  vvvv vvvv  vvvv vvvv : CALL address
        // CALL Indirect : 1001 1111  1100 0rrr  rr1i iiii  iiii iiii : JMPL address,%o7
        // CALL Indirect : 1001 1111  1100 0rrr  rr0. ....  ...r rrrr : JMPL address,%o7
        nn = pc + 8;
    }
    dbg_write_ibrk(nn);
    dbg_ibrk(1);
    dbg_dbrk(0);
    stepbrk[dbg_getcpu()] = 1;
    if (!dbg_run())
        saved[dbg_getcpu()] = 0;
    return 0;
}

int cmd_reset(unsigned p,int argc,char *argv[])
{
    dbg_write_cop_psr(0x00000080);      // S=1 ET=0
    dbg_write_wim(0x00000000);
    dbg_write_tbr(0x00000000);
    dbg_write_ry(0x00000000);
    dbg_write_cop_pc(0x00000000);
    dbg_write_cop_npc(0x00000004);
    dbg_write_mmureg(MMUREG_CONTROL, 0x00004000);

    return -1;
}

int cmd_hreset(unsigned p,int argc,char *argv[])
{
    dbg_hreset();
    return -1;
}

int cmd_stat(unsigned p,int argc,char *argv[])
{
    uint32_t stat, stat2;
    stat = dbg_read_status();
    stat2 = dbg_read_status2();
    uprintf
        ("STAT=%8X : CPUs=%X DSTOP=%i HaltError=%i PSR.S=%i PSR.PS=%i PSR.ET=%i PSR.EF=%i\n",
         (int) stat, (int)((stat >> 12) &15),(int) (stat & 1),
         (int) ((stat >> 2) & 1), (int) ((stat >> 4) & 1),
         (int) ((stat >> 5) & 1), (int) ((stat >> 6) & 1),
         (int) ((stat >> 7) & 1));
    uprintf
        ("              : PSR.PIL=%2i IRL=%2i TRAP.T=%i TRAP.TT=%2X FCC=%s\n",
         (int) ((stat >> 12) & 15), (int) ((stat >> 16) & 15),
         (int) ((stat >> 23) & 1), (int) ((stat >> 24) & 255),
         FCCS[(stat >> 20) & 3]);
    if (((stat >> 24) & 255) < 0x40)
        uprintf("              : TRAP : %2X:'%s'\n", (stat >> 24) & 255,
                TRAPTXTS[(stat >> 24) & 255]);
    if (((stat >> 2) & 1) && (((stat2 >> 8) & 255) < 0x40))
        uprintf("              : HETRAP : %2X:'%s'\n", (stat2 >> 8) & 255,
                TRAPTXTS[(stat2 >> 8) & 255]);
    uprintf
        ("STAT2=%8X : HETRAP=%3X TRAP=%3X PHASE=%i FPU : QNE=%i FTT=%i ETAT=%i cycle=%i fpu_cycle=%i\n",
         stat2, (stat2 >> 8) & 511, (stat2 & 255), (stat2 >> 27) & 7,
         (stat2 >> 23) & 1, (stat2 >> 24) & 7, (stat2 >> 30) & 3,
         (stat2 >> 16) & 3, (stat2 >> 18) & 3);
    if ((stat2 & 255) < 0x40)
        uprintf("              : %2X:'%s'\n", stat2 & 255,
                TRAPTXTS[stat2 & 255]);
                
    uprintf
        ("STAT2=%8X : SYSACE : PC=%X PHASE=%X SEL=%i REQ=%i ACK=%i    SD : PC=%X PHASE=%X SEL=%i REQ=%i ACK=%i\n",
        stat2,
         stat2&0x3FF,(stat2&0x1C00)>>10,(stat2&0x2000)>>13,(stat2&0x4000)>>14,(stat2&0x8000)>>15,
         (stat2>>16)&0x3FF,((stat2>>16)&0x1C00)>>10,((stat2>>16)&0x2000)>>13,((stat2>>16)&0x4000)>>14,((stat2>>16)&0x8000)>>15);
        
        /*
  auxdebug(15 DOWNTO 0) <= scsi_sysace_w.ack &
                           scsi_sysace_r.req & 
                           scsi_sysace_r.sel & 
                           scsi_sysace_r.phase & 
                           scsi_sysace_r.d_pc(9 DOWNTO 0);
  auxdebug(31 DOWNTO 16)<= scsi_sd_w.ack &
                           scsi_sd_r.req & 
                           scsi_sd_r.sel & 
                           scsi_sd_r.phase & 
                           scsi_sd_r.d_pc(9 DOWNTO 0);


*/
        

//    uprintf ("STAT=%X\n",(int)dbg_read_status());
    uprintf("PC = %08X     nPC = %08X\n", (int) dbg_read_pc(),
            (int) dbg_read_npc());

    return 0;
}

int cmd_ibrk(unsigned p,int argc,char *argv[])
{
    uint32_t v;
    int t = 0;
    if (argc<2) {
        uprintf("I_BREAK OFF\n");
        ibrk[dbg_getcpu()].v = 0;
        dbg_ibrk(0);
        return 0;
    }
    t = parseint32(argv[1], &v);
    if (!t) {
        uprintf("I_BREAK=%8X\n", v);
        ibrk[dbg_getcpu()].v = 1;
        ibrk[dbg_getcpu()].a = v;
        dbg_write_ibrk(v);
        dbg_ibrk(1);
        return 0;
    }
    return -1;
}

int cmd_dbrk(unsigned p,int argc,char *argv[])
{
    uint32_t v;
    int t = 0;
    if (argc<2) {
        uprintf("D_BREAK OFF\n");
        dbrk[dbg_getcpu()].v = 0;
        dbg_dbrk(0);
        return 0;
    }
    t = parseint32(argv[1], &v);
    if (!t) {
        uprintf("D_BREAK=%8X\n", v);
        dbrk[dbg_getcpu()].v = 1;
        dbrk[dbg_getcpu()].a = v;
        dbg_write_dbrk(v);
        dbg_dbrk(1);
        return 0;
    }
    return -1;
}

int cmd_brk(unsigned p,int argc,char *argv[])
{
    if (dbrk[dbg_getcpu()].v)
        uprintf("DATA breakpoint : %8X\n", dbrk[dbg_getcpu()].a);
    else
        uprintf("DATA breakpoint OFF\n");

    if (ibrk[dbg_getcpu()].v)
        uprintf("INSTRUCTION breakpoint : %8X\n", ibrk[dbg_getcpu()].a);
    else
        uprintf("INSTRUCTION breakpoint OFF\n");
    return 0;
}

//####################################################################

int cmd_reg(unsigned p,int argc,char *argv[])
{
    unsigned psr;
    
    uprintf("PSR = %08X  TBR=%08X  WIM=%08X RY=%08X\n",
            (int) (psr =
                   dbg_read_cop_psr()), (int) dbg_read_tbr(),
            (int) dbg_read_wim(), (int) dbg_read_ry());
    uprintf
        ("PSR : IMP/VER= %02X  N=%i Z=%i V=%i C=%i EF=%i PIL=%X S=%i PS=%i ET=%i CWP=%2i\n",
         psr >> 24, (psr >> 23) & 1, (psr >> 22) & 1, (psr >> 21) & 1,
         (psr >> 20) & 1, (psr >> 12) & 1, (psr >> 8) & 15, (psr >> 7) & 1,
         (psr >> 6) & 1, (psr >> 5) & 1, (psr) & 31);
    uprintf("PC = %08X nPC = %08X\n", (int) dbg_read_cop_pc(),
            (int) dbg_read_cop_npc());
    uprintf("    G0 = %08X   G1 = %08X   G2 = %08X   G3 = %08X\n",
            (int) dbg_read_reg(0), (int) dbg_read_reg(1),
            (int) dbg_read_reg(2), (int) dbg_read_reg(3));
    uprintf("    G4 = %08X   G5 = %08X   G6 = %08X   G7 = %08X\n",
            (int) dbg_read_reg(4), (int) dbg_read_reg(5),
            (int) dbg_read_reg(6), (int) dbg_read_reg(7));
    uprintf("    O0 = %08X   O1 = %08X   O2 = %08X   O3 = %08X\n",
            (int) dbg_read_reg(8), (int) dbg_read_reg(9),
            (int) dbg_read_reg(10), (int) dbg_read_reg(11));
    uprintf("    O4 = %08X   O5 = %08X   SP = %08X   O7 = %08X\n",
            (int) dbg_read_reg(12), (int) dbg_read_reg(13),
            (int) dbg_read_reg(14), (int) dbg_read_reg(15));
    uprintf("    L0 = %08X   L1 = %08X   L2 = %08X   L3 = %08X\n",
            (int) dbg_read_reg(16), (int) dbg_read_reg(17),
            (int) dbg_read_reg(18), (int) dbg_read_reg(19));
    uprintf("    L4 = %08X   L5 = %08X   L6 = %08X   L7 = %08X\n",
            (int) dbg_read_reg(20), (int) dbg_read_reg(21),
            (int) dbg_read_reg(22), (int) dbg_read_reg(23));
    uprintf("    I0 = %08X   I1 = %08X   I2 = %08X   I3 = %08X\n",
            (int) dbg_read_reg(24), (int) dbg_read_reg(25),
            (int) dbg_read_reg(26), (int) dbg_read_reg(27));
    uprintf("    I4 = %08X   I5 = %08X   FP = %08X   I7 = %08X\n",
            (int) dbg_read_reg(28), (int) dbg_read_reg(29),
            (int) dbg_read_reg(30), (int) dbg_read_reg(31));
    uprintf("\n\n");
    return 0;
}

int cmd_wreg(unsigned p,int argc,char *argv[])
{
    uint32_t v;
    char *r;
    unsigned i;
    
    if (argc<3) return -1;
    
    r=argv[1];
    for (i=0;r[i];i++) r[i]=toupper(r[i]);
    
    if (parseint32(argv[2], &v))
        return -1;
    
    uprintf("%s:%X\n", r, v);
    
    if ((!strcmp(r, "R1") ) || (!strcmp(r, "G1"))) { dbg_write_reg( 1, v); return 0; }
    if ((!strcmp(r, "R2") ) || (!strcmp(r, "G2"))) { dbg_write_reg( 2, v); return 0; }
    if ((!strcmp(r, "R3") ) || (!strcmp(r, "G3"))) { dbg_write_reg( 3, v); return 0; }
    if ((!strcmp(r, "R4") ) || (!strcmp(r, "G4"))) { dbg_write_reg( 4, v); return 0; }
    if ((!strcmp(r, "R5") ) || (!strcmp(r, "G5"))) { dbg_write_reg( 5, v); return 0; }
    if ((!strcmp(r, "R6") ) || (!strcmp(r, "G6"))) { dbg_write_reg( 6, v); return 0; }
    if ((!strcmp(r, "R7") ) || (!strcmp(r, "G7"))) { dbg_write_reg( 7, v); return 0; }
    if ((!strcmp(r, "R8") ) || (!strcmp(r, "O0"))) { dbg_write_reg( 8, v); return 0; }
    if ((!strcmp(r, "R9") ) || (!strcmp(r, "O1"))) { dbg_write_reg( 9, v); return 0; }
    if ((!strcmp(r, "R10")) || (!strcmp(r, "O2"))) { dbg_write_reg(10, v); return 0; }
    if ((!strcmp(r, "R11")) || (!strcmp(r, "O3"))) { dbg_write_reg(11, v); return 0; }
    if ((!strcmp(r, "R12")) || (!strcmp(r, "O4"))) { dbg_write_reg(12, v); return 0; }
    if ((!strcmp(r, "R13")) || (!strcmp(r, "O5"))) { dbg_write_reg(13, v); return 0; }
    if ((!strcmp(r, "R14")) || (!strcmp(r, "O6"))) { dbg_write_reg(14, v); return 0; }
    if ((!strcmp(r, "R15")) || (!strcmp(r, "O7"))) { dbg_write_reg(15, v); return 0; }
    if ((!strcmp(r, "R16")) || (!strcmp(r, "L0"))) { dbg_write_reg(16, v); return 0;}
    if ((!strcmp(r, "R17")) || (!strcmp(r, "L1"))) { dbg_write_reg(17, v); return 0; }
    if ((!strcmp(r, "R18")) || (!strcmp(r, "L2"))) { dbg_write_reg(18, v); return 0; }
    if ((!strcmp(r, "R19")) || (!strcmp(r, "L3"))) { dbg_write_reg(19, v); return 0; }
    if ((!strcmp(r, "R20")) || (!strcmp(r, "L4"))) { dbg_write_reg(20, v); return 0; }
    if ((!strcmp(r, "R21")) || (!strcmp(r, "L5"))) { dbg_write_reg(21, v); return 0; }
    if ((!strcmp(r, "R22")) || (!strcmp(r, "L6"))) { dbg_write_reg(22, v); return 0; }
    if ((!strcmp(r, "R23")) || (!strcmp(r, "L7"))) { dbg_write_reg(23, v); return 0; }
    if ((!strcmp(r, "R24")) || (!strcmp(r, "I0"))) { dbg_write_reg(24, v); return 0; }
    if ((!strcmp(r, "R25")) || (!strcmp(r, "I1"))) { dbg_write_reg(25, v); return 0; }
    if ((!strcmp(r, "R26")) || (!strcmp(r, "I2"))) { dbg_write_reg(26, v); return 0; }
    if ((!strcmp(r, "R27")) || (!strcmp(r, "I3"))) { dbg_write_reg(27, v); return 0; }
    if ((!strcmp(r, "R28")) || (!strcmp(r, "I4"))) { dbg_write_reg(28, v); return 0; }
    if ((!strcmp(r, "R29")) || (!strcmp(r, "I5"))) { dbg_write_reg(29, v); return 0; }
    if ((!strcmp(r, "R30")) || (!strcmp(r, "I6"))) { dbg_write_reg(30, v); return 0; }
    if ((!strcmp(r, "R31")) || (!strcmp(r, "I7"))) { dbg_write_reg(31, v); return 0; }
    if (!strcmp(r, "F0") ) { dbg_write_freg(0, v); return 0; }
    if (!strcmp(r, "F1") ) { dbg_write_freg(1, v); return 0; }
    if (!strcmp(r, "F2") ) { dbg_write_freg(2, v); return 0; }
    if (!strcmp(r, "F3") ) { dbg_write_freg(3, v); return 0; }
    if (!strcmp(r, "F4") ) { dbg_write_freg(4, v); return 0; }
    if (!strcmp(r, "F5") ) { dbg_write_freg(5, v); return 0; }
    if (!strcmp(r, "F6") ) { dbg_write_freg(6, v); return 0; }
    if (!strcmp(r, "F7") ) { dbg_write_freg(7, v); return 0; }
    if (!strcmp(r, "F8") ) { dbg_write_freg(8, v); return 0; }
    if (!strcmp(r, "F9") ) { dbg_write_freg(9, v); return 0; }
    if (!strcmp(r, "F10")) { dbg_write_freg(10, v); return 0; }
    if (!strcmp(r, "F11")) { dbg_write_freg(11, v); return 0; }
    if (!strcmp(r, "F12")) { dbg_write_freg(12, v); return 0; }
    if (!strcmp(r, "F13")) { dbg_write_freg(13, v); return 0; }
    if (!strcmp(r, "F14")) { dbg_write_freg(14, v); return 0; }
    if (!strcmp(r, "F15")) { dbg_write_freg(15, v); return 0; }
    if (!strcmp(r, "F16")) { dbg_write_freg(16, v); return 0; }
    if (!strcmp(r, "F17")) { dbg_write_freg(17, v); return 0; }
    if (!strcmp(r, "F18")) { dbg_write_freg(18, v); return 0; }
    if (!strcmp(r, "F19")) { dbg_write_freg(19, v); return 0; }
    if (!strcmp(r, "F20")) { dbg_write_freg(20, v); return 0; }
    if (!strcmp(r, "F21")) { dbg_write_freg(21, v); return 0; }
    if (!strcmp(r, "F22")) { dbg_write_freg(22, v); return 0; }
    if (!strcmp(r, "F23")) { dbg_write_freg(23, v); return 0; }
    if (!strcmp(r, "F24")) { dbg_write_freg(24, v); return 0; }
    if (!strcmp(r, "F25")) { dbg_write_freg(25, v); return 0; }
    if (!strcmp(r, "F26")) { dbg_write_freg(26, v); return 0; }
    if (!strcmp(r, "F27")) { dbg_write_freg(27, v); return 0; }
    if (!strcmp(r, "F28")) { dbg_write_freg(28, v); return 0; }
    if (!strcmp(r, "F29")) { dbg_write_freg(29, v); return 0; }
    if (!strcmp(r, "F30")) { dbg_write_freg(30, v); return 0; }
    if (!strcmp(r, "F31")) { dbg_write_freg(31, v); return 0; }
    
    if (!strcmp(r, "PSR")) {
        dbg_write_cop_psr(v);
        return 0;
    }
    if (!strcmp(r, "WIM")) {
        dbg_write_wim(v);
        return 0;
    }
    if (!strcmp(r, "TBR")) {
        dbg_write_tbr(v);
        return 0;
    }
    if (!strcmp(r, "RY")) {
        dbg_write_ry(v);
        return 0;
    }
    if (!strcmp(r, "PC")) {
        dbg_write_cop_pc(v);
        return 0;
    }
    if (!strcmp(r, "NPC")) {
        dbg_write_cop_npc(v);
        return 0;
    }
    if (!strcmp(r, "FSR")) {
        dbg_write_fsr(v);
        return 0;
    }
    
    return -1;
}

union {
    char c[4];
    float f;
    uint32_t u;
} u_float;

double conv_f(uint32_t a)
{
    u_float.u = a;
    return u_float.f;
}

union {
    char c[8];
    double f;
    uint32_t u[2];
} u_double;

double conv_d(uint32_t a, uint32_t b)
{
    u_double.u[0] = b; // LITTLE ENDIAN !!!!
    u_double.u[1] = a;
    return u_double.f;
}

const char* Rounding[] = {"'Nearest'" , "'Zero'" , "'+Inf'" , "'-Inf'"};
const char* FPTrapType[] = {"'NoTrap'" , "'IEEE754 exception'" , "'Unfinished FPop'" , "'Unimplemented FPop'",
                           "'Sequence Error'" , "'Hardware Error'" , "'Invalid FP Register'" , "'reserved'"};
const char *FPCondition[] = {"'='", "'<'" , "'>'" , "'?'" };

int cmd_freg(unsigned p,int argc,char *argv[])
{
    uint32_t a, b, c, d;
    int i;
    unsigned psr;

    uprintf("FP Regs\n");
    a=dbg_read_fsr();
    
    uprintf ("    FSR : %8X RD=%s TEM=%X NS=%i VER=%X FTT=%s QNE=%i FCC=%s AEXC=%X CEXC=%X (NV,OF,UF,DZ,NX)\n\n",
             a ,Rounding[(a >> 30) & 3] , (a >> 23) & 31 , (a >> 22) & 1 , (a >> 17) & 15,
             FPTrapType[(a >> 14) & 7] , (a >> 13) & 1 ,
             FPCondition[(a >> 10) & 3] , (a >> 5) & 31 , a & 31);
    
    for (i = 0; i < 32; i += 4) {
        a = dbg_read_freg(i);
        b = dbg_read_freg(i + 1);
        c = dbg_read_freg(i + 2);
        d = dbg_read_freg(i + 3);
        uprintf("    F%02i=%08X   F%02i=%08X   F%02i=%08X   F%02i=%08X\n",
                i, (int) a, i + 1, b, i + 2, c, i + 3, d);
    }

    uprintf("\n");
    for (i = 0; i < 32; i += 4) {
        a = dbg_read_freg(i);
        b = dbg_read_freg(i + 1);
        c = dbg_read_freg(i + 2);
        d = dbg_read_freg(i + 3);
        uprintf
            ("    F%02i=%14e  F%02i=%14e  F%02i=%14e  F%02i=%14e | D%02i=%14e  D%02i=%14e\n",
             i, conv_f(a), i + 1, conv_f(b), i + 2, conv_f(c), i + 3,
             conv_f(d), i, conv_d(a, b), i + 2, conv_d(c, d));
    }

    uprintf("\n\n");
    return 0;
}

int numreg(char *r)
{
    if (strlen(r)==2) return r[1] - '0';
    if (strlen(r)==3) return (r[1] - '0') * 10 + r[2] - '0';
    return 0;
}

int cmd_dfq(unsigned p,int argc,char *argv[])
{
    char ctxt[200];
    uint32_t v;
    
    v=dbg_read_dfq();
    disassemble(ctxt, v, 0);
    uprintf ("DFQ : Instruction : %8X : %s\n",v,ctxt);
    
    return 0;
}

int cmd_reg_win(unsigned p,int argc,char *argv[])
{
    unsigned psr;
    int i;

    psr = dbg_read_cop_psr();
    uprintf("WIM=%X\n\n", dbg_read_wim());
    for (i = 0; i < 8; i++) {
        uprintf("Win=%2i  :", psr & 0x7);
        psr = (psr & ~31) + ((psr & 31) + 1) & 31;

        uprintf("    L7 = %08X   :", (int) dbg_read_reg(23));
        uprintf("    SP = %08X   O7 = %08X  :", (int) dbg_read_reg(14),
                (int) dbg_read_reg(15));
        uprintf("    FP = %08X   I7 = %08X\n", (int) dbg_read_reg(30),
                (int) dbg_read_reg(31));

        dbg_write_psr(psr);
    }

    dbg_write_psr(dbg_read_cop_psr());
}

int cmd_reg_dump(unsigned p,int argc,char *argv[])
{
    unsigned psr;
    int i;

    psr = dbg_read_cop_psr();
    uprintf("WIM=%X\n\n", dbg_read_wim());
    for (i = 0; i < 8; i++) {
    
        uprintf("Win=%2i  :\n", psr & 0x7);
        
        uprintf("    O0 = %08X   O1 = %08X   O2 = %08X   O3 = %08X\n",
                (int) dbg_read_reg(8), (int) dbg_read_reg(9),
                (int) dbg_read_reg(10), (int) dbg_read_reg(11));
        uprintf("    O4 = %08X   O5 = %08X   SP = %08X   O7 = %08X\n",
                (int) dbg_read_reg(12), (int) dbg_read_reg(13),
                (int) dbg_read_reg(14), (int) dbg_read_reg(15));
        uprintf("    L0 = %08X   L1 = %08X   L2 = %08X   L3 = %08X\n",
                (int) dbg_read_reg(16), (int) dbg_read_reg(17),
                (int) dbg_read_reg(18), (int) dbg_read_reg(19));
        uprintf("    L4 = %08X   L5 = %08X   L6 = %08X   L7 = %08X\n",
                (int) dbg_read_reg(20), (int) dbg_read_reg(21),
                (int) dbg_read_reg(22), (int) dbg_read_reg(23));
        uprintf("    I0 = %08X   I1 = %08X   I2 = %08X   I3 = %08X\n",
                (int) dbg_read_reg(24), (int) dbg_read_reg(25),
                (int) dbg_read_reg(26), (int) dbg_read_reg(27));
        uprintf("    I4 = %08X   I5 = %08X   FP = %08X   I7 = %08X\n",
                (int) dbg_read_reg(28), (int) dbg_read_reg(29),
                (int) dbg_read_reg(30), (int) dbg_read_reg(31));
        psr = (psr & ~31) + ((psr & 31) + 1) & 31;
        dbg_write_psr(psr);
    }
    dbg_write_psr(dbg_read_cop_psr());
}

//####################################################################

// Virtual Dump 32bits
int cmd_vd4(unsigned p,int argc,char *argv[])
{
    uint32_t v, v2;
    int i, j;
    uint8_t pm[16];

    if (argc<2)
        return -1;
    if (parseint32(argv[1], &v))
        return -1;
    if (argc<3) {
        v2 = 256;
    } else {
        if (parseint32(argv[2], &v2))
            return -1;
    }

    testchar();
    testchar();
    testchar();
    testchar();

    v &= ~3;
    for (i = 0; i < (v2 & ~3); i += 16) {
        dbg_read_vmem(v + i, pm, 16);
        uprintf(" %08X : ",(int) i + v);
        for (j = 0; j < 16; j++) {
          uprintf ("%02X",pm[j]);
          if ((j & 3) == 3) uprintf (" ");
        }
        uprintf(" : ");
        for (j=0;j<16;j++) uprintf ("%c",co(pm[j]));
        uprintf("\n");
        if (testchar()) break;
    }
    return 0;
}

// Physical Dump 32bits
int cmd_pd4(unsigned p,int argc,char *argv[])
{
    uint64_t v;
    uint32_t v2;
    int i, j;
    uint8_t pm[16];
    
    if (argc<2)
        return -1;
    if (parseint64(argv[1], &v))
        return -1;
    if (argc<3) {
        v2 = 256;
    } else {
        if (parseint32(argv[2], &v2))
            return -1;
    }
    
    testchar();
    testchar();
    testchar();
    testchar();
    
    v &= ~3;
    for (i = 0; i < (v2 & ~3); i += 16) {
        dbg_read_pmem(v + i, pm, 16);
        uprintf(" %X.%08X : ",AHI(v+i), ALO(v+i));
        for (j=0;j<16;j++) {
          uprintf ("%02X",pm[j]);
          if ((j & 3) == 3) uprintf (" ");
        }
        uprintf(" : ");
        for (j=0;j<16;j++) uprintf ("%c",co(pm[j]));
        uprintf("\n");
        if (testchar()) break;
    }
    return 0;
}

// ASI Read
int cmd_asir(unsigned p,int argc,char *argv[])
{
    uint32_t v, v2, v3;
    
    if (argc<3)
        return -1;
    if (parseint32(argv[1], &v))
        return -1;
    if (parseint32(argv[2], &v2))
        return -1;
    
    v2&=~(uint64_t)p;
    switch (p) {
      case 3:
        v3 = dbg_read_asimem32(v,v2);
        uprintf("%02X [%08X] => %08X\n", v, v2, v3);
        break;
      case 1:
        v3 = dbg_read_asimem16(v,v2);
        uprintf("%02X [%08X] => %04X\n", v, v2, v3);
        break;
      default:
        v3 = dbg_read_asimem8(v,v2);
        uprintf("%02X [%08X] => %02X\n", v, v2, v3);
        break;
    }
    return 0;
}

// ASI Write
int cmd_asiw(unsigned p,int argc,char *argv[])
{
    uint32_t v, v2, v3;

    if (argc<4)
        return -1;
    if (parseint32(argv[1], &v))
        return -1;
    if (parseint32(argv[2], &v2))
        return -1;
    if (parseint32(argv[3], &v3))
        return -1;
    
    v2&=~(uint32_t)p;
    switch (p) {
      case 3:
        dbg_write_asimem32(v, v2, v3);
        uprintf("%02X [%08X] <= %08X\n", v, v2, v3);
        break;
      case 1:
        dbg_write_asimem16(v, v2, v3);
        uprintf("%02X [%08X] <= %04X\n", v, v2, v3);
        break;
      default:
        dbg_write_asimem8(v, v2, v3);
        uprintf("%02X [%08X] <= %02X\n", v, v2, v3);
        break;
    }
    return 0;
}

// Physical Read 8/16/32
int cmd_pr(unsigned p,int argc,char *argv[])
{
    uint64_t v,vx;
    uint32_t v2;
    
    if (argc<2)
        return -1;
    if (parseint64(argv[1], &v))
        return -1;
    
    v&=~(uint64_t)p;
    switch (p) {
      case 4:
        vx = dbg_read_pmem64(v);
        uprintf("[%X.%08X] => %08X_%08X\n", AHI(v), ALO(v), AHI(vx), ALO(vx));
        break;
      case 3:
        v2 = dbg_read_pmem32(v);
        uprintf("[%X.%08X] => %08X\n", AHI(v),ALO(v), v2);
        break;
      case 1:
        v2 = dbg_read_pmem16(v);
        uprintf("[%X.%08X] => %04X\n", AHI(v),ALO(v), v2);
        break;
      default:
        v2 = dbg_read_pmem8(v);
        uprintf("[%X.%08X] => %02X\n", AHI(v),ALO(v), v2);
        break;
    }
    return 0;
}

// Physical Write 8/16/32
int cmd_pw(unsigned p,int argc,char *argv[])
{
    uint64_t v;
    uint32_t v2;

    if (argc<3)
        return -1;
    if (parseint64(argv[1], &v))
        return -1;
    if (parseint32(argv[2], &v2))
        return -1;
    
    v&=~(uint64_t)p;
    switch (p) {
      case 3:
        uprintf("[%X.%08X] <= %08X\n", AHI(v),ALO(v), v2);
        dbg_write_pmem32(v,v2);
        break;
      case 1:
        uprintf("[%X.%08X] <= %04X\n", AHI(v),ALO(v), v2);
        dbg_write_pmem16(v,v2);
        break;
      default:
        uprintf("[%X.%08X] <= %02X\n", AHI(v),ALO(v), v2);
        dbg_write_pmem8(v,v2);
        break;
    }
    return 0;
}

// Virtual Read 8/16/32
int cmd_vr(unsigned p,int argc,char *argv[])
{
    uint32_t v,v2;

    if (argc<2)
        return -1;
    if (parseint32(argv[1], &v))
        return -1;
        
    v&=~p;
    switch (p) {
      case 3:
        v2 = dbg_read_vmem32(v);
        uprintf("[%08X] => %08X\n", v, v2);
        break;
      case 1:
        v2 = dbg_read_vmem16(v);
        uprintf("[%08X] => %04X\n", v, v2);
        break;
      default:
        v2 = dbg_read_vmem8(v);
        uprintf("[%08X] => %02X\n", v, v2);
        break;
    }
    return 0;
}

// Virtual Write 8/16/32
int cmd_vw(unsigned p,int argc,char *argv[])
{
    uint32_t v,v2;

    if (argc<3)
        return -1;
    if (parseint32(argv[1], &v))
        return -1;
    if (parseint32(argv[2], &v2))
        return -1;
    
    v&=~p;
    switch (p) {
      case 3:
        uprintf("[%08X] <= %08X\n", v, v2);
        dbg_write_vmem32(v,v2);
        break;
      case 1:
        uprintf("[%08X] <= %04X\n", v, v2);
        dbg_write_vmem16(v,v2);
        break;
      default:
        uprintf("[%08X] <= %02X\n", v, v2);
        dbg_write_vmem8(v,v2);
        break;
    }
    return 0;
}

// Physical fill mem
int cmd_pf4(unsigned p,int argc,char *argv[])
{
    uint64_t v;
    uint32_t v2, v3;
    int i;
    
    if (argc<4)
        return -1;
    if (parseint64(argv[1], &v))
        return -1;
    if (parseint32(argv[2], &v2))
        return -1;
    if (parseint32(argv[3], &v3))
        return -1;

    v&=~3LL;
    uprintf(" v=%X.%X  %X %X\n", AHI(v),ALO(v), v2, v3);

    for (i = 0; i < v2; i += 4) {
        dbg_write_pmem32(v + i, v3);
    }
    return 0;
}

// Disassemble
int cmd_disa(unsigned p,int argc,char *argv[])
{
    uint32_t v, v2, pc,a;
    int i;
    char ctxt[100];
    
    pc = dbg_read_cop_pc();
    v2=128;
    
    if (argc==1) {
        v=pc;
    }
    if (argc>=2) {
        if (parseint32(argv[1], &v))
            return -1;
    }
    if (argc>=3) {
        if (parseint32(argv[2], &v2))
            return -1;
    }
    
    testchar();
    testchar();
    testchar();
    testchar();

    v &= ~3;
    for (i = 0; i < (v2 & ~3); i += 4) {
        if (p == 0) {
          a = dbg_read_vmem32(v + i);
        } else {
          a = dbg_read_vmem32i(v + i);
        }
        disassemble(ctxt, a, v + i);
        uprintf(" %25s : %08X : %08X : %s\n",
                symboli(v + i), (int) (v + i), a, ctxt);
        if (testchar()) break;
    }
    return 0;
}

//####################################################################

char *TxtAT[]={
    "0:Load   User  Data",
    "1:Load   Super Data",
    "2:Ld/Exe User  Inst",
    "3:Ld/Exe Super Inst",
    "4:Store  User  Data",
    "5:Store  Super Data",
    "6:Store  User  Inst",
    "7:Store  Super Inst"};
    
char *TxtFT[]={
    "0:None           ",
    "1:Invalid Address",
    "2:Protection     ",
    "3:Privilege Viol.",
    "4:Translation    ",
    "5:Access bus     ",
    "6:Internal       ",
    "7:Reserved       " };


int cmd_rmmu (unsigned p,int argc,char *argv[])
{
  unsigned v, i;
  unsigned mc, stat;
 
  uprintf ("Registres MMU\n");
  mc = dbg_read_mmureg(MMUREG_CONTROL);
  uprintf ("MMU Control               = 0x%08X    IMP/VER = %02X  CPUID=%X BM=%d NF=%d E=%d DCE=%d ICE=%d "
           "L2TLB=%d WB=%d AoW=%d Snoop=%d\n",
           mc, mc >> 24, (mc>> 2) & 3,(mc >> 13) & 3, (mc >> 1) & 1,
           mc & 1, (mc >> 8) & 1, (mc >> 9) & 1,
           (mc >> 6) & 1,(mc >>4) & 1,(mc >>5) & 1,(mc >>14) & 1);
  uprintf ("MMU Context Table Pointer = 0x%08X\n",
           dbg_read_mmureg(MMUREG_CTPR));
  uprintf ("MMU Context               = 0x%08X\n",
           dbg_read_mmureg(MMUREG_CTXR));
  stat=dbg_read_mmureg(MMUREG_FSTAT);
  uprintf ("MMU Fault Status          = 0x%08X    L=%d AT=(%s) FT=(%s) FAV=%d OW=%d\n",stat,
           (stat >> 8) & 3, TxtAT[(stat >> 5) & 7], TxtFT[(stat >> 2) & 7], 
           (stat >> 1) & 1, stat & 1);
  uprintf ("MMU Fault Address         = 0x%08X\n",
           dbg_read_mmureg(MMUREG_FADR));
  uprintf ("MMU SYSCONF               = 0x%08X\n",
           dbg_read_mmureg(MMUREG_SYSCONF));
  uprintf ("MMU Tmp                   = 0x%08X\n",
           dbg_read_mmureg(MMUREG_TMP));
  uprintf ("MMU ALO0                  = 0x%08X\n",
           dbg_read_mmureg(MMUREG_ALO0));
  uprintf ("MMU AHI0                  = 0x%08X\n",
           dbg_read_mmureg(MMUREG_AHI0));
  uprintf ("MMU ALO1                  = 0x%08X\n",
           dbg_read_mmureg(MMUREG_ALO1));
  uprintf ("MMU AHI1                  = 0x%08X\n",
           dbg_read_mmureg(MMUREG_AHI1));
  uprintf ("MMU ALO2                  = 0x%08X\n",
           dbg_read_mmureg(MMUREG_ALO2));
  uprintf ("MMU AHI2                  = 0x%08X\n",
           dbg_read_mmureg(MMUREG_AHI2));
  uprintf ("MMU ACM                   = 0x%08X\n",
           dbg_read_mmureg(MMUREG_ACM));
  uprintf ("MMU ACP                   = 0x%08X\n",
           dbg_read_mmureg(MMUREG_ACP));
  uprintf ("MMU ACO                   = 0x%08X\n",
           dbg_read_mmureg(MMUREG_ACO));
  uprintf ("\n");
  return 0;
}

int cmd_wmmu(unsigned p,int argc,char *argv[])
{
    uint32_t v;
    char *r;
    int i;
    
    if (argc<3) return -1;
    
    r=argv[1];
    for (i=0;r[i];i++) r[i]=toupper(r[i]);
    
    if (parseint32(argv[2], &v))
        return -1;
    
    uprintf("%s:%X\n", r, v);

    if ((strcmp(r, "MCR") == 0) || (strcmp(r, "CR") == 0)
        || (strcmp(r, "C") == 0)) {
        dbg_write_mmureg(MMUREG_CONTROL, v);
        return 0;
    }
    if ((strcmp(r, "MCTPR") == 0) || (strcmp(r, "CTPR") == 0)
        || (strcmp(r, "CTP") == 0)) {
        dbg_write_mmureg(MMUREG_CTPR, v);
        return 0;
    }
    if ((strcmp(r, "MCTXR") == 0) || (strcmp(r, "CTXR") == 0)
        || (strcmp(r, "CTX") == 0)) {
        dbg_write_mmureg(MMUREG_CTXR, v);
        return 0;
    }
    if ((strcmp(r, "TEMP") == 0) || (strcmp(r, "TAMP") == 0)
        || (strcmp(r, "TMP") == 0)) {
        dbg_write_mmureg(MMUREG_TMP, v);
        return 0;
    }
    if ((strcmp(r, "ALO0") == 0)) { dbg_write_mmureg(MMUREG_ALO0, v); return 0; }
    if ((strcmp(r, "AHI0") == 0)) { dbg_write_mmureg(MMUREG_AHI0, v); return 0; }
    if ((strcmp(r, "ALO1") == 0)) { dbg_write_mmureg(MMUREG_ALO1, v); return 0; }
    if ((strcmp(r, "AHI1") == 0)) { dbg_write_mmureg(MMUREG_AHI1, v); return 0; }
    if ((strcmp(r, "ALO2") == 0)) { dbg_write_mmureg(MMUREG_ALO2, v); return 0; }
    if ((strcmp(r, "AHI2") == 0)) { dbg_write_mmureg(MMUREG_AHI2, v); return 0; }
    if ((strcmp(r, "ACM") == 0))  { dbg_write_mmureg(MMUREG_ACM, v); return 0; }
    if ((strcmp(r, "ACP") == 0))  { dbg_write_mmureg(MMUREG_ACP, v); return 0; }
    if ((strcmp(r, "ACO") == 0))  { dbg_write_mmureg(MMUREG_ACO, v); return 0; }
    
    uprintf("Reg ?\n");
    return -1;
}

// MMU Probe
int cmd_probe(unsigned p,int argc,char *argv[])
{
    uint32_t v, vv;
    int i, et, et1, et2, et3;
    uint32_t ctp, cxr;
    uint64_t ap;

    if (argc<2)
        return -1;
    if (parseint32(argv[1], &v))
        return -1;

    vv = dbg_mmu_probe((v & 0xFFFFF000) | 0x300);
    et3 = vv & 3;
    uprintf("Probe Context : %08X\n", vv);

    vv = dbg_mmu_probe((v & 0xFFFFF000) | 0x200);
    et2 = vv & 3;
    uprintf("Probe Region  : %08X\n", vv);

    vv = dbg_mmu_probe((v & 0xFFFFF000) | 0x100);
    et1 = vv & 3;
    uprintf("Probe Segment : %08X\n", vv);

    vv = dbg_mmu_probe(v & 0xFFFFF000);
    et = vv & 3;
    uprintf("Probe Page    : %08X\n", vv);

    if ((et1 == 2) && (et2 == 2) && (et3 == 2))
        uprintf("Size : Context : vvvv_vvvv\n");
    if ((et1 == 2) && (et2 == 2) && (et3 == 1))
        uprintf("Size : Region  : XXvv_vvvv\n");
    else if ((et1 == 2) && (et2 == 1) && (et3 == 1))
        uprintf("Size : Segment : XXXX_vvvv\n");
    else if ((et1 == 1) && (et2 == 1) && (et3 == 1))
        uprintf("Size : Page    : XXXX_Xvvv\n");
    else
        uprintf("???\n");

    if (et == 0)
        uprintf("Probe [%08X] = %08X Invalid\n", v, vv);
    else if (et == 1)
        uprintf("Probe [%08X] = %08X PTD :%08X0\n", v, vv, (vv - 1));
    else if (et == 2)
        uprintf
            ("Probe [%08X] = %08X PTE :ACC=%i C=%i M=%i R=%i PPN = " ANSI_ROUGE " %06X000" ANSI_DEFAULT "\n",
             v, vv, ((vv >> 2) & 7), ((vv >> 7) & 1), ((vv >> 6) & 1),
             ((vv >> 5) & 1), ((vv >> 8) & 0xFFFFFF));

    ctp = dbg_read_mmureg(MMUREG_CTPR) & (~3);
    cxr = dbg_read_mmureg(MMUREG_CTXR);
    uprintf("\n");
    // Context Table
    ap = ctp * 16;
    uprintf("Context Table : %X.%08X - Context =%X\n", AHI(ap), ALO(ap), (unsigned) cxr);

    ap = ap + 4 * cxr;
    vv = dbg_read_pmem32(ap);
    if ((vv & 3) == 0)
        uprintf("L1 PT : Invalid\n");
    else if ((vv & 3) == 3)
        uprintf("L1 PT : Reserved\n");
    else if ((vv & 3) == 2) {
        uprintf("L1 PTE %08X PTE :ACC=%i C=%i M=%i R=%i PPN=%06X000\n", vv,
                ((vv >> 2) & 7), ((vv >> 7) & 1), ((vv >> 6) & 1),
                ((vv >> 5) & 1), ((vv >> 8) & 0xFFFFFF));
    } else {
        vv = vv & ~3;
        uprintf("L1 PTD %08X       (A=%X.%08X)\n", vv, AHI(ap), ALO(ap));

        ap = vv * 16 + (v >> 24) * 4;
        vv = dbg_read_pmem32(ap);
        if ((vv & 3) == 0)
            uprintf("L2 PT : Invalid\n");
        else if ((vv & 3) == 3)
            uprintf("L2 PT : Reserved\n");
        else if ((vv & 3) == 2) {
            uprintf("L2 PTE %08X PTE :ACC=%i C=%i M=%i R=%i PPN=%06X000\n",
                    vv, ((vv >> 2) & 7), ((vv >> 7) & 1), ((vv >> 6) & 1),
                    ((vv >> 5) & 1), ((vv >> 8) & 0xFFFFFF));
            uprintf("                      (A=%X.%08X)\n", AHI(ap), ALO(ap));
        } else {
            vv = vv & ~3;
            uprintf("L2 PTD %08X       (A=%X.%08X)\n", vv, AHI(ap), ALO(ap));

            ap = vv * 16 + ((v >> 18) & 63) * 4;
            vv = dbg_read_pmem32(ap);
            if ((vv & 3) == 0)
                uprintf("L3 PT : Invalid\n");
            else if ((vv & 3) == 3)
                uprintf("L3 PT : Reserved\n");
            else if ((vv & 3) == 2) {
                uprintf
                    ("L3 PTE %08X PTE :ACC=%i C=%i M=%i R=%i PPN=%06X000\n",
                     vv, ((vv >> 2) & 7), ((vv >> 7) & 1), ((vv >> 6) & 1),
                     ((vv >> 5) & 1), ((vv >> 8) & 0xFFFFFF));
                uprintf("                      (A=%X.%08X)\n", AHI(ap), ALO(ap));
            } else {
                vv = vv & ~3;
                uprintf("L3 PTD %08X       (A=%X.%08X)\n", vv, AHI(ap), ALO(ap));

                ap = vv * 16 + ((v >> 12) & 63) * 4;
                vv = dbg_read_pmem32(ap);
                if ((vv & 3) == 0)
                    uprintf("L3 PT : Invalid\n");
                else if ((vv & 3) == 3)
                    uprintf("L3 PT : Reserved\n");
                else if ((vv & 3) == 2) {
                    uprintf
                        ("L3 PTE %08X PTE :ACC=%i C=%i M=%i R=%i PPN=%06X000\n",
                         vv, ((vv >> 2) & 7), ((vv >> 7) & 1),
                         ((vv >> 6) & 1), ((vv >> 5) & 1),
                         ((vv >> 8) & 0xFFFFFF));
                    uprintf("                      (A=%X.%08X)\n", AHI(ap), ALO(ap));
                } else {
                    vv = vv & ~3;
                    uprintf("LX : ERREUR : PTD %08X\n", vv);

                }
            }
        }
    }
    return 0;
}

char *acctxt[] = { "|R..|R..|", "|RW.|RW.|",
                   "|R.X|R.X|", "|RWX|RWX|",
                   "|..X|..X|", "|R..|RW.|",
                   "|...|R.X|", "|...|RWX|"};

// DUMP MMU Mappings
int cmd_mmumap(unsigned p,int argc,char *argv[])
{
    uint32_t ctp, cxr;
    unsigned i, j, k;
    uint32_t vv;
    uint64_t ap, bp, cp, dp, ep, fp;

    ctp = dbg_read_mmureg(MMUREG_CTPR) & (~3);
    cxr = dbg_read_mmureg(MMUREG_CTXR);
    uprintf("\n");
    testchar();
    testchar();
    testchar();

    // Context Table
    ap = ctp * 16;
    uprintf("Context Table : %X.%08X - Context =%X\n", AHI(ap),ALO(ap), (unsigned) cxr);

    ap = ap + 4 * cxr;
    uprintf("Root Table context : %X.%08X\n\n", AHI(ap), ALO(ap));
    vv = dbg_read_pmem32(ap);
    ap = (vv - 1) << 4;
    for (i = 0; i < 256; i++) {
        if (testchar()) break;
        bp = ap + 4 * i;
        vv = dbg_read_pmem32(bp);
        if ((vv & 3) == 0) {
            /*uprintf ("VA=%08X  -> %08X",(i<<24),vv);
               uprintf ("  --> Invalid\n"); */
        } else if ((vv & 3) == 3) {
            uprintf("VA=%08X  -> %08X", (i << 24), vv);
            uprintf("  --> Reserved\n");
        } else if ((vv & 3) == 2) {
            uprintf("VA=%08X  -> %08X", (i << 24), vv);
            uprintf("  --> PTE : PPN=%X.%05X000 CMR=%X %s\n",
                    (vv & 0xF0000000) >> 28, (vv & 0x0FFFFF00) >> 8,
                    (vv & 0xE0) >> 5, acctxt[(vv & 0x1C) >> 2]);
        } else {
            uprintf("VA=%08X  -> %08X", (i << 24), vv);
            uprintf("  --> PTD : PPN=%X.%06X00\n", (vv & 0xF0000000) >> 28,
                    (vv & 0x0FFFFFF0) >> 4);
            cp = (vv - 1) << 4L;
            for (j = 0; j < 64; j++) {
                if (testchar()) { i=256; break; }
                dp = cp + 4 * j;
                vv = dbg_read_pmem32(dp);
                if ((vv & 3) == 0) {
                    /*uprintf ("             VA=%08X  -> %08X",(i<<24)+(j<<18),vv);
                       uprintf ("  --> Invalid\n"); */
                } else if ((vv & 3) == 3) {
                    uprintf("             VA=%08X  -> %08X",
                            (i << 24) + (j << 18), vv);
                    uprintf("  --> Reserved\n");
                } else if ((vv & 3) == 2) {
                    uprintf("             VA=%08X  -> %08X",
                            (i << 24) + (j << 18), vv);
                    uprintf("  --> PTE : PPN=%X.%05X000 CMR=%X %s\n",
                            (vv & 0xF0000000) >> 28,
                            (vv & 0x0FFFFF00) >> 8, (vv & 0xE0) >> 5,
                            acctxt[(vv & 0x1C) >> 2]);
                } else {
                    uprintf("             VA=%08X  -> %08X",
                            (i << 24) + (j << 18), vv);
                    uprintf("  --> PTD : PPN=%X.%06X00\n",
                            (vv & 0xF0000000) >> 28,
                            (vv & 0x0FFFFFF0) >> 4);
                    ep = (vv - 1) << 4L;
                    for (k = 0; k < 64; k++) {
                        if (testchar()) { i=256; j=64; break; }
                        fp = ep + 4 * k;
                        vv = dbg_read_pmem32(fp);
                        if ((vv & 3) == 0) {
                            /*uprintf ("                          VA=%08X  -> %08X",(i<<24)+(j<<18)+(k<<12),vv);
                               uprintf ("  --> Invalid\n"); */
                        } else if ((vv & 3) == 3) {
                            uprintf
                                ("                          VA=%08X  -> %08X",
                                 (i << 24) + (j << 18) + (k << 12), vv);
                            uprintf("  --> Reserved\n");
                        } else if ((vv & 3) == 2) {
                            uprintf
                                ("                          VA=%08X  -> %08X",
                                 (i << 24) + (j << 18) + (k << 12), vv);
                            uprintf
                                ("  --> PTE : PPN=%X.%05X000 CMR=%X %s\n",
                                 (vv & 0xF0000000) >> 28,
                                 (vv & 0x0FFFFF00) >> 8, (vv & 0xE0) >> 5,
                                 acctxt[(vv & 0x1C) >> 2]);
                        } else {
                            uprintf
                                ("                          VA=%08X  -> %08X",
                                 (i << 24) + (j << 18) + (k << 12), vv);
                            uprintf("  --> PTD : PPN=%X.%06X00\n",
                                    (vv & 0xF0000000) >> 28,
                                    (vv & 0x0FFFFFF0) >> 4);
                            //ep=vv<<4L;
                        }
                    }
                }
            }
        }
    }
}

//####################################################################

int cmd_flush(unsigned p,int argc,char *argv[])
{
    uint32_t v;
    int i;

    if (argc<2) {
        uprintf("Entire FLUSH\n");
        for (i = 0; i < 0x1000; i += 0x20) {
            dbg_write_dtag(i, 0);
            dbg_write_itag(i, 0);
        }
        return 0;
    }
    
    if (parseint32(argv[1], &v))
        return -1;
    dbg_flush(v);
    return 0;
}

int cmd_tag(unsigned p,int argc,char *argv[])
{
    uint32_t i, v;
    
    uprintf("DATA TAGS\n");
    uprintf("Index :   TAG     :     VA     CTX   S  V\n");
    for (i = 0; i < 0x1000; i += 0x20) {
        v = dbg_read_dtag(i);
        uprintf("  %3X : %08X  =  %08X   %02X   %i  %i\n", i, v,
                BIF(v, 31, 12) * 4096, BIF(v, 11, 4), BIK(v, 1), BIK(v,
                                                                     0));
    }
    uprintf("\n");
    uprintf("INSTRUCTION TAGS\n");
    uprintf("Index :   TAG     :     VA     CTX   S  V\n");
    for (i = 0; i < 0x1000; i += 0x20) {
        v = dbg_read_itag(i);
        uprintf("  %3X : %08X  =  %08X   %02X   %i  %i\n", i, v,
                BIF(v, 31, 12) * 4096, BIF(v, 11, 4), BIK(v, 1), BIK(v,
                                                                     0));
    }
    return 0;
}

//####################################################################

const char *SCSI_PHASE[] ={"DOUT","DIN ","CMD ","STAT","100?","101?","MOUT","MIN "};
const char *SCSI_STATE[] ={"IDLE       ","INFO_TR    ","INFO_TR_END","INFO_TR_CHG",
                           "ICCS       ","ICCS_BIS   ","ICCS_TER   ","SELECT     ",
                           "SELECT_ATN ","SELECT_ATN2","SELECT_CMD ","SELECT_FIN ",
                           "NOSEL      "," ????      "," ????      "," ????      "};

#define X(v,a,b) (((unsigned long long)v>>(unsigned long long)a) & ( (1LL<<(unsigned long long)b)-1LL))

int cmd_trace_scsi(unsigned p,int argc,char *argv[])
{
    uint32_t conf,ptr,ptrin,ptrout;
    uint64_t tab[20000/*8192*/];
    uint64_t v;
    FILE *fil;
    conf=dbg_scsi_conf(p);
    ptr=dbg_scsi_ptr (p);
    
    fil = fopen("scsi.txt", "w");
    
    ptrin=ptr & 0xFFFF;
    ptrout=ptr >>16;
    uprintf ("CONF=%04X = %i PTRIN=%d PTROUT=%d\n",conf,(1<<conf),ptrin,ptrout);
    fprintf (fil,"CONF=%04X = %i PTRIN=%d PTROUT=%d\n",conf,(1<<conf),ptrin,ptrout);
    
    //conf=8;
    
    dbg_scsi_read(p,tab,1<<conf);

    uprintf(">>>\n");
    fprintf(fil,">>>\n");

    for (unsigned i=0;i<1<<conf;i++) {
        v=tab[i];
        uprintf ("%4i: <%s> %02X %02X %i %i ATN=%i BSY=%i DID=%d ", // DW DR ACK REQ
                 i,SCSI_PHASE[X(v,24,3)],X(v,0,8),X(v,16,8),X(v,15,1),X(v,14,1),
                 X(v,9,1),X(v,8,1),X(v,10,3));
        uprintf ("SEL=%i PC=%3i  [%4X] ",X(v,27,1),X(v,38,10),X(v,48,16));
        //uprintf ("| %i %i %i %X\n",X(v,28,1),X(v,29,1),X(v,30,1),X(v,32,5)); // RD WR ACK LBA
        uprintf ("| %s\n",SCSI_STATE[X(v,28,4)]);
        
        fprintf (fil,"%4i: <%s> %02X %02X %i %i ATN=%i BSY=%i DID=%d ",
                 i,SCSI_PHASE[X(v,24,3)],X(v,0,8),X(v,16,8),X(v,15,1),X(v,14,1),
                 X(v,9,1),X(v,8,1),X(v,10,3));
        fprintf (fil,"SEL=%i PC=%3i  [%4X] ",X(v,27,1),X(v,38,10),X(v,48,16));
        //fprintf (fil,"| %i %i %i %X\n",X(v,28,1),X(v,29,1),X(v,30,1),X(v,32,5));
        fprintf (fil,"| %s\n",SCSI_STATE[X(v,28,4)]);   
    }
    fclose(fil);
    return 0;
 /*   
  aux<=unsigned(sd_lba(5 DOWNTO 0) & '0' & sd_ack & sd_wr & sd_rd);
 
    sig( 7 DOWNTO  0)<=scsi_w.d;
      sig(15 DOWNTO  8)<=ack_v & req_v & scsi_w.rst & scsi_w.did & scsi_w.atn & scsi_w.bsy;
      sig(23 DOWNTO 16)<=scsi_r.d;
      sig(31 DOWNTO 24)<=aux(3 DOWNTO 0) & scsi_r.sel & scsi_r.phase;
      
      sig(47 DOWNTO 32)<=scsi_r.d_pc(9 DOWNTO 0) & aux(9 DOWNTO 4);
      sig(63 DOWNTO 48)<=timecode;

  */
}

int cmd_trace_scsi_conf(unsigned p,int argc,char *argv[])
{
    uint32_t v;

    if (argc<2)
        return -1;
    if (parseint32(argv[1], &v))
        return -1;
    
    dbg_scsi_setup(p,v);
    return 0;
}

//####################################################################
int cmd_trace(unsigned p,int argc,char *argv[])
{
    uint32_t a, dw, dr, pp, stat, off;
    unsigned i, j;
    char *bl;
    char ctxt[100];
    uint32_t tab_a[512], tab_dw[512], tab_pp[512], tab_dr[512];
    
/*
     0 : TR : A
     1 : TR : DW
     2 : TR : timecode / control
     3 : TR : DR
     4 : SIGS_H
     5 : SIGS_L

   31:28 : AH[35:32] / TimeCode(15:12)
   27:16 : TimeCode(11:0)
   15:14 : Burst
   13:12 : MODE
   11:8  : BE[0:3]
    7:6  : "00"
    5:0  : ASI
*/
    stat = dbg_trace_stat(p & 15);
    uprintf("STAT=%X\n", stat);
    stat = dbg_trace_stat(p & 15);
    uprintf("STAT=%X\n", stat);
    
    dbg_trace_read(p & 15,0,tab_a ,512);
    dbg_trace_read(p & 15,1,tab_dw,512);
    dbg_trace_read(p & 15,2,tab_pp,512);
    dbg_trace_read(p & 15,3,tab_dr,512);

    off = 0;
    for (i = 0; i < 512; i++) {
        j = (i + off) & 511;
        a  = tab_a[j];
        dw = tab_dw[j];
        pp = tab_pp[j];
        dr = tab_dr[j];

        if ((pp & 0xC000) == 0x0000)
            bl = "..";
        else if ((pp & 0xC000) == 0x4000)
            bl = "B2";
        else if ((pp & 0xC000) == 0x8000)
            bl = "B4";
        else if ((pp & 0xC000) == 0xC000)
            bl = "B8";

        if (brut64) {
            char sdra,sra;
            int dra=(pp >> 30) & 3;
            int ra=(pp >> 28) & 3;
            if (ra==0) sra=' '; else if (ra==1) sra='.'; else if (ra==2) sra=','; else sra='#';
            if (dra==0) sdra=' '; else if (dra==1) sdra='.'; else if (dra==2) sdra=','; else sdra='#';
            uprintf("  > %02X : %3i/%3i %c %i %c%c(%08X) = ", pp & 0x3F, j, i, (pp&0x1000)?'W':'R',a&7,sra,sdra, a&~7);
        } else {
            uprintf("  > %02X : %3i/%3i  %c (%X_%08X) = ", pp & 0x3F, j, i, (pp&0x1000)?'W':'R',(pp >> 28) & 15, a);        
        }
        
        if (pp & 0x1000) {
            // Ecriture
            if (pp & 0x800)
                uprintf("%02X", (dw >> 24) & 255);
            else
                uprintf("  ");
            if (pp & 0x400)
                uprintf("%02X", (dw >> 16) & 255);
            else
                uprintf("  ");
            if (pp & 0x200)
                uprintf("%02X", (dw >> 8) & 255);
            else
                uprintf("  ");
            if (pp & 0x100)
                uprintf("%02X", (dw) & 255);
            else
                uprintf("  ");
            uprintf(" %s  @%4X", bl, (pp >> 16) & 0xFFFF);
            if (p&16)
                uprintf (": %s",symboli(a));
            if (p&32) {
                disassemble(ctxt, dw, a);
                uprintf(" : %s", ctxt);
            }
        } else {
            // Lecture
            uprintf("%08X %s  @%4X", dr, bl, (pp >> 16) & 0xFFFF);
            if (p&16)
                uprintf (": %s",symboli(a));
            if (p&32) {
                disassemble(ctxt, dr, a);
                uprintf (": %s",ctxt);
            }
        }
        uprintf ("\n");
        
    }
}

int cmd_trace_brut(unsigned p,int argc,char *argv[])
{
    uint32_t a, dw, dr, pp, cpt, off,stat;
    unsigned i, j;
    char *bl;
    uint32_t tab_a[512], tab_dw[512], tab_pp[512], tab_dr[512];

    stat = dbg_trace_stat(p & 15);
    uprintf("STAT=%X\n", stat);

    dbg_trace_read(p & 15,0,tab_a ,512);
    dbg_trace_read(p & 15,1,tab_dw,512);
    dbg_trace_read(p & 15,2,tab_pp,512);
    dbg_trace_read(p & 15,3,tab_dr,512);
    
    off = 0; //cpt & 65535;
    for (i = 0; i < 512; i++) {
        j = (i + off) & 511;
        a  = tab_a[j];
        dw = tab_dw[j];
        pp = tab_pp[j];
        dr = tab_dr[j];

        if ((pp & 0xC000) == 0x0000)
            bl = "..";
        else if ((pp & 0xC000) == 0x4000)
            bl = "B2";
        else if ((pp & 0xC000) == 0x8000)
            bl = "B4";
        else if ((pp & 0xC000) == 0xC000)
            bl = "B8";

        if (brut64) {
            char sdra,sra;
            int dra=(pp >> 30) & 3;
            int ra=(pp >> 28) & 3;
            if (ra==0) sra=' '; else if (ra==1) sra='.'; else if (ra==2) sra=','; else sra='#';
            if (dra==0) sdra=' '; else if (dra==1) sdra='.'; else if (dra==2) sdra=','; else sdra='#';
            uprintf("  > %02X : %3i/%3i %c %i %c%c(%08X) = ", pp & 0x3F, j, i, (pp&0x1000)?'W':'R',a&7,sra,sdra, a&~7);
        } else {
            uprintf("  > %02X : %3i/%3i  %c (%X_%08X) = ", pp & 0x3F, j, i, (pp&0x1000)?'W':'R',(pp >> 28) & 15, a);        
        }
            uprintf(" <");

            if (pp & 0x800)
                uprintf("X");
            else
                uprintf(" ");
            if (pp & 0x400)
                uprintf("X");
            else
                uprintf(" ");
            if (pp & 0x200)
                uprintf("X");
            else
                uprintf(" ");
            if (pp & 0x100)
                uprintf("X");
            else
                uprintf(" ");
                uprintf("> ");
        uprintf("%02X", (dw >> 24) & 255);
        uprintf("%02X", (dw >> 16) & 255);
        uprintf("%02X", (dw >> 8) & 255);
        uprintf("%02X", (dw) & 255);
        uprintf("  %08X %s  @%4X\n", dr, bl, (pp >> 16) & 0xFFFF);

    }

}

//--------------------------------------------------------------------
int cmd_trace_sig(unsigned p,int argc,char *argv[])
{
    uint32_t stat, off;
    unsigned i;
    char *bl;
    uint32_t tab_s1[512], tab_s2[512];
    
    stat = dbg_trace_stat(p);
    uprintf("STAT=%X\n", stat);

    dbg_trace_read(p,4,tab_s1,512);
    dbg_trace_read(p,5,tab_s2,512);
    

    for (i = 0; i < 512; i++) {
        uprintf("   : %3i > %8X %8X\n", i, tab_s1[i], tab_s2[i]);
    }

}

/**************************************************************************************************/

int cmd_trace_adrs(unsigned p,int argc,char *argv[])
{
   
}

int cmd_trace_conf(unsigned p,int argc,char *argv[])
{
    uint32_t v;
    if (argc<2)
        return -1;
    if (parseint32(argv[1], &v))
        return -1;

    dbg_trace_conf(p,v);
    return 0;
}

int cmd_trace_stat(unsigned p,int argc,char *argv[])
{
    uint32_t stat,parm;
    stat=dbg_trace_stat(p);
    parm=dbg_trace_parm(p);
    
    uprintf ("STAT=%08X PARM=%08X\n",stat,parm);
    return 0;
}

int cmd_trace_start(unsigned p,int argc,char *argv[])
{
    uint32_t v;
    
    /*
    dbg_trace_start(p,2); // CLR
    dbg_trace_start(p,1); // START
    */
    
    if (argc<2)
        return -1;
    if (parseint32(argv[1], &v))
        return -1;
    
    dbg_trace_start(p,v);
    return 0;
}


//####################################################################

char *Phases[] = { "'Data OUT'", "'Data IN'", "'Command'", "'Status'",
    "'Reserved'", "'Reserved'", "'Msg OUT'", "'Msg IN'"
};

int cmd_peri(unsigned p,int argc,char *argv[])
{
    uint32_t v, v2, v3;
    uint16_t cop;

    v = dbg_read_pmem32(map.iommu_base);
    uprintf("[%X.%08X] IOMMU Control             = %08X\n",
            AHI(map.iommu_base), ALO(map.iommu_base),  (int) v);
    uprintf("                        IMP/VER=%X ENA=%i RANGE=%i (%iMo)\n",
            (int) (v >> 28), (int) (v & 1), (int) ((v & 0x1C) >> 2),
            (int) (16 << ((v & 0x1C) >> 2)));
/*
 16Mo  =  4096 * 4k --> Table 16ko
 64Mo  = 16384 * 4k --> Table 64ko
 256Mo = 65536 * 4k --> Table 256ko
*/

    v = dbg_read_pmem32(map.iommu_base + 4);
    v2 = v;
    uprintf("[%X.%08X] IOMMU Base Address  = %08X_0\n",
         AHI(map.iommu_base + 4), ALO(map.iommu_base + 4), (int) v);

    v = dbg_read_pmem32(map.dma_base);
    uprintf
        ("[%X.%08X] DVMA SCSI Control/Status  = %08X EnDMA=%i WRITE=%i RESET=%i IENA=%i INT=%i\n",
         AHI(map.dma_base), ALO(map.dma_base),
         (int) v, (int) ((v >> 9) & 1), (int) ((v >> 8) & 1),
         (int) ((v >> 7) & 1), (int) ((v >> 4) & 1), (int) (v & 1));

    v = dbg_read_pmem32(map.dma_base + 4);
    v3 = v;
    uprintf("[%X.%08X] DVMA SCSI Address         = %08X\n", 
            AHI(map.dma_base + 4), ALO(map.dma_base + 4), (int) v);

    v = v2 * 16 + ((v3 & 0x0FFFF000) >> 10);
    uprintf
        ("             DVMA pointeur                      (256M) = %08X\n",
         v);

    v = dbg_read_pmem32(map.dma_base + 0x1C);
// v3=v;
    uprintf("[%X.%08X] DVMA LANCE Address        = %08X\n", 
            AHI(map.dma_base + 0x1C), ALO(map.dma_base + 0x1C), (int) v);

    v = dbg_read_pmem32(map.intctl_base);
    uprintf("[%X.%08X] Proc 0 Interrupt Pending  = %08X\n",
            AHI(map.intctl_base), ALO(map.intctl_base), (int) v);

    v = dbg_read_pmem32(map.intctl_base + 0x10000);
    uprintf("[%X.%08X] System Interrupt Pending  = %08X\n",
            AHI(map.intctl_base + 0x10000), ALO(map.intctl_base + 0x10000), (int) v);

    v = dbg_read_pmem32(map.intctl_base + 0x10004);
    uprintf("[%X.%08X] System Interrupt Mask     = %08X\n",
            AHI(map.intctl_base + 0x10004), ALO(map.intctl_base + 0x10004), (int) v);

    v = dbg_read_pmem32(map.counter_base);
    uprintf("[%X.%08X] Proc 0 Limit   MSW        = %08X\n",
            AHI(map.counter_base), ALO(map.counter_base), (int) v);

    v = dbg_read_pmem32(map.counter_base + 4);
    uprintf("[%X.%08X] Proc 0 Counter LSW        = %08X\n",
            AHI(map.counter_base + 4), ALO(map.counter_base + 4), (int) v);

    v = dbg_read_pmem32(map.counter_base + 8);
    uprintf("[%X.%08X] Proc Limit              = %08X\n",
            AHI(map.counter_base + 8), ALO(map.counter_base + 8), (int) v);

    v = dbg_read_pmem32(map.counter_base + 0x10000);
    uprintf("[%X.%08X] Sys  Limit              = %08X = %i\n", 
            AHI(map.counter_base + 0x10000), ALO(map.counter_base + 0x10000),
            (int) v, (int) ((v & 0x7FFFFFFF) >> 9));

    v = dbg_read_pmem32(map.counter_base + 0x10004);
    uprintf("[%X.%08X] Sys  Counter            = %08X = %i\n",
            AHI(map.counter_base + 0x10004), ALO(map.counter_base + 0x10004),
            (int) v, (int) ((v & 0x7FFFFFFF) >> 9));

    cop = dbg_read_pmem16(map.le_base + 2);

    dbg_write_pmem16(map.le_base + 2, 0);
    v = dbg_read_pmem16(map.le_base);
    uprintf("[%X.%08X] LANCE        CSR0       = %04X (miss & '00' & miss & '0' & rint & tint & idon)\n"
            "                               (intr & inea & rxon & txon & '0' & stop & strt & init)\n",
            AHI(map.le_base), ALO(map.le_base),(int) v);

    dbg_write_pmem16(map.le_base + 2, 1);
    v = dbg_read_pmem16(map.le_base);
    uprintf("[%X.%08X] LANCE        CSR1       = %04X (iadr(15 DOWNTO 1) & '0')\n",
         AHI(map.le_base), ALO(map.le_base),(int) v);

    dbg_write_pmem16(map.le_base + 2, 2);
    v = dbg_read_pmem16(map.le_base);
    uprintf
        ("[%X.%08X] LANCE        CSR2       = %04X (iadr(23 DOWNTO 16))\n",
         AHI(map.le_base), ALO(map.le_base),(int) v);

    dbg_write_pmem16(map.le_base + 2, 3);
    v = dbg_read_pmem16(map.le_base);
    uprintf("[%X.%08X] LANCE        CSR3       = %04X (bswp)\n",
            AHI(map.le_base), ALO(map.le_base),(int) v);

    /*
       dbg_write_pmem16(map.le_base + 2,4);
       v=dbg_read_pmem16(map.le_base);
       uprintf ("LANCE        CSR4       = %04X (dma_rd & dma_wr & dma_rw & dma_busy & to_unsigned(pc,8)\n",(int)v); 

       dbg_write_pmem16(map.le_base + 2,5);
       v=dbg_read_pmem16(map.le_base);
       uprintf ("LANCE        CSR5       = %04X ('0000' & init_pend & txon & rec_r.fifordy & rec_r.eof & \n"
       "                                emi_r.fifordy & rec_r.crcok & rec_r.deof & '00000')\n",(int)v); 

       dbg_write_pmem16(map.le_base + 2,6);
       v=dbg_read_pmem16(map.le_base);
       uprintf ("LANCE        CSR6       = %04X (rec_r.len)\n",(int)v); 

       dbg_write_pmem16(map.le_base + 2,7);
       v=dbg_read_pmem16(map.le_base);
       uprintf ("LANCE        CSR7       = %04X (rx_act & rmd_cpt & tx_act & tmd_cpt)\n",(int)v);

       dbg_write_pmem16(map.le_base + 2,8);
       v=dbg_read_pmem16(map.le_base);
       uprintf ("LANCE        CSR8       = %04X (initvec(15 DOWNTO 0) = mode)\n",(int)v); 

       dbg_write_pmem16(map.le_base + 2,9);
       v=dbg_read_pmem16(map.le_base);
       uprintf ("LANCE        CSR9       = %04X (initvec(31 DOWNTO 16) = padr[15:0])\n",(int)v); 

       dbg_write_pmem16(map.le_base + 2,10);
       v=dbg_read_pmem16(map.le_base);
       uprintf ("LANCE        CSR10      = %04X (initvec(47 DOWNTO 32) = padr[31:16])\n",(int)v); 

       dbg_write_pmem16(map.le_base + 2,11);
       v=dbg_read_pmem16(map.le_base);
       uprintf ("LANCE        CSR11      = %04X (initvec(63 DOWNTO 48) = padr[47:32])\n",(int)v); 

       dbg_write_pmem16(map.le_base + 2,12);
       v=dbg_read_pmem16(map.le_base);
       uprintf ("LANCE        CSR12      = %04X (RDRA(15:3))\n",(int)v); 

       dbg_write_pmem16(map.le_base + 2,13);
       v=dbg_read_pmem16(map.le_base);
       uprintf ("LANCE        CSR13      = %04X (RLEN | RDRA(23:16))\n",(int)v); 

       dbg_write_pmem16(map.le_base + 2,14);
       v=dbg_read_pmem16(map.le_base);
       uprintf ("LANCE        CSR14      = %04X (TDRA(15:3))\n",(int)v); 

       dbg_write_pmem16(map.le_base + 2,15);
       v=dbg_read_pmem16(map.le_base);
       uprintf ("LANCE        CSR15      = %04X (TLEN | TDRA(23:16))\n",(int)v); 

       dbg_write_pmem16(map.le_base + 2,16);
       v=dbg_read_pmem16(map.le_base);
       uprintf ("LANCE        CSR16      = %04X (RMD(15:0) = LADR)\n",(int)v); 

       dbg_write_pmem16(map.le_base + 2,17);
       v=dbg_read_pmem16(map.le_base);
       uprintf ("LANCE        CSR17      = %04X (RMD(31:16) = OWN / ERR ... HADR)\n",(int)v); 

       dbg_write_pmem16(map.le_base + 2,18);
       v=dbg_read_pmem16(map.le_base);
       uprintf ("LANCE        CSR18      = %04X (RMD(47:32) = BCNT)\n",(int)v); 

       dbg_write_pmem16(map.le_base + 2,19);
       v=dbg_read_pmem16(map.le_base);
       uprintf ("LANCE        CSR19      = %04X (RMD(63:48) = MCNT)\n",(int)v); 


       dbg_write_pmem16(map.le_base + 2,20);
       v=dbg_read_pmem16(map.le_base);
       uprintf ("LANCE        CSR20      = %04X (TMD(15:0) = LADR)\n",(int)v); 

       dbg_write_pmem16(map.le_base + 2,21);
       v=dbg_read_pmem16(map.le_base);
       uprintf ("LANCE        CSR21      = %04X (TMD(31:16) = OWN / ERR ... HADR)\n",(int)v); 

       dbg_write_pmem16(map.le_base + 2,22);
       v=dbg_read_pmem16(map.le_base);
       uprintf ("LANCE        CSR22      = %04X (TMD(47:32) = BCNT)\n",(int)v); 

       dbg_write_pmem16(map.le_base + 2,23);
       v=dbg_read_pmem16(map.le_base);
       uprintf ("LANCE        CSR23      = %04X (TMD(63:48) = ...\n",(int)v); 

       dbg_write_pmem16(map.le_base + 2,24);
       v=dbg_read_pmem16(map.le_base);
       uprintf ("LANCE        CSR24      = %04X (EMI CPT_OUT / CPT_IN)\n",(int)v); 

       dbg_write_pmem16(map.le_base + 2,25);
       v=dbg_read_pmem16(map.le_base);
       uprintf ("LANCE        CSR25      = %04X (EMI LEV)\n",(int)v); 

       dbg_write_pmem16(map.le_base + 2,26);
       v=dbg_read_pmem16(map.le_base);
       uprintf ("LANCE        CSR26      = %04X (REC CPT_OUT / CPT_IN)\n",(int)v); 

       dbg_write_pmem16(map.le_base + 2,27);
       v=dbg_read_pmem16(map.le_base);
       uprintf ("LANCE        CSR27      = %04X (REC LEV)\n",(int)v); 

     */

    dbg_write_pmem16(map.le_base + 2, cop);

    v = dbg_read_pmem32(map.esp_base + 0x34);
    uprintf("[%X.%08X] ESP          PC=%i PHASE=%s BSY=%i ATN=%i\n",
            AHI(map.esp_base + 0x34), ALO(map.esp_base + 0x34),
            (unsigned) (v >> 16), Phases[(v & 7)], (v >> 7) & 1,
            (v >> 6) & 1);

    v = dbg_read_pmem32(map.esp_base + 0x38);
/* uprintf ("[E_F0800038] ESP          LEN=%i CMD=%2X\n",
          (unsigned)(v>>16),v&255);*/
    uprintf("[%X.%08X] ESP          %08X\n",
            AHI(map.esp_base + 0x38), ALO(map.esp_base + 0x38), (unsigned) v);

    v = dbg_read_pmem32(map.esp_base + 0x3C);
    uprintf("[%X.%08X] ESP          LENI=%i CMD=%2X\n",
            AHI(map.esp_base + 0x3C), ALO(map.esp_base + 0x3C), (unsigned) (v >> 16), v & 255);

    return 0;
}


uint8_t hexread(char *v)
{
    uint8_t d;
    d=(*v>'9')?(*v-'A'+10):(*v-'0');
    v++;
    d=(d<<4) | ((*v>'9')?(*v-'A'+10):(*v-'0'));
    return d;
}

int cmd_file(unsigned p,int argc,char *argv[])
{
    int i;
    int t = 0;
    char *filename;
    char tmp[100];
    uint8_t txt[50];
    uint32_t d,e;
    FILE *fil;
    uint32_t base,len;
    uint32_t ad=0xFFFFFFFF;
    uint32_t ae=0xFFFFFFFF;
    
    if (argc<3)
        return -1;
    if (parseint32(argv[1], &base))
        return -1;

    filename=argv[2];
    
    uprintf ("ADRS=%X FILE=:%s:\n",base,filename);
    fil = fopen(filename, "r");
    if (!fil) {
        uprintf ("No File\n");
        return -1;
    }
    
    testchar();
    testchar();
    testchar();
    testchar();
    
    do {
        fgets(tmp, 999, fil);
        if (tmp[0]!='S') return -1;
        len=strlen(tmp);
        switch (tmp[1]) {
            case '0': // S0 ll aaaa 00112233445566....     CC A16/ Init
                for (i=8;i<len-2;i+=2) txt[(i-8)/2]=hexread(&tmp[i]);
                txt[(len-10)/2]=0;
                uprintf ("FileName = %s\n",txt);
                break;
                
            case '1': // S1 ll aaaa 00112233445566....     CC A16 / Data
                ad=(hexread(&tmp[4])<<8) | hexread(&tmp[6]);
                if (ae==0xFFFFFFFF) ae=ad;
                for (i=8;i<len-2;i+=2) txt[(i-8)/2]=hexread(&tmp[i]);
                len=(len-2-8-2)/2;
                for (i=0;i<len;i+=4) {
                    d=(txt[i]<<24)  | (txt[i+1]<<16) | (txt[i+2]<<8) | (txt[i+3]);
                    e=(txt[i+4]<<24)  | (txt[i+5]<<16) | (txt[i+6]<<8) | (txt[i+7]);
                    if (i-len>=8) {
                        dbg_write_pmem64(base+ad-ae+i,((uint64_t)d << 32LL) | e);
                        uprintf (" %08X %08X",d,e);
                        i+=4;
                    }
                    else {
                        dbg_write_pmem32(base+ad-ae+i,d);
                        uprintf (" %08X",d);
                    }
                }
                uprintf ("\n");
                break;
                
            case '2': // S2 ll aaaaaa 00112233445566....   CC A24 / Data
                ad=(hexread(&tmp[4])<<16) | (hexread(&tmp[6])<<8) |
                    hexread(&tmp[8]);
                if (ae==0xFFFFFFFF) ae=ad;
                for (i=10;i<len-2;i+=2) txt[(i-10)/2]=hexread(&tmp[i]);
                len=(len-2-10-2)/2;
                uprintf ("> W %08X :",base+ad-ae);
                for (i=0;i<len;i+=4) {
                    d=(txt[i]<<24)  | (txt[i+1]<<16) | (txt[i+2]<<8) | (txt[i+3]);
                    e=(txt[i+4]<<24)  | (txt[i+5]<<16) | (txt[i+6]<<8) | (txt[i+7]);
                    if (i-len>=8) {
                        dbg_write_pmem64(base+ad-ae+i,((uint64_t)d << 32LL) | e);
                        uprintf (" %08X %08X",d,e);
                        i+=4;
                    }
                    else {
                        dbg_write_pmem32(base+ad-ae+i,d);
                        uprintf (" %08X",d);
                    }
                }
                uprintf ("\n");
                break;
                
            case '3': // S3 ll aaaaaaaa 00112233445566.... CC A32 / Data
                ad=(hexread(&tmp[4])<<24) | (hexread(&tmp[6])<<16) |
                   (hexread(&tmp[8])<<8)  | hexread(&tmp[10]);
                if (ae==0xFFFFFFFF) ae=ad;
                for (i=12;i<len-2;i+=2) txt[(i-12)/2]=hexread(&tmp[i]);
                len=(len-2-12-2)/2;
                uprintf ("> W %08X :",base+ad-ae);
                for (i=0;i<len;i+=4) {
                    d=(txt[i]<<24)  | (txt[i+1]<<16) | (txt[i+2]<<8) | (txt[i+3]);
                    e=(txt[i+4]<<24)  | (txt[i+5]<<16) | (txt[i+6]<<8) | (txt[i+7]);
                    if (i-len>=8) {
                        dbg_write_pmem64(base+ad-ae+i,((uint64_t)d << 32LL) | e);
                        uprintf (" %08X %08X",d,e);
                        i+=4;
                    }
                    else {
                        dbg_write_pmem32(base+ad-ae+i,d);
                        uprintf (" %08X",d);
                    }
                }
                uprintf ("\n");
                break;
                
        }
        if (testchar()) break;
    } while (!feof(fil));
    
    fclose(fil);
    return 0;
}

int cmd_map(unsigned p,int argc,char *argv[])
{
    char *filename;
    
    if (argc<2)
        return -1;

    filename=argv[1];
    
    uprintf ("FILE=:%s:\n",filename);
    razmap();
    readmap(filename);

    return 0;
}

//--------------------------------------------------------------------

int cmd_palinit(unsigned p,int argc,char *argv[])
{
    uint32_t v;
    int t = 0, t2 = 0;

    v=0;
    if (argc>1)
        if (parseint32(argv[1], &v))
            return -1;
    
    unsigned i, j;
    unsigned r, g, b;
    for (i = 0; i < 256; i++) {
        r = ((i & 7) << 5);
        g = (i & 0x70) << 1;
        b = (i & 0x80) | (i & 8) << 3;
        if (i < 128)
            g = (~g) & 0xE0;
        if ((i & 15) < 8)
            r = (~r) & 0xE0;
        if (v==1) {
            r=i;
            g=i;
            b=i;
        } else if (v==2) {
            r=(i&1)?255:0;
            g=(i&2)?255:0;
            b=(i&4)?255:0;
        }
        dbg_write_pmem32(map.tcx_base + 0x200000, i << 24);
        dbg_write_pmem32(map.tcx_base + 0x200004, r << 24);
        dbg_write_pmem32(map.tcx_base + 0x200004, g << 24);
        dbg_write_pmem32(map.tcx_base + 0x200004, b << 24);
        uprintf ("%2X %2X %2X %2X\n",i,r,g,b);
        //set_color( i, r*65536+g*256+b );
    }
}

int cmd_screen(unsigned p,int argc,char *argv[])
{
    unsigned x, y, i;
    uint64_t v64, v64_2, v64_3, v64_4;
    uint32_t v32, adrs;
    uint16_t v16;
    char c, r, v, b;
    char tmp[1024];
    FILE *fil;

    uprintf(">>>\n");
    fil = fopen("pic.bmp", "w");

    //Header (14)
    fwrite("BM", 2, 1, fil);    // BM hreader
    v32 = 14 + 40 + 256 * 4 + 768 * 1024;
    fwrite(&v32, 4, 1, fil);    // Size
    v32 = 0;
    fwrite(&v32, 4, 1, fil);    // Reserved
    v32 = 14 + 40 + 256 * 4;
    fwrite(&v32, 4, 1, fil);    // Offset

    //BITMAPINFOHEADER (40)
    v32 = 40;
    fwrite(&v32, 4, 1, fil);    // Header length
    v32 = 1024;
    fwrite(&v32, 4, 1, fil);    // Width
    v32 = -768;
    fwrite(&v32, 4, 1, fil);    // Height
    v16 = 1;
    fwrite(&v16, 2, 1, fil);    // Color planes
    v16 = 8;
    fwrite(&v16, 2, 1, fil);    // Bits per pixel
    v32 = 0;
    fwrite(&v32, 4, 1, fil);    // No compression
    v32 = 768 * 1024;
    fwrite(&v32, 4, 1, fil);    // Raw data size
    v32 = 2000;
    fwrite(&v32, 4, 1, fil);    // H resolution
    v32 = 2000;
    fwrite(&v32, 4, 1, fil);    // V resolution
    v32 = 256;
    fwrite(&v32, 4, 1, fil);    // 256 colours
    v32 = 0;
    fwrite(&v32, 4, 1, fil);    // Important colours

    //PALETTE
    uprintf("Palette :\n");
    for (i = 0; i < 256; i++) {
        dbg_write_pmem32(map.tcx_base + 0x200000, i << 24);
        uprintf("%02X : ", i);
        // R
        v32 = dbg_read_pmem32(map.tcx_base + 0x200004) >> 24;
        r = v32;
        uprintf("%02X-", v32);
        // V
        v32 = dbg_read_pmem32(map.tcx_base + 0x200004) >> 24;
        v = v32;
        uprintf("%02X-", v32);
        // B
        v32 = dbg_read_pmem32(map.tcx_base + 0x200004) >> 24;
        b = v32;
        uprintf("%02X\n", v32);
        fputc(b, fil);
        fputc(v, fil);
        fputc(r, fil);
        c = 0;
        fputc(c, fil);
    }

    testchar();
    testchar();
    testchar();
    testchar();
    //Pix
    uprintf("Image :\n");
    adrs = 0x7E00000;
    for (y = 0; y < 768; y++) {
        if ((y & 3) == 0)
            uprintf("%i/768\n", y);
        if (testchar())
            break;
        dbg_read_pmem(adrs, tmp, 1024);
        fwrite(tmp, 1024, 1, fil);
        adrs += 1024;
    }
    fclose(fil);

    return 0;
}

int cmd_ss5_20(unsigned p,int argc,char *argv[])
{
    if (p == 0) {
        map=MAP_SS5;
    } else {
        map=MAP_SS20;
    }

    return 0;
}


int cmd_echo(unsigned p,int argc,char *argv[])
{
    uint32_t v;
    
    if (argc<2)
        return -1;
    if (parseint32(argv[1], &v))
        return -1;
    
    uprintf (">%X< %d\n",v,v);
    return 0;
}

//####################################################################

typedef struct {
    char     *name[5];
    FUNC     *func;
    uint32_t p;
    uint32_t rs; // 1 : Run 2 : Stop 3 : Run &stop
    char     *doc;
} COMMAND;


COMMAND commands[] = {
    {{"help","h",0},    cmd_help,  0, 3, "List commands"},
    {{"quit","q","exit","abort",0},    cmd_quit,  0, 3, "Quit"},
    {{"fast",0},        cmd_uart,  0, 3, "Uart FAST 921600bits/s"},
    {{"slow",0},        cmd_uart,  1, 3, "Uart SLOW 115200bits/s"},

    {{"cpu",0},         cmd_cpu,   0, 3, "Select CPU"},
    {{"stop",0},        cmd_stop,  0, 1, "Stop the CPU"},
    {{"run",0},         cmd_run,   0, 2, "Resume execution"},
    {{"runstop",0},     cmd_runstop,   0, 3, "Tewak"},
    {{"stoprun",0},     cmd_stoprun,   0, 3, "Khrow"},
    {{"s",0},           cmd_step,  0, 2, "Single Stepping"},
    {{"u",0},           cmd_stepc, 0, 2, "Single Stepping Call"},
    {{"reset",0},       cmd_reset, 0, 2, "RESET CPU. Init registers"},
    {{"hreset",0},      cmd_hreset,0, 3, "Total HW RESET"},
    {{"stat",0},        cmd_stat,  0, 3, "CPU status"},
    {{"ib",0},          cmd_ibrk,  0, 3, "Instruction breakpoint"},
    {{"db",0},          cmd_dbrk,  0, 3, "Data breakpoint"},
    {{"brk",0},         cmd_brk,   0, 3, "List breakpoints"},
    
    {{"r","reg",0},     cmd_reg,   0, 2, "Read registers"},
    {{"w","wreg",0},    cmd_wreg,  0, 2, "Write Register (int,fp,sys)"},
    {{"fr","freg",0},   cmd_freg,  0, 2, "Read floating-point registers"},
    {{"dfq",0},         cmd_dfq,   0, 2, "FP queue pop instruction"},
    {{"rwin",0},        cmd_reg_win, 0, 2, "Backtrace"},
    {{"rall",0},        cmd_reg_dump, 0, 2, "Integer Register Dump All"},
    
    {{"d","d4","vd","vd4",0}, cmd_vd4, 0, 2, "Virtual Memory Dump 32bits : d address [length]"},
    {{"p","pd","pd4",0}, cmd_pd4, 0, 2, "Physical Memory Dump 32bits : p address [length]"},
    {{"asir","asir4",0}, cmd_asir, 3, 2, "ASI Memory Read 32bits : asir asi adress"},
    {{"asiw","asiw4",0}, cmd_asiw, 3, 2, "ASI Memory Write 32bits : asiw asi adress data"},
    
    {{"pr8",0},         cmd_pr, 4, 2, "Physical Memory Read 64bits : pr8 address"},
    {{"pr","pr4",0},    cmd_pr, 3, 2, "Physical Memory Read 32bits : pr address"},
    {{"pr2",0},         cmd_pr, 1, 2, "Physical Memory Read 16bits : pr2 address"},
    {{"pr1",0},         cmd_pr, 0, 2, "Physical Memory Read 8bits : pr1 address"},
    
    {{"pw","pw4",0},    cmd_pw ,3, 2, "Physical Memory Write 32bits : pw address data"},
    {{"pw2",0},         cmd_pw ,1, 2, "Physical Memory Write 16bits : pw2 address data"},
    {{"pw1",0},         cmd_pw ,0, 2, "Physical Memory Write 8bits : pw1 address data"},
    
    {{"vr","vr4",0},    cmd_vr, 3, 2, "Virtual Memory Read 32bits : pr address"},
    {{"vr2",0},         cmd_vr, 1, 2, "Virtual Memory Read 16bits : pr2 address"},
    {{"vr1",0},         cmd_vr, 0, 2, "Virtual Memory Read 8bits : pr1 address"},
    
    {{"vw","vw4",0},    cmd_vw ,3, 2, "Virtual Memory Write 32bits : pw address data"},
    {{"vw2",0},         cmd_vw ,1, 2, "Virtual Memory Write 16bits : pw2 address data"},
    {{"vw1",0},         cmd_vw ,0, 2, "Virtual Memory Write 8bits : pw1 address data"},
    
    {{"pf","pf4",0},    cmd_pf4, 0, 2, "Physical Memory Fill 32bits : pf address lenght data"},
    
    {{"dis","disas",0}, cmd_disa,0, 2, "Disassemble"},
    {{"disi",0},        cmd_disa,1, 2, "Disassemble, Instruction bus"},
    
    {{"rmmu",0},        cmd_rmmu, 0, 2, "Read MMU registers"},
    {{"wmmu",0},        cmd_wmmu, 0, 2, "Write MMU registers : CR, CTPR, CTXR"},
    {{"probe",0},       cmd_probe, 0, 2, "MMU Probe"},
    {{"mmumap",0},      cmd_mmumap, 0, 2, "MMU MAP"},
    
    {{"flush","flu",0}, cmd_flush, 0, 2, "Cache Flush"},
    {{"tag",0},         cmd_tag, 0, 2, "Cache Tags dump"},
    
    {{"tr0stat",0},     cmd_trace_stat,4,3, "Trace 0 : Status"},
    {{"tr1stat",0},     cmd_trace_stat,5,3, "Trace 1 : Status"},
    {{"tr2stat",0},     cmd_trace_stat,6,3, "Trace 2 : Status"},
    {{"tr3stat",0},     cmd_trace_stat,7,3, "Trace 3 : Status"},
    
    {{"tr0conf",0},     cmd_trace_conf,4,3, "Trace 0 : Configure"},
    {{"tr1conf",0},     cmd_trace_conf,5,3, "Trace 1 : Configure"},
    {{"tr2conf",0},     cmd_trace_conf,6,3, "Trace 2 : Configure"},
    {{"tr3conf",0},     cmd_trace_conf,7,3, "Trace 3 : Configure"},
        
    {{"tr0run",0},      cmd_trace_start,4,3, "Trace 0 : Start"},
    {{"tr1run",0},      cmd_trace_start,5,3, "Trace 1 : Start"},
    {{"tr2run",0},      cmd_trace_start,6,3, "Trace 2 : Start"},
    {{"tr3run",0},      cmd_trace_start,7,3, "Trace 3 : Start"},
        
    {{"tr0s",0},        cmd_trace, 4+16, 3, "Trace : TR0 symboles"},
    {{"tr1s",0},        cmd_trace, 5+16, 3, "Trace : TR1 symboles"},
    {{"tr2s",0},        cmd_trace, 6+16, 3, "Trace : TR2 symboles"},
    {{"tr3s",0},        cmd_trace, 7+16, 3, "Trace : TR3 symboles"},
    
    {{"tr0d",0},        cmd_trace, 4+32, 3, "Trace : TR0 desassemblage"},
    {{"tr1d",0},        cmd_trace, 5+32, 3, "Trace : TR1 desassemblage"},
    {{"tr2d",0},        cmd_trace, 6+32, 3, "Trace : TR2 desassemblage"},
    {{"tr0",0},         cmd_trace, 4,    3, "Trace : TR0"},
    {{"tr1",0},         cmd_trace, 5,    3, "Trace : TR1"},
    {{"tr2",0},         cmd_trace, 6,    3, "Trace : TR2"},
    {{"tr3",0},         cmd_trace, 7,    3, "Trace : TR3"},
    
    {{"trb0",0},        cmd_trace_brut, 4, 3, "Trace Brut : TR0"},
    {{"trb1",0},        cmd_trace_brut, 5, 3, "Trace Brut : TR1"},
    {{"trb2",0},        cmd_trace_brut, 6, 3, "Trace Brut : TR2"},
    {{"tr0sig",0},      cmd_trace_sig,4, 3, "Trace : TR0 signaux"},
    {{"tr1sig",0},      cmd_trace_sig,5, 3, "Trace : TR1 signaux"},
    {{"tr2sig",0},      cmd_trace_sig,6, 3, "Trace : TR2 signaux"},

    
    {{"trsconf",0},     cmd_trace_scsi_conf,8,3, "Trace SCSI : Configure"},
    {{"trs",0},         cmd_trace_scsi,8,3,"Trace SCSI"},

    //{{"ana",0},         cmd_trace_ana,0, 3,"Analyser"},

    {{"ss5",0},         cmd_ss5_20, 0, 2, "SparcStation 5 mapping"},
    {{"ss20",0},        cmd_ss5_20, 1, 2, "SparcStation 10/20 mapping"},
    {{"peri",0},        cmd_peri,0, 2, "Sun4m peripherals"},
    {{"palinit",0},     cmd_palinit, 0, 2, "Palette"},
    {{"screen",0},      cmd_screen, 0, 2, "Dump screen"},
    {{"brut",0},        cmd_brut , 1, 3, "Brut"},
    {{"nobrut",0},      cmd_brut , 0, 3, "No brut"},
    
    {{"file",0},        cmd_file, 0, 2,"Copy file to mem"},
    {{"map",0},         cmd_map, 0, 3,"Load mapping file"},
    {{"e",0},           cmd_echo, 0,3,"Echo"},
    {{0}, NULL, 0,0,NULL}
    };

//--------------------------------------------------------------------

int cmd_help(unsigned p,int argc,char *argv[])
{
    int i, j, k;
    char **pp;
    char *colo;

    for (i = 0; pp=commands[i].name; i++) {
        if (*pp == 0) break;
        switch (commands[i].rs) {
        case 0:
            colo=ANSI_DEFAULT;
            break;
        case 1:
            colo=ANSI_VERT;
            break;
        case 2:
            colo=ANSI_ROUGE;
            break;
        case 3:
            colo=ANSI_JAUNE;
            break;
        } 
        uprintf ("  %s",colo);
        k = 0;
        for (j = 0; pp[j]; j++) {
            k += strlen(pp[j])+2;
            uprintf("%s",pp[j]);
            if (pp[j+1]) uprintf (ANSI_DEFAULT", %s",colo);
        }
        for (j = k; j < 16; j++) uprintf (" ");
        uprintf (ANSI_DEFAULT);
        uprintf (" : %s\n",commands[i].doc);
    }
/*
#define ANSI_DEFAULT "\033[0m"

#define ANSI_ROUGE "\033[31;1m"
#define ANSI_VERT  "\033[32;1m"
#define ANSI_BLEU  "\033[34;1m"
#define ANSI_JAUNE "\033[33;1m"
*/
    return 0;
}

//####################################################################

COMMAND *find_command(char *name)
{
    int i, j;
    char **p;
    for (i = 0; p=commands[i].name; i++) {
        if (*p == 0) break;
        for (j = 0; p[j]; j++) {
            if (strcmp(name, p[j]) == 0)
                return (&commands[i]);
        }
    }
    return ((COMMAND *) NULL);
}

int execute_line(char *line)
{
    unsigned i,j;
    COMMAND *command;
    char ltemp[1000];
    char *argv[100];
    unsigned argc=0,pos=0;
    unsigned state=0,quo=0;

    for (i=0,j=0;line[i] && line[i]!='\n' && line[i]!='\r' && i<1000 && argc<100;i++) {
        if (!state) {
            if (line[i]!=' ') {
                state=1;
                pos=j;
            }
        }
        if (state) {
            if (line[i]=='"' || line[i]=='\'') {
                quo=1-quo;
            } else if (line[i]==' ' && quo==0) {
                argv[argc++]=&ltemp[pos];
                ltemp[j++]=0;
                state=0;
            } else {
                ltemp[j++]=line[i];
            }
        }
    }

    ltemp[j]=0;
    
    if (quo) {
        uprintf ("Error\n");
        return -1;
    }

    if (state)
        argv[argc++]=&ltemp[pos];
    
    if (argc==0) return -1;
    
    command = find_command(argv[0]);
    if (!command) {
        uprintf("Error : %s ?\n", argv[0]);
        return -1;
    }
    if (!(command->rs & 1) && dbg_running()) {
        uprintf("Impossible : RUN\n");
        return -1;
    }
    if (!(command->rs & 2) && !dbg_running()) {
        uprintf("Impossible : STOP\n");
        return -1;
    }
    
    return ((*(command->func)) (command->p,argc,argv));
}



