# Build, patch workflow, install

## Build

`./build.sh` → `build/vncviewer/vncviewer`. `./build.sh --fresh` deletes `src/` and `build/`
first. Both directories are build output and are not part of the repository.

What `build.sh` does, and why:

- It downloads `tigervnc_1.15.0+dfsg-2build1` (`.dsc`, `.debian.tar.xz`, `.orig.tar.xz`) from
  the Ubuntu archive pool and runs `dpkg-source -x`, which applies the Debian patches. This
  avoids needing `deb-src` entries for `apt-get source`. Only two Debian patches touch
  `vncviewer/`: `0175-xtigervncviewer-WM_CLASS.patch` and `CVE-2014-8240-849479.patch`.
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

`build.sh` makes `src/tigervnc-1.15.0` a git repository: tag `base` is the Debian-patched
source, then one commit per `patches/*.patch` (applied with `git am`).

1. Edit under `src/tigervnc-1.15.0`, then rebuild with `ninja -C build vncviewer`.
2. Run `tests/scale_test.sh` (see `docs/scaling.md`, "Testing").
3. Commit there (or `--amend`), then export:
   `rm patches/*.patch && git -C src/tigervnc-1.15.0 format-patch base -o ../../patches`.
   The file name follows the commit subject.
4. Check that `./build.sh --fresh` applies and builds it. `--fresh` discards anything in
   `src/` that was not exported.

## Install

`install -m 755 -s build/vncviewer/vncviewer ~/.local/bin/vncviewer`

- If `~/.local/bin` precedes `/usr/bin` in `PATH`, `vncviewer` now runs this build (check with
  `type -a vncviewer`). On Debian/Ubuntu `/usr/bin/vncviewer` is an alternatives link to the
  stock `/usr/bin/xtigervncviewer`.
- Desktop menu entries that call `xtigervncviewer` directly still start the stock viewer.
- Undo: delete `~/.local/bin/vncviewer`.
