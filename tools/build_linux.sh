#!/usr/bin/env bash
# Clean Linux build for the Steam Deck port.
#
# Removes the build directory first, on purpose: SDL2 caches its X11/GLX
# dependency probes in CMakeCache.txt, so re-running cmake in a tree that was
# first configured before the -dev packages were installed can keep GLX
# disabled and produce an executable that fails with
#   cannot open a window: SDL not configured with OpenGL/GLX support
#
# Environment:
#   BUILD_DIR   build directory (default: build-linux)
#   JOBS        parallel jobs (default: nproc)
#   CMAKE       cmake executable (default: cmake)
#   SKIP_TESTS  set to 1 to stop after building the game
#
# Usage: tools/build_linux.sh
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
build=${BUILD_DIR:-"$root/build-linux"}
cmake=${CMAKE:-cmake}
jobs=${JOBS:-$(nproc)}

echo "== removing $build =="
rm -rf -- "$build"

echo "== configuring =="
"$cmake" -S "$root" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release

sdl_config="$build/_deps/sdl2-build/SDL_config.h.intermediate"
if [ ! -f "$sdl_config" ]; then
    echo "ERROR: SDL2 configuration header not found at $sdl_config" >&2
    exit 1
fi
echo "== SDL2 backends actually compiled in =="
for macro in SDL_VIDEO_DRIVER_X11 SDL_VIDEO_OPENGL_GLX; do
    if grep -q "^#define $macro 1" "$sdl_config"; then
        echo "  $macro 1"
    else
        echo "ERROR: $macro is not enabled in $sdl_config" >&2
        echo "Install the X11/OpenGL development packages and run this script again." >&2
        exit 1
    fi
done

echo "== building =="
"$cmake" --build "$build" --parallel "$jobs" --target \
    opengt4 launcher_tests media_tests sound_tests movie_posix_tests

if [ "${SKIP_TESTS:-0}" = 1 ]; then
    echo "Skipping tests (SKIP_TESTS=1)"
    exit 0
fi

echo "== asset-independent tests =="
ctest --test-dir "$build" --output-on-failure \
    -R '^(launcher_config|launcher_config_negative|native_media|native_sound|menu_music_prefix_negative|movie_posix|appimage_launcher)$'

echo
echo "Game binary: $build/opengt4"
echo "Check window + OpenGL creation without a disc:"
echo "  $build/opengt4 --video-check"
