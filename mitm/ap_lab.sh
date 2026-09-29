#!/usr/bin/env bash
#
# ap_lab.sh — stand up YOUR OWN access point on the Pi so a test device YOU OWN
# connects through it, still reaches the internet (NAT'd out your router uplink),
# and every packet transits the Pi where you can inspect it.
#
# THIS IS NOT AN "EVIL TWIN." It broadcasts an SSID of YOUR choosing (not an
# impersonation of someone else's network), and it's meant for a device you own
# and knowingly connect. That's a legitimate MITM lab; luring other people's
# devices with a look-alike SSID is not, and this kit doesn't do that.
#
# Once clients route through the Pi you can:
#   - see cleartext + DNS + SNI + metadata:  tcdump -i <IFACE> -n
#   - decrypt HTTPS *with consent*: run mitm/inspect_own_device.sh and install
#     its CA on your own test device (http://mitm.it). No CA on the device =
#     HTTPS stays encrypted, which is correct.
#
# Usage:
#   sudo bash mitm/ap_lab.sh start --iface wlan1 --uplink eth0 \
#        --ssid MyLabAP --pass labpass123 --channel 6
#   sudo bash mitm/ap_lab.sh start --ssid MyLabAP --open   # OPEN (no password)
#   sudo bash mitm/ap_lab.sh status
#   sudo bash mitm/ap_lab.sh stop
#
# --open     : run an OPEN network (no passphrase). Traffic is then unencrypted
#              on the air — a vivid demo of why open WiFi is unsafe. Your own AP.
# --serve-ca : also generate the mitmproxy CA and host it at http://<AP-IP>:8000/
#              so the connected device can install it before you run the proxy.
#
# Requires: hostapd, dnsmasq  (sudo apt install hostapd dnsmasq)
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; s/^#$//' | sed '$d'; exit 0
fi
if [[ $EUID -ne 0 ]]; then echo "Run as root: sudo bash $0 ..." >&2; exit 1; fi

ACTION="${1:-}"; shift || true
IFACE="wlan1" UPLINK="eth0" SSID="MyLabAP" PASS="" CHANNEL="6" OPEN=0 SERVE_CA=0
CA_CONFDIR="/etc/netlab-mitm"; CA_PORT=8000   # where the mitmproxy CA lives / is served
AP_ADDR="10.42.0.1"; AP_CIDR="10.42.0.1/24"; AP_NET="10.42.0.0/24"
DHCP_LO="10.42.0.10"; DHCP_HI="10.42.0.100"
RUN=/run/netlab-ap; HCONF="$RUN/hostapd.conf"; DCONF="$RUN/dnsmasq.conf"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iface)   IFACE="$2"; shift 2;;
    --uplink)  UPLINK="$2"; shift 2;;
    --ssid)    SSID="$2"; shift 2;;
    --pass)    PASS="$2"; shift 2;;
    --channel) CHANNEL="$2"; shift 2;;
    --open)     OPEN=1; shift;;
    --serve-ca) SERVE_CA=1; shift;;
    *) echo "Unknown arg: $1 (see --help)" >&2; exit 1;;
  esac
done

nat_rules() {  # $1 = -A (add) or -D (delete)
  iptables -t nat "$1" POSTROUTING -s "$AP_NET" -o "$UPLINK" -j MASQUERADE 2>/dev/null || true
  iptables "$1" FORWARD -i "$IFACE" -o "$UPLINK" -j ACCEPT 2>/dev/null || true
  iptables "$1" FORWARD -i "$UPLINK" -o "$IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
  # MSS clamping: without this, "DNS works but pages hang / no internet" on the
  # client — forwarded TCP packets are too big for a smaller-MTU WAN (PPPoE/fibre
  # ~1492) and get dropped. Clamp SYN MSS so both ends negotiate a size that fits.
  iptables -t mangle "$1" FORWARD -o "$UPLINK" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
  iptables -t mangle "$1" FORWARD -o "$UPLINK" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1412 2>/dev/null || true
}

# Delete EVERY copy of one rule (handles duplicates) in a given iptables binary.
del_all() {  # <ipt> <table> <chain> <args...>
  local ipt="$1" tbl="$2" chain="$3"; shift 3
  local topt=(); [[ "$tbl" != filter ]] && topt=(-t "$tbl")
  local n=0
  while "$ipt" "${topt[@]}" -C "$chain" "$@" 2>/dev/null; do
    "$ipt" "${topt[@]}" -D "$chain" "$@" 2>/dev/null || break
    n=$((n + 1)); [[ $n -gt 30 ]] && break
  done
}

