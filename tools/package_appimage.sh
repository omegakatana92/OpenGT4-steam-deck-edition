#!/usr/bin/env bash
# Build the x86_64 Steam Deck AppImage.
#
# Usage: tools/package_appimage.sh BUILD_DIR /path/to/linuxdeploy.AppImage /path/to/ffmpeg
#
# The image contains exactly two executables and no bundled libraries. That is
# deliberate: OpenGT4 links SDL2, miniz and FSR statically, and its only shared
# dependencies (libOpenGL/libm/libc) belong to the host's graphics stack. The
# ffmpeg passed in must be equally self-contained -- build it with
# tools/build_ffmpeg_minimal.sh. The distribution ffmpeg links libavdevice,
# which links libSDL2 and libX11, and linuxdeploy would then copy that whole
# closure (176 libraries, including an unused SDL2) into the image where it
# shadows SteamOS's own drivers.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for tool in readelf realpath sed install sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Missing tool: $tool" >&2; exit 2; }
done
build=${1:?build directory required}
deploy=${2:?linuxdeploy executable required}
ffmpeg=${3:?FFmpeg executable required}
name=${OPENGT4_APPIMAGE_NAME:-OpenGT4-Steam-Deck-experimental-x86_64.AppImage}

[[ $(uname -m) == x86_64 ]] || { echo 'Use an x86_64 build host.' >&2; exit 2; }
[[ -x $build/opengt4 ]] || { echo "No executable at $build/opengt4; run tools/build_linux.sh first." >&2; exit 2; }
[[ -x $deploy ]] || { echo "linuxdeploy is not executable: $deploy" >&2; exit 2; }
[[ -x $ffmpeg ]] || { echo "FFmpeg is not executable: $ffmpeg" >&2; exit 2; }
build=$(realpath -- "$build")
deploy=$(realpath -- "$deploy")
ffmpeg=$(realpath -- "$ffmpeg")

# Libraries that must always come from the host. Anything else would have to be
# bundled, which is exactly the failure mode this script exists to prevent.
allowed_deps='^(linux-vdso\.so|ld-linux-x86-64\.so|libc\.so|libm\.so|libgcc_s\.so|libpthread\.so|libdl\.so|librt\.so|libOpenGL\.so|libGLdispatch\.so|libGLX\.so)'

