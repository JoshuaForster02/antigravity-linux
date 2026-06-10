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

# gtk4-layer-shell MUST be loaded before GTK initializes (PyGObject quirk)
import ctypes
for _lib in ("libgtk4-layer-shell.so.0", "libgtk4-layer-shell.so"):
    try:
        ctypes.CDLL(_lib)
        break
    except OSError:
        continue

import gi, sys, os, json, socket, threading, time, subprocess
gi.require_version('Gtk',     '4.0')
gi.require_version('Gdk',     '4.0')

from gi.repository import Gtk, Gdk, GLib
try:
    gi.require_version('Gtk4LayerShell', '1.0')
    from gi.repository import Gtk4LayerShell as GtkLayerShell
    HAS_LAYER_SHELL = True
except (ImportError, ValueError):
    HAS_LAYER_SHELL = False
    print("[agd] gtk4-layer-shell not available — statusbar disabled")

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

# ─── Command Palette — ENCOM OS Spotlight ────────────────────────────────────

PALETTE_COMMANDS = [
    # ── Apps ──
    {'cat':'APPS',   'label':'Terminal',          'icon':'▶', 'hint':'⌥T', 'desc':'Flynn UI Shell',        'action': lambda: launch('foot -e /usr/local/bin/flynn-ui')},
    {'cat':'APPS',   'label':'Notion',            'icon':'≡', 'hint':'⌥N', 'desc':'Open workspace',        'action': lambda: launch_url('https://notion.so', 'Notion')},
    {'cat':'APPS',   'label':'Anki',              'icon':'◈', 'hint':'⌥A', 'desc':'Flashcard review',      'action': lambda: launch_url('http://localhost:8765', 'Anki')},
    {'cat':'APPS',   'label':'Files',             'icon':'⊞', 'hint':'',  'desc':'Thunar file manager',   'action': lambda: launch('thunar')},
    {'cat':'APPS',   'label':'Steam',             'icon':'◉', 'hint':'',  'desc':'Gaming library',        'action': lambda: launch("bash -c 'command -v steam >/dev/null && steam -bigpicture || foot -e bash -c \"Run flynn-setup for Steam\"; read'")},
    # ── Study ──
    {'cat':'STUDY',  'label':'Focus Mode',        'icon':'◎', 'hint':'⌥F', 'desc':'Dims all but active',   'action': lambda: ipc_send('mode_changed', 'focus')},
    {'cat':'STUDY',  'label':'Focus OFF',         'icon':'○', 'hint':'',  'desc':'Restore normal mode',   'action': lambda: ipc_send('mode_changed', 'normal')},
    {'cat':'STUDY',  'label':'Reset Flow Timer',  'icon':'⏱', 'hint':'',  'desc':'Restart session clock', 'action': flow_timer.reset},
    {'cat':'STUDY',  'label':'Ambient Sound',     'icon':'♪', 'hint':'',  'desc':'Study loop on/off',     'action': lambda: launch('/usr/local/bin/flynn-ambient toggle')},
    {'cat':'STUDY',  'label':'Health Check',      'icon':'♡', 'hint':'F1','desc':'Break + stretch alert', 'action': lambda: launch('/usr/local/bin/flynn-health status')},
    {'cat':'STUDY',  'label':'Notion → Anki Sync','icon':'⇄', 'hint':'',  'desc':'Sync highlights→cards', 'action': lambda: launch('python3 /opt/flynn/notion_anki_sync.py')},
    # ── System ──
    {'cat':'SYSTEM', 'label':'System Info',       'icon':'⬡', 'hint':'',  'desc':'CPU / RAM / Disk',      'action': lambda: launch('foot -e fastfetch')},
    {'cat':'SYSTEM', 'label':'Network',           'icon':'⊛', 'hint':'',  'desc':'NetworkManager UI',     'action': lambda: launch('nm-connection-editor')},
    {'cat':'SYSTEM', 'label':'Game Mode ON',      'icon':'▶▶','hint':'⌥G', 'desc':'Boost CPU + close apps','action': lambda: launch('/usr/local/bin/game-mode-switch.sh game')},
    {'cat':'SYSTEM', 'label':'Study Mode ON',     'icon':'◑', 'hint':'⌥H', 'desc':'Quiet, focus layout',  'action': lambda: launch('/usr/local/bin/game-mode-switch.sh study')},
    {'cat':'SYSTEM', 'label':'Lock Screen',       'icon':'⊗', 'hint':'',  'desc':'Swaylock',              'action': lambda: launch('/usr/local/bin/flynn-lock')},
    {'cat':'SYSTEM', 'label':'Install to Disk',    'icon':'⬇', 'hint':'',  'desc':'Flynn disk installer',  'action': lambda: launch('foot -e /usr/local/bin/flynn-install')},
    {'cat':'SYSTEM', 'label':'OTA Update',        'icon':'↑', 'hint':'',  'desc':'Pull latest Flynn OS',  'action': lambda: launch('foot -e /usr/local/bin/flynn-update')},
    # ── Flynn ──
    {'cat':'FLYNN',  'label':'PC Status',         'icon':'⚡', 'hint':'',  'desc':'Flynn daemon :7777',    'action': lambda: launch("foot -e sh -c 'curl -s localhost:7777/api/status|python3 -m json.tool;read'")},
    {'cat':'FLYNN',  'label':'Stream Desktop',    'icon':'⟐', 'hint':'',  'desc':'Sunshine server',       'action': lambda: launch('/usr/local/bin/flynn-sunshine --start')},
    {'cat':'FLYNN',  'label':'Wake PC',           'icon':'◈', 'hint':'',  'desc':'Send Wake-on-LAN',      'action': lambda: launch('python3 /opt/flynn/pi-control/pi_agent.py wakepc')},
]

