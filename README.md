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

Login: **root** / **tron** — Sway (Wayland) starts automatically on tty1.

### Download ISO (CI)

GitHub Releases cap at 2 GB. Download: **Actions → latest run → Artifacts**.

### Test in UTM (Apple Silicon)

1. UTM → New → Emulate → Linux → x86_64
2. RAM 4GB, 4 CPU cores, Display: virtio-gpu
3. Boot ISO → Flynn OS loads directly into Wayland

### Post-install (live session)

```bash
flynn-setup          # Steam, Anki, Proton-GE, GPU tuning
flynn-install        # Install to disk (dual-boot)
```

## Architecture

```
macOS ANTIGRAVITY App  ◄─── REST / MQTT ───►  Flynn OS Linux (PC)
        ▲                                              ▲
        └──────────────── Pi Agent ────────────────────┘

Flynn OS Desktop Stack:
  Sway (Wayland WM)
    └─ flynn-bg-daemon     ← animated TRON grid (GTK layer shell)
    └─ Waybar + Dock       ← top HUD + floating dock (Nerd Font icons)
    └─ fuzzel              ← TRON app launcher
    └─ foot + AGD palette  ← Super+Space command palette
    └─ Flynn Daemon :7777  ← REST API for macOS app
```

## Roadmap

| Phase | Status | Inhalt |
|-------|--------|--------|
| 1 Foundation       | ✅ | Arch ISO · linux-zen · BIOS/UEFI · Sway Wayland |
| 2 Boot Experience  | ✅ | Plymouth TRON · Boot-Chime · Quiet Boot |
| 3 TRON Visual Core | ✅ | Live Grid · Waybar HUD · FlynnTron GTK · Cyan borders |
| 4 Core Apps        | ✅ | foot · fuzzel · Browser · flynn-setup (Steam/Anki) |
| 5 ANTIGRAVITY Shell| 🔨 | AGD Layer Shell · ⌘K Palette · Focus Mode |
| 6 FaceID + Health  | 🔨 | Howdy FaceID · Health Timer · Ambient · Sunshine |
| 7 TRON UX Polish   | 🔨 | Named workspaces · Power menu · Welcome OSD · Lock screen |
| 8 Installer        | 📋 | Calamares GUI · OTA updates · Hardware QA |
| 9 The Grid Vision  | 📋 | ANTIGRAVITY shell replaces tiling · Program metaphor |

**Legend:** ✅ Done · 🔨 In Progress · 📋 Planned

## Workspaces

| Key | Sector | Purpose |
|-----|--------|---------|
| Super+1 | GRID | Home terminal + dashboard |
| Super+2 | STUDY | Notion / Amboss |
| Super+3 | ANKI | Flashcards |
| Super+4 | GAME | Steam Big Picture |
| Super+5 | SYS | Tools / settings |

## Current Desktop Stack

| Component | What it does |
|-----------|-------------|
| `flynn-bg-daemon` | Animated TRON grid — data packets, node pulses, GTK4 layer shell |
| `waybar` | Top HUD — CPU/RAM/temp/battery, named workspace icons |
| `dock` | Floating bottom dock — macOS-style app launcher |
| `fuzzel` | TRON-styled app launcher (Super+D) |
| `flynn-power` | Power menu — lock, logout, reboot (Super+Escape) |
| `antigravity.py` | Layer shell HUD — flow timer, ⌘K command palette |
| `sway` | Wayland WM — workspace rules, TRON borders, floating Flynn UI |
| `flynn-daemon` | REST API :7777 for macOS ANTIGRAVITY app |

## Key Bindings

| Key | Action |
|-----|--------|
| `Super+Return` | Open terminal |
| `Super+D` | App launcher (Fuzzel) |
| `Super+Escape` | Power menu |
| `Super+Space` | ANTIGRAVITY command palette (AGD) |
| `Super+Shift+V` | Clipboard history |
| `Super+G` | Game / Study mode |
| `Super+N` / `Super+A` | Notion / Anki |
| `Super+?` | Help overlay |
| `Super+F1` | Health status |

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
