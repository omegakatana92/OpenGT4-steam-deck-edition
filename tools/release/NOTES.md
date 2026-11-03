First experimental native Linux release of OpenGT4 Steam Deck Edition, **Based on OpenGT4**. This is a modified, unofficial fork.

### Downloads

- **OpenGT4-Steam-Deck-v0.1.0-experimental-x86_64.AppImage** — single-file build; make it executable before launching.
- **OpenGT4-Linux-v0.1.0-experimental-x86_64.tar.gz** — portable native Linux folder; extract it and run `./AppRun`.
- **OpenGT4-v0.1.0-experimental-corresponding-source.tar.gz** — matching project, static dependency, and Ubuntu runtime dependency sources.
- **SHA256SUMS** — checksums for the three archives above.

Both binary downloads are built on Ubuntu 22.04 for x86_64 Linux. They include FFmpeg and runtime libraries. System graphics drivers and a working desktop/Gaming Mode session are required. This is a native Linux build; do not force Proton.

### First run

Use Steam Deck Desktop Mode for initial setup. Launch the AppImage or extracted `AppRun`, then select your own Gran Turismo 4 NTSC-U **SCUS-97328** ISO. Upstream tests disc version **2.00**. The wrapper uses host `kdialog` or `zenity`; if no picker is available, pass the ISO path as the first argument:

```sh
chmod +x OpenGT4-Steam-Deck-v0.1.0-experimental-x86_64.AppImage
./OpenGT4-Steam-Deck-v0.1.0-experimental-x86_64.AppImage "/home/deck/Games/GT4/your-disc.iso"
```

The selected ISO path is remembered. Keep the ISO outside the application. Use `--choose-disc` to select another disc. Saves/settings normally live in `~/.local/share/OpenGT4/OpenGT4/`, outside the read-only image. Add the AppImage or extracted `AppRun` to Steam as a non-Steam game after the Desktop Mode test.

### Changes and validation

- Native Linux compilation, OpenGL/math linking, and GCC declaration fixes.
- Linux FFmpeg movie decoding through a child process, using the existing frame queue and audio mixer.
- Persistent ISO selection and argument forwarding in the AppImage/portable launcher.
- Asset-independent tests for launcher configuration, media, sound, synthetic movie decoding/process cleanup, and launcher path persistence.

**Experimental: Steam Deck gameplay and performance are not verified.** No GT4 disc was available to the builder. Actual race behavior, movie sound synchronization, Steam Input/controller navigation, save/reload, and suspend/resume require on-device testing. The Windows settings launcher has not been ported; initial disc selection should be done in Desktop Mode. Upstream is alpha and has additional known issues documented in README.md.

No ISO, BIOS, game executable, music, textures, models, or other game assets are distributed. Code remains under GPLv3 with the additional terms in NOTICE; dependency licences/notices and corresponding sources accompany this release.
