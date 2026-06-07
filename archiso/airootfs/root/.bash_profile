#!/bin/bash
export HOME=/root
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export TERM=xterm-256color
export XDG_RUNTIME_DIR="/run/user/0"
export XDG_SESSION_TYPE=wayland
export MOZ_ENABLE_WAYLAND=1
export QT_QPA_PLATFORM=wayland
export GDK_BACKEND=wayland,x11
export ELECTRON_OZONE_PLATFORM_HINT=wayland
mkdir -p "$XDG_RUNTIME_DIR"

# Auto-start on tty1: Sway (Wayland) → startx (X11) → text shell
if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    if command -v sway &>/dev/null; then
        exec sway --unsupported-gpu 2>/tmp/sway.log
    elif command -v startx &>/dev/null; then
        exec startx -- -nolisten tcp >/tmp/startx.log 2>&1
    fi
fi
exec /usr/local/bin/flynn-ui
