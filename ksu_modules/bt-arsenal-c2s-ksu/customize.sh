#!/system/bin/sh

ui_print "- NetHunter internal Bluetooth mode switch"
ui_print "- Device: $(getprop ro.product.model) / $(getprop ro.product.device)"
ui_print "- Android SDK: $(getprop ro.build.version.sdk)"
ui_print "- Kernel requirements:"
ui_print "    hci_sock.c restore, commit 28ba5964 or newer"
ui_print "    CONFIG_BT_HCIUART_BCM=y (needs CONFIG_SERIAL_DEV_BUS=y)"

if [ -d /sys/class/bluetooth ]; then
  ui_print "- /sys/class/bluetooth present, Bluetooth socket layer is live"
else
  ui_print "! /sys/class/bluetooth missing, kernel may predate the hci_sock restore"
fi

if [ -e /sys/module/firmware_class/parameters/path ]; then
  ui_print "- firmware_class.path is settable, patchram can be located"
else
  ui_print "! /sys/module/firmware_class/parameters/path missing"
  ui_print "! the kernel cannot be pointed at the patchram blob"
fi

for tty in /dev/ttySAC1 /dev/ttySAC0 /dev/ttySAC2 /dev/ttySAC3; do
  [ -c "$tty" ] && ui_print "- Found $tty"
done

# The blob this module overlays. It is named BCM.hcd rather than BCM4375B1.hcd
# because the kernel derives the name from a subversion lookup that does not
# know 0x1111 and falls back to the literal "BCM" - see the note in btmode.
if [ -f "$MODPATH/system/vendor/firmware/brcm/BCM.hcd" ]; then
  ui_print "- Bundled patchram: /vendor/firmware/brcm/BCM.hcd"
else
  ui_print "! Bundled patchram missing, the chip will run unpatched ROM firmware"
fi

set_perm_recursive "$MODPATH/system" 0 0 0755 0644
set_perm "$MODPATH/system/bin/btmode" 0 0 0755

# The kernel's firmware loader reads with kernel credentials. Files inheriting a
# data context are refused with EACCES; /vendor/firmware content is
# vendor_firmware_file, which it can read. Match that or the download fails.
if [ -f "$MODPATH/system/vendor/firmware/brcm/BCM.hcd" ]; then
  if chcon u:object_r:vendor_firmware_file:s0 \
      "$MODPATH/system/vendor/firmware/brcm/BCM.hcd" 2>/dev/null; then
    ui_print "- Labelled patchram vendor_firmware_file"
  else
    ui_print "! Could not set SELinux label on the patchram blob"
    ui_print "! If firmware load fails with -13, that is why"
  fi
fi

ui_print "- Installed: btmode {detect|nethunter|android|status}"
ui_print "- Default stays Android Bluetooth, nothing changes until you switch"
