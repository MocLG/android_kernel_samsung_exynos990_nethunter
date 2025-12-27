### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=NetHunter-Extreme by lukag @ LGPC
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=c2s
device.name2=c2slte
device.name3=N985F
device.name4=N985
device.name5=N986B
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install
## boot files attributes
boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

# boot shell variables
# Note 20 Ultra uses standard by-name paths
block=/dev/block/by-name/boot;
dtbo_block=/dev/block/by-name/dtbo;
is_slot_device=0;
ramdisk_compression=auto;
patch_vbmeta_flag=--disable-verity --disable-verification;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;
# boot install
dump_boot; # Unpack the current boot image

patch_cmdline "androidboot.dtbo_idx" "-1";
patch_cmdline "androidboot.dtb_idx" "0";
patch_cmdline "androidboot.fmp_config" "0";
patch_cmdline "androidboot.iccc_status" "0";
# 1. SELinux Permissive Patch
# Fixes the hundreds of "unmapped" context errors in your logs
patch_cmdline "androidboot.vbmeta.device_state" "androidboot.vbmeta.device_state=unlocked";
patch_cmdline "androidboot.verifiedbootstate" "orange";
patch_cmdline "skip_override" "skip_override";
patch_cmdline "androidboot.selinux" "androidboot.selinux=permissive";
patch_cmdline "skip_initramfs" "";
# 2. Force Skip Samsung Security Checks
# This helps bypass the "bl_exception 7" reboot
patch_cmdline "androidboot.wsm" "0";
patch_cmdline "androidboot.knox.rev" "0";
patch_cmdline "androidboot.security_slot" "0";

# 3. Decrypted ROM fstab Patches (Note 20 Ultra Exynos 990)
# These prevent the kernel from trying to force-encrypt your data
patch_fstab fstab.samsungexynos990 "userdata" "f2fs" "forceencrypt" "encryptable";
patch_fstab fstab.samsungexynos990 "userdata" "ext4" "forceencrypt" "encryptable";
replace_string fstab.samsungexynos990 "fileencryption=" "encryptable=";

# 4. Neutralize Vaultkeeper & Samsung Security Services
# This is the "Manual Fix File" part - it stops these from starting
replace_section init.rc "service vault" " " " ";
replace_section init.rc "service gatekeeper" " " " ";
replace_section init.rc "service s_proca" " " " ";
replace_section init.rc "service vaultkeeper" " " " ";

write_boot; # Repack and flash the new Image