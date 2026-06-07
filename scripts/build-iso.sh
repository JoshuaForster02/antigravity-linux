#!/bin/bash
# Flynn OS — ISO assembler
# Called by: make iso
# Usage:     ./scripts/build-iso.sh <output-dir> <iso-name>
set -euo pipefail

OUTPUT="${1:-output}"
ISO_NAME="${2:-flynnos.iso}"
STAGING="$OUTPUT/iso-staging"

# Resolve script dir
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "[FLYNN] Building ISO: $ISO_NAME"

# ── 1. Find kernel + initrd ───────────────────────────────────────────────────
if [ -f "$OUTPUT/vmlinuz" ]; then
    KERNEL="$OUTPUT/vmlinuz"
    INITRD="$OUTPUT/initramfs.cpio.gz"
elif ls "$OUTPUT"/rootfs/boot/vmlinuz-* &>/dev/null; then
    KERNEL=$(ls "$OUTPUT"/rootfs/boot/vmlinuz-* | tail -1)
    INITRD=$(ls "$OUTPUT"/rootfs/boot/initrd.img-* | tail -1)
else
    # Use kernel from running system if available (for testing)
    KERNEL="/boot/vmlinuz"
    INITRD="/boot/initrd.img"
fi

echo "[FLYNN] Kernel : $KERNEL"
echo "[FLYNN] Initrd : $INITRD"

# ── 2. Create ISO staging area ───────────────────────────────────────────────
rm -rf "$STAGING"
mkdir -p "$STAGING/boot/grub"
mkdir -p "$STAGING/live"
mkdir -p "$STAGING/EFI/BOOT"

cp "$KERNEL" "$STAGING/boot/vmlinuz"
cp "$INITRD" "$STAGING/boot/initrd.img"

# ── 3. Copy GRUB theme ───────────────────────────────────────────────────────
if [ -d "$SCRIPT_DIR/grub/theme" ]; then
    cp -r "$SCRIPT_DIR/grub/theme" "$STAGING/boot/grub/"
fi
if [ -f "$SCRIPT_DIR/grub/grub.cfg" ]; then
    cp "$SCRIPT_DIR/grub/grub.cfg" "$STAGING/boot/grub/grub.cfg"
else
    # Fallback grub.cfg
    cat > "$STAGING/boot/grub/grub.cfg" <<'GRUB'
set default=0
set timeout=5
insmod all_video
insmod gfxterm
terminal_output gfxterm

menuentry "Flynn OS" {
    linux  /boot/vmlinuz quiet splash
    initrd /boot/initrd.img
}
GRUB
fi

# ── 4. Squash rootfs (if buildroot rootfs.tar.gz exists) ─────────────────────
if [ -f "$OUTPUT/rootfs.tar.gz" ]; then
    echo "[FLYNN] Extracting rootfs..."
    mkdir -p "$OUTPUT/rootfs-extracted"
    tar -xzf "$OUTPUT/rootfs.tar.gz" -C "$OUTPUT/rootfs-extracted"
    echo "[FLYNN] Creating squashfs (may take a few minutes)..."
    mksquashfs "$OUTPUT/rootfs-extracted" "$STAGING/live/filesystem.squashfs" \
        -comp xz -noappend -quiet
elif [ -d "$OUTPUT/rootfs" ]; then
    echo "[FLYNN] Creating squashfs from rootfs dir..."
    mksquashfs "$OUTPUT/rootfs" "$STAGING/live/filesystem.squashfs" \
        -comp xz -noappend -e boot -quiet
else
    echo "[WARN] No rootfs found — ISO will boot to kernel only"
fi

# ── 5. Build EFI boot image ──────────────────────────────────────────────────
if command -v grub-mkimage &>/dev/null; then
    grub-mkimage \
        --format=x86_64-efi \
        --output="$STAGING/EFI/BOOT/BOOTX64.EFI" \
        --prefix="" \
        efidisk iso9660 linux normal configfile fat part_gpt part_msdos \
        2>/dev/null || echo "[WARN] EFI image build failed — BIOS-only ISO"
fi

# ── 6. Assemble final ISO ─────────────────────────────────────────────────────
echo "[FLYNN] Assembling ISO..."
xorriso -as mkisofs \
    -r -J -joliet-long -l \
    -b boot/grub/i386-pc/eltorito.img \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    --grub2-boot-info \
    -V "FLYNNOS" \
    -o "$OUTPUT/$ISO_NAME" \
    "$STAGING" 2>/dev/null || \
xorriso -as mkisofs \
    -r -J -V "FLYNNOS" \
    -b boot/grub/grub.cfg \
    -no-emul-boot \
    -o "$OUTPUT/$ISO_NAME" \
    "$STAGING"

SIZE=$(du -sh "$OUTPUT/$ISO_NAME" 2>/dev/null | cut -f1)
echo ""
echo "╔═══════════════════════════════════════╗"
echo "║  Flynn OS ISO ready!                  ║"
echo "║  File: $OUTPUT/$ISO_NAME"
echo "║  Size: $SIZE"
echo "╚═══════════════════════════════════════╝"
echo ""
echo "Test in QEMU:"
echo "  qemu-system-x86_64 -cdrom $OUTPUT/$ISO_NAME -m 4G -vga std -boot d"
echo ""
echo "Flash to USB:"
echo "  sudo dd if=$OUTPUT/$ISO_NAME of=/dev/sdX bs=4M status=progress"
