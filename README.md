# tigervnc-client-scaling

📄 Project page: **[TigerVNC client-side scaling for vncviewer](https://zirize.github.io/tigervnc-client-scaling/)** · More projects: **[zirize.github.io](https://zirize.github.io/)**

A patch for the TigerVNC viewer (`vncviewer` 1.15.0 and 1.16.2, X11) that **scales the remote
desktop to the window on the client side** — fit, stretch or integer scaling, with nearest,
bilinear or an integer-then-bilinear filter — switchable at runtime from the context menu.

## Why

Stock TigerVNC has no client-side scaling. When the window is smaller or larger than the remote
screen you get scrollbars, or `RemoteResize` asks the server to change its resolution to match
the window. That is not always what you want: the remote may be a fixed-resolution session, a
low-resolution machine you want to see bigger, or a desktop whose layout should not change every
time you resize a window.

The usual workaround on Linux is to run the viewer inside a scaler such as `gamescope`. That
works for the picture, but the nested display server breaks input methods (IME) and clipboard
sharing. This patch puts the scaling into `vncviewer` itself, so the viewer stays a normal X11
client and IME and clipboard keep working.

## What it adds

Two parameters, given on the command line:

| Parameter | Values | Default |
|---|---|---|
| `Scale` | `Off`, `Fit` (keep aspect ratio, letterbox), `Stretch`, `Integer` | `Off` |
| `ScaleFilter` | `Nearest`, `Linear`, `IntegerPlus` | `Linear` |

```
vncviewer -Scale Fit -ScaleFilter Linear host:1
```

- **Fit / Stretch** use the chosen filter. **Integer** scales by the largest whole factor that
  fits, with nearest sampling and a border around the image; if the window is smaller than the
  remote it shrinks like Fit.
- **IntegerPlus** scales by the largest integer factor with nearest sampling, then covers the
  remaining fraction with bilinear. Pixels stay sharp without the uneven pixel widths of plain
  nearest at non-integer factors.
- **Scale=Off** (the default) behaves exactly like the stock viewer; this is checked
  pixel-for-pixel by the test below.
- While scaling, `RemoteResize` requests are suspended, so the remote resolution stays put when
  you resize the window.

### Context menu

The context menu (F8 in 1.15; `Ctrl+Alt+M` in 1.16, which replaced F8 with its new shortcut
keys) gains two submenus after "Resize window to session":

- **Display mode** — how the session follows the window. One choice at a time:
  *Resize remote session* (stock `RemoteResize`), *No resize (scrollbars)*,
  *Scale to fit*, *Scale to stretch*, *Scale by integer*. The first is greyed out when the
  server cannot change its size.
- **Scale filter** — *Nearest*, *Linear*, *Integer+*; active in Fit and Stretch.

Changes made in the menu last for the session.

## Versions

There is one patch per TigerVNC version, in `patches/<version>/`. Both do the same thing.

| Patch | For | Distributions shipping that version (late 2026) |
|---|---|---|
| `patches/1.15.0/` | TigerVNC 1.15.0 | Ubuntu 25.10–26.10 (incl. 26.04 LTS), Debian 13, Fedora 40–41 |
| `patches/1.16.2/` | TigerVNC 1.16.2 | Arch, Fedora 42+, Gentoo, NixOS 25.11+, openSUSE Tumbleweed, Debian 14 / sid, Ubuntu 27.04 |

The 1.16.2 patch is a port of the 1.15.0 one to 1.16's code (the `core` library, enum
parameters, the funnelled `remoteResize()`); there `Scale` and `ScaleFilter` reject invalid
values at startup like other enum parameters, instead of falling back to `Off`/`Linear`.

## Tested on

- Ubuntu 26.04 LTS, TigerVNC `1.15.0+dfsg-2build1` (the Ubuntu source package with its Debian
  patches), KDE Plasma on Wayland with the viewer running under Xwayland.
- On the real desktop, in scale mode: clipboard in both directions, Korean input through an
  IME running in the remote session (fcitx5-hangul under Openbox), and fullscreen all work.
