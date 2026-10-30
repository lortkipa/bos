#!/bin/bash
# Runs inside the chroot after rootfs/ has been copied in.
set -Eeuo pipefail

# Live session identity (casper reads this at boot).
cat > /etc/casper.conf <<EOF
export USERNAME="${LIVE_USER}"
export USERFULLNAME="${BOS_NAME} Live User"
export HOST="${LIVE_HOSTNAME}"
export BUILD_SYSTEM="Ubuntu"
export FLAVOUR="${BOS_NAME}"
EOF

# Version stamp in the branding files that the overlay ships as templates.
for f in /usr/lib/os-release /etc/lsb-release /etc/issue /etc/issue.net \
         /etc/calamares/branding/bos/branding.desc; do
  sed -i -e "s|@NAME@|${BOS_NAME}|g" -e "s|@ID@|${BOS_ID}|g" \
         -e "s|@VERSION@|${BOS_VERSION}|g" -e "s|@CODENAME@|${BOS_CODENAME}|g" \
         -e "s|@SUITE@|${SUITE}|g" "$f"
done

# Super key opens the app menu: add it to Xfce's default shortcuts without
# replacing the rest of the file.
kb=/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml
if [[ -f $kb ]] && ! grep -q 'name="Super_L"' "$kb"; then
  sed -i 's|^\(\s*\)<property name="&lt;Alt&gt;F1" type="string" value="[^"]*"/>|\1<property name="\&lt;Alt\&gt;F1" type="string" value="xfce4-popup-whiskermenu"/>\n\1<property name="Super_L" type="string" value="xfce4-popup-whiskermenu"/>\n\1<property name="\&lt;Super\&gt;space" type="string" value="xfce4-appfinder"/>|' "$kb"
  grep -q 'name="Super_L"' "$kb" || { echo "failed to add Super shortcut" >&2; exit 1; }
fi

# Raster versions of the logo for places that can't render SVG (installer, greeter).
mkdir -p /etc/calamares/branding/bos
rsvg-convert -w 128 -h 128 /usr/share/icons/hicolor/scalable/apps/bos-logo.svg \
  -o /etc/calamares/branding/bos/logo.png
rsvg-convert -w 64 -h 64 /usr/share/icons/hicolor/scalable/apps/bos-logo.svg \
  -o /etc/calamares/branding/bos/icon.png
rsvg-convert -w 1280 -h 720 /usr/share/backgrounds/bos/default.svg \
  -o /etc/calamares/branding/bos/welcome.png
rsvg-convert -w 1920 -h 1080 /usr/share/backgrounds/bos/default.svg \
  -o /usr/share/backgrounds/bos/default.png

chmod 0755 /usr/libexec/bos/* /usr/bin/bos-* 2>/dev/null || true
chmod 0440 /etc/sudoers.d/* 2>/dev/null || true

dconf update
glib-compile-schemas /usr/share/glib-2.0/schemas
gtk-update-icon-cache -q -f /usr/share/icons/hicolor || true
fc-cache -f >/dev/null
update-desktop-database -q /usr/share/applications || true

# Services: NetworkManager owns networking; keep the live boot quick.
systemctl enable NetworkManager lightdm systemd-resolved
systemctl disable systemd-networkd.service systemd-networkd-wait-online.service 2>/dev/null || true
systemctl mask NetworkManager-wait-online.service
systemctl set-default graphical.target

update-initramfs -u -k all
