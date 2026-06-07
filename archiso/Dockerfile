# Flynn OS — Arch Linux ISO builder
# ─────────────────────────────────────────────────────────────────────────────
# Strategy for Apple Silicon:
#  - SigLevel = Never in ALL sections before ANY pacman call
#  - pacman -Syy (force refresh) before installing
#  - pacman-key runs at CMD time (has entropy), not build time
# ─────────────────────────────────────────────────────────────────────────────

FROM --platform=linux/amd64 archlinux:latest

# ── Disable ALL signature checks for the build layer ─────────────────────────
RUN cat > /etc/pacman.conf << 'PACCONF'
[options]
HoldPkg      = pacman glibc
Architecture = auto
SigLevel     = Never
LocalFileSigLevel = Never

[core]
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch

[extra]
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch

[multilib]
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
PACCONF

# ── Force-refresh DB and install build tools ──────────────────────────────────
RUN pacman -Syy --noconfirm \
 && pacman -S --noconfirm --needed \
        archiso \
        grub \
        efibootmgr \
        mtools \
        squashfs-tools \
        dosfstools \
 && pacman -Scc --noconfirm

WORKDIR /build

# ── Copy Flynn OS profile ─────────────────────────────────────────────────────
COPY profiledef.sh          ./
COPY packages.x86_64        ./
COPY pacman.conf            ./pacman-iso.conf
COPY customize_airootfs.sh  airootfs/customize_airootfs.sh
COPY airootfs/              airootfs/

# ── Fix permissions ───────────────────────────────────────────────────────────
RUN find airootfs/ -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true; \
    find airootfs/usr/local/bin/ -type f -exec chmod +x {} \; 2>/dev/null || true

RUN mkdir -p /output /work

CMD ["bash", "-c", "set -e; \
  echo '╔══════════════════════════════════════════════════════╗'; \
  echo '║   Flynn OS — Arch Linux ISO Build  v3.0             ║'; \
  echo '╚══════════════════════════════════════════════════════╝'; \
  echo '[1/3] Initializing keyring (~30s)...'; \
  pacman-key --init && pacman-key --populate archlinux; \
  echo '[2/3] Building ISO (~20-40 min first run)...'; \
  mkarchiso -v -w /work -o /output /build; \
  echo '[3/3] Done!'; \
  ls -lh /output/*.iso"]
