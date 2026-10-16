# Fantech Revolver III (WGP12S) & ShanWan Gamepad Linux Fix

Fixes Linux recognition, X-Input mode, analog triggers, 1000Hz polling rate, and rumble/force-feedback for **Fantech Revolver III (WGP12S)** and similar **ShanWan-based controllers** (e.g. Cosmic Byte Blitz, Rapoo V600SE) for both **Wired (USB-C)** and **2.4GHz Wireless Dongle** connections.

[![Kernel](https://img.shields.io/badge/Linux_Kernel-%3E%3D_7.2-blue.svg)](https://kernel.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## 🎮 The Problem

Under Windows, this gamepad operates out-of-the-box as an **Xbox 360 (X-Input)** controller with full analog triggers, rumble, and high polling rate.

On Linux, however:
- **Wired Connection:** The controller is misdetected as `05ac:033e Apple, Inc. Gamepad` via `hid-generic`.
- **2.4GHz Wireless Dongle:** The controller is misdetected as `20bc:5001 ShenZhen ShanWan Technology Co., Ltd. Gamepad` via `hid-generic`.

In this fallback state:
- **No Vibration / Rumble:** Force feedback (`EV_FF`) is completely disabled.
- **Messed-up Controls:** Trigger and stick axes are mapped incorrectly or behave like digital buttons.
- **Game Incompatibility:** Games expecting an X-Input / Xbox controller fail to detect it properly.
- Only the 3rd LED (Android mode) or single D-Input LED lights up instead of LEDs 1 & 2 (X-Input mode).

---

## 🔬 Root Cause & Technical Details

1. **USB Descriptor Size Quirk (`error -71` / `EPROTO`):**
   - When plugged in via wire, the hardware initially attempts to connect as `0289:0200` (X-Input mode).
   - When plugged in via the 2.4GHz dongle, after initial handshake it switches to `0283:0001` (X-Input mode).
   - The device firmware strictly expects the host operating system to request a **255-byte** configuration descriptor (`wLength=255`), which is standard behavior on Microsoft Windows.
   - The Linux kernel (`usbcore`) by default requests only **9 bytes** (`wLength=9`).
   - The controller's firmware fails to handle the 9-byte request, throwing `-71` (`EPROTO`). Assuming it is not connected to a Windows PC, it immediately disconnects and silently degrades into a restricted **Android/Apple HID fallback persona** (`05ac:033e` wired, `20bc:5001` wireless).

2. **The Fix (`USB_QUIRK_WINDOWS_CONFIG_REQ_SIZE`):**
   - Linux kernel **7.2+** introduced the `r` quirk flag (`USB_QUIRK_WINDOWS_CONFIG_REQ_SIZE`), which forces `usbcore` to issue a 255-byte descriptor request mirroring Windows.
   - By applying `usbcore.quirks=0289:0200:r,0283:0001:r`, both the wired controller and the wireless dongle complete USB enumeration cleanly and remain in true X-Input mode.
   - Note: The initial dongle handshake identity `2563:0575` expects the standard 9-byte read, so only `0289:0200` and `0283:0001` receive the `:r` quirk flag.

3. **Driver Binding (`xpad`):**
   - The X-Input interface on both modes exposes vendor-specific Xbox 360 endpoints (`bInterfaceClass=0xff, bInterfaceSubClass=0x5d, bInterfaceProtocol=0x01`).
   - Dynamically registering `0289 0200 ff` and `0283 0001 ff` to `/sys/bus/usb/drivers/xpad/new_id` binds the standard kernel `xpad` driver, exposing full analog axes, button mappings, and rumble motors.

---

## 📋 Compatibility

- **Fantech Revolver III (WGP12S)** (Wired: `0289:0200`, Wireless: `0283:0001`)
- **Cosmic Byte Blitz** (and similar ShanWan clone gamepads)
- **Linux Kernel:** >= **7.2** recommended (contains `USB_QUIRK_WINDOWS_CONFIG_REQ_SIZE`).

---

## 🚀 Quick Installation

Clone this repository and run the installer:

```bash
git clone https://github.com/<YOUR_USERNAME>/fantech-revolver-iii-linux.git
cd fantech-revolver-iii-linux
chmod +x install.sh
sudo ./install.sh
```

Then replug your gamepad USB cable or 2.4GHz dongle. Both LEDs 1 & 2 will light up, indicating X-Input mode!

---

## 🛠️ Manual Installation (Step-by-Step)

If you prefer applying the changes manually without the script:

### 1. Ensure `xpad` loads at boot
Create `/etc/modules-load.d/fantech-revolver-iii.conf`:
```ini
xpad
```

### 2. Set runtime quirk fallback
Create `/etc/tmpfiles.d/fantech-revolver-iii.conf`:
```ini
w /sys/module/usbcore/parameters/quirks - - - - 0289:0200:r,0283:0001:r
```

### 3. Add Udev rules for automatic driver binding
Create `/etc/udev/rules.d/90-fantech-revolver-iii.rules`:
```udev
# Fantech Revolver III (WGP12S) - Register Wired (0289:0200) and 2.4GHz Wireless (0283:0001) X-Input IDs with xpad
ACTION=="add", SUBSYSTEM=="module", KERNEL=="xpad", RUN+="/bin/sh -c 'echo 0289 0200 ff > /sys/bus/usb/drivers/xpad/new_id 2>/dev/null || true; echo 0283 0001 ff > /sys/bus/usb/drivers/xpad/new_id 2>/dev/null || true'"

ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0289", ATTR{idProduct}=="0200", MODE="0660", TAG+="uaccess", RUN+="/usr/bin/modprobe xpad", RUN+="/bin/sh -c 'echo 0289 0200 ff > /sys/bus/usb/drivers/xpad/new_id 2>/dev/null || true'"
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0283", ATTR{idProduct}=="0001", MODE="0660", TAG+="uaccess", RUN+="/usr/bin/modprobe xpad", RUN+="/bin/sh -c 'echo 0283 0001 ff > /sys/bus/usb/drivers/xpad/new_id 2>/dev/null || true'"
```

### 4. Add bootloader kernel parameter (for boot-time plugging)
Add `usbcore.quirks=0289:0200:r,0283:0001:r` to your kernel command line.
- For **GRUB**: In `/etc/default/grub`, append to `GRUB_CMDLINE_LINUX_DEFAULT`:
  ```ini
  GRUB_CMDLINE_LINUX_DEFAULT="... usbcore.quirks=0289:0200:r,0283:0001:r"
  ```
  Then regenerate grub config:
  ```bash
  sudo grub-mkconfig -o /boot/grub/grub.cfg
  ```
- For **systemd-boot**: Append `usbcore.quirks=0289:0200:r,0283:0001:r` to the `options` line in your entry config (`/boot/loader/entries/*.conf`).

### 5. Apply live settings
```bash
sudo modprobe xpad
echo "0289:0200:r,0283:0001:r" | sudo tee /sys/module/usbcore/parameters/quirks
echo "0289 0200 ff" | sudo tee /sys/bus/usb/drivers/xpad/new_id
echo "0283 0001 ff" | sudo tee /sys/bus/usb/drivers/xpad/new_id
sudo udevadm control --reload-rules && sudo udevadm trigger
```

---

## 🔍 Verification

### Check connected device
```bash
lsusb
```
You should see:
- Wired: `ID 0289:0200 Controller`
- Wireless: `ID 0283:0001 Controller`

### Check input & rumble
```bash
cat /proc/bus/input/devices | grep -A 10 "Generic X-Box pad"
```
You should see `Generic X-Box pad` with `B: FF=107030000 0` indicating force feedback (rumble) is active.

You can also test rumble and inputs using standard utilities:
```bash
sudo pacman -S evtest # (or apt install evtest)
evtest
```
Select `Generic X-Box pad` to inspect live button and axis events.

---

## 🗑️ Uninstallation

To remove all configurations made by this fix:

```bash
sudo ./uninstall.sh
```

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
