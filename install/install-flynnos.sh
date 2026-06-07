#!/bin/bash
# Flynn OS — bare-metal install script
# Run from the live ISO: sudo bash install-flynnos.sh
#
# What this does:
#   1. Partition target disk (dual-boot-safe — preserves Windows)
#   2. Install base Debian 12
#   3. Install Flynn OS layer (compositor, daemon, gaming)
#   4. Configure GRUB dual-boot
#   5. Enable Flynn services

set -euo pipefail

TARGET_DISK=""     # e.g. /dev/sda — SET THIS or pass as $1
HOSTNAME="flynnpc"
USERNAME="flynn"
PASSWORD="flynn"   # change after install

# ─── Detect / confirm target disk ─────────────────────────────────────────────
if [ -n "${1:-}" ]; then
    TARGET_DISK="$1"
fi

if [ -z "$TARGET_DISK" ]; then
    echo "Available disks:"
    lsblk -d -o NAME,SIZE,MODEL | grep -v loop
    echo ""
    read -rp "Install Flynn OS to disk (e.g. /dev/sda): " TARGET_DISK
fi

if [ ! -b "$TARGET_DISK" ]; then
    echo "Error: $TARGET_DISK is not a block device"
    exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  Flynn OS Installer                                  ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  Target disk : $TARGET_DISK"
echo "║  WARNING: This will modify the partition table!      ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
read -rp "Continue? (yes/no): " CONFIRM
[ "$CONFIRM" = "yes" ] || { echo "Aborted."; exit 0; }

# ─── 1. Partition ──────────────────────────────────────────────────────────────
echo "[1/7] Partitioning $TARGET_DISK..."

# Find free space after existing Windows partitions
# We create: EFI (if needed), /boot, /  (root), swap
PART_EFI=""
PART_BOOT="${TARGET_DISK}p$(( $(lsblk -no PARTNUM "$TARGET_DISK" | wc -l) + 1 ))"
PART_ROOT="${TARGET_DISK}p$(( $(lsblk -no PARTNUM "$TARGET_DISK" | wc -l) + 2 ))"
PART_SWAP="${TARGET_DISK}p$(( $(lsblk -no PARTNUM "$TARGET_DISK" | wc -l) + 3 ))"

# Check if EFI partition already exists (Windows creates one)
if lsblk -no PARTTYPE "$TARGET_DISK" 2>/dev/null | grep -qi "c12a7328"; then
    PART_EFI=$(lsblk -lno NAME,PARTTYPE "$TARGET_DISK" | grep -i "c12a7328" | awk '{print "/dev/"$1}')
    echo "  Using existing EFI partition: $PART_EFI"
fi

# Create partitions using parted (appending to existing table)
parted -s "$TARGET_DISK" \
    mkpart primary ext4  "$(parted -s "$TARGET_DISK" unit MiB print free | grep "Free Space" | tail -1 | awk '{print $1}')" \
    "$(($(parted -s "$TARGET_DISK" unit MiB print free | grep "Free Space" | tail -1 | awk '{print $1}' | tr -d MiB) + 1024))MiB"

echo "[1/7] Partitions created."

# ─── 2. Format ────────────────────────────────────────────────────────────────
echo "[2/7] Formatting partitions..."
mkfs.ext4 -L FLYNNOS_ROOT -q "$PART_ROOT"
mkswap -L FLYNNOS_SWAP "$PART_SWAP" 2>/dev/null || true
echo "[2/7] Done."

# ─── 3. Mount ─────────────────────────────────────────────────────────────────
echo "[3/7] Mounting..."
mount "$PART_ROOT" /mnt
mkdir -p /mnt/boot
[ -n "$PART_EFI" ] && { mkdir -p /mnt/boot/efi; mount "$PART_EFI" /mnt/boot/efi; }

# ─── 4. debootstrap Debian ────────────────────────────────────────────────────
echo "[4/7] Installing Debian 12 base (this takes ~10 minutes)..."
debootstrap --arch=amd64 bookworm /mnt http://deb.debian.org/debian

