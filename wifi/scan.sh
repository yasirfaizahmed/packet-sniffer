#!/usr/bin/env bash
#
# scan.sh — list nearby WiFi networks and their clients using airodump-ng.
#
# You need this to find YOUR OWN network's BSSID (the AP's MAC) and channel,
# which the capture step requires. It shows every AP in range; you will only
# act against the one that is yours.
#
#   sudo bash wifi/scan.sh <monitor-iface>      # e.g. wlan1mon
#
# Get a monitor interface first:  sudo bash wifi/monitor_mode.sh start wlan1
set -euo pipefail

if [[ $EUID -ne 0 ]]; then echo "Run as root." >&2; exit 1; fi

MON="${1:-}"
if [[ -z "$MON" ]]; then
  echo "Usage: sudo bash $0 <monitor-iface>   (see: iw dev)" >&2
  echo "Enable monitor mode first: sudo bash wifi/monitor_mode.sh start wlan1" >&2
  exit 1
fi

cat <<'EOF'
[*] Launching airodump-ng. Read the columns:
      BSSID   = the access point's MAC        (you need YOUR router's)
      CH      = channel                       (you need YOUR router's)
      ENC/CIPHER/AUTH = WPA2/CCMP/PSK etc.
      ESSID   = network name
    Lower table = STATIONs (clients) and which BSSID they're associated with.

    Note your OWN network's BSSID + CH, then press Ctrl-C.
EOF
echo
sleep 2
exec airodump-ng "$MON"
