# O6 registration stall: capture and current facts

The O6 card-registration failure is the priority. 0231 addresses disconnected-port warning noise only.

Download collect-sky1-audio.sh to the machine with O6 access and run:

```bash
ssh jperlow@2601:601:780:b412:248:54ff:fe20:1ae8 \
  'sudo -n bash -s' < collect-sky1-audio.sh > o6-audio-evidence.tar.gz
```

The collector was exercised on O6N. It requires bash, Python 3 and sudo; it does not require acpidump. It copies raw DSDT/SSDT and other ACPI tables directly from sysfs. It changes no kernel controls, drivers, services or mounts and writes/removes only its own temporary capture directory. It captures installed DP/ASoC modules and loaded build IDs so source assumptions can be checked. Missing optional debugfs files are recorded, not mounted.

## What the real source requires

For DP index i, cix_acpi_dp_audio_check_present requires both `\\_SB.I2S(i+5)` and `\\_SB.DP0i` to have ACPI present status. The parser counts these pairs before resolving platform devices and codec children. For each present pair it then requires:

1. I2S platform device.
2. DP platform device with a child named hdmi-audio-codec (not an arbitrary i2c child).
3. Bound I2S and codec suppliers, after device links are established.

The dp[i] log appears only after these resolutions and supplier checks. After dp[1], the next expected pair is I2S7/DP02 if present. A missing provider/codec can return -EPROBE_DEFER silently: sky1-card.c suppresses logging that errno. A blocked device-lock acquisition is another possibility, hence task states/stacks in the capture. HDMI-codec registration happens at the end of trilin_dp_probe(), called by the DRM component bind callback. That callback can return -EPROBE_DEFER before codec creation if encoder->possible_crtcs is zero. Therefore a bound DP platform driver alone does not prove an audio codec exists; component-binding and DRM state are included in the capture. No cause is selected without O6 evidence; do not drop declared links to hide a missing supplier.

## Measured O6N ACPI baseline

| Pair | DP ACPI ID | I2S ACPI ID | Both status | Physical devices |
|---|---|---|---|---|
| DP00 / I2S5 | CIXH502F:00 | CIXH6011:02 | 15 | present and bound |
| DP01 / I2S6 | CIXH502F:01 | CIXH6011:03 | 15 | present and bound |
| DP02 / I2S7 | CIXH502F:02 | CIXH6011:04 | 0 | absent |
| DP03 / I2S8 | CIXH502F:03 | CIXH6011:05 | 0 | absent |
| DP04 / I2S9 | CIXH502F:04 | CIXH6011:06 | 15 | present and bound |

All three present DP devices have bound hdmi-audio-codec children. This directly explains O6N's three DP links. It does not establish O6's topology; that comparison awaits its archive.

## Provenance follow-up

On O6N (.3), neither /home/mini nor /root contains the reported Yocto checkout; no matching checkout was found under /mnt, /media, /opt or /srv at the inspected depth, and git is not installed. Running 7.2.4+r264 is accepted as fact, but its exact source commit remains unknown.

Loaded build IDs match the installed modules:

- trilin_dpsub: 939d7a6450911b88cec3cd17fe300b3748392cab
- snd_soc_sky1_sound_card: 688dd26b8786f1a13d5f7449c89e3a3356ce548d
- snd_soc_hdmi_codec: d93c99e2a0b6a01950f559e397e475bbe55ec98d
- snd_soc_cdns_i2s_mc: eada6d6baca18f2c5181db9a9357b85db5e8c4bc
- linlon_dp: e40cd0135e0e96600ae38e684b7fa4e4320ab2f2

The running card module includes cix_card_link_supplier and cix_dp_match_hdmi_codec symbols. The DP module contains the ELD callback and modern EDID helper symbols.

Main's version discrepancy is not just its LINUX_VERSION label: its SRCREV dc59e4fea9d83f03bad6bddf3fa2e52491777482 resolves to v7.2-rc1, with EXTRAVERSION=-rc1 in that commit's Makefile. This does not override O6N's 7.2.4 banner; it means the target cannot be attributed to unmodified current main from the available evidence.

## Build continuation

The operator supplied the applicable checklist requirements: exact staged headers via --kernelsourcedir, all assets staged together, rescue retained, and supervised tests of both Mali and Panthor entries.

ULTRA had neither DKMS installed nor a registered Panthor module. release-kernel.sh has no registration path before step 4b; a full run cannot bootstrap this by itself. DKMS was installed using password-authenticated sudo (no sudoers changes), and panthor-cix/7.2.0 was registered from cix-installer's existing assets/kernel/panthor sources using the package script's source-cleaning convention. Build/install remain delegated to release-kernel.sh's exact staged-header path. The r267eld full run passed kernel/Mali builds and, under non-interactive SSH with stdin closed, KVM/ABI gates. An earlier PTY invocation timed out with an empty QEMU log despite an identical Image; the non-PTY recheck passed.

Step 4b then failed on missing `scripts/basic/fixdep` in the exact staged headers. The extractor strips foreign host binaries, but the release script does not perform native host-tool preparation before DKMS. The log also records host GCC 16.2.1 versus OE GCC 15.3.0. Native host-tool preparation exists in build-kernel-debs.sh's headers postinst, but it is not run by step 4b. Do not substitute generic headers or ignore the build failure. No Panthor module was installed by this attempt and no candidate was installed on O6N.

Concurrent changes appeared in ULTRA's installer tree during this run: an r264/7.2.4 asset directory and edits to build/stage-canonical-assets.sh. Before the final staging step, edge pointed to r264. After the failed run, edge was restored to that observed r264 target, preserving the other operator's changes. Coordinate further shared installer work before altering its pipeline. Failure logs are in evidence/ultra-release-r267.log and evidence/ultra-panthor-r267-make.log.
