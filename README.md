# Fantech Revolver III (WGP12S) & ShanWan Gamepad Linux Fix

Linux kernel configuration, udev rules, and driver bindings to enable native X-Input mode, analog triggers, vibration feedback, 1000Hz wired polling rate, and proper LED indicators for the **Fantech Revolver III (WGP12S)** and similar **ShanWan-based controllers** (e.g., Cosmic Byte Blitz, Rapoo V600SE) across both **Wired (USB-C)** and **2.4GHz Wireless Dongle** connections.

[![Linux Kernel](https://img.shields.io/badge/Linux_Kernel->=_7.2-blue.svg)](https://kernel.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## Quick Reference & Hardware Specifications

The following table provides hardware IDs, kernel quirks, driver bindings, and expected operational states:

| Attribute | Wired Connection (USB-C) | 2.4GHz Wireless Dongle |
| :--- | :--- | :--- |
| **Native Target VID:PID** | `0289:0200` | `0283:0001` |
| **Degraded Fallback VID:PID** | `05ac:033e` (Apple Inc. Gamepad) | `20bc:5001` (ShanWan Android Gamepad) |
| **Target Kernel Driver** | `xpad` | `xpad` |
| **Required USB Core Quirk** | `0289:0200:r` (`USB_QUIRK_WINDOWS_CONFIG_REQ_SIZE`) | `0283:0001:r` (`USB_QUIRK_WINDOWS_CONFIG_REQ_SIZE`) |
| **Target USB Class / Protocol** | `ff:5d:01` (Xbox 360 Controller) | `ff:5d:01` (Xbox 360 Controller) |
| **Active LED Indicator (Working)** | LEDs 1 and 2 illuminated (X-Input mode) | LEDs 1 and 2 illuminated (X-Input mode) |
| **Degraded LED Indicator (Fault)** | LED 3 illuminated (Android mode) | LED 3 illuminated or single D-Input LED |
| **Force Feedback / Vibration** | Supported (`EV_FF` / `ff-memless`) | Supported (`EV_FF` / `ff-memless`) |
| **Analog Triggers (LT / RT)** | Full analog range (0-255, `ABS_Z` / `ABS_RZ`) | Full analog range (0-255, `ABS_Z` / `ABS_RZ`) |
| **Polling Rate** | Up to 1000Hz | Up to 250Hz |

---

## Problem Statement

When connected to Microsoft Windows, the Fantech Revolver III (WGP12S) identifies as a standard Xbox 360 controller via X-Input with working analog triggers, force feedback, and high polling rate.

On default Linux installations, the controller fails enumeration and falls back into restricted generic HID modes:
- **Wired Connection:** Recognized as `05ac:033e Apple, Inc. Gamepad` via `hid-generic`.
- **2.4GHz Wireless Dongle:** Recognized as `20bc:5001 ShenZhen ShanWan Technology Co., Ltd. Gamepad` via `hid-generic`.

In this fallback state:
- Force feedback (rumble) is disabled; `EV_FF` capabilities are missing.
- Left and right triggers (`LT` / `RT`) act as digital buttons or map to incorrect axis offsets.
- Games and compatibility layers (Steam Input, Proton, Wine) fail to recognize the device as an X-Input controller.
- The controller displays incorrect LED indicators (LED 3 illuminated instead of LEDs 1 and 2).

---

## Root Cause and Technical Architecture

### 1. USB Descriptor Size Quirk (error -71 / EPROTO)

When plugged in, the hardware firmware attempts to present its native X-Input persona (`0289:0200` wired, `0283:0001` wireless):
- ShanWan and Compx microcontroller firmwares expect the operating system to query configuration descriptors with a 255-byte buffer length (`wLength = 255`), which is standard Windows USB stack behavior.
- The Linux kernel USB core subsystem (`usbcore`) historically issues an initial descriptor request of only 9 bytes (`wLength = 9`) to determine `wTotalLength` before issuing a second request.
- The controller firmware fails to process the 9-byte request, throwing a protocol error:
  ```text
  usb 1-1: device descriptor read/all, error -71
  ```
- Believing it is connected to a non-Windows host (such as an Android device or macOS system), the controller disconnects and resets into a restricted fallback HID persona (`05ac:033e` or `20bc:5001`).

### 2. The Solution: USB_QUIRK_WINDOWS_CONFIG_REQ_SIZE (Quirk Flag 'r')

Linux kernel 7.2 introduced the `r` quirk flag (`USB_QUIRK_WINDOWS_CONFIG_REQ_SIZE`). This flag instructs `usbcore` to request a full 255-byte configuration descriptor immediately during initial device probe, mirroring Windows behavior.

Applying the quirk parameter:
```ini
usbcore.quirks=0289:0200:r,0283:0001:r
```
allows both the wired controller and the wireless dongle to complete descriptor negotiation cleanly, remaining in native X-Input mode.

*Note on initial dongle handshake:* The 2.4GHz dongle's preliminary boot identity `2563:0575` handles the standard 9-byte read correctly; only the subsequent X-Input persona identities (`0289:0200` and `0283:0001`) require the `r` quirk flag.

### 3. Dynamic Driver Binding via xpad

After enumeration succeeds, the device exposes vendor-specific Xbox endpoints (`bInterfaceClass=0xff, bInterfaceSubClass=0x5d, bInterfaceProtocol=0x01`). Because these specific vendor and product IDs are not hardcoded into older upstream `xpad` device tables, udev dynamically registers them:
```bash
echo 0289 0200 ff > /sys/bus/usb/drivers/xpad/new_id
echo 0283 0001 ff > /sys/bus/usb/drivers/xpad/new_id
```
This binds the standard Linux kernel `xpad` driver, exposing standard analog axes, button mappings, and dual-motor rumble via `ff-memless`.

---

## Hardware and System Compatibility

### Verified Hardware
- **Fantech Revolver III (WGP12S)** (Wired: `0289:0200`, Wireless: `0283:0001`)
- **Cosmic Byte Blitz** (ShanWan / Compx variants)
- **Rapoo V600SE**
- Other ShanWan-based controllers exhibiting 9-byte USB descriptor timeout or `-71` errors

### Operating System Requirements
- **Linux Kernel:** >= 7.2 recommended (includes native `USB_QUIRK_WINDOWS_CONFIG_REQ_SIZE`).
- **Supported Distributions:** Arch Linux, Ubuntu, Debian, Fedora, openSUSE, SteamOS, Manjaro, Pop!_OS, CachyOS.
- **Root Privileges:** Required for installing udev rules, module configuration, and bootloader options.

---

## Installation

### Automated Installation (Recommended)

1. Clone this repository:
   ```bash
   git clone https://github.com/Nylord5578ygt/fantech-revolver-iii-linux.git
   cd fantech-revolver-iii-linux
   ```

2. Make the installer executable and run it:
   ```bash
   chmod +x install.sh
   sudo ./install.sh
   ```

3. Replug your controller USB cable or 2.4GHz wireless dongle.
   LEDs 1 and 2 will illuminate, confirming active X-Input mode.

### What the Automated Script Configures
- Deploys `/etc/modules-load.d/fantech-revolver-iii.conf` to load `xpad` at boot.
- Deploys `/etc/tmpfiles.d/fantech-revolver-iii.conf` to set runtime USB quirks during boot.
- Installs `/etc/udev/rules.d/90-fantech-revolver-iii.rules` to dynamically bind the controller IDs to `xpad`.
- Updates GRUB configuration if GRUB is detected.
- Reloads active udev rules and applies live sysfs parameters immediately.

---

## Manual Installation (Step-by-Step)

If you prefer applying configuration changes manually without executing the installer script, follow these steps:

### Step 1: Ensure kernel module loads at boot
Create `/etc/modules-load.d/fantech-revolver-iii.conf`:
```ini
xpad
```
Load the module in the active session:
```bash
sudo modprobe xpad
sudo modprobe ff-memless
```

### Step 2: Configure runtime USB quirks
Create `/etc/tmpfiles.d/fantech-revolver-iii.conf`:
```ini
w /sys/module/usbcore/parameters/quirks - - - - 0289:0200:r,0283:0001:r
```
Apply the tmpfiles configuration immediately:
```bash
sudo systemd-tmpfiles --create /etc/tmpfiles.d/fantech-revolver-iii.conf
```

### Step 3: Install Udev rules
Create `/etc/udev/rules.d/90-fantech-revolver-iii.rules` with the following content:
```udev
# Fantech Revolver III (WGP12S) - Register Wired (0289:0200) and 2.4GHz Wireless (0283:0001) X-Input IDs with xpad
ACTION=="add", SUBSYSTEM=="module", KERNEL=="xpad", RUN+="/bin/sh -c 'echo 0289 0200 ff > /sys/bus/usb/drivers/xpad/new_id 2>/dev/null || true; echo 0283 0001 ff > /sys/bus/usb/drivers/xpad/new_id 2>/dev/null || true'"

ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0289", ATTR{idProduct}=="0200", MODE="0660", TAG+="uaccess", RUN+="/usr/bin/modprobe xpad", RUN+="/bin/sh -c 'echo 0289 0200 ff > /sys/bus/usb/drivers/xpad/new_id 2>/dev/null || true'"
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0283", ATTR{idProduct}=="0001", MODE="0660", TAG+="uaccess", RUN+="/usr/bin/modprobe xpad", RUN+="/bin/sh -c 'echo 0283 0001 ff > /sys/bus/usb/drivers/xpad/new_id 2>/dev/null || true'"
```

### Step 4: Configure Bootloader (for boot-time device connections)
Adding the quirk to your bootloader ensures that gamepads plugged in before system power-on enumerate properly.

#### For GRUB:
1. Edit `/etc/default/grub` and append to `GRUB_CMDLINE_LINUX_DEFAULT`:
   ```ini
   GRUB_CMDLINE_LINUX_DEFAULT="... usbcore.quirks=0289:0200:r,0283:0001:r"
   ```
2. Regenerate grub configuration:
   - On Debian / Ubuntu:
     ```bash
     sudo update-grub
     ```
   - On Arch Linux / Fedora / openSUSE:
     ```bash
     sudo grub-mkconfig -o /boot/grub/grub.cfg
     ```

#### For systemd-boot:
Append `usbcore.quirks=0289:0200:r,0283:0001:r` to the `options` line of your loader entry (e.g., in `/boot/loader/entries/*.conf` or `/efi/loader/entries/*.conf`).

#### For rEFInd:
Append `usbcore.quirks=0289:0200:r,0283:0001:r` to `options` in `/boot/refind_linux.conf` or `refind.conf`.

### Step 5: Apply Live Settings
Apply the settings to your running session without rebooting:
```bash
echo "0289:0200:r,0283:0001:r" | sudo tee /sys/module/usbcore/parameters/quirks
echo "0289 0200 ff" | sudo tee /sys/bus/usb/drivers/xpad/new_id
echo "0283 0001 ff" | sudo tee /sys/bus/usb/drivers/xpad/new_id
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=usb
```

---

## Verification and Testing

### 1. Check Connected USB Hardware
Run `lsusb`:
```bash
lsusb
```
Expected output:
- **Wired:** `Bus 001 Device 002: ID 0289:0200 Controller`
- **Wireless:** `Bus 001 Device 003: ID 0283:0001 Controller`

If you see `05ac:033e` or `20bc:5001`, the USB quirk parameter is not active. Recheck `cat /sys/module/usbcore/parameters/quirks`.

### 2. Verify Active Kernel Driver and Force Feedback
Inspect input device nodes:
```bash
cat /proc/bus/input/devices | grep -A 10 "Generic X-Box pad"
```
Verify the following values:
- `N: Name="Generic X-Box pad"`
- `H: Handlers=eventX jsY`
- `B: FF=107030000 0` (Non-zero bits confirm that force feedback rumble is active).

### 3. Interactive Input and Rumble Testing
Install event testing utilities for your distribution:

- **Arch Linux / Manjaro:**
  ```bash
  sudo pacman -S evtest linuxconsole
  ```
- **Ubuntu / Debian / Linux Mint:**
  ```bash
  sudo apt-get install evtest joystick
  ```
- **Fedora / RHEL:**
  ```bash
  sudo dnf install evtest joystick
  ```
- **openSUSE:**
  ```bash
  sudo zypper install evtest joystick
  ```

Run `evtest`:
```bash
sudo evtest
```
Select the entry corresponding to `Generic X-Box pad`. Test the analog triggers (`ABS_Z` and `ABS_RZ`) to verify analog values from 0 to 255.

### 4. Polling Rate Verification
In wired mode, the controller supports up to a 1000Hz polling rate. You can measure live event frequency using `evhz`:
```bash
git clone https://github.com/nickguletskii/evhz.git
cd evhz && make
sudo ./evhz
```
Move the analog sticks rapidly to observe polling rates up to 1000Hz.

---

## Troubleshooting Guide

The following matrix lists diagnostic steps and solutions for common conditions:

| Symptom | Probable Cause | Diagnostic Command | Remediation |
| :--- | :--- | :--- | :--- |
| Device displays `05ac:033e` or `20bc:5001` in `lsusb` | USB quirk flag not loaded into kernel memory | `cat /sys/module/usbcore/parameters/quirks` | Write quirk manually: `echo "0289:0200:r,0283:0001:r" \| sudo tee /sys/module/usbcore/parameters/quirks` and replug device. |
| Only LED 3 is illuminated on gamepad | Controller in degraded Android mode | Inspect physical LEDs on controller face | Ensure quirk is set before connecting. If using bootloader, ensure `usbcore.quirks` is in `/proc/cmdline`. |
| Device enumerates as `0289:0200` but no `/dev/input/js0` | `xpad` driver did not claim interface | `dmesg \| grep -i xpad` | Manually bind driver: `echo "0289 0200 ff" \| sudo tee /sys/bus/usb/drivers/xpad/new_id`. |
| No vibration in games or Steam | `ff-memless` module missing or Steam Input override | `lsmod \| grep ff_memless` | Run `sudo modprobe ff-memless`. In Steam controller settings, verify Xbox Configuration Support is enabled. |
| Quirk works on replug, but not after cold boot | Missing bootloader parameter | `cat /proc/cmdline \| grep quirks` | Add `usbcore.quirks=0289:0200:r,0283:0001:r` to bootloader command line (see Step 4 of Manual Installation). |
| Kernel warning during installation | Kernel version is below 7.2 | `uname -r` | Quirk flag `r` requires Linux >= 7.2 or a kernel with backported `USB_QUIRK_WINDOWS_CONFIG_REQ_SIZE`. |

---

## Uninstallation

To remove all configurations made by this fix:

```bash
sudo ./uninstall.sh
```

### Manual Cleanup
If removing files manually:
```bash
sudo rm -f /etc/modules-load.d/fantech-revolver-iii.conf
sudo rm -f /etc/tmpfiles.d/fantech-revolver-iii.conf
sudo rm -f /etc/udev/rules.d/90-fantech-revolver-iii.rules
```
If you edited `/etc/default/grub`, remove `usbcore.quirks=0289:0200:r,0283:0001:r` from `GRUB_CMDLINE_LINUX_DEFAULT` and regenerate grub configuration (`sudo grub-mkconfig -o /boot/grub/grub.cfg` or `sudo update-grub`).

Reload udev rules:
```bash
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=usb
```

---

## License

This project is licensed under the [MIT License](LICENSE).
