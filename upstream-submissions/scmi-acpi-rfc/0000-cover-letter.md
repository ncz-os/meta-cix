# [RFC PATCH 0/2] firmware: arm_scmi: activate + channel-setup protocols on ACPI

**To:** Sudeep Holla <sudeep.holla@arm.com> (ARM SCMI maintainer),
Cristian Marussi <cristian.marussi@arm.com>
**Cc:** arm-scmi@vger.kernel.org, linux-arm-kernel@lists.infradead.org,
linux-kernel@vger.kernel.org
**From:** Jason Perlow <jperlow@gmail.com>

## The gap

The arm_scmi core enumerates protocols from **DT child nodes**:
`scmi_probe()` walks one child-per-protocol under the SCMI node and calls
`scmi_txrx_setup()` + `scmi_create_protocol_devices()` for each.

On **ACPI** platforms this model does not hold. The ACPI description names
the SCMI transport (mailbox / shared memory), but it does **not** enumerate
a child object per SCMI protocol — the protocol set is discovered at runtime
from the firmware via `BASE_DISCOVER_LIST_PROTOCOLS`. Consequently, on ACPI
today:

1. The DT child loop activates **nothing** — no protocol devices are created,
   so no consumer driver (clocks, perf, power domains, hwmon, reset) binds.
2. Even once protocols are activated, each protocol device is created
   **without a Tx/Rx channel**. A protocol with no `info->tx_idr` entry gets
   `-EINVAL` from `do_xfer()` on every transfer (there is no Base-channel
   fallback outside RAW mode), so it is silently non-functional.

The second failure is the nastier one: `SCMI_PROTOCOL_POWER` (0x11) registers
no power domains, and genpd consumers then touch unpowered MMIO. On an arm64
ACPI test platform this manifested as a multi-second AXI lock (GPU / NPU /
display blocks powered by SCMI genpd) before the watchdog recovered.

## This series

- **1/2** — after the DT child scan, if the SCMI fwnode is an ACPI node,
  activate every protocol the firmware reports as *implemented* (skipping
  unimplemented ids, which can wedge some SCP firmwares).
- **2/2** — for each ACPI-activated protocol, call
  `scmi_txrx_setup(info, NULL, prot_id)` before creating its device, so the
  protocol is aliased onto the Base channel and `do_xfer()` works.

Both changes are gated on `is_acpi_node(np)`; the DT path is untouched.

## Questions for the maintainers (why this is an RFC)

1. **Is Base-channel aliasing the right model?** These platforms expose a
   single shared SCMI transport for all protocols. Passing a NULL fwnode to
   `scmi_chan_setup()` takes the Base-channel alias path. Would you prefer the
   ACPI firmware describe per-protocol channels instead (and, if so, is there
   an agreed ACPI binding for that)?
2. **Discovery placement** — is `scmi_probe()` the right place for the
   firmware-driven activation fallback, or would you rather see it behind a
   transport/OF-vs-ACPI abstraction?
3. Should the activation range be the full `0x01..0xFF` id space (as here) or
   restricted to the currently-known protocol ids?

Tested on a Cadence/CIX Sky1-class arm64 ACPI SoC (SCMI over mailbox +
shared memory); clocks, perf, power-domains, hwmon and reset all come up with
the series applied, and the genpd AXI-lock hang is gone.

Happy to respin against whatever shape you prefer.
