#!/bin/bash

# === Colors for output ===
GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

# === Error handling function ===
abort() {
    echo -e "${RED}✗ Error: Script terminated with an error in the previous step.${RESET}"
    exit 1
}

echo -e "${GREEN}Starting kernel build configuration.${RESET}"

# --- Question 1: OS_PATCH_LEVEL and OS_VERSION configuration ---
DEFAULT_OS_PATCH_LEVEL=2025-08
DEFAULT_OS_VERSION=13.0.0

read -p "Use default values for OS_PATCH_LEVEL (${DEFAULT_OS_PATCH_LEVEL}) and OS_VERSION (${DEFAULT_OS_VERSION})? (y/N): " use_default_os_params
if [[ "$use_default_os_params" =~ ^[Yy]$ ]]; then
    OS_PATCH_LEVEL="$DEFAULT_OS_PATCH_LEVEL"
    OS_VERSION="$DEFAULT_OS_VERSION"
    echo -e "${GREEN}Using default OS_PATCH_LEVEL=${OS_PATCH_LEVEL} and OS_VERSION=${OS_VERSION}.${RESET}"
else
    read -p "Enter new value for OS_PATCH_LEVEL (e.g., 2025-08 ): " new_patch_level
    if [ -n "$new_patch_level" ]; then
        OS_PATCH_LEVEL="$new_patch_level"
    else
        OS_PATCH_LEVEL="$DEFAULT_OS_PATCH_LEVEL"
        echo -e "${RED}OS_PATCH_LEVEL not entered. Using default value: ${OS_PATCH_LEVEL}${RESET}"
    fi

    read -p "Enter new value for OS_VERSION (e.g., 13.0.0 ): " new_os_version
    if [ -n "$new_os_version" ]; then
        OS_VERSION="$new_os_version"
    else
        OS_VERSION="$DEFAULT_OS_VERSION"
        echo -e "${RED}OS_VERSION not entered. Using default value: ${OS_VERSION}${RESET}"
    fi
    echo -e "${GREEN}Using custom values: OS_PATCH_LEVEL=${OS_PATCH_LEVEL} and OS_VERSION=${OS_VERSION}.${RESET}"
fi

# --- Question 2: Offer to open menuconfig ---
read -p "Open menuconfig before building? (y/N): " menuconfig_choice
if [[ "$menuconfig_choice" =~ ^[Yy]$ ]]; then
    RUN_MENUCONFIG="true"
    echo -e "${GREEN}menuconfig will be launched before building.${RESET}"
else
    RUN_MENUCONFIG="false"
    echo -e "${GREEN}menuconfig will be skipped.${RESET}"
fi

echo -e "${GREEN}Configuration complete. Starting build process...${RESET}"

# === Preliminary cleanup of output directories ===
echo -e "${GREEN}Cleaning build/out directory for a new build...${RESET}"
rm -rf build/out || { echo -e "${RED}Failed to clean build/out. Check permissions.${RESET}"; exit 1; }
echo -e "${GREEN}✓ build/out directory cleaned.${RESET}"

# === Step 1: Install/Update KernelSU Next ===
#echo -e "${GREEN}Step 1: Installing/Updating KernelSU Next...${RESET}"
#curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -

# === Step 1: Set environment variables ===
echo -e "${GREEN}Step 1: Setting environment variables...${RESET}"
export PLATFORM_VERSION=11
export ANDROID_MAJOR_VERSION=r
export SEC_BUILD_CONF_VENDOR_BUILD_OS=13
export ARCH=arm64

# === Step 2: Apply kernel configuration ===
echo -e "${GREEN}Step 2: Applying kernel configuration...${RESET}"
make NetHunter-Extreme-c2sxxx_defconfig || abort

# === Step 3: Run menuconfig (if selected) ===
if [[ "$RUN_MENUCONFIG" == "true" ]]; then
    echo -e "${GREEN}Step 3: Launching menuconfig...${RESET}"
    make menuconfig || abort
fi

# === Step 4: Build kernel ===
echo -e "${GREEN}Step 4: Building kernel...${RESET}"
make -j$(nproc) || abort

