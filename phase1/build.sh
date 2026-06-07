#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  Flynn OS Linux — Build Script                                      ║
# ║  Builds a bootable ISO from Docker, then launches in QEMU.         ║
# ╚══════════════════════════════════════════════════════════════════════╝
# Needs: Docker Desktop running, QEMU (brew install qemu)
# Usage: bash build.sh [--no-cache] [--no-run]

set -euo pipefail
cd "$(dirname "$0")"

IMAGE="flynnos-p1"
ISO="output/flynn-os.iso"
NO_CACHE=""
NO_RUN=false

for arg in "$@"; do
    case $arg in
        --no-cache) NO_CACHE="--no-cache" ;;
        --no-run)   NO_RUN=true ;;
    esac
done

mkdir -p output

printf "\e[1;36m"
echo "╔══════════════════════════════════════════════════════╗"
echo "║   F L Y N N   O S   —   Linux Build                 ║"
echo "╚══════════════════════════════════════════════════════╝"
printf "\e[0m\n"

# ── 0. Sync all assets into Docker build context ──────────────────────────────
echo "[0/4] Syncing build assets..."

# Daemon
cp -r ../daemon ./daemon 2>/dev/null && echo "  ✓ daemon" || echo "  - daemon (skipped)"

# Phase 2 — boot experience
mkdir -p phase2/plymouth phase2/sounds phase2/greetd phase2/grub-theme

# Plymouth TRON theme
cp ../phase2/plymouth/flynn-theme/flynn.script   phase2/plymouth/ 2>/dev/null || true
cp ../phase2/plymouth/flynn-theme/flynn.plymouth phase2/plymouth/ 2>/dev/null || true

# Boot chime WAV
if [ -f ../phase2/sounds/boot-chime.wav ]; then
    cp ../phase2/sounds/boot-chime.wav phase2/sounds/
    echo "  ✓ boot-chime.wav"
fi

# TRON greeter
cp ../phase2/greetd/flynn-greeter phase2/greetd/ 2>/dev/null || true

# Install scripts — bundled on live ISO
mkdir -p install
cp -r ../install/. install/ 2>/dev/null && echo "  ✓ install scripts" || echo "  - install (skipped)"

# X11 / Openbox theme already in rootfs-overlay — no extra sync needed
echo "  ✓ X11 session (openbox + TRON theme in rootfs-overlay)"

# GRUB TRON theme (background + theme.txt)
if [ -f ../phase2/grub-theme/background.png ]; then
    cp ../phase2/grub-theme/background.png phase2/grub-theme/
    cp ../phase2/grub-theme/theme.txt      phase2/grub-theme/
    echo "  ✓ GRUB TRON theme"
fi

echo ""

# ── 1. Build Docker image ─────────────────────────────────────────────────────
echo "[1/4] Building image..."
echo "      (first run ~10 min — downloads Alpine + Ubuntu kernel)"
echo ""

docker buildx build \
    --platform linux/amd64 \
    --load \
    $NO_CACHE \
    -t "$IMAGE" \
    -f Dockerfile \
    . 2>&1 | grep -E "^\[|^#[0-9]+|ERROR|error|warning|Flynn|✓|initrd:|kernel:" || true

echo ""

if ! docker image inspect "$IMAGE" &>/dev/null; then
    printf "\e[0;31m[ERROR] Build failed. Run with full output:\e[0m\n"
    echo "  docker buildx build --platform linux/amd64 --load -t $IMAGE -f Dockerfile . 2>&1 | tee build.log"
    exit 1
fi

# ── 2. Extract ISO from image ─────────────────────────────────────────────────
echo "[2/4] Extracting ISO..."
docker run --rm \
    --platform linux/amd64 \
    -v "$(pwd)/output:/out" \
    "$IMAGE" \
    cp /output/flynn-os.iso /out/flynn-os.iso

if [ ! -f "$ISO" ]; then
    printf "\e[0;31m[ERROR] ISO not found at %s\e[0m\n" "$ISO"
    exit 1
fi

SIZE=$(du -sh "$ISO" | cut -f1)
printf "\e[1;32m✓ ISO ready:\e[0m  %s  (%s)\n\n" "$ISO" "$SIZE"

if $NO_RUN; then
    echo "  --no-run: skipping QEMU launch."
    echo "  To boot: qemu-system-x86_64 -cdrom $ISO -m 1G -smp 2 -vga std -boot d"
    exit 0
fi

# ── 3. Check QEMU ─────────────────────────────────────────────────────────────
echo "[3/4] Checking QEMU..."
if ! command -v qemu-system-x86_64 &>/dev/null; then
    printf "\e[0;33mQEMU not found.\e[0m  Install: \e[1;36mbrew install qemu\e[0m\n"
    echo ""
    echo "Then boot with:"
    echo "  qemu-system-x86_64 -cdrom $ISO -m 1G -smp 2 -vga std -boot d"
    exit 0
fi

# ── 4. Launch ─────────────────────────────────────────────────────────────────
echo "[4/4] Launching Flynn OS in QEMU..."
echo ""
printf "  \e[2;37mKernel output appears in THIS terminal (serial).\e[0m\n"
printf "  \e[2;37mLogin prompt appears in QEMU window on tty1.\e[0m\n"
printf "  \e[2;37mControls: Ctrl+Alt+G = release mouse\e[0m\n\n"

ISO_ABS="$(cd "$(dirname "$ISO")" && pwd)/$(basename "$ISO")"

qemu-system-x86_64 \
    -cdrom  "$ISO_ABS" \
    -m      2G \
    -smp    2 \
    -vga    std \
    -boot   d \
    -device usb-ehci \
    -device usb-tablet \
    -serial stdio \
    -display cocoa,show-cursor=on \
    -name   "Flynn OS Linux — The Grid" \
    2>/dev/null || \
qemu-system-x86_64 \
    -cdrom  "$ISO_ABS" \
    -m      2G \
    -smp    2 \
    -vga    std \
    -boot   d \
    -device usb-tablet \
    -serial stdio \
    -name   "Flynn OS Linux — The Grid"
