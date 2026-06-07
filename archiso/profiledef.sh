#!/usr/bin/env bash
# Flynn OS Linux — archiso profile definition
# Base: Arch Linux  |  Kernel: linux-zen  |  GPU: AMDGPU + Vulkan

iso_name="flynnos"
iso_label="FLYNNOS_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Flynn OS Project"
iso_application="Flynn OS Linux — The Grid"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux.mbr' 'bios.syslinux.eltorito' 'uefi-x64.systemd-boot.esp' 'uefi-x64.systemd-boot.eltorito')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
    ["/etc/shadow"]="0:0:400"
    ["/usr/local/bin/"]="0:0:755"
    ["/root/.xinitrc"]="0:0:755"
    ["/root/.config/openbox/autostart"]="0:0:755"
    ["/etc/flynn/"]="0:0:755"
)
