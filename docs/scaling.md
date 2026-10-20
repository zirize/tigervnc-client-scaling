# Client-side scaling (Stage 1) — how it works

Patch: `patches/0001-vncviewer-client-side-scaling-*.patch` (8 files under `vncviewer/`; the
name is whatever `git format-patch` derives from the commit subject).
X11 only: `Surface::drawScaled()` exists only in `Surface_X11.cxx`, so a Win32/macOS build
would fail to link. Only X11 is supported.

## Options

| Parameter | Values | Default |
|---|---|---|
| `Scale` | `Off`, `Fit` (keep aspect, letterbox), `Stretch`, `Integer` | `Off` |
| `ScaleFilter` | `Nearest`, `Linear`, `IntegerPlus` (used by Fit and Stretch only) | `Linear` |

- Case-insensitive. An unknown value logs an error and falls back to `Off` / `Linear`.
- **Command line only** (`vncviewer -Scale Fit -ScaleFilter IntegerPlus host`). They are not
  in `parameterArray` (`parameters.cxx`), so they are neither saved to nor loaded from
  `.tigervnc` files and are absent from the Options dialog. Adding them there is a separate
  item: a saved file would then carry names the stock viewer does not know.
- `RemoteResize` (stock, also command line only) decides what happens with `Scale=Off`:
  resize the remote desktop to the window, or keep it and show scrollbars.
- F8 menu, after "Resize window to session":
  - `Display mode ▸` — one radio group, because the choices exclude each other:
    "Resize remote session" (`Scale=Off`, `RemoteResize=1`), "No resize (scrollbars)"
    (`Scale=Off`, `RemoteResize=0`), then "Scale to fit / stretch / by integer". The first
    item is inactive, and "No resize" shown as current, when the server cannot resize
    (`supportsSetDesktopSize`).
  - `Scale filter ▸` — inactive unless the mode is Fit or Stretch.
  - Changes set the parameters in memory and last for the session.
  - `DesktopWindow::updateScaling()` sends one `remoteResize(w(), h())` whenever the result
    is "Resize remote session" and the remote size differs from the window.
- `Integer` ignores the filter: nearest at `floor(min(window / framebuffer))`; when the window
  is smaller than the remote it shrinks like `Fit` with linear.
- `IntegerPlus` falls back to nearest at exact integer factors and to linear when shrinking.
- Between 1x and 2x (e.g. 1080 → 1800) N = 1, so the nearest pass is a 1:1 copy and the
  output equals `Linear`; the two-pass path still runs (one extra copy, same pixels).
- Under Xwayland with the compositor's "applications scale themselves" mode, the viewer draws
  at physical pixels: one bilinear resample. A GTK3 Wayland client at a fractional scale draws
  at buffer scale 2 and the compositor shrinks it again (e.g. 1080 → 2400 → 1800), which is
  why the same "linear" looks much softer in such a viewer.
- Letterbox colour is the stock window background (40,40,40), not black.

## Structure

- **Widget size vs framebuffer size.** Stock `Viewport::resize()` reallocated the framebuffer
  whenever the widget size changed, because the widget always equalled the remote size. Now
  `Viewport::resize()` only resizes the widget and calls `updateScale()`; the framebuffer is
  reallocated only by `Viewport::resizeFramebuffer()`, called from
  `DesktopWindow::resizeFramebuffer()` (server-driven). Keep it that way:
  `CConnection::setFramebuffer()` asserts the new buffer equals the server size.
  `fbWidth()/fbHeight()` give the remote size; `w()/h()` the widget size.
- **Layout.** `DesktopWindow::repositionWidgets()`: when scaling, the viewport covers the whole
  window and both scrollbars are hidden; otherwise the viewport is first restored to the
  framebuffer size, then the stock centring/scrolling code runs.
- **Geometry.** `Viewport::updateScale()` parses the two parameters and computes `scaleX/Y`
  and `imageRect` (image area relative to the widget, centred). Called on widget resize,
  framebuffer resize, and `DesktopWindow::updateScaling()` (F8 menu).
