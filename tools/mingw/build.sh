#!/bin/bash

set -e

TRIPLE="$1"
OUTDIR="$2"
PREFIX="/opt/deps/$TRIPLE"

cat > src/Makefile.local <<EOF
CC_NATIVE = $TRIPLE-gcc-posix
CXX_NATIVE = $TRIPLE-g++-posix
LD_NATIVE = $TRIPLE-g++-posix
AR_NATIVE = $TRIPLE-gcc-ar
RANLIB_NATIVE = $TRIPLE-gcc-ranlib

EXE_SUFFIX = .exe

STD_C = -std=gnu11
STD_CXX = -std=gnu++17

INCLUDE_EXTRA = -I$PREFIX/include -I$PREFIX/include/SDL2

CFLAGS_NATIVE = -O2 -flto -DENABLE_DEBUGGER -DCURL_STATICLIB \\
	-DWIN32_LEAN_AND_MEAN -D_POSIX_THREAD_SAFE_FUNCTIONS

LDFLAGS_NATIVE = -O2 -flto -static -L$PREFIX/lib \\
	\$(shell $PREFIX/bin/sdl2-config --static-libs) -lSDL2_image \\
	\$(shell $PREFIX/bin/curl-config --static-libs) \\
	-lreadline -ltermcap -lws2_32 -liphlpapi -mconsole
EOF

make -Csrc clean
make -Csrc -j"$(nproc)" bin

mkdir -p "$OUTDIR"
mv src/cloudpilot/cloudpilot-emu.exe src/uarm/cp-uarm.exe src/fstools/fstools.exe \
    src/vfs/vfs.exe "$OUTDIR"

"$TRIPLE-strip" "$OUTDIR"/*.exe

make -Csrc clean
rm -f src/Makefile.local
