# OpenGT4 Steam Deck Edition — experimental Linux port

Based on OpenGT4. This fork is modified and unofficial, and is not the official
OpenGT4 release. It retains GPLv3 and the additional terms in NOTICE.

## Status

A native x86_64 Linux build and a corrected AppImage packaging path are provided.
The SDL2/OpenGL startup failure described below is fixed and verified on a Linux
host with X11 and a Mesa GLX driver. **It has not been run on Steam Deck
hardware as part of this change**, and no Gran Turismo 4 disc was available, so
menu rendering, races, movie audio sync, controller navigation, saves,
performance and suspend/resume are still unverified. Do not describe the port as
playable until the on-device checklist at the end has actually been completed.

No game data or PS2 BIOS is included. Supply your own Gran Turismo 4 NTSC-U
SCUS-97328 ISO; upstream tests version 2.00. Keep the ISO outside the AppImage.

## The startup failure this change fixes

Symptom, before any disc is opened:

```
cannot open a window: SDL not configured with OpenGL/GLX support
```

How it is produced:

* SDL2 is linked **statically** (`SDL_STATIC ON`, `SDL_SHARED OFF`), so
  `opengt4` has no `DT_NEEDED` entry for `libSDL2-2.0.so.0`. Adding a system
  `libsdl2-dev` or installing SDL2 at run time cannot change the backend: the
  copy compiled into the executable is the one that runs.
* SDL2 only compiles its X11 video driver and its GLX backend when
  `check_c_source_compiles()` finds the headers at configure time. Those probe
  results (`HAVE_X11`, `HAVE_OPENGL_GLX`, …) are ordinary CMake **cache**
  entries.
* Configure once without `libx11-dev`/`libgl1-mesa-dev`, install them, and
  re-run `cmake` in the same directory: the successful probe is never re-run, so
  `SDL_VIDEO_OPENGL_GLX` stays undefined. The X11 driver still creates the
  window, then `SDL_GL_CreateContext()` fails with SDL's compiled-out stub
  message above. This is why "delete the build directory" is not folklore.

This was reproduced deterministically on Ubuntu 22.04 by configuring SDL2 with
`-DHAVE_OPENGL_GLX=OFF` (the state a stale cache leaves behind):

```
compiled video drivers: x11 wayland KMSDRM offscreen dummy evdev
SDL_VIDEO_DRIVER_X11=1
SDL_VIDEO_OPENGL_GLX=0
current driver: x11
SDL_CreateWindow failed: SDL not configured with OpenGL/GLX support
```

A clean configure of the same source produces `SDL_VIDEO_OPENGL_GLX=1` and a
working OpenGL 4.1 core context on Mesa.

