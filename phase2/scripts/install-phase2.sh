#!/bin/bash
# Flynn OS — Phase 2 Install: Boot Experience
# Run this INSIDE Flynn OS after Phase 1 is installed.
# Adds: Plymouth animation, boot chime, TRON login screen.
#
# Usage: sudo bash install-phase2.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "╔══════════════════════════════════════════════╗"
echo "║  Flynn OS — Phase 2: Boot Experience        ║"
echo "╚══════════════════════════════════════════════╝"

# ── 1. Plymouth ───────────────────────────────────────────────────────────────
echo "[1/5] Installing Plymouth..."
apt-get install -y -qq plymouth plymouth-themes 2>/dev/null || \
    apk add --no-cache plymouth 2>/dev/null || \
    echo "Plymouth not available in package manager — manual install needed"

# Install Flynn theme
THEME_DIR="/usr/share/plymouth/themes/flynn"
mkdir -p "$THEME_DIR"
cp "$SCRIPT_DIR/plymouth/flynn-theme/flynn.plymouth" "$THEME_DIR/"
cp "$SCRIPT_DIR/plymouth/flynn-theme/flynn.script"   "$THEME_DIR/"

# Set as default
if command -v plymouth-set-default-theme &>/dev/null; then
    plymouth-set-default-theme flynn
    update-initramfs -u 2>/dev/null || true
    echo "  ✓ Plymouth theme set to 'flynn'"
else
    # Fallback: write to plymouthd config
    mkdir -p /etc/plymouth
    cat > /etc/plymouth/plymouthd.conf <<'PCONF'
[Daemon]
Theme=flynn
ShowDelay=0
PCONF
    echo "  ✓ Plymouth config written"
fi

# Add splash to kernel cmdline (GRUB)
if [ -f /etc/default/grub ]; then
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/' \
        /etc/default/grub 2>/dev/null || true
    update-grub 2>/dev/null || true
fi

# ── 2. Boot Chime ─────────────────────────────────────────────────────────────
echo "[2/5] Installing boot chime..."
apt-get install -y -qq alsa-utils sox 2>/dev/null || \
    apk add --no-cache alsa-utils sox 2>/dev/null || true

mkdir -p /etc/flynnos/sounds
cp "$SCRIPT_DIR/sounds/boot-chime.wav" /etc/flynnos/sounds/

# Plymouth sound hook (plays chime when animation starts)
mkdir -p /usr/share/plymouth/themes/flynn
cat > /usr/share/plymouth/themes/flynn/play-chime.sh <<'CHIME'
#!/bin/sh
# Plays boot chime via ALSA (non-blocking)
aplay /etc/flynnos/sounds/boot-chime.wav &>/dev/null &
CHIME
chmod +x /usr/share/plymouth/themes/flynn/play-chime.sh

echo "  ✓ Boot chime installed at /etc/flynnos/sounds/boot-chime.wav"

# ── 3. greetd Login Screen ────────────────────────────────────────────────────
echo "[3/5] Installing Flynn login screen..."

cp "$SCRIPT_DIR/greetd/flynn-greeter" /usr/local/bin/flynn-greeter
chmod +x /usr/local/bin/flynn-greeter

# greetd (optional, falls back to inittab auto-login)
if apt-get install -y -qq greetd 2>/dev/null; then
    mkdir -p /etc/greetd
    cp "$SCRIPT_DIR/greetd/config.toml" /etc/greetd/config.toml
    # Create greeter user
    useradd -r -s /bin/false greeter 2>/dev/null || true
    systemctl enable greetd 2>/dev/null || true
    echo "  ✓ greetd installed and configured"
else
    # Fallback: update inittab to use Flynn greeter instead of raw login
    if [ -f /etc/inittab ]; then
        sed -i 's|tty1::respawn:/bin/login -f root|tty1::respawn:/usr/local/bin/flynn-greeter|' \
            /etc/inittab
        echo "  ✓ inittab updated to use Flynn greeter"
    fi
fi

# ── 4. Hide kernel boot messages ─────────────────────────────────────────────
echo "[4/5] Silencing kernel boot messages..."
# Write kernel cmdline additions
mkdir -p /etc/flynnos
echo "quiet loglevel=0 rd.systemd.show_status=false vt.global_cursor_default=0" \
    > /etc/flynnos/kernel-quiet.conf
echo "  ✓ Add these to GRUB cmdline for silent boot"

# ── 5. GRUB TRON splash ───────────────────────────────────────────────────────
echo "[5/5] Installing GRUB TRON theme..."
GRUB_THEME_DIR="/boot/grub/themes/flynn"
mkdir -p "$GRUB_THEME_DIR"

# Generate a minimal GRUB theme
cat > "$GRUB_THEME_DIR/theme.txt" <<'GRUBTHEME'
desktop-color: "#06091a"
title-text: ""

+ boot_menu {
    left   = 20%
    top    = 45%
    width  = 60%
    height = 30%
    item_color          = "#33aadd"
    selected_item_color = "#ffffff"
    item_height         = 36
    item_padding        = 12
    item_spacing        = 4
}

+ label {
    text  = "FLYNN OS"
    left  = 20%
    top   = 32%
    width = 60%
    align = "center"
    color = "#22bbdd"
    font  = "Sans Bold 28"
}

+ label {
    text  = "SELECT PROGRAM  //  END OF LINE"
    left  = 20%
    top   = 40%
    width = 60%
    align = "center"
    color = "#1a4455"
    font  = "Sans 12"
}

+ progress_bar {
    id           = "__timeout__"
    left         = 20%
    top          = 82%
    width        = 60%
    height       = 3
    fg_color     = "#22bbdd"
    bg_color     = "#0a2030"
    border_color = "#1a4455"
    show_text    = false
}
GRUBTHEME

if [ -f /etc/default/grub ]; then
    grep -q "GRUB_THEME" /etc/default/grub || \
        echo "GRUB_THEME=\"$GRUB_THEME_DIR/theme.txt\"" >> /etc/default/grub
    update-grub 2>/dev/null || true
    echo "  ✓ GRUB theme installed"
fi

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  Phase 2 installed!                         ║"
echo "║                                             ║"
echo "║  Reboot to see:                             ║"
echo "║  • TRON GRUB menu                           ║"
echo "║  • Grid boot animation (Plymouth)           ║"
echo "║  • Synthesizer boot chime                   ║"
echo "║  • Flynn OS login screen                    ║"
echo "╚══════════════════════════════════════════════╝"
