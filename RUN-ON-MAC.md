# Flynn OS auf dem Mac testen (UTM)

## Option 1 — UTM (empfohlen, kostenlos)

UTM ist eine native macOS-App die QEMU-VMs mit GUI verwaltet.
Auf Apple Silicon läuft x86_64 via Rosetta-Beschleunigung.

### Schritte:
1. UTM installieren: https://mac.getutm.app  (kostenlos, kein Homebrew nötig)
2. ISO herunterladen: GitHub → Actions → letzter Build → Artifacts → `flynn-os-linux-*.iso`
3. In UTM: **New VM → Emulate → Other → Browse → ISO auswählen**
   - CPU: x86_64
   - RAM: 4096 MB
   - Display: VirtIO (beste Performance)
   - USB: USB 3.0 (für Maus)
4. VM starten → GRUB-Menü → Flynn OS booten

### Login:
```
user: root
pass: flynn
```

### GUI starten (nach Login):
```bash
startx
```

---

## Option 2 — QEMU direkt (wenn QEMU installiert)

```bash
qemu-system-x86_64 \
  -cdrom flynn-os-linux-*.iso \
  -m 4G -smp 4 \
  -vga std \
  -device usb-tablet \
  -boot d
```

---

## Option 3 — VirtualBox (Intel Mac)

1. VirtualBox installieren: https://virtualbox.org
2. Neue VM → Linux → Arch Linux (64-bit)
3. ISO einlegen → booten

---

## Auf dem Windows-PC installieren (Dual-Boot)

Nach dem Boot in der VM oder QEMU:
```bash
install   # Flynn OS Installer starten
```
Installiert neben Windows, GRUB wählt beim Start das OS.
