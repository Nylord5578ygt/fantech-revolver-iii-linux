#!/usr/bin/env bash
# ==============================================================================
# Fantech Revolver III (WGP12S) & ShanWan Gamepad Linux Fix Installer
# ==============================================================================
set -euo pipefail

# Ensure script is run as root
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Elevating privileges with sudo..."
    exec sudo "$0" "$@"
fi

echo "=================================================================="
echo " Installing Fantech Revolver III (WGP12S) Linux Fix..."
echo "=================================================================="

# Check kernel version (recommend >= 7.2 for USB_QUIRK_WINDOWS_CONFIG_REQ_SIZE)
KERNEL_MAJOR=$(uname -r | cut -d. -f1)
KERNEL_MINOR=$(uname -r | cut -d. -f2)

if [ "$KERNEL_MAJOR" -lt 7 ] || { [ "$KERNEL_MAJOR" -eq 7 ] && [ "$KERNEL_MINOR" -lt 2 ]; }; then
    echo "WARNING: Detected kernel $(uname -r)."
    echo "The 'r' (USB_QUIRK_WINDOWS_CONFIG_REQ_SIZE) quirk flag was officially merged in Linux 7.2+."
    echo "If your kernel does not support the 'r' quirk flag, descriptor negotiation might still fail."
else
    echo "✓ Detected kernel $(uname -r) with built-in 255-byte config quirk support."
fi

# 1. Configure module loading
echo "-> Configuring /etc/modules-load.d/fantech-revolver-iii.conf..."
cat << 'EOF' > /etc/modules-load.d/fantech-revolver-iii.conf
xpad
EOF

# 2. Configure systemd-tmpfiles runtime parameter
echo "-> Configuring /etc/tmpfiles.d/fantech-revolver-iii.conf..."
cat << 'EOF' > /etc/tmpfiles.d/fantech-revolver-iii.conf
w /sys/module/usbcore/parameters/quirks - - - - 0289:0200:r,0283:0001:r
EOF

# 3. Configure udev rules
echo "-> Configuring /etc/udev/rules.d/90-fantech-revolver-iii.rules..."
cat << 'EOF' > /etc/udev/rules.d/90-fantech-revolver-iii.rules
# Fantech Revolver III (WGP12S) - Register Wired (0289:0200) and 2.4GHz Wireless (0283:0001) X-Input IDs with xpad
ACTION=="add", SUBSYSTEM=="module", KERNEL=="xpad", RUN+="/bin/sh -c 'echo 0289 0200 ff > /sys/bus/usb/drivers/xpad/new_id 2>/dev/null || true; echo 0283 0001 ff > /sys/bus/usb/drivers/xpad/new_id 2>/dev/null || true'"

ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0289", ATTR{idProduct}=="0200", MODE="0660", TAG+="uaccess", RUN+="/usr/bin/modprobe xpad", RUN+="/bin/sh -c 'echo 0289 0200 ff > /sys/bus/usb/drivers/xpad/new_id 2>/dev/null || true'"
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0283", ATTR{idProduct}=="0001", MODE="0660", TAG+="uaccess", RUN+="/usr/bin/modprobe xpad", RUN+="/bin/sh -c 'echo 0283 0001 ff > /sys/bus/usb/drivers/xpad/new_id 2>/dev/null || true'"
EOF

# 4. Apply live kernel parameters
echo "-> Applying live parameters..."
modprobe xpad || true
modprobe ff-memless || true
if [ -w /sys/module/usbcore/parameters/quirks ]; then
    echo "0289:0200:r,0283:0001:r" > /sys/module/usbcore/parameters/quirks
fi
if [ -w /sys/bus/usb/drivers/xpad/new_id ]; then
    echo "0289 0200 ff" > /sys/bus/usb/drivers/xpad/new_id 2>/dev/null || true
    echo "0283 0001 ff" > /sys/bus/usb/drivers/xpad/new_id 2>/dev/null || true
fi

# 5. Configure GRUB bootloader if present
if [ -f /etc/default/grub ]; then
    echo "-> Detected GRUB. Updating kernel command line..."
    if grep -q "usbcore.quirks=" /etc/default/grub; then
        sed -i 's/usbcore.quirks=[^ "]*/usbcore.quirks=0289:0200:r,0283:0001:r/g' /etc/default/grub
    else
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\([^"]*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 usbcore.quirks=0289:0200:r,0283:0001:r"/' /etc/default/grub
    fi

    if command -v grub-mkconfig >/dev/null 2>&1 && [ -f /boot/grub/grub.cfg ]; then
        echo "-> Regenerating /boot/grub/grub.cfg..."
        grub-mkconfig -o /boot/grub/grub.cfg
    elif command -v update-grub >/dev/null 2>&1; then
        update-grub
    fi
fi

# 6. Reload udev rules
echo "-> Reloading udev rules..."
udevadm control --reload-rules
udevadm trigger --subsystem-match=usb

echo "=================================================================="
echo " Installation Complete!"
echo " Please replug your Fantech Revolver III USB cable or 2.4G dongle."
echo "=================================================================="
