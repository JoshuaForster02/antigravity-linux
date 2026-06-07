# Flynn OS — Arch Linux ISO builder
# Uses official archlinux image + archiso
# Build: bash build-arch.sh
# Output: output/flynnos-YYYY.MM-x86_64.iso (~1.5–2.5 GB)

FROM --platform=linux/amd64 archlinux:latest

# ── Install build tools ───────────────────────────────────────────────────────
# Disable sig checking for the builder image only (no entropy for pacman-key
# during RUN). The actual Flynn OS ISO packages are still signature-verified
# by mkarchiso which runs at container start with full entropy available.
RUN sed -i 's/SigLevel.*/SigLevel = Never/' /etc/pacman.conf \
    && pacman -Sy --noconfirm \
         archiso grub efibootmgr mtools squashfs-tools dosfstools \
    && pacman -Scc --noconfirm \
    && sed -i 's/SigLevel.*/SigLevel    = Required DatabaseOptional/' /etc/pacman.conf

WORKDIR /build

# ── Copy Flynn OS profile ──────────────────────────────────────────────────────
COPY profiledef.sh       ./
COPY packages.x86_64     ./
COPY pacman.conf         ./
COPY customize_airootfs.sh airootfs/
COPY airootfs/           airootfs/

# ── Set permissions ────────────────────────────────────────────────────────────
RUN chmod +x airootfs/customize_airootfs.sh \
             airootfs/usr/local/bin/* \
             airootfs/root/.xinitrc \
             airootfs/root/.config/openbox/autostart \
    2>/dev/null || true

# ── Build ISO ─────────────────────────────────────────────────────────────────
# mkarchiso needs to run in a privileged container (loop devices)
# We set up the command here; actual run needs --privileged
RUN mkdir -p /output /work

CMD ["bash", "-c", "\
    echo '╔══════════════════════════════════════════════════════╗' && \
    echo '║   Flynn OS — Arch Linux ISO Build                    ║' && \
    echo '╚══════════════════════════════════════════════════════╝' && \
    echo '' && \
    echo '[1/3] Initializing pacman keyring...' && \
    pacman-key --init && \
    pacman-key --populate archlinux && \
    echo '[2/3] Building Flynn OS ISO (this takes ~20-40 min)...' && \
    mkarchiso -v -w /work -o /output /build && \
    echo '' && \
    echo '[3/3] Done!' && \
    echo '╔══════════════════════════════════════════════════════╗' && \
    echo '║   BUILD COMPLETE                                     ║' && \
    ls -lh /output/*.iso && \
    echo '╚══════════════════════════════════════════════════════╝' \
"]
