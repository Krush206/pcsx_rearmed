#CROSS_COMPILE=
AS = $(CROSS_COMPILE)as
CC = $(CROSS_COMPILE)gcc
LD = $(CROSS_COMPILE)ld

ARCH = $(shell $(CC) -v 2>&1 | grep -i 'target:' | awk '{print $$2}' | awk -F '-' '{print $$1}')

CFLAGS += -Wall -ggdb -Ifrontend
LDFLAGS += -lz -lpthread -ldl -lpng -lbz2
ifeq "$(ARCH)" "arm"
CFLAGS += -mcpu=cortex-a8 -mtune=cortex-a8 -mfloat-abi=softfp -ffast-math
ASFLAGS += -mcpu=cortex-a8 -mfpu=neon
endif
ifndef DEBUG
CFLAGS += -O2 -DNDEBUG
endif
CFLAGS += $(EXTRA_CFLAGS)

USE_OSS ?= 1
#USE_ALSA = 1
#DRC_DBG = 1
#PCNT = 1
TARGET = pcsx

-include Makefile.local

all: $(TARGET)

# core
OBJS += libpcsxcore/cdriso.o libpcsxcore/cdrom.o libpcsxcore/cheat.o libpcsxcore/debug.o \
	libpcsxcore/decode_xa.o libpcsxcore/disr3000a.o libpcsxcore/gte.o libpcsxcore/mdec.o \
	libpcsxcore/misc.o libpcsxcore/plugins.o libpcsxcore/ppf.o libpcsxcore/psxbios.o \
	libpcsxcore/psxcommon.o libpcsxcore/psxcounters.o libpcsxcore/psxdma.o libpcsxcore/psxhle.o \
	libpcsxcore/psxhw.o libpcsxcore/psxinterpreter.o libpcsxcore/psxmem.o libpcsxcore/r3000a.o \
	libpcsxcore/sio.o libpcsxcore/socket.o libpcsxcore/spu.o
ifeq "$(ARCH)" "arm"
OBJS += libpcsxcore/gte_neon.o
endif
libpcsxcore/cdrom.o libpcsxcore/misc.o: CFLAGS += -Wno-pointer-sign
libpcsxcore/misc.o libpcsxcore/psxbios.o: CFLAGS += -Wno-nonnull

# dynarec
ifndef NO_NEW_DRC
OBJS += libpcsxcore/new_dynarec/new_dynarec.o libpcsxcore/new_dynarec/linkage_arm.o
OBJS += libpcsxcore/new_dynarec/pcsxmem.o
endif
OBJS += libpcsxcore/new_dynarec/emu_if.o
libpcsxcore/new_dynarec/new_dynarec.o: libpcsxcore/new_dynarec/assem_arm.c \
	libpcsxcore/new_dynarec/pcsxmem_inline.c
libpcsxcore/new_dynarec/new_dynarec.o: CFLAGS += -Wno-all -Wno-pointer-sign
ifdef DRC_DBG
libpcsxcore/new_dynarec/emu_if.o: CFLAGS += -D_FILE_OFFSET_BITS=64
CFLAGS += -DDRC_DBG
endif

# spu
OBJS += plugins/dfsound/dma.o plugins/dfsound/freeze.o \
	plugins/dfsound/registers.o plugins/dfsound/spu.o
plugins/dfsound/spu.o: plugins/dfsound/adsr.c plugins/dfsound/reverb.c \
	plugins/dfsound/xa.c
ifeq "$(ARCH)" "arm"
OBJS += plugins/dfsound/arm_utils.o
endif
ifeq "$(USE_OSS)" "1"
plugins/dfsound/%.o: CFLAGS += -DUSEOSS
OBJS += plugins/dfsound/oss.o
endif
ifeq "$(USE_ALSA)" "1"
plugins/dfsound/%.o: CFLAGS += -DUSEALSA
OBJS += plugins/dfsound/alsa.o
LDFLAGS += -lasound
endif

