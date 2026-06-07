#!/bin/bash
# Deploy Flynn Pi Agent to the Raspberry Pi
# Run this from your Mac:  bash deploy-to-pi.sh
#
# Pi IP:  100.74.204.71  (Tailscale)
# User:   pi

PI="pi@100.74.204.71"
REMOTE_DIR="/opt/flynn-agent"

set -euo pipefail
cd "$(dirname "$0")"

echo "╔══════════════════════════════════════════════╗"
echo "║  Flynn Pi Agent — Deploying                 ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "Target: $PI"
echo ""

# ── 1. Create remote directory ────────────────────────────────────────────────
echo "[1/4] Creating remote directory..."
ssh "$PI" "mkdir -p $REMOTE_DIR"

# ── 2. Copy agent files ───────────────────────────────────────────────────────
echo "[2/4] Copying agent files..."
scp pi_agent.py              "$PI:$REMOTE_DIR/"
scp setup-pi.sh              "$PI:$REMOTE_DIR/"
scp notion_anki_sync.py      "$PI:$REMOTE_DIR/"
scp setup-notion-anki.sh     "$PI:$REMOTE_DIR/"

# Also copy config template
cat > /tmp/pi-agent.conf <<'CONF'
# Flynn Pi Agent Configuration
# Edit this file on the Pi at: /etc/flynn/pi-agent.conf

mqtt_port    = 1883
mqtt_prefix  = flynn
ollama_host  = http://localhost:11434
ollama_model = mistral

# === REQUIRED: Set your Windows PC's MAC address ===
# Find it: Windows → ipconfig /all → look for "Physical Address" on your LAN adapter
# Example: pc_mac = A4:B1:C1:DD:EE:FF
pc_mac       = AA:BB:CC:DD:EE:FF

# PC hostname or IP on your local network (not Tailscale)
pc_host      = 192.168.1.XXX
pc_api_port  = 7777

# Tailscale IP of your Mac (for direct messaging)
mac_host     = 100.XXX.XXX.XXX
mac_api_port = 7778

# Pi Tailscale IP (set automatically, shown below)
# pi_host    = 100.74.204.71
CONF
scp /tmp/pi-agent.conf "$PI:/tmp/pi-agent-template.conf"

# ── 3. Run setup ──────────────────────────────────────────────────────────────
echo "[3/4] Running setup on Pi (this takes ~5 minutes)..."
ssh -t "$PI" "sudo bash $REMOTE_DIR/setup-pi.sh"

# ── 4. Show status ────────────────────────────────────────────────────────────
echo ""
echo "[4/4] Checking status..."
ssh "$PI" "systemctl is-active flynn-pi 2>/dev/null && echo '  ✓ flynn-pi service: active' || echo '  ✗ flynn-pi service not running'"
ssh "$PI" "systemctl is-active mosquitto && echo '  ✓ Mosquitto MQTT: active' || echo '  ✗ Mosquitto not running'"
ssh "$PI" "ollama list 2>/dev/null | head -5 || echo '  Ollama pulling model (background)...'"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  NEXT STEP: Set your PC's MAC address       ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "SSH into Pi and edit the config:"
echo ""
echo "  ssh $PI"
echo "  sudo nano /etc/flynn/pi-agent.conf"
echo ""
echo "Set 'pc_mac' to your Windows PC's LAN MAC address."
echo "(Windows: ipconfig /all → Physical Address on Ethernet/Wi-Fi adapter)"
echo ""
echo "Then restart the agent:"
echo "  sudo systemctl restart flynn-pi"
echo ""
echo "Test WoL:"
echo "  ssh $PI python3 $REMOTE_DIR/pi_agent.py wake"
echo ""
echo "Live logs:"
echo "  ssh $PI journalctl -u flynn-pi -f"
