# Flynn OS Linux

[![Build Arch ISO](https://github.com/JoshuaForster02/antigravity-linux/actions/workflows/build-arch-iso.yml/badge.svg)](https://github.com/JoshuaForster02/antigravity-linux/actions/workflows/build-arch-iso.yml)

> A TRON-universe operating environment built on Arch Linux — not just a Linux desktop with TRON colors, but a genuinely different visual paradigm.

```
  ███████╗██╗  ██╗   ██╗███╗   ██╗███╗   ██╗     ██████╗ ███████╗
  ██╔════╝██║  ╚██╗ ██╔╝████╗  ██║████╗  ██║    ██╔═══██╗██╔════╝
  █████╗  ██║   ╚████╔╝ ██╔██╗ ██║██╔██╗ ██║    ██║   ██║███████╗
  ╚═╝     ╚══════╝╚═╝   ╚═╝  ╚═══╝╚═╝  ╚═══╝    ╚═════╝ ╚══════╝
                 OS  ·  linux-zen  ·  The Grid  ·  v4.0
```

## Quick Start

```bash
cd archiso
bash build-local.sh    # Docker Desktop required
# → output/flynnos-YYYY.MM-x86_64.iso
```

Login: **root** / **flynn** — Sway (Wayland) starts automatically on tty1.

### Test in UTM (Apple Silicon)

1. UTM → New → Emulate → Linux → x86_64
2. RAM 4GB, 4 CPU cores, Display: virtio-gpu
3. Boot ISO → Flynn OS loads directly into Wayland

### Install to disk (from live session)

```bash
bash /usr/local/bin/flynn-install
# Dual-boot with Windows is detected automatically
```

## Architecture

```
macOS ANTIGRAVITY App  ◄─── REST / MQTT ───►  Flynn OS Linux (PC)
        ▲                                              ▲
        └──────────────── Pi Agent ────────────────────┘

Flynn OS Desktop Stack:
  Sway (Wayland WM)
    └─ ANTIGRAVITY Background Daemon  ← live animated TRON grid
    └─ Waybar TRON Control Panel      ← bottom bar with glow + animations
    └─ Picom Compositor               ← cyan glow shadows, rounded corners
    └─ foot terminal + AGD palette    ← ⌘K command palette
    └─ Flynn Daemon :7777             ← REST API for macOS app
```

## Roadmap

| Phase | Status | Inhalt |
|-------|--------|--------|
| 1 Foundation       | ✅ | Arch ISO · linux-zen · BIOS/UEFI · Sway Wayland |
| 2 Boot Experience  | ✅ | Plymouth Spinner · Boot-Chime · Quiet Boot |
| 3 TRON Visual Core | ✅ | Live Grid Background · Picom Glow · Waybar Control Panel · Cyan Borders |
| 4 Core Apps        | ✅ | foot · GTK4 TRON · Steam/Gaming · MangoHud · WebKit Browser |
| 5 ANTIGRAVITY Shell| 🔨 | AGD Layer Shell · ⌘K Palette · Focus Mode · Flow Timer |
| 6 FaceID + Health  | 🔨 | Howdy FaceID · Health Timer · Ambient Sound · Sunshine Streaming |
| 7 TRON UX Polish   | 📋 | App-launch animations · Window materialisation effect · TRON cursor |
| 8 Installer        | 📋 | Calamares GUI installer · OTA updates · Hardware QA |
| 9 The Grid Vision  | 📋 | Full ANTIGRAVITY shell replaces Sway tiling · Program-metaphor app model |

**Legend:** ✅ Done · 🔨 In Progress · 📋 Planned

## What Phase 9 (The Grid) looks like

Instead of a traditional tiling desktop:
- The **ANTIGRAVITY daemon IS the desktop** — no taskbar, no Sway tiles
- Apps open as "Programs" that materialise onto the grid with a light-trail animation
- Workspace switching = traversing grid sectors (animated camera move)
- System stats are HUD overlays, not a taskbar
- Everything lives inside the TRON universe metaphor

## Current Desktop Stack

| Component | What it does |
|-----------|-------------|
| `flynn-bg-daemon` | Animated TRON grid background — data packets, node pulses, 20fps via Cairo+GTK4 layer shell |
| `waybar` | TRON Control Panel — pulsing border, segment-display clock, glowing modules |
| `picom` | Cyan glow shadows on all windows, rounded corners, smooth fade animations |
| `antigravity.py` | Layer shell HUD — flow timer, ⌘K command palette, focus mode |
| `sway` | Wayland WM — floating terminal, workspace rules, TRON border colors |
| `flynn-daemon` | REST API :7777 for macOS ANTIGRAVITY app |

## Key Bindings

| Key | Action |
|-----|--------|
| `Super+Return` | Open terminal |
| `Super+D` | TRON launcher (Rofi) |
| `Super+Space` | ANTIGRAVITY command palette |
| `Super+Q` | Close window |
| `Super+F` | Fullscreen |
| `Super+G` | Toggle GameMode |
| `Super+N` | Notion browser |
| `Super+A` | Anki browser |
| `Super+F1` | Health status |
| `Super+Shift+A` | Ambient sound toggle |
| `Super+Shift+S` | Sunshine streaming status |

## Flynn Daemon API (:7777)

| Endpoint | Description |
|----------|-------------|
| `GET /api/status` | System stats |
| `POST /api/gamemode` | Toggle GameMode |
| `POST /api/launch/game` | Launch Steam game |
| `GET /api/config` | Read config |

Config: `/etc/flynnos/defaults.conf`

## ANTIGRAVITY Ecosystem

- **[antigravity-app](https://github.com/JoshuaForster02/antigravity-app)** — macOS menu-bar workspace agent
- **[antigravity-linux](https://github.com/JoshuaForster02/antigravity-linux)** — this repo (The Grid OS)
- **[antigravity-kernel](https://github.com/JoshuaForster02/antigravity-kernel)** — bare-metal kernel experiments

## License

MIT — Flynn OS Project