def launch(cmd: str):
    env = {**os.environ, 'WAYLAND_DISPLAY': os.environ.get('WAYLAND_DISPLAY', 'wayland-0')}
    subprocess.Popen(cmd, shell=True, env=env)

def launch_url(url: str, title: str):
    launch(f'/usr/local/bin/flynn-browser {url} --title {title}')

CSS_PALETTE = """
window.palette-win {
    background: rgba(0, 6, 16, 0.97);
    border:        1px solid rgba(0, 229, 255, 0.30);
    border-radius: 16px;
}

/* ── Search bar ─────────────────────────────────────────────────────────────  */
.p-search-row {
    padding: 16px 20px 12px;
    border-bottom: 1px solid rgba(0, 229, 255, 0.08);
}
.p-search-icon {
    font-size: 20px;
    color: rgba(0, 150, 180, 0.50);
    padding-right: 4px;
}
.p-entry {
    background:  transparent;
    border:      none;
    color:       #d0eef8;
    font-family: "JetBrains Mono", monospace;
    font-size:   18px;
    font-weight: 500;
    caret-color: #00e5ff;
}
.p-entry:focus { box-shadow: none; outline: none; }
.p-entry placeholder { color: rgba(0, 150, 180, 0.35); font-size: 16px; }

/* ── Category header ─────────────────────────────────────────────────────────  */
.p-cat {
    font-family:   "JetBrains Mono", monospace;
    font-size:     8px;
    font-weight:   700;
    letter-spacing: 2px;
    color:         rgba(0, 120, 150, 0.55);
    padding:       8px 20px 4px;
}

/* ── Result row ─────────────────────────────────────────────────────────────  */
row {
    border-radius: 6px;
    margin:        1px 8px;
    padding:       0;
}
row:selected, row:hover { background: rgba(0, 229, 255, 0.08); }
row:selected .p-label   { color: #00e5ff; }

.p-icon {
    font-size:     16px;
    color:         rgba(0, 180, 220, 0.75);
    min-width:     32px;
    padding-left:  12px;
    font-family:   "JetBrains Mono", monospace;
}
row:selected .p-icon { color: #00e5ff; }

.p-label {
    font-family:   "JetBrains Mono", monospace;
    font-size:     13px;
    font-weight:   600;
    color:         rgba(180, 220, 235, 0.90);
}
.p-desc {
    font-family: "JetBrains Mono", monospace;
    font-size:   10px;
    color:       rgba(0, 130, 160, 0.55);
    margin-top:  1px;
}
.p-hint {
    font-family:  "JetBrains Mono", monospace;
    font-size:    9px;
    color:        rgba(0, 130, 160, 0.40);
    padding-right: 14px;
    margin-left:  auto;
}

/* ── Footer ─────────────────────────────────────────────────────────────────  */
.p-footer {
    padding:       8px 20px;
    border-top:    1px solid rgba(0, 229, 255, 0.06);
    font-family:   "JetBrains Mono", monospace;
    font-size:     9px;
    color:         rgba(0, 100, 130, 0.40);
    letter-spacing: 1px;
}
"""

