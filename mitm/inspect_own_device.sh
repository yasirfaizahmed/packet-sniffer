#!/usr/bin/env bash
#
# inspect_own_device.sh — inspect the HTTPS traffic of a device YOU OWN, the
# honest way: a transparent proxy plus a CA certificate you install on that
# device with its consent. This is how you actually "see the sites" a device
# talks to, decrypted — because you put your own trust anchor on your own phone.
#
# WHY THIS, AND NOT COVERT INTERCEPTION:
#   Modern traffic is HTTPS. You cannot read it just by sniffing — that's TLS
#   doing its job. The only legitimate way to see inside is to have the endpoint
#   *trust* your proxy: install the proxy's CA on the device you own. If a site
#   uses HSTS/pinning it still won't decrypt, and that's correct behaviour.
#   There is deliberately nothing here to bypass pinning or trick devices that
#   haven't opted in.
#
# This uses mitmproxy in transparent mode and enables IP forwarding so the
# target device can still reach the internet through this Pi.
#
#   sudo bash mitm/inspect_own_device.sh --iface eth0 --target 192.168.1.42
#
# The target must be a device you own. You will:
#   1) run this,
#   2) install the mitmproxy CA on the target (visit http://mitm.it from it),
#   3) set the target's gateway/proxy to this Pi (or use arp redirection you
#      run manually and understand — see mitm/README.md).
set -euo pipefail

if [[ $EUID -ne 0 ]]; then echo "Run as root." >&2; exit 1; fi

IFACE="" TARGET="" MODE="transparent" WEBPORT=8081

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iface)  IFACE="$2"; shift 2;;
    --target) TARGET="$2"; shift 2;;
    --mode)   MODE="$2"; shift 2;;   # transparent | regular
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
done

[[ -n "$IFACE" ]] || { echo "Need --iface (your LAN interface)." >&2; exit 1; }

command -v mitmproxy >/dev/null || {
  echo "mitmproxy not installed. Recommended:  pipx install mitmproxy" >&2
  exit 1
}

cat <<EOF

  You are about to run a TLS-intercepting proxy for:
      target device : ${TARGET:-<any device you route through here>}
      interface     : $IFACE
      mode          : $MODE

  This only decrypts traffic from a device that TRUSTS the mitmproxy CA, i.e.
  a device you control and have installed the CA on. Do this ONLY with devices
  you own or have explicit permission to inspect.

EOF
read -r -p "  Type YES to confirm the target is yours: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || { echo "Aborted."; exit 1; }

# Fixed, predictable CA location (mitmproxy otherwise scatters it under whatever
# HOME sudo happened to use). Generate the CA up front so you can install it on
# the device BEFORE the proxy starts.
CONFDIR="/etc/netlab-mitm"
mkdir -p "$CONFDIR"
if [[ ! -f "$CONFDIR/mitmproxy-ca-cert.pem" ]]; then
  echo "[*] Generating the mitmproxy CA in $CONFDIR (first run)…"
  timeout 4 mitmdump --set confdir="$CONFDIR" >/dev/null 2>&1 || true
fi
IPADDR=$(ip -4 -o addr show "$IFACE" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
cat <<EOF

[*] CA cert: $CONFDIR/mitmproxy-ca-cert.pem (.cer for Android)
    Install it on the device FIRST — in ANOTHER terminal run:
        sudo python3 -m http.server 8000 --directory $CONFDIR
    then on the device open  http://${IPADDR:-<this-Pi-IP>}:8000/  and install + TRUST it
    (Android: mitmproxy-ca-cert.cer ; iOS: .pem, then enable in Certificate Trust Settings).
EOF

# Free the proxy port (8080) if a stale mitmproxy/mitmdump is still holding it —
# otherwise mitmproxy fails with "[Errno 98] address already in use".
if ss -lnt 2>/dev/null | grep -q ':8080 '; then
  echo "[*] Port 8080 busy — stopping any stale mitmproxy/mitmdump…"
  pkill -x mitmproxy 2>/dev/null || true
  pkill -x mitmdump  2>/dev/null || true
  sleep 1
fi
if ss -lnt 2>/dev/null | grep -q ':8080 '; then
  echo "[!] Port 8080 is still in use by something else:" >&2
  ss -lntp 2>/dev/null | grep ':8080 ' >&2
  echo "    Free it, or use another port (edit the REDIRECT --to-port and add" >&2
  echo "    @<port> to mitmproxy --mode transparent@<port>)." >&2
  exit 1
fi

if [[ "$MODE" == "transparent" ]]; then
  echo "[*] Enabling IPv4 forwarding so the target keeps internet access"
  sysctl -w net.ipv4.ip_forward=1 >/dev/null

  echo "[*] Redirecting the target's HTTP/HTTPS to mitmproxy (port 8080)"
  # Only redirect the specified target if given, to avoid catching other devices.
  SRC_MATCH=""; [[ -n "$TARGET" ]] && SRC_MATCH="-s $TARGET"
  iptables -t nat -A PREROUTING -i "$IFACE" $SRC_MATCH -p tcp --dport 80  -j REDIRECT --to-port 8080
  iptables -t nat -A PREROUTING -i "$IFACE" $SRC_MATCH -p tcp --dport 443 -j REDIRECT --to-port 8080
  # Block QUIC (HTTP/3, UDP/443): browsers like Chrome use it and it would sail
  # PAST a TCP-only redirect ("traffic not going through mitmproxy"). Rejecting
  # it forces a fallback to TCP TLS, which we DO intercept.
  echo "[*] Blocking QUIC (UDP/443) so browsers fall back to interceptable TCP"
  iptables -A FORWARD -i "$IFACE" $SRC_MATCH -p udp --dport 443 -j REJECT

  cleanup() {
    echo; echo "[*] Removing iptables redirects + QUIC block"
    iptables -t nat -D PREROUTING -i "$IFACE" $SRC_MATCH -p tcp --dport 80  -j REDIRECT --to-port 8080 2>/dev/null || true
    iptables -t nat -D PREROUTING -i "$IFACE" $SRC_MATCH -p tcp --dport 443 -j REDIRECT --to-port 8080 2>/dev/null || true
    iptables -D FORWARD -i "$IFACE" $SRC_MATCH -p udp --dport 443 -j REJECT 2>/dev/null || true
  }
  trap cleanup INT TERM EXIT

  cat <<'EOF'

[*] On the TARGET device (once its traffic is routed through this Pi):
      1. Browse to  http://mitm.it  and install the CA for its OS.
      2. Trust the CA (Android: Settings > Security > install cert;
         iOS: install profile, then Settings > General > About > Certificate
         Trust Settings > enable).
    Without that trusted CA you'll see connections but NOT their decrypted
    contents — which is exactly how TLS is supposed to protect users.

[*] Starting mitmproxy in transparent mode. Press q to quit.
EOF
  mitmproxy --mode transparent --showhost --set block_global=false --set confdir="$CONFDIR"
else
  cat <<EOF

[*] Regular proxy mode. Set the target device's HTTP/HTTPS proxy to:
      $(hostname -I | awk '{print $1}'):8080
    then install the CA from http://mitm.it as above.

[*] Starting mitmproxy. Press q to quit.
EOF
  mitmproxy --set confdir="$CONFDIR"
fi
