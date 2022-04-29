# [SparcStation](https://en.wikipedia.org/wiki/SPARCstation) for [MiSTer Platform](https://github.com/MiSTer-devel/Main_MiSTer/wiki)

## Compilation Modes

### SS5
SparcStation 5 : Single CPU. MicroSparcII compatible CPU. Up to around 65MHz.

Compatible with all the OSes which supported actual Sun4m SparcStations : Linux, NetBSD, OpenBSD, SunOS, Solaris, NextSTEP. Some OSes requires a special configuration.
  
### SS20
SparcStation 20 : Up to 3 CPUs can fit in MiSTer FPGA. SMP with write-back caches, MESI coherency. SuperSparc compatible CPU. Up to around 50MHz.

SS20 seems to work with NetBSD with 3 CPUs. This is quite complex code and difficult to validate. Linux hardy ever supported multicore on these computers. I would like to be able to run multicore Solaris. IIRC, the debug monitor (/soft/debugarm) is currently needed to properly activate SMP mode.

## Code
Core: https://github.com/Grabulosaure/ss

There is also the OpenBIOS sources with the changes for this core (original repo. works with QEMU) : https://github.com/Grabulosaure/ss_openbios

## Current Builds
http://temlib.org/pub/mister/SS/ss5.rbf

http://temlib.org/pub/mister/SS/ss20.rbf

http://temlib.org/pub/mister/SS/boot.rom

## Setup
### BIOS
Place boot.rom in games/SparcStation folder.

### OS
Use OS images from http://temlib.org/pub/mister/SS/ , passwords are the OS names, uppercase and lowercase characters. 

You can also make your own images using QEMU, or a real SparcStation.

[Using QEMU Sparc emulator to build a RAW image](https://learn.adafruit.com/build-your-own-sparc-with-qemu-and-solaris?view=all&gclid=CjwKCAjwsJ6TBhAIEiwAfl4TWB7lb0zPB9E2s0v9HOEfbNoVReuQV-d9LEpU9mJ8X-fljT1ssA6kQRoCJdgQAvD_BwE
)

`qemu-img create -f raw solaris8.raw 2.9G`

`qemu-system-sparc -m 256 -drive format=raw,file=solaris8.raw,bus=0,unit=0,media=disk -cdrom sol-8-hw4-sparc-v1.iso -prom-env 'auto-boot?=false'`

## Core Notes
Type "boot" in OpenBIOS prompt if the OS doesn't start right away. And be patient. Keep a backup copy of the OS images on the SD card.

It's better to reboot MiSTer when trying different OSes, probably a few missing register reset.

When trying different IOMMU rev options, do a core RESET after applying a new value as this is copied by the BIOS into
a configuration structure.

I've also disabled as default The L2TLB which is a pity as it offers something like a 30% speed boost. I think there is some
way to check which OS could support it, or try to find a bug.

The Ethernet interface isn't enabled on MiSTer. It used to work on the Xilinx board with a direct MII PHY.

## OS Notes
Besides my own bugs, running all these different OSes is a bit tricky because the actual CPUs on SparcStations,
MicroSparcII on SS5 and SuperSparc on SS20 cannot be efficiently implemented exactly the same in a FPGA, and, more
than that, these microprocessors made by Fujistu and Texas Instruments and designed partly by Sun were full of bugs,
particularly in the MMU and cache, so that the Operating Systems had to detect which CPU was present (hence IOMMU rev parameter)
to enable different cache and MMU management code. Awful.
(Just have to read old Linux kernel source code for Sparc32 support, it's full of profanities)

And NextSTEP has some bugs as well, it does weird things during boot and cannot yet be emulated with QEMU.
I didn't expect all these problems when I started this project, a long, long time ago.
