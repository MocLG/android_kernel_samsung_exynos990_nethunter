#!/system/bin/sh

# Unified recovery/AnyKernel3 installer and Android boot-time patcher.
# AnyKernel3 usage: sh "$home/ak_scripts/nethunter-usb-arsenal-compat.sh"

SCRIPT_NAME=nethunter-usb-arsenal-compat.sh
SERVICE_DIR=${SERVICE_DIR:-/data/adb/service.d}
SERVICE_PATH=${SERVICE_PATH:-$SERVICE_DIR/$SCRIPT_NAME}
NH_USB_ARSENAL=${NH_USB_ARSENAL:-/data/data/com.offsec.nethunter/scripts/usbarsenal}
LOG=${LOG:-/data/local/tmp/nethunter-usb-arsenal-compat.log}
USERDATA=${USERDATA:-/dev/block/bootdevice/by-name/userdata}

script_path()
{
	case "$0" in
		/*) printf '%s\n' "$0" ;;
		*) printf '%s/%s\n' "$(pwd)" "$0" ;;
	esac
}

find_busybox()
{
	for bb in /tmp/scripts/busybox /sbin/busybox /system/bin/busybox /data/adb/magisk/busybox busybox; do
		if [ -x "$bb" ] || command -v "$bb" >/dev/null 2>&1; then
			printf '%s\n' "$bb"
			return 0
		fi
	done

	return 1
}

mount_data()
{
	grep -q ' /data ' /proc/mounts 2>/dev/null && return 0

	mkdir -p /data 2>/dev/null
	BB=$(find_busybox 2>/dev/null)

	for dev in "$USERDATA" /dev/block/by-name/userdata /dev/block/mapper/userdata /dev/block/platform/*/by-name/userdata; do
		[ -b "$dev" ] || continue
		for fs in f2fs ext4; do
			if [ -n "$BB" ]; then
				"$BB" mount -t "$fs" "$dev" /data 2>/dev/null && return 0
			fi
			mount -t "$fs" "$dev" /data 2>/dev/null && return 0
		done
	done

	return 1
}

run_installed_once()
{
	if [ -x /tmp/scripts/busybox ]; then
		/tmp/scripts/busybox sh "$SERVICE_PATH" --patch 2>/dev/null
	elif BB=$(find_busybox 2>/dev/null); then
		"$BB" sh "$SERVICE_PATH" --patch 2>/dev/null
	else
		sh "$SERVICE_PATH" --patch 2>/dev/null
	fi
}

install_service()
{
	self=$(script_path)
	BB=$(find_busybox 2>/dev/null)

	[ -f "$self" ] || return 1
	mount_data || return 1
	[ -d /data/adb ] || return 1

	mkdir -p "$SERVICE_DIR" || return 1
	if [ -n "$BB" ]; then
		"$BB" cp "$self" "$SERVICE_PATH" || return 1
		"$BB" chown 0:0 "$SERVICE_PATH" 2>/dev/null
		"$BB" chmod 0755 "$SERVICE_PATH" || return 1
	else
		cp "$self" "$SERVICE_PATH" || return 1
		chown 0:0 "$SERVICE_PATH" 2>/dev/null
		chmod 0755 "$SERVICE_PATH" || return 1
	fi

	run_installed_once
	return 0
}

