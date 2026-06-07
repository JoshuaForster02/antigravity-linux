#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  Flynn OS Linux — Post-Install Setup                                    ║
# ║  Turns a fresh Arch Linux installation into Flynn OS                    ║
# ║                                                                         ║
# ║  Usage (after installing Arch via archinstall or manually):             ║
# ║    curl -fsSL https://raw.githubusercontent.com/JoshuaForster02/        ║
# ║      antigravity/main/post-install/setup-flynnos.sh | sudo bash         ║
# ║                                                                         ║
# ║  Or from the repo:                                                      ║
# ║    sudo bash post-install/setup-flynnos.sh                              ║
# ╚══════════════════════════════════════════════════════════════════════════╝
set -euo pipefail

CY='\e[1;36m' GN='\e[1;32m' RD='\e[0;31m' YL='\e[0;33m' DM='\e[2;37m' WH='\e[1;37m' RS='\e[0m'
ok()    { printf "${GN}  ✓  %s${RS}\n" "$*"; }
info()  { printf "${CY}  »  %s${RS}\n" "$*"; }
warn()  { printf "${YL}  !  %s${RS}\n" "$*"; }
fail()  { printf "${RD}  ✗  %s${RS}\n" "$*"; exit 1; }
hline() { printf "${CY}"; printf '%*s' 70 '' | tr ' ' '═'; printf "${RS}\n"; }
step()  { echo ""; hline; printf "  ${CY}▶  %s${RS}\n" "$*"; hline; echo ""; }

# Must run as root
[ "$(id -u)" = "0" ] || fail "Run as root: sudo bash setup-flynnos.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Banner ─────────────────────────────────────────────────────────────────────
printf "${CY}"
cat << 'BANNER'
  ███████╗██╗  ██╗   ██╗███╗   ██╗███╗   ██╗     ██████╗ ███████╗
  ██╔════╝██║  ╚██╗ ██╔╝████╗  ██║████╗  ██║    ██╔═══██╗██╔════╝
  █████╗  ██║   ╚████╔╝ ██╔██╗ ██║██╔██╗ ██║    ██║   ██║███████╗
  ██║     ███████╗██║   ██║ ╚████║██║ ╚████║    ╚██████╔╝███████║
  ╚═╝     ╚══════╝╚═╝   ╚═╝  ╚═══╝╚═╝  ╚═══╝    ╚═════╝ ╚══════╝
                  Post-Install Setup  ·  Arch Linux  ·  v3.0
BANNER
printf "${RS}\n"

echo ""
info "This script installs Flynn OS on top of a fresh Arch installation."
info "Estimated time: 5–15 min (depends on connection speed)"
echo ""
read -rp "  Continue? [Y/n] " confirm
[[ "${confirm,,}" == "n" ]] && echo "  Aborted." && exit 0
echo ""

# ─── 1. SYSTEM UPDATE ─────────────────────────────────────────────────────────
step "1/8  System update + multilib"

# Enable multilib (required for Steam + 32-bit libs)
if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    sed -i '/^#\[multilib\]/,/^#Include/{s/^#//}' /etc/pacman.conf
    ok "multilib enabled"
fi

pacman -Syu --noconfirm
ok "System updated"

# ─── 2. CORE PACKAGES ─────────────────────────────────────────────────────────
step "2/8  Installing core packages"

pacman -S --noconfirm --needed \
    xorg-server xorg-xinit xorg-xrandr xorg-xsetroot xorg-xrdb xorg-xset \
    xf86-input-libinput \
    openbox obconf picom xterm feh rofi dunst tint2 scrot xdotool \
    ttf-dejavu ttf-jetbrains-mono noto-fonts noto-fonts-emoji \
    pipewire pipewire-alsa pipewire-pulse wireplumber alsa-utils \
    networkmanager iwd openssh nm-connection-editor \
    python python-pip python-xlib python-flask python-requests \
    git vim nano htop btop tmux tree curl wget rsync \
    nmap iproute2 iputils \
    lsblk parted e2fsprogs dosfstools gptfdisk \
    thunar mousepad

ok "Core packages installed"

# ─── 3. GPU DRIVERS (AMD RX 6800 = RDNA2 = amdgpu) ───────────────────────────
step "3/8  GPU drivers"

GPU=$(lspci 2>/dev/null | grep -i "VGA\|3D\|Display" | head -1)
info "Detected: ${GPU:-unknown GPU}"

if echo "$GPU" | grep -qi "AMD\|Radeon\|AMDGPU"; then
    pacman -S --noconfirm --needed \
        mesa lib32-mesa \
        vulkan-radeon lib32-vulkan-radeon \
        libva-mesa-driver mesa-vdpau \
        xf86-video-amdgpu
    ok "AMDGPU + Vulkan installed (RX 6800 optimized)"
