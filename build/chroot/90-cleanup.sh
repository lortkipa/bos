#!/bin/bash
# Runs inside the chroot (no /proc, /dev mounted) right before the squashfs is made.
set -Eeuo pipefail

rm -f /usr/sbin/policy-rc.d
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/debconf/*-old /var/lib/dpkg/*-old
rm -rf /tmp/* /var/tmp/* /root/.cache /root/.bash_history
find /var/log -type f -exec truncate -s 0 {} +

# Generated per machine on first boot.
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id
rm -f /etc/ssh/ssh_host_*

ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
