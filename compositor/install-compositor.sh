#!/bin/bash
# Flynn OS — Compositor Install Script
# Builds and installs flynn-compositor from source on the target system.
# Run AFTER Phase 1+2 are installed (needs Wayland base).
#
# Usage:  sudo bash install-compositor.sh
# Needs:  Debian/Ubuntu/Alpine with build-essential, meson, ninja

set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "╔══════════════════════════════════════════════╗"
echo "║  Flynn OS — Compositor Build + Install      ║"
echo "╚══════════════════════════════════════════════╝"

# ── Detect distro ─────────────────────────────────────────────────────────────
if command -v apt-get &>/dev/null; then
    PKG="apt-get install -y -qq"
elif command -v apk &>/dev/null; then
    PKG="apk add --no-cache -q"
else
    echo "Unsupported distro — install deps manually, then run: meson setup build && ninja -C build install"
    exit 1
fi

# ── Install build deps ────────────────────────────────────────────────────────
echo "[1/5] Installing build dependencies..."
$PKG \
    build-essential \
    meson ninja-build \
    pkg-config \
    libwlroots-dev \
    libwayland-dev \
    libxkbcommon-dev \
    libpixman-1-dev \
    libinput-dev \
    libdrm-dev \
    libgles2-mesa-dev \
    libegl1-mesa-dev \
    libgbm-dev \
    2>/dev/null || true

# ── Check wlroots version ─────────────────────────────────────────────────────
echo "[2/5] Checking wlroots..."
if ! pkg-config --exists wlroots 2>/dev/null; then
    echo "  wlroots not found via pkg-config — building from source..."
    apt-get install -y -qq git 2>/dev/null || true
    git clone --depth=1 --branch 0.17.4 \
        https://gitlab.freedesktop.org/wlroots/wlroots.git /tmp/wlroots 2>/dev/null
    cd /tmp/wlroots
    meson setup build -Dprefix=/usr -Dexamples=false
    ninja -C build install
    cd "$DIR"
    ldconfig 2>/dev/null || true
    echo "  wlroots built + installed"
else
    echo "  wlroots $(pkg-config --modversion wlroots) found"
fi

# ── Build compositor ──────────────────────────────────────────────────────────
echo "[3/5] Building flynn-compositor..."
cd "$DIR"
rm -rf build
meson setup build \
    --prefix=/usr \
    --buildtype=release \
    -Dwarnlevel=0 2>&1 | tail -5

ninja -C build 2>&1 | grep -E "Compiling|Linking|error|warning" || true

# ── Install ───────────────────────────────────────────────────────────────────
echo "[4/5] Installing..."
ninja -C build install 2>/dev/null
# Make sure shaders landed
ls /usr/share/flynn-compositor/shaders/ 2>/dev/null && echo "  ✓ shaders installed" || true

# ── Wrapper script ────────────────────────────────────────────────────────────
echo "[5/5] Creating session wrapper..."
cat > /usr/local/bin/start-compositor <<'WRAPPER'
#!/bin/bash
# Start Flynn compositor (Wayland server)
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XDG_SESSION_TYPE=wayland
export WLR_BACKENDS=drm       # drm for real hardware
# Uncomment for testing inside X11:
# export WLR_BACKENDS=x11
# export DISPLAY=:0

mkdir -p "$XDG_RUNTIME_DIR"

exec /usr/bin/flynn-compositor "$@"
WRAPPER
chmod +x /usr/local/bin/start-compositor

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  flynn-compositor installed!                ║"
echo "║  Run:  start-compositor                     ║"
echo "║  Or:   flynn-session  (full desktop)        ║"
echo "╚══════════════════════════════════════════════╝"
