# Sky1 DP audio investigation — 2026-09-07

Status: connected-port ELD failure is **not reproduced on O6N**. Audible output and boot/hotplug ordering remain unverified. No board reboot, kernel installation, driver reload, or O6 access performed.

## Measured on O6N

Running kernel: `7.2.4-sky1-ncz`, image/headers package `7.2.4-sky1-ncz+r264`.

| PCM | ACPI DP link | Codec | Jack | ELD |
|---|---|---|---|---|
| 0 | dp[0] | hdmi-audio-codec.11.auto | off | zero |
| 1 | dp[1] | hdmi-audio-codec.12.auto | on | version 2, VP2488-4K, LPCM stereo |
| 2 | dp[4] | hdmi-audio-codec.13.auto | off | zero |

The connected monitor advertises 32/44.1/48/88.2/96 kHz, 16/20/24 bits. This is O6N's own EDID/ELD evidence, not the supplied O6 EDID.

Direct ALSA silent playback on hw:0,1 reached:

```
state: RUNNING
format: S16_LE
channels: 2
rate: 48000 (48000/1)
hw_ptr: 42000
```

A controlled same-session comparison:

1. Snapshot latest kernel warning at monotonic 534.197638.
2. Open disconnected hw:0,0 with a two-second silent stream.
3. New `.11` ELD-zero warning at 537.360072.
4. Open connected hw:0,1 with the same stream.
5. No additional warning; latest line still 537.360072.

See `evidence/o6n-disconnected-vs-connected.txt` and `evidence/o6n-pcm1-silence.txt`. Timeout termination of these bounded streams is intentional. Silent playback proves PCM operation, **not audible sound**.

The full baseline contains 36 ELD-zero warnings, all from disconnected codecs .11/.13; none from .12. ALSA exposes valid ELD in `/proc/asound/card0/eld#1` and the PCM 1 ELD mixer control. Missing DRM connector `eld` sysfs files is not a valid criterion for this ASoC path.

PipeWire autoswitch selects `ncz_sky1_hdmi_0_1`. With no persistent desktop session, SSH causes mini's user manager/audio services to start and later stop. Startup probes disconnected ports and adds warnings. A brief early snapshot can show only Dummy Output while services initialize.

The installed DP module contains `dptx_audio_get_eld`, `drm_edid_read`, `drm_edid_connector_update`, and `drm_edid_connector_add_modes` symbols. On-disk symbols alone do not establish exact loaded-module provenance, but the valid live ELD also contradicts the claim that the board has no working ELD callback.

## Real source and hypothesis

ULTRA source was refreshed successfully with:

```
~/yocto-work/y6-run-ultra.sh "bitbake -c patch linux-cix-sky1-ncz"
```

Layer base: `6eac8a7d0a822126e2a1b5b7759a38939123f521`.
Source: `~/ybuild/tmp/work/cixmini-nclawzero-linux/linux-cix-sky1-ncz/7.2.3+ncz/kernel-source`.
The original pre-refresh working tree had 0223/0226 but lacked 0229, illustrating why refreshing do_patch mattered.

In this source:

- `drm_edid_connector_update()` updates display info and builds ELD.
- **The legacy path also builds ELD in this kernel.** `drm_connector_update_edid_property()` delegates to `drm_edid_connector_update()` (drm_edid.c:7215), and `drm_add_edid_modes()` calls `update_display_info()` (drm_edid.c:7245), which calls `drm_edid_to_eld()` (drm_edid.c:6857). Thus 0226's claim that the legacy path cannot populate ELD is false for this real source. Its measured lack of improvement does not demonstrate an ordering bug. See `evidence/source-api-excerpts.txt`.
- `trilin_dp_plugged_status()` is simply `dp->status == connector_status_connected`.
- HPD work performs detect, returns early for unchanged status, issues DRM hotplug handling, then calls the audio plug callback.
- The hook-registration callback immediately reports current DP status.
- hdmi-codec calls get_eld in both plugged_cb and **every playback startup**. It is not a one-shot read permanently cached until reboot.
- Disconnected `dptx_audio_startup()` returns success; get_eld returns zero bytes; hdmi-codec then parses those bytes and logs the warning. This matches the live reproduction.

An early notification before mode probing remains possible, but cannot by itself explain permanent ELD failure across later PCM opens. No eager mode probe or notification-order fix is justified by current observations.

## Changes

Branch: `wip/gpt6astra/2026-09-07-dp-audio-eld`, based on the requested wip/ultra branch.

- **0230**: regenerated diagnostic logs for mode reads, no-EDID failure, ELD update, codec notification, and get_eld raw/returned bytes, with device/connector identity and jiffies. Read bytes under eld_mutex and guard zero-length output. Wired into recipe for a diagnostic build only.
- **0231**: candidate returning -ENODEV from disconnected audio startup before hdmi-codec parses empty ELD. **Unwired and not hardware validated.** Does not claim to repair audible output or boot ordering. Connected startup stays unchanged; desktop probing/hotplug behavior needs regression testing.

The user's original sketch is retained unchanged. Both generated patches pass git apply --check against copies from successful do_patch and checkpatch.pl with zero errors/warnings. The source mirror resolves v7.2.3 to recipe SRCREV 58e7295cfecaddec94629160386412e0f2b1e8fe. Build/release status is recorded separately in the logs.

## Provenance and separate ACPI issue

After fetching origin, `origin/main` is b73472f and its 7.2 recipe declares `LINUX_VERSION = "7.2-rc1"`. The wip branch declares 7.2.3. Neither alone explains O6N's 7.2.4+r264 artifact; do not label it a demonstrated main build without its build record. No broad merge or main mutation was performed.

`cix_card_parse_acpi()` counts present ACPI I2S/DP pairs, then resolves each device/codec supplier. Thus num_links is topology-derived, not a fixed kernel constant. O6N currently registers dp[0], dp[1], dp[4]. A failure resolving the next supplier can leave a card unregistered after only two link messages. Establishing O6's specific cause requires its already-captured ACPI/deferred-probe evidence; no contact with O6 was attempted. Avoid dropping a declared link merely to make registration succeed.

## Required remaining validation

- Locate/read the full required kernel-build-checklist.md (absent on PROTEUS and ULTRA at the supplied path).
- Complete release gates; ULTRA currently lacks host DKMS and passwordless sudo, relevant to release-kernel.sh's panthor step.
- Reconcile target 7.2.4 provenance versus diagnostic branch 7.2.3 before selecting a supervised boot candidate.
- Coordinate installation/boot with Jason; keep known-good boot default. No unattended reboot.
- Capture diagnostic cold-boot and supervised hotplug ordering per connector.
- Test candidate 0231 connected/disconnected PCM behavior and autoswitch recovery.
- Obtain a human audible-output observation. ELD and running DMA alone cannot establish it.
