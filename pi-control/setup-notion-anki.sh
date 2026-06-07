#!/bin/bash
# Flynn OS — Notion→Anki Sync Setup
# Run on the Pi: sudo bash setup-notion-anki.sh

set -euo pipefail

echo "╔══════════════════════════════════════════════╗"
echo "║  Notion → Anki Auto-Sync Setup              ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── 1. Install Python deps ────────────────────────────────────────────────────
echo "[1/4] Installing Python dependencies..."
pip3 install --break-system-packages requests schedule 2>/dev/null || \
pip3 install requests schedule

# ── 2. Copy script ────────────────────────────────────────────────────────────
echo "[2/4] Installing sync daemon..."
mkdir -p /opt/flynn
cp "$(dirname "$0")/notion_anki_sync.py" /opt/flynn/
chmod +x /opt/flynn/notion_anki_sync.py

# ── 3. Systemd service ────────────────────────────────────────────────────────
echo "[3/4] Creating systemd service..."
cat > /etc/systemd/system/flynn-notion-anki.service << 'SVC'
[Unit]
Description=Flynn OS — Notion to Anki Auto-Sync
After=network-online.target
Wants=network-online.target

[Service]
User=pi
ExecStart=/usr/bin/python3 /opt/flynn/notion_anki_sync.py daemon
Restart=on-failure
RestartSec=30
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable flynn-notion-anki

# ── 4. Config check ───────────────────────────────────────────────────────────
echo "[4/4] Checking config..."
CFG="/etc/flynn/daemon.conf"
mkdir -p /etc/flynn

if ! grep -q "notion_token" "$CFG" 2>/dev/null; then
    echo ""
    echo "  notion_token and notion_db_id not set yet."
    echo "  Add these lines to $CFG:"
    echo ""
    echo "  notion_token   = secret_xxxxxxxxxxxx"
    echo "  notion_db_id   = xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    echo "  anki_host      = 192.168.1.XXX   # PC local IP"
    echo "  anki_port      = 8765"
    echo "  sync_interval  = 60"
fi

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  Setup complete!                            ║"
echo "║                                             ║"
echo "║  1. Add tokens to /etc/flynn/daemon.conf    ║"
echo "║  2. Install AnkiConnect on your PC:         ║"
echo "║     Anki → Tools → Add-ons → 2055492159    ║"
echo "║  3. Start:                                  ║"
echo "║     sudo systemctl start flynn-notion-anki  ║"
echo "║  4. Test:                                   ║"
echo "║     python3 /opt/flynn/notion_anki_sync.py sync  ║"
echo "╚══════════════════════════════════════════════╝"

echo ""
echo "Notion database template URL:"
echo "  https://www.notion.so/templates/  (search 'flashcards')"
echo ""
echo "Required database properties:"
echo "  Front   (Title)       — card front / question"
echo "  Back    (Text)        — card back / answer"
echo "  Tags    (Multi-select)— Anki tags"
echo "  Deck    (Select)      — Anki deck (default: Flynn::Auto)"
echo "  Synced  (Checkbox)    — checked after sync, leave empty for new cards"
