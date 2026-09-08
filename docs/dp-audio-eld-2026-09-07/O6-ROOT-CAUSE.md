# O6 audio registration: ACPI backlight dependency blocks DP02

Status: source fix 0232 implemented; hardware validation pending. 0231 remains a separate disconnected-port ELD warning fix.

## Evidence from the supplied O6 capture

`devices_deferred.txt`:

```
CIXH5040:00 platform: supplier CIXH5041:00 not ready
CIXH502F:02 platform: supplier CIXH5040:00 not ready
CIXH6070:00
```

The boot journal repeatedly prints `num_links = 5`, dp[0] and dp[1], then retries. The final attempt logs dp[1] at 20.191353 seconds and the three deferred devices above at 20.192483, 20.193606 and 20.194719 seconds. This is deferred registration, not evidence of a thread hung inside the parser.

The ACPI/platform inventory shows:

- All five DP/I2S pairs enabled and all five I2S controllers bound.
- DP00, DP01, DP03 and DP04 bound, each with an HDMI codec child.
- DP02 (CIXH502F:02) unbound, with no codec child.
- EDP0 (CIXH5040:00) and DPBL (CIXH5041:00) present but unbound.
- PWM0 (CIXH2011:00) present and bound to pwm-sky1.
- CONFIG_BACKLIGHT_PWM=m and CONFIG_PWM_SKY1=y. pwm_bl is not loaded.

O6N's capture instead reports status=0 for DP02/I2S7 and DP03/I2S8. Its three-link count is therefore explained by its firmware's reported topology; no kernel version explanation is needed for that difference.

`iasl -da DSDT SSDT1 SSDT2` on the captured raw tables confirms DPBL has HID CIXH5041, status 15, enable-gpios, `pwms = { PWM0, 0, 100000 }`, 255 brightness values (0..254), and default index 200. EDP0 references DPBL through `backlight`. PWM core's ACPI consumer path already accepts the two numeric PWM arguments (channel and period).

The actual 7.2.3 do_patch source lacks both pwm_bl's CIXH5041 ACPI match and its firmware-property parser. Its parser requires dev->of_node. Merely forcing driver binding would still fail. Legacy Sky1 patches 0065 and 0080 contain these missing backlight portions, but they are outside this recipe's applied 7.2 series.

The audio parser counts present pairs before resolving each codec. DP02 has no codec, so the third resolution returns -EPROBE_DEFER. sky1-card suppresses that errno's log and cannot register a partial card. The supplier chain explains why four probed DP ports can yield zero Sky1 PCM devices.

## Implemented fix

0232 restores CIXH5041 matching and reads brightness properties through the generic device-property API. The parser and default-brightness helper compile with ACPI even without OF. CIX ACPI backlights preserve the observed initial power state so the eDP panel controls enable timing. DT matching, interpolation and platform-data support remain available.

No ACPI status overrides, dropped audio links, or eager ELD probes are involved. No O6 runtime changes were performed.

The missing supplier support is established in the inspected build source; the archive does not contain O6's pwm_bl.ko or modules.alias. Thus it cannot independently establish whether O6's installed backlight module also lacks the alias, is absent, or is prevented from loading. If the candidate still leaves DPBL unbound, capture `modinfo pwm_bl`, `modprobe -n -v pwm_bl`, the CIXH5041 entry from modules.alias, and the new deferred-probe journal before changing anything further.

## Provenance

Captured module files match all five loaded build IDs:

| Module | Build ID |
|---|---|
| trilin_dpsub | aa5e84b4fef72a6b30b21f14f3e129683784b785 |
| linlon_dp | 600697082878406db2a2b7d74c9b153e8e735918 |
| snd_soc_sky1_sound_card | f5b3a03e97ad2004e3bbff98f3b511052ae08df2 |
| snd_soc_hdmi_codec | 2295f28e159c07b4e4809e8764e8700ba2eabb4b |
| snd_soc_cdns_i2s_mc | 23c723b2af5c7a1db743e0663b233dea505529d1 |

This validates the files as evidence of loaded code, not an exact meta-cix commit attribution. O6's banner is 7.2.3; O6N's is 7.2.4+r264. The latter's exact source commit is still unknown.

## Hardware acceptance

After complete release gates and explicit operator supervision, boot O6N in both Mali and Panthor entries with the rescue entry retained. Check backlight/panel binding, DRM/ASoC registration, connected-port playback and disconnected-port rejection. O6N does not reproduce the five-link dependency because its firmware disables DP02. Confirming O6's actual recovery therefore requires a later authorized maintenance window on O6, or another five-link test target; O6N success alone cannot establish it.

Additional read-only O6N check: installed 7.2.4 pwm_bl has only the platform and OF aliases; modules.alias has no CIXH5041 entry. A dry-run named modprobe resolves its existing module file. This confirms the omission in O6N's shipped binary independently of the branch source. O6's matching check remains requested.

## Build validation

The full kernel build passed (904 tasks, 880 reused), and 0232 passed checkpatch with zero errors/warnings. Existing series/buildpath warnings remain. The actual do_patch source matches the reviewed file byte for byte; the resulting module advertises acpi*:CIXH5041:*.

The isolated r268audio release completed, including Mali, Panthor built against exact staged headers, KVM/ABI gates, packages and manifest validation. Extracted final packages contain both GPU stacks and the fixed PWM driver. Native host-tool preparation, including the helper shipped in the headers package, preserved all 7,410 header/config/symbol hashes. See RELEASE-VALIDATION.md for exact artifacts, checks, build-flow fixes, the existing VPU manifest warning and trial side effects.

O6N's latest read-only preflight returned No route to host. No candidate was installed and no board rebooted. Supervised tests of both GPU entries remain pending, followed by an authorized five-link hardware test to establish O6 recovery.
