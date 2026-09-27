#!/usr/bin/env bash
#
# monitor_mode.sh — enable or disable monitor mode on a wireless interface.
# A thin, readable wrapper around `airmon-ng` / `iw` so you can see exactly
# what's happening. Monitor mode lets the radio hear ALL nearby 802.11 frames,
# not just those addressed to you — the basis of WiFi capture.
#
#   sudo bash wifi/monitor_mode.sh start wlan1
#   sudo bash wifi/monitor_mode.sh stop  wlan1
#   sudo bash wifi/monitor_mode.sh status
#
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root." >&2
  exit 1
fi

ACTION="${1:-status}"
IFACE="${2:-}"

pick_iface() {
  iw dev | awk '/Interface/{print $2}' | grep -v '^wlan0$' | head -n1 \
    || iw dev | awk '/Interface/{print $2}' | head -n1
}

case "$ACTION" in
  start)
    IFACE="${IFACE:-$(pick_iface)}"
    echo "==> Killing processes that interfere with monitor mode (NetworkManager, wpa_supplicant)…"
    # airmon-ng check kill stops them cleanly; note this drops that radio's
    # normal WiFi connection, so keep your uplink on Ethernet or wlan0.
    airmon-ng check kill || true
    echo "==> Enabling monitor mode on $IFACE"
    airmon-ng start "$IFACE"
    echo
    echo "New monitor interface:"
    iw dev | awk '/Interface/{print "    "$2}'
    ;;
  stop)
    IFACE="${IFACE:-$(pick_iface)}"
    echo "==> Disabling monitor mode on $IFACE"
    airmon-ng stop "$IFACE" || {
      ip link set "$IFACE" down
      iw dev "$IFACE" set type managed
      ip link set "$IFACE" up
    }
    echo "==> Restarting NetworkManager"
    systemctl restart NetworkManager 2>/dev/null || service network-manager restart 2>/dev/null || true
    ;;
  status)
    iw dev | sed 's/^/    /'
    ;;
  *)
    echo "Usage: sudo bash $0 {start|stop|status} [interface]" >&2
    exit 1
    ;;
esac
