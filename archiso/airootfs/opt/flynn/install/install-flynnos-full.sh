#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  Flynn OS Linux — Full Post-Boot Installer                         ║
# ║  Installs Phase 2-5 on a running Phase 1 system.                   ║
# ║  Run ONCE after first boot: sudo bash install-flynnos-full.sh      ║
# ╚══════════════════════════════════════════════════════════════════════╝
# Needs: internet access, Debian/Ubuntu/Alpine base

set -euo pipefail

CY='\e[1;36m' GN='\e[1;32m' RD='\e[0;31m' YL='\e[0;33m' DM='\e[2;37m' RS='\e[0m'

ok()   { printf "${GN}  ✓  %s${RS}\n" "$*"; }
info() { printf "${CY}  »  %s${RS}\n" "$*"; }
warn() { printf "${YL}  !  %s${RS}\n" "$*"; }
fail() { printf "${RD}  ✗  %s${RS}\n" "$*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

printf "${CY}"
cat <<'BANNER'
  ███████╗██╗  ██╗   ██╗███╗   ██╗███╗   ██╗     ██████╗ ███████╗
  ██╔════╝██║  ╚██╗ ██╔╝████╗  ██║████╗  ██║    ██╔═══██╗██╔════╝
  █████╗  ██║   ╚████╔╝ ██╔██╗ ██║██╔██╗ ██║    ██║   ██║███████╗
  ██╔══╝  ██║    ╚██╔╝  ██║╚██╗██║██║╚██╗██║    ██║   ██║╚════██║
  ██║     ███████╗██║   ██║ ╚████║██║ ╚████║    ╚██████╔╝███████║
  ╚═╝     ╚══════╝╚═╝   ╚═╝  ╚═══╝╚═╝  ╚═══╝    ╚═════╝ ╚══════╝
BANNER
printf "${RS}\n"
printf "  ${DM}Full system installer  ·  Phase 2 + 3 + 4 + 5${RS}\n\n"

# ── Detect distro + package manager ──────────────────────────────────────────
if command -v apt-get &>/dev/null; then
    PM_UPDATE="apt-get update -qq"
    PM_INSTALL="apt-get install -y -qq"
    DISTRO="debian"
elif command -v apk &>/dev/null; then
    PM_UPDATE="apk update -q"
    PM_INSTALL="apk add --no-cache -q"
    DISTRO="alpine"
else
    fail "Unsupported distro — needs apt or apk"
    exit 1
fi

info "Detected: $DISTRO"

# ── Phase tracking ────────────────────────────────────────────────────────────
PHASES_DONE="/etc/flynnos-phases"
touch "$PHASES_DONE"

phase_done() { grep -q "$1" "$PHASES_DONE" 2>/dev/null; }
mark_done()  { echo "$1" >> "$PHASES_DONE"; }

# ════════════════════════════════════════════════════════════════════════════
# PHASE 2 — Boot Experience
# ════════════════════════════════════════════════════════════════════════════
if ! phase_done "phase2"; then
    printf "\n${CY}══ PHASE 2  Boot Experience ══════════════════════════════${RS}\n\n"

    # PipeWire / ALSA
    info "Installing audio..."
    $PM_UPDATE
    if [ "$DISTRO" = "debian" ]; then
        $PM_INSTALL pipewire pipewire-alsa pipewire-audio pipewire-pulse \
                    alsa-utils pulseaudio-utils 2>/dev/null || \
        $PM_INSTALL alsa-utils 2>/dev/null || warn "Audio install partial"
    else
        $PM_INSTALL alsa-utils alsa-lib 2>/dev/null || true
    fi

    # Boot chime
    CHIME_SRC="$REPO_ROOT/phase2/sounds/boot-chime.wav"
    if [ -f "$CHIME_SRC" ]; then
        mkdir -p /etc/flynnos/sounds
        cp "$CHIME_SRC" /etc/flynnos/sounds/boot-chime.wav
        ok "Boot chime installed"
    fi

    # Plymouth TRON theme
    PLYMOUTH_SRC="$REPO_ROOT/phase2/plymouth/flynn-theme"
    if [ -d "$PLYMOUTH_SRC" ]; then
        mkdir -p /usr/share/plymouth/themes/flynn
        cp -r "$PLYMOUTH_SRC"/. /usr/share/plymouth/themes/flynn/
        if command -v plymouth-set-default-theme &>/dev/null; then
            plymouth-set-default-theme flynn 2>/dev/null || true
        fi
        ok "Plymouth TRON theme installed"
    fi

    # Flynn greeter
    GREETER="$REPO_ROOT/phase2/greetd/flynn-greeter"
    if [ -f "$GREETER" ]; then
        cp "$GREETER" /usr/local/bin/
        chmod +x /usr/local/bin/flynn-greeter
        ok "Flynn greeter installed"
    fi

    # greetd
    if [ "$DISTRO" = "debian" ]; then
        $PM_INSTALL greetd 2>/dev/null || warn "greetd not available — using getty"
    fi

    mark_done "phase2"
    ok "Phase 2 complete"
fi

# ════════════════════════════════════════════════════════════════════════════
# PHASE 3 — TRON Compositor
# ════════════════════════════════════════════════════════════════════════════
if ! phase_done "phase3"; then
    printf "\n${CY}══ PHASE 3  TRON Compositor ══════════════════════════════${RS}\n\n"

    COMP_DIR="$REPO_ROOT/compositor"
    if [ -d "$COMP_DIR" ] && [ -f "$COMP_DIR/meson.build" ]; then
        info "Building Flynn compositor from source..."
        bash "$COMP_DIR/install-compositor.sh" && ok "Compositor installed" || \
            warn "Compositor build failed — install wlroots manually and retry"
    else
        warn "Compositor source not found at $COMP_DIR"
        info "Clone with: git clone https://github.com/JoshuaForster02/antigravity-linux"
    fi

    mark_done "phase3"
fi

# ════════════════════════════════════════════════════════════════════════════
# PHASE 4 — Apps + Gaming
# ════════════════════════════════════════════════════════════════════════════
if ! phase_done "phase4"; then
    printf "\n${CY}══ PHASE 4  Apps + Gaming ════════════════════════════════${RS}\n\n"

    # Foot terminal
    info "Installing foot terminal..."
    $PM_INSTALL foot 2>/dev/null || warn "foot not in repos — build from source"

    # GTK4 TRON theme
    THEME_SCRIPT="$REPO_ROOT/phase4/theme/install-theme.sh"
    if [ -f "$THEME_SCRIPT" ]; then
        bash "$THEME_SCRIPT" && ok "GTK4 TRON theme installed"
    fi

    # Mako notifications
    info "Installing Mako notifications..."
    $PM_INSTALL mako-notifier 2>/dev/null || \
    $PM_INSTALL dunst         2>/dev/null || warn "No notification daemon found"

    MAKO_CFG="$REPO_ROOT/phase4/notifications/mako.conf"
    if [ -f "$MAKO_CFG" ]; then
        mkdir -p /root/.config/mako
        cp "$MAKO_CFG" /root/.config/mako/config
        ok "Mako config installed"
    fi

    # lf file manager
    info "Installing lf file manager..."
    if ! command -v lf &>/dev/null; then
        wget -q "https://github.com/gokcehan/lf/releases/download/r32/lf-linux-amd64.tar.gz" \
             -O /tmp/lf.tar.gz 2>/dev/null && \
        tar -xzf /tmp/lf.tar.gz -C /usr/local/bin/ && rm /tmp/lf.tar.gz && \
        ok "lf installed" || warn "lf install failed"
    else
        ok "lf already installed"
    fi

    # Core apps
    info "Installing core apps (Neovim, imv)..."
    $PM_INSTALL neovim imv 2>/dev/null || true

    # Copy foot config
    FOOT_CFG="$REPO_ROOT/phase4/config/foot.ini"
    if [ -f "$FOOT_CFG" ]; then
        mkdir -p /root/.config/foot
        cp "$FOOT_CFG" /root/.config/foot/foot.ini
        ok "foot TRON config installed"
    fi

    # Gaming (optional)
    read -rp "  Install gaming layer (Steam, Proton-GE, GameMode)? [y/N] " ans
    if [[ "${ans,,}" == "y" ]]; then
        bash "$REPO_ROOT/phase4/gaming/install-gaming.sh" && ok "Gaming layer installed"
    else
        info "Skipping gaming layer (run phase4/gaming/install-gaming.sh later)"
    fi

    mark_done "phase4"
    ok "Phase 4 complete"
fi

# ════════════════════════════════════════════════════════════════════════════
# PHASE 5 — ANTIGRAVITY Layer
# ════════════════════════════════════════════════════════════════════════════
if ! phase_done "phase5"; then
    printf "\n${CY}══ PHASE 5  ANTIGRAVITY Layer ════════════════════════════${RS}\n\n"

    PHASE5="$REPO_ROOT/phase5/install-phase5.sh"
    if [ -f "$PHASE5" ]; then
        bash "$PHASE5" && ok "ANTIGRAVITY layer installed"
    else
        warn "Phase 5 script not found — run manually"
    fi

    mark_done "phase5"
fi

# ════════════════════════════════════════════════════════════════════════════
# Flynn Daemon
# ════════════════════════════════════════════════════════════════════════════
printf "\n${CY}══ Flynn Daemon (REST API :7777) ══════════════════════════${RS}\n\n"

if command -v pip3 &>/dev/null; then
    info "Installing Flynn daemon Python deps..."
    pip3 install --break-system-packages \
        flask flask-cors paho-mqtt psutil requests 2>/dev/null || \
    pip3 install flask flask-cors paho-mqtt psutil requests || \
    warn "pip install partial"
fi

DAEMON_SRC="$REPO_ROOT/daemon/flynn_daemon.py"
if [ -f "$DAEMON_SRC" ]; then
    mkdir -p /opt/flynn/daemon
    cp "$DAEMON_SRC" /opt/flynn/daemon/
    chmod +x /opt/flynn/daemon/flynn_daemon.py
    ok "Flynn daemon installed"
fi

# Systemd service
DAEMON_SVC="$REPO_ROOT/systemd/flynn-daemon.service"
if [ -f "$DAEMON_SVC" ] && command -v systemctl &>/dev/null; then
    cp "$DAEMON_SVC" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable flynn-daemon
    ok "Flynn daemon service enabled"
fi

# ════════════════════════════════════════════════════════════════════════════
# Final summary
# ════════════════════════════════════════════════════════════════════════════
printf "\n"
printf "${GN}╔══════════════════════════════════════════════════════╗${RS}\n"
printf "${GN}║  Flynn OS — Installation complete!                  ║${RS}\n"
printf "${GN}╚══════════════════════════════════════════════════════╝${RS}\n\n"

printf "  ${DM}Installed phases:${RS}\n"
cat "$PHASES_DONE" | while read p; do
    printf "  ${GN}✓${RS}  %s\n" "$p"
done

printf "\n  ${CY}Start full session:${RS}\n"
printf "  ${DM}  flynn-session${RS}\n"
printf "\n  ${CY}Or run components separately:${RS}\n"
printf "  ${DM}  start-compositor    # Wayland compositor${RS}\n"
printf "  ${DM}  agd                 # ANTIGRAVITY daemon${RS}\n"
printf "  ${DM}  flynn-daemon        # REST API :7777${RS}\n"
printf "\n  ${DM}Reboot recommended to apply all changes.${RS}\n\n"
