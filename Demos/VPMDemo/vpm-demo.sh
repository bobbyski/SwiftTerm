#!/bin/bash
#
# VTG Page Mode demo.
#
# Nothing but escape sequences written with printf, so it runs in any terminal
# that advertises `page=` in its VTG capabilities. Five scenes:
#
#   1. A card floating over live terminal output
#   2. A long document built off screen, shown in one step, then scrolled
#   3. A double-buffered animation over a background drawn once and shared
#   4. Drawing straight onto the visible page, over the terminal
#   5. Back to the terminal
#
# Needs bash (it uses arrays). `bash vpm-demo.sh auto` runs without waiting
# for Return.

AUTO=0
[ "$1" = auto ] && AUTO=1

vtg() { printf '\033_VTG;%s\033\\' "$1"; }

# One attributed-text run: <style>:<utf-8 byte count>:<text>.
run() {
    local bytes
    bytes=$(printf %s "$2" | LC_ALL=C wc -c | tr -d ' ')
    printf '%s:%s:%s' "$1" "$bytes" "$2"
}

wait_return() {
    if [ "$AUTO" = 1 ]; then sleep 1.5; else read -r _; fi
}

# Ordinary output that keeps scrolling underneath the pages.
TICKER=
start_ticker() {
    (
        i=0
        modules="Parser Scene Layers Pages Text Fonts Growth Scroll Cache Input"
        while [ $i -lt 600 ]; do
            set -- $modules
            shift $((i % 10))
            printf '\033[2m%s  step %03d  compiling %s.swift\033[0m\n' "$(date +%H:%M:%S)" "$i" "$1"
            i=$((i + 1))
            sleep 0.12
        done
    ) &
    TICKER=$!
}
stop_ticker() {
    [ -n "$TICKER" ] && kill "$TICKER" 2>/dev/null && wait "$TICKER" 2>/dev/null
    TICKER=
}

OLD_STTY=$(stty -g 2>/dev/null)
cleanup() {
    stop_ticker
    vtg "pageEnd"
    [ -n "$OLD_STTY" ] && stty "$OLD_STTY" 2>/dev/null
}
trap cleanup EXIT
trap 'exit 130' INT TERM
stty -echo 2>/dev/null

# This script never reads the terminal's replies, so it asks for none.
vtg "detach"

# Styles are defined once and used by name for the rest of the session.
vtg "textStyle,id=title,font=Georgia,size=44,weight=bold,color=#ffffff"
vtg "textStyle,id=h2,font=Georgia,size=30,weight=bold,color=#f8fafc"
vtg "textStyle,id=body,font=Helvetica Neue,size=18,color=#cbd5e1"
vtg "textStyle,id=em,inherit=body,color=#5eead4,weight=bold"
vtg "textStyle,id=warm,inherit=body,color=#fbbf24,slant=italic"
vtg "textStyle,id=code,font=mono,size=15,color=#fbbf24"
vtg "textStyle,id=label,font=mono,size=13,color=#94a3b8"
vtg "textStyle,id=hud,font=Helvetica Neue,size=16,weight=bold,color=#0f172a"

# --------------------------------------------------------------------------
# Scene 1 — a card floating over live terminal output

clear
printf '\033[1mVTG Page Mode demo\033[0m\n\n'
printf 'The grey lines below are ordinary terminal output. They keep\n'
printf 'running underneath while pages float above them.\n\n'
start_ticker
sleep 2

vtg "pageBegin,id=demo"
# A 620x300 page, placed in a rectangle of the window, 90% opaque.
vtg "pageOpen,id=card,bg=#0b1220e6,w=620,h=300,grow=none"
vtg "pageViewport,x=240,y=150,w=620,h=300"
vtg "rect,id=frame,x=1,y=1,w=618,h=298,stroke=#5eead4,fill=none,width=2,radius=14"
vtg "styledText,id=t,x=310,y=34,style=title,align=center;VTG Page Mode"
vtg "attrText,id=s,x=310,y=108,style=body,align=center;$(run - 'A page is drawn ')$(run em 'off screen')$(run - ', then shown in one step.')$(run NL '')$(run - 'It floats above the terminal, and the')$(run NL '')$(run - 'output underneath ')$(run warm 'keeps scrolling.')"
vtg "styledText,id=code,x=310,y=236,style=code,align=center;pageOpen  →  draw  →  pageShow"
# Nothing is visible yet: everything above went into an off-screen buffer.
sleep 1.5
vtg "pageShow"
sleep 6

# --------------------------------------------------------------------------
# Scene 2 — a long document built off screen, shown in one step, scrolled

