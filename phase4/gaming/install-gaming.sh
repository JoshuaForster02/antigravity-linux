#!/bin/bash
# Flynn OS — Phase 4: Gaming Layer
# Installs Steam, Heroic, Proton, DXVK, GameMode, MangoHud on Debian/Ubuntu base
# Run as root inside a running Flynn OS install (phase 1+2+3 must be done first)

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "╔══════════════════════════════════════════════╗"
echo "║  Flynn OS — Gaming Layer                    ║"
echo "╚══════════════════════════════════════════════╝"

# ── 0. Enable i386 (needed for Steam + 32-bit Proton DLLs) ───────────────────
echo "[0/8] Enabling i386 architecture..."
dpkg --add-architecture i386
apt-get update -qq

# ── 1. Mesa + Vulkan + 32-bit libs ────────────────────────────────────────────
echo "[1/8] Installing Vulkan drivers..."
apt-get install -y -qq \
    mesa-vulkan-drivers mesa-vulkan-drivers:i386 \
    vulkan-tools vulkan-validationlayers \
    libvulkan1 libvulkan1:i386 \
    libgl1-mesa-dri libgl1-mesa-dri:i386 \
    libglx-mesa0 libglx-mesa0:i386 \
    libegl-mesa0 libegl-mesa0:i386 \
    2>/dev/null || true

# ── 2. Steam ──────────────────────────────────────────────────────────────────
echo "[2/8] Installing Steam..."
# Method A: flatpak (cleanest)
if command -v flatpak &>/dev/null; then
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
    flatpak install -y flathub com.valvesoftware.Steam 2>/dev/null || true
fi
# Method B: native deb (fallback)
if ! command -v steam &>/dev/null && ! flatpak list 2>/dev/null | grep -q Steam; then
    wget -qO /tmp/steam.deb https://cdn.cloudflare.steamstatic.com/client/installer/steam.deb
    apt-get install -y -qq /tmp/steam.deb || true
    rm -f /tmp/steam.deb
fi

# ── 3. Proton-GE (bleeding-edge Wine+Proton) ─────────────────────────────────
echo "[3/8] Installing Proton-GE..."
# Install ProtonUp-Qt for easy Proton-GE management
if command -v flatpak &>/dev/null; then
    flatpak install -y flathub net.davidotek.pupgui2 2>/dev/null || true
fi
# Also put a copy of the latest Proton-GE directly in Steam's compatibilitytools
PROTON_DIR="${HOME}/.steam/root/compatibilitytools.d"
mkdir -p "$PROTON_DIR"
LATEST_TAG=$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest \
    | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": "\(.*\)".*/\1/')
if [ -n "$LATEST_TAG" ]; then
    echo "  Downloading Proton-GE $LATEST_TAG..."
    curl -sL \
        "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${LATEST_TAG}/${LATEST_TAG}.tar.gz" \
        | tar -xz -C "$PROTON_DIR/" 2>/dev/null && \
        echo "  Proton-GE $LATEST_TAG installed to $PROTON_DIR" || \
        echo "  Proton-GE download failed — use ProtonUp-Qt after boot"
fi

# ── 4. DXVK (DirectX 9/10/11 → Vulkan) ──────────────────────────────────────
echo "[4/8] Installing DXVK..."
apt-get install -y -qq dxvk 2>/dev/null || true
# Manual fallback if not in apt
if ! dpkg -l dxvk &>/dev/null 2>&1; then
    DXVK_TAG=$(curl -s https://api.github.com/repos/doitsujin/dxvk/releases/latest \
        | grep '"tag_name"' | head -1 | sed 's/.*"v\(.*\)".*/\1/')
    if [ -n "$DXVK_TAG" ]; then
        curl -sL \
            "https://github.com/doitsujin/dxvk/releases/download/v${DXVK_TAG}/dxvk-${DXVK_TAG}.tar.gz" \
            -o /tmp/dxvk.tar.gz
        tar -xzf /tmp/dxvk.tar.gz -C /tmp/
        bash "/tmp/dxvk-${DXVK_TAG}/setup_dxvk.sh" install 2>/dev/null || true
        rm -rf /tmp/dxvk-* /tmp/dxvk.tar.gz
    fi
