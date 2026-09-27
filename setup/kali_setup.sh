#!/usr/bin/env bash
#
# kali_setup.sh — prepare Kali Linux (on the Pi 5) for this lab.
#
# On Kali most tools already ship in kali-linux-default; this script just makes
# sure the ones this kit uses are present, installs the RTL8812AU driver for the
# AWUS036ACH the easy way (Kali packages it), and installs the small Python deps.
#
#   sudo bash setup/kali_setup.sh
#
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root:  sudo bash $0" >&2
  exit 1
fi

if ! grep -qi kali /etc/os-release 2>/dev/null; then
  echo "[!] This doesn't look like Kali. For Raspberry Pi OS use setup/install_deps.sh"
  read -r -p "    Continue anyway? [y/N] " a; [[ "$a" == "y" || "$a" == "Y" ]] || exit 1
fi

echo "==> apt update"
apt-get update

# On Kali these are usually already installed; apt is idempotent so this is safe.
echo "==> Ensuring the toolset is present"
apt-get install -y \
  aircrack-ng hashcat hcxtools hcxdumptool \
  wifite reaver bully \
  bettercap mitmproxy \
  kismet \
  nmap tcpdump tshark wireshark \
  macchanger \
  iw wireless-tools net-tools iproute2 \
  python3 python3-pip python3-venv \
  dkms build-essential

echo "==> Installing the RTL8812AU driver (AWUS036ACH) — Kali packages it"
# Kali ships a maintained DKMS package for this chipset; far simpler than a
# manual git build. If the metapackage name changes, fall back to the git build.
if apt-get install -y realtek-rtl88xxau-dkms; then
  echo "[OK] realtek-rtl88xxau-dkms installed."
else
  echo "[!] Package unavailable; falling back to the git DKMS build."
  bash "$(dirname "$0")/setup_adapter.sh"
fi
modprobe 88XXau 2>/dev/null || true

echo "==> Python packages"
if pip3 install --help 2>/dev/null | grep -q break-system-packages; then
  pip3 install --break-system-packages -r "$(dirname "$0")/../requirements.txt" || {
    python3 -m venv "$(dirname "$0")/../.venv"
    # shellcheck disable=SC1091
    source "$(dirname "$0")/../.venv/bin/activate"
    pip install -r "$(dirname "$0")/../requirements.txt"
  }
else
  pip3 install -r "$(dirname "$0")/../requirements.txt"
fi

echo
echo "==> Done. Verify the adapter + monitor mode:"
echo "    iw dev"
echo "    sudo bash setup/check_adapter.sh"
echo
echo "    Tip on Kali the Alfa usually appears as wlan1. Keep wlan0 or eth0 as"
echo "    your normal uplink, since enabling monitor mode drops the capture radio."
