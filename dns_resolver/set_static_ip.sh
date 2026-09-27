#!/usr/bin/env bash
#
# set_static_ip.sh — pin this Pi to a fixed IP so it can be your LAN's
# resolver / DHCP server reliably.
#
# Why: `networkctl status` shows eth0 gets its address by DHCP from the router.
# If you then turn the router's DHCP off (Option B, so the Pi hands out DNS),
# the Pi would lose its own lease. So make the address STATIC first — by
# default the SAME IP it has now, so nothing else needs to change.
#
# This box uses netplan + systemd-networkd (and cloud-init). The script writes
# a high-priority netplan override and tells cloud-init to stop rewriting the
# network on reboot. Everything is backed up and reversible with --revert.
#
# Usage:
#   sudo bash dns_resolver/set_static_ip.sh                 # keep current IP, static
#   sudo bash dns_resolver/set_static_ip.sh --address 192.168.0.106/24 \
#        --gateway 192.168.0.1 --dns 1.1.1.1,8.8.8.8
#   sudo bash dns_resolver/set_static_ip.sh --revert        # back to DHCP
#   sudo bash dns_resolver/set_static_ip.sh --help
#
# --iface    interface (default: eth0). Refuses wlan0 (Pi built-in).
# --address  CIDR to pin (default: the interface's current address).
# --gateway  default gateway (default: current default route).
# --dns      upstream DNS for the Pi ITSELF, comma-separated
#            (default 1.1.1.1,8.8.8.8 — LAN clients use the Pi, the Pi uses these).
# -y         skip the YES prompt.
#
# NOTE: applying network changes briefly drops connectivity. If you keep the
# SAME IP (the default) the blip is minimal.
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; s/^#$//' | sed '$d'
  exit 0
fi
if [[ $EUID -ne 0 ]]; then echo "Run as root: sudo bash $0 ..." >&2; exit 1; fi

IFACE="eth0" ADDRESS="" GATEWAY="" DNS="1.1.1.1,8.8.8.8" ASSUME_YES=0 REVERT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --iface)   IFACE="$2"; shift 2;;
    --address) ADDRESS="$2"; shift 2;;
    --gateway) GATEWAY="$2"; shift 2;;
    --dns)     DNS="$2"; shift 2;;
    --revert)  REVERT=1; shift;;
    -y|--yes)  ASSUME_YES=1; shift;;
    *) echo "Unknown arg: $1  (see --help)" >&2; exit 1;;
  esac
done

NETPLAN=/etc/netplan/99-netlab-static.yaml
CLOUDINIT=/etc/cloud/cloud.cfg.d/99-netlab-disable-network.cfg

if ! command -v netplan >/dev/null 2>&1; then
  echo "netplan not found — this helper is for the netplan/networkd setup." >&2
  exit 1
fi

# --- revert -----------------------------------------------------------------
if [[ "$REVERT" -eq 1 ]]; then
  [[ -f "$NETPLAN" ]] && rm -f "$NETPLAN" && echo "[*] Removed $NETPLAN"
  [[ -f "$CLOUDINIT" ]] && rm -f "$CLOUDINIT" && echo "[*] Removed $CLOUDINIT (cloud-init manages network again)"
  echo "[*] Applying netplan (back to DHCP)..."
  netplan apply
  echo "[*] Done. If the router's DHCP is OFF, turn it back ON or the Pi gets no address."
  exit 0
fi

if [[ "$IFACE" == "wlan0" ]]; then
  echo "Refusing wlan0 (Pi built-in). Use eth0 or the Alfa (wlan1)." >&2; exit 1
fi

# --- fill defaults from the live interface ----------------------------------
[[ -z "$ADDRESS" ]] && ADDRESS=$(ip -4 -o addr show dev "$IFACE" 2>/dev/null | awk '{print $4; exit}')
[[ -z "$GATEWAY" ]] && GATEWAY=$(ip route | awk '/^default/{print $3; exit}')
if [[ -z "$ADDRESS" || -z "$GATEWAY" ]]; then
  echo "Could not auto-detect address/gateway for $IFACE. Pass --address and --gateway." >&2
  exit 1
fi
[[ "$ADDRESS" == */* ]] || ADDRESS="$ADDRESS/24"   # assume /24 if no prefix given

DNS_YAML=$(echo "$DNS" | sed 's/,/, /g')

cat <<EOF

  About to pin $IFACE to a STATIC address:
    address  : $ADDRESS
    gateway  : $GATEWAY
    Pi's DNS : $DNS   (LAN clients will use the Pi; the Pi uses these upstream)
    writes   : $NETPLAN  and  $CLOUDINIT
  Applying will briefly drop connectivity (minimal if the IP is unchanged).
EOF
if [[ "$ASSUME_YES" -ne 1 ]]; then
  read -r -p "  Type YES to proceed: " CONFIRM
  [[ "$CONFIRM" == "YES" ]] || { echo "Aborted."; exit 1; }
fi

# --- back up existing netplan, then write override --------------------------
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/etc/netlab/backups"; mkdir -p "$BACKUP_DIR" /etc/cloud/cloud.cfg.d
cp -a /etc/netplan "$BACKUP_DIR/netplan.$STAMP" 2>/dev/null || true

cat > "$NETPLAN" <<EOF
# Managed by homelab-netsec dns_resolver/set_static_ip.sh — $STAMP
# Revert with: sudo bash dns_resolver/set_static_ip.sh --revert
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      dhcp4: false
      dhcp6: false
      addresses:
        - $ADDRESS
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses: [$DNS_YAML]
EOF
chmod 600 "$NETPLAN"
echo "[*] Wrote $NETPLAN"

# Stop cloud-init re-generating the network (which would undo the static IP).
cat > "$CLOUDINIT" <<EOF
# homelab-netsec: keep cloud-init from overwriting our static netplan.
network: {config: disabled}
EOF
echo "[*] Wrote $CLOUDINIT"

echo "[*] Validating netplan..."
netplan generate
echo "[*] Applying (connectivity may blip)..."
netplan apply
sleep 2

echo "[*] Result:"
ip -4 -o addr show dev "$IFACE" | awk '{print "    address:",$4}'
ip route | awk '/^default/{print "    gateway:",$3; exit}'

cat <<EOF

============================================================
 $IFACE is now STATIC at ${ADDRESS%/*}.
 Next:
   1. Start the Pi as resolver + DHCP (pool excludes this IP):
        sudo bash dns_resolver/setup_resolver.sh --serve-dhcp \\
             --gateway $GATEWAY --dhcp-range 192.168.0.110,192.168.0.199
   2. THEN disable the router's DHCP (uncheck DHCP: Enable) and Save.
   3. Renew leases on devices (reboot / Wi-Fi off-on).
 Revert:  sudo bash dns_resolver/set_static_ip.sh --revert
============================================================
EOF
