# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# nclawzero-image-cixmini -- comprehensive headless image for Cix Sky1 / MS-R1.
#
# Goal: parity (and then some) with what Minisforum's stock Debian image gives
# operators out of the box — networking, dev tools, hardware-diag, package
# management — without committing to a specific GUI/desktop. Headless edge
# device with a generous toolbox.

SUMMARY = "nclawzero Cix Sky1 edge image"
DESCRIPTION = "Comprehensive nclawzero image for the Cix Sky1 / CP8180 Minisforum MS-R1 target. Headless, but stocked with the tools and apps an operator expects."
LICENSE = "Apache-2.0"

inherit core-image

COMPATIBLE_MACHINE = "(cixmini)"

# debug-tweaks intentionally NOT in the canonical image — leaves the root
# password unset and is a Layer Index review concern. Dev builds opt in via
# local.conf:
#     EXTRA_IMAGE_FEATURES = "debug-tweaks empty-root-password allow-empty-password"
IMAGE_FEATURES += " \
    ssh-server-openssh \
    package-management \
    tools-debug \
    tools-profile \
"

# Comprehensive runtime — admin, dev, networking, hardware-diag.
# Containers (podman/runc) gated for a follow-up image variant once
# meta-virtualization layer is wired in (kept slim here for first-flash).
IMAGE_INSTALL = " \
    packagegroup-core-boot \
    packagegroup-core-full-cmdline \
    packagegroup-core-buildessential \
    cix-sky1-firmware \
    linux-firmware \
    kernel-modules \
    \
    python3 python3-pip python3-modules \
    git \
    sudo \
    nano \
    htop \
    tmux \
    jq \
    rsync \
    curl wget \
    openssh-sftp-server openssh-scp \
    \
    iproute2 iputils \
    tcpdump \
    nftables \
    bind-utils \
    \
    pciutils usbutils i2c-tools ethtool dmidecode \
    e2fsprogs parted gptfdisk util-linux \
    smartmontools hdparm \
    \
    chrony \
    bash-completion \
    file tree which \
    tar gzip xz bzip2 unzip \
    \
    ca-certificates \
"

IMAGE_LINGUAS = ""
SYSTEMD_DEFAULT_TARGET ?= "multi-user.target"
# More room for runtime opkg installs, logs, agent data
IMAGE_ROOTFS_EXTRA_SPACE = "2097152"

# Idempotent user provisioning — fixed-salt SHA-512 crypt hash means
# every build produces the same /etc/shadow content. Re-running bitbake
# does not regenerate or rotate credentials.
inherit extrausers
EXTRA_USERS_PARAMS = "\
    usermod -p '\$6\$cixmini2026\$Ek3ZY9PbE9CUI2hDX7DI6U5fk3JEfzGCzjbbgPaaX.nUZ70Gz6mufxWYeataJsXY22OAwppjCz6OTOxkS9CtW.' root; \
    useradd -m -s /bin/bash -G sudo,disk,plugdev,dialout ncz; \
    usermod -p '\$6\$cixmini2026\$Ek3ZY9PbE9CUI2hDX7DI6U5fk3JEfzGCzjbbgPaaX.nUZ70Gz6mufxWYeataJsXY22OAwppjCz6OTOxkS9CtW.' ncz; \
"
