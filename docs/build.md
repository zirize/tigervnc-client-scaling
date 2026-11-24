# Build, patch workflow, install

## Build

`./build.sh [VERSION]` → `build/VERSION/vncviewer/vncviewer`, VERSION `1.15.0` (default) or
`1.16.2`; it applies `patches/VERSION/*.patch`. `./build.sh --fresh [VERSION]` deletes
`src/tigervnc-VERSION` and `build/VERSION` first. `src/` and `build/` are build output and are
not part of the repository.

What `build.sh` does, and why:

- It downloads the Ubuntu source package (`.dsc`, `.debian.tar.xz`, `.orig.tar.xz`):
  `tigervnc_1.15.0+dfsg-2build1` (Ubuntu 26.04) or `tigervnc_1.16.2+dfsg-1ubuntu1` (Ubuntu
  27.04), from the Ubuntu archive pool, which serves every series, and runs `dpkg-source -x`,
  which applies the Debian patches. This avoids needing `deb-src` entries for `apt-get source`.
  In both versions only two Debian patches touch `vncviewer/`:
  `0175-xtigervncviewer-WM_CLASS.patch` and `CVE-2014-8240-849479.patch`.
- 1.16.2 builds on Ubuntu 26.04 with the same dependencies as 1.15.0.
- Build dependencies for the viewer only: on a desktop Ubuntu the missing ones were
  `apt install --no-install-recommends libfltk1.3-dev libavcodec-dev libavutil-dev libswscale-dev libpam0g-dev`.
  - `apt build-dep tigervnc` would pull the whole X server build stack.
  - Without `--no-install-recommends`, FLTK 1.4 and fluid come along.
  - PAM is a hard CMake requirement on Linux, although only the servers use it. A configure
    that failed for it stays cached, so delete `build/` after installing it.
- CMake flags match `debian/rules` (NLS, Nettle, GnuTLS, H.264 on). `ninja vncviewer` builds
  only the viewer. Without this patch, the result links exactly the same libraries as the
  distribution's `/usr/bin/xtigervncviewer` (`ldd` diff empty).

## Changing the patch

`build.sh` makes `src/tigervnc-VERSION` a git repository: tag `base` is the Debian-patched
source, then one commit per `patches/VERSION/*.patch` (applied with `git am`). The two
versions' patches are kept separately; a change to the scaling code goes into both.

1. Edit under `src/tigervnc-VERSION`, then rebuild with `ninja -C build/VERSION vncviewer`.
2. Run `tests/scale_test.sh build/VERSION/vncviewer/vncviewer` (see `docs/scaling.md`, "Testing").
3. Commit there (or `--amend`), then export:
   `rm patches/VERSION/*.patch && git -C src/tigervnc-VERSION format-patch base -o ../../patches/VERSION`.
   The file name follows the commit subject.
4. Check that `./build.sh --fresh VERSION` applies and builds it. `--fresh` discards anything
   in `src/tigervnc-VERSION` that was not exported.

Porting to a new upstream version: add a `case` line to `build.sh`, build it once with an empty
`patches/<new version>/` (that build is also the stock viewer for the parity checks: `STOCK=...
tests/scale_test.sh`), then `git apply --reject` the previous version's patch inside
`src/tigervnc-<new version>`, resolve the `.rej` hunks, commit and export as above.

## Install

`install -m 755 -s build/VERSION/vncviewer/vncviewer ~/.local/bin/vncviewer`

- If `~/.local/bin` precedes `/usr/bin` in `PATH`, `vncviewer` now runs this build (check with
  `type -a vncviewer`). On Debian/Ubuntu `/usr/bin/vncviewer` is an alternatives link to the
  stock `/usr/bin/xtigervncviewer`.
- Desktop menu entries that call `xtigervncviewer` directly still start the stock viewer.
- Without the distro `tigervnc-viewer` package there is no `vncviewer.desktop` and no `tigervnc`
  icon, so the Plasma (Wayland) task manager cannot match the window class `TigerVNC Viewer` and
  shows the generic Xwayland icon. Install both per user:

  ```bash
  M=src/tigervnc-VERSION/media/icons
  for r in 16 22 24 32 48 64 128; do
    install -Dm644 $M/tigervnc_$r.png ~/.local/share/icons/hicolor/${r}x${r}/apps/tigervnc.png
  done
  install -Dm644 $M/tigervnc.svg ~/.local/share/icons/hicolor/scalable/apps/tigervnc.svg
  sed "s|^Exec=.*|Exec=$HOME/.local/bin/vncviewer|" build/VERSION/vncviewer/vncviewer.desktop.in \
    > ~/.local/share/applications/vncviewer.desktop
  kbuildsycoca6
  ```

  The match key is `StartupWMClass=TigerVNC Viewer` (the FLTK `default_xclass` in
  `vncviewer.cxx`); restart the viewer to see the icon.
- Undo: delete `~/.local/bin/vncviewer` (and the icon and desktop files above).
