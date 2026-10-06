SWIG = swig
PYTHON = python3
CC = gcc
CFLAGS = -fPIC -std=c99 $(shell python3-config --cflags)
INCLUDES = -I. -I./libloragw/include
LDFLAGS = $(shell python3-config --ldflags)
LIBS = -Llibloragw/lib -lloragw -ltinymt32 -lrt -lm

.PHONY: all clean

all: _loragw.so

sx1302_hal:
	git clone --depth=1 https://github.com/Lora-net/sx1302_hal

sx1302_hal/libloragw/libloragw.a: sx1302_hal
	perl -i -pe 's/^(CFLAGS :=.*)/\1 -fPIC/' sx1302_hal/libloragw/Makefile
	make -C sx1302_hal/libtools
	make -C sx1302_hal/libloragw libloragw.a

libloragw/lib/libloragw.a: sx1302_hal/libloragw/libloragw.a
	mkdir -p libloragw/include libloragw/lib
	cp sx1302_hal/libloragw/inc/config.h libloragw/include/
	cp sx1302_hal/libloragw/inc/loragw_com.h libloragw/include/
	cp sx1302_hal/libloragw/inc/loragw_hal.h libloragw/include/
	cp sx1302_hal/libtools/libtinymt32.a libloragw/lib/
	cp sx1302_hal/libloragw/libloragw.a libloragw/lib/
	cp sx1302_hal/packet_forwarder/global_conf.json.sx1250.EU868 libloragw/global_conf.json
	perl -i -pe 's/static LGW_SPECTRAL_SCAN_RESULT_SIZE/LGW_SPECTRAL_SCAN_RESULT_SIZE/g' libloragw/include/loragw_hal.h

_loragw.so: libloragw/lib/libloragw.a swig/loragw.i
	$(SWIG) -python -outdir . swig/loragw.i
	$(CC) $(CFLAGS) $(INCLUDES) -c swig/loragw_wrap.c -o swig/loragw_wrap.o
	$(CC) $(LDFLAGS) -shared swig/loragw_wrap.o $(LIBS) -o _loragw.so

clean:
	rm -f *.so *.o swig/loragw_wrap.* loragw.py
	rm -rf __pycache__

distclean: clean
	rm -rf libloragw/* sx1302_hal

test: _loragw.so
	$(PYTHON) sniffer.py
