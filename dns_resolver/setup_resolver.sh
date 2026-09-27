#!/usr/bin/env bash
#
# setup_resolver.sh — turn this Pi into the DNS resolver for YOUR OWN LAN.
#
# This is the honest, correct way to see (and later filter) what every device
# on your network looks up: instead of sniffing or decrypting anyone's traffic,
# the Pi *becomes* the DNS server every device asks by design. It configures
# dnsmasq to:
#   - listen on a LAN interface you choose (NOT the Pi's built-in wlan0),
#   - forward queries upstream and cache them,
#   - LOG every query (client IP + domain + time) to build your baseline,
#   - optionally block domains from a generated blocklist (adult/ads/etc).
#
# It changes system config, so it asks you to type YES to confirm this is your
# own network. Everything it does is reverted by cleanup.sh.
#
# ONE thing this script CANNOT do: tell your other devices to use the Pi. That
# is a setting on your ROUTER (DHCP → "DNS server" = this Pi's IP). The script
# prints the exact IP to enter. Until you set that, only the Pi itself uses it.
#
# Usage:
#   sudo bash dns_resolver/setup_resolver.sh                 # auto-pick LAN iface
#   sudo bash dns_resolver/setup_resolver.sh --iface eth0
#   sudo bash dns_resolver/setup_resolver.sh --iface wlan1 --upstream 1.1.1.1,8.8.8.8
#   sudo bash dns_resolver/setup_resolver.sh --help
#
# --iface       interface to serve DNS on (default: the one carrying your LAN).
#               Refuses wlan0 (Pi built-in) by design; pass wlan1 for the Alfa
#               once it is plugged in and joined to your SSID in MANAGED mode.
# --upstream    comma-separated upstream resolvers (default: 1.1.1.1,8.8.8.8).
# --serve-dhcp  ALSO run DHCP on the Pi, so it tells every device to use itself
#               for DNS with no router UI. You MUST disable the router's own
#               DHCP first, or the two servers collide and break the LAN.
# --gateway     router IP for DHCP mode (default: current default gateway).
# --dhcp-range  DHCP pool for DHCP mode, "start,end" (default: .100-.200).
# -y            skip the interactive YES prompt (for automation).
#
# Hardening lesson: running your own resolver lets you see and control DNS, but
# it also means the Pi is now trusted by every device — keep it patched, don't
# expose port 53 to the internet, and consider DoT/DoH upstream so your ISP
# can't read your lookups either.
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; s/^#$//' | sed '$d'
  exit 0
fi

if [[ $EUID -ne 0 ]]; then echo "Run as root: sudo bash $0 ..." >&2; exit 1; fi

IFACE="" UPSTREAM="1.1.1.1,8.8.8.8" ASSUME_YES=0
SERVE_DHCP=0 GATEWAY="" DHCP_RANGE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --iface)      IFACE="$2"; shift 2;;
    --upstream)   UPSTREAM="$2"; shift 2;;
    --serve-dhcp) SERVE_DHCP=1; shift;;
    --gateway)    GATEWAY="$2"; shift 2;;
    --dhcp-range) DHCP_RANGE="$2"; shift 2;;
    -y|--yes)     ASSUME_YES=1; shift;;
    *) echo "Unknown arg: $1  (see --help)" >&2; exit 1;;
  esac
done

# --- pick / validate the interface -----------------------------------------
if [[ -z "$IFACE" ]]; then
  IFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
fi
if [[ -z "$IFACE" ]]; then
  echo "Could not auto-detect a LAN interface. Pass --iface <name>." >&2; exit 1
fi
if [[ "$IFACE" == "wlan0" ]]; then
  echo "Refusing to serve on wlan0 (the Pi's built-in radio) by design." >&2
  echo "Use --iface eth0, or --iface wlan1 for the Alfa in managed mode." >&2
  exit 1
