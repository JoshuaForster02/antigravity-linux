#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Flynn OS Linux 3.0 — Arch ISO Build Script                 ║
# ║  Requires: Docker Desktop running                           ║
# ║  Output:   output/flynnos-YYYY.MM-x86_64.iso               ║
# ╚══════════════════════════════════════════════════════════════╝
set -euo pipefail
cd "$(dirname "$0")"

IMAGE="flynnos-archiso"
OUTPUT="$(pwd)/output"
mkdir -p "$OUTPUT"

printf "\e[1;36m"
cat << 'BANNER'
  ███████╗██╗  ██╗   ██╗███╗   ██╗███╗   ██╗     ██████╗ ███████╗
  ██╔════╝██║  ╚██╗ ██╔╝████╗  ██║████╗  ██║    ██╔═══██╗██╔════╝
  █████╗  ██║   ╚████╔╝ ██╔██╗ ██║██╔██╗ ██║    ██║   ██║███████╗
  ██║     ███████╗██║   ██║ ╚████║██║ ╚████║    ╚██████╔╝███████║
  ╚═╝     ╚══════╝╚═╝   ╚═╝  ╚═══╝╚═╝  ╚═══╝    ╚═════╝ ╚══════╝
                  Arch Linux  ·  The Grid  ·  v3.0
BANNER
printf "\e[0m\n"

# ── 0. Check Docker ──────────────────────────────────────────────────────────
if ! docker info &>/dev/null; then
    printf "\e[0;31m[ERROR] Docker is not running. Open Docker Desktop first.\e[0m\n"
    exit 1
fi

# ── 1. Build Docker image ────────────────────────────────────────────────────
echo "[1/3] Building archiso Docker image..."
echo "      (downloads Arch base image + archiso — ~500 MB first time)"
echo ""

docker buildx build \
    --platform linux/amd64 \
    --load \
    -t "$IMAGE" \
    -f Dockerfile \
    . 2>&1 | grep -E "^\[|Step|FROM|RUN|COPY|ERROR|pacman|flynnos" || true

echo ""

# ── 2. Build ISO (needs --privileged for loop device mounts) ─────────────────
echo "[2/3] Building Flynn OS ISO..."
echo "      (downloads all Arch packages — 1–3 GB, ~20–40 min first run)"
echo "      (cached on subsequent runs — much faster)"
echo ""

docker run --rm \
    --privileged \
    --platform linux/amd64 \
    -v "${OUTPUT}:/output" \
    "$IMAGE"

# ── 3. Find and report ISO ───────────────────────────────────────────────────
ISO=$(ls "$OUTPUT"/flynnos-*.iso 2>/dev/null | tail -1)

if [ -z "$ISO" ]; then
    printf "\e[0;31m[ERROR] ISO not found in %s\e[0m\n" "$OUTPUT"
    echo "Run manually to see full output:"
    echo "  docker run --rm --privileged --platform linux/amd64 -v \$(pwd)/output:/output $IMAGE"
    exit 1
fi

SIZE=$(du -sh "$ISO" | cut -f1)
echo ""
printf "\e[1;32m✓ ISO ready:\e[0m  %s  (%s)\n\n" "$(basename "$ISO")" "$SIZE"

# ── 4. QEMU launch ───────────────────────────────────────────────────────────
if ! command -v qemu-system-x86_64 &>/dev/null; then
    printf "\e[0;33mQEMU not found.\e[0m  brew install qemu\n"
    echo "  Boot with: qemu-system-x86_64 -cdrom $ISO -m 4G -smp 4 -vga std -boot d"
    exit 0
fi

echo "[3/3] Launching in QEMU..."
echo ""
printf "  \e[2;37mControls: Ctrl+Alt+G = release mouse\e[0m\n"
printf "  \e[2;37mLogin:    root / flynn\e[0m\n"
printf "  \e[2;37mGUI:      auto-starts X11 + Openbox on tty1\e[0m\n\n"

qemu-system-x86_64 \
    -cdrom "$ISO" \
    -m 4G \
    -smp 4 \
    -vga virtio \
    -boot d \
    -device usb-ehci \
    -device usb-tablet \
    -audiodev coreaudio,id=snd0 \
    -device ich9-intel-hda \
    -device hda-output,audiodev=snd0 \
    -display cocoa,show-cursor=on \
    -cpu host \
    -accel hvf \
    -name "Flynn OS Linux 3.0 — The Grid" \
    2>/dev/null || \
qemu-system-x86_64 \
    -cdrom "$ISO" \
    -m 4G \
    -smp 4 \
    -vga std \
    -boot d \
    -device usb-tablet \
    -display cocoa,show-cursor=on \
    -name "Flynn OS Linux 3.0 — The Grid"