audit_binary() {
    local file=$1 label=$2 needed bad=''
    needed=$(readelf -d "$file" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p')
    while IFS= read -r lib; do
        [ -n "$lib" ] || continue
        [[ $lib =~ $allowed_deps ]] || bad+=" $lib"
    done <<< "$needed"
    if [ -n "$bad" ]; then
        cat >&2 <<EOF
ERROR: $label depends on libraries that are not allowed in the AppImage:$bad

Those must come from SteamOS, not from the image: bundling them shadows the
system graphics/X11/Wayland/audio stack and breaks on a different SteamOS
release. SDL2 is statically linked, so a libSDL2 dependency means the wrong
ffmpeg was supplied.
  * Build the decoder with: tools/build_ffmpeg_minimal.sh <output-directory>
  * The game itself must not acquire new shared dependencies.
EOF
        return 1
    fi
    printf '  %-24s %s\n' "$label" "$(echo "${needed:-<none>}" | tr '\n' ' ')"
}

echo '== dependency audit (before staging) =='
audit_binary "$build/opengt4" 'opengt4'
audit_binary "$ffmpeg" 'ffmpeg'

echo '== staging AppDir =='
mkdir -p "$root/dist"
stage=$(mktemp -d "$root/dist/appimage-stage.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT
appdir=$stage/AppDir
mkdir -p "$appdir/usr/bin" "$appdir/usr/share/doc/opengt4"
install -m 0755 "$build/opengt4" "$appdir/usr/bin/opengt4"
install -m 0755 "$ffmpeg" "$appdir/usr/bin/ffmpeg"
install -m 0644 "$root/LICENSE" "$root/NOTICE" "$appdir/usr/share/doc/opengt4/"
install -m 0644 "$root/docs/STEAM_DECK.md" "$appdir/usr/share/doc/opengt4/"
# Normalise line endings so a Windows checkout with core.autocrlf=true does not
# stage an AppRun whose `#!/bin/sh\r` shebang the kernel cannot resolve. The
# desktop file and icon stay outside the AppDir; linuxdeploy installs them.
sed 's/\r$//' "$root/packaging/linux/opengt4-steam-deck.desktop" > "$stage/opengt4-steam-deck.desktop"
sed 's/\r$//' "$root/packaging/linux/opengt4-steam-deck.svg" > "$stage/opengt4-steam-deck.svg"
sed 's/\r$//' "$root/packaging/linux/AppRun" > "$stage/AppRun"
chmod 0755 "$stage/AppRun"

# Record the exact bundled decoder, not an assumed LGPL/GPL configuration.
"$ffmpeg" -hide_banner -version > "$appdir/usr/share/doc/opengt4/ffmpeg-build.txt" 2>&1
for component in ps2float stb fsr1; do
    mkdir -p "$appdir/usr/share/doc/opengt4/$component"
    find "$root/third_party/$component" -maxdepth 1 -type f \
        \( -iname '*license*' -o -iname '*copying*' \) \
        -exec install -m 0644 {} "$appdir/usr/share/doc/opengt4/$component/" \;
done
# SDL/miniz are statically linked by CMake. Ship their actual licence texts.
for entry in 'sdl2-src/LICENSE.txt' 'miniz-src/LICENSE'; do
    [[ -f $build/_deps/$entry ]] || { echo "Missing dependency licence: $entry" >&2; exit 2; }
    install -m 0644 "$build/_deps/$entry" \
        "$appdir/usr/share/doc/opengt4/$(dirname "$entry")-LICENSE.txt"
done
cat > "$appdir/usr/share/doc/opengt4/THIRD_PARTY.txt" <<'EOF'
Based on OpenGT4. This is a modified, unofficial experimental Linux build.
Source: https://github.com/omegakatana92/OpenGT4-steam-deck-edition

Statically linked into opengt4: SDL2 (zlib), miniz (MIT), stb_image (MIT),
FSR1 (MIT), ps2float (LGPL-3.0-or-later).

Bundled as a separate executable: FFmpeg, built by
tools/build_ffmpeg_minimal.sh from the pinned upstream release. See
ffmpeg-build.txt for the exact version, licence and configure line.

No shared libraries are bundled. libOpenGL, the X11/Wayland client libraries,
libdrm and the Mesa/AMD drivers are provided by SteamOS and are intentionally
taken from the host; the AppImage does not set LD_LIBRARY_PATH.

Before publishing a release, include matching dependency copyright notices and
provide corresponding source for all bundled LGPL components, including the
exact FFmpeg source release. This script creates a local test artifact; it does
not publish or certify a distribution-ready release.
EOF

echo '== packaging =='
cd "$root/dist"
export ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1
export OUTPUT=$name
"$deploy" --appdir "$appdir" \
    --desktop-file "$stage/opengt4-steam-deck.desktop" \
    --icon-file "$stage/opengt4-steam-deck.svg" \
    --custom-apprun "$stage/AppRun"
# linuxdeploy/patchelf can leave files with owner-only permissions.
chmod -R a+rX "$appdir"

# The deploy plugin may still have collected libraries. Refuse to ship any.
if [ -d "$appdir/usr/lib" ] && [ -n "$(ls -A "$appdir/usr/lib" 2>/dev/null)" ]; then
    echo 'ERROR: libraries were staged into usr/lib:' >&2
    ls -1 "$appdir/usr/lib" >&2
    echo 'Do not bundle them; rebuild the inputs instead (see the audit above).' >&2
    exit 1
fi
# Keep the tree minimal: an empty directory would otherwise be packaged.
rmdir "$appdir/usr/lib" 2>/dev/null || true

"$deploy" --appdir "$appdir" --output appimage
sha256sum "$OUTPUT" > "$OUTPUT.sha256"

echo '== verifying the packaged image =='
extract=$(mktemp -d "$root/dist/appimage-check.XXXXXX")
trap 'rm -rf -- "$stage" "$extract"' EXIT
(
    cd "$extract"
    "$root/dist/$OUTPUT" --appimage-extract >/dev/null
)
for binary in squashfs-root/usr/bin/opengt4 squashfs-root/usr/bin/ffmpeg; do
    audit_binary "$extract/$binary" "$(basename "$binary")"
done
if [ -d "$extract/squashfs-root/usr/lib" ] && [ -n "$(ls -A "$extract/squashfs-root/usr/lib" 2>/dev/null)" ]; then
    echo 'ERROR: the finished image contains bundled libraries:' >&2
    ls -1 "$extract/squashfs-root/usr/lib" >&2
    exit 1
fi
echo '  no bundled shared libraries'

# Create a real window and OpenGL context from inside the image when a display
# is available. This is the check that failed before the SDL2/GLX repair.
if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && [ -z "${OPENGT4_SKIP_SMOKE:-}" ]; then
    echo '== OpenGL startup self-test inside the AppImage =='
    APPIMAGE_EXTRACT_AND_RUN=1 "$root/dist/$OUTPUT" --video-check
else
    echo '== OpenGL self-test skipped: no DISPLAY/WAYLAND_DISPLAY =='
fi

echo
echo "Wrote dist/$OUTPUT"
cat "$OUTPUT.sha256"
