#!/usr/bin/env bash
set -euo pipefail

PREFIX=${1-}
if [ -z "$PREFIX" ]; then
  echo "Usage: $0 <install-prefix>" >&2
  exit 2
fi

SOURCE_DIR=${FFMPEG_SOURCE_DIR:-ffmpeg_src}
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 4)}

echo "Install prefix: $PREFIX"
echo "Source dir: $SOURCE_DIR"

# 4. 准备 MSVC 路径
PREFIX_WIN=$(cygpath -w "$PREFIX" 2>/dev/null || echo "$PREFIX")
PREFIX_WIN_LIB=$(cygpath -w "$PREFIX/lib" 2>/dev/null || echo "$PREFIX/lib")
PREFIX_WIN_INC=$(cygpath -w "$PREFIX/include" 2>/dev/null || echo "$PREFIX/include")

export LIB="$PREFIX_WIN_LIB${LIB:+;$LIB}"
export INCLUDE="$PREFIX_WIN_INC${INCLUDE:+;$INCLUDE}"

# 5. 配置参数：去掉所有 LAME 相关项
CONFIGURE_FLAGS=(
  --prefix="$PREFIX"
  --extra-cflags="-I$PREFIX_WIN_INC"
  --extra-ldflags="-LIBPATH:$PREFIX_WIN_LIB"
  --toolchain=msvc
  --arch=x86_64
  --target-os=win64
  --enable-static
  --disable-shared
  --disable-everything
  --disable-programs
  --disable-ffplay
  --disable-ffprobe
  --disable-doc
  --disable-iconv
  --disable-bzlib
  --disable-libilbc
  --disable-lzma
  --disable-debug
  --disable-avdevice
  --disable-network
  --disable-avfilter
  --enable-small
  --enable-stripping
  --enable-demuxer=mov
  --enable-muxer=mp4
  --enable-protocol=file
  --enable-decoder=aac
  --enable-decoder=h264
  --enable-encoder=copy
  --enable-parser=aac
  --enable-parser=h264
  --enable-bsf=aac_adtstoasc
  --enable-bsf=h264_mp4toannexb
  --pkg-config-flags=--static
)

cd "$SOURCE_DIR"

echo "Configuring FFmpeg with MSVC toolchain..."
if ! ./configure "${CONFIGURE_FLAGS[@]}"; then
  echo "Configure failed! Displaying config.log"
  cat ffbuild/config.log 2>/dev/null || echo "Could not read config.log"
  exit 1
fi

echo "Running make -j$JOBS"
make -j"$JOBS"

echo "Running make install"
make install

mkdir -p "$PREFIX"
cp -r "$(pwd)/install"/* "$PREFIX/" 2>/dev/null || true

cd ..
