#!/usr/bin/env bash
# Build the bOS live/installer ISO.
#
#   sudo build/build.sh [--profile dev|release] [--clean]
#
# Stages: bootstrap -> packages -> overlay -> finalize -> squashfs -> iso.
# Must run as root on an Ubuntu/Debian host (or inside build/Dockerfile).
set -Eeuo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../bos.conf
source "$REPO/bos.conf"

PROFILE=dev
CLEAN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --profile=*) PROFILE="${1#*=}"; shift ;;
    --clean) CLEAN=1; shift ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

WORK="${WORK_DIR:-$REPO/work}"
OUT="${OUT_DIR:-$REPO/out}"
CACHE="${CACHE_DIR:-$REPO/cache}"
CHROOT="$WORK/chroot"
STAGE="$WORK/iso"

case "$PROFILE" in
  dev)
    # Fast to build and boot: light compression, reuse downloaded packages.
    SQUASHFS_OPTS=(-comp zstd -Xcompression-level 3)
    USE_CACHE=1
    ISO_NAME="$BOS_ID-dev-$ARCH.iso"
    ;;
  release)
    # Smallest image, built from a clean tree with nothing reused from earlier builds.
    SQUASHFS_OPTS=(-comp xz -Xbcj x86 -b 1M)
    USE_CACHE=0
    CLEAN=1
    ISO_NAME="$BOS_ID-$BOS_VERSION-$ARCH.iso"
    ;;
  *) echo "unknown profile: $PROFILE (expected dev or release)" >&2; exit 2 ;;
esac

