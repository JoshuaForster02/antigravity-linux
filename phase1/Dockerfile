# Flynn OS Linux — Phase 1 + Phase 2 Build
# ─────────────────────────────────────────────────────────────────────────────
# Strategy:
#   · Ubuntu 22.04 kernel  (no separate download)
#   · Alpine 3.19 mini-rootfs  (~3 MB)
#   · Flynn OS UI + daemon overlaid
#   · Phase 2: GRUB theme, boot chime (ALSA), TRON greeter
#   · GRUB BIOS + EFI bootable ISO via grub-mkrescue
#
# Build:  bash build.sh
# Manual: docker buildx build --platform linux/amd64 --load -t flynnos-p1 .
# ─────────────────────────────────────────────────────────────────────────────

FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# ── Host build tools ──────────────────────────────────────────────────────────
RUN apt-get update -qq && apt-get install -y -qq \
    linux-image-generic \
    grub-pc-bin \
    grub-efi-amd64-bin \
    grub-common \
    xorriso \
    mtools \
    squashfs-tools \
    dosfstools \
    wget \
    cpio \
    gzip \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# ── Alpine mini-rootfs ────────────────────────────────────────────────────────
RUN wget -q \
    "https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-3.19.1-x86_64.tar.gz" \
    -O alpine-rootfs.tar.gz && \
    mkdir -p rootfs && \
    tar -xzf alpine-rootfs.tar.gz -C rootfs && \
    rm alpine-rootfs.tar.gz

# ── Packages inside the Alpine rootfs ────────────────────────────────────────
RUN cp /etc/resolv.conf rootfs/etc/resolv.conf && \
    chroot rootfs /bin/sh -c " \
        apk update -q && \
        apk add --no-cache -q \
            bash busybox-extras coreutils \
            python3 py3-pip \
            iproute2 iputils nmap \
            ncurses nano vim \
            procps util-linux lsblk \
            alsa-utils alsa-lib \
            mpg123 \
            dropbear \
            iwd wpa_supplicant wireless-tools \
            openssh-client \
            htop tree file \
            curl wget \
            parted e2fsprogs dosfstools \
            rsync \
            tmux \
            xorg-server xf86-video-vesa xf86-video-fbdev \
            xf86-input-keyboard xf86-input-mouse xf86-input-evdev \
            openbox obconf \
            xterm \
            feh \
            xsetroot \
            picom \
            mesa-dri-gallium \
    " && \
    rm -f rootfs/etc/resolv.conf

# ── Flynn OS overlay (Phase 1) ────────────────────────────────────────────────
COPY rootfs-overlay/ rootfs/

# ── Phase 2: Boot experience ──────────────────────────────────────────────────
COPY phase2/plymouth/  rootfs/usr/share/plymouth/themes/flynn/
COPY phase2/sounds/    rootfs/etc/flynnos/sounds/
COPY phase2/greetd/flynn-greeter rootfs/usr/local/bin/

# ── Installers — available on the live ISO ────────────────────────────────────
COPY install/          rootfs/opt/flynn/install/