patch_usbarsenal()
{
	[ -f "$NH_USB_ARSENAL" ] || exit 0

	if grep -q 'ANDROID_USB_FUNCS=' "$NH_USB_ARSENAL" 2>/dev/null &&
		! grep -q 'setprop sys.usb.config "$ANDROID_USB_FUNCS"' "$NH_USB_ARSENAL" 2>/dev/null &&
		[ -f "$NH_USB_ARSENAL.nh-usb.bak" ]; then
		cat "$NH_USB_ARSENAL.nh-usb.bak" > "$NH_USB_ARSENAL"
		chmod 0700 "$NH_USB_ARSENAL"
	fi

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
		-e 's#FUNCS_NAME_ORDER=\$((FUNCS_NAME_ORDER + 1))#:#g' \
		-e 's#SYMLINK_FUNC_NAME="\$FUNCS_NAME_PREFIX\$FUNCS_NAME_ORDER"#:#g' \
		"$NH_USB_ARSENAL" > "$tmp"; then
		if ! grep -q '/sys/class/udc' "$tmp"; then
			tmp_udc="$tmp.udc"
			while IFS= read -r line; do
				echo "$line"
				if [ "$line" = 'ORI_DWC=$(getprop sys.usb.controller)' ]; then
					echo '[ -n "$ORI_DWC" ] || ORI_DWC=$(ls /sys/class/udc 2>/dev/null | head -n1)'
				fi
			done < "$tmp" > "$tmp_udc" && mv "$tmp_udc" "$tmp"
		fi

		if ! grep -q 'ANDROID_USB_FUNCS=' "$tmp"; then
			tmp_legacy="$tmp.legacy"
			in_revert=0
			while IFS= read -r line; do
				echo "$line"
				if [ "$line" = 'function revert_to_ori_state(){' ]; then
					in_revert=1
				fi
				if [ "$line" = 'function clear_funcs(){' ]; then
					echo '    [ -e /sys/class/android_usb/android0/enable ] && echo 0 > /sys/class/android_usb/android0/enable 2>/dev/null'
				fi
				if [ "$in_revert" = 1 ] && [ "$line" = '    clear_funcs' ]; then
					echo '    if [ -e /sys/class/android_usb/android0/functions ]; then'
					echo '        setprop sys.usb.config adb'
					echo '        echo adb > /sys/class/android_usb/android0/functions'
					echo '        start adbd'
					echo '        setprop sys.usb.ffs.ready 1'
					echo '        fireup_funcs'
					echo '        return'
					echo '    fi'
				fi
				if [ "$line" = '    echo $ORI_DWC > $DIR_CONFIGFS/UDC' ]; then
					echo '    [ -e /sys/class/android_usb/android0/enable ] && echo 1 > /sys/class/android_usb/android0/enable 2>/dev/null'
				fi
				if [ "$line" = 'function switch_funcs(){' ]; then
					echo '    if [ -e /sys/class/android_usb/android0/functions ]; then'
					echo '        function prepare_hid_keyboard(){ return 0; }'
					echo '        function prepare_hid_mouse(){ return 0; }'
					echo '    fi'
				fi
				if [ "$line" = '    ## If user'\''s input is valid, then clear the current usb functions and start to symlink the target functions. ##' ]; then
					echo '    if [ -e /sys/class/android_usb/android0/functions ] && echo "$TARGET_FUNCS" | grep -q hid; then'
					echo '        FUNCS_DESC=()'
					echo '        for i in ${ARRAY_TARGET_FUNCS[@]}; do'
					echo '            case "$i" in'
					echo '                adb) IS_ADB_SELECTED=0; FUNCS_DESC+=('\''adb'\'');;'
					echo '                hid) IS_HID_SELECTED=0; FUNCS_DESC+=('\''hid'\'');;'
					echo '                mass_storage) IS_MASS_SELECTED=0; FUNCS_DESC+=('\''mass_storage'\'');;'
					echo '                rndis) IS_RNDIS_SELECTED=0; FUNCS_DESC+=('\''rndis'\'');;'
					echo '                acm) IS_ACM_SELECTED=0; FUNCS_DESC+=('\''acm'\'');;'
					echo '                ecm) IS_ECM_SELECTED=0; FUNCS_DESC+=('\''ecm'\'');;'
					echo '            esac'
					echo '        done'
					echo '        ANDROID_USB_FUNCS=$(join_by , "${FUNCS_DESC[@]}")'
					echo '        bklog "[!] Selecting Samsung legacy functions: $ANDROID_USB_FUNCS"'
					echo '        clear_funcs'
					echo '        rmdir $DIR_ALL_FUNCS/hid.0 $DIR_ALL_FUNCS/hid.1 2>/dev/null'
					echo '        setprop sys.usb.config "$ANDROID_USB_FUNCS"'
					echo '        echo "$ANDROID_USB_FUNCS" > /sys/class/android_usb/android0/functions'
					echo '        if [ $IS_ADB_SELECTED -eq 0 ]; then'
					echo '            start adbd'
					echo '            setprop sys.usb.ffs.ready 1'
					echo '        fi'
					echo '        fireup_funcs'
					echo '        FUNCS_DESC_STR=$(join_by _ "${FUNCS_DESC[@]}")'
					echo '        echo "$FUNCS_DESC_STR" > $DIR_CUR_FUNCS/strings/0x409/configuration'
					echo '        if [ $IS_HID_SELECTED -eq 0 ]; then'
					echo '            if [ ! -c /dev/hidg0 -o ! -c /dev/hidg1 ]; then'
					echo '                bklog "[-] No /dev/hidg0 or /dev/hidg1 is up"'
					echo '                bklog "[!] Reverting usb state to '\''adb'\''"'
					echo '                revert_to_ori_state'
					echo '                exit 1'
					echo '            else'
					echo '                chmod 666 /dev/hidg0 /dev/hidg1'
					echo '            fi'
					echo '        fi'
					echo '        bklog "[+] Done."'
					echo '        exit 0'
					echo '    fi'
					echo ''
				fi
				if [ "$line" = '    ## 1. Fireup the usb functions ##' ]; then
					echo '    if [ -e /sys/class/android_usb/android0/functions ]; then'
					echo '        ANDROID_USB_FUNCS=$(join_by , "${FUNCS_DESC[@]}")'
					echo '        setprop sys.usb.config "$ANDROID_USB_FUNCS"'
					echo '        echo "$ANDROID_USB_FUNCS" > /sys/class/android_usb/android0/functions'
					echo '    fi'
					echo ''
				fi
				if [ "$in_revert" = 1 ] && [ "$line" = '}' ]; then
					in_revert=0
				fi
			done < "$tmp" > "$tmp_legacy" && mv "$tmp_legacy" "$tmp"
		fi

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
}

case "$1" in
	--patch|patch|service)
		patch_usbarsenal
		;;
	--install|install)
		install_service
		exit 0
		;;
esac

case "$(script_path)" in
	/data/adb/service.d/*)
		patch_usbarsenal
		;;
	*)
		install_service && exit 0
		patch_usbarsenal
		;;
esac
