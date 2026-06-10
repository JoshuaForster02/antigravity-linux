#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  Flynn OS Linux — Disk Installer                                        ║
# ║  Installs Flynn OS to a disk with optional Windows dual-boot            ║
# ║  Run from live ISO: bash /opt/flynn/install/install-to-disk.sh          ║
# ╚══════════════════════════════════════════════════════════════════════════╝
set -euo pipefail

CY='\e[1;36m' GN='\e[1;32m' RD='\e[0;31m' YL='\e[0;33m' DM='\e[2;37m' WH='\e[1;37m' RS='\e[0m'
ok()   { printf "${GN}  ✓  %s${RS}\n" "$*"; }
info() { printf "${CY}  »  %s${RS}\n" "$*"; }
warn() { printf "${YL}  !  %s${RS}\n" "$*"; }
die()  { printf "${RD}  ✗  %s${RS}\n" "$*"; exit 1; }
hline(){ printf "${CY}"; printf '%*s' 70 ''|tr ' ' '═'; printf "${RS}\n"; }

hline
printf "${CY}"; cat <<'BANNER'
  ███████╗██╗  ██╗   ██╗███╗   ██╗███╗   ██╗     ██████╗ ███████╗
  ██╔════╝██║  ╚██╗ ██╔╝████╗  ██║████╗  ██║    ██╔═══██╗██╔════╝
  █████╗  ██║   ╚████╔╝ ██╔██╗ ██║██╔██╗ ██║    ██║   ██║███████╗
  ██║     ███████╗██║   ██║ ╚████║██║ ╚████║    ╚██████╔╝███████║
  ╚═╝     ╚══════╝╚═╝   ╚═╝  ╚═══╝╚═╝  ╚═══╝    ╚═════╝ ╚══════╝
BANNER
printf "${RS}"
hline; echo ""

# ── Parse args ────────────────────────────────────────────────────────────────
TARGET="${1:-}"
MODE="full"   # full = wipe+install, dualboot = keep Windows EFI/partition

for arg in "$@"; do
    case "$arg" in
        --target=*) TARGET="${arg#*=}" ;;
        --target)   shift; TARGET="$1" ;;
        --dualboot) MODE="dualboot" ;;
    esac
done

# ── Interactive target selection ──────────────────────────────────────────────
if [ -z "$TARGET" ]; then
    info "Available disks:"
    echo ""
    lsblk -d -o NAME,SIZE,MODEL,TRAN 2>/dev/null | awk '
        NR==1{printf "  \033[2;36m%-10s %-8s %-30s %s\033[0m\n",$1,$2,$3,$4;next}
        {printf "  \033[1;37m/dev/%-6s\033[0;36m %-8s \033[2;37m%-30s %s\033[0m\n",$1,$2,$3,$4}'
    echo ""
    printf "  ${WH}Target disk (e.g. sda, nvme0n1) [q=quit]: ${RS}"
    read -r TARGET
    [ "$TARGET" = "q" ] || [ -z "$TARGET" ] && echo "  Aborted." && exit 0
    # Strip /dev/ prefix if given
    TARGET="/dev/${TARGET#/dev/}"
fi

[ -b "$TARGET" ] || die "Not a block device: $TARGET"

# Check for Windows EFI (dual-boot detection)
WINDOWS_EFI=""
for part in ${TARGET}*; do
    [ -b "$part" ] || continue
    fs=$(lsblk -no FSTYPE "$part" 2>/dev/null||true)
    label=$(lsblk -no LABEL "$part" 2>/dev/null||true)
    if [ "$fs" = "vfat" ] && (echo "$label"|grep -qi "EFI\|System\|BOOT"); then
        WINDOWS_EFI="$part"
    fi
done

[ -n "$WINDOWS_EFI" ] && warn "Windows EFI partition detected at $WINDOWS_EFI"
printf "  ${YL}Install mode:${RS}\n"
printf "    ${WH}1${RS}  ${DM}Dual-boot — keep Windows, use free space automatically${RS}\n"
printf "    ${WH}2${RS}  ${DM}Full wipe — erase EVERYTHING, Flynn OS only${RS}\n"
printf "    ${WH}3${RS}  ${DM}Advanced  — pick existing partitions yourself (nothing auto-deleted)${RS}\n"
printf "    ${WH}q${RS}  ${DM}Quit${RS}\n\n"
printf "  ${WH}Choice: ${RS}"; read -r choice
case "$choice" in
    1) MODE="dualboot" ;;
    2) MODE="full" ;;
    3) MODE="advanced" ;;
    *) echo "  Aborted." && exit 0 ;;
esac

