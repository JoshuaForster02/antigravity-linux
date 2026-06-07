#!/bin/bash
# Flynn OS — Install Mako + dunstify notification setup
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

apt-get install -y -qq mako-notifier libnotify-bin 2>/dev/null || \
    apt-get install -y -qq dunst libnotify-bin 2>/dev/null || \
    echo "notification daemon: install mako or dunst manually"

mkdir -p /root/.config/mako
cp "$DIR/mako.conf" /root/.config/mako/config

# Also set up dunst fallback (same TRON style)
mkdir -p /root/.config/dunst
cat > /root/.config/dunst/dunstrc <<'DUNST'
[global]
    monitor = 0
    follow = none
    width = 360
    height = 120
    origin = top-right
    offset = 12x12
    scale = 0
    notification_limit = 5
    progress_bar = true
    progress_bar_height = 3
    progress_bar_frame_width = 1
    progress_bar_min_width = 320
    progress_bar_max_width = 360
    progress_bar_corner_radius = 2
    indicate_hidden = yes
    transparency = 8
    separator_height = 1
    padding = 12
    horizontal_padding = 14
    text_icon_padding = 0
    frame_width = 1
    frame_color = "#22aacc66"
    separator_color = frame
    sort = yes
    idle_threshold = 120
    font = Fira Code 11
    line_height = 0
    markup = full
    format = "<b>%s</b>\n%b"
    alignment = left
    vertical_alignment = center
    show_age_threshold = 60
    ellipsize = middle
    ignore_newline = no
    stack_duplicates = true
    hide_duplicate_count = false
    show_indicators = yes
    icon_corner_radius = 3
    icon_position = left
    min_icon_size = 0
    max_icon_size = 32
    sticky_history = yes
    history_length = 20
    always_run_script = true
    title = Flynn OS
    class = flynnos
    corner_radius = 6
    ignore_dbusclose = false
    force_xwayland = false
    force_xinerama = false
    mouse_left_click = close_current
    mouse_middle_click = do_action, close_current
    mouse_right_click = close_all

[experimental]
    per_monitor_dpi = false

[urgency_low]
    background = "#06091acc"
    foreground = "#556677"
    frame_color = "#1a334488"
    timeout = 3
    default_icon = dialog-information

[urgency_normal]
    background = "#0a0f1aee"
    foreground = "#aaddee"
    frame_color = "#22aacc88"
    timeout = 5
    default_icon = dialog-information

[urgency_critical]
    background = "#1a0a0aee"
    foreground = "#ffaabb"
    frame_color = "#ee4455cc"
    timeout = 0
    default_icon = dialog-warning
DUNST

# Helper: send notification from shell
cat > /usr/local/bin/flynn-notify <<'NOTIFY'
#!/bin/bash
# Usage: flynn-notify "Title" "Body" [urgency=low|normal|critical]
TITLE="${1:-Flynn OS}"
BODY="${2:-}"
URGENCY="${3:-normal}"
if command -v notify-send &>/dev/null; then
    notify-send -u "$URGENCY" -a "flynn-daemon" "$TITLE" "$BODY"
elif command -v dunstify &>/dev/null; then
    dunstify -u "$URGENCY" "$TITLE" "$BODY"
fi
NOTIFY
chmod +x /usr/local/bin/flynn-notify

echo "  ✓ Mako config: /root/.config/mako/config"
echo "  ✓ Dunst config: /root/.config/dunst/dunstrc"
echo "  ✓ flynn-notify helper installed"
