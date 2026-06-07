#!/usr/bin/env bash
# Flynn OS — archiso customize hook
# Runs inside the chroot during ISO build.
# Sets up: root password, locale, services, Flynn branding.

set -euo pipefail

echo "╔══════════════════════════════════════╗"
echo "║  Flynn OS archiso customize hook     ║"
echo "╚══════════════════════════════════════╝"

# ── Root password ─────────────────────────────────────────────────────────────
echo "root:flynn" | chpasswd
echo "  ✓ root password: flynn"

# ── Locale ────────────────────────────────────────────────────────────────────
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "  ✓ locale"

# ── Timezone ──────────────────────────────────────────────────────────────────
ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
echo "  ✓ timezone: Europe/Berlin"

# ── Openbox theme symlink ──────────────────────────────────────────────────────
ln -sf /usr/share/themes/Flynn /root/.themes/Flynn 2>/dev/null || true

# ── Enable services ───────────────────────────────────────────────────────────
systemctl enable NetworkManager
systemctl enable sshd
# Auto-start Flynn session on tty1 (already handled by .bash_profile + getty autologin)
systemctl enable getty@tty1

# ── Flynn daemon install ───────────────────────────────────────────────────────
mkdir -p /opt/flynn/daemon
pip install --break-system-packages flask flask-cors paho-mqtt psutil requests wakeonlan 2>/dev/null || true
echo "  ✓ Python deps for Flynn daemon"

# ── Steam multilib ────────────────────────────────────────────────────────────
# Already enabled in pacman.conf — Steam + lib32 packages installed via packages.x86_64

# ── GameMode ──────────────────────────────────────────────────────────────────
usermod -a -G gamemode root 2>/dev/null || true

# ── TRON GRUB theme ───────────────────────────────────────────────────────────
mkdir -p /usr/share/grub/themes/flynn
cat > /usr/share/grub/themes/flynn/theme.txt << 'GRUBTHEME'
desktop-color: "#000810"
title-text: ""
message-color: "#00e5ff"
message-bg-color: "#000810"

+ boot_menu {
    left   = 25%
    top    = 35%
    width  = 50%
    height = 30%
    item_color               = "#004455"
    selected_item_color      = "#00e5ff"
    item_height              = 28
    item_padding             = 8
    item_spacing             = 4
    scrollbar                = true
    scrollbar_width          = 4
    scrollbar_thumb          = "scrollbar_thumb"
}

+ label {
    top  = 15%
    left = 30%
    width = 40%
    align = "center"
    text = "FLYNN OS  //  THE GRID"
    color = "#00e5ff"
    font = "DejaVu Sans Bold 18"
}

+ label {
    top  = 22%
    left = 30%
    width = 40%
    align = "center"
    text = "Arch Linux"
    color = "#004455"
    font = "DejaVu Sans 12"
}
GRUBTHEME

echo "  ✓ GRUB TRON theme"

# ── GRUB config ───────────────────────────────────────────────────────────────
cat > /etc/default/grub << 'GRUBCFG'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Flynn OS"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3"
GRUB_CMDLINE_LINUX=""
GRUB_THEME="/usr/share/grub/themes/flynn/theme.txt"
GRUB_GFXMODE="1920x1080,1280x720,auto"
GRUB_GFXPAYLOAD_LINUX="keep"
GRUB_DISABLE_OS_PROBER=false
GRUBCFG

echo "  ✓ GRUB config"

# ── Flynn version ─────────────────────────────────────────────────────────────
echo "Flynn OS Linux 3.0 (Arch) — $(date +%Y-%m-%d)" > /etc/flynnos-release
cat /etc/flynnos-release

echo ""
echo "  Flynn OS customize complete ✓"
