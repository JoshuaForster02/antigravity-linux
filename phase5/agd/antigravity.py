#!/usr/bin/env python3
"""
ANTIGRAVITY Daemon (agd) — Flynn OS Overlay Layer
The OS-level implementation of the ANTIGRAVITY workspace concept.

Features:
  • ⌘K (Super+Space) — global command palette
  • Focus Mode — dims all windows except active
  • Floating Panels — Notion, Amboss as overlay windows
  • Flow Timer — bottom status bar with session timer
  • Compositor IPC — talks to flynn-compositor via Unix socket

Runs as a Wayland client alongside the compositor.
"""

import gi, sys, os, json, socket, threading, time, subprocess
gi.require_version('Gtk',     '4.0')
gi.require_version('Gdk',     '4.0')
gi.require_version('GtkLayerShell', '0.1')

from gi.repository import Gtk, Gdk, GLib
try:
    from gi.repository import GtkLayerShell
    HAS_LAYER_SHELL = True
except ImportError:
    HAS_LAYER_SHELL = False
    print("[agd] gtk-layer-shell not available — statusbar disabled")

# ─── Compositor IPC ──────────────────────────────────────────────────────────

IPC_SOCK = os.path.join(
    os.environ.get('XDG_RUNTIME_DIR', '/run/user/1000'),
    'flynn-compositor.sock')

def ipc_connect():
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(IPC_SOCK)
        s.setblocking(False)
        return s
    except Exception:
        return None

def ipc_send(event: str, payload: str = ''):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(IPC_SOCK)
        msg = json.dumps({'event': event, 'payload': payload}) + '\n'
        s.send(msg.encode())
        s.close()
    except Exception as e:
        print(f"[agd] IPC error: {e}")

# ─── Flow Timer ──────────────────────────────────────────────────────────────

class FlowTimer:
    def __init__(self):
        self.start_time = time.time()
        self.running    = True

    def elapsed_str(self) -> str:
        secs = int(time.time() - self.start_time)
        h, m = secs // 3600, (secs % 3600) // 60
        s = secs % 60
        return f"{h:02d}:{m:02d}:{s:02d}" if h else f"{m:02d}:{s:02d}"

    def reset(self):
        self.start_time = time.time()

flow_timer = FlowTimer()

# ─── Status Bar (Wayland layer shell) ────────────────────────────────────────

