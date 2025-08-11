# build examples using hiredis
#
# last update: 2024-09-18
###############################################################
PREFIX=.

all: rediscmd.c
	gcc -o rediscmd rediscmd.c \
	-I../libs/hiredis/include \
	-L../libs/hiredis/lib \
	-ldl -lpthread \
	-Wl,--rpath=./:./libs:../libs/hiredis/lib:/usr/local/lib \
	-lhiredis

clean:
	rm -f *.o rediscmd

.phony: all clean