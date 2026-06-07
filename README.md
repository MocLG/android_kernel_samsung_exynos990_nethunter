# Samsung Exynos 990 NetHunter Kernel 🐉

![Kernel Version](https://img.shields.io/badge/Kernel-4.19.x-blue.svg)
![Android Version](https://img.shields.io/badge/Android13-green.svg)
![Platform](https://img.shields.io/badge/Platform-Exynos%20990-orange.svg)

A custom kernel for Samsung Exynos 990 devices (Note 20 / S20 Series) specifically optimized for **Kali NetHunter**. This kernel enables advanced penetration testing features directly from your mobile device.

---

## 🚀 Key Features

* **Wireless Injection:** Support for external Wi-Fi adapters (TP-Link, Alfa, etc.).
* **Bluetooth Arsenal:** Support for bluetooth arsenal/attacks with external adapter.
* **HID Support:** Keyboard/Mouse hijacking (BadUSB/Rubber Ducky attacks). (Not working at the moment)
* **DriveDroid Support:** Use your phone as a bootable USB drive. (Not working at the moment)
* **Network Protocols:** Full support for IEEE 802.11, Bluetooth HCI, and SDR.
* **Wireguard:** Secure and encrypted network tunneling for privacy and penetration testing.
* **Battery bypass:** Power components directly from the outlet reducing heat and increasing battery life.
* **Optimized Performance:** Debloated and tuned for better efficiency under heavy loads.
* **Custom SUSFS system** Deeply hide root access, Zygisk, and LSPosed from detection by apps, bypassing root checks for banking apps, games, or other sensitive software.
* **And much more.....**
---

## 🛠 Supported Devices

This kernel is designed for the **Exynos 990 (universal9830/9832)** platform:
* Samsung Galaxy Note 20 / Note 20 Ultra (Exynos)
* Samsung Galaxy S20 / S20+ / S20 Ultra (Exynos)(Samsung S20 series require modifications to dtb/custom dtbo.img)
* **Tested on Galaxy Note 20 Ultra (N985F), other devices are not officially supported.**
---

## 🏗 Build Instructions

Follow these steps to build the kernel from source on an **Arch Linux** or Ubuntu environment.

### 1. Clone the Repository
```bash
git clone https://github.com/MocLG/android_kernel_samsung_exynos990_nethunter
cd android_kernel_samsung_exynos990_nethunter
```

### 2. Execution
Run the automated build script provided in the repository:
```bash
chmod +x build_kernel.sh
./build_kernel.sh
```
The script will handle the environment setup, configuration, and compilation. Once finished, the flashable Zip will be automatically created.

---

## 📲 Installation

1. **Backup:** Always perform a full Nandroid backup in TWRP before flashing.
2. **Flash:**
   * Reboot to Recovery.
   * Formate data.
   * Reboot to Recovery.
   * Flash the generated `.zip` file(you may need to flash samsung multidisabler after kernel zip).
   * Formate data.
3. * Download and install KernelSU app v0.9.5
   **NetHunter App:** Install the Kali NetHunter app to manage HID and Wireless features.

---

## ⚠️ Disclaimer

> **WARNING:** Flashing a custom kernel modifies your system partitions. I am not responsible for bricked devices, dead SD cards, or thermonuclear war. You are choosing to make these modifications at your own risk. **Knox will be tripped.**

---

## 🤝 Contributing

Contributions are welcome! If you find a bug or want to add support for a specific driver:
1. Fork the Project.
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`).
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`).
4. Push to the Branch (`git push origin feature/AmazingFeature`).
5. Open a Pull Request.

## Credits
This repository is a downstream fork of the Exynos990 KSU-Next project by Hargriv (H-K-Systems).

---

**Developed with ❤️ for the NetHunter Community.**
*
