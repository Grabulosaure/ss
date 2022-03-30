/* Debugger.
   DO 5/2011
*/


#include <stdint.h>
#include <stdlib.h>

//#define MODE_CTSRTS

//#define INVERTBREAK
/*
#ifdef ARM
#define SERIAL_PORT "/dev/ttyS1"
#else
#define SERIAL_PORT "/dev/ttyUSB"
#endif
*/
#define RELEASE "[r5]"
#define SERIAL_PORT "/dev/ttyS1"

//--------------------------------------------------------------------
// main.c
extern int done;
extern int saved[4];
extern int stepbrk[4];

int uprintf(const char *fmt, ...);
int dbg_running();

//--------------------------------------------------------------------
// command.c

struct break_t {
   uint32_t a; // Address
   uint32_t v; // Valid
};
extern struct break_t dbrk[4],ibrk[4];

int execute_line(char *line);
char *stripwhite(char *string);
void disas_pc();

//--------------------------------------------------------------------
// serie.c
extern int sp_fd;

int sp_init();
void sp_close();
void sp_puc(unsigned char v);
unsigned char sp_gec();

void sp_cts(int v);
int sp_rts();
void sp_break();
void sp_purge();
void sp_drain();

void sp_freq(int v);
int sp_testchar();

//--------------------------------------------------------------------
// disas.c
void disassemble(char *s, uint32_t op, uint32_t pc);
char *symboli(uint32_t a);
int symbolt(char *s,uint32_t *pv);
int readmap(const char *mapfile);
void razmap();

//--------------------------------------------------------------------
// lib.c

#define BIF(x,y,z) ((x>>z)&((1<<(y-z+1))-1))
#define BIK(x,y) BIF(x,y,y)

//void dbg_write_op(uint32_t op);
//void dbg_write_ctrl(uint32_t cmd);
void dbg_write_ibrk(uint32_t a);
void dbg_write_dbrk(uint32_t a);

void dbg_resync();

uint32_t dbg_read_data();
uint32_t dbg_read_status();
uint32_t dbg_read_status2();
uint32_t dbg_read_pc();
uint32_t dbg_read_npc();

void dbg_selcpu(int n);
uint dbg_getcpu();
uint dbg_cpus();

void dbg_init();
void dbg_prologue();
void dbg_epilogue();

int dbg_stop();
int dbg_stop_deja();
int dbg_run();
int dbg_hreset();


void dbg_nosup(int nosup);
void dbg_opt0(int v);
void dbg_opt1(int v);

void dbg_ibrk(int ib);
void dbg_dbrk(int db);
void dbg_uspeed(int v);

int dbg_ibrk_stat();
int dbg_dbrk_stat();

uint32_t dbg_read_reg(int n);
void dbg_write_reg(int n, uint32_t v);

uint32_t dbg_read_freg(int n);
void dbg_write_freg(int n,uint32_t v);
uint32_t dbg_read_fsr();
void dbg_write_fsr(uint32_t v);
void dbg_fpop(uint32_t opf,int rs1,int rs2,int rd);
uint32_t dbg_read_dfq();

#define FADDs  (0x41)
#define FADDd  (0x42)
#define FSUBs  (0x45)
#define FSUBd  (0x46)
#define FMULs  (0x49)
#define FMULd  (0x4A)
#define FsMULd (0x69)
#define FDIVs  (0x4D)
#define FDIVd  (0x4E)
#define FSQRTs (0x29)
#define FSQRTd (0x2A)
#define FMOVs  (0x1)
#define FNEGs  (0x5)
#define FABSs  (0xA)
#define FiTOs  (0xC4)
#define FiTOd  (0xC8)
#define FsTOi  (0xD1)
#define FdTOi  (0xD2)
#define FsTOd  (0xC9)
#define FdTOs  (0xC6)

uint32_t dbg_read_cop_psr();
void     dbg_write_cop_psr(uint32_t v);