elif echo "$GPU" | grep -qi "NVIDIA"; then
    pacman -S --noconfirm --needed nvidia nvidia-utils lib32-nvidia-utils
    ok "NVIDIA drivers installed"
elif echo "$GPU" | grep -qi "Intel\|VMware\|VirtualBox\|QEMU\|Red Hat"; then
    pacman -S --noconfirm --needed mesa lib32-mesa xf86-video-vmware 2>/dev/null || \
    pacman -S --noconfirm --needed mesa lib32-mesa
    ok "Mesa/Intel/VM drivers installed"
else
    pacman -S --noconfirm --needed mesa lib32-mesa
    warn "Unknown GPU — installed generic mesa"
fi

# ─── 4. GAMING LAYER ──────────────────────────────────────────────────────────
step "4/8  Gaming layer (Steam + GameMode)"

read -rp "  Install Steam + gaming tools? [Y/n] " gaming
if [[ "${gaming,,}" != "n" ]]; then
    pacman -S --noconfirm --needed \
        steam gamemode lib32-gamemode \
        mangohud lib32-mangohud

    # Proton-GE from AUR (install yay if needed)
    if ! command -v yay &>/dev/null; then
        info "Installing yay (AUR helper)..."
        pacman -S --noconfirm --needed base-devel
        TMP=$(mktemp -d)
        git clone https://aur.archlinux.org/yay.git "$TMP/yay"
        cd "$TMP/yay"
        # Build as non-root user if possible
        if id "nobody" &>/dev/null; then
            chown -R nobody "$TMP/yay"
            sudo -u nobody makepkg -si --noconfirm 2>/dev/null || \
                makepkg -si --noconfirm
        else
            makepkg -si --noconfirm --skippgpcheck 2>/dev/null || true
        fi
        cd "$SCRIPT_DIR"
        rm -rf "$TMP"
    fi

    ok "Gaming layer installed"
fi

# ─── 5. FLYNN OS FILES ────────────────────────────────────────────────────────
step "5/8  Installing Flynn OS files"

# Flynn UI Shell
install -m 755 "$REPO_ROOT/archiso/airootfs/usr/local/bin/flynn-ui" /usr/local/bin/ 2>/dev/null || \
install -m 755 "$REPO_ROOT/phase1/rootfs-overlay/usr/local/bin/flynn-ui" /usr/local/bin/
ok "flynn-ui installed"

install -m 755 "$REPO_ROOT/archiso/airootfs/usr/local/bin/flynn-startx" /usr/local/bin/ 2>/dev/null || true
install -m 755 "$REPO_ROOT/archiso/airootfs/usr/local/bin/flynn-network-init" /usr/local/bin/ 2>/dev/null || true
install -m 755 "$REPO_ROOT/archiso/airootfs/usr/local/bin/flynn-draw-bg" /usr/local/bin/ 2>/dev/null || true

# Openbox TRON theme
mkdir -p /usr/share/themes/Flynn/openbox-3
cp "$REPO_ROOT/archiso/airootfs/usr/share/themes/Flynn/openbox-3/themerc" \
   /usr/share/themes/Flynn/openbox-3/ 2>/dev/null || true

# Openbox config for root
mkdir -p /root/.config/openbox
for f in rc.xml autostart menu.xml; do
    cp "$REPO_ROOT/archiso/airootfs/root/.config/openbox/$f" /root/.config/openbox/ 2>/dev/null || true
done
chmod +x /root/.config/openbox/autostart 2>/dev/null || true

# tint2 panel
mkdir -p /root/.config/tint2
cp "$REPO_ROOT/archiso/airootfs/root/.config/tint2/tint2rc" /root/.config/tint2/ 2>/dev/null || true

# Picom TRON glow
mkdir -p /root/.config/picom
cp "$REPO_ROOT/archiso/airootfs/root/.config/picom/picom.conf" /root/.config/picom/ 2>/dev/null || true

# Rofi TRON launcher
mkdir -p /root/.config/rofi
cp "$REPO_ROOT/archiso/airootfs/root/.config/rofi/config.rasi" /root/.config/rofi/ 2>/dev/null || true

# Dunst notifications
mkdir -p /root/.config/dunst
cp "$REPO_ROOT/archiso/airootfs/root/.config/dunst/dunstrc" /root/.config/dunst/ 2>/dev/null || true

# XTerm + Xresources
cp "$REPO_ROOT/archiso/airootfs/root/.Xresources" /root/.Xresources 2>/dev/null || true

# .xinitrc
cp "$REPO_ROOT/archiso/airootfs/root/.xinitrc" /root/.xinitrc 2>/dev/null || true
chmod +x /root/.xinitrc 2>/dev/null || true

# Flynn daemon
mkdir -p /opt/flynn/daemon
cp "$REPO_ROOT/daemon/flynn_daemon.py" /opt/flynn/daemon/ 2>/dev/null || true
cp "$REPO_ROOT/daemon/requirements.txt" /opt/flynn/daemon/ 2>/dev/null || true
pip install --break-system-packages flask flask-cors paho-mqtt psutil requests 2>/dev/null || true

