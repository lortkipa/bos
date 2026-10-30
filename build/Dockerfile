# Build environment for hosts that aren't Ubuntu/Debian (Fedora, Arch, macOS, ...).
# Used by `make docker-iso` / `make docker-release`; needs --privileged for chroot mounts.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      debootstrap squashfs-tools xorriso mtools dosfstools \
      grub-common grub-pc-bin grub-efi-amd64-bin \
      ca-certificates make python3 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
ENTRYPOINT ["/src/build/build.sh"]
