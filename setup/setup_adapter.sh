#!/usr/bin/env bash
#
# setup_adapter.sh — build & install the RTL8812AU driver (DKMS) so the
# Alfa AWUS036ACH can do monitor mode and packet injection on the Pi 5.
#
#   sudo bash setup/setup_adapter.sh
#
# Why this is needed:
#   The AWUS036ACH uses the Realtek RTL8812AU chipset. The driver that ships
#   in the kernel gives you normal WiFi but NOT reliable monitor mode /
#   injection. The community aircrack-ng/rtl8812au driver adds those. DKMS
#   rebuilds it automatically whenever your kernel updates.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root:  sudo bash $0" >&2
  exit 1
fi

SRC=/usr/src/rtl8812au-git
REPO=https://github.com/aircrack-ng/rtl8812au.git

echo "==> Ensuring build prerequisites"
apt-get install -y git build-essential dkms bc \
  "raspberrypi-kernel-headers" 2>/dev/null || \
  apt-get install -y git build-essential dkms bc linux-headers-"$(uname -r)"

echo "==> Fetching the driver source into $SRC"
if [[ -d "$SRC/.git" ]]; then
  git -C "$SRC" pull --ff-only
else
  rm -rf "$SRC"
  git clone --depth 1 "$REPO" "$SRC"
fi

# The driver's Makefile targets ARM64 correctly, but be explicit for the Pi 5.
echo "==> Installing via DKMS (this compiles the module; takes a few minutes)"
cd "$SRC"

# Remove any half-installed prior version so 'dkms add' doesn't error out.
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' dkms.conf 2>/dev/null || echo "5.6.4.2")
dkms remove -m rtl8812au -v "$VER" --all 2>/dev/null || true

if [[ -x ./dkms-install.sh ]]; then
  ./dkms-install.sh
else
  make dkms_install
fi

echo
echo "==> Loading the module"
modprobe 88XXau 2>/dev/null || modprobe 8812au 2>/dev/null || true

cat <<'EOF'

==> Done.
    Plug in the AWUS036ACH (if it wasn't already) and check it appeared:

      iw dev            # should list a new interface, usually wlan1
      lsusb             # should show a Realtek 8812au device

    If the interface is missing, unplug/replug the adapter, or reboot so the
    freshly-built module is picked up cleanly:

      sudo reboot

    Then verify monitor mode:  sudo bash setup/check_adapter.sh
EOF
