#!/usr/bin/env bash
# ==============================================================================
# Fantech Revolver III (WGP12S) Linux Fix Uninstaller
# ==============================================================================
set -euo pipefail

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Elevating privileges with sudo..."
    exec sudo "$0" "$@"
fi

echo "=================================================================="
echo " Uninstalling Fantech Revolver III (WGP12S) Linux Fix..."
echo "=================================================================="

rm -f /etc/modules-load.d/fantech-revolver-iii.conf
rm -f /etc/tmpfiles.d/fantech-revolver-iii.conf
rm -f /etc/udev/rules.d/90-fantech-revolver-iii.rules

if [ -f /etc/default/grub ] && grep -q "0289:0200:r" /etc/default/grub; then
    echo "-> Removing usbcore.quirks from /etc/default/grub..."
    sed -i 's/[ ]*usbcore.quirks=0289:0200:r,0283:0001:r//g' /etc/default/grub
    if command -v grub-mkconfig >/dev/null 2>&1 && [ -f /boot/grub/grub.cfg ]; then
        grub-mkconfig -o /boot/grub/grub.cfg
    elif command -v update-grub >/dev/null 2>&1; then
        update-grub
    fi
fi

udevadm control --reload-rules
udevadm trigger --subsystem-match=usb

echo "=================================================================="
echo " Uninstallation Complete!"
echo "=================================================================="
