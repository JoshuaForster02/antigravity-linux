#!/bin/sh
# Flynn OS X11 Session — launched by `startx`

export DISPLAY=:0
export HOME=/root
cd /root

# TRON dark background
xsetroot -solid "#000810" 2>/dev/null || true

# Draw animated TRON grid as wallpaper (if Python available)
python3 /usr/local/bin/flynn-draw-bg 2>/dev/null &

# Load Xresources (xterm TRON colors)
[ -f /root/.Xresources ] && xrdb -merge /root/.Xresources 2>/dev/null

# Compositor — use xrender fallback (works in QEMU, no GLX needed)
picom --backend xrender --vsync 2>/dev/null &

# Start Openbox WM
exec openbox --config-file /root/.config/openbox/rc.xml