# 💾 Save final .config from build directory
echo -e "${GREEN}Saving final .config file...${RESET}"
mkdir -p build/out/c2s/ # Ensure directory exists before copying
cp .config build/out/c2s/.config || {
    echo -e "${RED}Failed to save .config${RESET}"
    exit 1
}
echo -e "${GREEN}✓ .config file saved to build/out/c2s/.config${RESET}"

# ➤ Copy Image to expected location
echo -e "${GREEN}Copying Image from build directory to build/out/c2s/Image...${RESET}"
cp arch/arm64/boot/Image build/out/c2s/Image || abort
echo -e "${GREEN}✓ Image copied.${RESET}"


# === Step 5: Prepare ramdisk for boot.img compilation ===
echo -e "${GREEN}Step 5: Preparing ramdisk...${RESET}"
RAMDISK_DIR="build/ramdisk"
mkdir -p "$RAMDISK_DIR"/{dev,proc,sys,mnt,debug_ramdisk}

echo -e "${GREEN}Created/checked directories in ramdisk:${RESET}"
for dir in dev proc sys mnt debug_ramdisk; do
    if [ -d "$RAMDISK_DIR/$dir" ]; then
        echo -e "  ✓ $RAMDISK_DIR/$dir"
    else
        echo -e "${RED}  ✗ Failed to create: $RAMDISK_DIR/$dir${RESET}"
        exit 1
    fi
done

# Create output directory if it doesn't exist
mkdir -p "$(dirname "build/out/c2s/boot.img")"

# === Step 6: Parameters for boot.img compilation ===
echo -e "${GREEN}Step 6: Parameters for boot.img compilation${RESET}"
DTB_PATH=build/out/c2s/dtb.img
KERNEL_PATH=build/out/c2s/Image
KERNEL_OFFSET=0x00008000
DTB_OFFSET=0x00000000
RAMDISK_OFFSET=0x01000000
SECOND_OFFSET=0xF0000000
TAGS_OFFSET=0x00000100
BASE=0x10000000
CMDLINE='androidboot.hardware=exynos990 loop.max_part=7'
HASHTYPE=sha1
HEADER_VERSION=2
PAGESIZE=2048
RAMDISK=build/out/c2s/ramdisk.cpio.gz
OUTPUT_FILE=build/out/c2s/boot.img
BOARD=SRPTB27C009KU
MODEL="c2s"

# === Step 7: Build ramdisk, DTB/DTBO and boot.img ===
echo -e "${GREEN}Step 7: Building ramdisk, DTB/DTBO and boot.img...${RESET}"
pushd build/ramdisk > /dev/null
find . ! -name . | LC_ALL=C sort | cpio -o -H newc -R root:root | gzip > ../out/c2s/ramdisk.cpio.gz || abort
popd > /dev/null

# ➤ Check for DTS directory existence before mkdtimg call
DTS_DIR="arch/arm64/boot/dts/exynos"
if [ ! -d "$DTS_DIR" ]; then
    echo -e "${RED}✗ Error: DTS directory not found: $DTS_DIR.${RESET}"
    echo -e "${RED}This means kernel build (Step 5) might not have generated the necessary Device Tree Source files.${RESET}"
    echo -e "${RED}Check previous kernel build logs for DTS/DTB related errors.${RESET}"
    abort
fi

# ➤ DTB and DTBO
./toolchain/mkdtimg cfg_create "$DTB_PATH" build/dtconfigs/exynos9830.cfg -d "$DTS_DIR" || abort
./toolchain/mkdtimg cfg_create build/out/c2s/dtbo.img build/dtconfigs/c2s.cfg -d arch/arm64/boot/dts/samsung || abort

# ➤ boot.img
./toolchain/mkbootimg \
    --base "$BASE" --board "$BOARD" --cmdline "$CMDLINE" --dtb "$DTB_PATH" \
    --dtb_offset "$DTB_OFFSET" --hashtype "$HASHTYPE" --header_version "$HEADER_VERSION" --kernel "$KERNEL_PATH" \
    --kernel_offset "$KERNEL_OFFSET" --os_patch_level "$OS_PATCH_LEVEL" --os_version "$OS_VERSION" --pagesize "$PAGESIZE" \
    --ramdisk "$RAMDISK" --ramdisk_offset "$RAMDISK_OFFSET" --second_offset "$SECOND_OFFSET" \
    --tags_offset "$TAGS_OFFSET" -o "$OUTPUT_FILE" || abort