- **Drawing.** On X11 `DesktopWindow::draw()` always renders into its `offscreen` Surface via
  `Viewport::draw(Surface*)`, which branches to `Viewport::drawScaled()`. The overlay and stats
  graph are blended afterwards in window space, so they stay unscaled.
  `Surface::drawScaled()` sets an XRender transform (1/scale), the filter, and `RepeatPad`
  (without it bilinear fades into transparent black at the right/bottom edge), composites
  with `PictOpSrc`, then restores identity/nearest/`RepeatNone` because other code copies the
  same picture 1:1.
- **Pixel centres.** Rendering samples window pixel `p` at `(p + 0.5 - offset) / scale`
  (pixman convention); `toFramebuffer()` uses the same formula for pointer events, then clamps
  into the framebuffer (letterbox clicks hit the nearest edge pixel). `fromFramebuffer()` is
  the inverse, used by `DesktopWindow::setCursorPos()` for server-side pointer warps.
- **Damage.** `Viewport::updateWindow()` maps the framebuffer damage rect with
  floor/ceil and a 1 px margin, clipped to `imageRect`.
- **IntegerPlus.** Pass 1 copies the framebuffer with nearest into `intermediate`
  (framebuffer × N, N = floor(scale)); pass 2 draws `intermediate` with bilinear at
  scale/N. Pass 1 is driven by **accumulated framebuffer damage** (`intermediateDamage`),
  not by the draw clip, so the intermediate is always complete and pass 2 may sample anywhere.
  `intermediateStale` forces a full pass 1 after a mode/filter change, a framebuffer
  reallocation, a change of N, or whenever another path drew instead (the intermediate is not
  maintained there).
- **RemoteResize** is suspended while scaling in three places in `DesktopWindow.cxx`: the
  window `resize()` timer, `handleDesktopSize()` on the first update (an explicit
  `DesktopSize` is still honoured), and edge scrolling (`handle()`, `handleEdgeScroll()`).
- "Resize window to session" uses `fbWidth()/fbHeight()`.

## Testing

`tests/scale_test.sh` runs headless on private Xvnc displays (:91 remote 320x200 rejecting
resizes, :92 viewer screen, :93 remote accepting resizes) and checks, with exit status =
failures: Off vs stock viewer pixel parity at three window sizes; nearest/integer/stretch/
letterbox output equal to ImageMagick references (linear and IntegerPlus within 4/255);
pointer mapping at corners and edges; partial updates (a remote window moved twice) equal to
a fresh viewer for every mode; live window resize; F8 menu switching with RemoteResize
suspend/restore and Display mode switching (remote / no resize / fit); server-side resize
while scaling. The parity checks are skipped when `/usr/bin/xtigervncviewer` is absent; a
viewer whose window never appears is reported as FAIL rather than hanging `xwininfo`.
Last run: 2026-10-21, 0 failures (also on a build from the upstream `v1.15.0` tag, parity
skipped).

Traps found while writing it (all are test-environment issues, not viewer bugs):

- The viewer's default `RemoteResize=1` resizes an Xvnc remote to the window size; a fixed
  remote needs `Xvnc -AcceptSetDesktopSize=0`.
- Default encoding uses JPEG first and a lossless refresh later, so captures differ by a few
  levels in gradients; use `-AutoSelect=0 -PreferredEncoding=Raw -NoJPEG`.
- A fresh Xvnc ignores pointer motion relayed by a viewer until the first button event (stock
  viewer too); the script clicks once first.
- No window manager on :92/:91: windows carry no `_NET_WM_PID` (find xmessage by
  `--class`), F8 reaches the viewer only after `xdotool windowfocus`, and
  `import -window <id>` returns black — crop the root window instead.
- Capture only after the 4 s "Press F8" overlay has faded, and never run two viewers at the
  same position.
- Stopping the Xvnc servers by `pkill -f "Xvnc :91"` also kills the calling shell (its own
  command line matches); kill by PID.

Not covered by the script (it renders with pixman on the CPU in Xvnc). Checked by hand on the
real KDE desktop on 2026-10-21, in scale mode: clipboard both ways, Korean input through
fcitx5-hangul running in the remote session, and fullscreen. Still unchecked: HiDPI.
