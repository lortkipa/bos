# bOS

A clean, calm Linux desktop with a macOS-style layout: a translucent **menu bar** across the
top (with the focused app's menus in it) and a magnifying **dock** at the bottom.

bOS is built on **Ubuntu 24.04 LTS** (no snaps) with an Xfce core, re-skinned:

| Piece | What bOS uses |
| --- | --- |
| Menu bar | `xfce4-panel` at the top: bOS menu (Whisker), global app menu, status icons, clock, power menu |
| Dock | `plank` with a frosted-glass bOS theme, zoom on hover, Trash and an Applications stack |
| Windows | `xfwm4` with a custom bOS theme: traffic-light buttons on the left, centred titles, rounded corners |
| Look | Arc-Lighter GTK theme, Papirus icons, Inter + JetBrains Mono fonts, bOS wallpaper |
| Apps | Thunar, GNOME Web, Terminal, Mousepad, Ristretto, Evince, Calculator, Disks |
| Boot / install | Hybrid BIOS + UEFI live ISO (casper) with the Calamares installer |

```
┌──────────────────────────────────────────────────────────────────┐
│ b  Files  File Edit View Go Help          🔊 🔋   Fri 30 Oct 14:02 ⏻ │  ← menu bar
│                                                                  │
│          ┌─● ● ●────────── Home ──────────────┐                  │
│          │                                    │                  │
│          └────────────────────────────────────┘                  │
│                                                                  │
│                 ╭──────────────────────────────╮                 │
│                 │ ▦  🗂  🌐  >_  ✎  ＝  ⚙  ⬇  🗑 │                 │  ← dock
└─────────────────┴──────────────────────────────┴─────────────────┘
```

Keyboard: **Super** opens the bOS menu, **Super+Space** opens the app finder.

## Requirements

Building needs root (it uses `debootstrap` and `chroot`) and about 15 GB of free disk.

- **Ubuntu 22.04+ / Debian 12+ host**: run `make deps` once to install the tools
  (`debootstrap`, `squashfs-tools`, `xorriso`, `mtools`, GRUB for BIOS and EFI, QEMU, OVMF).
- **Any other Linux host**: install Docker and use the `docker-*` targets below; you still need
  QEMU (+ OVMF for UEFI) on the host to run the VM.

## Development: build and run in a VM

```bash
make deps
```

```bash
make dev
```

`make dev` is `make iso` followed by `make run`:

- `make iso` builds `out/bos-dev-amd64.iso`. The dev profile is tuned for iteration: the
  bootstrapped base system and every downloaded `.deb` are cached in `cache/`, and the squashfs
  uses fast zstd compression. The first build downloads ~1.5 GB; rebuilds reuse the cache.
- `make run` boots the newest ISO in QEMU (BIOS, 4 GB RAM, 4 CPUs, virtio GPU, USB tablet).
  It uses KVM when `/dev/kvm` is accessible and falls back to (slow) emulation otherwise.

Other VM targets:

| Command | What it does |
| --- | --- |
| `make run-uefi` | Boot the ISO with UEFI firmware (OVMF) |
| `make run-install` | Boot the ISO (UEFI) with a blank 32 GB disk at `vm/disk.qcow2` — click **Install bOS** in the dock |
| `make run-installed` | Boot the installed `vm/disk.qcow2` without the ISO |
| `scripts/run-vm.sh --help` | All options: `--mem`, `--cpus`, `--headless` (VNC on `localhost:5900`), a custom ISO path, ... |

The live session logs in automatically as user `bos` (passwordless `sudo`).

Without an Ubuntu/Debian host, build the dev ISO in Docker, then run it the same way:

```bash
make docker-iso
```

```bash
make run
```

### Typical edit loop

1. Change files in `rootfs/` (copied over the image), `build/packages/*.list` (packages) or
   `build/chroot/*.sh` (setup steps).
2. `make dev` to rebuild and boot.
3. To try a desktop setting quickly, change it live in the VM first (Xfce settings write to
   `~/.config/xfce4/xfconf/`), then copy the result into `rootfs/etc/skel/`.

## Production build

```bash
make release
```

or, in Docker:

```bash
make docker-release
```

The release profile always starts from an empty tree (fresh `debootstrap`, no cached packages)
and compresses the squashfs with xz, giving a smaller ISO. It writes:

- `out/bos-<version>-amd64.iso` — hybrid ISO, boots from DVD or USB on BIOS and UEFI machines
- `out/bos-<version>-amd64.iso.sha256` — checksum
- `out/bos-<version>-amd64.manifest` — every package and version in the image

Set the version in `bos.conf` (or `make release BOS_VERSION=1.0.0`) before building. Verify and
write to a USB stick (replace `/dev/sdX` with your stick — everything on it is erased):

```bash
sha256sum -c out/bos-0.1.0-amd64.iso.sha256
```

```bash
sudo dd if=out/bos-0.1.0-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

The ISO's GRUB is unsigned, so turn off Secure Boot to boot the live media. Systems installed
from it on UEFI get Ubuntu's signed shim + GRUB.

## Configuration

`bos.conf` holds the build settings; each can be overridden from the environment:

| Variable | Default | Meaning |
| --- | --- | --- |
| `BOS_NAME`, `BOS_ID` | `bOS`, `bos` | Display name / machine id used in `os-release`, ISO name |
| `BOS_VERSION`, `BOS_CODENAME` | `0.1.0`, `aurora` | Release version |
| `SUITE`, `ARCH` | `noble`, `amd64` | Ubuntu base release and architecture |
| `MIRROR` | `http://archive.ubuntu.com/ubuntu` | Package mirror, e.g. a local apt-cacher |
| `LIVE_USER`, `LIVE_HOSTNAME` | `bos` | Live session user and host name |
| `LOCALE`, `TIMEZONE` | `en_US.UTF-8`, `Etc/UTC` | Image defaults (the installer asks) |
| `WORK_DIR`, `OUT_DIR`, `CACHE_DIR` | `work/`, `out/`, `cache/` | Build directories |

Example: `sudo MIRROR=http://192.168.1.10:3142/archive.ubuntu.com/ubuntu build/build.sh --profile dev`.

## How the build works

`build/build.sh` runs these stages:

1. **bootstrap** — `debootstrap --variant=minbase` an Ubuntu base into `work/chroot`
   (dev: unpacked from `cache/` after the first time).
2. **packages** — `build/chroot/10-packages.sh` sets up apt (snapd pinned out, no recommends),
   locale, and installs everything in `build/packages/*.list`.
3. **overlay** — copies `rootfs/` over the system: branding, themes, dock and menu bar config.
4. **finalize** — `build/chroot/20-configure.sh` (casper live config, dconf, icon/font caches,
   services, initramfs), then `90-cleanup.sh`.
5. **squashfs** — packs the system into `casper/filesystem.squashfs` with kernel + initrd.
6. **iso** — `grub-mkrescue` produces a hybrid BIOS/UEFI ISO with the menu in `build/iso/grub.cfg`.

## Repository layout

```
bos.conf                 build settings
Makefile                 entry points (make help)
build/
  build.sh               the builder
  chroot/*.sh            steps run inside the image
  packages/*.list        package sets (base, desktop, live-only)
  iso/grub.cfg           live boot menu
  Dockerfile             build container for non-Debian hosts
rootfs/                  files copied into the image
  etc/skel/.config/      default user settings: menu bar, window manager, dock items, terminal
  etc/dconf/db/local.d/  system defaults: dock (plank) and GTK4 app settings
  etc/calamares/         installer configuration and branding
  usr/share/themes/bOS/  window decorations (generated by tools/gen-wm-theme.py)
  usr/share/plank/themes/bOS/  dock theme
  usr/share/backgrounds/bos/   wallpaper
scripts/run-vm.sh        QEMU launcher
tools/gen-wm-theme.py    regenerates the window decoration PNGs (`make theme`)
```

## Cleaning up

- `make clean` removes the build tree (`work/`).
- `make distclean` also removes the download cache, ISOs and the VM disk.

## License

MIT — see [LICENSE](LICENSE). Packages in the image keep their own licenses.
