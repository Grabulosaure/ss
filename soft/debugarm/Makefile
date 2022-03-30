CC=arm-linux-gnueabihf-gcc
#CFLAGS=-W -Wall -ansi -pedantic
CFLAGS=-O4
LDFLAGS=
EXEC=debug

all: $(EXEC)

debug: main.o serie.o disas.o lib.o command.o
	$(CC) -o $@ $^ $(LDFLAGS)

%.o: %.c
	$(CC) -o $@ -c $< $(CFLAGS)

main.o: lib.h
command.o: lib.h
disas.o: lib.h
serie.o: lib.h
lib.o: lib.h

clean:
	rm -rf *.o

