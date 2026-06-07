#!/usr/bin/env bash
# Flynn OS — archiso customize hook
# Runs inside the chroot during ISO build.

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

# ── Desktop theming ───────────────────────────────────────────────────────────
ln -sf /usr/share/themes/Flynn /root/.themes/Flynn 2>/dev/null || true
mkdir -p /root/.config/gtk-3.0 /root/.config/gtk-4.0 /root/.icons
cat > /root/.config/gtk-3.0/settings.ini << 'GTK3'
[Settings]
gtk-theme-name=FlynnTron
gtk-icon-theme-name=Adwaita
gtk-font-name=JetBrains Mono 11
gtk-cursor-theme-name=Capitaine Cursors
gtk-application-prefer-dark-theme=1
GTK3
cp /root/.config/gtk-3.0/settings.ini /root/.config/gtk-4.0/settings.ini
ln -sf /usr/share/icons/capitaine-cursors /root/.icons/default 2>/dev/null || true
echo "  ✓ GTK4 TRON theme + cursor"

# ── Services ──────────────────────────────────────────────────────────────────
systemctl enable NetworkManager
systemctl enable sshd
systemctl enable getty@tty1
systemctl enable bluetooth.service 2>/dev/null || true
systemctl enable flynn-daemon.service
echo "  ✓ systemd services"

# ── Flynn daemon ──────────────────────────────────────────────────────────────
mkdir -p /opt/flynn/daemon /etc/flynn
chmod 755 /opt/flynn/daemon/flynn_daemon.py 2>/dev/null || true
chmod 755 /usr/local/bin/flynn-boot-chime 2>/dev/null || true
pip install --break-system-packages flask flask-cors paho-mqtt psutil requests wakeonlan 2>/dev/null || true
echo "  ✓ Flynn daemon + Python deps"

# ── Plymouth TRON boot animation ──────────────────────────────────────────────
if [ -f /usr/share/plymouth/themes/flynn/flynn.plymouth ]; then
    mkdir -p /etc/plymouth
    cat > /etc/plymouth/plymouthd.conf << 'PLY'
[Daemon]
Theme=flynn
ShowDelay=0
DeviceTimeout=8
PLY
    plymouth-set-default-theme -R flynn 2>/dev/null || ln -sf ../flynn/flynn.plymouth /usr/share/plymouth/themes/default.plymouth
    echo "  ✓ Plymouth TRON theme"
fi

# ── Kernel cmdline — quiet boot + plymouth ────────────────────────────────────
mkdir -p /etc/cmdline.d
echo 'quiet splash loglevel=3 rd.udev.log_level=3' > /etc/cmdline.d/flynn.conf

# ── GameMode ──────────────────────────────────────────────────────────────────
usermod -a -G gamemode root 2>/dev/null || true

# ── TRON GRUB theme (installed systems) ───────────────────────────────────────
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
    text = "Arch Linux · linux-zen"
    color = "#004455"
    font = "DejaVu Sans 12"
}
GRUBTHEME

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
echo "  ✓ GRUB TRON theme"

# ── Flynn version ─────────────────────────────────────────────────────────────
echo "Flynn OS Linux 3.0 (Arch) — $(date +%Y-%m-%d)" > /etc/flynnos-release
cat /etc/flynnos-release

echo ""
echo "  Flynn OS customize complete ✓"
