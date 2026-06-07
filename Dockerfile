# antigravity-linux build environment
# Builds a minimal Linux system with BusyBox userspace
# Output: rootfs.cpio.gz (initramfs) + bzImage (kernel)

FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    build-essential bc bison flex libelf-dev libssl-dev \
    libncurses-dev cpio gzip wget curl xz-utils \
    qemu-system-x86 grub-pc-bin \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
