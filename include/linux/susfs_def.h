#ifndef KSU_SUSFS_DEF_H
#define KSU_SUSFS_DEF_H

#include <linux/bits.h>

/********/
/* ENUM */
/********/
/* shared with userspace ksu_susfs tool */
#define CMD_SUSFS_ADD_SUS_PATH 0x55550
#define CMD_SUSFS_SET_ANDROID_DATA_ROOT_PATH 0x55551
#define CMD_SUSFS_SET_SDCARD_ROOT_PATH 0x55552
#define CMD_SUSFS_ADD_SUS_MOUNT 0x55560
#define CMD_SUSFS_HIDE_SUS_MNTS_FOR_ALL_PROCS 0x55561
#define CMD_SUSFS_UMOUNT_FOR_ZYGOTE_ISO_SERVICE 0x55562
#define CMD_SUSFS_ADD_SUS_KSTAT 0x55570
#define CMD_SUSFS_UPDATE_SUS_KSTAT 0x55571
#define CMD_SUSFS_ADD_SUS_KSTAT_STATICALLY 0x55572
#define CMD_SUSFS_ADD_TRY_UMOUNT 0x55580
#define CMD_SUSFS_SET_UNAME 0x55590
#define CMD_SUSFS_ENABLE_LOG 0x555a0
#define CMD_SUSFS_SET_CMDLINE_OR_BOOTCONFIG 0x555b0
#define CMD_SUSFS_ADD_OPEN_REDIRECT 0x555c0
#define CMD_SUSFS_RUN_UMOUNT_FOR_CURRENT_MNT_NS 0x555d0
#define CMD_SUSFS_SHOW_VERSION 0x555e1
#define CMD_SUSFS_SHOW_ENABLED_FEATURES 0x555e2
#define CMD_SUSFS_SHOW_VARIANT 0x555e3
#define CMD_SUSFS_SHOW_SUS_SU_WORKING_MODE 0x555e4
#define CMD_SUSFS_IS_SUS_SU_READY 0x555f0
#define CMD_SUSFS_SUS_SU 0x60000

#define SUSFS_MAX_LEN_PATHNAME 256 // 256 should address many paths already unless you are doing some strange experimental stuff, then set your own desired length
#define SUSFS_FAKE_CMDLINE_OR_BOOTCONFIG_SIZE 4096

#define TRY_UMOUNT_DEFAULT 0 /* used by susfs_try_umount() */
#define TRY_UMOUNT_DETACH 1 /* used by susfs_try_umount() */

#define SUS_SU_DISABLED 0
#define SUS_SU_WITH_OVERLAY 1 /* deprecated */
#define SUS_SU_WITH_HOOKS 2

#define DEFAULT_SUS_MNT_ID 100000 /* used by mount->mnt_id */
#define DEFAULT_SUS_MNT_ID_FOR_KSU_PROC_UNSHARE 1000000 /* used by vfsmount->susfs_mnt_id_backup */
#define DEFAULT_SUS_MNT_GROUP_ID 1000 /* used by mount->mnt_group_id */

/*
 * inode->i_state => storing flag 'INODE_STATE_'
 * mount->mnt.susfs_mnt_id_backup => storing original mnt_id of normal mounts or custom sus mnt_id of sus mounts
 * task_struct->susfs_last_fake_mnt_id => storing last valid fake mnt_id
 * task_struct->susfs_task_state => storing flag 'TASK_STRUCT_'
 */

#define INODE_STATE_SUS_PATH BIT(24)
#define INODE_STATE_SUS_MOUNT BIT(25)
#define INODE_STATE_SUS_KSTAT BIT(26)
#define INODE_STATE_OPEN_REDIRECT BIT(27)

#define TASK_STRUCT_NON_ROOT_USER_APP_PROC BIT(24)

#define MAGIC_MOUNT_WORKDIR "/debug_ramdisk/workdir"
#define DATA_ADB_UMOUNT_FOR_ZYGOTE_SYSTEM_PROCESS "/data/adb/susfs_umount_for_zygote_system_process"
#define DATA_ADB_NO_AUTO_ADD_SUS_BIND_MOUNT "/data/adb/susfs_no_auto_add_sus_bind_mount"
#define DATA_ADB_NO_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT "/data/adb/susfs_no_auto_add_sus_ksu_default_mount"
#define DATA_ADB_NO_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT "/data/adb/susfs_no_auto_add_try_umount_for_bind_mount"

/* Syscall Families for susfs_sus_path_by_path */
#define SYSCALL_FAMILY_STAT           (1 << 0)
#define SYSCALL_FAMILY_LSTAT          (1 << 1)
#define SYSCALL_FAMILY_STATFS         (1 << 2)
#define SYSCALL_FAMILY_FSTAT          (1 << 3)
#define SYSCALL_FAMILY_FSTATAT        (1 << 4)
#define SYSCALL_FAMILY_USTAT          (1 << 5)
#define SYSCALL_FAMILY_FSTATFS        (1 << 6)
#define SYSCALL_FAMILY_ALL            (0xFFFFFFFF)
#define SYSCALL_FAMILY_ALL_ENOENT     (0x7FFFFFFF)
#define SYSCALL_FAMILY_MKNOD          (1 << 7)
#define SYSCALL_FAMILY_MKNODAT        (1 << 8)
#define SYSCALL_FAMILY_MKDIR          (1 << 9)
#define SYSCALL_FAMILY_MKDIRAT        (1 << 10)
#define SYSCALL_FAMILY_RMDIR          (1 << 11)
#define SYSCALL_FAMILY_UNLINK         (1 << 12)
#define SYSCALL_FAMILY_UNLINKAT       (1 << 13)
#define SYSCALL_FAMILY_SYMLINK        (1 << 14)
#define SYSCALL_FAMILY_SYMLINKAT_OLDNAME (1 << 15)
#define SYSCALL_FAMILY_SYMLINKAT_NEWNAME (1 << 16)
#define SYSCALL_FAMILY_LINK           (1 << 17)
#define SYSCALL_FAMILY_LINKAT_OLDNAME (1 << 18)
#define SYSCALL_FAMILY_LINKAT_NEWNAME (1 << 19)
#define SYSCALL_FAMILY_RENAME         (1 << 20)
#define SYSCALL_FAMILY_RENAMEAT_OLDNAME (1 << 21)
#define SYSCALL_FAMILY_RENAMEAT_NEWNAME (1 << 22)
#define SYSCALL_FAMILY_RENAMEAT2_OLDNAME (1 << 23)
#define SYSCALL_FAMILY_RENAMEAT2_NEWNAME (1 << 24)
#define SYSCALL_FAMILY_TRUNCATE       (1 << 25)
#define SYSCALL_FAMILY_FTRUNCATE      (1 << 26)
#define SYSCALL_FAMILY_CREAT          (1 << 27)

#endif // #ifndef KSU_SUSFS_DEF_H
