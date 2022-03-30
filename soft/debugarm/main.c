/* Debugger.
   Main

   DO 5/2011
*/

#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <termios.h>
#include <stdarg.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <poll.h>
#include <ctype.h>

#include "lib.h"
typedef int (FUNC) (char *arg);

typedef struct {
    char *name;
    FUNC *func;
    char *doc;
} COMMAND;

#define ANSI_DEFAULT "\033[0m"

#define ANSI_ROUGE "\033[31;1m"
#define ANSI_VERT  "\033[32;1m"
#define ANSI_BLEU  "\033[34;1m"
#define ANSI_JAUNE "\033[33;1m"

#define ANSI_BACK "\033[D \033[D"

//--------------------------------------------------------------------
int dbg_running()
{
    return !(dbg_read_status()&1);
}

void dbg_mode(int v)
{
    char code;
    int i;
#ifdef MODE_CTSRTS
    sp_cts(v);
#else
    code=v?'3':'4'; // '3'=Debug. '4'=Mon
    
    for (i = 0;i < 8;i++) {
        sp_break();
        sp_puc(code);
        sp_drain();
    }
    if (v) uprintf ("          ");
#endif
}

//--------------------------------------------------------------------
int lofi = 0;
#define ANSI_RR "\033[31;1m"
#define ANSI_DD "\033[0m"

int uprintf(const char *fmt, ...)
{
    int i, n, size = 10000;
    char *p;
    va_list ap;
    p = malloc(size);
    va_start(ap, fmt);
    n = vsnprintf(p, size, fmt, ap);
    if (lofi)
        write(lofi, p, n);
    va_end(ap);
    if (n > 0)
        for (i = 0; i < n; i++) {
            if (p[i] == '\n') {
                printf(ANSI_DD);
                putchar('\n');
                putchar('\r');
            } else
                putchar(p[i]);
        }

}

int uputchar(char c)
{
    if (lofi)
        write(lofi, &c, 1);
    write(STDOUT_FILENO, &c, 1);
    return 0;;
}

//--------------------------------------------------------------------
int done = 0;
int fin = 0;

int saved[4] = {0,0,0,0};

int stepbrk[4] = {0,0,0,0};
int smp = 0,smpinit = 0;

//####################################################################

//STDIN_FILENO
int logfile;

//--------------------------------------------------------------------
const char TTA = '\005';
const char TTB = '\006';
const char TTC = '\007';
const char TTD = '\010';
const char TTE = '\377';
char pre, pre2, pre3, pre4, code;

