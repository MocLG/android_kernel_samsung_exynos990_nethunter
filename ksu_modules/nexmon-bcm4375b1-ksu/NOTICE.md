# Nexmon BCM4375B1 Firmware Overlay Notice

This KernelSU module contains patched BCM4375B1 18.41.117 firmware artifacts for Samsung Exynos990 NetHunter use.

The included firmware files are identical copies installed to multiple vendor firmware paths for device compatibility:

```text
166f05c93ddb7d48687f4a8998197029472d5712665163e4eef5accfe2b86935  system/vendor/etc/wifi/bcmdhd_sta.bin
166f05c93ddb7d48687f4a8998197029472d5712665163e4eef5accfe2b86935  system/vendor/etc/wifi/bcmdhd_sta.bin_b1
166f05c93ddb7d48687f4a8998197029472d5712665163e4eef5accfe2b86935  system/vendor/firmware/bcmdhd_sta.bin
166f05c93ddb7d48687f4a8998197029472d5712665163e4eef5accfe2b86935  system/vendor/firmware/bcmdhd_sta.bin_b1
```

Provenance:

- Nexmon framework, monitor mode, frame injection concepts, and `NEX_INJECT_FRAME` ABI: Nexmon team.
  https://github.com/seemoo-lab/nexmon
- Initial BCM4375B1 18.41.117 firmware patch support: 0xIO32 / Markus Probst.
  https://github.com/0xIO32/nexmon/commit/fd117f434e1c479f6819a0ba31f9ca82d75f8a3a
- Downstream BCM4375B1 18.41.117 bring-up and Samsung Exynos990/NetHunter integration used by this module: MocLG fork branch.
  https://github.com/MocLG/nexmon/tree/bcm4375b1_18_41_117_patch