stop_ticker
# Lands in the other buffer; the card stays on screen while this is drawn.
vtg "pageOpen,id=doc,bg=#0f172a"
vtg "styledText,id=d-title,x=80,y=60,style=title;A page larger than the window"
vtg "attrText,id=d-sub,x=80,y=128,style=body;$(run - 'This page is ')$(run em 'growable')$(run - ': it started at the window height and grew to fit')$(run NL '')$(run - 'every box drawn into it. Nothing here was visible until one ')$(run code 'pageShow')$(run - '.')"

sections=(
  "Two buffers|A page opened while another is visible always lands in the other slot. One page is on screen while the next is built, and pageShow swaps them in a single step — no flicker, no half-drawn frames, no repainting the terminal underneath."
  "Growth|Each axis is fixed or growable. Content past a fixed edge is clipped but kept; content past a growable edge extends the page. Growth only ever goes one way, and a host limit keeps a runaway loop from eating memory."
  "Layers|A page has named layers with their own order, opacity, and offset. A layer can be pinned to the viewport, like the bar at the bottom of this page, so it stays put while the document scrolls beneath it."
  "Rich text|Named styles cascade. Text can be one run in any font and size, attributed runs like the heading above, or a box that wraps to fit — this paragraph is one. Runs are length-prefixed, so no character ever needs escaping."
  "Sharing|A layer can be borrowed from the other page by reference. The next scene draws a night sky once and reuses it for every frame of an animation; the renderer rasterizes it once, for both buffers."
  "Safety|A page can never strand itself over your shell. The terminal takes it down when the program exits, detaches, resets the terminal, or when a shell prompt comes back — which also catches a program that died over SSH."
  "Compatibility|A program that never sends pageBegin sees exactly the protocol it always did. The new commands are new names older terminals ignore, and the features are advertised in their own capability fields."
  "Measuring|textMeasure? lays text out with the same engine that draws it, so a program can place boxes exactly. This demo does not bother — it never reads the terminal's replies — and simply leaves room."
)
y=220
n=0
for entry in "${sections[@]}"; do
    heading=${entry%%|*}
    text=${entry#*|}
    n=$((n + 1))
    vtg "rect,id=bar$n,x=56,y=$((y + 4)),w=6,h=130,fill=#5eead4,stroke=none,radius=3"
    vtg "styledText,id=h$n,x=80,y=$y,style=h2;$n. $heading"
    vtg "textBox,id=p$n,x=80,y=$((y + 48)),w=760,h=-1,style=body,lineHeight=27;$(run - "$text")"
    y=$((y + 210))
done
vtg "styledText,id=end,x=80,y=$((y + 10)),style=warm;— end of the document —"

# A bar pinned to the viewport: it ignores the page's scroll.
vtg "pageLayerAdd,id=hud,z=10,scroll=fixed"
vtg "rect,id=hud-bg,x=250,y=622,w=600,h=40,fill=#5eead4,stroke=none,radius=20,layer=hud"
vtg "styledText,id=hud-t,x=550,y=631,style=hud,align=center,layer=hud;Scene 2 · a growable page, scrolling"

sleep 1
vtg "pageShow"
sleep 2
s=0
while [ $s -le 1500 ]; do
    vtg "pageScroll,y=$s"
    s=$((s + 10))
    sleep 0.012
done
sleep 1
vtg "pageScrollTo,anchor=top"

# Hand the scroll wheel to the page.
vtg "pageScrollMode,user=1,axis=y"
vtg "styledText,id=hud-t,x=550,y=631,style=hud,align=center,layer=hud;Scroll with your trackpad · press Return to go on"
wait_return
vtg "pageScrollMode,user=0"

# --------------------------------------------------------------------------
# Scene 3 — double buffering over a background drawn once and shared

vtg "pageOpen,id=f0,bg=#050816"
vtg "pageLayerAdd,id=sky,z=0,cache=1"
colors="#050816 #0a1030 #121a44 #1c2458 #2a2f66 #3b3470"
band=0
for color in $colors; do
    vtg "rect,id=band$band,x=0,y=$((band * 120)),w=1100,h=120,fill=$color,stroke=none,layer=sky"
    band=$((band + 1))
done
awk 'BEGIN {
    srand(7)
    for (i = 0; i < 160; i++) {
        printf "\033_VTG;circle,id=star%d,cx=%d,cy=%d,r=%.1f,fill=#ffffff%02x,stroke=none,layer=sky\033\\",
            i, rand() * 1100, rand() * 420, 0.6 + rand() * 1.4, 90 + rand() * 165
    }
}'
vtg "circle,id=moon,cx=880,cy=120,r=46,fill=#f8fafc,stroke=none,layer=sky"
vtg "circle,id=moon-shade,cx=900,cy=108,r=42,fill=#1c2458,stroke=none,layer=sky"
vtg "path,id=far,fill=#1e1b4b,stroke=none,layer=sky;M 0 520 L 140 400 L 260 470 L 420 340 L 560 460 L 700 370 L 860 480 L 1000 360 L 1100 430 L 1100 720 L 0 720 Z"
vtg "path,id=near,fill=#0b0a1f,stroke=none,layer=sky;M 0 600 L 180 520 L 330 580 L 520 500 L 700 590 L 880 530 L 1100 600 L 1100 720 L 0 720 Z"