int main(int argc, char **argv)
{
    char *line, *s;
    char ms[10];
    fd_set rfds;
    int nfds;
    int retval;
    int i;
    char c;
    int moni = 0;
    char *sib, *sdb;
    char scpu;
    uint32_t pc, npc, opcode;
    char ctxt[100];
    char b0, b1, b2;
    line = malloc(2000);
    struct termios temo, tema, stdio;
    struct pollfd pfd;

    if (sp_init()) return 0;
    dbg_init();

    tcgetattr(0, &tema);

    cfmakeraw(&temo);

    temo.c_lflag &= ~(ICANON | ECHO | ECHOE | ISIG);
    temo.c_cc[VMIN] = 1;
    temo.c_cc[VTIME] = 0;

    // temo.c_oflag |=ONLRET; //ONLCR | OCRNL | ONLRET;
    temo.c_oflag &= ~OPOST;
    // temo.c_iflag |=INLCR; //ICRNL | INLCR;
    tcsetattr(0, TCSAFLUSH, &temo);

    uprintf ("\n" ANSI_ROUGE "TEMLIB Debugger " RELEASE ANSI_DEFAULT "\n");
    uprintf (ANSI_ROUGE "Serial port : "  ANSI_DEFAULT SERIAL_PORT "\n");
#ifdef MODE_CTSRTS 
    uprintf (ANSI_ROUGE "Console/Debug switch :" ANSI_DEFAULT " CTS / RTS\n");
#else
    uprintf (ANSI_ROUGE "Console/Debug switch :" ANSI_DEFAULT " BREAK\n");
#endif
    uprintf ("[Press ESC twice to enter Monitor]\n");
    lofi = open("log.log", O_RDWR | O_CREAT, S_IRWXU);

    razmap();
    readmap("map.map");
    readmap("map2.map");

   // sp_freq(1); //FAST !
   
    do {
        uprintf("\n" ANSI_BLEU "======== Terminal ========" ANSI_DEFAULT
                "\n\n");
      dbg_mode(0);
        moni = 0;
        do {
            FD_ZERO(&rfds);
            FD_SET(0, &rfds);
            FD_SET(sp_fd, &rfds);

            retval = select(sp_fd + 1, &rfds, NULL, NULL, NULL);
            if (FD_ISSET(0, &rfds)) {
                read(0, line, 1);
                if (line[0] == 27) {
                    pfd.fd = 0;
                    pfd.events = POLLIN;
                    pfd.revents = 0;
                    poll(&pfd, 1, 250);
                    if (pfd.revents == POLLIN) {
                        read(0, line, 1);
                        if (line[0] == 27) {
                            moni = 1;
                        } else {
                            write(sp_fd, "\033", 1);
                            write(sp_fd, line, 1);
                        }
                    } else {
                        write(sp_fd, "\033", 1);
                    }
                } else {
                    write(sp_fd, line, 1);
                }
            }
            if (FD_ISSET(sp_fd, &rfds)) {
                // Caractères reçus SPORT
                read(sp_fd, line, 1);
                uputchar(line[0]);
            }
        } while (!moni);

        uprintf("\n" ANSI_BLEU "======== Monitor =========\n");
        //uprintf ("\n\ndbg_mode\n");
        dbg_mode(1);
        //uprintf ("sp_purge\n");
        sp_purge();
        //uprintf ("dbg_resync\n");
        dbg_resync();
        //uprintf ("dbg_cpus\n");
        smp = dbg_cpus();
        //uprintf ("dbg_cpus après\n");
        if (!smpinit) {
            smpinit=1;
            if ((smp==8) || (smp==4) || (smp==2) || (smp==1) || (smp ==0)) 
               smp=0;
            else
               smp=1;
            uprintf (ANSI_ROUGE "SMP : " ANSI_DEFAULT " %s\n",smp?"YES":"NO");
        }

        done = 0;
        do {
            if (!dbg_running() && !saved[dbg_getcpu()]) {
                dbg_stop_deja();
                dbg_prologue();
                uprintf(ANSI_JAUNE "<BREAKPOINT> ");
                disas_pc();
                saved[dbg_getcpu()] = 1;
                dbg_dbrk(0);
                if (stepbrk[dbg_getcpu()]) {
                    stepbrk[dbg_getcpu()] = 0;
                    if (ibrk[dbg_getcpu()].v)
                        dbg_write_ibrk(ibrk[dbg_getcpu()].a);
                    else
                        dbg_ibrk(0);
                }
            }
            if (dbg_running() && saved[dbg_getcpu()]) {
                uprintf("\n\n" ANSI_JAUNE "<RESET ?>\n");
                saved[dbg_getcpu()] = 0;
            }
            if (ibrk[dbg_getcpu()].v)
                sib = "I";
            else
                sib = " ";
            if (dbrk[dbg_getcpu()].v)
                sdb = "D";
            else
                sdb = " ";
            if (smp)
                scpu = '0' + dbg_getcpu();
            else
                scpu = ' ';
            if (dbg_running()) {
                uprintf("\n" ANSI_VERT "%c:(%s%s) RUN >", scpu, sib, sdb);
            } else {
                uprintf("\n" ANSI_ROUGE "%c:(%s%s) STOP>", scpu, sib, sdb);
            }
            i = 0;
            do {
                c = getchar();
                if (c != 127) {
                    line[i] = c;
                    uputchar(c);
                } else {
                    uprintf(ANSI_BACK);
                    if (i >= 1)
                        i -= 2;
                }

                if (i < 1990)
                    i++;
            } while (c != '\n' && c != 3 && c != '\r' && c != 27);
            line[i] = 0;
            if (c == 27)
                done = 1;
            else if (c == 3) {
                done = 1;
                fin = 1;
            } else {
                /* s = stripwhite(line); */
                /* if (*s) { */
                uprintf("\n");
                execute_line(line);
                /* } */
            }
        } while (!done);

    } while (!fin);

    dbg_uspeed(0);

    uprintf("\n\n");
    tcsetattr(0, TCSAFLUSH, &tema);

    close(lofi);
}


/*

gcc lib.c main.c serie.c disas.c -o debug

chmod 777 /dev/ttyUSB0

/sbin/fxload -v -t fx2 -I /opt/Xilinx/ISE12.2/ISE_DS/ISE/bin/lin64/xusbdfwu.hex -D  /proc/bus/usb/001/008

*/

/*  -- D 0xxx xxxx : Trace buffers
  sel.tr    <=to_std_logic(aa(35 DOWNTO 28)=x"D0"); -- Trace
*/
// DATA
//     0x0000 : TR1 : A
//     0x0800 : TR1 : DW
//     0x1000 : TR1 : parms
//     0x1800 : TR1 : DR
//     0x2000 : TR1 : conf
//     0x3000 : TR1 : CPT

