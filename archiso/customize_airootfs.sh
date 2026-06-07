#!/usr/bin/env bash
# Flynn OS — archiso customize hook
# Runs inside the chroot during ISO build.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

echo "╔══════════════════════════════════════════════════╗"
echo "║  Flynn OS Linux 3.0 — archiso customize hook    ║"
echo "╚══════════════════════════════════════════════════╝"

# ── Root password ─────────────────────────────────────────────────────────────
echo "root:flynn" | chpasswd
echo "  ✓ root password: flynn"

# ── Locale + timezone ─────────────────────────────────────────────────────────
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sed -i 's/#de_DE.UTF-8/de_DE.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
echo "  ✓ locale + timezone"

# ── Hostname ──────────────────────────────────────────────────────────────────
echo "flynnos" > /etc/hostname
cat > /etc/hosts << 'HOSTS'
127.0.0.1   localhost
::1         localhost
127.0.1.1   flynnos.local flynnos
HOSTS
echo "  ✓ hostname: flynnos"

# ── Auto-login root on tty1 (text shell → user types startx for GUI) ──────────
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << 'AUTOLOGIN'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
Type=idle
AUTOLOGIN
echo "  ✓ autologin root on tty1"

# ── Shell profile: show Flynn banner + hint ───────────────────────────────────
cat > /root/.bash_profile << 'PROFILE'
#!/bin/bash
export HOME=/root
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export TERM=xterm-256color
export HISTSIZE=1000

# Start Flynn UI shell
exec /usr/local/bin/flynn-ui
PROFILE

# ── .xinitrc: `startx` launches TRON Openbox session ─────────────────────────
cat > /root/.xinitrc << 'XINITRC'
#!/bin/sh
export DISPLAY=:0
xsetroot -solid "#000810"
[ -f /root/.Xresources ] && xrdb -merge /root/.Xresources
# TRON wallpaper (Python)
python3 /usr/local/bin/flynn-draw-bg 2>/dev/null &
# Compositor (xrender = works in VMs)
picom --backend xrender --vsync 2>/dev/null &
# Flynn daemon status bar (tint2)
tint2 -c /root/.config/tint2/tint2rc 2>/dev/null &
# Dunst notifications
dunst -config /root/.config/dunst/dunstrc 2>/dev/null &
# Open Flynn terminal on start
sleep 0.3
xterm -bg "#000810" -fg "#00e5ff" -fa "JetBrains Mono" -fs 11 \
      -title "Flynn OS" -geometry 120x35+40+60 \
      -e /usr/local/bin/flynn-ui &
# Openbox WM (last — becomes the session process)
exec openbox --config-file /root/.config/openbox/rc.xml
XINITRC
chmod +x /root/.xinitrc

# ── Xresources: TRON xterm colors ─────────────────────────────────────────────
cat > /root/.Xresources << 'XRES'
XTerm*background:           #000810
XTerm*foreground:           #00e5ff
XTerm*cursorColor:          #00e5ff
XTerm*selectBackground:     #004455
XTerm*faceName:             JetBrains Mono
XTerm*faceSize:             11
XTerm*scrollBar:            false
XTerm*borderWidth:          0
XTerm*internalBorder:       8
XTerm*saveLines:            10000
! TRON 16-color palette
XTerm*color0:   #000810
XTerm*color1:   #ff3366
XTerm*color2:   #00ff9f
XTerm*color3:   #ffcc00
XTerm*color4:   #0088ff
XTerm*color5:   #cc00ff
XTerm*color6:   #00e5ff
XTerm*color7:   #c0d8e0
XTerm*color8:   #002030
XTerm*color9:   #ff6688
XTerm*color10:  #44ffcc
XTerm*color11:  #ffdd44
XTerm*color12:  #44aaff
XTerm*color13:  #dd44ff
XTerm*color14:  #44eeff
XTerm*color15:  #ffffff
XRES

# ── GTK theme ─────────────────────────────────────────────────────────────────
mkdir -p /root/.config/gtk-3.0 /root/.config/gtk-4.0 /root/.icons
cat > /root/.config/gtk-3.0/settings.ini << 'GTK'
[Settings]
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Adwaita
gtk-font-name=JetBrains Mono 11
gtk-application-prefer-dark-theme=1
GTK
cp /root/.config/gtk-3.0/settings.ini /root/.config/gtk-4.0/settings.ini
echo "  ✓ GTK dark theme"

