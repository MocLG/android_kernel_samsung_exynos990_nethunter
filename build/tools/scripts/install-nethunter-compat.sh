#!/sbin/sh

BB=/tmp/scripts/busybox
SRC=/tmp/scripts/nethunter-usb-arsenal-compat.sh
DST=/data/adb/service.d/nethunter-usb-arsenal-compat.sh
USERDATA=/dev/block/bootdevice/by-name/userdata

mount_data()
{
	grep -q ' /data ' /proc/mounts && return 0

	mkdir -p /data
	$BB mount -t f2fs "$USERDATA" /data 2>/dev/null && return 0
	$BB mount -t ext4 "$USERDATA" /data 2>/dev/null && return 0
	mount -t f2fs "$USERDATA" /data 2>/dev/null && return 0
	mount -t ext4 "$USERDATA" /data 2>/dev/null && return 0

	return 1
}

[ -x "$BB" ] || exit 0
[ -f "$SRC" ] || exit 0

if mount_data && [ -d /data/adb ]; then
	mkdir -p /data/adb/service.d
	cp "$SRC" "$DST"
	chown 0:0 "$DST" 2>/dev/null
	chmod 0755 "$DST"
	$BB sh "$DST" 2>/dev/null
fi

exit 0
