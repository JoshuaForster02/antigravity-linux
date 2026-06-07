#!/bin/bash
# Run once on your Raspberry Pi:  sudo bash setup-pi.sh
set -euo pipefail

echo "╔══════════════════════════════════════════╗"
echo "║  Flynn Pi Agent — Setup                  ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── System deps ───────────────────────────────────────────────────────────────
apt-get update -qq
apt-get install -y -qq mosquitto mosquitto-clients python3 python3-pip curl

# Allow external MQTT connections
cat > /etc/mosquitto/conf.d/flynn.conf <<'MQTT'
listener 1883
allow_anonymous true
MQTT
systemctl enable mosquitto
systemctl restart mosquitto

# ── Python deps ───────────────────────────────────────────────────────────────
pip3 install --break-system-packages paho-mqtt requests wakeonlan psutil flask

# ── Ollama (local AI on Pi) ────────────────────────────────────────────────────
if ! command -v ollama &>/dev/null; then
    echo "Installing Ollama..."
    curl -fsSL https://ollama.ai/install.sh | sh
fi
# Pull a model that runs well on Pi 5 (4-bit quantized, ~4 GB)
ollama pull mistral:7b-instruct-q4_K_M &

# ── Install agent ─────────────────────────────────────────────────────────────
mkdir -p /opt/flynn /etc/flynn
cp "$(dirname "$0")/pi_agent.py" /opt/flynn/pi_agent.py
chmod +x /opt/flynn/pi_agent.py

# ── systemd service ───────────────────────────────────────────────────────────
cat > /etc/systemd/system/flynn-pi.service <<'SVC'
[Unit]
Description=Flynn Pi Agent
After=network.target mosquitto.service

[Service]
User=pi
ExecStart=/usr/bin/python3 /opt/flynn/pi_agent.py daemon
Restart=always
RestartSec=10
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
SVC
systemctl daemon-reload
systemctl enable flynn-pi
systemctl start flynn-pi

echo ""
echo "✓ Mosquitto MQTT broker running on :1883"
echo "✓ Flynn Pi Agent installed at /opt/flynn/pi_agent.py"
echo "✓ Service: flynn-pi"
echo ""
echo "NEXT: Edit /etc/flynn/pi-agent.conf — set your PC's MAC address:"
echo '  {"pc_mac":"AA:BB:CC:DD:EE:FF","pc_host":"flynnpc.local"}'
echo ""
echo "Get your PC's MAC address:"
echo "  Windows:  ipconfig /all   → Physical Address"
echo "  Linux:    ip link show    → link/ether ..."
echo ""
echo "Commands:"
echo "  python3 /opt/flynn/pi_agent.py status     — check status"
echo "  python3 /opt/flynn/pi_agent.py wake        — wake Flynn PC"
echo "  journalctl -u flynn-pi -f                 — live logs"