uint32_t dbg_read_psr();
void     dbg_write_psr(uint32_t v);
uint32_t dbg_read_tbr();
void     dbg_write_tbr(uint32_t v);
uint32_t dbg_read_wim();
void     dbg_write_wim(uint32_t v);
uint32_t dbg_read_ry();
void     dbg_write_ry(uint32_t v);
uint32_t dbg_read_pc();
uint32_t dbg_read_npc();
void     dbg_write_cop_pc(uint32_t pc);
void     dbg_write_cop_npc(uint32_t npc);
uint32_t dbg_read_cop_pc();
uint32_t dbg_read_cop_npc();

//-----------------------------------------
void dbg_read_asimem(uint8_t asi, uint32_t a, void *p, unsigned len);
uint8_t  dbg_read_asimem8(uint8_t asi, uint32_t a);
uint16_t dbg_read_asimem16(uint8_t asi, uint32_t a);
uint32_t dbg_read_asimem32(uint8_t asi, uint32_t a);
uint64_t dbg_read_asimem64(uint8_t asi, uint32_t a);
void dbg_write_asimem8(uint8_t asi, uint32_t a, uint8_t v);
void dbg_write_asimem16(uint8_t asi, uint32_t a, uint16_t v);
void dbg_write_asimem32(uint8_t asi,uint32_t a, uint32_t v);
void dbg_write_asimem64(uint8_t asi,uint32_t a, uint64_t v);

//--------------
void     dbg_read_pmem(uint64_t a, void *p, unsigned len);
uint8_t  dbg_read_pmem8(uint64_t a);
uint16_t dbg_read_pmem16(uint64_t a);
uint32_t dbg_read_pmem32(uint64_t a);
uint64_t dbg_read_pmem64(uint64_t a);
void     dbg_write_pmem8(uint64_t a, uint8_t v);
void     dbg_write_pmem16(uint64_t a, uint16_t v);
void     dbg_write_pmem32(uint64_t a, uint32_t v);
void     dbg_write_pmem64(uint64_t a, uint64_t v);


void     dbg_read_vmem(uint32_t a,void *p, unsigned len);
uint8_t  dbg_read_vmem8(uint32_t a);
uint16_t dbg_read_vmem16(uint32_t a);
uint32_t dbg_read_vmem32(uint32_t a);
uint32_t dbg_read_vmem32i(uint32_t a);
void     dbg_write_vmem8(uint32_t a, uint8_t v);
void     dbg_write_vmem16(uint32_t a, uint16_t v);
void     dbg_write_vmem32(uint32_t a, uint32_t v);

uint32_t dbg_read_dtags(uint32_t a);
uint32_t dbg_read_itags(uint32_t a);
void     dbg_write_dtags(uint32_t a, uint32_t v);
void     dbg_write_itags(uint32_t a, uint32_t v);

uint32_t dbg_read_dtag(uint32_t a);
void     dbg_write_dtag(uint32_t a, uint32_t v);
uint32_t dbg_read_itag(uint32_t a);
void     dbg_write_itag(uint32_t a, uint32_t v);

uint32_t dbg_read_mmureg(uint32_t a);
void     dbg_write_mmureg(uint32_t a, uint32_t v);

uint32_t dbg_mmu_probe(uint32_t a);
void dbg_flush(uint32_t a);

//-----------------------------------------------
// PLOMB trace
void dbg_trace_addr(uint8_t a,uint32_t ad,uint32_t adm,uint8_t s,uint8_t sm);
void dbg_trace_conf(uint8_t a,uint32_t v);
void dbg_trace_start(uint8_t a,uint32_t v);
uint32_t dbg_trace_stat(uint8_t a);
uint32_t dbg_trace_parm(uint8_t a);
void dbg_trace_read(uint8_t a,uint8_t p,uint32_t tab[],uint32_t len);

// SCSI trace
#define SCSI_ENA (8)
#define SCSI_REQACK (4)
#define SCSI_CLRIN (1)
#define SCSI_CLROUT (2)

void dbg_scsi_setup(uint8_t a,uint32_t v);
uint32_t dbg_scsi_conf(uint8_t a);
uint32_t dbg_scsi_ptr(uint8_t a);
void dbg_scsi_read(uint8_t a,uint64_t tab[],uint32_t len);










