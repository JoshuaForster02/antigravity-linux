#!/bin/bash
# Flynn OS — Lokaler ISO Build (Mac + Linux)
# ─────────────────────────────────────────────────────────────────────────────
# Erster Build: ~20-30 min (lädt ~3 GB Arch-Pakete, wird gecached)
# Folgebuilds:  ~5-8 min  (nur geänderte Pakete werden neu geladen)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

IMAGE="flynnos-builder"
OUTPUT="$(pwd)/output"
CACHE="$(pwd)/.pkg-cache"
mkdir -p "$OUTPUT" "$CACHE"

CY='\e[1;36m' GN='\e[1;32m' YL='\e[0;33m' RD='\e[0;31m' RST='\e[0m'

printf "${CY}"
cat << 'BANNER'
  ╔══════════════════════════════════════════════════════════════╗
  ║   F L Y N N   O S  —  Lokaler ISO Build                    ║
  ║   Arch Linux · linux-zen · TRON Desktop                    ║
  ╚══════════════════════════════════════════════════════════════╝
BANNER
printf "${RST}\n"

# ── 0. Docker check ──────────────────────────────────────────────────────────
if ! docker info &>/dev/null; then
    printf "${RD}[✗] Docker läuft nicht. Docker Desktop starten.${RST}\n"
    open -a Docker 2>/dev/null || true
    echo "    Warte 10s..."
    sleep 10
    docker info &>/dev/null || { echo "Docker immer noch nicht bereit."; exit 1; }
fi
printf "${GN}[✓] Docker läuft${RST}\n"

# ── 1. Builder-Image (nur wenn nicht gecached) ───────────────────────────────
if docker image inspect "$IMAGE" &>/dev/null 2>&1; then
    printf "${GN}[✓] Builder-Image gecached (skip)${RST}\n"
else
    printf "${CY}[1/3] Builder-Image bauen (~3 min, einmalig)...${RST}\n"
    docker buildx build \
        --platform linux/amd64 \
        --load \
        -t "$IMAGE" \
        -f Dockerfile \
        . 2>&1 | grep -E "^\[|Step|FROM|RUN|ERROR|warning|✓" || true
    printf "${GN}[✓] Builder-Image fertig${RST}\n"
fi

# ── 2. ISO bauen ─────────────────────────────────────────────────────────────
# Free up Docker overlay space before build
printf "${CY}[1.5] Docker-Overlay bereinigen (freed space)...${RST}\n"
docker system prune -f --filter "until=24h" 2>/dev/null | tail -2 || true

printf "${CY}[2/3] Flynn OS ISO bauen...${RST}\n"
printf "      ${YL}Erster Build: ~20-30 min | Folgebuilds: ~5-8 min${RST}\n"
printf "      Pakete werden in ${CACHE} gecached\n\n"

docker run --rm \
    --privileged \
    --platform linux/amd64 \
    --shm-size=512m \
    --tmpfs /isoout:exec,size=2g \
    -v "$(pwd):/build" \
    -v "$OUTPUT:/output" \
    -v "$CACHE:/var/cache/pacman/pkg" \
    "$IMAGE" \
    bash -c "
        set -e
        mkdir -p /work /output

        echo '=== pacman keyring init ==='
        pacman-key --init
        pacman-key --populate archlinux

        echo '=== archiso installieren ==='
        pacman -Sy --noconfirm --needed archiso grub efibootmgr mtools squashfs-tools dosfstools

        echo '=== Rechte setzen ==='
        find /build/airootfs/usr/local/bin/ -type f -exec chmod +x {} \; 2>/dev/null || true
        find /build/airootfs/opt/flynn/ -name '*.py' -exec chmod +x {} \; 2>/dev/null || true
        chmod +x /build/customize_airootfs.sh

        echo '=== ISO bauen ==='
        mkarchiso -v -w /work -o /isoout /build

        echo '=== Kopiere ISO nach /output ==='
        cp /isoout/*.iso /output/
        cp /isoout/*.iso.sha256 /output/ 2>/dev/null || true

        echo ''
        echo '╔══════════════════════════════════════════╗'
        echo '║   Flynn OS ISO — FERTIG                  ║'
        ls -lh /output/*.iso
        echo '╚══════════════════════════════════════════╝'
    "

# ── 3. Ergebnis ──────────────────────────────────────────────────────────────
ISO=$(ls "$OUTPUT"/flynnos-*.iso 2>/dev/null | tail -1)

if [ -z "$ISO" ]; then
    printf "${RD}[✗] ISO nicht gefunden in %s${RST}\n" "$OUTPUT"
    exit 1
fi

SIZE=$(du -sh "$ISO" | cut -f1)
printf "\n${GN}╔══════════════════════════════════════════════════════╗${RST}\n"
printf "${GN}║  ✓ Flynn OS ISO fertig: %-28s║${RST}\n" "$(basename "$ISO")  ($SIZE)"
printf "${GN}╚══════════════════════════════════════════════════════╝${RST}\n\n"

# ── 4. VMware Fusion oder QEMU starten? ──────────────────────────────────────
ISO_ABS="$(cd "$(dirname "$ISO")" && pwd)/$(basename "$ISO")"

printf "  In VMware Fusion öffnen? [y/N] "; read -r R
if [[ "${R:-n}" =~ ^[Yy] ]]; then
    open -a "VMware Fusion" "$ISO_ABS" 2>/dev/null || \
    open "$ISO_ABS" 2>/dev/null || \
    echo "  Fusion nicht gefunden — öffne $ISO_ABS manuell"
    exit 0
fi

if command -v qemu-system-x86_64 &>/dev/null; then
    printf "  In QEMU starten? [y/N] "; read -r Q
    if [[ "${Q:-n}" =~ ^[Yy] ]]; then
        echo "  Starte QEMU... (Ctrl+Alt+G = Maus freigeben)"
        qemu-system-x86_64 \
            -cdrom "$ISO_ABS" \
            -m 4G -smp 4 \
            -vga std \
            -device usb-tablet \
            -boot d \
            -serial stdio \
            2>/dev/null
    fi
fi

echo "  ISO liegt unter: $ISO_ABS"
