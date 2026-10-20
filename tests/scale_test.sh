#!/bin/bash
# Headless regression test for the scaling patch. Runs everything on private Xvnc displays
# (:91 remote 320x200 that rejects resizes, :92 viewer screen, :93 remote that accepts
# resizes); the user's desktop is not touched.
#
#   tests/scale_test.sh [viewer]     default: build/vncviewer/vncviewer
#
# Needs: Xvnc (tigervnc-standalone-server), xtigervncviewer (stock, for the parity checks,
# which are skipped without it),
# ImageMagick 7 (magick, import, display), xdotool, xwininfo, xdpyinfo.
# Prints PASS/FAIL per check; exit status is the number of failures.
set -uo pipefail

HERE=$(cd "$(dirname "$0")/.." && pwd)
V=${1:-$HERE/build/vncviewer/vncviewer}
STOCK=/usr/bin/xtigervncviewer
W=$(mktemp -d)
NET="-AutoSelect=0 -PreferredEncoding=Raw -NoJPEG"   # lossless, deterministic
fails=0
pids=()

cleanup() {
    for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done
    rm -rf "$W"
}
trap cleanup EXIT

check() { # check <label> <actual> <expected>
    if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got $2, want $3"; fails=$((fails+1)); fi
}

xvnc() { # xvnc <n> <geometry> [extra args]
    local n=$1 g=$2; shift 2
    Xvnc :$n -geometry $g -depth 24 -SecurityTypes None -localhost -rfbport 59$n "$@" \
        >"$W/xvnc$n.log" 2>&1 &
    pids+=($!)
}

winpos() { # winpos <pid> -> sets WID X Y WW WH
    local i
    WID=
    for i in $(seq 40); do  # up to 10 s for the window to appear
        WID=$(DISPLAY=:92 xdotool search --pid "$1" 2>/dev/null | tail -1)
        [ -n "$WID" ] && break
        sleep 0.25
    done
    if [ -z "$WID" ]; then
        # An empty -id would make xwininfo wait for a mouse click forever
        echo "FAIL no viewer window for pid $1"; fails=$((fails+1))
        X=0 Y=0 WW=1 WH=1
        return 1
    fi
    eval "$(DISPLAY=:92 xwininfo -id "$WID" | awk '/Absolute upper-left X/{print "X="$4}
        /Absolute upper-left Y/{print "Y="$4} /Width:/{print "WW="$2} /Height:/{print "WH="$2}')"
}

grab() { # grab <pid> <file>: the viewer window's pixels
    winpos "$1"
    DISPLAY=:92 import -window root -crop "${WW}x${WH}+${X}+${Y}" +repage "$2"
}

shot() { # shot <bin> <out> <WxH> [args]: fresh viewer, capture after the overlay fades
    local bin=$1 out=$2 g=$3; shift 3
    DISPLAY=:92 "$bin" -geometry "$g+0+0" $NET "$@" localhost::5991 >/dev/null 2>&1 &
    local p=$!
    sleep 5
    grab $p "$out"
    kill $p; wait $p 2>/dev/null
}

ae() { magick compare -metric AE "$1" "$2" null: 2>&1 | cut -d' ' -f1; }
pae() { magick compare -metric PAE "$1" "$2" null: 2>&1 | cut -d' ' -f1; }

# Remote pattern: 1px checker, gradient, 1px lines
magick -size 160x200 pattern:gray50 \( -size 160x200 gradient:red-blue \) +append \
    -fill none -stroke red -strokewidth 1 -draw "rectangle 0,0 319,199" \
    -stroke lime -draw "line 0,100 319,100" -stroke yellow -draw "line 160,0 160,199" \
    +repage -depth 8 "$W/pattern.png"

xvnc 91 320x200 -AlwaysShared -AcceptSetDesktopSize=0
xvnc 92 1280x800
xvnc 93 320x200 -AlwaysShared
sleep 1.5
DISPLAY=:91 display -window root "$W/pattern.png"
DISPLAY=:93 display -window root "$W/pattern.png"

echo "== Scale=Off is identical to stock"
if [ -x "$STOCK" ]; then
    for g in 320x200 500x300 200x150; do
        shot $STOCK "$W/s.png" $g
        shot "$V" "$W/o.png" $g
        check "off $g" "$(ae "$W/s.png" "$W/o.png")" 0
    done
else
    echo "SKIP no stock viewer at $STOCK"
fi
shot "$V" "$W/off.png" 320x200

