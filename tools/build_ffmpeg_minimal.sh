#!/usr/bin/env bash
# Build the minimal FFmpeg the Linux AppImage ships for menu-movie decoding.
#
# Why not the distribution's ffmpeg? Ubuntu/Debian build libavdevice with the
# SDL2 output device, so /usr/bin/ffmpeg has DT_NEEDED entries for
# libSDL2-2.0.so.0, libX11 and dozens of other libraries. linuxdeploy then
# copies that whole closure into the AppImage, where LD_LIBRARY_PATH makes the
# bundled libraries shadow SteamOS's own graphics/audio stack. Not bundling
# them is not an option either: the dynamic loader resolves DT_NEEDED before
# main() runs, so ffmpeg would simply fail to start.
#
# The port only spawns ffmpeg to read MPEG-2 video out of an MPEG program
# stream and write raw RGBA frames to a pipe (src/platform/sdl/movie.c). This
# builds exactly those components as a self-contained executable that needs
# nothing but libc and libm.
#
# Usage: tools/build_ffmpeg_minimal.sh [output-directory]
# Result: <output-directory>/bin/ffmpeg  (default: build-ffmpeg/bin/ffmpeg)
set -euo pipefail

version=7.1
sha256=40973d44970dbc83ef302b0609f2e74982be2d85916dd2ee7472d30678a7abe6
url="https://ffmpeg.org/releases/ffmpeg-${version}.tar.xz"

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# configure resolves --prefix relative to its own build directory, so make it
# absolute before handing it over.
out=$(realpath -m -- "${1:-"$root/build-ffmpeg"}")
cache=$(realpath -m -- "${OPENGT4_FFMPEG_CACHE:-"$root/build-ffmpeg-cache"}")
jobs=${JOBS:-$(nproc)}

for tool in curl tar make cc; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Missing build tool: $tool" >&2; exit 2; }
done
if ! command -v nasm >/dev/null 2>&1; then
    cat >&2 <<'EOF'
nasm is required for FFmpeg's x86 assembly. Install it first:
  Debian/Ubuntu: sudo apt-get install nasm
  SteamOS/Arch:  sudo pacman -S nasm
EOF
    exit 2
fi

mkdir -p "$cache"
tarball="$cache/ffmpeg-${version}.tar.xz"
if [ ! -f "$tarball" ]; then
    echo "Downloading FFmpeg ${version}"
    curl -fL --retry 3 -o "$tarball.part" "$url"
    mv -- "$tarball.part" "$tarball"
fi
echo "$sha256  $tarball" | sha256sum -c -

work="$cache/src-${version}"
rm -rf -- "$work"
mkdir -p "$work"
tar -x -f "$tarball" -C "$work" --strip-components=1

# --disable-autodetect keeps configure from linking zlib, libX11, SDL2 and
# anything else it happens to find on the build host. Only the components the
# movie path actually invokes are enabled.
(
    cd "$work"
    ./configure \
        --prefix="$out" \
        --disable-shared --enable-static --disable-autodetect \
        --disable-doc --disable-debug --disable-network \
        --disable-avdevice --disable-ffprobe \
        --disable-everything \
        --enable-ffmpeg \
        --enable-avcodec --enable-avformat --enable-avfilter --enable-swscale --enable-swresample \
        --enable-decoder=mpeg2video --enable-parser=mpegvideo \
        --enable-demuxer=mpegps,mpegvideo \
        --enable-encoder=rawvideo --enable-muxer=rawvideo \
        --enable-protocol=file,pipe \
        --enable-filter=il,setfield,yadif,scale,format,fps,null,anull,aresample
    make -s -j"$jobs"
    make -s install
)

ffmpeg="$out/bin/ffmpeg"
[ -x "$ffmpeg" ] || { echo "FFmpeg build did not produce $ffmpeg" >&2; exit 1; }

echo
echo "Built $ffmpeg ($(du -h "$ffmpeg" | cut -f1))"
echo "Shared library dependencies:"
readelf -d "$ffmpeg" | sed -n 's/.*Shared library: \[\(.*\)\]/  \1/p'
echo
"$ffmpeg" -hide_banner -version | grep -E 'version|configuration|License' | sed 's/^/  /'
cat <<EOF

Record for the release notes / corresponding source:
  FFmpeg $version, source $url
  sha256 $sha256
  build: tools/build_ffmpeg_minimal.sh (see the configure line above)
EOF
