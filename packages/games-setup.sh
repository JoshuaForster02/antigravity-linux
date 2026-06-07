#!/bin/bash
# Flynn OS — Games Layer Setup
# Installs Steam, Proton, Lutris, Gamescope with TRON theming
# Run inside Flynn OS after first boot

set -e

echo "╔══════════════════════════════════════════╗"
echo "║  Flynn OS — Games Layer Installation    ║"
echo "╚══════════════════════════════════════════╝"

# ── Base: Flatpak ─────────────────────────────────────────────────────────────
echo "[1/7] Installing Flatpak runtime..."
apt-get install -y flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# ── Steam ─────────────────────────────────────────────────────────────────────
echo "[2/7] Installing Steam..."
dpkg --add-architecture i386
apt-get update
apt-get install -y steam-installer

# Enable Proton in Steam:
# Steam → Settings → Steam Play → Enable Steam Play for all titles → Proton Experimental

# ── Proton-GE (better game compatibility) ────────────────────────────────────
echo "[3/7] Installing ProtonGE..."
PROTON_VER="GE-Proton9-7"
mkdir -p ~/.steam/root/compatibilitytools.d/
curl -sL "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${PROTON_VER}/${PROTON_VER}.tar.gz" \
    | tar -xz -C ~/.steam/root/compatibilitytools.d/

# ── Lutris (GOG, Epic, etc.) ──────────────────────────────────────────────────
echo "[4/7] Installing Lutris..."
flatpak install -y flathub net.lutris.Lutris

# ── Gamescope (Valve's gaming compositor) ─────────────────────────────────────
echo "[5/7] Installing Gamescope..."
apt-get install -y gamescope

# Gamescope launch script for games
cat > /usr/local/bin/flynn-game << 'GAME'
#!/bin/bash
# Flynn OS game launcher with TRON aesthetic
# Usage: flynn-game "game-command"
gamescope \
    -w 1920 -h 1080 \
    -r 60 \
    --steam \
    --force-grab-cursor \
    -- "$@"
GAME
chmod +x /usr/local/bin/flynn-game

# ── MangoHud (TRON-themed FPS overlay) ───────────────────────────────────────
echo "[6/7] Installing MangoHud..."
apt-get install -y mangohud

mkdir -p ~/.config/MangoHud/
cat > ~/.config/MangoHud/MangoHud.conf << 'MANGO'
# MangoHud — Flynn OS TRON theme
background_alpha=0.4
background_color=00000A
text_color=33AADD
font_size=18
font_file=
position=top-left
round_corners=5

# What to show
fps
frametime
cpu_load
gpu_load
gpu_temp
cpu_temp
ram
vram
time
battery

# Colors
gpu_load_color=22BB66,EEAA00,CC2222
cpu_load_color=22BB66,EEAA00,CC2222
MANGO

# ── Flynn OS Game Mode switcher ───────────────────────────────────────────────
echo "[7/7] Setting up Game Mode switch..."
cat > /usr/local/bin/flynn-gamemode << 'GM'
#!/bin/bash
# Switch between Work Mode and Game Mode
MODE=${1:-game}
if [ "$MODE" = "game" ]; then
    echo "Switching to GAME MODE..."
    # Kill work compositor, launch Gamescope + Steam
    pkill -f flynn-compositor 2>/dev/null
    sleep 0.5
    gamescope -w 1920 -h 1080 --steam -- steam -bigpicture
elif [ "$MODE" = "work" ]; then
    echo "Switching to WORK MODE..."
    pkill -f gamescope 2>/dev/null
    sleep 0.5
    /usr/local/bin/flynn-compositor &
fi
GM
chmod +x /usr/local/bin/flynn-gamemode

echo ""
echo "Games layer installed!"
echo ""
echo "  WORK MODE: flynn-gamemode work"
echo "  GAME MODE: flynn-gamemode game"
echo "  Launch game: flynn-game steam"
echo ""
echo "Keyboard shortcuts in Flynn OS:"
echo "  Super+G  → Game Mode"
echo "  Super+W  → Work Mode"