// INST
//     0x4000 : TR2 : A
//     0x4800 : TR2 : DW
//     0x5000 : TR2 : parms
//     0x5800 : TR2 : DR
//     0x6000 : TR2 : conf
//     0x7000 : TR2 : CPT

// EXT
//     0x8000 : TR3 : A
//     0x8800 : TR3 : DW
//     0x9000 : TR3 : parms
//     0x9800 : TR3 : DR
//     0xA000 : TR3 : conf
//     0xB000 : TR3 : CPT

// Ana
//     0xC000 : TR4 : V1
//     0xC800 : TR4 : V2
//     0xD000 : TR4 : V3
//     0xD800 : TR4 : V4
//     0xE000 : TR4 : CPT


/*

CHRONTEL :

wch 33 06
wch 34 26
wch 36 A0
wch 49 C0
wch 21 09

pw ff1800004 00031337

pw ff1800004 00021337

pw ff1800004 00011337




pw ff1800004 00001337



p ff1800000

pw ff1800004 00031337


p 7800000

pw 7800000 FFFFFFFF
pw 7800004 FFFFFFFF
pw 7800008 FFFFFFFF
pw 780000C FFFFFFFF

pwf 78C0000 1000 0

pwf 78C0000 10000 0

pwf 7804000 4000 01010101
pwf 7808000 4000 02020202

C0000

Fin   78E_2000
Début 782_0000

pw e20200000 0
pw e20200004 FF000000
pw e20200004 FF000000
pw e20200004 FF000000
pw e20200004 00000000
pw e20200004 10000000
pw e20200004 FF000000
pw e20200004 FF000000
pw e20200004 10000000
pw e20200004 40000000


pw e20200000 0
pw e20200004 FF000000
pw e20200004 00000000
pw e20200004 00000000

pw e20200000 0
pw e20200004 00000000
pw e20200004 FF000000
pw e20200004 00000000

pw e20200000 0
pw e20200004 00000000
pw e20200004 00000000
pw e20200004 FF000000


pw e20200000 FE000000
pw e20200004 40000000
pw e20200004 40000000
pw e20200004 10000000


  -- +    20_0000 : Palette : 16 octets       (Offset 2Mo)

mingetty tty2
X vt2


/sbin/fxload -v -t fx2 -I /opt/Xilinx/ISE12.2/ISE_DS/ISE/bin/lin64/xusbdfwu.hex -D  /proc/bus/usb/001/006

chmod 777 /dev/ttyUSB0 

pw ff1800004 0011337  



  sel.auxio0 <=to_std_logic(aa(35 DOWNTO 20)=x"FF18"); -- Auxiliary IO1


p ff1800000                                                                                                             


pw ff1800008 ed0000                                                                                                     


pw ff1800008 eded0000                                                                                                     
pw ff1800008 eded0000                                                                                                     
pw ff1800008 eded0000                                                                                                     
pw ff1800008 eded0000                                                                                                     
pw ff1800008 eded0000                                                                                                     
pw ff1800008 eded0000                                                                                                     
pw ff1800008 eded0000                                                                                                     
pw ff1800008 eded0000                                                                                                     
pw ff1800008 eded0000                                                                                                     


////////////////////////////
Nouvelle génération


p ff1800000


activation vidéo

pw ff1800004 72333

pw ff1800004 09337
pw ff1800004 59333


 *aux_iic=0x00072333;

pw ff1800008 0000


activation mode PS/2

pw ff1800008 1000




activation émulation PS/2

pw ff1800008 3000


26.24
26.32
26.17
26.40


pw ff1800008 233000


pw ff1800008 0000


p ff1000000


pw ff1800008 237000


pw ff1800008 233000


--   7:0 : (RW) PS/2 DATA
--     8 : (R ) PS/2 DATA error
--     9 : (R ) PS/2 DATA ready

--    12 : (RW) PS/2 PS2/Sun
--    13 : (RW) PS/2 Emu/Direct
--    14 : (RW) PS/2 Souris/Clavier

-- 23:16 : (RW) Sun KB Layout

p ff1000000                                                                                                             


p ff1800000                                                                                                             




pw ff1800008 237000


//////////////////////

Activation échantillonnages Souris

pw ff1800008 2310f4


pw ff1800008 237000

pw ff1800008 233000
pw ff1800004 72333



gcc lib.c main.c serie.c disas.c -o debug



*/