class CommandPalette(Gtk.Window):
    def __init__(self, app):
        super().__init__(title='Flynn Command Palette')
        self.set_decorated(False)
        self.set_modal(True)
        self.set_default_size(640, 480)
        self.set_resizable(False)
        self.add_css_class('palette-win')
        self._all = list(PALETTE_COMMANDS)
        self._filtered = self._all[:]

        self._load_css()
        self._build_ui()

        key = Gtk.EventControllerKey()
        key.connect('key-pressed', self._on_key)
        self.add_controller(key)
        GLib.idle_add(lambda: self.entry.grab_focus() or False)

    def _load_css(self):
        prov = Gtk.CssProvider()
        prov.load_from_data(CSS_PALETTE.encode("utf-8"))
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), prov,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 10)

    def _build_ui(self):
        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        # ── Search row
        srow = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        srow.add_css_class('p-search-row')

        icon = Gtk.Label(label='⌘')
        icon.add_css_class('p-search-icon')

        self.entry = Gtk.Entry()
        self.entry.set_placeholder_text('Befehl, App oder Suche...')
        self.entry.add_css_class('p-entry')
        self.entry.set_hexpand(True)
        self.entry.connect('changed', self._on_search)
        self.entry.connect('activate', self._on_activate)

        srow.append(icon)
        srow.append(self.entry)
        root.append(srow)

        # ── Results
        self.list_box = Gtk.ListBox()
        self.list_box.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.list_box.connect('row-activated', self._on_row_activated)

        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_child(self.list_box)
        root.append(scroll)

        # ── Footer hint
        footer = Gtk.Label(label='↑↓  navigate  ·  ⏎  execute  ·  Esc  close')
        footer.add_css_class('p-footer')
        footer.set_halign(Gtk.Align.START)
        root.append(footer)

        self.set_child(root)
        self._populate()

    def _make_row(self, cmd):
        row = Gtk.ListBoxRow()
        h = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        h.set_margin_top(7); h.set_margin_bottom(7)

        icon = Gtk.Label(label=cmd['icon'])
        icon.add_css_class('p-icon')

        texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        texts.set_hexpand(True)

        lbl = Gtk.Label(label=cmd['label'])
        lbl.add_css_class('p-label')
        lbl.set_halign(Gtk.Align.START)

        desc = Gtk.Label(label=cmd['desc'])
        desc.add_css_class('p-desc')
        desc.set_halign(Gtk.Align.START)

        texts.append(lbl)
        texts.append(desc)

        hint = Gtk.Label(label=cmd.get('hint', ''))
        hint.add_css_class('p-hint')

        h.append(icon)
        h.append(texts)
        h.append(hint)
        row.set_child(h)
        return row

    def _populate(self):
        while (r := self.list_box.get_row_at_index(0)):
            self.list_box.remove(r)

        prev_cat = None
        for cmd in self._filtered:
            if cmd['cat'] != prev_cat:
                lbl = Gtk.Label(label=cmd['cat'])
                lbl.add_css_class('p-cat')
                lbl.set_halign(Gtk.Align.START)
                header_row = Gtk.ListBoxRow()
                header_row.set_selectable(False)
                header_row.set_activatable(False)
                header_row.set_child(lbl)
                self.list_box.append(header_row)
                prev_cat = cmd['cat']
            self.list_box.append(self._make_row(cmd))

        first = self._first_selectable()
        if first:
            self.list_box.select_row(first)

    def _first_selectable(self):
        i = 0
        while (r := self.list_box.get_row_at_index(i)):
            if r.get_selectable():
                return r
            i += 1
        return None

    def _on_search(self, entry):
        q = entry.get_text().lower().strip()
        self._filtered = [c for c in self._all
                          if q in c['label'].lower() or q in c['desc'].lower()
                          ] if q else self._all[:]
        self._populate()

    def _on_activate(self, entry):
        row = self.list_box.get_selected_row()
        if row and row.get_selectable():
            idx = self._row_to_cmd_index(row)
            if idx is not None:
                self._filtered[idx]['action']()
                self.close()

    def _on_row_activated(self, lb, row):
        if not row.get_selectable():
            return
        idx = self._row_to_cmd_index(row)
        if idx is not None:
            self._filtered[idx]['action']()
            self.close()

    def _row_to_cmd_index(self, row):
        """Map a ListBoxRow to its index in _filtered (skipping category headers)."""
        cmd_idx = 0
        prev_cat = None
        i = 0
        while (r := self.list_box.get_row_at_index(i)):
            if not r.get_selectable():
                i += 1
                continue
            if r == row:
                return cmd_idx
            cmd_idx += 1
            i += 1
        return None

    def _on_key(self, ctrl, keyval, keycode, state):
        if keyval == Gdk.KEY_Escape:
            self.close()
            return True
        if keyval == Gdk.KEY_Down:
            self._move_selection(1)
            return True
        if keyval == Gdk.KEY_Up:
            self._move_selection(-1)
            return True
        return False

    def _move_selection(self, delta):
        row = self.list_box.get_selected_row()
        i = row.get_index() if row else -1
        while True:
            i += delta
            r = self.list_box.get_row_at_index(i)
            if r is None:
                break
            if r.get_selectable():
                self.list_box.select_row(r)
                break


