#!/usr/bin/env bash
# Boot a bOS ISO (or an installed disk) in QEMU.
#
#   scripts/run-vm.sh [options] [ISO]
#
#   --uefi            boot with UEFI firmware (OVMF) instead of legacy BIOS
#   --disk            attach vm/disk.qcow2 (created, 32G, if missing) to install onto
#   --boot-disk       boot vm/disk.qcow2 only, no ISO (after installing)
#   --mem MB          guest memory (default 4096)
#   --cpus N          guest CPUs (default 4)
#   --headless        no window; VNC on localhost:5900 and serial log on stdout
#
# ISO defaults to the newest *.iso in out/.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_DIR="${VM_DIR:-$REPO/vm}"
DISK="$VM_DIR/disk.qcow2"
MEM=4096 CPUS=4 UEFI=0 USE_DISK=0 BOOT_DISK=0 HEADLESS=0 ISO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --uefi) UEFI=1 ;;
    --disk) USE_DISK=1 ;;
    --boot-disk) USE_DISK=1; BOOT_DISK=1 ;;
    --mem) MEM="$2"; shift ;;
    --cpus) CPUS="$2"; shift ;;
    --headless) HEADLESS=1 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) ISO="$1" ;;
  esac
  shift
done

command -v qemu-system-x86_64 >/dev/null || { echo "qemu-system-x86_64 not found (install qemu)" >&2; exit 1; }

if [[ $BOOT_DISK -eq 0 ]]; then
  if [[ -z "$ISO" ]]; then
    ISO="$(ls -t "$REPO"/out/*.iso 2>/dev/null | head -1 || true)"
  fi
  [[ -f "$ISO" ]] || { echo "no ISO found — build one with 'make iso' or pass a path" >&2; exit 1; }
fi

args=(-name bOS -m "$MEM" -smp "$CPUS"
      -machine q35 -device virtio-vga
      -device qemu-xhci -device usb-tablet -device usb-kbd
      -nic user,model=virtio-net-pci
      -device virtio-rng-pci)

# Hardware acceleration when available; otherwise plain emulation (slow but works).
if [[ -w /dev/kvm ]]; then
  args+=(-accel kvm -cpu host)
elif [[ "$(uname -s)" == Darwin && "$(uname -m)" == x86_64 ]]; then
  args+=(-accel hvf -cpu host)
else
  echo "warning: no KVM access — running unaccelerated, expect a slow VM" >&2
  [[ -e /dev/kvm ]] && echo "         (add yourself to the 'kvm' group to fix this)" >&2
  args+=(-accel tcg -cpu max)
fi

if [[ $UEFI -eq 1 ]]; then
  code="" vars=""
  for pair in \
    /usr/share/OVMF/OVMF_CODE_4M.fd:/usr/share/OVMF/OVMF_VARS_4M.fd \
    /usr/share/OVMF/OVMF_CODE.fd:/usr/share/OVMF/OVMF_VARS.fd \
    /usr/share/edk2/ovmf/OVMF_CODE.fd:/usr/share/edk2/ovmf/OVMF_VARS.fd \
    /usr/share/edk2/x64/OVMF_CODE.4m.fd:/usr/share/edk2/x64/OVMF_VARS.4m.fd \
    /usr/share/qemu/edk2-x86_64-code.fd:/usr/share/qemu/edk2-i386-vars.fd \
    /opt/homebrew/share/qemu/edk2-x86_64-code.fd:/opt/homebrew/share/qemu/edk2-i386-vars.fd \
    /usr/local/share/qemu/edk2-x86_64-code.fd:/usr/local/share/qemu/edk2-i386-vars.fd; do
    if [[ -f "${pair%%:*}" && -f "${pair##*:}" ]]; then code="${pair%%:*}" vars="${pair##*:}"; break; fi
  done
  [[ -n "$code" ]] || { echo "OVMF firmware not found (install the 'ovmf' / 'edk2-ovmf' package)" >&2; exit 1; }
  mkdir -p "$VM_DIR"
  [[ -f "$VM_DIR/ovmf-vars.fd" ]] || cp "$vars" "$VM_DIR/ovmf-vars.fd"
  args+=(-drive "if=pflash,format=raw,readonly=on,file=$code"
         -drive "if=pflash,format=raw,file=$VM_DIR/ovmf-vars.fd")
fi

if [[ $USE_DISK -eq 1 ]]; then
  mkdir -p "$VM_DIR"
  [[ -f "$DISK" ]] || qemu-img create -f qcow2 "$DISK" 32G >/dev/null
  args+=(-drive "file=$DISK,if=virtio,format=qcow2,discard=unmap")
fi

if [[ $BOOT_DISK -eq 0 ]]; then
  args+=(-drive "file=$ISO,media=cdrom,readonly=on")
  [[ $USE_DISK -eq 1 ]] && args+=(-boot order=dc,menu=on) || args+=(-boot order=d)
fi

if [[ $HEADLESS -eq 1 ]]; then
  args+=(-display none -vnc 127.0.0.1:0 -serial stdio)
  echo "VNC: localhost:5900" >&2
fi

echo "+ qemu-system-x86_64 ${args[*]}" >&2
exec qemu-system-x86_64 "${args[@]}"
