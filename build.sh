#!/bin/bash
# Fetch the Ubuntu TigerVNC 1.15.0 source package, apply our patches/*.patch on top of the
# Debian patches, and build only vncviewer. Output: build/vncviewer/vncviewer
#
#   ./build.sh            fetch (if missing), patch, configure, build
#   ./build.sh --fresh    delete src/ and build/ first (re-applies patches from scratch;
#                         uncommitted or unexported edits in src/ are lost)
#
# One-time build deps (viewer only; libpam0g-dev is required by CMake even for the viewer):
#   sudo apt install --no-install-recommends libfltk1.3-dev libavcodec-dev libavutil-dev \
#        libswscale-dev libpam0g-dev
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PKG=tigervnc_1.15.0+dfsg-2build1
ORIG=tigervnc_1.15.0+dfsg.orig.tar.xz
POOL=https://archive.ubuntu.com/ubuntu/pool/universe/t/tigervnc
SRC=$HERE/src/tigervnc-1.15.0
BUILD=$HERE/build

if [ "${1:-}" = --fresh ]; then
    rm -rf "$HERE/src" "$BUILD"
fi

if [ ! -d "$SRC" ]; then
    mkdir -p "$HERE/src"
    cd "$HERE/src"
    for f in $PKG.dsc $PKG.debian.tar.xz $ORIG; do
        [ -f "$f" ] || curl -sfO "$POOL/$f"
    done
    dpkg-source -x $PKG.dsc tigervnc-1.15.0   # also applies debian/patches
    # Tag the Debian-patched tree as "base" and apply ours as commits, so edits can be
    # exported again with: git -C src/tigervnc-1.15.0 format-patch base -o ../../patches
    # A fixed committer, so this works without a configured git identity (git am keeps each
    # patch's author)
    git=(git -C "$SRC" -c user.name=build -c user.email=build@localhost)
    "${git[@]}" init -q
    "${git[@]}" add -A
    "${git[@]}" commit -qm "base: $PKG with Debian patches"
    "${git[@]}" tag base
    shopt -s nullglob
    for p in "$HERE"/patches/*.patch; do
        echo "applying $(basename "$p")"
        "${git[@]}" am -q "$p"
    done
fi

cmake -S "$SRC" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_NLS=ON -DENABLE_NETTLE=ON -DENABLE_GNUTLS=ON -DENABLE_H264=ON \
    -DINSTALL_SYSTEMD_UNITS=OFF >/dev/null
ninja -C "$BUILD" vncviewer
echo "built: $BUILD/vncviewer/vncviewer"
