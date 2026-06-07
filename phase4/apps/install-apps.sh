#!/bin/bash
# Flynn OS — Phase 4: Core Apps Installation
# Run inside Flynn OS (after Phase 1+2+3)

set -euo pipefail
echo "╔══════════════════════════════════════════════╗"
echo "║  Flynn OS — Phase 4: Core Apps             ║"
echo "╚══════════════════════════════════════════════╝"

# ── 1. Foot terminal emulator ─────────────────────────────────────────────────
echo "[1/6] Installing foot terminal..."
apt-get install -y -qq foot 2>/dev/null || \
    flatpak install -y flathub org.codeberg.dnkl.foot 2>/dev/null || \
    echo "foot: install manually from https://codeberg.org/dnkl/foot"

mkdir -p /home/flynn/.config/foot
cp "$(dirname "$0")/../config/foot.ini" /home/flynn/.config/foot/foot.ini
chown -R flynn:flynn /home/flynn/.config/foot

# ── 2. WebKit browser (for Notion, Amboss) ────────────────────────────────────
echo "[2/6] Installing WebKit browser..."
apt-get install -y -qq \
    libwebkit2gtk-4.1-dev \
    gir1.2-webkit-6.0 \
    python3-gi \
    python3-gi-cairo \
    gir1.2-gtk-4.0 \
    2>/dev/null || true

# Flynn browser launcher (WebKitGTK4 python wrapper)
cat > /usr/local/bin/flynn-browser <<'BROWSER'
#!/usr/bin/env python3
"""
Flynn OS Browser — WebKitGTK4 wrapper for Notion, Amboss, etc.
Usage: flynn-browser [URL] [--title TITLE]
"""
import sys, gi
gi.require_version('Gtk', '4.0')
gi.require_version('WebKit', '6.0')
from gi.repository import Gtk, WebKit, GLib

class FlynnBrowser(Gtk.ApplicationWindow):
    def __init__(self, app, url='https://notion.so', title='Flynn Browser'):
        super().__init__(application=app, title=title)
        self.set_default_size(1200, 800)

        # TRON styling
        css = Gtk.CssProvider()
        css.load_from_data(b"""
            window { background: #06091a; }
            headerbar { background: #0a0f1a; color: #22aacc;
                        border-bottom: 1px solid #1a3344; }
        """)
        Gtk.StyleContext.add_provider_for_display(
            self.get_display(), css,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        wv = WebKit.WebView()
        wv.load_uri(url)

        # Dark mode
        settings = wv.get_settings()
        settings.set_property('enable-developer-extras', True)
        wv.get_settings().set_property(
            'user-agent',
            'Mozilla/5.0 (X11; Linux x86_64) Flynn/1.0 WebKit/6.0')

        self.set_child(wv)

class FlynnBrowserApp(Gtk.Application):
    def __init__(self, url, title):
        super().__init__(application_id='os.flynnos.browser')
        self.url   = url
        self.title = title
        self.connect('activate', self.on_activate)

    def on_activate(self, app):
        win = FlynnBrowser(app, self.url, self.title)
        win.present()

if __name__ == '__main__':
    url   = sys.argv[1] if len(sys.argv) > 1 else 'https://notion.so'
    title = sys.argv[3] if len(sys.argv) > 3 and sys.argv[2] == '--title' else 'Flynn Browser'
    app   = FlynnBrowserApp(url, title)
    app.run()
BROWSER
chmod +x /usr/local/bin/flynn-browser

# ── 3. Anki ───────────────────────────────────────────────────────────────────
echo "[3/6] Installing Anki..."
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null
flatpak install -y flathub net.ankiweb.Anki 2>/dev/null || \
    apt-get install -y -qq anki 2>/dev/null || \
    echo "Anki: install from https://apps.ankiweb.net"

# ── 4. File manager (lf — terminal file manager, TRON-compatible) ─────────────
echo "[4/6] Installing lf file manager..."
if ! command -v lf &>/dev/null; then
    LF_VER="r32"
    wget -q "https://github.com/gokcehan/lf/releases/download/${LF_VER}/lf-linux-amd64.tar.gz" \
        -O /tmp/lf.tar.gz && \
    tar -xzf /tmp/lf.tar.gz -C /usr/local/bin/ && \
    rm /tmp/lf.tar.gz
fi

mkdir -p /home/flynn/.config/lf
cat > /home/flynn/.config/lf/lfrc <<'LF'
set icons true
set hidden true
set drawbox true
set preview true
set color256 true
map <delete> delete
map e $$EDITOR "$f"
LF

# ── 5. Image viewer (imv — Wayland native) ────────────────────────────────────
echo "[5/6] Installing imv image viewer..."
apt-get install -y -qq imv 2>/dev/null || true

# ── 6. Neovim with TRON colorscheme ──────────────────────────────────────────
echo "[6/6] Installing Neovim..."
apt-get install -y -qq neovim 2>/dev/null || true

mkdir -p /home/flynn/.config/nvim
cat > /home/flynn/.config/nvim/init.lua <<'VIM'
-- Flynn OS Neovim config — TRON theme
vim.opt.termguicolors = true
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.cursorline = true

-- TRON colorscheme (manual)
vim.cmd([[
  hi Normal       guibg=#06091a guifg=#aaddee
  hi Comment      guifg=#1a5577 gui=italic
  hi Keyword      guifg=#22aacc gui=bold
  hi String       guifg=#33cc88
  hi Number       guifg=#ee4477
  hi Function     guifg=#33ddff gui=bold
  hi Type         guifg=#ddaa22
  hi CursorLine   guibg=#0a1020
  hi LineNr       guifg=#1a4455
  hi CursorLineNr guifg=#22aacc
  hi Visual       guibg=#1a3344
  hi StatusLine   guibg=#0a1020 guifg=#22aacc
]])
VIM

chown -R flynn:flynn /home/flynn/.config

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  Phase 4 installed!                         ║"
echo "║  foot  · browser  · Anki  · lf  · nvim     ║"
echo "╚══════════════════════════════════════════════╝"
