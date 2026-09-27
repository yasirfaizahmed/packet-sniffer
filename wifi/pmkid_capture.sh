#!/usr/bin/env bash
#
# pmkid_capture.sh — capture a PMKID from YOUR OWN AP (the "clientless" attack).
#
# WHY THIS IS INTERESTING (vs. the 4-way handshake):
#   Some APs include a PMKID in the first EAPOL message of association. The PMKID
#   is derived from the PMK (your passphrase-derived master key), the AP MAC and
#   the client MAC. If the AP offers it, you can grab it WITHOUT waiting for a
#   real client to connect and WITHOUT any deauth — just by associating yourself.
#   Like the handshake, it only lets you TEST guesses offline; it never reveals
#   the password, and a strong passphrase stays safe. Not all APs are vulnerable
#   (it depends on the AP), which is itself a useful thing to discover about your
#   own router.
#
# Uses hcxdumptool (capture) + hcxpcapngtool (convert to hashcat 22000).
#
#   sudo bash wifi/pmkid_capture.sh --iface wlan1mon --bssid AA:BB:CC:DD:EE:FF \
#        [--out captures/pmkid] [--seconds 60]
#
# Requires monitor mode:  sudo bash wifi/monitor_mode.sh start wlan1
set -euo pipefail

if [[ $EUID -ne 0 ]]; then echo "Run as root." >&2; exit 1; fi

IFACE="" BSSID="" OUT="captures/pmkid" SECONDS_RUN=60

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iface)   IFACE="$2"; shift 2;;
    --bssid)   BSSID="$2"; shift 2;;
    --out)     OUT="$2"; shift 2;;
    --seconds) SECONDS_RUN="$2"; shift 2;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
done

if [[ -z "$IFACE" || -z "$BSSID" ]]; then
  echo "Need --iface (monitor) and --bssid (YOUR AP). See --help." >&2
  exit 1
fi
command -v hcxdumptool >/dev/null || { echo "Install hcxdumptool (Kali: apt install hcxdumptool)." >&2; exit 1; }

cat <<EOF

  About to attempt PMKID capture from AP:  $BSSID  on $IFACE
  Do this ONLY on an access point you own or are authorized to test.

EOF
read -r -p "  Type YES if this AP is yours: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || { echo "Aborted."; exit 1; }

mkdir -p "$(dirname "$OUT")"

# Restrict hcxdumptool to ONLY your BSSID via a filter list (filtermode=2 = only
# attack listed APs). This is what keeps the tool from touching your neighbours.
FILTER="$(mktemp)"
echo "${BSSID//:/}" > "$FILTER"     # hcxdumptool wants the MAC without colons
trap 'rm -f "$FILTER"' EXIT

PCAP="${OUT}.pcapng"
echo "[*] Capturing to $PCAP for ${SECONDS_RUN}s (restricted to $BSSID)…"
echo "[*] Note: hcxdumptool flags vary by version; if this errors, check 'hcxdumptool --help'."

# Common hcxdumptool 6.2.x invocation. --filtermode=2 + --filterlist_ap limits
# targeting to your AP only. Runs for the given time then stops.
timeout "${SECONDS_RUN}s" hcxdumptool -i "$IFACE" -o "$PCAP" \
  --filterlist_ap="$FILTER" --filtermode=2 --enable_status=3 \
  || echo "[*] hcxdumptool exited (timeout or version flag mismatch)."

echo
echo "[*] Converting to hashcat 22000 format…"
OUT22000="${OUT}.hc22000"
if hcxpcapngtool -o "$OUT22000" "$PCAP" 2>/dev/null && [[ -s "$OUT22000" ]]; then
  echo "[OK] Wrote $OUT22000"
  grep -q '^WPA\*01' "$OUT22000" 2>/dev/null && echo "     Contains a PMKID (type 01)."
  grep -q '^WPA\*02' "$OUT22000" 2>/dev/null && echo "     Contains an EAPOL handshake (type 02)."
  echo "     Crack it:  hashcat -m 22000 $OUT22000 /usr/share/wordlists/rockyou.txt"
  echo "     or:        sudo bash wifi/crack_handshake.sh --cap $PCAP --engine hashcat"
else
  echo "[!] No PMKID/handshake extracted. Your AP may not expose a PMKID —"
  echo "    that's fine; fall back to wifi/capture_handshake.sh (4-way handshake)."
fi
