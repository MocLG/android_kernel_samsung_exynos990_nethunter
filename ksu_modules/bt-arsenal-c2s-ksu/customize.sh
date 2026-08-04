#!/system/bin/sh

ui_print "- NetHunter internal Bluetooth mode switch"
ui_print "- Device: $(getprop ro.product.model) / $(getprop ro.product.device)"
ui_print "- Android SDK: $(getprop ro.build.version.sdk)"
ui_print "- Kernel requirement: hci_sock.c restore, commit 28ba5964 or newer"

if [ -d /sys/class/bluetooth ]; then
  ui_print "- /sys/class/bluetooth present, Bluetooth socket layer is live"
else
  ui_print "! /sys/class/bluetooth missing, kernel may predate the hci_sock restore"
fi

for tty in /dev/ttySAC1 /dev/ttySAC0 /dev/ttySAC2 /dev/ttySAC3; do
  [ -c "$tty" ] && ui_print "- Found $tty"
done

hcd=""
for f in /vendor/firmware/*.hcd /vendor/etc/bluetooth/*.hcd; do
  [ -f "$f" ] && { hcd="$f"; break; }
done
if [ -n "$hcd" ]; then
  ui_print "- Found patchram firmware: $hcd"
else
  ui_print "! No .hcd patchram firmware found in the usual vendor paths"
  ui_print "! Run 'btmode detect' after boot and set BTMODE_HCD if needed"
fi

set_perm_recursive "$MODPATH/system" 0 0 0755 0755

ui_print "- Installed: btmode {detect|nethunter|android|status}"
ui_print "- Default stays Android Bluetooth, nothing changes until you switch"