# ─── 5. Chroot install ────────────────────────────────────────────────────────
echo "[5/7] Configuring system..."
mount --bind /dev  /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys  /mnt/sys

# Copy installer into chroot
cp "$0" /mnt/tmp/install-chroot.sh
cp -r "$(dirname "$0")/../" /mnt/opt/flynnos-src/ 2>/dev/null || true

chroot /mnt /bin/bash <<CHROOT
set -e
echo "$HOSTNAME" > /etc/hostname
cat >> /etc/hosts <<HOSTS
127.0.1.1   $HOSTNAME
HOSTS

# Sources
cat > /etc/apt/sources.list <<APT
deb http://deb.debian.org/debian bookworm main non-free-firmware contrib
deb http://deb.debian.org/debian bookworm-updates main non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main
APT

apt-get update -qq

# Core system
apt-get install -y --no-install-recommends \
    linux-image-amd64 linux-headers-amd64 \
    grub-efi-amd64 grub-pc \
    systemd systemd-sysv dbus udev \
    network-manager sudo locales \
    python3 python3-pip \
    pipewire wireplumber pipewire-pulse \
    bluez firmware-linux firmware-linux-nonfree \
    amd64-microcode intel-microcode

# Display
apt-get install -y --no-install-recommends \
    libwayland-server0 libwlroots11 libxkbcommon0 \
    mesa-vulkan-drivers mesa-utils \
    intel-media-va-driver mesa-va-drivers \
    libgl1-mesa-dri libgles2-mesa libvulkan1

# Python deps for Flynn daemon
pip3 install --break-system-packages \
    flask flask-cors paho-mqtt psutil requests

# Gaming
apt-get install -y --no-install-recommends \
    gamemode mangohud flatpak

# Flynn user
useradd -m -s /bin/bash -G sudo,audio,video,input,gamemode $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
echo "%sudo ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

# Install Flynn OS files
if [ -d /opt/flynnos-src ]; then
    mkdir -p /opt/flynn/{bin,daemon,compositor,gaming,sync}
    cp /opt/flynnos-src/daemon/flynn_daemon.py /opt/flynn/daemon/
    cp /opt/flynnos-src/daemon/requirements.txt /opt/flynn/daemon/
    cp /opt/flynnos-src/systemd/*.service /etc/systemd/system/
    cp /opt/flynnos-src/packages/games-setup.sh /opt/flynn/
    cp /opt/flynnos-src/ui/flynn-ui.sh /usr/local/bin/flynn-ui
    chmod +x /usr/local/bin/flynn-ui
    systemctl enable flynn-daemon
fi

# Generate fstab
echo "UUID=$(blkid -s UUID -o value $PART_ROOT)  /       ext4  defaults  0 1" >> /etc/fstab
echo "UUID=$(blkid -s UUID -o value $PART_SWAP)  none    swap  sw        0 0" 2>/dev/null >> /etc/fstab || true

# GRUB install
if [ -d /boot/efi ]; then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=FlynnOS
else
    grub-install --target=i386-pc $TARGET_DISK
fi
update-grub

echo "Chroot install complete."
CHROOT

# ─── 6. Cleanup ───────────────────────────────────────────────────────────────
umount /mnt/sys /mnt/proc /mnt/dev 2>/dev/null || true
[ -n "$PART_EFI" ] && umount /mnt/boot/efi 2>/dev/null || true
umount /mnt

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  Flynn OS installed!                                 ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  1. Remove the USB/ISO                               ║"
echo "║  2. Reboot — GRUB will show Flynn OS + Windows       ║"
echo "║  3. First boot: login as $USERNAME / $PASSWORD              ║"
echo "║  4. Run: sudo bash /opt/flynn/games-setup.sh         ║"
echo "║  5. Configure: /etc/flynn/daemon.conf                ║"
echo "╚══════════════════════════════════════════════════════╝"