vtg "pageLayerAdd,id=clouds,z=1,cache=1"
vtg "ellipse,id=c1,cx=200,cy=200,rx=140,ry=26,fill=#ffffff1c,stroke=none,layer=clouds"
vtg "ellipse,id=c2,cx=620,cy=150,rx=190,ry=30,fill=#ffffff16,stroke=none,layer=clouds"
vtg "ellipse,id=c3,cx=1000,cy=260,rx=160,ry=24,fill=#ffffff1a,stroke=none,layer=clouds"
vtg "ellipse,id=c4,cx=1400,cy=190,rx=170,ry=28,fill=#ffffff16,stroke=none,layer=clouds"
vtg "ellipse,id=c5,cx=1800,cy=230,rx=150,ry=26,fill=#ffffff1a,stroke=none,layer=clouds"
vtg "pageShow"
sleep 0.5

frames=220
i=1
while [ $i -le $frames ]; do
    prev=$((i - 1))
    vtg "pageOpen,id=f$i,bg=#050816"
    # Borrowed by reference: never redrawn, rasterized once for both buffers.
    vtg "pageLayerCopy,id=sky,from=f$prev,layer=sky,cache=1"
    # Parallax: the same clouds, shifted, without drawing them again.
    vtg "pageLayerCopy,id=clouds,from=f$prev,layer=clouds,cache=1,x=$(( -((i * 3) % 800) ))"

    x=$((i * 5 - 40))
    t=$((i % 40))
    bob=$(( t < 20 ? t : 40 - t ))
    y=$((300 + bob))
    flame=$(( i % 2 == 0 ? 26 : 18 ))
    vtg "ellipse,id=flame,cx=$((x - 22)),cy=$y,rx=$flame,ry=7,fill=#fb923ccc,stroke=none"
    vtg "triangle,id=ship,x1=$((x - 18)),y1=$((y - 16)),x2=$((x + 34)),y2=$y,x3=$((x - 18)),y3=$((y + 16)),fill=#e2e8f0,stroke=#5eead4,width=2,radius=3"
    vtg "circle,id=window,cx=$((x + 6)),cy=$y,r=5,fill=#0ea5e9,stroke=none"

    vtg "pageLayerAdd,id=hud,z=10,scroll=fixed"
    vtg "rect,id=hud-bg,x=250,y=622,w=600,h=40,fill=#5eead4,stroke=none,radius=20,layer=hud"
    if [ $((i % 2)) = 1 ]; then slot=B; else slot=A; fi
    vtg "styledText,id=hud-t,x=550,y=631,style=hud,align=center,layer=hud;Scene 3 · frame $i, drawn in buffer $slot · sky drawn once"
    vtg "pageShow"
    i=$((i + 1))
    sleep 0.025
done
sleep 1

# --------------------------------------------------------------------------
# Scene 4 — drawing straight onto the visible page, over the terminal

clear
start_ticker
sleep 1.5
# Transparent: the terminal shows through everywhere nothing is drawn.
vtg "pageOpen,id=bye,bg=none"
vtg "pageShow,select=1"
vtg "rect,id=pill,x=300,y=250,w=500,h=150,fill=#0b1220e0,stroke=#5eead4,width=2,radius=24"
vtg "styledText,id=bye-t,x=550,y=276,style=h2,align=center;A transparent page"
for count in 3 2 1; do
    # This page is visible, so each change appears as it is drawn.
    vtg "attrText,id=bye-s,x=550,y=330,style=body,align=center;$(run - 'Back to the terminal in ')$(run em "$count")$(run - '…')"
    sleep 1
done

# --------------------------------------------------------------------------
# Scene 5 — back to the terminal

vtg "pageEnd"
sleep 2
stop_ticker
printf '\n\033[1mPage mode ended.\033[0m The terminal underneath was never touched.\n'