# ── tint2 panel config (TRON style) ───────────────────────────────────────────
mkdir -p /root/.config/tint2
cat > /root/.config/tint2/tint2rc << 'TINT2'
panel_monitor = all
panel_position = bottom center horizontal
panel_size = 100% 28
panel_margin = 0 0
panel_padding = 4 0 4
panel_background_id = 1
font_shadow = 0
panel_items = TSC
panel_clock = 1
time1_format = %H:%M
time2_format = %Y-%m-%d
time1_font = JetBrains Mono Bold 10
time2_font = JetBrains Mono 9
clock_font_color = #00e5ff 100
taskbar_mode = single_desktop
task_text = 1
task_active_background_id = 2
task_background_id = 1
task_font = JetBrains Mono 10
task_font_color = #80c8d8 100
task_active_font_color = #00e5ff 100
systray = 1
systray_padding = 4 4 4
#---------------------------------------------
# BACKGROUNDS
#---------------------------------------------
rounded = 0
border_width = 0
background_color = #000810 95
border_color = #00e5ff 0

rounded = 0
border_width = 1
background_color = #004455 80
border_color = #00e5ff 60
TINT2

# ── Dunst notification config ──────────────────────────────────────────────────
mkdir -p /root/.config/dunst
cat > /root/.config/dunst/dunstrc << 'DUNST'
[global]
font = JetBrains Mono 10
markup = full
format = "<b>%s</b>\n%b"
sort = no
indicate_hidden = yes
alignment = left
bounce_freq = 0
show_age_threshold = 60
word_wrap = yes
ignore_newline = no
geometry = "360x5-12+36"
shrink = no
transparency = 10
idle_threshold = 120
monitor = 0
follow = none
sticky_history = yes
history_length = 20
show_indicators = no
line_height = 0
separator_height = 1
padding = 8
horizontal_padding = 12
frame_width = 1
frame_color = "#00e5ff"
separator_color = "#004455"
startup_notification = false
browser = /usr/bin/xdg-open
[urgency_low]
background = "#000810"
foreground = "#004455"
timeout = 3
[urgency_normal]
background = "#000810"
foreground = "#00e5ff"
frame_color = "#00e5ff"
timeout = 6
[urgency_critical]
background = "#200010"
foreground = "#ff3366"
frame_color = "#ff3366"
timeout = 0
DUNST
echo "  ✓ tint2 + dunst TRON config"

# ── Openbox config ─────────────────────────────────────────────────────────────
mkdir -p /root/.config/openbox
cat > /root/.config/openbox/rc.xml << 'OBRC'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <theme>
    <name>Flynn</name>
    <titleLayout>NLIMC</titleLayout>
    <keepBorder>yes</keepBorder>
    <animateIconify>no</animateIconify>
    <font place="ActiveWindow"><name>JetBrains Mono Bold</name><size>10</size></font>
    <font place="InactiveWindow"><name>JetBrains Mono</name><size>10</size></font>
  </theme>
  <desktops><number>4</number><firstdesk>1</firstdesk></desktops>
  <resize><drawContents>yes</drawContents></resize>
  <mouse>
    <dragThreshold>1</dragThreshold>
    <doubleClickTime>200</doubleClickTime>
    <context name="Frame">
      <mousebind button="A-Left" action="Press"><action name="Focus"/><action name="Raise"/></mousebind>
      <mousebind button="A-Left" action="Drag"><action name="Move"/></mousebind>
      <mousebind button="A-Right" action="Drag"><action name="Resize"/></mousebind>
    </context>
    <context name="Titlebar">
      <mousebind button="Left" action="Press"><action name="Focus"/><action name="Raise"/></mousebind>
      <mousebind button="Left" action="Drag"><action name="Move"/></mousebind>
      <mousebind button="Left" action="DoubleClick"><action name="ToggleMaximizeFull"/></mousebind>
    </context>
    <context name="Desktop">
      <mousebind button="Right" action="Press"><action name="ShowMenu"><menu>root-menu</menu></action></mousebind>
    </context>
  </mouse>
  <keyboard>
    <keybind key="Super_L"><action name="ShowMenu"><menu>root-menu</menu></action></keybind>
    <keybind key="Super-Return"><action name="Execute"><command>xterm -bg "#000810" -fg "#00e5ff" -fa "JetBrains Mono" -fs 11 -e /usr/local/bin/flynn-ui</command></action></keybind>
    <keybind key="Super-f"><action name="ToggleMaximizeFull"/></keybind>
    <keybind key="Super-q"><action name="Close"/></keybind>
    <keybind key="Super-h"><action name="Execute"><command>/usr/local/bin/game-mode-switch.sh study</command></action></keybind>
    <keybind key="Super-g"><action name="Execute"><command>/usr/local/bin/game-mode-switch.sh game</command></action></keybind>
    <keybind key="Super-Tab"><action name="NextWindow"><dialog>no</dialog></action></keybind>
    <keybind key="A-F4"><action name="Close"/></keybind>
    <keybind key="Super-Left"><action name="MoveResizeTo"><x>0</x><y>0</y><width>50%</width><height>100%</height></action></keybind>
    <keybind key="Super-Right"><action name="MoveResizeTo"><x>50%</x><y>0</y><width>50%</width><height>100%</height></action></keybind>
  </keyboard>
  <menu>
    <file>/root/.config/openbox/menu.xml</file>
    <hideDelay>200</hideDelay>
    <middle>no</middle>
    <submenuShowDelay>100</submenuShowDelay>
  </menu>