fi
if ! ip link show "$IFACE" >/dev/null 2>&1; then
  echo "Interface '$IFACE' not found. Available:" >&2
  ip -br link | awk '{print "  "$1}' >&2
  [[ "$IFACE" == wlan1* ]] && echo "  (wlan1 = the Alfa; plug it in and join your SSID first.)" >&2
  exit 1
fi

LAN_IP=$(ip -4 -o addr show dev "$IFACE" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
if [[ -z "$LAN_IP" ]]; then
  echo "Interface '$IFACE' has no IPv4 address — is it up and on the LAN?" >&2
  exit 1
fi

# --- ownership gate ---------------------------------------------------------
cat <<EOF

  About to make THIS Pi the DNS resolver for your LAN:
    interface : $IFACE
    Pi LAN IP : $LAN_IP
    upstream  : $UPSTREAM
    logging   : /var/log/netlab/dnsmasq.log
    blocklist : /etc/netlab/blocklist.hosts (if present)

  Only do this on a network YOU own or administer.
EOF
if [[ "$SERVE_DHCP" -eq 1 ]]; then
  cat <<EOF

  !! --serve-dhcp will make the Pi HAND OUT DHCP leases for the whole LAN.
     You MUST disable your ROUTER's DHCP server FIRST, or the two will fight
     and knock devices offline. Only continue if the router's DHCP is OFF.
EOF
fi
if [[ "$ASSUME_YES" -ne 1 ]]; then
  read -r -p "  Type YES to confirm this is your own network: " CONFIRM
  [[ "$CONFIRM" == "YES" ]] || { echo "Aborted."; exit 1; }
fi

# --- check port 53 is free --------------------------------------------------
if ss -lunH 2>/dev/null | awk '{print $5}' | grep -qE '(^|[:.])53$'; then
  HOLDER=$(ss -lunpH 2>/dev/null | grep -E '(^|[:.])53 ' | head -1)
  echo "WARNING: something already listens on UDP/53:" >&2
  echo "  $HOLDER" >&2
  echo "If that is systemd-resolved, disable its stub first, then re-run." >&2
  # Not fatal if it is dnsmasq itself from a previous run; continue.
fi

# --- back up and write config ----------------------------------------------
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/etc/netlab/backups"
mkdir -p "$BACKUP_DIR" /var/log/netlab /etc/netlab /etc/dnsmasq.d

# We run our OWN dnsmasq instance (see the unit below) pointed at just this
# file, so we don't touch /etc/dnsmasq.conf or depend on the distro service.

CONF=/etc/dnsmasq.d/netlab-resolver.conf
[[ -f "$CONF" ]] && cp -a "$CONF" "$BACKUP_DIR/netlab-resolver.conf.$STAMP"

UPSTREAM_LINES=""
IFS=',' read -ra SRV <<< "$UPSTREAM"
for s in "${SRV[@]}"; do UPSTREAM_LINES+="server=${s}"$'\n'; done

cat > "$CONF" <<EOF
# Managed by homelab-netsec dns_resolver/setup_resolver.sh — $STAMP
# Remove with dns_resolver/cleanup.sh (do not hand-edit).

# Serve DNS only on your chosen LAN interface (never wlan0).
interface=$IFACE
bind-interfaces
listen-address=127.0.0.1,$LAN_IP

# Forward everything upstream ourselves; ignore /etc/resolv.conf.
no-resolv
$UPSTREAM_LINES
# Sanity hygiene: don't forward junk / private reverse lookups upstream.
domain-needed
bogus-priv

# Cache + LOG every query — this file is your baseline dataset.
cache-size=1000
log-queries
log-facility=/var/log/netlab/dnsmasq.log

# Blocklist (generated by build_blocklist.py). Missing file is fine.
addn-hosts=/etc/netlab/blocklist.hosts
EOF

# Optional: also hand out DHCP so every device is told to use the Pi for DNS
# WITHOUT touching the router UI. You MUST disable the router's own DHCP first,
# or two DHCP servers will fight and break the LAN.
if [[ "$SERVE_DHCP" -eq 1 ]]; then
  BASE="${LAN_IP%.*}"                       # e.g. 192.168.0
  GW="${GATEWAY:-$(ip route | awk '/^default/{print $3; exit}')}"
  RANGE="${DHCP_RANGE:-${BASE}.100,${BASE}.200}"
  cat >> "$CONF" <<EOF

# --- DHCP server (opt-in via --serve-dhcp) ---
dhcp-range=${RANGE},12h
dhcp-option=option:router,${GW}
dhcp-option=option:dns-server,${LAN_IP}
dhcp-authoritative
EOF
  echo "[*] DHCP enabled: range ${RANGE}, gateway ${GW}, DNS ${LAN_IP}"
fi

# Ensure the blocklist file exists (empty = block nothing yet).
[[ -f /etc/netlab/blocklist.hosts ]] || : > /etc/netlab/blocklist.hosts

echo "[*] Wrote $CONF"
echo "[*] Validating dnsmasq config..."
dnsmasq --test --conf-file="$CONF"

# Free port 53 if a distro dnsmasq.service is running (we use our own unit).
if systemctl list-unit-files 2>/dev/null | grep -q '^dnsmasq\.service'; then
  systemctl stop dnsmasq 2>/dev/null || true
  systemctl disable dnsmasq >/dev/null 2>&1 || true
fi

# Ship our own self-contained systemd unit (works even with only dnsmasq-base).
UNIT=/etc/systemd/system/netlab-dnsmasq.service
cat > "$UNIT" <<EOF
[Unit]
Description=homelab-netsec DNS resolver (dnsmasq, netlab-managed)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$(command -v dnsmasq) -k --conf-file=$CONF
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
echo "netlab-dnsmasq" > /etc/netlab/service   # so cleanup/build_blocklist know the name

systemctl daemon-reload
systemctl enable netlab-dnsmasq >/dev/null 2>&1 || true
systemctl restart netlab-dnsmasq
sleep 1
if ! systemctl is-active --quiet netlab-dnsmasq; then
  echo "Resolver failed to start. Check: journalctl -u netlab-dnsmasq -n 30" >&2
  exit 1
fi

# --- self-test --------------------------------------------------------------
echo "[*] Testing resolution through the Pi ($LAN_IP)..."
if nslookup example.com "$LAN_IP" >/dev/null 2>&1; then
  echo "    OK — the Pi is resolving DNS."
else
  echo "    WARN — test query failed; check journalctl -u netlab-dnsmasq." >&2
fi

cat <<EOF

============================================================
 DONE — the Pi is now a DNS resolver at:  $LAN_IP  (on $IFACE)
 Service: netlab-dnsmasq   (systemctl status netlab-dnsmasq)
EOF

if [[ "$SERVE_DHCP" -eq 1 ]]; then
cat <<EOF

 DHCP MODE: the Pi is now serving DHCP and telling every device to use
 itself for DNS. No router DNS field to change — BUT make sure the
 router's own DHCP is DISABLED, then renew leases on your devices.
EOF
else
cat <<EOF

 >>> ONE manual step (scripts can't touch your router) <<<
   1. Open your router admin page (usually http://192.168.0.1).
   2. Find DHCP / LAN settings → "DNS server".
   3. Set the PRIMARY DNS to:  $LAN_IP
      (leave secondary blank, or you'll leak around the Pi).
   4. Save. Reboot devices or renew their DHCP lease.
   (Prefer no router UI? Re-run with --serve-dhcp after turning
    OFF the router's DHCP — the Pi then hands out DNS itself.)
EOF
fi

cat <<EOF

 Watch it work:
   sudo tail -f /var/log/netlab/dnsmasq.log
   python3 dns_resolver/log_to_csv.py --follow          # tidy live view
   python3 dns_resolver/log_to_csv.py --out baseline.csv # build the dataset

 Add blocking later:
   python3 dns_resolver/build_blocklist.py --help

 Undo everything (and restore router = manual step it will remind you):
   sudo bash dns_resolver/cleanup.sh
============================================================
EOF
