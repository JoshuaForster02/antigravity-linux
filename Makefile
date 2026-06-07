# Flynn OS Linux — Master Makefile
# Usage: make help

ARCH        = x86_64
LINUX_VER   = 6.6.30
BR_VER      = 2024.02
OUTPUT_DIR  = output
ISO_NAME    = flynnos.iso

.PHONY: help setup buildroot kernel compositor packages iso pxe clean

help:
	@echo ""
	@echo "  Flynn OS Linux Build System"
	@echo "  ==========================="
	@echo "  make setup        — install build dependencies"
	@echo "  make buildroot    — build minimal rootfs"
	@echo "  make kernel       — build Linux kernel"
	@echo "  make compositor   — build TRON Wayland compositor"
	@echo "  make packages     — build/install Steam, apps"
	@echo "  make iso          — assemble bootable ISO"
	@echo "  make pxe          — create PXE boot package for Pi"
	@echo "  make run          — test in QEMU"
	@echo "  make clean        — remove build output"
	@echo ""

setup:
	@echo "Installing build dependencies..."
	sudo apt-get update && sudo apt-get install -y \
	    build-essential bc bison flex libelf-dev libssl-dev \
	    libncurses-dev cpio gzip wget curl xz-utils \
	    libwayland-dev libwlroots-dev libinput-dev libdrm-dev \
	    libgles2-mesa-dev libgbm-dev libxkbcommon-dev \
	    grub-pc-bin xorriso squashfs-tools \
	    qemu-system-x86 ovmf

buildroot: buildroot-$(BR_VER)
	@cp buildroot-config/buildroot.config buildroot-$(BR_VER)/.config
	$(MAKE) -C buildroot-$(BR_VER) -j$(shell nproc)
	@mkdir -p $(OUTPUT_DIR)
	@cp buildroot-$(BR_VER)/output/images/rootfs.tar.gz $(OUTPUT_DIR)/

buildroot-$(BR_VER).tar.gz:
	wget -q https://buildroot.org/downloads/buildroot-$(BR_VER).tar.gz

buildroot-$(BR_VER): buildroot-$(BR_VER).tar.gz
	tar xf $<

kernel:
	@$(MAKE) -C kernel-config build ARCH=$(ARCH)

compositor:
	@$(MAKE) -C compositor build

iso: $(OUTPUT_DIR)/rootfs.tar.gz
	@scripts/build-iso.sh $(OUTPUT_DIR) $(ISO_NAME)
	@echo "  ISO: $(ISO_NAME)"

pxe:
	@scripts/build-pxe.sh $(OUTPUT_DIR)
	@echo "  PXE package ready: output/pxe/"

run: iso
	qemu-system-x86_64 \
	    -cdrom $(ISO_NAME) \
	    -m 4G \
	    -enable-kvm \
	    -cpu host \
	    -smp 4 \
	    -vga virtio \
	    -display sdl,gl=on \
	    -boot d

clean:
	rm -rf $(OUTPUT_DIR) $(ISO_NAME)
