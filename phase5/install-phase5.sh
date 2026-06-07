#!/bin/bash
# Flynn OS — Phase 5: ANTIGRAVITY Layer
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "╔══════════════════════════════════════════════╗"
echo "║  Flynn OS — Phase 5: ANTIGRAVITY Layer      ║"
echo "╚══════════════════════════════════════════════╝"

# ── 1. GTK4 + layer-shell ─────────────────────────────────────────────────────
echo "[1/4] Installing GTK4 + gtk-layer-shell..."
apt-get install -y -qq \
    python3-gi \
    gir1.2-gtk-4.0 \
    gir1.2-glib-2.0 \
    gtk-layer-shell \
    gir1.2-gtklayershell-0.1 \
    libgtk-layer-shell-dev \
    2>/dev/null || echo "Some GTK4 layer-shell packages may need manual install"

# ── 2. Install AGD ────────────────────────────────────────────────────────────
echo "[2/4] Installing ANTIGRAVITY daemon..."
mkdir -p /opt/flynn/agd
cp "$DIR/agd/antigravity.py" /opt/flynn/agd/
chmod +x /opt/flynn/agd/antigravity.py

cat > /usr/local/bin/agd <<'AGD'
#!/bin/bash
exec python3 /opt/flynn/agd/antigravity.py "$@"
AGD
chmod +x /usr/local/bin/agd

# Systemd user service
mkdir -p /home/flynn/.config/systemd/user
cat > /home/flynn/.config/systemd/user/agd.service <<'SVC'
[Unit]
Description=ANTIGRAVITY Daemon
After=graphical-session.target
PartOf=graphical-session.target

[Service]
ExecStart=/usr/local/bin/agd
Restart=on-failure
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=graphical-session.target
SVC

# ── 3. Flynn session launcher ─────────────────────────────────────────────────
echo "[3/4] Installing Flynn session launcher..."
cp "$DIR/launcher/flynn-session" /usr/local/bin/flynn-session
chmod +x /usr/local/bin/flynn-session

# Desktop session file (for greetd/display managers)
mkdir -p /usr/share/wayland-sessions
cat > /usr/share/wayland-sessions/flynnos.desktop <<'DESK'
[Desktop Entry]
Name=Flynn OS
Comment=TRON-style Wayland compositor
Exec=/usr/local/bin/flynn-session
Type=Application
DESK

# ── 4. greetd config update ───────────────────────────────────────────────────
echo "[4/4] Updating login screen to auto-launch Flynn session..."
if [ -f /etc/greetd/config.toml ]; then
    cat > /etc/greetd/config.toml <<'GREETD'
[terminal]
vt = 1

[default_session]
command = "agreety --cmd /usr/local/bin/flynn-session"
user = "greeter"
GREETD
fi

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  Phase 5 installed!                         ║"
echo "║                                             ║"
echo "║  Start session:  flynn-session              ║"
echo "║  Status bar:     Super+Space for palette    ║"
echo "║  Focus mode:     Super+D                    ║"
echo "╚══════════════════════════════════════════════╝"
