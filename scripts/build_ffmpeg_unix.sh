#!/usr/bin/env bash
set -euo pipefail

PREFIX=${1-}
if [ -z "$PREFIX" ]; then
  echo "Usage: $0 <install-prefix>" >&2
  exit 2
fi

SOURCE_DIR=${FFMPEG_SOURCE_DIR:-ffmpeg_src}
ARCH=${FFMPEG_ARCH:-$(uname -m)}
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}

if [ -n "${FFMPEG_TARGET_OS:-}" ]; then
  TARGET_OS=$FFMPEG_TARGET_OS
else
  case "$(uname -s)" in
    Linux)
      TARGET_OS=linux
      ;;
    Darwin)
      TARGET_OS=darwin
      ;;
    *)
      echo "Unsupported host OS: $(uname -s)" >&2
      exit 1
      ;;
  esac
fi

echo "Install prefix: $PREFIX"
echo "Source dir: $SOURCE_DIR"
echo "Target OS: $TARGET_OS"
echo "Arch: $ARCH"

CONFIGURE_FLAGS=(
  --prefix="$PREFIX"
  --arch="$ARCH"
  --target-os="$TARGET_OS"
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

echo "Configuring FFmpeg..."
if ! ./configure "${CONFIGURE_FLAGS[@]}"; then
  echo "Configure failed! Displaying config.log"
  cat ffbuild/config.log 2>/dev/null || echo "Could not read config.log"
  exit 1
fi

echo "Running make -j$JOBS"
make -j"$JOBS"

echo "Running make install"
make install
