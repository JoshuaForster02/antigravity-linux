#!/bin/sh
# Flynn OS — X11 session init

# Load TRON colour palette for XTerm
[ -f ~/.Xresources ] && xrdb -merge ~/.Xresources

# Set cursor (hidden — TRON has no cursor)
xsetroot -solid "#000810" -cursor_name left_ptr

# Keyboard repeat rate
xset r rate 300 50 2>/dev/null || true

# Disable screen blanking
xset s off s noblank dpms 0 0 0 2>/dev/null || true

# Start Openbox — loads ~/.config/openbox/autostart automatically
exec openbox --config-file /root/.config/openbox/rc.xml