# gpu
# note: code is not safe for strict-aliasing? (Castlevania problems)
plugins/dfxvideo/%.o: CFLAGS += -fno-strict-aliasing
OBJS += plugins/dfxvideo/gpu.o
plugins/dfxvideo/gpu.o: plugins/dfxvideo/fps.c plugins/dfxvideo/prim.c \
	plugins/dfxvideo/gpu.c plugins/dfxvideo/soft.c
ifdef X11
LDFLAGS += -lX11 -lXv
OBJS += plugins/dfxvideo/draw.o
else
OBJS += plugins/dfxvideo/draw_fb.o
endif

# cdrcimg
OBJS += plugins/cdrcimg/cdrcimg.o

# dfinput
OBJS += plugins/dfinput/main.o plugins/dfinput/pad.o plugins/dfinput/guncon.o

# gui
OBJS += frontend/main.o frontend/plugin.o
OBJS += frontend/plugin_lib.o frontend/common/readpng.o
OBJS += frontend/common/fonts.o frontend/linux/plat.o
ifeq "$(USE_GTK)" "1"
OBJS += maemo/hildon.o maemo/main.o
maemo/%.o: maemo/%.c
else
frontend/%.o: CFLAGS += -DVOUT_FBDEV
OBJS += frontend/menu.o
OBJS += frontend/linux/fbdev.o frontend/linux/in_evdev.o
OBJS += frontend/common/input.o frontend/linux/oshide.o
ifeq "$(ARCH)" "arm"
OBJS += frontend/plat_omap.o
OBJS += frontend/pandora.o
else
OBJS += frontend/plat_dummy.o
endif
endif # !USE_GTK
ifeq "$(ARCH)" "arm"
OBJS += frontend/arm_utils.o
endif
ifdef X11
frontend/%.o: CFLAGS += -DX11
OBJS += frontend/xkb.o
endif
ifdef PCNT
CFLAGS += -DPCNT
endif
ifndef NO_TSLIB
frontend/%.o: CFLAGS += -DHAVE_TSLIB
OBJS += frontend/pl_gun_ts.o
endif
frontend/%.o: CFLAGS += -DIN_EVDEV
frontend/menu.o: frontend/revision.h

frontend/revision.h: FORCE
	@(git describe || echo) | sed -e 's/.*/#define REV "\0"/' > $@_
	@diff -q $@_ $@ > /dev/null 2>&1 || cp $@_ $@
	@rm $@_
.PHONY: FORCE


$(TARGET): $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS) -Wl,-Map=$@.map

PLUGINS = plugins/spunull/spunull.so plugins/gpu_unai/gpuPCSX4ALL.so \
	plugins/gpu-gles/gpuGLES.so plugins/gpu_neon/gpu_neon.so

$(PLUGINS):
	make -C $(dir $@)

clean:
	$(RM) $(TARGET) $(OBJS) $(TARGET).map

clean_plugins:
	for dir in $(PLUGINS) ; do \
		$(MAKE) -C $$(dirname $$dir) clean; done

# ----------- release -----------

PND_MAKE ?= $(HOME)/dev/pnd/src/pandora-libraries/testdata/scripts/pnd_make.sh

VER ?= $(shell git describe master)

rel: pcsx $(PLUGINS) \
		pandora/pcsx.sh pandora/pcsx.pxml.templ pandora/pcsx.png \
		pandora/picorestore pandora/readme.txt pandora/skin COPYING
	rm -rf out
	mkdir -p out/plugins
	cp -r $^ out/
	sed -e 's/%PR%/$(VER)/g' out/pcsx.pxml.templ > out/pcsx.pxml
	rm out/pcsx.pxml.templ
	mv out/*.so out/plugins/
	mv out/plugins/gpu_neon.so out/plugins/gpuPEOPS2.so
	$(PND_MAKE) -p pcsx_rearmed_$(VER).pnd -d out -x out/pcsx.pxml -i pandora/pcsx.png -c
