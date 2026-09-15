#!/usr/bin/env python3
"""
Stage 5 thinning of config.sky1-next -- foreign WiFi chip vendor drivers.

Per README.md's driver table (authoritative, real-hardware-confirmed):
  Wi-Fi:     mt7921e (MediaTek MT7921/MT7922) -- confirmed loaded on MS-R1
  Wi-Fi alt: rtw88/rtw89 -- "if equipped" on O6/O6N/OrangePi M.2 slot

No other WiFi vendor is documented as used on any of the 4 boards. Real
ground truth on MS-R1 itself (lspci) confirms MT7922 [14c3:0616] is the
integrated chip. Cutting: iwlwifi (Intel), ath10k/ath11k/ath12k (Qualcomm
Atheros), mwifiex (Marvell), wlcore/wl18xx (TI), brcmfmac (Broadcom),
rsi_91x (Redpine). mt76/mt7921 family and rtw88/rtw89 family are left
completely untouched.
"""
import re
import sys

PATH = "config.sky1-next"

PROTECT_EXACT = set()

STAGE5 = [
    ("Foreign WiFi chip vendors (README-confirmed: only mt7921e + rtw88/89 are real on any board)", [
        r"^CONFIG_IWLWIFI",
        r"^CONFIG_IWLDVM",
        r"^CONFIG_IWLMVM",
        r"^CONFIG_ATH10K",
        r"^CONFIG_ATH11K",
        r"^CONFIG_ATH12K",
        r"^CONFIG_ATH_COMMON",
        r"^CONFIG_MWIFIEX",
        r"^CONFIG_WLCORE",
        r"^CONFIG_WL18XX",
        r"^CONFIG_WL12XX",
        r"^CONFIG_BRCMFMAC",
        r"^CONFIG_BRCMSMAC",
        r"^CONFIG_BRCMUTIL",
        r"^CONFIG_RSI_",
    ], []),
]

def load(path):
    with open(path) as f:
        return f.readlines()

def symbol_of(line):
    m = re.match(r"^(CONFIG_[A-Za-z0-9_]+)=(y|m)\s*$", line)
    if m:
        return m.group(1), True
    m = re.match(r"^# (CONFIG_[A-Za-z0-9_]+) is not set\s*$", line)
    if m:
        return m.group(1), False
    return None, None

def main():
    apply_changes = "--apply" in sys.argv
    lines = load(PATH)
    changes = []
    for i, line in enumerate(lines):
        sym, enabled = symbol_of(line)
        if not sym or not enabled:
            continue
        if sym in PROTECT_EXACT:
            continue
        for label, patterns, explicit in STAGE5:
            hit = sym in explicit or any(re.match(p, sym) for p in patterns)
            if hit:
                changes.append((i, sym, line.rstrip("\n"), label))
                break

    by_label = {}
    for i, sym, old, label in changes:
        by_label.setdefault(label, []).append(sym)

    print(f"=== Stage 5 dry-run: {len(changes)} symbols would be disabled ===\n")
    for label, syms in by_label.items():
        print(f"[{label}] {len(syms)} symbols:")
        print("  " + ", ".join(syms))
        print()

    if apply_changes:
        for i, sym, old, label in changes:
            lines[i] = f"# {sym} is not set\n"
        with open(PATH, "w") as f:
            f.writelines(lines)
        print(f"APPLIED: {len(changes)} lines changed in {PATH}")
    else:
        print("(dry run only -- pass --apply to write changes)")

if __name__ == "__main__":
    main()
