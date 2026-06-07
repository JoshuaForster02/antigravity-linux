#!/bin/bash
# Flynn OS — Install GTK4 TRON Theme system-wide
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing Flynn OS GTK4 TRON Theme..."

# System-wide theme
THEME_DIR="/usr/share/themes/FlynnTron/gtk-4.0"
mkdir -p "$THEME_DIR"
cp "$DIR/gtk4-tron.css" "$THEME_DIR/gtk.css"

# User config (takes priority)
mkdir -p /root/.config/gtk-4.0
cp "$DIR/gtk4-tron.css" /root/.config/gtk-4.0/gtk.css

# gsettings (if available)
if command -v gsettings &>/dev/null; then
    gsettings set org.gnome.desktop.interface gtk-theme 'FlynnTron' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface font-name 'Fira Code 11' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface monospace-font-name 'Fira Code 12' 2>/dev/null || true
fi

# GTK3 compatibility (slim dark override)
mkdir -p /usr/share/themes/FlynnTron/gtk-3.0
cat > /usr/share/themes/FlynnTron/gtk-3.0/gtk.css <<'GTK3'
@import url("../gtk-4.0/gtk.css");
/* GTK3 extras */
.background { background-color: #06091a; }
GtkWindow { background-color: #0a0f1a; }
GTK3

# Set env vars for all sessions
cat > /etc/profile.d/flynn-theme.sh <<'ENV'
export GTK_THEME=FlynnTron
export GTK2_RC_FILES=/usr/share/themes/FlynnTron/gtk-2.0/gtkrc
export QT_QPA_PLATFORMTHEME=gtk4
# Force dark mode for Electron apps
export ELECTRON_FORCE_WINDOW_MENU_BAR=0
export GTK_THEME=FlynnTron:dark
ENV

echo "  ✓ Theme installed to /usr/share/themes/FlynnTron/"
echo "  ✓ User config at /root/.config/gtk-4.0/gtk.css"
echo "  ✓ Environment variables set in /etc/profile.d/flynn-theme.sh"
echo ""
echo "Re-login or 'source /etc/profile.d/flynn-theme.sh' to activate."
