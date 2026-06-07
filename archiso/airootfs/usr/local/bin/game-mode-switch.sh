#!/bin/bash
# Flynn OS — Game/Study Mode Switcher
# Wayland (Sway) + X11 kompatibel
# Usage: game-mode-switch.sh [game|study|toggle]

STATE_FILE="/tmp/flynnos-mode"
CURRENT=$(cat "$STATE_FILE" 2>/dev/null || echo "study")

# Toggle logic
if [ "${1:-toggle}" = "toggle" ]; then
    MODE=$([ "$CURRENT" = "game" ] && echo "study" || echo "game")
else
    MODE="$1"
fi

# Notify helper (works on Wayland + X11)
notify() {
    local title="$1" msg="$2"
    if command -v notify-send &>/dev/null; then
        notify-send "$title" "$msg" --urgency=normal 2>/dev/null || true
    fi
    echo "[flynn] $title — $msg"
}

if [ "$MODE" = "game" ]; then
    # ── CPU → Performance ────────────────────────────────────────────────────
    echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor \
        2>/dev/null || true

    # ── AMD GPU perf flags ───────────────────────────────────────────────────
    export AMD_VULKAN_ICD=RADV
    export RADV_PERFTEST=aco,ngg
    export DXVK_ASYNC=1
    export VKD3D_CONFIG=dxr11,dxr
    export MESA_VK_WSI_PRESENT_MODE=mailbox

    # ── gamemode daemon ──────────────────────────────────────────────────────
    command -v gamemoded &>/dev/null && gamemoded 2>/dev/null || true

    # ── Sway: hide waybar + maximize focus ──────────────────────────────────
    if pgrep -x sway &>/dev/null; then
        swaymsg bar mode invisible 2>/dev/null || true
        swaymsg gaps inner all set 0 2>/dev/null || true
        swaymsg gaps outer all set 0 2>/dev/null || true
    fi

    # ── Stop study services ──────────────────────────────────────────────────
    systemctl stop flynn-daemon.service 2>/dev/null || true
    pkill -f antigravity.py 2>/dev/null || true

    # ── Launch Steam ─────────────────────────────────────────────────────────
    echo game > "$STATE_FILE"
    # Stop ambient + health timer in game mode
    /usr/local/bin/flynn-ambient stop 2>/dev/null
    /usr/local/bin/flynn-health stop 2>/dev/null
    export MANGOHUD=1
    notify "⚡ GAME MODE" "CPU→Performance · MangoHud ON · Ambient OFF"
    steam 2>/dev/null &

else
    # ── CPU → Schedutil ─────────────────────────────────────────────────────
    echo schedutil | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor \
        2>/dev/null || true

    # ── Stop gamemode ────────────────────────────────────────────────────────
    pkill gamemoded 2>/dev/null || true

    # ── Sway: restore waybar + gaps ──────────────────────────────────────────
    if pgrep -x sway &>/dev/null; then
        swaymsg bar mode dock 2>/dev/null || true
        swaymsg gaps inner all set 8 2>/dev/null || true
        swaymsg gaps outer all set 4 2>/dev/null || true
    fi

    # ── Restart study services ───────────────────────────────────────────────
    systemctl start flynn-daemon.service 2>/dev/null || true
    python3 /opt/flynn/agd/antigravity.py &>/tmp/agd.log &

    echo study > "$STATE_FILE"
    # Start ambient sound + health timer in study mode
    /usr/local/bin/flynn-ambient start 2>/dev/null &
    /usr/local/bin/flynn-health start 2>/dev/null &
    notify "📚 STUDY MODE" "CPU→Schedutil · Ambient ON · Health timer ON"
fi

echo "[flynn] Mode: $MODE"