if [ "$MODE" = "advanced" ]; then
    # ── Advanced: user picks partitions (prepare them beforehand, e.g. in
    #    Windows Disk Management or with: cfdisk $TARGET ) ────────────────────
    echo ""
    info "Current layout:"
    lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "$TARGET" | sed 's/^/    /'
    echo ""
    printf "  ${WH}Root partition for Flynn OS (e.g. ${TARGET}3) — WILL BE FORMATTED ext4: ${RS}"
    read -r ROOT_PART
    [ -b "$ROOT_PART" ] || { warn "Not a block device: $ROOT_PART"; exit 1; }
    printf "  ${WH}EFI partition (e.g. ${TARGET}1) — kept as-is, NOT formatted: ${RS}"
    read -r EFI_PART
    [ -b "$EFI_PART" ] || { warn "Not a block device: $EFI_PART"; exit 1; }
    SWAP_PART=""
    echo ""
    warn "ONLY $ROOT_PART will be formatted. $EFI_PART stays untouched."
    printf "  ${RD}Type YES to confirm: ${WH}"; read -r confirm; printf "${RS}"
    [ "$confirm" = "YES" ] || { echo "  Aborted."; exit 0; }
    mkfs.ext4 -L "FLYNNOS_ROOT" -q -F "$ROOT_PART"
    ok "Root formatted: $ROOT_PART"
fi

if [ "$MODE" != "advanced" ]; then
echo ""
if [ "$MODE" = "dualboot" ]; then
    info "Mode: DUAL-BOOT  (Windows preserved)"
else
    warn "Mode: FULL WIPE  (ALL data on $TARGET will be erased)"
fi
echo ""
printf "  ${RD}Type YES to confirm: ${WH}"; read -r confirm; printf "${RS}"
[ "$confirm" = "YES" ] || { echo "  Aborted."; exit 0; }
echo ""

# ── Partitioning ──────────────────────────────────────────────────────────────
info "Partitioning $TARGET ..."

if [ "$MODE" = "full" ]; then
    # GPT: 512MB EFI + 2GB swap + rest = root
    parted -s "$TARGET" mklabel gpt
    parted -s "$TARGET" mkpart EFI fat32 1MiB 513MiB
    parted -s "$TARGET" set 1 esp on
    parted -s "$TARGET" mkpart swap linux-swap 513MiB 2561MiB
    parted -s "$TARGET" mkpart root ext4 2561MiB 100%

    # Determine partition names (sda1 vs nvme0n1p1)
    if echo "$TARGET" | grep -q "nvme\|mmcblk"; then
        EFI_PART="${TARGET}p1"
        SWAP_PART="${TARGET}p2"
        ROOT_PART="${TARGET}p3"
    else
        EFI_PART="${TARGET}1"
        SWAP_PART="${TARGET}2"
        ROOT_PART="${TARGET}3"
    fi

    info "Formatting..."
    mkfs.vfat -F32 -n "FLYNNOS_EFI" "$EFI_PART"
    mkswap -L "FLYNNOS_SWAP" "$SWAP_PART"
    mkfs.ext4 -L "FLYNNOS_ROOT" -q "$ROOT_PART"

else
    # Dual-boot: find free space and create a Flynn partition
    # For simplicity we create one large partition in available free space
    warn "Dual-boot partitioning — using remaining free space"
    END=$(parted -s "$TARGET" unit MiB print free 2>/dev/null | awk '/Free Space/{e=$2;gsub(/MiB/,"",e)}END{print e}')
    START=$(parted -s "$TARGET" unit MiB print free 2>/dev/null | awk '/Free Space/{s=$1;gsub(/MiB/,"",s)}END{print s}')
    [ -z "$START" ] || [ -z "$END" ] && die "Could not find free space on $TARGET"
    [ "$((END-START))" -lt 8192 ] && die "Not enough free space (need 8GB+)"

    parted -s "$TARGET" mkpart "FlynnOS" ext4 "${START}MiB" "${END}MiB"
    sleep 1
    # Find the new partition
    ROOT_PART=$(lsblk -lno NAME,LABEL "$TARGET" 2>/dev/null | awk '/FlynnOS/{print "/dev/"$1}')
    EFI_PART="$WINDOWS_EFI"   # reuse Windows EFI
    SWAP_PART=""

    mkfs.ext4 -L "FLYNNOS_ROOT" -q "$ROOT_PART"
fi
fi   # end non-advanced partitioning

ok "Partitions ready: root=$ROOT_PART  efi=$EFI_PART"

# ── Mount ─────────────────────────────────────────────────────────────────────
MNTROOT="/mnt/flynnos-install"
mkdir -p "$MNTROOT"
mount "$ROOT_PART" "$MNTROOT"
mkdir -p "${MNTROOT}/boot/efi"
mount "$EFI_PART" "${MNTROOT}/boot/efi"
[ -n "$SWAP_PART" ] && swapon "$SWAP_PART" 2>/dev/null || true