# ── Rootfs configuration ──────────────────────────────────────────────────────
RUN chmod +x rootfs/init \
             rootfs/usr/local/bin/flynn-ui \
             2>/dev/null || true && \
    chmod +x rootfs/usr/local/bin/flynn-greeter 2>/dev/null || true && \
    \
    # Hostname + hosts
    echo "flynnos"         > rootfs/etc/hostname && \
    echo "127.0.1.1 flynnos" >> rootfs/etc/hosts && \
    \
    # Create required dirs
    mkdir -p rootfs/root \
             rootfs/opt/flynn/daemon \
             rootfs/var/log \
             rootfs/usr/share/plymouth/themes/flynn \
             rootfs/etc/flynnos/sounds \
             rootfs/etc/profile.d && \
    \
    # Boot chime script — plays WAV on tty1 startup if ALSA available
    printf '#!/bin/sh\n# Play boot chime if ALSA is available\nif command -v aplay >/dev/null 2>&1; then\n    aplay -q /etc/flynnos/sounds/boot-chime.wav 2>/dev/null &\nfi\n' \
        > rootfs/etc/profile.d/flynn-chime.sh && \
    chmod +x rootfs/etc/profile.d/flynn-chime.sh && \
    \
    # Inittab — tty1 starts X11 (Flynn graphical session), tty2 = text fallback
    printf '::sysinit:/etc/init.d/rcS\n::once:/usr/local/bin/flynn-network-init\ntty1::respawn:/usr/local/bin/flynn-startx\ntty2::respawn:/usr/local/bin/flynn-ui\ntty3::respawn:/sbin/getty 38400 tty3\n::once:/usr/sbin/dropbear -R -p 22 2>/dev/null\n' \
        > rootfs/etc/inittab && \
    \
    # Dropbear SSH — generate host keys dir, allow root login
    mkdir -p rootfs/etc/dropbear && \
    printf 'DROPBEAR_OPTS="-R -p 22"\n' > rootfs/etc/conf.d/dropbear 2>/dev/null || true && \
    \
    # Root password = "flynn" (for SSH access in testing)
    chroot rootfs /bin/sh -c "echo 'root:flynn' | chpasswd" 2>/dev/null || \
    printf 'root:$6$flynn$4L7vB0Zr0n.LFY/5y0nBxKHsF3MqHiQK4X/UNGOovRVRJdqYoJGMk8UZlNlXkL6K1EO8gLtU3vR9XU9hWPAl1:18000:0:99999:7:::\n' \
        > rootfs/etc/shadow 2>/dev/null || true && \
    \
    # ALSA config — set card 0 as default
    printf 'pcm.!default { type hw; card 0 }\nctl.!default { type hw; card 0 }\n' \
        > rootfs/etc/asound.conf && \
    \
    rm -rf rootfs/var/cache/apk/*

# ── Flynn daemon (optional — Python REST API :7777) ───────────────────────────
COPY daemon/ rootfs/opt/flynn/daemon/
RUN chroot rootfs /bin/sh -c " \
        pip3 install --no-cache-dir \
            flask flask-cors paho-mqtt psutil requests 2>/dev/null \
    " 2>/dev/null || echo "[build] pip install optional — skipping"

# ── Build initramfs ───────────────────────────────────────────────────────────
RUN (cd rootfs && find . | cpio -H newc -o 2>/dev/null) | gzip -9 > /build/initrd.img && \
    echo "initrd: $(du -sh /build/initrd.img | cut -f1)"

# ── Grab Ubuntu kernel ────────────────────────────────────────────────────────
RUN KERNEL=$(ls /boot/vmlinuz-*-generic 2>/dev/null | sort -V | tail -1) && \
    [ -n "$KERNEL" ] || { echo "ERROR: no kernel found in /boot/"; ls /boot/; exit 1; } && \
    cp "$KERNEL" /build/vmlinuz && \
    echo "kernel: $(basename $KERNEL)  ($(du -sh /build/vmlinuz | cut -f1))"

# ── GRUB config ───────────────────────────────────────────────────────────────
COPY grub/grub-linux.cfg /staging-grub/grub.cfg

# ── Phase 2: GRUB TRON theme ─────────────────────────────────────────────────
COPY phase2/grub-theme/ /build/grub-theme/

# ── Assemble ISO staging tree ─────────────────────────────────────────────────
RUN mkdir -p /staging/boot/grub/fonts \
             /staging/boot/grub/themes/flynnos \
             /staging/EFI/BOOT \
             /output && \
    \
    # Kernel + initrd
    cp /build/vmlinuz    /staging/boot/vmlinuz && \
    cp /build/initrd.img /staging/boot/initrd.img && \
    \
    # GRUB config
    cp /staging-grub/grub.cfg /staging/boot/grub/grub.cfg && \
    \
    # GRUB unicode font (needed for gfxterm)
    cp /usr/share/grub/unicode.pf2 /staging/boot/grub/fonts/ 2>/dev/null || true && \
    \
    # TRON theme assets
    cp /build/grub-theme/theme.txt    /staging/boot/grub/themes/flynnos/ && \
    cp /build/grub-theme/background.png /staging/boot/grub/themes/flynnos/ 2>/dev/null || true

# ── Build ISO ─────────────────────────────────────────────────────────────────
# grub-mkrescue puts modules on the ISO filesystem → no 480KB core-image limit
RUN grub-mkrescue \
        -o /output/flynn-os.iso \
        /staging \
        --compress=no \
        2>&1 | tail -5 && \
    echo "" && \
    echo "╔══════════════════════════════════════════╗" && \
    echo "║   Flynn OS Linux ISO — BUILD COMPLETE   ║" && \
    printf "║   %-40s║\n" "$(du -sh /output/flynn-os.iso | cut -f1)  total" && \
    echo "╚══════════════════════════════════════════╝"

CMD ["bash", "-c", "ls -lh /output/flynn-os.iso"]