log() { printf '\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
die() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run as root (sudo make ...), or use 'make docker-iso'"
for tool in debootstrap mksquashfs grub-mkrescue xorriso mformat; do
  command -v "$tool" >/dev/null || die "missing '$tool' — run 'sudo make deps' or use 'make docker-iso'"
done
[[ -d /usr/lib/grub/i386-pc && -d /usr/lib/grub/x86_64-efi ]] \
  || die "grub-pc-bin and grub-efi-amd64-bin are required — run 'sudo make deps'"

# --- chroot mount handling ---------------------------------------------------
MOUNTS=()
mount_chroot() {
  local m
  for m in proc sys dev dev/pts run; do mkdir -p "$CHROOT/$m"; done
  mount -t proc proc "$CHROOT/proc";              MOUNTS+=("$CHROOT/proc")
  mount -t sysfs sys "$CHROOT/sys";               MOUNTS+=("$CHROOT/sys")
  mount --bind /dev "$CHROOT/dev";                MOUNTS+=("$CHROOT/dev")
  mount -t devpts devpts "$CHROOT/dev/pts" -o gid=5,mode=620; MOUNTS+=("$CHROOT/dev/pts")
  mount -t tmpfs tmpfs "$CHROOT/run";             MOUNTS+=("$CHROOT/run")
  if [[ $USE_CACHE -eq 1 ]]; then
    mkdir -p "$CACHE/apt" "$CHROOT/var/cache/apt/archives"
    mount --bind "$CACHE/apt" "$CHROOT/var/cache/apt/archives"
    MOUNTS+=("$CHROOT/var/cache/apt/archives")
  fi
}
umount_chroot() {
  local i
  for (( i=${#MOUNTS[@]}-1; i>=0; i-- )); do
    umount -l "${MOUNTS[i]}" 2>/dev/null || true
  done
  MOUNTS=()
}
trap umount_chroot EXIT

in_chroot() {
  chroot "$CHROOT" /usr/bin/env -i \
    HOME=/root TERM="${TERM:-xterm}" LANG=C.UTF-8 \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    DEBIAN_FRONTEND=noninteractive \
    BOS_NAME="$BOS_NAME" BOS_ID="$BOS_ID" BOS_VERSION="$BOS_VERSION" BOS_CODENAME="$BOS_CODENAME" \
    SUITE="$SUITE" MIRROR="$MIRROR" LIVE_USER="$LIVE_USER" LIVE_HOSTNAME="$LIVE_HOSTNAME" \
    LOCALE="$LOCALE" TIMEZONE="$TIMEZONE" PROFILE="$PROFILE" \
    "$@"
}

# --- stages ------------------------------------------------------------------
stage_bootstrap() {
  if [[ $CLEAN -eq 1 ]]; then
    log "Removing previous build tree"
    rm -rf "$WORK"
  fi
  mkdir -p "$WORK" "$OUT"

  local tarball="$CACHE/bootstrap-$SUITE-$ARCH.tar"
  rm -rf "$CHROOT"
  if [[ $USE_CACHE -eq 1 && -f "$tarball" ]]; then
    log "Unpacking cached base system ($tarball)"
    mkdir -p "$CHROOT"
    tar -C "$CHROOT" -xpf "$tarball"
  else
    log "Bootstrapping Ubuntu $SUITE ($ARCH) from $MIRROR"
    debootstrap --variant=minbase --arch="$ARCH" --components=main,universe \
      "$SUITE" "$CHROOT" "$MIRROR"
    if [[ $USE_CACHE -eq 1 ]]; then
      mkdir -p "$CACHE"
      tar -C "$CHROOT" -cpf "$tarball.tmp" . && mv "$tarball.tmp" "$tarball"
    fi
  fi
}

stage_packages() {
  log "Installing packages"
  rm -rf "$CHROOT/tmp/bos-build"
  mkdir -p "$CHROOT/tmp/bos-build"
  cp -a "$REPO/build/chroot/." "$CHROOT/tmp/bos-build/"
  cp -a "$REPO/build/packages" "$CHROOT/tmp/bos-build/packages"
  cp /etc/resolv.conf "$CHROOT/etc/resolv.conf.host" 2>/dev/null || true
  in_chroot /bin/bash /tmp/bos-build/10-packages.sh
}

stage_overlay() {
  log "Applying rootfs overlay"
  # Plain copy: files in rootfs/ win over whatever the packages shipped.
  cp -a --no-preserve=ownership "$REPO/rootfs/." "$CHROOT/"
}

stage_finalize() {
  log "Configuring system"
  in_chroot /bin/bash /tmp/bos-build/20-configure.sh
  umount_chroot
  in_chroot /bin/bash /tmp/bos-build/90-cleanup.sh
  rm -rf "$CHROOT/tmp/bos-build"
}

stage_squashfs() {
  log "Creating squashfs (${SQUASHFS_OPTS[*]})"
  rm -rf "$STAGE"
  mkdir -p "$STAGE/casper" "$STAGE/boot/grub" "$STAGE/.disk"

  local kver
  kver="$(basename "$(ls -1d "$CHROOT"/lib/modules/* | sort -V | tail -1)")"
  cp "$CHROOT/boot/vmlinuz-$kver"    "$STAGE/casper/vmlinuz"
  cp "$CHROOT/boot/initrd.img-$kver" "$STAGE/casper/initrd"

  chroot "$CHROOT" dpkg-query -W --showformat='${Package} ${Version}\n' > "$STAGE/casper/filesystem.manifest"
  # Packages the installer removes from the installed system.
  printf '%s\n' casper calamares calamares-settings-ubuntu-common > "$STAGE/casper/filesystem.manifest-remove"
  du -sx --block-size=1 "$CHROOT" | cut -f1 > "$STAGE/casper/filesystem.size"

  mksquashfs "$CHROOT" "$STAGE/casper/filesystem.squashfs" \
    -noappend -wildcards -e 'proc/*' -e 'sys/*' -e 'dev/*' -e 'run/*' -e 'tmp/*' \
    "${SQUASHFS_OPTS[@]}" -quiet -progress
}

stage_iso() {
  log "Building hybrid BIOS/UEFI ISO"
  local label
  label="$(echo "${BOS_ID}_${BOS_VERSION}" | tr '[:lower:].' '[:upper:]_' | cut -c1-32)"

  sed -e "s|@NAME@|$BOS_NAME|g" -e "s|@VERSION@|$BOS_VERSION|g" \
    "$REPO/build/iso/grub.cfg" > "$STAGE/boot/grub/grub.cfg"
  echo "$BOS_NAME $BOS_VERSION \"$BOS_CODENAME\" - $ARCH ($(date -u +%Y%m%d))" > "$STAGE/.disk/info"
  touch "$STAGE/.disk/base_installable"
  echo "full_cd/single" > "$STAGE/.disk/cd_type"

  (cd "$STAGE" && find . -type f ! -name md5sum.txt ! -path './boot/*' -print0 \
    | xargs -0 md5sum > md5sum.txt)

  grub-mkrescue -o "$OUT/$ISO_NAME" "$STAGE" -- -volid "$label" 2>&1 \
    | grep -vE '^(xorriso|libisofs|libburn).*(UPDATE|NOTE)' || true
  [[ -s "$OUT/$ISO_NAME" ]] || die "ISO was not created"

  if [[ $PROFILE == release ]]; then
    cp "$STAGE/casper/filesystem.manifest" "$OUT/${ISO_NAME%.iso}.manifest"
    (cd "$OUT" && sha256sum "$ISO_NAME" > "$ISO_NAME.sha256")
  fi
  if [[ -n "${SUDO_UID:-}" ]]; then
    chown "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$OUT" "$OUT"/* 2>/dev/null || true
  fi
  log "Done: $OUT/$ISO_NAME ($(du -h "$OUT/$ISO_NAME" | cut -f1))"
}

START=$SECONDS
stage_bootstrap
mount_chroot
stage_packages
stage_overlay
stage_finalize
stage_squashfs
stage_iso
log "Build finished in $(( (SECONDS - START) / 60 ))m $(( (SECONDS - START) % 60 ))s"