# ── Copy rootfs ───────────────────────────────────────────────────────────────
info "Copying Flynn OS rootfs..."
LIVE_ROOT="/"

# Exclude virtual/live-specific paths
rsync -aAX --info=progress2 \
    --exclude=/proc --exclude=/sys --exclude=/dev \
    --exclude=/tmp --exclude=/run --exclude=/mnt \
    --exclude=/media --exclude=/lost+found \
    --exclude=/run/archiso --exclude=/var/cache/pacman/pkg \
    "$LIVE_ROOT" "$MNTROOT/" 2>/dev/null || true

ok "Rootfs copied"

# ── fstab ─────────────────────────────────────────────────────────────────────
info "Writing /etc/fstab..."
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART" 2>/dev/null)
EFI_UUID=$(blkid -s UUID -o value "$EFI_PART" 2>/dev/null)
SWAP_UUID=$([ -n "$SWAP_PART" ] && blkid -s UUID -o value "$SWAP_PART" 2>/dev/null || echo "")

cat > "${MNTROOT}/etc/fstab" << FSTAB
# Flynn OS fstab — generated by install-to-disk.sh
UUID=${ROOT_UUID}  /          ext4  defaults,noatime  0 1
UUID=${EFI_UUID}   /boot/efi  vfat  umask=0077        0 2
$([ -n "$SWAP_UUID" ] && echo "UUID=${SWAP_UUID}   none       swap  sw                0 0")
tmpfs              /tmp       tmpfs defaults,noatime   0 0
FSTAB

ok "fstab written"

# ── Install GRUB + initramfs (Arch) ───────────────────────────────────────────
info "Configuring bootloader for installed system..."

mount --bind /dev  "${MNTROOT}/dev"
mount --bind /proc "${MNTROOT}/proc"
mount --bind /sys  "${MNTROOT}/sys"
mount --bind /run  "${MNTROOT}/run" 2>/dev/null || true

# Remove live-ISO-only mkinitcpio config
rm -f "${MNTROOT}/etc/mkinitcpio.conf.d/archiso.conf"

# Installed-system initramfs: standard hooks + Plymouth boot splash
cat > "${MNTROOT}/etc/mkinitcpio.conf" << 'MKCONF'
# Flynn OS — installed system
MODULES=()
BINARIES=()
FILES=()
HOOKS=(base udev plymouth microcode modconf kms keyboard keymap consolefont block filesystems fsck)
MKCONF

cat > "${MNTROOT}/etc/mkinitcpio.d/linux-zen.preset" << 'PRESET'
PRESETS=('default')
ALL_config='/etc/mkinitcpio.conf'
ALL_kver='/boot/vmlinuz-linux-zen'
default_image='/boot/initramfs-linux-zen.img'
PRESET

chroot "$MNTROOT" plymouth-set-default-theme flynnos 2>/dev/null || true
chroot "$MNTROOT" mkinitcpio -P linux-zen 2>&1 | tail -5

chroot "$MNTROOT" grub-install --target=x86_64-efi --efi-directory=/boot/efi \
    --bootloader-id=FlynnOS --recheck 2>&1 | tail -3

# BIOS fallback for older machines
chroot "$MNTROOT" grub-install --target=i386-pc "$TARGET" 2>/dev/null || true

chroot "$MNTROOT" grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | tail -3

# Enable services on installed system
chroot "$MNTROOT" systemctl enable NetworkManager flynn-daemon sshd 2>/dev/null || true

umount "${MNTROOT}/run" 2>/dev/null || true
umount "${MNTROOT}/dev" "${MNTROOT}/proc" "${MNTROOT}/sys"
ok "GRUB + initramfs configured"

# ── Cleanup ───────────────────────────────────────────────────────────────────
umount "${MNTROOT}/boot/efi"
umount "$MNTROOT"
[ -n "$SWAP_PART" ] && swapoff "$SWAP_PART" 2>/dev/null || true

echo ""
hline
printf "\n  ${GN}Flynn OS installed successfully!${RS}\n\n"
printf "  ${DM}Root:  ${WH}%s  ${DM}(UUID: %s)${RS}\n" "$ROOT_PART" "$ROOT_UUID"
printf "  ${DM}EFI:   ${WH}%s${RS}\n" "$EFI_PART"
[ -n "$SWAP_PART" ] && printf "  ${DM}Swap:  ${WH}%s${RS}\n" "$SWAP_PART"
echo ""
printf "  ${CY}Remove the ISO/USB and reboot to boot into Flynn OS.${RS}\n\n"
hline
echo ""
