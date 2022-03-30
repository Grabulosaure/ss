/* Debugger.
   Port série
   DO 5/2011
*/

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <termios.h>
#include <sys/ioctl.h>
#include "lib.h"

int sp_fd;

int sp_init()
{
    struct termios config;

    sp_fd = open(SERIAL_PORT, O_RDWR | O_NOCTTY | O_NDELAY);
    
    if (sp_fd == -1) {
        printf("Impossible d'ouvrir le port\n");
        return sp_fd;
    }
    fcntl(sp_fd, F_SETFL, 0);

    tcgetattr(sp_fd, &config);
    config.c_iflag &= ~(IGNBRK | BRKINT | ICRNL |
                        INLCR | PARMRK | INPCK | ISTRIP | IXON);
    config.c_iflag &= ~(IXON | IXOFF | IXANY);
    config.c_oflag = 0;
    config.c_lflag &= ~(ECHO | ECHONL | ICANON | IEXTEN | ISIG);



    config.c_lflag &= ~(ICANON | ECHO | ECHOE | ISIG);



    config.c_cflag &= ~(CSIZE | PARENB);
    config.c_cflag |= CS8;
    config.c_cc[VMIN] = 1;
    config.c_cc[VTIME] = 0;

    cfsetispeed(&config, B115200);
    cfsetospeed(&config, B115200);
    tcsetattr(sp_fd, TCSAFLUSH, &config);

    return 0;
}

void sp_close()
{
    close(sp_fd);
}

void sp_puc(unsigned char v)
{
    unsigned char c;
    c = v;
    //printf ("[%c %2X]\n\r",c,(unsigned)c);
    write(sp_fd, &c, 1);
}

unsigned char sp_gec()
{
    unsigned char c;
    read(sp_fd, &c, 1);
    //printf (">%c %2X<\n\r",c,(unsigned)c);
    return c;
}

void sp_cts(int v)
{
    int status;
    ioctl(sp_fd, TIOCMGET, &status);
    // L'entrée CTS du FPGA est relié à la sortie RTS du contrôleur USB
    // La sortie RTS du FPGA est relié à l'entrée CTS du contrôleur USB  
    if (!v)
        status |= TIOCM_RTS;    // TIOCM_CTS; // | TIOCM_RTS;
    else
        status &= ~TIOCM_RTS;   //TIOCM_CTS; // | TIOCM_RTS;

    ioctl(sp_fd, TIOCMSET, &status);
    sp_purge();
}

int sp_rts()
{
    int status;
    ioctl(sp_fd, TIOCMGET, &status);
    return (status & TIOCM_CTS);
}

void sp_break()
{
    tcdrain(sp_fd);
#ifdef INVERTBREAK    
    ioctl(sp_fd, TIOCCBRK, 0);
    usleep(1000);
    ioctl(sp_fd, TIOCSBRK, 0);
    usleep(1000);
#else
    ioctl(sp_fd, TIOCSBRK, 0);
    usleep(1000);
    ioctl(sp_fd, TIOCCBRK, 0);
    usleep(1000);
#endif
    tcdrain(sp_fd);
}

void sp_drain()
{
    tcdrain(sp_fd);
}

// Purge
void sp_purge()
{
    char line[1010];

    tcdrain(sp_fd);
    usleep(10000);

    fcntl(sp_fd,F_SETFL,O_NONBLOCK);
    usleep(10000);
    read(sp_fd,line,1000);
    fcntl(sp_fd,F_SETFL,0);
    fcntl(sp_fd,F_SETFL,O_NONBLOCK);
    usleep(10000);
    read(sp_fd,line,1000);
    fcntl(sp_fd,F_SETFL,0);
    usleep(10000);
    sp_rts();
}

void sp_freq(int v)
{
    struct termios config;
    unsigned freq;
    if (v)
        freq = B921600;
    else
        freq = B115200;

    sp_purge();
    tcgetattr(sp_fd, &config);
    cfsetispeed(&config, freq);
    cfsetospeed(&config, freq);
    tcsetattr(sp_fd, TCSANOW, &config);
    sp_purge();

}

int sp_testchar()
{
    fd_set rfds;
    struct timeval tv;
    int retval;
    FD_ZERO(&rfds);
    FD_SET(sp_fd, &rfds);
    tv.tv_sec = 0;
    tv.tv_usec = 0;
    retval = select(sp_fd + 1, &rfds, NULL, NULL, &tv);
    return retval; 
}