# === Step 8: Prepare and archive kernel for flashing ===
echo -e "${GREEN}Step 8: Preparing and archiving kernel for flashing...${RESET}"

# Cleanup and create necessary directories for ZIP archive
mkdir -p build/out/c2s/zip/tools/scripts
mkdir -p build/out/c2s/zip/META-INF/com/google/android || abort

# === COPY BASH AND BUSYBOX ===
# Correct paths to bash and busybox in your project structure
BASH_SOURCE="build/tools/scripts/bash"
BUSYBOX_SOURCE="build/tools/scripts/busybox"

echo -e "${GREEN}Copying bash and busybox to installer ZIP...${RESET}"
# Check and copy bash
if [ -f "$BASH_SOURCE" ]; then
    cp "$BASH_SOURCE" build/out/c2s/zip/tools/scripts/bash || abort
    echo -e "${GREEN}✓ bash copied.${RESET}"
else
    echo -e "${RED}✗ Error: Bash file not found at: $BASH_SOURCE. Skipping copy. Ensure '$BASH_SOURCE' exists relative to the script's execution directory.${RESET}"
fi

# Check and copy busybox
if [ -f "$BUSYBOX_SOURCE" ]; then
    cp "$BUSYBOX_SOURCE" build/out/c2s/zip/tools/scripts/busybox || abort
    echo -e "${GREEN}✓ busybox copied.${RESET}"
else
    echo -e "${RED}✗ Error: Busybox file not found at: $BUSYBOX_SOURCE. Skipping copy. Ensure '$BUSYBOX_SOURCE' exists relative to the script's execution directory.${RESET}"
fi

for EXTRA_SCRIPT in build/tools/scripts/*.sh; do
    [ -e "$EXTRA_SCRIPT" ] || continue
    cp "$EXTRA_SCRIPT" build/out/c2s/zip/tools/scripts/ || abort
    chmod 0755 "build/out/c2s/zip/tools/scripts/$(basename "$EXTRA_SCRIPT")" || abort
    echo -e "${GREEN}✓ $(basename "$EXTRA_SCRIPT") copied.${RESET}"
done
# ==================================

# Copy files to ZIP archive structure
echo -e "${GREEN}Copying files to ZIP structure...${RESET}"
# Copy boot.img and dtbo.img directly to ZIP root
cp "$OUTPUT_FILE" build/out/c2s/zip/boot.img || abort
cp build/out/c2s/dtbo.img build/out/c2s/zip/dtbo.img || abort
cp build/ksunext/update-binary build/out/c2s/zip/META-INF/com/google/android/update-binary || abort
cp build/ksunext/updater-script build/out/c2s/zip/META-INF/com/google/android/updater-script || abort

# ➤ Get CONFIG_LOCALVERSION from .config
CONFIG_FILE="build/out/c2s/.config"
if [[ -f "$CONFIG_FILE" ]]; then
    LOCAL_VERSION=$(grep "^CONFIG_LOCALVERSION=" "$CONFIG_FILE" | cut -d= -f2 | tr -d '"')
    if [ -z "$LOCAL_VERSION" ]; then
        echo -e "${RED}CONFIG_LOCALVERSION not found in $CONFIG_FILE. Using 'unknown'.${RESET}"
        LOCAL_VERSION="unknown"
    fi
else
    echo -e "${RED}.config file not found at: $CONFIG_FILE. Using 'unknown' for version.${RESET}"
    LOCAL_VERSION="unknown"
fi

# Use MODEL for ZIP file name
ZIP_NAME="${LOCAL_VERSION}_${MODEL}.zip"

# ➤ Archive with progress
echo -e "${GREEN}Creating ZIP archive: build/out/c2s/$ZIP_NAME...${RESET}"
pushd build/out/c2s/zip > /dev/null
zip -r -q "../$ZIP_NAME" . || {
    echo -e "${RED}Error creating ZIP archive.${RESET}"
    abort
}
popd > /dev/null

echo -e "${GREEN}Archive created: build/out/c2s/$ZIP_NAME${RESET}"
echo -e "${GREEN}Script completed successfully!${RESET}"
