#!/bin/bash
# Flynn OS Phase 3 — TRON Wayland Compositor installer
set -euo pipefail
CY='\e[1;36m' GN='\e[1;32m' RD='\e[0;31m' RS='\e[0m'
info() { printf "${CY}  »  %s${RS}\n" "$*"; }
ok()   { printf "${GN}  ✓  %s${RS}\n" "$*"; }
die()  { printf "${RD}  ✗  %s${RS}\n" "$*"; exit 1; }
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
printf "${CY}  Flynn OS Phase 3 — Compositor Install${RS}\n\n"
info "Installing build dependencies..."
apt-get update -qq && apt-get install -y -qq \
    meson ninja-build pkg-config gcc \
    libwlroots-dev libwayland-dev libxkbcommon-dev \
    libgl-dev libgles-dev libegl-dev \
    libpixman-1-dev libdrm-dev libseat-dev libinput-dev \
    wayland-protocols 2>&1 | tail -3
ok "Build deps installed"
info "Building compositor..."
cd "$REPO_ROOT/compositor"
meson setup build --wipe -Dbuildtype=release 2>&1 | tail -3
ninja -C build -j$(nproc) 2>&1 | tail -5
install -m755 build/flynn-compositor /usr/local/bin/
mkdir -p /usr/share/flynn/shaders
install -m644 shaders/* /usr/share/flynn/shaders/
ok "Installed: /usr/local/bin/flynn-compositor"
cat > /usr/local/bin/flynn-session << 'SESSION'
#!/bin/bash
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY=wayland-1
export WLR_NO_HARDWARE_CURSORS=1
mkdir -p "$XDG_RUNTIME_DIR"
exec /usr/local/bin/flynn-compositor
SESSION
chmod +x /usr/local/bin/flynn-session
ok "Phase 3 done — run: flynn-session"
