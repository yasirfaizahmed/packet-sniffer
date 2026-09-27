#!/usr/bin/env bash
#
# wifite_guided.sh — drive wifite2 (Kali's all-in-one WiFi auditor) but LOCKED
# to a single BSSID: your own. wifite normally scans and attacks everything in
# range; this wrapper forces the --bssid filter so it only ever touches the AP
# you name, after you confirm it's yours.
#
# wifite orchestrates the same steps you learned manually (monitor mode,
# handshake/PMKID capture, and cracking) — a good way to see the whole pipeline
# automated once you understand each piece.
#
#   sudo bash wifi/wifite_guided.sh --bssid AA:BB:CC:DD:EE:FF [--iface wlan1] \
#        [--dict /usr/share/wordlists/rockyou.txt]
#
set -euo pipefail

if [[ $EUID -ne 0 ]]; then echo "Run as root." >&2; exit 1; fi
command -v wifite >/dev/null || { echo "wifite not found (Kali: apt install wifite)." >&2; exit 1; }

BSSID="" IFACE="" DICT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bssid) BSSID="$2"; shift 2;;
    --iface) IFACE="$2"; shift 2;;
    --dict)  DICT="$2"; shift 2;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
done

if [[ -z "$BSSID" ]]; then
  echo "Refusing to run without --bssid. This wrapper only targets ONE AP: yours." >&2
  echo "Find it with: sudo bash wifi/scan.sh <monitor-iface>" >&2
  exit 1
fi

cat <<EOF

  About to run wifite restricted to a single AP:
      BSSID : $BSSID
$( [[ -n "$IFACE" ]] && echo "      iface : $IFACE" )
  Do this ONLY on an access point you own or are authorized to test.

EOF
read -r -p "  Type YES if this AP is yours: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || { echo "Aborted."; exit 1; }

ARGS=(--bssid "$BSSID" --kill)
[[ -n "$IFACE" ]] && ARGS+=(-i "$IFACE")
[[ -n "$DICT"  ]] && ARGS+=(--dict "$DICT")

echo "[*] Launching: wifite ${ARGS[*]}"
echo "[*] wifite will handle monitor mode; when done, it drops back to managed."
exec wifite "${ARGS[@]}"