echo "== Scaled output against ImageMagick references"
bg="xc:rgb(40,40,40)"
ref() { magick "$W/off.png" "$@"; }
ref -filter point -resize 960x600! "$W/e1.png"
shot "$V" "$W/a1.png" 960x600 -Scale Fit -ScaleFilter Nearest
check "fit nearest 3x" "$(ae "$W/e1.png" "$W/a1.png")" 0
magick -size 960x700 $bg \( "$W/e1.png" \) -geometry +0+50 -composite "$W/e2.png"
shot "$V" "$W/a2.png" 960x700 -Scale Fit -ScaleFilter Nearest
check "fit letterbox" "$(ae "$W/e2.png" "$W/a2.png")" 0
magick -size 1000x700 $bg \( "$W/e1.png" \) -geometry +20+50 -composite "$W/e3.png"
shot "$V" "$W/a3.png" 1000x700 -Scale Integer
check "integer 3x centred" "$(ae "$W/e3.png" "$W/a3.png")" 0
ref -filter point -resize 960x400! "$W/e4.png"
shot "$V" "$W/a4.png" 960x400 -Scale Stretch -ScaleFilter Nearest
check "stretch nearest" "$(ae "$W/e4.png" "$W/a4.png")" 0
# Bilinear: pixman and ImageMagick round differently; allow 4/255
ref -filter triangle -resize 800x500! "$W/e5.png"
shot "$V" "$W/a5.png" 800x500 -Scale Fit -ScaleFilter Linear
check "fit linear 2.5x (PAE<=1028)" "$([ "$(pae "$W/e5.png" "$W/a5.png")" -le 1028 ] && echo ok)" ok
ref -filter point -resize 640x400! -filter triangle -resize 800x500! "$W/e6.png"
shot "$V" "$W/a6.png" 800x500 -Scale Fit -ScaleFilter IntegerPlus
check "fit integerplus 2.5x (PAE<=1028)" "$([ "$(pae "$W/e6.png" "$W/a6.png")" -le 1028 ] && echo ok)" ok

echo "== Window smaller than the remote: Integer and IntegerPlus shrink like Fit/Linear"
shot "$V" "$W/k1.png" 200x150 -Scale Fit -ScaleFilter Linear
shot "$V" "$W/k2.png" 200x150 -Scale Integer
shot "$V" "$W/k3.png" 200x150 -Scale Fit -ScaleFilter IntegerPlus
check "shrink integer == linear" "$(ae "$W/k1.png" "$W/k2.png")" 0
check "shrink integerplus == linear" "$(ae "$W/k1.png" "$W/k3.png")" 0
check "shrink is not blank" "$([ "$(magick "$W/k1.png" -format '%[fx:standard_deviation>0.05]' info:)" = 1 ] && echo ok)" ok

