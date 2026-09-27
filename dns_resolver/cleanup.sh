#!/usr/bin/env bash
#
# cleanup.sh — undo setup_resolver.sh: stop the Pi being your LAN's resolver
# and restore everything it changed on the Pi.
#
# What it reverts (on the Pi):
#   - stops + disables dnsmasq,
#   - removes /etc/dnsmasq.d/netlab-resolver.conf,
#   - restores /etc/dnsmasq.conf from the most recent backup (if we edited it),
#   - leaves your logs/baseline CSVs in place (yours to keep or delete).
#
# What it CANNOT do: change your ROUTER back. It prints the exact step so your
# network resolves normally again.
#
# Usage:
#   sudo bash dns_resolver/cleanup.sh
#   sudo bash dns_resolver/cleanup.sh --purge-logs   # also delete /var/log/netlab
#   sudo bash dns_resolver/cleanup.sh --help
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; s/^#$//' | sed '$d'
  exit 0
fi

if [[ $EUID -ne 0 ]]; then echo "Run as root: sudo bash $0" >&2; exit 1; fi

PURGE_LOGS=0
[[ "${1:-}" == "--purge-logs" ]] && PURGE_LOGS=1

BACKUP_DIR="/etc/netlab/backups"
CONF=/etc/dnsmasq.d/netlab-resolver.conf
UNIT=/etc/systemd/system/netlab-dnsmasq.service

echo "[*] Stopping and disabling the netlab resolver..."
systemctl stop netlab-dnsmasq 2>/dev/null || true
systemctl disable netlab-dnsmasq >/dev/null 2>&1 || true
if [[ -f "$UNIT" ]]; then
  rm -f "$UNIT"
  systemctl daemon-reload
  echo "[*] Removed $UNIT"
fi
rm -f /etc/netlab/service

if [[ -f "$CONF" ]]; then
  rm -f "$CONF"
  echo "[*] Removed $CONF"
else
  echo "[*] $CONF not present (already clean)."
fi

# Restore /etc/dnsmasq.conf if an older version of this tool backed it up.
LATEST_MAIN=$(ls -1t "$BACKUP_DIR"/dnsmasq.conf.* 2>/dev/null | head -1 || true)
if [[ -n "$LATEST_MAIN" ]]; then
  cp -a "$LATEST_MAIN" /etc/dnsmasq.conf
  echo "[*] Restored /etc/dnsmasq.conf from $LATEST_MAIN"
fi

# We intentionally do NOT delete /etc/netlab/blocklist.hosts or backups —
# they are cheap to keep and useful if you re-enable. Logs only on --purge-logs.
if [[ "$PURGE_LOGS" -eq 1 ]]; then
  rm -rf /var/log/netlab
  echo "[*] Purged /var/log/netlab (logs + baseline)."
else
  echo "[*] Left logs/baseline in /var/log/netlab (use --purge-logs to remove)."
fi

cat <<EOF

============================================================
 Pi restored — it is no longer configured as your resolver.

 >>> ONE manual step on your ROUTER (scripts can't do this) <<<
   1. Open your router admin page (usually http://192.168.0.1).
   2. DHCP / LAN settings → "DNS server".
   3. Set it back to AUTOMATIC / blank (or your router's own IP,
      e.g. 192.168.0.1). Save.
   4. Reboot devices or renew DHCP so they stop asking the Pi.

   If you had used --serve-dhcp: re-ENABLE the router's own DHCP
   server (you disabled it), since the Pi is no longer handing out
   leases — otherwise devices won't get an IP at all.

 Until you do that, devices still pointed at the Pi will FAIL to
 resolve DNS (dnsmasq is now stopped). So do the router step now.
============================================================
EOF
