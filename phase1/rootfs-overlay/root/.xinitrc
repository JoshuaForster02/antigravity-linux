#!/bin/sh
# Flynn OS X11 Session

export DISPLAY=:0

# Set TRON-dark root window colour
xsetroot -solid "#000810" 2>/dev/null || true

# Compositor for transparency/shadows (optional, graceful fail)
picom --backend glx --vsync --no-fading-openclose 2>/dev/null &

# Start Openbox WM
exec openbox --config-file /root/.config/openbox/rc.xml