echo "== Pointer mapping (window point -> remote pixel)"
# A fresh Xvnc ignores relayed pointer motion until the first button event (stock viewer
# too), so click once through a throwaway viewer
DISPLAY=:92 "$V" -geometry 320x200+0+0 $NET localhost::5991 >/dev/null 2>&1 &
a=$!; sleep 2; winpos $a
DISPLAY=:92 xdotool mousemove $((X+30)) $((Y+40)) click 1; sleep 0.5
kill $a; wait $a 2>/dev/null
ptr() { # ptr <WxH> <args> <x,y=rx,ry ...>
    local g=$1 args=$2; shift 2
    DISPLAY=:92 "$V" -geometry "$g+0+0" $NET $args localhost::5991 >/dev/null 2>&1 &
    local p=$!
    sleep 2
    winpos $p
    for t in "$@"; do
        local w=${t%=*} want=${t#*=}
        DISPLAY=:92 xdotool mousemove $((X+${w%,*})) $((Y+${w#*,})); sleep 0.3
        check "ptr $g $args $w" "$(DISPLAY=:91 xdotool getmouselocation | sed -E 's/x:([0-9]+) y:([0-9]+).*/\1,\2/')" "$want"
    done
    kill $p; wait $p 2>/dev/null
}
ptr 320x200 "" 0,0=0,0 319,199=319,199
ptr 960x600 "-Scale Fit" 0,0=0,0 2,2=0,0 3,3=1,1 959,599=319,199
ptr 960x700 "-Scale Fit" 10,10=3,0 959,690=319,199
ptr 800x500 "-Scale Fit" 1,1=0,0 2,2=1,1 799,499=319,199
ptr 960x400 "-Scale Stretch" 5,3=1,1 6,4=2,2
ptr 200x150 "-Scale Fit" 0,0=0,0 199,136=319,199 100,140=160,199

echo "== Partial updates: running viewer equals a fresh one"
dyn() { # dyn <label> <WxH> [args]
    local label=$1 g=$2; shift 2
    DISPLAY=:91 display -window root "$W/pattern.png"
    DISPLAY=:92 "$V" -geometry "$g+0+0" $NET "$@" localhost::5991 >/dev/null 2>&1 &
    local a=$!
    sleep 2
    DISPLAY=:91 xmessage -geometry +37+23 "partial update test 123" &
    local m=$!
    sleep 1.5
    local mw=$(DISPLAY=:91 xdotool search --class Xmessage 2>/dev/null | head -1)
    DISPLAY=:91 xdotool windowmove "$mw" 101 77; sleep 1
    DISPLAY=:91 xdotool windowmove "$mw" 13 141; sleep 3
    grab $a "$W/run.png"; kill $a; wait $a 2>/dev/null
    shot "$V" "$W/fresh.png" $g "$@"
    kill $m; wait $m 2>/dev/null
    check "partial $label" "$(ae "$W/run.png" "$W/fresh.png")" 0
}
dyn off 320x200
dyn nearest 800x500 -Scale Fit -ScaleFilter Nearest
dyn linear 800x500 -Scale Fit -ScaleFilter Linear
dyn integerplus 800x500 -Scale Fit -ScaleFilter IntegerPlus
dyn stretch 777x555 -Scale Stretch -ScaleFilter Linear
dyn integer 1000x700 -Scale Integer
DISPLAY=:91 display -window root "$W/pattern.png"

echo "== Live window resize while scaling"
DISPLAY=:92 "$V" -geometry 800x500+0+0 $NET -Scale Fit -ScaleFilter IntegerPlus localhost::5991 >/dev/null 2>&1 &
a=$!; sleep 2; winpos $a
for s in "900 520" "1000 640" "700 450" "1037 613"; do DISPLAY=:92 xdotool windowsize "$WID" $s; sleep 0.4; done
sleep 4; grab $a "$W/live.png"; kill $a; wait $a 2>/dev/null
shot "$V" "$W/fresh.png" 1037x613 -Scale Fit -ScaleFilter IntegerPlus
check "live resize" "$(ae "$W/live.png" "$W/fresh.png")" 0

echo "== F8 menu switching and RemoteResize (remote :93)"
rsize() { DISPLAY=:93 xdpyinfo | awk '/dimensions/{print $2}'; }
DISPLAY=:92 "$V" -geometry 900x600+0+0 $NET -Scale Fit localhost::5993 >/dev/null 2>&1 &
a=$!; sleep 3; winpos $a
# Menu opens at the pointer (400,300); "Display mode" is the 5th row, its items start at y=410
menu_mode() { # menu_mode <item y>: 410 Remote, 434 None, 458 Fit, 482 Stretch, 506 Integer
    DISPLAY=:92 xdotool mousemove 400 300; DISPLAY=:92 xdotool windowfocus "$WID"; sleep 0.3
    DISPLAY=:92 xdotool key F8; sleep 0.8
    DISPLAY=:92 xdotool mousemove 430 410; sleep 0.6
    DISPLAY=:92 xdotool mousemove 600 410; sleep 0.3
    DISPLAY=:92 xdotool mousemove 600 "$1"; sleep 0.3
    DISPLAY=:92 xdotool click 1; sleep 1.5
}
wsize() { DISPLAY=:92 xdotool windowsize "$WID" $1 $2; sleep 1.5; }
check "scaling: no remote resize on connect" "$(rsize)" 320x200
wsize 1000 640
check "scaling: no remote resize on window resize" "$(rsize)" 320x200
menu_mode 410
check "menu Remote: remote follows window" "$(rsize)" 1000x640
wsize 900 600
check "Remote: window resize resizes remote" "$(rsize)" 900x600
menu_mode 434
wsize 1000 640
check "menu None: remote kept" "$(rsize)" 900x600
menu_mode 410
check "menu Remote again: remote follows window" "$(rsize)" 1000x640
menu_mode 458
wsize 900 600
check "menu Fit: remote kept" "$(rsize)" 1000x640
kill $a; wait $a 2>/dev/null

echo "== Server-side resize while scaling"
DISPLAY=:93 xrandr --fb 320x200 >/dev/null 2>&1; DISPLAY=:93 display -window root "$W/pattern.png"
DISPLAY=:92 "$V" -geometry 900x600+0+0 $NET -Scale Fit -ScaleFilter IntegerPlus localhost::5993 >/dev/null 2>&1 &
a=$!; sleep 3
DISPLAY=:93 xrandr --fb 400x300 >/dev/null 2>&1; sleep 0.5
DISPLAY=:93 display -window root "$W/pattern.png"; sleep 3
grab $a "$W/srv.png"; kill $a; wait $a 2>/dev/null
DISPLAY=:92 "$V" -geometry 900x600+0+0 $NET -Scale Fit -ScaleFilter IntegerPlus localhost::5993 >/dev/null 2>&1 &
b=$!; sleep 5; grab $b "$W/srv_fresh.png"; kill $b; wait $b 2>/dev/null
check "server resize" "$(ae "$W/srv.png" "$W/srv_fresh.png")" 0

echo "== $fails failure(s)"
exit $fails
