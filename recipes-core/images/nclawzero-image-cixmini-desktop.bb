# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# nclawzero-image-cixmini-desktop -- full-fat GNOME desktop variant for
# Cix Sky1 / MS-R1 with the nclawzero agent stack baked in.
#
# Layered on top of the BSP image (require nclawzero-image-cixmini.bb)
# rather than duplicated, so a flash-test of the BSP image stays
# minimally-perturbed and cheap to rebuild.
#
# What this adds on top of the BSP image:
#   - GNOME desktop (gdm + gnome-shell + apps)
#   - Chromium (ozone-wayland — runs natively on the GNOME Wayland session)
#   - Cix Sky1 closed-source userspace (S4 BSP + S5 AI tools — Mali, NPU,
#     llama.cpp/MNN/Mesa/libdrm/libglvnd/audio-DSP)
#   - Container runtime + nclawzero agent quadlets (openclaw, zeroclaw v0.7.4,
#     hermes — auto-start on boot via systemd quadlet generator)
#   - Node.js + npm (substrate for `claude-code` install at first-boot)
#   - GPU/Vulkan/audio/network/stress validation tools
#   - gnome-remote-desktop (Wayland-native RDP for headless access)
#
# Operators must opt into the per-recipe LICENSE_FLAGS_ACCEPTED for the
# closed-source Cix userspace before this image will build — see local.conf
# (or layer the LICENSE_FLAGS_ACCEPTED += line in your distro conf).

require nclawzero-image-cixmini.bb

SUMMARY = "nclawzero Cix Sky1 desktop image (GNOME + agent stack + LLM userspace)"
DESCRIPTION = "Full-fat GNOME desktop image for the Cix Sky1 / MS-R1, with the nclawzero agent stack (openclaw + zeroclaw + hermes), Chromium browser, Cix closed-source NPU/GPU userspace, and validation tooling for system + LLM acceleration testing."

# Boot to graphical, not multi-user. gdm autostarts on graphical.target.
SYSTEMD_DEFAULT_TARGET = "graphical.target"

# Desktop + agents push us well past the 5 GiB BSP rootfs. Need headroom
# for runtime opkg installs (claude-code from npm), agent OCI images, etc.
IMAGE_ROOTFS_EXTRA_SPACE = "4194304"

IMAGE_FEATURES += " \
    splash \
"

# ------------------------------------------------------------------------
# GNOME desktop core (meta-gnome — already in bblayers)
# ------------------------------------------------------------------------
IMAGE_INSTALL:append = " \
    packagegroup-base-extended \
    \
    gdm \
    gnome-shell \
    gnome-shell-extensions \
    mutter \
    gnome-control-center \
    gnome-session \
    gnome-settings-daemon \
    gnome-keyring \
    \
    gnome-terminal \
    nautilus \
    gnome-system-monitor \
    gnome-text-editor \
    gnome-disk-utility \
    \
    gnome-remote-desktop \
    \
    networkmanager \
    network-manager-applet \
    \
    pipewire \
    wireplumber \
    pulseaudio \
    \
    fontconfig-utils \
    ttf-dejavu-sans \
    ttf-dejavu-sans-mono \
    ttf-liberation \
    \
    xkeyboard-config \
    libinput \
    \
    xdg-utils \
    xdg-user-dirs \
    \
    polkit \
"

# ------------------------------------------------------------------------
# Chromium (meta-browser/meta-chromium — already in bblayers).
# ozone-wayland is the Wayland-native build; runs cleanly under mutter.
# ------------------------------------------------------------------------
IMAGE_INSTALL:append = " \
    chromium-ozone-wayland \
"

# ------------------------------------------------------------------------
# Cix Sky1 closed-source userspace — the BSP layer adds cix-audio-dsp
# already; here we round out the GPU + NPU + AI stack for Mali/NPU
# inference. Each is gated by LICENSE_FLAGS, opt-in via local.conf:
#
#   LICENSE_FLAGS_ACCEPTED += " \\
#       commercial_cix-gpu-umd \\
#       commercial_cix-noe-umd \\
#       commercial_cix-vpu-umd \\
#       commercial_cix-isp-umd \\
#       commercial_cix-libdrm \\
#       commercial_cix-libglvnd \\
#       commercial_cix-mesa \\
#       commercial_cix-llama-cpp \\
#       commercial_cix-mnn \\
#   "
# ------------------------------------------------------------------------
IMAGE_INSTALL:append = " \
    cix-gpu-umd \
    cix-noe-umd \
    cix-libdrm \
    cix-libglvnd \
    cix-mesa \
    cix-llama-cpp \
    cix-mnn \
"

# ------------------------------------------------------------------------
# Agent stack — podman runtime + the 3 quadlet units (openclaw/zeroclaw/
# hermes). nclawzero-agent-quadlets ships under recipes-nclawzero/agent-stack/
# and pins each agent to an immutable sha256.
# ------------------------------------------------------------------------
IMAGE_INSTALL:append = " \
    podman \
    crun \
    conmon \
    netavark \
    aardvark-dns \
    nclawzero-agent-quadlets \
"

# ------------------------------------------------------------------------
# Claude Code substrate. We don't bake the npm package itself (npm publishes
# at a faster cadence than image rebuilds), but ship node + npm so an
# operator can `sudo npm install -g @anthropic-ai/claude-code` immediately
# after first boot. Captured in /etc/motd-style guidance in a follow-up.
# ------------------------------------------------------------------------
IMAGE_INSTALL:append = " \
    nodejs \
    nodejs-npm \
"

# ------------------------------------------------------------------------
# System + LLM validation tools. glmark2 + vulkaninfo + mesa-demos give
# coverage for Mali GPU graphics; vainfo + libva-utils for video accel;
# alsa-utils + pulseaudio-server for audio path; stress-ng + iperf3 +
# iotop for system-load + network throughput sanity.
# ------------------------------------------------------------------------
IMAGE_INSTALL:append = " \
    glmark2 \
    vulkan-tools \
    mesa-demos \
    libva-utils \
    alsa-utils \
    \
    stress-ng \
    iperf3 \
    iotop \
    \
    python3-numpy \
    python3-requests \
"
