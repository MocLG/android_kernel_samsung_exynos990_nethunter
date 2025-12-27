# android_kernel_samsung_exynos990_nethunter
# NetHunter Kernel for Samsung Note 20 Ultra (N985F)
**Target ROM:** OneUI 5.1 (Android 13)  
**Kernel Version:** 4.19.x  
**Root Solution:** KernelSU (v0.9.5)

A custom Kali NetHunter kernel built for the Exynos 990 (c2s) featuring full HID support, 
Wireless Injection, and KernelSU Next integration.

## 🚀 Features
- **KernelSU:** Integrated at source level for stealthy root access.
- **802.11 WiFi Injection:** Support for external adapters (Atheros, Realtek, Mediatek).
- **HID Support:** Turns the device into a "Rubber Ducky" (Keyboard/Mouse emulation).
- **Bluetooth Arsenal:** Enabled RFCOMM and HCI USB support.
- **SDR Support:** Drivers for RTL-SDR dongles.
- **Metasploit Ready:** CONFIG_SYSVIPC enabled for PostgreSQL database support.

## 🛠️ Build Environment
- **OS:** Arch Linux (Ryzen 5 7530U)
- **Compression:** LZ4

## 🏗️ How to Build
1. **Clone the Source:**
   ```bash
   git clone https://github.com/MocLG/android_kernel_samsung_exynos990_nethunter
