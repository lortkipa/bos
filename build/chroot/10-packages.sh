#!/bin/bash
# Runs inside the chroot: configure apt and install every package in build/packages/*.list.
set -Eeuo pipefail
cd /tmp/bos-build

[[ -s /etc/resolv.conf.host ]] && cat /etc/resolv.conf.host > /etc/resolv.conf
rm -f /etc/resolv.conf.host

# Never start services while building the image.
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d

rm -f /etc/apt/sources.list
cat > /etc/apt/sources.list.d/ubuntu.sources <<EOF
Types: deb
URIs: ${MIRROR}
Suites: ${SUITE} ${SUITE}-updates ${SUITE}-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://security.ubuntu.com/ubuntu
Suites: ${SUITE}-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF

# bOS ships no snaps: keep snapd (and the snap-only transitional debs) out for good.
cat > /etc/apt/preferences.d/no-snap <<'EOF'
Package: snapd
Pin: release a=*
Pin-Priority: -10
EOF
cat > /etc/apt/apt.conf.d/90bos <<'EOF'
APT::Install-Recommends "false";
APT::Install-Suggests "false";
Dpkg::Options { "--force-confdef"; "--force-confold"; };
EOF

echo "$LIVE_HOSTNAME" > /etc/hostname
dbus-uuidgen > /etc/machine-id 2>/dev/null || systemd-machine-id-setup 2>/dev/null || true

apt-get update
apt-get -y full-upgrade

# Locale first so later postinst scripts don't complain.
apt-get -y install locales tzdata
locale-gen "$LOCALE"
update-locale LANG="$LOCALE"
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
echo "$TIMEZONE" > /etc/timezone

# Answer debconf questions up front so installs never prompt.
debconf-set-selections <<'EOF'
keyboard-configuration keyboard-configuration/layoutcode string us
keyboard-configuration keyboard-configuration/modelcode string pc105
grub-pc grub-pc/install_devices_empty boolean true
grub-pc grub-pc/install_devices multiselect
lightdm shared/default-x-display-manager select lightdm
EOF

mapfile -t PKGS < <(cat packages/*.list | sed -e 's/#.*//' -e 's/[[:space:]]*$//' | grep -v '^$')
apt-get -y install "${PKGS[@]}"

# Offline bootloader packages for the installer: BIOS systems keep grub-pc (already
# installed); UEFI systems get grub-efi + shim from this cache (see rootfs/usr/libexec/bos).
mkdir -p /var/lib/bos/debs/efi
apt-get -y --download-only -o Dir::Cache::archives=/var/lib/bos/debs/efi \
  install grub-efi-amd64 grub-efi-amd64-signed shim-signed
rm -rf /var/lib/bos/debs/efi/partial /var/lib/bos/debs/efi/lock

# Replace distro branding files with ours (shipped in rootfs/). Diverting keeps
# package upgrades from overwriting them on installed systems.
divert() {
  dpkg-divert --quiet --local --rename --add "$1"
}
divert /usr/lib/os-release
divert /etc/lsb-release
divert /etc/issue
divert /etc/issue.net
divert /usr/share/backgrounds/xfce/xfce-shapes.svg