- A headless regression test (`tests/scale_test.sh`) passes with 0 failures.
- **1.16.2:** built on the same Ubuntu 26.04 from the Ubuntu 27.04 source package
  `1.16.2+dfsg-1ubuntu1`; the headless test passes with 0 failures, including `Scale=Off`
  against an unpatched 1.16.2 build pixel for pixel. On the real desktop, in scale mode:
  Korean input through the remote IME, clipboard both ways, fullscreen (`Ctrl+Alt+Enter`),
  the context menu (`Ctrl+Alt+M`) and live window resizing all work.

Each patch also applies cleanly to the matching upstream tag (`v1.15.0`, `v1.16.2`). Other
versions have not been tried.

## Building

The build script targets Ubuntu: it downloads the Ubuntu source package of the chosen version
(`tigervnc_1.15.0+dfsg-2build1` or `tigervnc_1.16.2+dfsg-1ubuntu1`) from the Ubuntu archive,
applies the Debian patches and then this patch, and builds only the viewer. Either version
builds on Ubuntu 26.04.

You need a C++ toolchain, CMake, Ninja, `curl`, `dpkg-dev` and `git`, plus the TigerVNC
viewer's build dependencies (X11 development libraries, pixman, zlib, libjpeg, GnuTLS, Nettle,
gettext — see upstream `BUILDING.txt`). On a desktop Ubuntu where most of those were already
present, these were the ones still missing:

```
sudo apt install --no-install-recommends \
     libfltk1.3-dev libavcodec-dev libavutil-dev libswscale-dev libpam0g-dev
./build.sh              # 1.15.0 -> build/1.15.0/vncviewer/vncviewer
./build.sh 1.16.2       # 1.16.2 -> build/1.16.2/vncviewer/vncviewer
./build.sh --fresh 1.16.2   # start over from a clean download
```

Install it wherever you like, e.g. `install -m 755 -s build/1.16.2/vncviewer/vncviewer ~/.local/bin/vncviewer`
(it shadows the system `vncviewer` if `~/.local/bin` comes first in `PATH`; delete it to undo).

On another distribution, apply the patch for your version to a TigerVNC source tree and build
the viewer as usual:

```
git clone --branch v1.16.2 https://github.com/TigerVNC/tigervnc.git
cd tigervnc && git apply ../patches/1.16.2/0001-*.patch
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release && ninja -C build vncviewer
```

More detail — dependencies, why PAM is needed, how to change and re-export the patch — is in
[`docs/build.md`](docs/build.md).

## Testing

`tests/scale_test.sh [path/to/vncviewer]` (default `build/1.15.0/vncviewer/vncviewer`) runs entirely on private, headless Xvnc displays and
checks:

- `Scale=Off` against the stock viewer, pixel for pixel;
- every mode against reference images;
- pointer mapping at the corners and edges;
- partial screen updates;
- live window resizing;
- context menu switching (F8 or `Ctrl+Alt+M`, picked from the viewer's version), including
  suspending and restoring `RemoteResize`;
- a server-side resolution change while scaling.

It needs Xvnc (`tigervnc-standalone-server`), ImageMagick 7, `xdotool`, `xwininfo` and
`xdpyinfo`; a stock viewer is needed only for the parity checks, which are skipped
without it. It defaults to the distribution's `/usr/bin/xtigervncviewer`; for a version your
distribution does not ship, point `STOCK=` at an unpatched build of the same version (e.g.
plain upstream, or the `base` tag of `src/tigervnc-<version>` built into another directory). How the scaling works and the traps found while testing
are in [`docs/scaling.md`](docs/scaling.md).

## Limitations

- **X11 only.** The scaled drawing uses XRender; Windows and macOS builds of the patched viewer
  would not link.
- `Scale` and `ScaleFilter` are command-line parameters only. They are not saved to `.tigervnc`
  files and do not appear in the Options dialog, so a saved configuration stays readable by the
  stock viewer.
- The local cursor is not scaled.

## License

GPL-2.0-or-later, the same as TigerVNC. See [`LICENSE`](LICENSE).