</openbox_config>
OBRC

cat > /root/.config/openbox/menu.xml << 'OBMENU'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu">
  <menu id="root-menu" label="FLYNN OS">
    <item label="[ Terminal ]"><action name="Execute"><command>xterm -bg "#000810" -fg "#00e5ff" -fa "JetBrains Mono" -fs 11 -e /usr/local/bin/flynn-ui</command></action></item>
    <item label="[ File Manager ]"><action name="Execute"><command>thunar</command></action></item>
    <item label="[ Steam ]"><action name="Execute"><command>steam</command></action></item>
    <separator/>
    <item label="[ Game Mode ON ]"><action name="Execute"><command>/usr/local/bin/game-mode-switch.sh game</command></action></item>
    <item label="[ Study Mode ON ]"><action name="Execute"><command>/usr/local/bin/game-mode-switch.sh study</command></action></item>
    <separator/>
    <item label="Flynn System Info"><action name="Execute"><command>xterm -e 'fastfetch; read'</command></action></item>
    <separator/>
    <item label="Reboot"><action name="Execute"><command>reboot</command></action></item>
    <item label="Shutdown"><action name="Execute"><command>shutdown -h now</command></action></item>
  </menu>
</openbox_menu>
OBMENU
echo "  ✓ Openbox config + TRON menu"

# ── Openbox TRON theme ─────────────────────────────────────────────────────────
mkdir -p /usr/share/themes/Flynn/openbox-3
cat > /usr/share/themes/Flynn/openbox-3/themerc << 'THEMERC'
border.width: 1
padding.width: 4
padding.height: 4
window.active.border.color: #00e5ff
window.inactive.border.color: #002030
window.active.title.bg: Flat Solid
window.active.title.bg.color: #000810
window.active.label.text.color: #00e5ff
window.active.label.bg: Flat Solid
window.active.label.bg.color: #000810
window.active.button.*.bg: Flat Solid
window.active.button.*.bg.color: #000810
window.active.button.*.image.color: #00e5ff
window.inactive.title.bg: Flat Solid
window.inactive.title.bg.color: #000810
window.inactive.label.text.color: #002a3a
window.inactive.label.bg: Flat Solid
window.inactive.label.bg.color: #000810
window.inactive.button.*.bg: Flat Solid
window.inactive.button.*.bg.color: #000810
window.inactive.button.*.image.color: #002a3a
menu.border.width: 1
menu.border.color: #00e5ff
menu.bg: Flat Solid
menu.bg.color: #000810
menu.title.bg: Flat Solid
menu.title.bg.color: #001520
menu.title.text.color: #00e5ff
menu.items.bg: Flat Solid
menu.items.bg.color: #000810
menu.items.text.color: #80c8d8
menu.items.active.bg: Flat Solid
menu.items.active.bg.color: #004455
menu.items.active.text.color: #00e5ff
osd.border.width: 1
osd.border.color: #00e5ff
osd.bg: Flat Solid
osd.bg.color: #000810
osd.label.text.color: #00e5ff
THEMERC
echo "  ✓ Flynn Openbox TRON theme"

