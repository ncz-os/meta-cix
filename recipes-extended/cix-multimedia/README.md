# Cix Sky1 Multimedia (S6) — DEFERRED

**Status as of 2026-05-01:** No recipes shipped. Standard `meta-multimedia`
GStreamer is the recommended path for now. Full Cix-fork integration
deferred to a later slice.

## What Cix's GStreamer fork provides

The Cix Sky1 desktop image ships `cix-gstreamer` (1.22.1) with these
hardware-accelerated plugins under `/usr/share/cix/lib/gstreamer-1.0/`:

- `libgstcixsr.so` — Cix super-resolution (upscaling)
- `libgstcixheaacv2enc.so` — HE-AAC v2 encode (DSP-accelerated)
- `libgstcixmp3dec.so` — MP3 decode (DSP-accelerated)
- `libgstcixdspif.so` — DSP interface plugin (gateway to cix-audio-dsp
  codec stack)

Additional gst-plugins-bad subprojects:
- `subprojects/gst-plugins-bad/ext/onnx` — ONNX inference plugin

The hardware-acceleration value-prop: VPU video codec offload (H.264,
H.265, AV1, VP8, VP9, JPEG via cix-vpu-umd firmware blobs) and DSP
audio codec offload (HE-AAC, MP3, Opus, FLAC, Vorbis via
cix-audio-dsp).

## Why deferred

1. **Source tree size:** `component/cix_opensource/gstreamer` is 190 MB
   (full Cix-fork tree, not just plugins). Building from source means
   pulling all of upstream GStreamer + Cix patches + plugin subprojects
   — a multi-hour Yocto build, far heavier than any other slice in
   this layer.
2. **Pre-built debs unavailable:** Unlike cix-llama-cpp / cix-mnn /
   cix-libdrm / cix-libglvnd / cix-mesa, `cix-gstreamer` is NOT
   published in `minisforum-cix-p1-repo/ext_debs`. So we can't take
   the cheap bin_package path.
3. **Orthogonal to agent value-prop:** zeroclaw / openclaw / hermes
   don't depend on Cix-accelerated multimedia. They use cix-noe-umd
   (NPU) and cix-llama-cpp (NPU-llama) for inference. GStreamer
   acceleration only matters for video/audio playback workloads.

## Recommended path for cixmini images today

Add `meta-multimedia` to bblayers, install standard `gstreamer1.0`
+ `gstreamer1.0-plugins-{base,good,bad,ugly}` from there. This gives
software-decoded multimedia support without the Cix VPU/DSP offload.

```
# In cixmini's local.conf:
IMAGE_INSTALL:append = " gstreamer1.0 \
                         gstreamer1.0-plugins-base \
                         gstreamer1.0-plugins-good \
                         gstreamer1.0-plugins-bad"
```

## What S6 (full integration) would require

When it's worth building, the slice would author:

1. `cix-gstreamer_1.22.1.bb` — Cix's GStreamer fork from
   `minisforum-cix-p1-repo/freedesktop_repo__gstreamer__gstreamer`
   at SRCREV (manifest-pinned). meson + ninja build, ~30-60 min on
   ULTRA arm64. Replaces meta-multimedia gstreamer for cixmini.

2. `cix-gst-plugins-cix_*.bb` — the four `libgstcix*` plugins,
   either as part of the gstreamer recipe's PACKAGES split or
   as a separate recipe pulling from the same source tree.

3. `cix-gst-onnx-plugin_*.bb` — the gst-plugins-bad/ext/onnx
   subproject as a standalone recipe.

4. Updates to nclawzero-image-cixmini.bb to pull cix-gstreamer
   in via IMAGE_INSTALL when the multimedia variant is requested
   (gated behind a DISTRO_FEATURE or PACKAGECONFIG so headless
   agent images don't drag in 200 MB of multimedia).

5. RDEPENDS chain wiring: cix-gstreamer plugins → cix-vpu-umd
   (firmware) and cix-audio-dsp (codec libs).

Estimated effort: 1-2 days of focused recipe authoring + Codex
review iteration. Not a tonight-overnight slice.

## See also

- `recipes-extended/cix-ai-tools/cix-ai-tools.inc` — pattern for
  ext_debs-based bin_package recipes (would NOT work for
  cix-gstreamer since it's not in ext_debs)
- `recipes-bsp/cix-userspace/cix-userspace.inc` — pattern for
  cix_proprietary-based bin_package recipes
- `component/cix_opensource/gstreamer/` in the synced source tree on
  ARGOS — full Cix-fork source available for the future S6 build