> The published `v0.1.0-experimental` AppImage itself was built **with** GLX
> (`glXCreateContextAttribsARB` is present and the stub string is not), so the
> message above almost certainly comes from a local `build-linux` tree that was
> reused after a dependency change. That archive has a different problem — it
> bundles 176 shared libraries including an unused SDL2 — see
> [Packaging](#packaging). Both are addressed here; neither the old image nor a
> new one has been validated on a Steam Deck.

### What was changed

| Area | Change |
| --- | --- |
| `CMakeLists.txt` | Clears SDL2's cached X11/GLX probes on every Linux configure, sets `SDL_X11`/`SDL_OPENGL` explicitly, requires `find_package(X11)`/`find_package(OpenGL)`, checks `GL/glx.h`, and reads the generated `SDL_config.h` to fail the configure if either backend is missing. |
| `src/platform/sdl/video_gl.c` | Records the failing startup step together with `SDL_GetError()`, reports the SDL version, compiled/selected video drivers, whether GLX was compiled in, and the GL vendor/renderer/version. |
| `src/app/main.c` | Prints the new diagnostic on failure and adds `--video-check`, which creates a real window and OpenGL context without a disc. |
| `packaging/linux/AppRun` | `--video-check` bypasses disc selection; **no longer sets `LD_LIBRARY_PATH`**, so the image cannot shadow SteamOS libraries. |
| `tools/build_linux.sh` | New: deletes the build directory, configures, verifies the SDL2 backends, builds and runs the asset-independent tests. |
| `tools/build_ffmpeg_minimal.sh` | New: builds a 2.2 MB FFmpeg with no shared dependencies beyond libc/libm (MPEG-2/MPEG-PS decode + the exact filter chain `movie.c` uses). |
| `tools/package_appimage.sh` | Audits dependencies, bundles no libraries at all, refuses to ship an image whose `usr/lib` is not empty, and runs the OpenGL self-test from inside the finished image. |
| `.github/workflows/linux.yml` | Clean builds, prints the compiled backends, and creates an X11/GLX window under Xvfb on every push. |

## Build on Linux

Use an x86_64 Linux host, GCC or Clang, CMake 3.20+, Ninja, Python 3 and
FFmpeg. On Ubuntu 22.04/24.04:

```sh
sudo apt-get update
sudo apt-get install build-essential cmake ninja-build git python3 pkg-config \
  libgl1-mesa-dev libx11-dev libxext-dev libxrandr-dev libxcursor-dev \
  libxi-dev libxfixes-dev libasound2-dev libpulse-dev libudev-dev ffmpeg
```

Confirm the host really provides what SDL2 needs (do this before blaming the
build):

```sh
dpkg -s libgl1-mesa-dev libx11-dev libxext-dev libxrandr-dev \
        libxcursor-dev libxi-dev libxfixes-dev | grep -E '^(Package|Status)'
test -f /usr/include/GL/glx.h && echo 'GL/glx.h present'
glxinfo -B | head -5          # needs mesa-utils; shows the GLX renderer
```

Clean build (always; the script removes `build-linux` first):

```sh
JOBS=4 tools/build_linux.sh
```

This is equivalent to, but safer than:

```sh
rm -rf build-linux
cmake -S . -B build-linux -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build-linux --target opengt4 launcher_tests media_tests \
      sound_tests movie_posix_tests --parallel 4
```

`tools/build_linux.sh` fails immediately if the generated
`build-linux/_deps/sdl2-build/SDL_config.h.intermediate` does not contain
`SDL_VIDEO_DRIVER_X11 1` and `SDL_VIDEO_OPENGL_GLX 1`.

Build on an older compatible distribution (the CI uses Ubuntu 22.04) to avoid
requiring a newer glibc than the target SteamOS installation. Do not use
`-march=native`, fast-math or unsafe floating-point optimizations.

## Verify before packaging

The game otherwise needs a disc to reach video initialisation, which is why the
failure could only be seen after setup. `--video-check` needs no disc, no save
and no game data:

```sh
./build-linux/opengt4 --video-check
```

Observed on Ubuntu 22.04.5 (WSL2, Mesa 23.2.1 through D3D12, X11/GLX):

```
video check: creating a window and an OpenGL context
video: x11 driver, OpenGL 4.1 (Core Profile) Mesa 23.2.1 ... (D3D12 (Intel(R) Iris(R) Plus Graphics)), GLSL 4.10
video: SDL 2.30.9, 6 video driver(s) compiled in: x11 wayland KMSDRM offscreen dummy evdev
video: driver in use: x11
video: OpenGL/GLX backend compiled in: yes
video: DISPLAY=:0 WAYLAND_DISPLAY=wayland-0 SDL_VIDEODRIVER=x11
video: OpenGL 4.1 (Core Profile) Mesa 23.2.1 ... | D3D12 (...) | Microsoft Corporation | GLSL 4.10
video check: OK
```

The same test passes under `xvfb-run -a -s "-screen 0 1280x800x24"` (a separate
X server) and fails with an actionable message when no display exists:

```
video check: FAILED: SDL_Init(SDL_INIT_VIDEO): x11 not available
video: driver in use: (none)
video: OpenGL/GLX backend compiled in: yes
video: no usable display was found. ...
```

Inspect a binary without running it:

```sh
readelf -d build-linux/opengt4 | grep NEEDED
#   libOpenGL.so.0, libm.so.6, libc.so.6 — no libSDL2

grep -E '^#define SDL_VIDEO_(DRIVER_X11|OPENGL_GLX) 1' \
    build-linux/_deps/sdl2-build/SDL_config.h.intermediate
#   #define SDL_VIDEO_DRIVER_X11 1
#   #define SDL_VIDEO_OPENGL_GLX 1
```

## Packaging

The image contains exactly two executables and **no shared libraries**:

```
AppRun
opengt4-steam-deck.desktop
opengt4-steam-deck.svg
usr/bin/opengt4        4.7 MB   static SDL2/miniz/FSR; needs libOpenGL, libm, libc
usr/bin/ffmpeg         2.2 MB   static; needs libm, libc
usr/share/doc/opengt4/          licences, build record, notes
```

The distribution `ffmpeg` cannot be used: Ubuntu builds `libavdevice` with the
SDL2 output device, so `/usr/bin/ffmpeg` links `libSDL2-2.0.so.0`, `libX11` and
~170 other libraries. linuxdeploy copies that closure into the image (that is
where the 80 MB `v0.1.0-experimental` image came from) and `LD_LIBRARY_PATH`
then makes Ubuntu's 2022 libraries shadow SteamOS's current ones. Removing only
`libSDL2` is not possible either — the loader resolves `DT_NEEDED` before
`main()`, so ffmpeg would fail to start.

Build the minimal decoder once (downloads and verifies the pinned FFmpeg 7.1
release, needs `nasm`):

```sh
sudo apt-get install nasm
tools/build_ffmpeg_minimal.sh build-ffmpeg
```

Then build and verify the AppImage:

```sh
curl -fL https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage \
  -o /tmp/linuxdeploy-x86_64.AppImage
printf '%s\n' 'df908b19f1ed1cdafa79508d415aa12d6c56ce4d56d4149aa8c09286718706e5  /tmp/linuxdeploy-x86_64.AppImage' \
  | sha256sum -c -
chmod +x /tmp/linuxdeploy-x86_64.AppImage

tools/package_appimage.sh build-linux /tmp/linuxdeploy-x86_64.AppImage build-ffmpeg/bin/ffmpeg
```

The script:

1. refuses any input whose `DT_NEEDED` set leaves the allowlist
   (`libc`, `libm`, `libgcc_s`, `libpthread`, `libdl`, `librt`, `libOpenGL`,
   `libGLdispatch`, `libGLX`, `ld-linux`), with a message pointing at
   `tools/build_ffmpeg_minimal.sh`;
2. stages the binaries, licences and documentation in a fresh directory (never
   the checkout or an ISO), normalising CRLF from a Windows checkout;
3. fails if linuxdeploy left anything in `usr/lib`;
4. runs `opengt4 --video-check` from inside the finished image when a display is
   available, which is the same test that failed before.

Observed result (Ubuntu 22.04.5, X11):

```
  opengt4                  libOpenGL.so.0 libm.so.6 libc.so.6
  ffmpeg                   libm.so.6 libc.so.6
  no bundled shared libraries
== OpenGL startup self-test inside the AppImage ==
video: driver in use: x11
video: OpenGL/GLX backend compiled in: yes
video check: OK
```

The image is ~3.9 MB with an SHA-256 file next to it. The upstream
`linuxdeploy` `continuous` asset can change: a checksum mismatch must stop the
build until the replacement has been reviewed.

Set `OPENGT4_SKIP_SMOKE=1` only on a machine with no display. Set
`OPENGT4_APPIMAGE_NAME` to choose another output filename.

## First run on Steam Deck

1. Copy the AppImage and your own ISO to the Deck. Keep the ISO in a stable
   folder, outside the image.
2. In Desktop Mode, run the startup diagnostic first — it needs no disc:

   ```sh
   chmod +x OpenGT4-Steam-Deck-...-x86_64.AppImage
   ./OpenGT4-Steam-Deck-...-x86_64.AppImage --video-check
   ```

   Expect `driver in use: x11` (or `wayland`), `OpenGL/GLX backend compiled in:
   yes`, an AMD/Mesa renderer string and `video check: OK`. If it fails, the
   message and the `video:` lines are the bug report.
3. Launch the AppImage and select the ISO with `kdialog`/`zenity`, or pass it
   directly:

   ```sh
   ./OpenGT4-Steam-Deck-...-x86_64.AppImage "/home/deck/Games/GT4/your-disc.iso"
   ```

4. The selected path is remembered under
   `${XDG_CONFIG_HOME:-$HOME/.config}/opengt4-steam-deck/disc-path`. Use
   `--choose-disc` to select another image.
5. Add the AppImage to Steam as a non-Steam game. Use native Linux execution; do
   not force Proton. Try Gaming Mode only after the Desktop Mode checks pass.
6. Saves and settings use SDL's OpenGT4 preferences directory, normally
   `~/.local/share/OpenGT4/OpenGT4/`. `--save-dir` overrides it. Nothing is
   written inside the read-only AppImage mount.

If FUSE is unavailable, run with `APPIMAGE_EXTRACT_AND_RUN=1`.

## On-device acceptance checklist

Nothing below has been executed on Steam Deck hardware for this change.

- [ ] `--video-check` prints `video check: OK` in **Gaming Mode** (gamescope/X11).
- [ ] `--video-check` prints `video check: OK` in **Desktop Mode** (KDE Wayland).
- [ ] Record: SteamOS build, Deck model (LCD/OLED), `glxinfo -B` renderer, the
      `video:` lines, and whether `SDL_VIDEODRIVER` was needed.
- [ ] Disc recognition; intro/menu videos; menu BGM and effects.
- [ ] Arcade: complete races on several tracks and return through results.
- [ ] GT Mode: purchase, licence/event progression, save, quit, reload.
- [ ] Both sticks, D-pad, triggers, buttons, pause, Steam Input.
- [ ] Frame times and audio delay at 1280x800; report settings.
- [ ] Movie video/audio sync and a sustained 20–30 minute race session.
- [ ] Suspend/resume, offline launch, paths with spaces, relocated ISO.

Record actual logs and results before marking any release Steam Deck compatible.

## Known limitations

- No Steam Deck hardware and no GT4 disc were available for this change, so
  startup is verified on a Linux host only and gameplay is unverified.
- Only the X11/GLX path has been tested end to end. Wayland/EGL is compiled in
  but not exercised; SteamOS Gaming Mode is expected to use X11.
- The bundled FFmpeg is deliberately minimal (MPEG-2/MPEG-PS, `il`,
  `setfield`, `yadif`, `scale`, `format`, `fps`, rawvideo). If `movie.c` starts
  using another codec or filter, rebuild it with the matching `--enable-*`.
- The Windows settings launcher is not ported; initial disc selection uses the
  host desktop picker.
- Dependency licence/notice materials must be completed and the matching FFmpeg
  source published before distributing binaries.
- `v0.1.0-experimental` predates these fixes. It should be treated as superseded;
  no replacement release should be published before the on-device checklist is
  complete.