# Remove every rule this lab AND inspect_own_device.sh may add — in BOTH iptables
# backends, because switching backends leaves the other's rules live (that's the
# "stopped but still no internet" trap). Targeted (not a blanket flush), so it
# never touches unrelated firewall rules.
purge_all_rules() {
  local backends=() b
  for b in iptables-legacy iptables-nft; do command -v "$b" >/dev/null 2>&1 && backends+=("$b"); done
  [[ ${#backends[@]} -eq 0 ]] && backends=(iptables)
  local ipt
  for ipt in "${backends[@]}"; do
    del_all "$ipt" nat    POSTROUTING -s "$AP_NET" -o "$UPLINK" -j MASQUERADE
    del_all "$ipt" nat    PREROUTING  -i "$IFACE" -p tcp --dport 80  -j REDIRECT --to-port 8080
    del_all "$ipt" nat    PREROUTING  -i "$IFACE" -p tcp --dport 443 -j REDIRECT --to-port 8080
    del_all "$ipt" filter FORWARD -i "$IFACE" -o "$UPLINK" -j ACCEPT
    del_all "$ipt" filter FORWARD -i "$UPLINK" -o "$IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
    del_all "$ipt" filter FORWARD -i "$IFACE" -p udp --dport 443 -j REJECT
    del_all "$ipt" mangle FORWARD -o "$UPLINK" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
    del_all "$ipt" mangle FORWARD -o "$UPLINK" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1412
  done
}

do_stop() {
  echo "[*] Tearing down the AP lab…"
  [[ -f "$RUN/hostapd.pid" ]] && kill "$(cat "$RUN/hostapd.pid")" 2>/dev/null || true
  [[ -f "$RUN/dnsmasq.pid" ]] && kill "$(cat "$RUN/dnsmasq.pid")" 2>/dev/null || true
  [[ -f "$RUN/caserver.pid" ]] && kill "$(cat "$RUN/caserver.pid")" 2>/dev/null || true
  pkill -f "$HCONF" 2>/dev/null || true
  pkill -x mitmproxy 2>/dev/null || true    # stop a transparent proxy if one is up
  purge_all_rules                           # NAT + redirect + QUIC + MSS, both backends
  ip addr flush dev "$IFACE" 2>/dev/null || true
  ip link set "$IFACE" down 2>/dev/null || true
  nmcli dev set "$IFACE" managed yes >/dev/null 2>&1 || true
  rm -rf "$RUN"
  echo "[*] Done. $IFACE returned to NetworkManager; all lab rules removed (both iptables backends)."
}

case "$ACTION" in
  status)
    echo "== interfaces =="; ip -br addr show "$IFACE" 2>/dev/null || echo "  $IFACE absent"
    echo "== hostapd =="; pgrep -af "$HCONF" || echo "  not running"
    echo "== dnsmasq =="; [[ -f "$RUN/dnsmasq.pid" ]] && pgrep -af dnsmasq | grep -q "$DCONF" && echo "  running" || echo "  not running"
    exit 0;;
  stop) do_stop; exit 0;;
  start) : ;;
  *) echo "Usage: sudo bash $0 {start|stop|status} [--iface .. --uplink .. --ssid .. --pass .. --channel ..]" >&2; exit 1;;
esac

# --- start ------------------------------------------------------------------
for t in hostapd dnsmasq; do
  command -v "$t" >/dev/null || { echo "Missing '$t'. Install: sudo apt install hostapd dnsmasq" >&2; exit 1; }
