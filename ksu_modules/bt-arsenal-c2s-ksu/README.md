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
- `CONFIG_BT_HCIUART=y` and `CONFIG_BT_HCIUART_H4=y` — both already in the
  NetHunter defconfig.
- `hciattach` with `bcm43xx` vendor support, either in `/system/bin` or in the
  NetHunter chroot.
- The BCM4375B1 patchram blob (`.hcd`) that `hciattach` downloads to the chip.

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
`hciattach` if one exists.

One consequence worth knowing: when BlueZ runs inside the chroot it resolves
firmware against the *chroot's* root, so the `.hcd` patchram blob needs to be at
`/lib/firmware` **inside the chroot**, not in Android's `/vendor/firmware`.
`btmode detect` reports which one it found and which root the path is relative
to.

## Usage

```
btmode detect      # report what was found, change nothing
btmode nethunter   # hand the UART to BlueZ, bring up hci0
btmode android     # hand it back to Android's stack
btmode status      # which mode is active right now
```

Start with `btmode detect`. It prints the UART, the rfkill switch, the HAL
service name, the `hciattach` binary, the patchram blob, and anything currently
holding the UART — without touching any of them.

Anything it fails to autodetect can be forced:

```
BTMODE_TTY=/dev/ttySAC1 \
BTMODE_CHROOT=/data/local/nhsystem/kali-arm64 \
BTMODE_HCD=/lib/firmware/BCM4375B1.hcd \
btmode nethunter
```

`BTMODE_HCD` is interpreted the way BlueZ will see it — chroot-relative when
BlueZ runs in the chroot. `BTMODE_HCIATTACH` forces a native Android binary and
bypasses the chroot entirely.

## Notes

- Default is Android mode. Installing this module changes nothing until you
  explicitly switch.
- If `btmode android` leaves Bluetooth greyed out, toggle it in Settings — the
  framework sometimes needs a nudge after the HAL restarts.
- Everything is recoverable with a reboot; nothing here is persistent.
- A USB Bluetooth dongle remains the more reliable option and needs none of
  this — `btusb` registers `hci0` on its own.