# ── Services ──────────────────────────────────────────────────────────────────
systemctl enable NetworkManager
systemctl enable sshd
systemctl enable bluetooth.service  2>/dev/null || true
systemctl enable flynn-daemon.service 2>/dev/null || true
echo "  ✓ systemd services"

# ── Flynn daemon Python deps ───────────────────────────────────────────────────
pip install --break-system-packages --quiet \
    flask flask-cors paho-mqtt psutil requests wakeonlan 2>/dev/null || true
echo "  ✓ Flynn daemon Python deps"

# ── GameMode ──────────────────────────────────────────────────────────────────
usermod -a -G gamemode root 2>/dev/null || true
# game-mode-switch.sh available as /usr/local/bin/game-mode-switch.sh (from airootfs)
echo "  ✓ GameMode configured"

# ── Plymouth TRON boot animation ──────────────────────────────────────────────
if [ -f /usr/share/plymouth/themes/flynn/flynn.plymouth ]; then
    mkdir -p /etc/plymouth
    cat > /etc/plymouth/plymouthd.conf << 'PLY'
[Daemon]
Theme=flynn
ShowDelay=0
DeviceTimeout=8
PLY
    plymouth-set-default-theme -R flynn 2>/dev/null || true
    echo "  ✓ Plymouth TRON theme"
fi

# ── GRUB TRON theme ───────────────────────────────────────────────────────────
mkdir -p /usr/share/grub/themes/flynn
cat > /usr/share/grub/themes/flynn/theme.txt << 'GRUBTHEME'
desktop-color: "#000810"
title-text: ""
message-color: "#00e5ff"
message-bg-color: "#000810"
+ boot_menu {
    left   = 20%
    top    = 30%
    width  = 60%
    height = 35%
    item_color          = "#004455"
    selected_item_color = "#00e5ff"
    item_height         = 32
    item_padding        = 10
    item_spacing        = 6
    scrollbar           = true
    scrollbar_width     = 4
}
+ label {
    top = 12%; left = 25%; width = 50%; align = "center"
    text = "FLYNN OS  //  THE GRID"
    color = "#00e5ff"
    font = "DejaVu Sans Bold 20"
}
+ label {
    top = 19%; left = 25%; width = 50%; align = "center"
    text = "Arch Linux · linux-zen · ANTIGRAVITY"
    color = "#004455"
    font = "DejaVu Sans 11"
}
GRUBTHEME

cat > /etc/default/grub << 'GRUBCFG'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Flynn OS"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3"
GRUB_CMDLINE_LINUX=""
GRUB_THEME="/usr/share/grub/themes/flynn/theme.txt"
GRUB_GFXMODE="1920x1080,1280x720,auto"
GRUB_GFXPAYLOAD_LINUX="keep"
GRUB_DISABLE_OS_PROBER=false
GRUBCFG
echo "  ✓ GRUB TRON theme"

# ── MOTD ──────────────────────────────────────────────────────────────────────
cat > /etc/motd << 'MOTD'

  ███████╗██╗  ██╗   ██╗███╗   ██╗███╗   ██╗     ██████╗ ███████╗
  ██╔════╝██║  ╚██╗ ██╔╝████╗  ██║████╗  ██║    ██╔═══██╗██╔════╝
  █████╗  ██║   ╚████╔╝ ██╔██╗ ██║██╔██╗ ██║    ██║   ██║███████╗
  ╚═╝     ╚══════╝╚═╝   ╚═╝  ╚═══╝╚═╝  ╚═══╝    ╚═════╝ ╚══════╝

  Flynn OS Linux 3.0  |  Arch · linux-zen  |  The Grid

  Commands:  help    status    matrix    scan    wifi    services
  GUI:       startx                (launches Openbox + TRON desktop)
  Game Mode: Super+G               (inside X11)
  Install:   install               (dual-boot installer for PC)

MOTD
echo "  ✓ MOTD"

# ── Flynn version ─────────────────────────────────────────────────────────────
echo "Flynn OS Linux 3.0 (Arch) — $(date +%Y-%m-%d)" > /etc/flynnos-release

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   Flynn OS customize complete ✓                 ║"
echo "╚══════════════════════════════════════════════════╝"
