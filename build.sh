#!/bin/bash
# Fetch the Ubuntu TigerVNC source package for one supported version, apply our
# patches/<version>/*.patch on top of the Debian patches, and build only vncviewer.
# Output: build/<version>/vncviewer/vncviewer
#
#   ./build.sh [--fresh] [VERSION]   VERSION: 1.15.0 (default) or 1.16.2
#     --fresh   delete src/tigervnc-VERSION and build/VERSION first (re-applies patches from
#               scratch; uncommitted or unexported edits in that source tree are lost)
#
# One-time build deps (viewer only; libpam0g-dev is required by CMake even for the viewer):
#   sudo apt install --no-install-recommends libfltk1.3-dev libavcodec-dev libavutil-dev \
#        libswscale-dev libpam0g-dev
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
FRESH=
VER=1.15.0
for a in "$@"; do
    case $a in
        --fresh) FRESH=1 ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) VER=$a ;;
    esac
done

# Ubuntu source package per version (1.16.2 is from the Ubuntu 27.04 series; the pool
# serves every series, so it builds on older releases too)
case $VER in
    1.15.0) PKG=tigervnc_1.15.0+dfsg-2build1 ;;
    1.16.2) PKG=tigervnc_1.16.2+dfsg-1ubuntu1 ;;
    *) echo "build.sh: unsupported version $VER (1.15.0 or 1.16.2)" >&2; exit 2 ;;
esac
ORIG=tigervnc_$VER+dfsg.orig.tar.xz
POOL=https://archive.ubuntu.com/ubuntu/pool/universe/t/tigervnc
SRC=$HERE/src/tigervnc-$VER
BUILD=$HERE/build/$VER

if [ -n "$FRESH" ]; then
    rm -rf "$SRC" "$BUILD"
fi

if [ ! -d "$SRC" ]; then
    mkdir -p "$HERE/src"
    cd "$HERE/src"
    for f in $PKG.dsc $PKG.debian.tar.xz $ORIG; do
        [ -f "$f" ] || curl -sfO "$POOL/$f"
    done
    dpkg-source -x $PKG.dsc "tigervnc-$VER"   # also applies debian/patches
    # Tag the Debian-patched tree as "base" and apply ours as commits, so edits can be
    # exported again with: git -C src/tigervnc-VER format-patch base -o ../../patches/VER
    # A fixed committer, so this works without a configured git identity (git am keeps each
    # patch's author)
    git=(git -C "$SRC" -c user.name=build -c user.email=build@localhost)
    "${git[@]}" init -q
    "${git[@]}" add -A
    "${git[@]}" commit -qm "base: $PKG with Debian patches"
    "${git[@]}" tag base
    shopt -s nullglob
    for p in "$HERE/patches/$VER"/*.patch; do
        echo "applying $VER/$(basename "$p")"
        "${git[@]}" am -q "$p"
    done
fi

cmake -S "$SRC" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_NLS=ON -DENABLE_NETTLE=ON -DENABLE_GNUTLS=ON -DENABLE_H264=ON \
    -DINSTALL_SYSTEMD_UNITS=OFF >/dev/null
ninja -C "$BUILD" vncviewer
echo "built: $BUILD/vncviewer/vncviewer"
