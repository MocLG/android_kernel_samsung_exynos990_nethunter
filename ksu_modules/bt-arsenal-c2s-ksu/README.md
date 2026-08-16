# NetHunter Internal Bluetooth Mode Switch

Gives Bluetooth Arsenal access to the phone's own BCM4375B1 instead of requiring
a USB dongle, without permanently breaking Android Bluetooth.

## Why a switch is needed

The internal chip sits on Samsung UART1 (`/dev/ttySAC1`). Android's Bluetooth
stack (Fluoride + libbt-vendor) drives it entirely from userspace and never
registers a kernel HCI device, which is why no `hciX` exists on a stock kernel.
The in-tree `drivers/bluetooth/bcm43xx.c` only manages the power and wake GPIOs
via rfkill — it does not implement HCI.

To get an `hci0`, the UART has to be handed to the kernel's HCI line discipline
instead. Only one stack can own the UART at a time, so Android Bluetooth and
NetHunter Bluetooth are mutually exclusive. This module switches between them.

The alternative — binding the UART in-kernel with serdev and `hci_bcm` — would
make `hci0` appear automatically at boot, but it takes the UART away from
Android's stack permanently and needs device-tree changes, since the `bluetooth`
node is a standalone platform device rather than a serdev child of the UART.
That is not switchable, so it is deliberately not what this does.

## Requirements

- A kernel with the restored HCI socket layer (commit `28ba5964` or newer).
  Without it, any BlueZ tool panics the kernel.
- `CONFIG_BT_HCIUART=y`, `CONFIG_BT_HCIUART_H4=y`, and `CONFIG_BT_HCIUART_BCM=y`.
  The last one needs `CONFIG_SERIAL_DEV_BUS=y`: it `depends on
  BT_HCIUART_SERDEV`, and without the bus Kconfig drops it **silently**, leaving
  `btattach -P bcm` to fail with `Protocol not supported`.
- `btattach` in the NetHunter chroot (part of BlueZ) or on Android.
- The BCM4375B1 patchram blob, bundled with this module.

## How the chip gets its firmware

The BCM4375B1 boots into a ROM firmware that answers HCI commands but cannot
transmit or receive: BD address `AA:AA:AA:AA:AA:AA`, `HCI Revision 0x0`, and
every scan comes back empty. A patchram blob has to be downloaded first.

This module does **not** load that blob itself. BlueZ's `hciattach bcm43xx`
handler cannot parse Samsung's `.hcd` files — it times out mid-download and
leaves the chip wedged until a power cycle. The kernel's own `btbcm.c` can, so
`btmode` attaches with `btattach -P bcm` and lets `btbcm_setup_patchram()` do it.

Three details that are easy to get wrong:

1. The kernel asks for `brcm/<hw_name>.hcd`, where `hw_name` comes from a
   subversion lookup in `bcm_uart_subver_table`. The BCM4375B1 reports `0x1111`,
   which is not in that table, so `hw_name` falls back to the literal `BCM` —
   the file must be named **`BCM.hcd`**, not `BCM4375B1.hcd`.
2. `firmware_class.path` must be written with `printf`, never `echo`. The sysfs
   store hands the buffer straight to `param_set_copystring()` with no newline
   stripping, so `echo` bakes a `\n` into every path the loader then builds.
3. The blob must be readable by the kernel domain under SELinux.
   `/vendor/firmware` content is `vendor_firmware_file` and works; a copy under
   `/data` is `vendor_data_file` and fails the open with `EACCES` (`-13`). This
   module overlays the blob into `/vendor/firmware/brcm/` for that reason.

Patchram runs from `hdev->setup()`, which the kernel calls only while the
`HCI_SETUP` flag is set — once per registration. `hciconfig hci0 down; hciconfig
hci0 up` will **not** reload it; a retry has to detach and re-attach.

Samsung keeps the real BD address in `/mnt/vendor/efs/bluetooth/bt_addr` and
writes it from the vendor HAL, which this bypasses, so `btmode` writes it itself
with the Broadcom vendor command `0xFC01`.

## Where it runs

`btmode` installs to `/system/bin` through the module overlay, which puts it on
`PATH` for any **Android** root shell — `adb shell su`, Termux, or the NetHunter
Terminal's *AndroidSu* session.

**Run it from the Android shell, not from inside the Kali chroot.** It drives
`svc`, `setprop` and `getprop`, which need Android's property service and
runtime and do not work under the chroot.

That is not a limitation in practice, because `hci0` is **global kernel state**,
not a file. Once `btmode nethunter` brings it up from the Android side, BlueZ
tools inside the chroot see it immediately over `AF_BLUETOOTH`. Nothing has to
be shared between the two filesystems for Arsenal to work — switch mode in the
Android shell, then use `hciconfig`, `hcitool` and the rest from the Kali shell
as normal.

The reverse direction matters too: BlueZ itself normally lives in the chroot,
and those binaries are glibc-linked. They cannot be executed directly from
Android, which has neither their loader nor their libraries, so `btmode` invokes
them through `chroot(8)`. It autodetects the rootfs and falls back to a native
`btattach` if one exists.

The patchram blob is *not* subject to that split. The kernel loads it, not
BlueZ, so it is resolved against Android's filesystem regardless of where
`btattach` lives — which is why it ships at `/vendor/firmware/brcm/BCM.hcd`
rather than inside the chroot. `btmode detect` reports the path it found and the
value currently in `firmware_class.path`.

## Usage

```
btmode detect      # report what was found, change nothing
btmode nethunter   # hand the UART to BlueZ, bring up hci0
btmode android     # hand it back to Android's stack
btmode status      # which mode is active right now
```

Start with `btmode detect`. It prints the UART, the rfkill switch and its power
state, the HAL service name, the `btattach` binary, the patchram blob, the live
`firmware_class.path`, the BD address, the HCI revision, and anything currently
holding the UART — without touching any of them.

Anything it fails to autodetect can be forced:

```
BTMODE_TTY=/dev/ttySAC1 \
BTMODE_CHROOT=/data/local/nhsystem/kali-arm64 \
BTMODE_FWDIR=/vendor/firmware \
BTMODE_BDADDR=BC:7A:BF:FE:EA:1B \
btmode nethunter
```

`BTMODE_FWDIR` is a **directory**, not a file: the kernel appends
`brcm/BCM.hcd` to it. `BTMODE_BTATTACH` forces a native Android binary and
bypasses the chroot entirely.

## Notes

- Default is Android mode. Installing this module changes nothing until you
  explicitly switch.
- If `btmode android` leaves Bluetooth greyed out, toggle it in Settings — the
  framework sometimes needs a nudge after the HAL restarts.
- Turn Bluetooth off in Settings before `btmode nethunter` for the cleanest run.
  The HAL is restarted by `hwservicemanager` on demand, and its exit path drives
  `BT_REG_ON` low, so a respawn racing the attach can leave the chip unpowered —
  `BCM: Reset failed (-110)` in dmesg. `btmode` retries around this, but not
  needing to is faster.
- Everything is recoverable with a reboot; nothing here is persistent.
- A USB Bluetooth dongle remains the more reliable option and needs none of
  this — `btusb` registers `hci0` on its own.
