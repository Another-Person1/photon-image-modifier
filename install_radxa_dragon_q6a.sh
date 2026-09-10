#!/bin/bash

# Exit on errors, print commands, ignore unset variables
set -ex +u
set -o pipefail

# Keep Armbian's Q6A kernel, DTB, firmware, EFI partition and UUID-based boot
# configuration. The image runner mounts rootfs only; do not reinstall GRUB.
# Let the stock SPI BIOS select microSD, eMMC, NVMe or USB. This 512-byte-sector
# image is not the separate 4096-byte-sector layout required for native UFS.
grep -Eq '^BOARD="?radxa-dragon-q6a"?$' /etc/armbian-release
grep -Eq '^VERSION_CODENAME="?trixie"?$' /etc/os-release
test "$(dpkg --print-architecture)" = arm64
grep -Eq 'root=(UUID|PARTUUID)=' /boot/grub/grub.cfg
grep -Eq '^(UUID|PARTUUID)=[^[:space:]]+[[:space:]]+/[[:space:]]' /etc/fstab

cat > /etc/apt/apt.conf.d/99dpkg.conf << EOF
Dpkg::Progress-Fancy "0";
APT::Color "0";
Dpkg::Use-Pty "0";
EOF

chmod +x ./install.sh
./install.sh --control-networking=yes --arch=aarch64 --version="$1"

apt-get --yes -qq install openssh-server lm-sensors libc6 libstdc++6

# Radxa publishes Debian packages for FastRPC and the Hexagon v68 QNN runtime.
# Use pinned, verified releases instead of adding the Rubik Ubuntu PPA to Debian.
package_dir=$(mktemp -d)
while read -r checksum url; do
    package="$package_dir/${url##*/}"
    wget --quiet --output-document="$package" "$url"
    echo "$checksum  $package" | sha256sum --check -
done < ./files/radxa-dragon-q6a/packages.sha256

# Armbian already owns the kernel firmware. Extract only Radxa's DSP userspace
# files and license, avoiding conflicting firmware packages and initramfs hooks.
dpkg-deb --fsys-tarfile "$package_dir/radxa-firmware-qcs6490_0.2.41_all.deb" |
    tar -x -C / ./usr/share/qcom ./usr/share/doc/radxa-firmware-qcs6490
rm "$package_dir/radxa-firmware-qcs6490_0.2.41_all.deb"
apt-get --yes install "$package_dir/"*.deb
rm -rf "$package_dir"
ldconfig

# Check installed payloads in the chroot; actual DSP execution needs Q6A hardware.
test -s /usr/lib/aarch64-linux-gnu/libQnnHtp.so
test -s /usr/lib/aarch64-linux-gnu/libQnnHtpV68Stub.so
test -s /usr/lib/aarch64-linux-gnu/libQnnHtpV68Skel.so
test -s /usr/lib/aarch64-linux-gnu/libQnnTFLiteDelegate.so
test -d /usr/share/qcom/qcs6490/radxa/dragon-q6a/dsp/cdsp
test -s /usr/lib/firmware/qcom/qcs6490/radxa/dragon-q6a/cdsp.mbn

# The QCS6490 uses the same performance-core numbering as the Rubik Pi 3.
# Use a drop-in so subsequent PhotonVision service updates retain these settings.
mkdir -p /etc/systemd/system/photonvision.service.d
cat > /etc/systemd/system/photonvision.service.d/20-qcs6490.conf << 'EOF'
[Unit]
Wants=fastrpc.service cdsprpcd.service
After=fastrpc.service cdsprpcd.service

[Service]
AllowedCPUs=4-7
Environment="ADSP_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu;/usr/lib/dsp;/usr/lib/dsp/cdsp"
EOF

systemctl enable ssh
systemctl disable NetworkManager-wait-online.service

# Disable radios for the vision appliance without removing Qualcomm DSP firmware.
systemctl mask bluetooth.service wpa_supplicant.service
mkdir -p /etc/NetworkManager/conf.d /var/lib/NetworkManager
cat > /etc/NetworkManager/conf.d/disable-wifi.conf << EOF
[keyfile]
unmanaged-devices=interface-name:wlan*;type:wifi
EOF
cat > /var/lib/NetworkManager/NetworkManager.state << EOF
[main]
NetworkingEnabled=true
WirelessEnabled=false
WWANEnabled=false
EOF

echo "photonvision" > /etc/hostname
sed -i 's/127.0.1.1.*/127.0.1.1    photonvision/g' /etc/hosts

# Preserve Armbian's first-boot filesystem growth, but skip interactive first login
# so install_common.sh's photon:vision account is not overwritten.
rm -f /root/.not_logged_in_yet
printf '#!/bin/bash\nexit 0\n' > /usr/lib/armbian/armbian-firstlogin
chmod +x /usr/lib/armbian/armbian-firstlogin
chmod -x /etc/update-motd.d/*

rm -rf /var/lib/apt/lists/*
apt-get --yes -qq clean
rm -rf /usr/share/locale/
