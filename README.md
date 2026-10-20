# tigervnc-client-scaling

📄 Project page: **[TigerVNC client-side scaling for vncviewer](https://zirize.github.io/tigervnc-client-scaling/)** · More projects: **[zirize.github.io](https://zirize.github.io/)**

A patch for the TigerVNC viewer (`vncviewer` 1.15.0, X11) that **scales the remote desktop to
the window on the client side** — fit, stretch or integer scaling, with nearest, bilinear or an
integer-then-bilinear filter — switchable at runtime from the F8 menu.

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

### F8 menu

The context menu (F8) gains two submenus after "Resize window to session":

- **Display mode** — how the session follows the window. One choice at a time:
  *Resize remote session* (stock `RemoteResize`), *No resize (scrollbars)*,
  *Scale to fit*, *Scale to stretch*, *Scale by integer*. The first is greyed out when the
  server cannot change its size.
- **Scale filter** — *Nearest*, *Linear*, *Integer+*; active in Fit and Stretch.

Changes made in the menu last for the session.

## Tested on

- Ubuntu 26.04 LTS, TigerVNC `1.15.0+dfsg-2build1` (the Ubuntu source package with its Debian
  patches), KDE Plasma on Wayland with the viewer running under Xwayland.
- On the real desktop, in scale mode: clipboard in both directions, Korean input through an
  IME running in the remote session (fcitx5-hangul under Openbox), and fullscreen all work.
- A headless regression test (`tests/scale_test.sh`) passes with 0 failures.

The patch also applies cleanly to the upstream `v1.15.0` tag, and the viewer built from it
passes the headless test (the stock-parity checks were skipped there, since they need the
distribution's viewer installed). Other versions have not been tried.

## Building

The build script targets Ubuntu: it downloads the `tigervnc_1.15.0+dfsg-2build1` source package
from the Ubuntu archive, applies the Debian patches and then this patch, and builds only the
viewer.

You need a C++ toolchain, CMake, Ninja, `curl`, `dpkg-dev` and `git`, plus the TigerVNC
viewer's build dependencies (X11 development libraries, pixman, zlib, libjpeg, GnuTLS, Nettle,
gettext — see upstream `BUILDING.txt`). On a desktop Ubuntu where most of those were already
present, these were the ones still missing:

```
sudo apt install --no-install-recommends \
     libfltk1.3-dev libavcodec-dev libavutil-dev libswscale-dev libpam0g-dev
./build.sh              # -> build/vncviewer/vncviewer
./build.sh --fresh      # start over from a clean download
```

Install it wherever you like, e.g. `install -m 755 -s build/vncviewer/vncviewer ~/.local/bin/vncviewer`
(it shadows the system `vncviewer` if `~/.local/bin` comes first in `PATH`; delete it to undo).

On another distribution, apply the patch to a TigerVNC 1.15.0 source tree and build the viewer
as usual:

```
git clone --branch v1.15.0 https://github.com/TigerVNC/tigervnc.git
cd tigervnc && git apply ../patches/0001-*.patch
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release && ninja -C build vncviewer
```

More detail — dependencies, why PAM is needed, how to change and re-export the patch — is in
[`docs/build.md`](docs/build.md).

## Testing

`tests/scale_test.sh [path/to/vncviewer]` runs entirely on private, headless Xvnc displays and
checks:

- `Scale=Off` against the stock viewer, pixel for pixel;
- every mode against reference images;
- pointer mapping at the corners and edges;
- partial screen updates;
- live window resizing;
- F8 menu switching, including suspending and restoring `RemoteResize`;
- a server-side resolution change while scaling.

It needs Xvnc (`tigervnc-standalone-server`), ImageMagick 7, `xdotool`, `xwininfo` and
`xdpyinfo`; the stock `xtigervncviewer` is needed only for the parity checks, which are skipped
without it. How the scaling works and the traps found while testing
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
