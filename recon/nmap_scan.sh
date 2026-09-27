#!/usr/bin/env bash
#
# nmap_scan.sh — guided network mapping of YOUR OWN subnet with nmap.
#
# Once you know which hosts are on your LAN (sniffing/lan_hosts.py), nmap tells
# you what each one is running: open ports, service versions, and an OS guess.
# This is how you build an inventory of your own network and spot things you
# forgot were listening (an old IoT device, an exposed admin panel, etc.).
#
#   sudo bash recon/nmap_scan.sh --target 192.168.1.0/24 --profile discover
#   sudo bash recon/nmap_scan.sh --target 192.168.1.10  --profile services
#   sudo bash recon/nmap_scan.sh --target 192.168.1.10  --profile full
#
# Profiles:
#   discover  fast ping/ARP sweep — who's up            (-sn)
#   services  open TCP ports + service/version detection (-sV)
#   full      services + OS detection + default scripts  (-A)  [slower, noisier]
#   vuln      run nmap's 'vuln' NSE scripts against a host (needs services first)
#
# nmap only touches the target you give it. Only scan your own network — active
# scanning of others' hosts is intrusive and, off your own network, unlawful.
set -euo pipefail

TARGET="" PROFILE="discover" OUTDIR="captures/nmap"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)  TARGET="$2"; shift 2;;
    --profile) PROFILE="$2"; shift 2;;
    --outdir)  OUTDIR="$2"; shift 2;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
done

command -v nmap >/dev/null || { echo "Install nmap (Kali: apt install nmap)." >&2; exit 1; }
[[ -n "$TARGET" ]] || { echo "Need --target (an IP, range, or CIDR on YOUR network)." >&2; exit 1; }

mkdir -p "$OUTDIR"
STAMP=$(date +%Y%m%d-%H%M%S)
BASE="$OUTDIR/${PROFILE}-${STAMP}"

echo "[*] nmap profile '$PROFILE' against $TARGET"
echo "[*] Only scan networks/hosts you own or are authorized to test."
echo "[*] Output saved as ${BASE}.*"
echo

case "$PROFILE" in
  discover) FLAGS=(-sn -PR);;                      # ARP/ping sweep, no ports
  services) FLAGS=(-sV --top-ports 1000);;         # service/version detect
  full)     FLAGS=(-A -T4);;                        # OS + scripts + traceroute
  vuln)     FLAGS=(-sV --script vuln);;            # NSE vuln scripts
  *) echo "Unknown profile '$PROFILE'." >&2; exit 1;;
esac

# -oA writes .nmap/.gnmap/.xml so you can grep or import into other tools later.
# OS detection / -A need root; ARP sweep benefits from it too.
RUN=(nmap "${FLAGS[@]}" -oA "$BASE" "$TARGET")
if [[ $EUID -ne 0 && ( "$PROFILE" == "full" || "$PROFILE" == "discover" ) ]]; then
  echo "[!] Tip: run with sudo for accurate OS detection / ARP discovery."
fi
echo "[*] Running: ${RUN[*]}"
"${RUN[@]}"

echo
echo "[*] Done. Human-readable: ${BASE}.nmap  | grep-able: ${BASE}.gnmap  | XML: ${BASE}.xml"
[[ "$PROFILE" == "discover" ]] && \
  echo "[*] Next: pick a host and run --profile services on it."
