#!/usr/bin/env bash
#
# install_deps.sh — install the system + Python dependencies for this lab
# on Raspberry Pi OS / Debian (Bookworm). Run once.
#
#   sudo bash setup/install_deps.sh
#
# Review this list before running. Nothing here is exotic — these are the
# standard packet-analysis and wireless tools.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root:  sudo bash $0" >&2
  exit 1
fi

echo "==> Updating apt package lists"
apt-get update

echo "==> Installing system packages"
apt-get install -y \
  git build-essential dkms linux-headers-"$(uname -r)" \
  aircrack-ng \
  tcpdump \
  tshark \
  wireshark \
  nmap \
  net-tools iproute2 wireless-tools iw \
  python3 python3-pip python3-venv \
  macchanger \
  hashcat \
  bettercap

# tshark asks whether non-root users may capture; default to no (safer).
echo "wireshark-common wireshark-common/install-setuid boolean false" | debconf-set-selections || true

echo "==> Installing Python packages"
# Bookworm marks the system Python as 'externally managed'. A project venv is
# the clean way; we fall back to --break-system-packages only if you insist.
if pip3 install --help 2>/dev/null | grep -q break-system-packages; then
  pip3 install --break-system-packages -r "$(dirname "$0")/../requirements.txt" || {
    echo "Falling back to a virtualenv at ./.venv"
    python3 -m venv "$(dirname "$0")/../.venv"
    # shellcheck disable=SC1091
    source "$(dirname "$0")/../.venv/bin/activate"
    pip install -r "$(dirname "$0")/../requirements.txt"
  }
else
  pip3 install -r "$(dirname "$0")/../requirements.txt"
fi

echo
echo "==> Done. Next: sudo bash setup/setup_adapter.sh   (builds the RTL8812AU driver)"