AGD_SOCK = os.path.join(
    os.environ.get('XDG_RUNTIME_DIR', '/run/user/0'),
    'flynn-agd.sock')


def agd_send(event: str, payload: str = '') -> bool:
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(AGD_SOCK)
        s.sendall((json.dumps({'event': event, 'payload': payload}) + '\n').encode())
        s.close()
        return True
    except Exception:
        return False


class AGDApp(Gtk.Application):
  """ANTIGRAVITY overlay daemon — status bar + command palette."""

  def __init__(self):
      super().__init__(application_id='org.flynnos.agd')
      self.palette = None
      self.status_bar = None
      self._agd_server = None

  def do_activate(self):
      if self.status_bar is None:
          self.status_bar = StatusBar(self)
          self.status_bar.present()
      self._start_agd_socket()
      print('[agd] ANTIGRAVITY daemon online')
      print(f'[agd] Control socket: {AGD_SOCK}')

  def _start_agd_socket(self):
      if self._agd_server is not None:
          return
      try:
          if os.path.exists(AGD_SOCK):
              os.unlink(AGD_SOCK)
      except OSError:
          pass
      server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
      server.bind(AGD_SOCK)
      os.chmod(AGD_SOCK, 0o666)
      server.listen(4)
      server.setblocking(False)
      self._agd_server = server
      GLib.timeout_add(120, self._poll_agd_socket)

  def _poll_agd_socket(self):
      if not self._agd_server:
          return False
      try:
          conn, _ = self._agd_server.accept()
          data = conn.recv(4096).decode().strip()
          conn.close()
          for line in data.splitlines():
              if line:
                  self._handle_ipc(json.loads(line))
      except BlockingIOError:
          pass
      except Exception as exc:
          print(f'[agd] socket error: {exc}')
      return True

  def _handle_ipc(self, msg: dict):
      event = msg.get('event', '')
      if event == 'palette_toggle':
          if msg.get('payload') == 'close':
              if self.palette:
                  self.palette.close()
                  self.palette = None
          else:
              self._show_palette()
      elif event == 'mode_changed':
          active = msg.get('payload') == 'focus'
          if self.status_bar and hasattr(self.status_bar, 'focus_btn'):
              self.status_bar.focus_btn.set_active(active)
      return False

  def _show_palette(self):
      if self.palette:
          self.palette.close()
          self.palette = None
      self.palette = CommandPalette(self)
      self.palette.connect('close-request', self._on_palette_closed)
      self.palette.present()

  def _on_palette_closed(self, _win):
      self.palette = None
      return False


class PaletteApp(Gtk.Application):
  def do_activate(self):
      CommandPalette(self).present()


if __name__ == '__main__':
    if '--palette' in sys.argv:
        PaletteApp().run(sys.argv)
    else:
        AGDApp().run(sys.argv)
