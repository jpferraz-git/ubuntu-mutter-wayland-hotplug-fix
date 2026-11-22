#!/usr/bin/env bash
# ==============================================================================
# Ubuntu 24.04 Wayland HDMI Hotplug Crash Mitigator (Mutter 46 / Intel i915)
# Mitigates LP: #2117277 before the official libmutter-14-0 SRU lands
# ==============================================================================
set -euo pipefail

echo "[1/2] Checking GNOME Shell extensions that trigger mass window placement on hotplug..."
if command -v gnome-extensions >/dev/null 2>&1; then
    if gnome-extensions list --enabled | grep -q "tiling-assistant@ubuntu.com"; then
        gnome-extensions disable tiling-assistant@ubuntu.com
        echo "  -> Disabled tiling-assistant@ubuntu.com"
    else
        echo "  -> tiling-assistant@ubuntu.com is already disabled."
    fi
fi

echo "[2/2] Checking Intel i915 Panel Self-Refresh (PSR) kernel parameter..."
if lspci -k 2>/dev/null | grep -qi "i915"; then
    if grep -q "i915.enable_psr=0" /proc/cmdline; then
        echo "  -> i915.enable_psr=0 is already active in kernel cmdline."
    else
        echo "  -> Intel i915 detected. To prevent i915_hotplug_work_func CPU stalls on HDMI unplug,"
        echo "     run with --apply-grub (requires sudo) to add 'i915.enable_psr=0' to /etc/default/grub."
        if [[ "${1:-}" == "--apply-grub" ]]; then
            sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash i915.enable_psr=0"/' /etc/default/grub
            sudo update-grub
            echo "  -> Updated /etc/default/grub and ran update-grub. Reboot to apply kernel parameter."
        fi
    fi
fi

echo "Done!"