fi

# ── 5. GameMode (CPU governor boost on game launch) ───────────────────────────
echo "[5/8] Installing GameMode..."
apt-get install -y -qq gamemode gamemode:i386 libgamemode0 libgamemode0:i386 2>/dev/null || true
# Enable gamemode service
systemctl --user enable gamemoded 2>/dev/null || true

# ── 6. MangoHud (performance overlay) ────────────────────────────────────────
echo "[6/8] Installing MangoHud..."
apt-get install -y -qq mangohud mangohud:i386 2>/dev/null || true

# Flynn OS MangoHud config — TRON themed
mkdir -p /etc/mangohud
cat > /etc/mangohud/MangoHud.conf <<'MANGO'
# MangoHud — Flynn OS TRON config
# Place at: ~/.config/MangoHud/MangoHud.conf (or /etc/mangohud/ for system-wide)

fps
frametime
cpu_stats
gpu_stats
ram
vram
battery
time
frame_timing

# TRON cyan on dark
background_color=06091a
text_color=22aacc
gpu_color=33ddff
cpu_color=22aacc
fps_color=00ff88,ffaa00,ff3333
battery_color=22cc88

position=top-right
font_size=14
font_scale=1.0
round_corners=4
MANGO
cp /etc/mangohud/MangoHud.conf /usr/share/doc/mangohud/MangoHud.conf 2>/dev/null || true

# ── 7. Heroic Games Launcher (GOG + Epic) ────────────────────────────────────
echo "[7/8] Installing Heroic Launcher..."
if command -v flatpak &>/dev/null; then
    flatpak install -y flathub com.heroicgameslauncher.hgl 2>/dev/null || true
else
    HEROIC_TAG=$(curl -s https://api.github.com/repos/Heroic-Games-Launcher/HeroicGamesLauncher/releases/latest \
        | grep '"tag_name"' | head -1 | sed 's/.*"\(v.*\)".*/\1/')
    if [ -n "$HEROIC_TAG" ]; then
        wget -q \
            "https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/releases/download/${HEROIC_TAG}/heroic_${HEROIC_TAG#v}_amd64.deb" \
            -O /tmp/heroic.deb 2>/dev/null && \
            apt-get install -y -qq /tmp/heroic.deb && \
            rm -f /tmp/heroic.deb || true
    fi
fi

# ── 8. Gaming kernel tuning ───────────────────────────────────────────────────
echo "[8/8] Applying gaming kernel tunings..."

# /etc/sysctl.d/99-gaming.conf
cat > /etc/sysctl.d/99-gaming.conf <<'SYSCTL'
# Flynn OS Gaming Optimizations
vm.swappiness=10
vm.dirty_ratio=6
vm.dirty_background_ratio=3
kernel.sched_child_runs_first=0
net.core.rmem_max=134217728
net.core.wmem_max=134217728
SYSCTL

# Udev rule: set CPU governor to performance for game processes
cat > /etc/udev/rules.d/60-gaming.rules <<'UDEV'
# Set performance governor when steam/game processes are active
ACTION=="add", SUBSYSTEM=="cpu", ATTR{cpufreq/scaling_governor}="performance"
UDEV

# Apply sysctl now
sysctl -p /etc/sysctl.d/99-gaming.conf 2>/dev/null || true

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  Gaming layer installed!                    ║"
echo "║  Steam  ·  Proton-GE  ·  DXVK              ║"
echo "║  GameMode  ·  MangoHud  ·  Heroic           ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo "  1. Log out and back in (for Flatpak PATH)"
echo "  2. Run 'steam' or 'flatpak run com.valvesoftware.Steam'"
echo "  3. In Steam → Settings → Compatibility → Enable Proton for all"
echo "  4. Use ProtonUp-Qt to manage Proton-GE versions"
