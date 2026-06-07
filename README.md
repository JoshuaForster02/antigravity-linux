# Flynn OS Linux

[![Build Arch ISO](https://github.com/JoshuaForster02/antigravity-linux/actions/workflows/build-arch-iso.yml/badge.svg)](https://github.com/JoshuaForster02/antigravity-linux/actions/workflows/build-arch-iso.yml)

> TRON-inspired Linux OS auf **Arch Linux** · Openbox Desktop · PipeWire · Steam/Gaming · Flynn REST API

```
  ███████╗██╗  ██╗   ██╗███╗   ██╗███╗   ██╗
  ██╔════╝██║  ╚██╗ ██╔╝████╗  ██║████╗  ██║
  █████╗  ██║   ╚████╔╝ ██╔██╗ ██║██╔██╗ ██║
  ██╔══╝  ██║    ╚██╔╝  ██║╚██╗██║██║╚██╗██║
  ██║     ███████╗██║   ██║ ╚████║██║ ╚████║
  ╚═╝     ╚══════╝╚═╝   ╚═╝  ╚═══╝╚═╝  ╚═══╝  OS · v3.0
```

## Quick Start

### ISO bauen (empfohlen — Arch Linux Live)

```bash
cd archiso
bash build-arch.sh          # braucht Docker Desktop
# → output/flynnos-YYYY.MM-x86_64.iso
```

### QEMU testen

```bash
qemu-system-x86_64 -cdrom archiso/output/flynnos-*.iso \
  -m 4G -smp 4 -vga virtio -boot d \
  -device usb-tablet -display cocoa
```

Login: **root** / **flynn** — GUI startet automatisch auf tty1.

### Auf Festplatte installieren (Live-Session)

```bash
bash /opt/flynn/install/install-to-disk.sh
# Dual-Boot mit Windows wird erkannt
```

### GitHub Actions

Jeder Push auf `main`/`dev` (Pfad `archiso/**`) baut die ISO automatisch.
Download: **Actions → Build Flynn OS Arch ISO → Artifacts**

## Roadmap (Linux)

| Phase | Status | Inhalt |
|-------|--------|--------|
| 1 Foundation | ✅ | Arch ISO · linux-zen · BIOS/UEFI · Openbox Desktop |
| 2 Boot Experience | ✅ | Plymouth TRON · Boot-Chime · Quiet Boot |
| 3 Compositor | 🔨 | wlroots Wayland · Glow-Shader (Post-Install) |
| 4 Core Apps | ✅ | foot · GTK4 TRON · Steam · Thunar |
| 5 ANTIGRAVITY | 🔨 | Floating Panels · ⌘K Palette (Wayland) |
| 6 Polish | 🔨 | Calamares GUI · OTA · Hardware QA |

## Was die ISO enthält

- **Kernel:** linux-zen + AMD/NVIDIA Mesa/Vulkan
- **Desktop:** Openbox + picom + tint2 + dunst + rofi (TRON Theme)
- **Audio:** PipeWire + Boot-Chime
- **Boot:** Plymouth Grid-Animation · syslinux + systemd-boot
- **Bluetooth:** bluez + blueman
- **Gaming:** Steam · GameMode · MangoHud
- **Daemon:** REST API auf Port **7777** (systemd: `flynn-daemon.service`)
- **Install:** `install-to-disk.sh` mit GRUB + mkinitcpio für Arch

## Flynn UI Shell

| Command | Funktion |
|---------|----------|
| `status` | CPU/RAM/Disk Dashboard |
| `net` | Netzwerk + Ping |
| `daemon` | Daemon-Status :7777 |
| `install` | Disk-Installer starten |
| `sh` | Shell |

## Flynn Daemon API (:7777)

| Endpoint | Beschreibung |
|----------|--------------|
| `GET /api/status` | System-Stats |
| `POST /api/gamemode` | GameMode toggle |
| `POST /api/launch/game` | Steam-Spiel starten |
| `GET /api/config` | Config lesen |

Config: `/etc/flynn/daemon.conf`

## ANTIGRAVITY Ecosystem

```
macOS Antigravity App  ◄── REST/MQTT ──►  Flynn OS Linux (PC)
        ▲                                        ▲
        └──────────── Pi Agent ──────────────────┘
```

- **[antigravity-app](https://github.com/JoshuaForster02/antigravity-app)** — macOS Workspace
- **[antigravity-kernel](https://github.com/JoshuaForster02/antigravity-kernel)** — Bare-Metal Kernel
- **antigravity-linux** — dieses Repo

## Legacy Build (Alpine phase1)

Der ältere Alpine-ISO-Pfad liegt in `phase1/` — nur noch für Experimente.
**Produktion = `archiso/`**

```bash
cd phase1 && bash build.sh   # Legacy Alpine ISO
```

## Lizenz

MIT — Flynn OS Project
