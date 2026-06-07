#!/bin/bash
# Flynn OS — Game Mode Switch
# Called by the Flynn daemon and the macOS app to toggle between Study and Game modes.
# Usage: game-mode-switch.sh on|off

MODE="${1:-}"

enable_game_mode() {
    echo "Flynn OS: Switching to GAME MODE"

    # 1. Set CPU governor to performance
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo performance > "$cpu" 2>/dev/null || true
    done

    # 2. Disable compositor effects (tell flynn-compositor via IPC)
    if [ -S /run/flynn-compositor.sock ]; then
        echo '{"cmd":"set_mode","mode":"game"}' | nc -U /run/flynn-compositor.sock 2>/dev/null || true
    fi

    # 3. Maximize memory for games: drop file caches
    sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

    # 4. Set high-priority scheduling for the calling user's future processes
    # (GameMode daemon handles this per-process via dbus)
    systemctl --user start gamemoded 2>/dev/null || true

    # 5. Notify Flynn daemon
    if [ -f /var/run/flynn-daemon.pid ]; then
        kill -USR1 "$(cat /var/run/flynn-daemon.pid)" 2>/dev/null || true
    fi

    # 6. TRON-style feedback
    echo ""
    printf "\e[1;36m╔══════════════════════════════════════════════╗\n"
    printf "\e[1;36m║  \e[1;32mGAME MODE — ONLINE\e[1;36m                         ║\n"
    printf "\e[1;36m║  CPU: performance  ·  GameMode: active      ║\n"
    printf "\e[1;36m╚══════════════════════════════════════════════╝\n\e[0m"
}

disable_game_mode() {
    echo "Flynn OS: Switching to STUDY MODE"

    # 1. Restore CPU governor
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo schedutil > "$cpu" 2>/dev/null || true
    done

    # 2. Restore compositor
    if [ -S /run/flynn-compositor.sock ]; then
        echo '{"cmd":"set_mode","mode":"study"}' | nc -U /run/flynn-compositor.sock 2>/dev/null || true
    fi

    # 3. Stop gamemoded
    systemctl --user stop gamemoded 2>/dev/null || true

    printf "\e[1;36m╔══════════════════════════════════════════════╗\n"
    printf "\e[1;36m║  \e[1;34mSTUDY MODE — ACTIVE\e[1;36m                        ║\n"
    printf "\e[1;36m║  CPU: schedutil  ·  Focus mode: on          ║\n"
    printf "\e[1;36m╚══════════════════════════════════════════════╝\n\e[0m"
}

case "$MODE" in
    on|enable|game)    enable_game_mode ;;
    off|disable|study) disable_game_mode ;;
    *)
        echo "Usage: $0 on|off"
        echo "  on  = Game Mode (performance CPU, GameMode daemon)"
        echo "  off = Study Mode (power-save CPU, focus compositor)"
        exit 1
        ;;
esac