class StatusBar(Gtk.ApplicationWindow):
    """Slim bottom status bar — always on top via wlr-layer-shell."""

    def __init__(self, app):
        super().__init__(application=app, title='Flynn Status Bar')
        self.set_decorated(False)

        if HAS_LAYER_SHELL:
            GtkLayerShell.init_for_window(self)
            GtkLayerShell.set_layer(self, GtkLayerShell.Layer.TOP)
            GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.BOTTOM, True)
            GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.LEFT,   True)
            GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.RIGHT,  True)
            GtkLayerShell.set_exclusive_zone(self, 28)

        self.set_default_size(-1, 28)
        self._build_ui()
        self._apply_css()

        # Update timer every second
        GLib.timeout_add(1000, self._tick)

    def _build_ui(self):
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        box.set_homogeneous(False)

        # Left: OS name
        left = Gtk.Label(label='FLYNN OS')
        left.add_css_class('bar-brand')
        left.set_margin_start(12)
        left.set_margin_end(20)

        # Center: workspace indicators
        self.ws_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        for i in range(1, 6):
            btn = Gtk.Button(label=str(i))
            btn.add_css_class('ws-btn')
            btn.connect('clicked', self._switch_workspace, i)
            self.ws_box.append(btn)

        # Right: timer + date + focus toggle
        right = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        right.set_halign(Gtk.Align.END)

        self.focus_btn = Gtk.ToggleButton(label='FOCUS')
        self.focus_btn.add_css_class('bar-btn')
        self.focus_btn.connect('toggled', self._toggle_focus)

        self.timer_lbl = Gtk.Label(label='00:00')
        self.timer_lbl.add_css_class('bar-timer')

        self.clock_lbl = Gtk.Label()
        self.clock_lbl.add_css_class('bar-clock')
        self._update_clock()

        right.append(self.focus_btn)
        right.append(self.timer_lbl)
        right.append(self.clock_lbl)
        right.set_margin_end(12)

        box.append(left)
        box.append(self.ws_box)
        spacer = Gtk.Label()
        spacer.set_hexpand(True)
        box.append(spacer)
        box.append(right)

        self.set_child(box)

    def _apply_css(self):
        css = Gtk.CssProvider()
        css.load_from_data(b"""
            window {
                background-color: alpha(#06091a, 0.92);
                border-top: 1px solid #1a3344;
            }
            .bar-brand {
                color: #22aacc;
                font-family: monospace;
                font-size: 11px;
                font-weight: bold;
                letter-spacing: 2px;
            }
            .bar-timer {
                color: #22aacc;
                font-family: monospace;
                font-size: 12px;
            }
            .bar-clock {
                color: #335566;
                font-family: monospace;
                font-size: 11px;
            }
            .bar-btn {
                background: transparent;
                color: #335566;
                border: 1px solid #1a3344;
                border-radius: 3px;
                padding: 2px 8px;
                font-size: 10px;
                font-family: monospace;
            }
            .bar-btn:checked {
                background: #0a2030;
                color: #22aacc;
                border-color: #22aacc;
            }
            .ws-btn {
                background: transparent;
                color: #1a3344;
                border: none;
                min-width: 24px;
                min-height: 24px;
                font-size: 10px;
                font-family: monospace;
            }
            .ws-btn:hover { color: #22aacc; }
        """)
        Gtk.StyleContext.add_provider_for_display(
            self.get_display(), css,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    def _tick(self):
        self.timer_lbl.set_label(flow_timer.elapsed_str())
        self._update_clock()
        return True

    def _update_clock(self):
        import datetime
        now = datetime.datetime.now()
        self.clock_lbl.set_label(now.strftime('%a %d %b  %H:%M'))

    def _toggle_focus(self, btn):
        if btn.get_active():
            ipc_send('mode_changed', 'focus')
        else:
            ipc_send('mode_changed', 'normal')

    def _switch_workspace(self, btn, n):
        ipc_send('workspace_switch', str(n))

# ─── Command Palette ─────────────────────────────────────────────────────────

PALETTE_COMMANDS = [
    {'label': 'Open Notion',       'icon': 'N', 'action': lambda: launch_panel('notion')},
    {'label': 'Open Amboss',       'icon': 'A', 'action': lambda: launch_panel('amboss')},
    {'label': 'Open Terminal',     'icon': '>_','action': lambda: launch('foot')},
    {'label': 'Focus Mode ON',     'icon': '◉', 'action': lambda: ipc_send('mode_changed', 'focus')},
    {'label': 'Focus Mode OFF',    'icon': '○', 'action': lambda: ipc_send('mode_changed', 'normal')},
    {'label': 'Game Mode',         'icon': '⬛','action': lambda: ipc_send('mode_changed', 'game')},
    {'label': 'Reset Flow Timer',  'icon': '⏱', 'action': flow_timer.reset},
    {'label': 'Overview',          'icon': '⊞', 'action': lambda: ipc_send('mode_changed', 'overview')},
    {'label': 'Open Anki',         'icon': '📚','action': lambda: launch('flatpak run net.ankiweb.Anki')},
    {'label': 'System Info',       'icon': '≡', 'action': lambda: launch('foot -e htop')},
    {'label': 'Flynn Daemon Status','icon':'⚡', 'action': lambda: launch('foot -e curl -s http://localhost:7777/api/status | python3 -m json.tool')},
]

def launch(cmd: str):
    subprocess.Popen(cmd.split(), env={**os.environ, 'WAYLAND_DISPLAY': os.environ.get('WAYLAND_DISPLAY', 'wayland-0')})

def launch_panel(name: str):
    urls = {
        'notion': 'https://notion.so',
        'amboss': 'https://amboss.com/us',
    }
    url = urls.get(name, 'https://example.com')
    launch(f'flynn-browser {url} --title {name.capitalize()}')

class CommandPalette(Gtk.Window):
    def __init__(self, app):
        super().__init__(title='Flynn Command Palette')
        self.set_decorated(False)
        self.set_modal(True)
        self.set_default_size(580, 400)
        self._query = ''
        self._filtered = list(PALETTE_COMMANDS)
        self._selected = 0
        self._build_ui()
        self._apply_css()

        ctrl = Gtk.EventControllerKey()
        ctrl.connect('key-pressed', self._on_key)
        self.add_controller(ctrl)

    def _build_ui(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        # Search field
        search_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        search_row.set_margin_top(12)
        search_row.set_margin_bottom(8)
        search_row.set_margin_start(16)
        search_row.set_margin_end(16)

        icon = Gtk.Label(label='⌘')
        icon.add_css_class('palette-icon')

        self.entry = Gtk.Entry()
        self.entry.set_placeholder_text('Search commands, open apps, ask AI...')
        self.entry.add_css_class('palette-entry')
        self.entry.set_hexpand(True)
        self.entry.connect('changed', self._on_search)
        self.entry.connect('activate', self._on_activate)

        search_row.append(icon)
        search_row.append(self.entry)

        sep = Gtk.Separator()

        # Results list
        self.list_box = Gtk.ListBox()
        self.list_box.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.list_box.connect('row-activated', self._on_row_activated)

        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_child(self.list_box)

        box.append(search_row)
        box.append(sep)
        box.append(scroll)
        self.set_child(box)

        self._populate()

    def _populate(self):
        while row := self.list_box.get_row_at_index(0):
            self.list_box.remove(row)

        for i, cmd in enumerate(self._filtered):
            row = Gtk.ListBoxRow()
            h = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
            h.set_margin_top(8)
            h.set_margin_bottom(8)
            h.set_margin_start(16)

            icon_lbl = Gtk.Label(label=cmd['icon'])
            icon_lbl.add_css_class('palette-cmd-icon')
            icon_lbl.set_size_request(28, 28)

            lbl = Gtk.Label(label=cmd['label'])
            lbl.add_css_class('palette-cmd-label')
            lbl.set_halign(Gtk.Align.START)

            h.append(icon_lbl)
            h.append(lbl)
            row.set_child(h)
            self.list_box.append(row)

        if self._filtered:
            first = self.list_box.get_row_at_index(0)
            self.list_box.select_row(first)

    def _on_search(self, entry):
        q = entry.get_text().lower()
        self._filtered = [c for c in PALETTE_COMMANDS
                          if q in c['label'].lower()] if q else list(PALETTE_COMMANDS)
        self._populate()

    def _on_activate(self, entry):
        row = self.list_box.get_selected_row()
        if row:
            idx = row.get_index()
            if 0 <= idx < len(self._filtered):
                self._filtered[idx]['action']()
                self.close()

    def _on_row_activated(self, lb, row):
        idx = row.get_index()
        if 0 <= idx < len(self._filtered):
            self._filtered[idx]['action']()
            self.close()

    def _on_key(self, ctrl, keyval, keycode, state):
        if keyval == Gdk.KEY_Escape:
            self.close()
            return True
        return False

    def _apply_css(self):
        css = Gtk.CssProvider()
        css.load_from_data(b"""
            window {
                background-color: #131929;
                border-radius: 12px;
                border: 1px solid #1a3344;
            }
            .palette-entry {
                background: transparent;
                border: none;
                color: #ddeeff;
                font-family: monospace;
                font-size: 15px;
            }
            .palette-entry:focus { box-shadow: none; }
            .palette-icon { color: #335566; font-size: 16px; }
            .palette-cmd-icon {
                color: #22aacc;
                font-size: 14px;
                background: #0a1a2a;
                border-radius: 6px;
            }
            .palette-cmd-label {
                color: #cce8f0;
                font-family: monospace;
                font-size: 13px;
            }
            row:selected { background: #1a2a3a; }
            row:hover    { background: #0f1a28; }
        """)
        Gtk.StyleContext.add_provider_for_display(
            self.get_display(), css,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

# ─── Main Application ─────────────────────────────────────────────────────────

class AGDApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id='os.flynnos.agd')
        self.status_bar = None
        self.palette    = None
        self.connect('activate', self.on_activate)

    def on_activate(self, app):
        self.status_bar = StatusBar(app)
        self.status_bar.present()

        # Listen to compositor IPC for palette toggle
        self._start_ipc_listener()

        print('[agd] ANTIGRAVITY daemon online')
        print(f'[agd] IPC socket: {IPC_SOCK}')

    def _start_ipc_listener(self):
        def listen():
            while True:
                sock = ipc_connect()
                if not sock:
                    time.sleep(2)
                    continue
                try:
                    buf = b''
                    while True:
                        try:
                            chunk = sock.recv(256)
                            if not chunk:
                                break
                            buf += chunk
                            while b'\n' in buf:
                                line, buf = buf.split(b'\n', 1)
                                msg = json.loads(line.decode())
                                GLib.idle_add(self._handle_ipc, msg)
                        except BlockingIOError:
                            time.sleep(0.05)
                except Exception:
                    time.sleep(1)

        t = threading.Thread(target=listen, daemon=True)
        t.start()

    def _handle_ipc(self, msg: dict):
        event = msg.get('event', '')
        if event == 'palette_toggle':
            if msg.get('payload') == 'open':
                self._show_palette()
            else:
                if self.palette:
                    self.palette.close()
                    self.palette = None
        elif event == 'mode_changed':
            pass  # update status bar indicator (future)
        return False

    def _show_palette(self):
        if self.palette:
            self.palette.close()
        self.palette = CommandPalette(self)
        self.palette.set_transient_for(self.status_bar)
        self.palette.present()
        self.palette.entry.grab_focus()

if __name__ == '__main__':
    app = AGDApp()
    app.run()
