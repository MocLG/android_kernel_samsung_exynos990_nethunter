#!/system/bin/sh

NH_USB_ARSENAL=/data/data/com.offsec.nethunter/scripts/usbarsenal
LOG=/data/local/tmp/nethunter-usb-arsenal-compat.log

[ -f "$NH_USB_ARSENAL" ] || exit 0

tmp="$NH_USB_ARSENAL.tmp.$$"

if sed \
	-e 's# -o -f /sys/devices/virtual/android_usb/android0/enable##g' \
	-e 's#if \[ ! -e \$DIR_CUR_FUNCS/\$SYMLINK_FUNC_NAME \]; then#if [ ! -e $DIR_CUR_FUNCS/ffs.adb ]; then#g' \
	-e 's#ln -s \$DIR_ALL_FUNCS/ffs\.adb \$DIR_CUR_FUNCS/\$SYMLINK_FUNC_NAME#ln -s $DIR_ALL_FUNCS/ffs.adb $DIR_CUR_FUNCS/ffs.adb#g' \
	-e 's#ln -s \$DIR_ALL_FUNCS/hid\.0 \$DIR_CUR_FUNCS/\$SYMLINK_FUNC_NAME#ln -s $DIR_ALL_FUNCS/hid.0 $DIR_CUR_FUNCS/hid.0#g' \
	-e 's#ln -s \$DIR_ALL_FUNCS/hid\.1 \$DIR_CUR_FUNCS/\$SYMLINK_FUNC_NAME#ln -s $DIR_ALL_FUNCS/hid.1 $DIR_CUR_FUNCS/hid.1#g' \
	-e 's#ln -s \$DIR_ALL_FUNCS/\$REAL_MASS_STORAGE_NAME \$DIR_CUR_FUNCS/\$SYMLINK_FUNC_NAME#ln -s $DIR_ALL_FUNCS/$REAL_MASS_STORAGE_NAME $DIR_CUR_FUNCS/$REAL_MASS_STORAGE_NAME#g' \
	-e 's#ln -s \$DIR_ALL_FUNCS/\$REAL_RNDIS_NAME \$DIR_CUR_FUNCS/\$SYMLINK_FUNC_NAME#ln -s $DIR_ALL_FUNCS/$REAL_RNDIS_NAME $DIR_CUR_FUNCS/$REAL_RNDIS_NAME#g' \
	-e 's#ln -s \$DIR_ALL_FUNCS/acm\.usb0 \$DIR_CUR_FUNCS/\$SYMLINK_FUNC_NAME#ln -s $DIR_ALL_FUNCS/acm.usb0 $DIR_CUR_FUNCS/acm.usb0#g' \
	-e 's#ln -s \$DIR_ALL_FUNCS/ecm\.usb0 \$DIR_CUR_FUNCS/\$SYMLINK_FUNC_NAME#ln -s $DIR_ALL_FUNCS/ecm.usb0 $DIR_CUR_FUNCS/ecm.usb0#g' \
	"$NH_USB_ARSENAL" > "$tmp"; then
	if ! cmp -s "$NH_USB_ARSENAL" "$tmp"; then
		cp -p "$NH_USB_ARSENAL" "$NH_USB_ARSENAL.nh-usb.bak" 2>/dev/null
		cat "$tmp" > "$NH_USB_ARSENAL"
		chmod 0700 "$NH_USB_ARSENAL"
		echo "patched $NH_USB_ARSENAL" > "$LOG"
	fi
else
	echo "failed to patch $NH_USB_ARSENAL" > "$LOG"
fi

rm -f "$tmp"

exit 0
