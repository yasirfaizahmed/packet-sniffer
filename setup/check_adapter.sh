#!/usr/bin/env bash
#
# check_adapter.sh — sanity-check that a wireless interface can enter monitor
# mode (the prerequisite for capturing WiFi frames / handshakes).
#
#   sudo bash setup/check_adapter.sh [interface]
#
# With no argument it tries to auto-pick the non-builtin adapter (your Alfa).
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root:  sudo bash $0 [interface]" >&2
  exit 1
fi

echo "==> Wireless interfaces seen by the kernel:"
iw dev | sed 's/^/    /'
echo

IFACE="${1:-}"
if [[ -z "$IFACE" ]]; then
  # Prefer wlan1+ (USB adapters) over wlan0 (Pi built-in).
  IFACE=$(iw dev | awk '/Interface/{print $2}' | grep -v '^wlan0$' | head -n1 || true)
  IFACE="${IFACE:-$(iw dev | awk '/Interface/{print $2}' | head -n1)}"
fi

if [[ -z "$IFACE" ]]; then
  echo "No wireless interface found. Is the adapter plugged in and the driver loaded?" >&2
  echo "Run: lsusb  and  sudo bash setup/setup_adapter.sh" >&2
  exit 1
fi

echo "==> Testing interface: $IFACE"
PHY=$(iw dev "$IFACE" info | awk '/wiphy/{print "phy"$2}')
echo "    belongs to $PHY"
echo
echo "==> Supported interface modes (need 'monitor'):"
iw phy "$PHY" info | sed -n '/Supported interface modes/,/[A-Za-z]* commands/p' | grep -E '\*' | sed 's/^/    /'
echo

if iw phy "$PHY" info | grep -qi '\* monitor'; then
  echo "[OK] $PHY advertises monitor mode."
else
  echo "[WARN] monitor mode not advertised — driver may not be the aircrack-ng one." >&2
fi

echo
echo "==> Live toggle test (brings the interface down, into monitor, and back):"
ip link set "$IFACE" down
if iw dev "$IFACE" set type monitor 2>/dev/null; then
  ip link set "$IFACE" up
  MODE=$(iw dev "$IFACE" info | awk '/type/{print $2}')
  echo "    $IFACE is now type: $MODE"
  # restore
  ip link set "$IFACE" down
  iw dev "$IFACE" set type managed
  ip link set "$IFACE" up
  echo "[OK] monitor mode works. Restored $IFACE to managed."
else
  ip link set "$IFACE" up || true
  echo "[FAIL] could not switch $IFACE to monitor mode." >&2
  echo "       Re-run setup/setup_adapter.sh and reboot." >&2
  exit 1
fi
