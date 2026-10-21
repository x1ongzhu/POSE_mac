#!/bin/bash

set -e

TRIPLE="$1"
PREFIX="/opt/deps/$TRIPLE"

: "${MSYS2_PACKAGES_REF:=master}"

ZLIB_VERSION=1.3.1
TERMCAP_VERSION=1.3.1
READLINE_VERSION=8.3
READLINE_PATCHLEVEL=3
CURL_VERSION=8.22.0
SDL2_VERSION=2.32.10
SDL2_IMAGE_VERSION=2.8.12

MSYS2_RAW="https://raw.githubusercontent.com/msys2/MINGW-packages/$MSYS2_PACKAGES_REF"

JOBS="$(nproc)"
WORK="$(mktemp -d)"

export CC="$TRIPLE-gcc-posix"
export CXX="$TRIPLE-g++-posix"
export AR="$TRIPLE-ar"
export RANLIB="$TRIPLE-ranlib"
export STRIP="$TRIPLE-strip"
export WINDRES="$TRIPLE-windres"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"

mkdir -p "$PREFIX"
cd "$WORK"

fetch() {
    curl -fsSL --retry 3 -o "$2" "$1"
}

echo "=== zlib $ZLIB_VERSION ==="
fetch "https://zlib.net/fossils/zlib-$ZLIB_VERSION.tar.gz" zlib.tar.gz
tar xf zlib.tar.gz
make -C "zlib-$ZLIB_VERSION" -f win32/Makefile.gcc -j"$JOBS" \
    PREFIX="$TRIPLE-" CC="$CC" AR="$AR" RC="$WINDRES" libz.a
install -d "$PREFIX/include" "$PREFIX/lib"
install -m644 "zlib-$ZLIB_VERSION/libz.a" "$PREFIX/lib"
install -m644 "zlib-$ZLIB_VERSION/zlib.h" "zlib-$ZLIB_VERSION/zconf.h" "$PREFIX/include"

echo "=== termcap $TERMCAP_VERSION ==="
fetch "https://ftp.gnu.org/gnu/termcap/termcap-$TERMCAP_VERSION.tar.gz" termcap.tar.gz
tar xf termcap.tar.gz
cd "termcap-$TERMCAP_VERSION"
fetch "$MSYS2_RAW/mingw-w64-termcap/0001-tparam-replace-write-with-fprintf.patch" tparam.patch
patch -p1 -i tparam.patch
autoconf
./configure --host="$TRIPLE" --build="$(./config.guess 2>/dev/null || echo x86_64-pc-linux-gnu)" \
    --prefix="$PREFIX"
make -j"$JOBS" termcap.o tparam.o version.o
rm -f libtermcap.a
"$AR" rcs libtermcap.a termcap.o tparam.o version.o
install -m644 libtermcap.a "$PREFIX/lib"
install -m644 termcap.h "$PREFIX/include"
cd "$WORK"

echo "=== readline $READLINE_VERSION ==="
fetch "https://ftp.gnu.org/gnu/readline/readline-$READLINE_VERSION.tar.gz" readline.tar.gz
tar xf readline.tar.gz
cd "readline-$READLINE_VERSION"
for i in $(seq 1 $READLINE_PATCHLEVEL); do
    i="$(printf '%03d' "$i")"
    fetch "https://ftp.gnu.org/gnu/readline/readline-$READLINE_VERSION-patches/readline${READLINE_VERSION//./}-$i" "up-$i.patch"
    patch -Np0 -i "up-$i.patch"
done
for p in 0001-sigwinch 0002-event-hook 0003-no-winsize 0004-locale; do
    fetch "$MSYS2_RAW/mingw-w64-readline/$p.patch" "$p.patch"
    patch -p1 -i "$p.patch"
done
CFLAGS="-O2 -DNEED_EXTERN_PC=1 -D__USE_MINGW_ALARM -D_POSIX -I$PREFIX/include " \
LDFLAGS="-L$PREFIX/lib" \
    ./configure --host="$TRIPLE" --build="$(./support/config.guess)" --prefix="$PREFIX" \
    --without-curses --enable-static --disable-shared \
    bash_cv_wcwidth_broken=no bash_cv_func_sigsetjmp=missing \
    bash_cv_func_ctype_nonascii=yes
make -j"$JOBS"
make install
cd "$WORK"

echo "=== curl $CURL_VERSION ==="
fetch "https://curl.se/download/curl-$CURL_VERSION.tar.gz" curl.tar.gz
tar xf curl.tar.gz
cd "curl-$CURL_VERSION"
./configure --host="$TRIPLE" --prefix="$PREFIX" \
    --with-schannel --enable-websockets --disable-shared --enable-static \
    --with-zlib="$PREFIX" --without-libpsl --disable-ldap --disable-ldaps --disable-docs \
    --disable-manual --without-libidn2 --without-brotli --without-zstd --without-nghttp2
make -j"$JOBS"
make install
cd "$WORK"

echo "=== SDL2 $SDL2_VERSION ==="
fetch "https://github.com/libsdl-org/SDL/releases/download/release-$SDL2_VERSION/SDL2-devel-$SDL2_VERSION-mingw.tar.gz" sdl2.tar.gz
tar xf sdl2.tar.gz
make -C "SDL2-$SDL2_VERSION" install-package arch="$TRIPLE" prefix="$PREFIX"

echo "=== SDL2_image $SDL2_IMAGE_VERSION ==="
fetch "https://github.com/libsdl-org/SDL_image/releases/download/release-$SDL2_IMAGE_VERSION/SDL2_image-devel-$SDL2_IMAGE_VERSION-mingw.tar.gz" sdl2_image.tar.gz
tar xf sdl2_image.tar.gz
make -C "SDL2_image-$SDL2_IMAGE_VERSION" install-package arch="$TRIPLE" prefix="$PREFIX"

rm -f "$PREFIX"/lib/*.dll.a "$PREFIX"/bin/*.dll

"$PREFIX/bin/curl-config" --feature
"$PREFIX/bin/curl-config" --protocols

cd /
rm -fr "$WORK"
