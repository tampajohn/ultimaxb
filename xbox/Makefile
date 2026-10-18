# Run with an activated nxdk environment: make -C xbox NXDK=/path/to/nxdk
ifeq ($(strip $(NXDK)),)
$(error Set NXDK to an installed nxdk checkout and activate its toolchain)
endif
XBE_TITLE = UltimaXB
SRCS = $(CURDIR)/../src/main.c
NXDK_SDL = y
CFLAGS += -DULTIMAXB_XBOX -std=gnu99 -Wall -Wextra
include $(NXDK)/Makefile
