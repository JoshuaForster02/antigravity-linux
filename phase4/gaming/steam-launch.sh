#!/bin/bash
# Flynn OS — Steam Game Launcher
# Called by the Flynn daemon when the macOS app sends a "launch game" request.
# Usage: steam-launch.sh <steam_app_id>
# Example: steam-launch.sh 730   (CS2)

APP_ID="${1:-}"

if [ -z "$APP_ID" ]; then
    echo "Usage: $0 <steam_app_id>"
    exit 1
fi

# Switch to game mode first
"$(dirname "$0")/game-mode-switch.sh" on

# Small delay for governor to take effect
sleep 0.5

echo "Flynn OS: Launching Steam App $APP_ID..."

# Try flatpak Steam first
if flatpak list 2>/dev/null | grep -q 'com.valvesoftware.Steam'; then
    # With MangoHud + GameMode
    MANGOHUD=1 gamemoderun \
        flatpak run com.valvesoftware.Steam \
        -applaunch "$APP_ID" \
        -fullscreen &
    echo "  Launched via Flatpak Steam (PID $!)"
elif command -v steam &>/dev/null; then
    MANGOHUD=1 gamemoderun \
        steam -applaunch "$APP_ID" -fullscreen &
    echo "  Launched via native Steam (PID $!)"
else
    echo "ERROR: Steam not found. Run install-gaming.sh first."
    exit 1
fi

# Write the PID for later management
echo $! > /tmp/flynn-game.pid
