#!/bin/bash
# Flynn OS — Game/Study mode switcher
# Usage: game-mode-switch.sh [game|study]
MODE="${1:-game}"

if [ "$MODE" = "game" ]; then
    echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null || true
    systemctl stop flynn-daemon.service 2>/dev/null || true
    export DXVK_ASYNC=1
    export RADV_PERFTEST=aco
    notify-send "GAME MODE" "CPU→Performance  |  Flynn layer off  |  Steam ready" \
        --icon=applications-games --urgency=normal 2>/dev/null || true
    steam 2>/dev/null &
    echo "[flynn] Game Mode ON"
else
    echo schedutil | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null || true
    systemctl start flynn-daemon.service 2>/dev/null || true
    notify-send "STUDY MODE" "CPU→Schedutil  |  Flynn layer on  |  Focus active" \
        --icon=applications-education --urgency=normal 2>/dev/null || true
    echo "[flynn] Study Mode ON"
fi
