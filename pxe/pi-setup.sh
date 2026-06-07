#!/bin/bash
# Flynn OS — Raspberry Pi PXE Server Setup
# Run this ON the Pi: sudo bash pi-setup.sh
# After setup: Pi boots the Windows PC into Flynn OS via network

set -e

PC_MAC=""       # fill in: MAC address of Windows PC (e.g. aa:bb:cc:dd:ee:ff)
PI_IP=""        # fill in: Pi IP address (e.g. 192.168.1.10)
PC_IP=""        # fill in: PC IP address (static, e.g. 192.168.1.100)

echo "╔══════════════════════════════════════╗"
echo "║  Flynn OS PXE Server Setup           ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── 1. Install dependencies ───────────────────────────────────────────────────
echo "[1/6] Installing dnsmasq, tftpd-hpa, nfs-kernel-server..."
apt-get update -qq
apt-get install -y -qq dnsmasq tftpd-hpa nfs-kernel-server wakeonlan pv

# ── 2. Configure dnsmasq for PXE ──────────────────────────────────────────────
echo "[2/6] Configuring dnsmasq for PXE boot..."
cat > /etc/dnsmasq.d/pxe.conf << EOF
# PXE boot for Flynn OS
interface=eth0
dhcp-range=${PC_IP},${PC_IP},12h
dhcp-host=${PC_MAC},flynnos-pc,${PC_IP}

# TFTP
enable-tftp
tftp-root=/srv/tftp

# PXE boot file
dhcp-boot=pxelinux.0
pxe-prompt="Flynn OS",1
pxe-service=x86PC,"Flynn OS",pxelinux
EOF

# ── 3. Set up TFTP directory ──────────────────────────────────────────────────
echo "[3/6] Setting up TFTP boot directory..."
mkdir -p /srv/tftp/flynnos

# Copy PXELinux files (requires syslinux-common)
apt-get install -y -qq syslinux-common
cp /usr/lib/syslinux/modules/bios/*.c32 /srv/tftp/ 2>/dev/null || true
cp /usr/lib/PXELINUX/pxelinux.0         /srv/tftp/

# PXELinux config
mkdir -p /srv/tftp/pxelinux.cfg
cat > /srv/tftp/pxelinux.cfg/default << EOF
DEFAULT flynnos
LABEL flynnos
    MENU LABEL Flynn OS Linux
    KERNEL flynnos/vmlinuz
    APPEND initrd=flynnos/initrd.img root=/dev/nfs nfsroot=${PI_IP}:/srv/nfs/flynnos,vers=4 rw ip=dhcp quiet splash
    IPAPPEND 2
EOF

# ── 4. Set up NFS root export ─────────────────────────────────────────────────
echo "[4/6] Setting up NFS root filesystem..."
mkdir -p /srv/nfs/flynnos
echo "/srv/nfs/flynnos ${PC_IP}(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
exportfs -ra

# ── 5. Set up Wake-on-LAN service ─────────────────────────────────────────────
echo "[5/6] Setting up Wake-on-LAN auto-boot..."
cat > /usr/local/bin/flynn-wake << 'WAKE'
#!/bin/bash
# Wake the PC and wait for it to boot Flynn OS
MAC="${1:-$PC_MAC}"
echo "[Flynn] Waking PC ($MAC)..."
wakeonlan "$MAC"
echo "[Flynn] Waiting for PC to come online..."
for i in $(seq 1 30); do
    ping -c1 -W1 "$PC_IP" &>/dev/null && echo "[Flynn] PC online!" && break
    sleep 2
done
WAKE
chmod +x /usr/local/bin/flynn-wake

# Schedule: auto-wake PC at 7:00 AM every weekday
echo "0 7 * * 1-5 root /usr/local/bin/flynn-wake" >> /etc/crontab

# ── 6. agd-server (ANTIGRAVITY sync daemon) ───────────────────────────────────
echo "[6/6] Installing ANTIGRAVITY sync daemon..."
cat > /usr/local/bin/agd-server << 'AGD'
#!/usr/bin/env python3
"""
ANTIGRAVITY Daemon — sync hub for Flynn OS ↔ macOS ↔ Pi
Port 7777 (WebSocket + REST)
"""
import asyncio, json, datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading

STATE = {
    "timer_start": None,
    "focus_mode": False,
    "clipboard": "",
    "active_app": "terminal",
    "study_context": {}
}

class AGDHandler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass  # quiet

    def do_GET(self):
        if self.path == "/state":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(STATE).encode())
        elif self.path == "/wake":
            import subprocess
            subprocess.run(["wakeonlan", "$PC_MAC"])
            self.send_response(200); self.end_headers()
            self.wfile.write(b"waking PC...")
        else:
            self.send_response(404); self.end_headers()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length) or b"{}")
        if self.path == "/state":
            STATE.update(body)
        elif self.path == "/focus":
            STATE["focus_mode"] = body.get("enabled", False)
        elif self.path == "/clipboard":
            STATE["clipboard"] = body.get("text", "")
        self.send_response(200); self.end_headers()
        self.wfile.write(json.dumps({"ok": True}).encode())

if __name__ == "__main__":
    print("[agd] ANTIGRAVITY sync daemon starting on :7777")
    server = HTTPServer(("0.0.0.0", 7777), AGDHandler)
    server.serve_forever()
AGD
chmod +x /usr/local/bin/agd-server

# Autostart agd-server
cat > /etc/systemd/system/agd.service << EOF
[Unit]
Description=ANTIGRAVITY Sync Daemon
After=network.target

[Service]
ExecStart=/usr/local/bin/agd-server
Restart=always
User=pi

[Install]
WantedBy=multi-user.target
EOF
systemctl enable agd
systemctl start agd

echo ""
echo "✓ PXE server ready"
echo "✓ Wake-on-LAN configured"
echo "✓ agd-server running on :7777"
echo ""
echo "Next: copy Flynn OS kernel to /srv/tftp/flynnos/"
echo "      copy rootfs to /srv/nfs/flynnos/"
echo "      Set PC_MAC and PC_IP at top of this script"
