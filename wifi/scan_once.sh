#!/usr/bin/env bash
#
# scan_once.sh — non-interactive WiFi scan. Runs airodump-ng for a fixed number
# of seconds and writes the result to a CSV (APs + clients), instead of the
# full-screen live view. Handy for scripting / for handing the CSV to a tool.
#
#   sudo bash wifi/scan_once.sh <monitor-iface> [seconds] [out-prefix]
#   sudo bash wifi/scan_once.sh wlan1mon 25
#
# Find YOUR OWN network's row in the CSV: note its BSSID (AP MAC) and channel,
# then feed them to capture_handshake.sh. Only act on the AP that is yours.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then echo "Run as root: sudo bash $0 <monitor-iface> [seconds]" >&2; exit 1; fi

MON="${1:-}"
SECS="${2:-25}"
PREFIX="${3:-/tmp/netlab-scan}"

if [[ -z "$MON" ]]; then
  echo "Usage: sudo bash $0 <monitor-iface> [seconds] [out-prefix]" >&2
  echo "Get a monitor iface first: sudo bash wifi/monitor_mode.sh start wlan1" >&2
  exit 1
fi
if ! iw dev "$MON" info >/dev/null 2>&1; then
  echo "Interface '$MON' not found. Current interfaces:" >&2
  iw dev | awk '/Interface/{print "  "$2}' >&2
  exit 1
fi

rm -f "${PREFIX}"-*.csv 2>/dev/null || true
echo "[*] Scanning ~${SECS}s on $MON (writing CSV to ${PREFIX}-NN.csv)…"
# Run airodump in the background and stop it ourselves. This is more reliable
# than `timeout` for airodump (it handles SIGINT cleanly to flush the CSV),
# and lets us bail out early if the USB adapter drops off the bus.
airodump-ng --output-format csv --write-interval 2 -w "$PREFIX" "$MON" >/dev/null 2>&1 &
AIRO_PID=$!
for ((i=0; i<SECS; i++)); do
  sleep 1
  # If the monitor interface vanished (Alfa dropped off USB), stop waiting.
  if ! iw dev "$MON" info >/dev/null 2>&1; then
    echo "[!] $MON disappeared mid-scan — the adapter dropped off the USB bus." >&2
    break
  fi
  kill -0 "$AIRO_PID" 2>/dev/null || break   # airodump already exited
done
kill -INT "$AIRO_PID" 2>/dev/null || true
sleep 1
kill -KILL "$AIRO_PID" 2>/dev/null || true
wait "$AIRO_PID" 2>/dev/null || true

CSV=$(ls -1t "${PREFIX}"-*.csv 2>/dev/null | head -1 || true)
if [[ -z "$CSV" || ! -s "$CSV" ]]; then
  echo "[!] No CSV produced. Did the adapter stay on the bus? (dmesg | tail)" >&2
  exit 1
fi

echo "[*] Wrote: $CSV"
echo
echo "==> Access points seen (BSSID | CH | ENC | ESSID):"
# The AP table is the first CSV block, up to the blank line before "Station MAC".
awk -F',' '
  /^Station MAC/ {exit}
  NR>2 && $1 ~ /([0-9A-Fa-f]{2}:){5}/ {
    gsub(/^ +| +$/,"",$1); gsub(/^ +| +$/,"",$4); gsub(/^ +| +$/,"",$6); gsub(/^ +| +$/,"",$14);
    printf "    %-18s ch %-3s %-8s %s\n", $1, $4, $6, $14
  }' "$CSV"
echo
echo "[*] Note YOUR network's BSSID + channel, then:"
echo "    sudo bash wifi/capture_handshake.sh --iface $MON --bssid <YOURS> --channel <CH> --seconds 60"
