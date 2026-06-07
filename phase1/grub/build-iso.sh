#!/bin/bash
# Called from Dockerfile stage 2
# Args: <rootfs-dir> <grub-dir> <output-iso>
set -euo pipefail

ROOTFS="$1"
GRUB_DIR="$2"
OUTPUT="$3"

STAGING=/tmp/iso-staging
mkdir -p "$STAGING/boot/grub/fonts" "$STAGING/live" /output

# ── Kernel + initrd from rootfs ───────────────────────────────────────────────
VMLINUZ=$(ls "$ROOTFS/boot/vmlinuz"* 2>/dev/null | head -1)
INITRD=$(ls  "$ROOTFS/boot/initramfs"* "$ROOTFS/boot/initrd"* 2>/dev/null | head -1)

if [ -z "$VMLINUZ" ]; then
    echo "[ERROR] No kernel found in $ROOTFS/boot/" && ls "$ROOTFS/boot/" && exit 1
fi

echo "[GRUB] Kernel : $VMLINUZ"
echo "[GRUB] Initrd : ${INITRD:-NONE}"

cp "$VMLINUZ" "$STAGING/boot/vmlinuz"
[ -n "$INITRD" ] && cp "$INITRD" "$STAGING/boot/initrd.img"

# ── Copy GRUB config ──────────────────────────────────────────────────────────
cp "$GRUB_DIR/grub.cfg" "$STAGING/boot/grub/grub.cfg"

# Copy unicode font if available
for font_path in \
    /usr/share/grub/unicode.pf2 \
    /usr/share/grub2/unicode.pf2 \
    /boot/grub/fonts/unicode.pf2; do
    [ -f "$font_path" ] && cp "$font_path" "$STAGING/boot/grub/fonts/" && break
done

# ── Squash the rootfs ─────────────────────────────────────────────────────────
echo "[GRUB] Creating squashfs..."
mksquashfs "$ROOTFS" "$STAGING/live/filesystem.squashfs" \
    -comp gzip -noappend -quiet \
    -e boot proc sys dev run tmp

# ── Build GRUB BIOS image ─────────────────────────────────────────────────────
echo "[GRUB] Installing GRUB into ISO staging..."
grub-mkstandalone \
    --format=i386-pc \
    --output="$STAGING/boot/grub/core.img" \
    --install-modules="linux normal iso9660 biosdisk memdisk search tar ls all_video vbe vga video_bochs video_cirrus gfxterm" \
    --modules="linux normal iso9660 biosdisk search gfxterm" \
    "boot/grub/grub.cfg=$STAGING/boot/grub/grub.cfg"

cat /usr/lib/grub/i386-pc/cdboot.img "$STAGING/boot/grub/core.img" \
    > "$STAGING/boot/grub/bios.img"

# ── Build EFI image ───────────────────────────────────────────────────────────
mkdir -p "$STAGING/EFI/BOOT"
grub-mkstandalone \
    --format=x86_64-efi \
    --output="$STAGING/EFI/BOOT/BOOTX64.EFI" \
    --install-modules="linux normal iso9660 search gfxterm fat" \
    "boot/grub/grub.cfg=$STAGING/boot/grub/grub.cfg" 2>/dev/null || \
    echo "[WARN] EFI boot image failed — BIOS only"

# Create EFI FAT image
dd if=/dev/zero of="$STAGING/boot/grub/efi.img" bs=1M count=4 2>/dev/null
mkfs.fat -F 12 "$STAGING/boot/grub/efi.img" 2>/dev/null
mmd -i "$STAGING/boot/grub/efi.img" ::/EFI ::/EFI/BOOT 2>/dev/null
mcopy -i "$STAGING/boot/grub/efi.img" "$STAGING/EFI/BOOT/BOOTX64.EFI" ::/EFI/BOOT/ 2>/dev/null || true

# ── Assemble ISO ──────────────────────────────────────────────────────────────
echo "[GRUB] Assembling ISO: $OUTPUT"
xorriso -as mkisofs \
    -r -J -joliet-long \
    -V "FLYNNOS" \
    -b boot/grub/bios.img \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    --grub2-boot-info \
    --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
    -eltorito-alt-boot \
    -e boot/grub/efi.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -o "$OUTPUT" \
    "$STAGING" 2>/dev/null || \
xorriso -as mkisofs \
    -r -J -V "FLYNNOS" \
    -b boot/grub/bios.img \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -o "$OUTPUT" \
    "$STAGING"

SIZE=$(du -sh "$OUTPUT" | cut -f1)
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  Flynn OS Linux 1.0 — ISO ready!         ║"
echo "║  Size: $SIZE"
echo "╚══════════════════════════════════════════╝"
