#!/bin/bash
# Flynn OS Linux — Native build on Linux (or inside Docker container)
# For running directly inside the build container, not on macOS.
# Usage: docker run --rm -v $(pwd):/src --privileged flynnos-builder bash /src/build-native.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="$SCRIPT_DIR/output"
WORK="/tmp/flynnos-build"
ROOTFS="$WORK/rootfs"
ALPINE_VER="3.19.1"
ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-${ALPINE_VER}-x86_64.tar.gz"

mkdir -p "$OUTPUT" "$ROOTFS"

echo "╔══════════════════════════════════════════════╗"
echo "║  Flynn OS Linux Phase 1 — Native Build      ║"
echo "╚══════════════════════════════════════════════╝"

# ── 1. Alpine mini-rootfs ─────────────────────────────────────────────────────
echo "[1/6] Downloading Alpine ${ALPINE_VER} mini-rootfs..."
if [ ! -f "$WORK/alpine.tar.gz" ]; then
    wget -q --show-progress "$ALPINE_URL" -O "$WORK/alpine.tar.gz"
fi
echo "[1/6] Extracting rootfs..."
tar -xzf "$WORK/alpine.tar.gz" -C "$ROOTFS"

# ── 2. Install packages inside chroot ────────────────────────────────────────
echo "[2/6] Installing packages in rootfs..."
# Copy resolv.conf for DNS
cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf" 2>/dev/null || true

# Mount proc for chroot
mount --bind /proc "$ROOTFS/proc" 2>/dev/null || true

chroot "$ROOTFS" /bin/sh <<'CHROOT'
apk update -q
apk add --no-cache -q \
    bash busybox-extras coreutils util-linux \
    procps python3 py3-pip curl wget ca-certificates \
    iproute2 iputils net-tools ncurses htop nano
pip3 install --no-cache-dir --break-system-packages \
    flask flask-cors paho-mqtt psutil requests 2>/dev/null || true
echo "packages done"
CHROOT

umount "$ROOTFS/proc" 2>/dev/null || true

# ── 3. Apply Flynn OS overlay ─────────────────────────────────────────────────
echo "[3/6] Installing Flynn OS overlay..."
cp -r "$SCRIPT_DIR/rootfs-overlay/." "$ROOTFS/"
chmod +x "$ROOTFS/usr/local/bin/flynn-ui"

# Configure auto-login → Flynn UI
cat > "$ROOTFS/etc/inittab" <<'INITTAB'
::sysinit:/etc/init.d/rcS
::once:/sbin/udhcpc -i eth0 -q 2>/dev/null
tty1::respawn:/bin/login -f root
tty2::respawn:/sbin/getty 38400 tty2
::shutdown:/sbin/swapoff -a
::shutdown:/bin/umount -a -r
INITTAB

# Root auto-login runs /etc/profile which launches flynn-ui on tty1
mkdir -p "$ROOTFS/root"
echo "exec /usr/local/bin/flynn-ui" > "$ROOTFS/root/.profile"
chmod +x "$ROOTFS/root/.profile"

# Set hostname
echo "flynnos" > "$ROOTFS/etc/hostname"
echo "127.0.1.1 flynnos" >> "$ROOTFS/etc/hosts"

# Copy Flynn daemon
mkdir -p "$ROOTFS/opt/flynn/daemon"
cp -r "$SCRIPT_DIR/../daemon/"* "$ROOTFS/opt/flynn/daemon/" 2>/dev/null || true

# ── 4. Get kernel + initrd ────────────────────────────────────────────────────
echo "[4/6] Getting kernel..."
# Try to use the system kernel (when running inside a Linux VM/Docker)
KERNEL=""
INITRD=""

if [ -f /boot/vmlinuz-*-amd64 ]; then
    KERNEL=$(ls /boot/vmlinuz-*-amd64 | head -1)
    INITRD=$(ls /boot/initrd.img-*-amd64 2>/dev/null | head -1)
elif [ -f /boot/vmlinuz ]; then
    KERNEL=/boot/vmlinuz
    INITRD=/boot/initrd.img
fi

if [ -z "$KERNEL" ]; then
    echo "[4/6] Downloading Alpine kernel..."
    ALPINE_ISO_URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-standard-${ALPINE_VER}-x86_64.iso"
    wget -q --show-progress "$ALPINE_ISO_URL" -O "$WORK/alpine.iso"
    # Extract kernel from ISO
    mkdir -p "$WORK/alpine-iso"
    mount -o loop,ro "$WORK/alpine.iso" "$WORK/alpine-iso" 2>/dev/null
    KERNEL="$WORK/alpine-iso/boot/vmlinuz-lts"
    INITRD="$WORK/alpine-iso/boot/initramfs-lts"
fi

echo "[4/6] Kernel: $KERNEL"
echo "[4/6] Initrd: ${INITRD:-none}"

# ── 5. Create initramfs from our rootfs ───────────────────────────────────────
echo "[5/6] Creating initramfs..."
( cd "$ROOTFS" && find . | cpio -H newc -o 2>/dev/null ) | gzip > "$OUTPUT/initrd.img"
cp "$KERNEL" "$OUTPUT/vmlinuz"
echo "[5/6] initramfs: $(du -sh $OUTPUT/initrd.img | cut -f1)"

# ── 6. Build GRUB ISO ─────────────────────────────────────────────────────────
echo "[6/6] Building ISO..."
bash "$SCRIPT_DIR/grub/build-iso.sh" "$ROOTFS" "$SCRIPT_DIR/grub" "$OUTPUT/flynn-os.iso"

echo ""
echo "✓ ISO: $OUTPUT/flynn-os.iso  ($(du -sh $OUTPUT/flynn-os.iso | cut -f1))"
echo ""
echo "Test with:"
echo "  qemu-system-x86_64 -cdrom $OUTPUT/flynn-os.iso -m 1G -vga std -boot d"