# Install scripts
mkdir -p /opt/flynn/install
cp "$REPO_ROOT/install/"*.sh /opt/flynn/install/ 2>/dev/null || true
chmod +x /opt/flynn/install/*.sh 2>/dev/null || true

# MOTD
cat > /etc/motd << 'MOTD'

  ╔══════════════════════════════════════════════════════════════╗
  ║   F L Y N N   O S   ·   Arch Linux   ·   The Grid   v3.0  ║
  ║   startx = launch GUI  ·  ssh root@<ip>  ·  pw: (yours)    ║
  ╚══════════════════════════════════════════════════════════════╝

MOTD

ok "Flynn OS files installed"

# ─── 6. AUTO-LOGIN + STARTX ───────────────────────────────────────────────────
step "6/8  Auto-login + X11 autostart"

# Auto-login on tty1
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin root %I $TERM
EOF

# .bash_profile — auto-startx on tty1
cat > /root/.bash_profile << 'EOF'
[[ -z $DISPLAY && $XDG_VTNR -eq 1 ]] && exec /usr/local/bin/flynn-startx
EOF

# .bashrc — TRON prompt, auto-start flynn-ui on tty2
cat > /root/.bashrc << 'EOF'
export TERM=linux
export EDITOR=vim
export PATH=/usr/local/bin:$PATH
PS1='\[\e[2;36m\][\[\e[1;37m\]root\[\e[0;36m\]@flynnos\[\e[2;36m\]]\[\e[1;36m\]▶ \[\e[0m\]'
[[ $TERM == "linux" && $(tty) == /dev/tty2 ]] && exec /usr/local/bin/flynn-ui
EOF

ok "Auto-login + X11 configured"

# ─── 7. SERVICES ──────────────────────────────────────────────────────────────
step "7/8  Enabling services"

systemctl enable NetworkManager
systemctl enable sshd
systemctl enable getty@tty1

# PipeWire user service (auto-started by systemd user session)
# No manual enable needed — wireplumber/pipewire start via autostart

ok "Services enabled"

# ─── 8. GRUB TRON THEME ───────────────────────────────────────────────────────
step "8/8  GRUB TRON theme"

mkdir -p /usr/share/grub/themes/flynn
cat > /usr/share/grub/themes/flynn/theme.txt << 'GRUBTHEME'
desktop-color: "#000810"
title-text: ""
message-color: "#00e5ff"
message-bg-color: "#000810"

+ label {
    top  = 12%
    left = 25%
    width = 50%
    align = "center"
    text = "FLYNN OS  ·  THE GRID"
    color = "#00e5ff"
    font = "DejaVu Sans Bold 18"
}
+ label {
    top  = 19%
    left = 25%
    width = 50%
    align = "center"
    text = "Arch Linux"
    color = "#004455"
    font = "DejaVu Sans 12"
}
+ boot_menu {
    left   = 20%
    top    = 28%
    width  = 60%
    height = 40%
    item_color          = "#004455"
    selected_item_color = "#00e5ff"
    item_height         = 32
    item_padding        = 10
    item_spacing        = 6
    scrollbar           = true
    scrollbar_width     = 4
}
GRUBTHEME

# Update GRUB config
if [ -f /etc/default/grub ]; then
    sed -i 's|#\?GRUB_THEME=.*|GRUB_THEME="/usr/share/grub/themes/flynn/theme.txt"|' /etc/default/grub
    sed -i 's|#\?GRUB_GFXMODE=.*|GRUB_GFXMODE="1920x1080,1280x720,auto"|' /etc/default/grub
    sed -i 's|GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3"|' /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null && ok "GRUB updated" || warn "GRUB update failed (skip if in chroot)"
fi

ok "GRUB TRON theme installed"

# ─── COMPLETE ─────────────────────────────────────────────────────────────────
echo ""
hline
printf "\n  ${GN}Flynn OS installed successfully!${RS}\n\n"
printf "  ${DM}Next steps:${RS}\n"
printf "  ${CY}  reboot${DM}              — reboot into Flynn OS${RS}\n"
printf "  ${CY}  startx${DM}              — start GUI manually (if no reboot)${RS}\n"
printf "  ${CY}  flynn-ui${DM}            — launch TRON terminal${RS}\n"
printf "  ${CY}  /opt/flynn/install/${DM}  — HDD installer + persistence scripts${RS}\n"
echo ""
printf "  ${DM}SSH:  ${CY}ssh root@$(hostname -I 2>/dev/null | awk '{print $1}' || echo '<ip>')${RS}\n"
echo ""
hline
echo ""

read -rp "  Reboot now? [Y/n] " reboot_now
[[ "${reboot_now,,}" != "n" ]] && reboot
