#!/bin/bash
# Flynn OS — Deploy Pi Agent to Raspberry Pi
# Run from Flynn OS or macOS terminal

CY='\e[1;36m' GN='\e[1;32m' RD='\e[0;31m' RST='\e[0m'

PI_IP="${FLYNN_PI_IP:-$(grep PI_IP /etc/flynnos/defaults.conf 2>/dev/null | cut -d= -f2 || echo '100.74.204.71')}"
PI_USER="${FLYNN_PI_USER:-pi}"

printf "${CY}╔══════════════════════════════════════════════════╗\n"
printf "║  Flynn OS — Pi Agent Deploy                      ║\n"
printf "║  Target: %-40s║\n" "$PI_USER@$PI_IP"
printf "╚══════════════════════════════════════════════════╝${RST}\n\n"

# Check connectivity
printf "${CY}[1/4] Verbindung prüfen...${RST}\n"
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$PI_USER@$PI_IP" true 2>/dev/null; then
    printf "${RD}  ✗ Kann Pi nicht erreichen: $PI_USER@$PI_IP${RST}\n"
    printf "  Prüfe:\n"
    printf "    · Pi läuft und ist im Netzwerk / Tailscale\n"
    printf "    · SSH key ist eingerichtet: ssh-copy-id $PI_USER@$PI_IP\n"
    printf "    · IP stimmt: /etc/flynnos/defaults.conf → PI_IP=...\n"
    exit 1
fi
printf "${GN}  ✓ Pi erreichbar${RST}\n\n"

# Create remote dir
printf "${CY}[2/4] Verzeichnisse anlegen...${RST}\n"
ssh "$PI_USER@$PI_IP" "mkdir -p ~/pi-control ~/pi-control/logs"
printf "${GN}  ✓ Verzeichnisse OK${RST}\n\n"

# Copy files
printf "${CY}[3/4] Dateien kopieren...${RST}\n"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
scp "$SCRIPT_DIR/pi_agent.py"  "$PI_USER@$PI_IP:~/pi-control/"
scp "$SCRIPT_DIR/setup-pi.sh"  "$PI_USER@$PI_IP:~/pi-control/"
printf "${GN}  ✓ Dateien übertragen${RST}\n\n"

# Run setup
printf "${CY}[4/4] Pi Agent einrichten...${RST}\n"
ssh "$PI_USER@$PI_IP" "bash ~/pi-control/setup-pi.sh"
printf "${GN}  ✓ Pi Agent läuft${RST}\n\n"

printf "${GN}Pi Bridge aktiv.${RST}\n"
printf "  Endpoints:  http://$PI_IP:8765/api/status\n"
printf "  Logs:       ssh $PI_USER@$PI_IP journalctl -u flynn-pi-agent -f\n"
