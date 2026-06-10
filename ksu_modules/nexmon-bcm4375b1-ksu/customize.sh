#!/system/bin/sh

ui_print "- Nexmon BCM4375B1 firmware overlay"
ui_print "- Device: $(getprop ro.product.model) / $(getprop ro.product.device)"
ui_print "- Android SDK: $(getprop ro.build.version.sdk)"
ui_print "- Target firmware: BCM4375B1 18.41.117 STA"
ui_print "- Patched firmware hash: 166f05c93ddb7d48687f4a8998197029472d5712665163e4eef5accfe2b86935"
ui_print "- Kernel requirement: bcmdhd monitor driver commit a5dee55c or newer"

check_firmware_hash() {
  path="$1"

  if [ ! -f "$path" ] || ! command -v sha256sum >/dev/null 2>&1; then
    return
  fi

  current_hash="$(sha256sum "$path" | awk '{print $1}')"
  case "$current_hash" in
    1676f46ce56b96f58dc70de08beaab4ab3362ee6dd751465a8d6a0023c3c54ad)
      ui_print "- $path matches known stock c2s BCM4375B1 18.41.117"
      ;;
    c406c39b2e7cc5aa3cdd92146ef13bc5a048c8c513791652013f141bce60cac6|\
    de9fd20ba2eabfd463fbec695f0048a3f3da927ba34250ea0d93153d6f7c0b98|\
    fe7052c25246be229d0d11447fdd856c6f951ea4012146f595eb408f02ef336d)
      ui_print "- $path appears to be an earlier Nexmon BCM4375B1 build"
      ;;
    166f05c93ddb7d48687f4a8998197029472d5712665163e4eef5accfe2b86935)
      ui_print "- $path already matches this retune firmware"
      ;;
    *)
      ui_print "! $path hash is not one of the known BCM4375B1 18.41.117 hashes"
      ui_print "! Continuing because this KernelSU module is systemless and removable"
      ;;
  esac
}

check_firmware_hash /vendor/etc/wifi/bcmdhd_sta.bin_b1
check_firmware_hash /vendor/etc/wifi/bcmdhd_sta.bin
check_firmware_hash /vendor/firmware/bcmdhd_sta.bin_b1
check_firmware_hash /vendor/firmware/bcmdhd_sta.bin

set_perm_recursive "$MODPATH/system" 0 0 0755 0644

ui_print "- Reboot is required for the built-in bcmdhd driver to load this firmware"
