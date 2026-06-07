#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  Flynn OS — Persistence Setup                                            ║
# ║  Creates an overlayfs persistence partition on USB / spare partition.   ║
# ║  Run from live: bash /opt/flynn/install/setup-persistence.sh            ║
# ╚══════════════════════════════════════════════════════════════════════════╝
set -euo pipefail

CY='\e[1;36m' GN='\e[1;32m' RD='\e[0;31m' YL='\e[0;33m' DM='\e[2;37m' WH='\e[1;37m' RS='\e[0m'
info() { printf "${CY}  »  %s${RS}\n" "$*"; }
ok()   { printf "${GN}  ✓  %s${RS}\n" "$*"; }
die()  { printf "${RD}  ✗  %s${RS}\n" "$*"; exit 1; }

printf "${CY}  Flynn OS — Persistence Layer Setup${RS}\n\n"

# ── Find USB drives ───────────────────────────────────────────────────────────
info "Detected removable storage:"
echo ""
lsblk -d -o NAME,SIZE,TRAN,MODEL 2>/dev/null | awk '
    /usb/{printf "  \033[1;37m/dev/%-8s\033[0;36m %-8s \033[2;37m%s\033[0m\n",$1,$2,$4}
    NR==1{printf "  \033[2;36m%-10s %-8s %-8s %s\033[0m\n",$1,$2,$3,$4}'
echo ""

printf "  ${WH}Target device for persistence (e.g. sdb) [q=quit]: ${RS}"
read -r TARGET; [ "$TARGET" = "q" ] && exit 0
TARGET="/dev/${TARGET#/dev/}"
[ -b "$TARGET" ] || die "Not a block device: $TARGET"

# ── Create persistence partition ──────────────────────────────────────────────
info "Creating persistence partition on $TARGET..."
PERSIST_PART="${TARGET}1"
echo "$TARGET" | grep -q "nvme\|mmcblk" && PERSIST_PART="${TARGET}p1"

parted -s "$TARGET" mklabel msdos 2>/dev/null || true
parted -s "$TARGET" mkpart primary ext4 1MiB 100%
sleep 1
mkfs.ext4 -L "flynnos-persist" -q "$PERSIST_PART"
ok "Partition created: $PERSIST_PART"

# ── Create overlay structure ──────────────────────────────────────────────────
MNTPT="/mnt/persist-setup"
mkdir -p "$MNTPT"
mount "$PERSIST_PART" "$MNTPT"
mkdir -p "$MNTPT/upper" "$MNTPT/work"

# Copy current user data to persist partition
for dir in /root /home /etc/flynnos /opt/flynn; do
    if [ -d "$dir" ]; then
        UPPER_DIR="$MNTPT/upper${dir}"
        mkdir -p "$UPPER_DIR"
        cp -a "$dir/." "$UPPER_DIR/" 2>/dev/null || true
    fi
done

umount "$MNTPT"
ok "Persistence data seeded"

# ── Write init hook for future boots ─────────────────────────────────────────
PERSIST_UUID=$(blkid -s UUID -o value "$PERSIST_PART")
cat > /etc/profile.d/flynn-persist.sh << HOOK
#!/bin/sh
# Flynn OS — mount persistence overlay on login
PERSIST_UUID="${PERSIST_UUID}"
PERSIST_DEV=\$(blkid -U "\$PERSIST_UUID" 2>/dev/null)
if [ -n "\$PERSIST_DEV" ] && ! mountpoint -q /root; then
    mkdir -p /mnt/persist /mnt/persist/upper /mnt/persist/work
    mount -U "\$PERSIST_UUID" /mnt/persist 2>/dev/null || exit 0
    # Overlay /root and /etc/flynnos
    for dir in root etc/flynnos; do
        mkdir -p "/mnt/persist/upper/\$dir" "/mnt/persist/work/\$dir"
        mount -t overlay overlay \
            -o lowerdir=/\${dir},upperdir=/mnt/persist/upper/\${dir},workdir=/mnt/persist/work/\${dir} \
            "/\${dir}" 2>/dev/null || true
    done
fi
HOOK
chmod +x /etc/profile.d/flynn-persist.sh

echo ""
ok "Persistence set up! UUID: $PERSIST_UUID"
printf "\n  ${DM}On next boot, keep $PERSIST_PART plugged in.${RS}\n"
printf "  ${DM}Your data in /root and /etc/flynnos will persist.${RS}\n\n"