done
if [[ "$OPEN" -ne 1 && ( -z "$PASS" || ${#PASS} -lt 8 ) ]]; then
  echo "Set --pass to a WPA2 passphrase of 8+ chars (YOUR AP's password), or use --open." >&2; exit 1
fi
if ! iw dev "$IFACE" info >/dev/null 2>&1; then
  echo "Interface '$IFACE' not found (need an AP-capable radio, e.g. the Alfa wlan1)." >&2; exit 1
fi

cat <<EOF

  About to run an ACCESS POINT you control:
    AP radio : $IFACE      SSID: "$SSID"   channel: $CHANNEL
    security : $( [[ "$OPEN" -eq 1 ]] && echo "OPEN — no password, traffic UNENCRYPTED on the air" || echo "WPA2-PSK" )
    uplink   : $UPLINK  ->  internet (NAT)
    AP subnet: $AP_NET   (Pi = $AP_ADDR, DHCP $DHCP_LO-$DHCP_HI)

  Connect ONLY a device you own to this AP. This is a lab on your own gear,
  not an impersonation of another network.
EOF
read -r -p "  Type YES to confirm this is your own AP + your own client: " C
[[ "$C" == "YES" ]] || { echo "Aborted."; exit 1; }

mkdir -p "$RUN"
# Let us own the radio (NetworkManager off it), give it the gateway IP.
nmcli dev set "$IFACE" managed no >/dev/null 2>&1 || true
ip link set "$IFACE" down 2>/dev/null || true
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add "$AP_CIDR" dev "$IFACE"
ip link set "$IFACE" up

cat > "$HCONF" <<EOF
interface=$IFACE
driver=nl80211
ssid=$SSID
hw_mode=g
channel=$CHANNEL
wmm_enabled=1
auth_algs=1
EOF
if [[ "$OPEN" -ne 1 ]]; then
  cat >> "$HCONF" <<EOF
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_passphrase=$PASS
EOF
fi   # else: no wpa lines = an OPEN (unencrypted) network

cat > "$DCONF" <<EOF
interface=$IFACE
bind-interfaces
dhcp-range=$DHCP_LO,$DHCP_HI,255.255.255.0,12h
dhcp-option=option:router,$AP_ADDR
dhcp-option=option:dns-server,$AP_ADDR
server=1.1.1.1
server=8.8.8.8
log-queries
log-facility=$RUN/dns.log
EOF

echo 1 > /proc/sys/net/ipv4/ip_forward
nat_rules -A

dnsmasq --conf-file="$DCONF" --pid-file="$RUN/dnsmasq.pid"
hostapd -B -P "$RUN/hostapd.pid" "$HCONF"
sleep 1
if ! pgrep -af "$HCONF" >/dev/null; then
  echo "hostapd failed to start. Debug:  hostapd $HCONF   (run without -B to see why)." >&2
  do_stop; exit 1
fi

# --serve-ca: generate the mitmproxy CA (if needed) and serve it on the AP so the
# connected device can install it before you run the transparent proxy.
CA_URL=""
if [[ "$SERVE_CA" -eq 1 ]]; then
  mkdir -p "$CA_CONFDIR"
  if [[ ! -f "$CA_CONFDIR/mitmproxy-ca-cert.pem" ]]; then
    if command -v mitmdump >/dev/null 2>&1; then
      echo "[*] Generating the mitmproxy CA in $CA_CONFDIR (first run)…"
      timeout 5 mitmdump --set confdir="$CA_CONFDIR" >/dev/null 2>&1 || true
    else
      echo "[!] mitmdump not found — install mitmproxy to use --serve-ca." >&2
    fi
  fi
  # Honest, clearly-labelled lab landing page (states "your own device only";
  # no impersonation). It's the index for the CA download links.
  PORTAL="$(cd "$(dirname "$0")" && pwd)/portal/index.html"
  [[ -f "$PORTAL" ]] && cp -f "$PORTAL" "$CA_CONFDIR/index.html"
  # Serve ONLY on the AP address (not the LAN/uplink) so the cert isn't offered
  # to the wider network.
  python3 -m http.server "$CA_PORT" --bind "$AP_ADDR" --directory "$CA_CONFDIR" >/dev/null 2>&1 &
  echo $! > "$RUN/caserver.pid"
  CA_URL="http://$AP_ADDR:$CA_PORT/"
fi

cat <<EOF

============================================================
 AP is UP:  SSID "$SSID"  (ch $CHANNEL)  on $IFACE
 Connect your OWN test device to it. It gets internet via $UPLINK.

 Inspect the client's traffic (all of it transits the Pi):
   cleartext + DNS + SNI + metadata:
     sudo tcpdump -i $IFACE -n
   which domains it looks up (dnsmasq log):
     tail -f $RUN/dns.log
EOF
if [[ "$SERVE_CA" -eq 1 ]]; then
cat <<EOF
   HTTPS, decrypted (consent):
     1) on the device, open  $CA_URL  and install + TRUST the CA
        (Android: mitmproxy-ca-cert.cer ; iOS: .pem, then Certificate Trust Settings)
     2) then:  sudo bash mitm/inspect_own_device.sh --iface $IFACE
EOF
else
cat <<EOF
   HTTPS, decrypted (consent): re-run with --serve-ca to also host the CA, or
   install it manually, THEN:  sudo bash mitm/inspect_own_device.sh --iface $IFACE
EOF
fi
cat <<EOF

 Tear down:  sudo bash mitm/ap_lab.sh stop
============================================================
EOF
