#!/system/bin/sh

NH_USB_ARSENAL=/data/data/com.offsec.nethunter/scripts/usbarsenal

[ -f "$NH_USB_ARSENAL" ] || exit 0

if grep -q '/sys/devices/virtual/android_usb/android0/enable' "$NH_USB_ARSENAL"; then
	cp -p "$NH_USB_ARSENAL" "$NH_USB_ARSENAL.nh-usb.bak" 2>/dev/null
	tmp="$NH_USB_ARSENAL.tmp.$$"

	if sed 's# -o -f /sys/devices/virtual/android_usb/android0/enable##' \
		"$NH_USB_ARSENAL" > "$tmp"; then
		cat "$tmp" > "$NH_USB_ARSENAL"
		chmod 0755 "$NH_USB_ARSENAL"
	fi

	rm -f "$tmp"
fi

exit 0
