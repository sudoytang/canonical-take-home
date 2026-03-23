#!/bin/bash
set -euo pipefail

WORK_DIR="$(pwd)/work"
INITRAMFS_DIR="$WORK_DIR/initramfs"
OUT_DIR="$(pwd)/out"
KERNEL_URL="https://deb.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux"
OVMF="/usr/share/ovmf/OVMF.fd"

# Use sudo only when not running as root
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

# Install a package if the given command is not found
export DEBIAN_FRONTEND=noninteractive

APT_UPDATED=0
apt_install() {
    local pkg=$1
    if [ "$APT_UPDATED" -eq 0 ]; then
        $SUDO apt-get update -qq
        APT_UPDATED=1
    fi
    $SUDO apt-get install -y "$pkg"
}

require() {
    local cmd=$1
    local pkg=$2
    if ! command -v "$cmd" &>/dev/null; then
        echo "Installing $pkg..."
        apt_install "$pkg"
    fi
}

require curl          curl
require gcc           gcc
require cpio          cpio
require grub-mkrescue grub-efi-amd64-bin
require xorriso       xorriso
require mtools        mtools
require qemu-system-x86_64 qemu-system-x86

# OVMF is a firmware file, not a command
if [ ! -f "$OVMF" ]; then
    echo "Installing ovmf..."
    apt_install ovmf
fi

# Clean up and create directory structure
rm -rf "$WORK_DIR"
mkdir -p "$INITRAMFS_DIR"
mkdir -p "$OUT_DIR"

# Download kernel
echo "Downloading kernel..."
curl -L "$KERNEL_URL" -o "$OUT_DIR/vmlinuz"

# Compile a static init binary that prints "hello world" and halts
cat > "$WORK_DIR/init.c" << 'EOF'
#include <unistd.h>

int main() {
    const char msg[] = "hello world\n";
    write(STDOUT_FILENO, msg, sizeof(msg) - 1);
    while (1) {
        pause();
    }
    return 0;
}
EOF

echo "Compiling init..."
gcc -static -o "$INITRAMFS_DIR/init" "$WORK_DIR/init.c"

# Pack into initramfs.img
echo "Building initramfs..."
(cd "$INITRAMFS_DIR" && find . | cpio -o -H newc | gzip > "$OUT_DIR/initramfs.img")

# Build bootable ISO with GRUB EFI bootloader
ISO_ROOT="$WORK_DIR/iso"
mkdir -p "$ISO_ROOT/boot/grub"
cp "$OUT_DIR/vmlinuz"       "$ISO_ROOT/boot/vmlinuz"
cp "$OUT_DIR/initramfs.img" "$ISO_ROOT/boot/initramfs.img"

cat > "$ISO_ROOT/boot/grub/grub.cfg" << 'EOF'
set timeout=0

menuentry "hello world" {
    linux  /boot/vmlinuz console=ttyS0 quiet
    initrd /boot/initramfs.img
}
EOF

echo "Building ISO..."
grub-mkrescue -o "$OUT_DIR/boot.iso" "$ISO_ROOT"

# Boot the ISO with QEMU using UEFI firmware
echo "Booting..."
qemu-system-x86_64 \
  -bios "$OVMF" \
  -cdrom "$OUT_DIR/boot.iso" \
  -nographic \
  -m 512M
