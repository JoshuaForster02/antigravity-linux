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

# Auto-start on tty1: Sway (Wayland, software-render safe for VMs)
if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    if command -v sway &>/dev/null; then
        # pixman = pure software renderer, works in UTM/QEMU/VMware without GPU
        export WLR_RENDERER=pixman
        export WLR_NO_HARDWARE_CURSORS=1
        export LIBSEAT_BACKEND=noop
        exec sway --unsupported-gpu 2>/tmp/sway.log
    fi
fi
exec /usr/local/bin/flynn-ui
