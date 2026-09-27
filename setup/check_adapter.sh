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

# Does this interface sit on the USB bus (i.e. an external adapter like the
# Alfa) rather than the Pi's built-in SDIO radio?
is_usb_iface() {
  local dev="/sys/class/net/$1/device"
  [[ -e "$dev" ]] && readlink -f "$dev" 2>/dev/null | grep -q '/usb'
}

echo "==> Wireless interfaces seen by the kernel:"
for w in $(iw dev | awk '/Interface/{print $2}'); do
  if is_usb_iface "$w"; then tag="USB adapter"; else tag="built-in"; fi
  echo "    $w  ($tag)"
done
echo

IFACE="${1:-}"
if [[ -n "$IFACE" ]]; then
  if ! iw dev "$IFACE" info >/dev/null 2>&1; then
    echo "Interface '$IFACE' not found — see the list above." >&2
    echo "If it is your Alfa, check: lsusb ; dmesg | tail -30" >&2
    exit 1
  fi
else
  # Auto-pick: prefer a USB adapter (your Alfa) over the built-in radio.
  for w in $(iw dev | awk '/Interface/{print $2}'); do
    if is_usb_iface "$w"; then IFACE="$w"; break; fi
  done
  if [[ -z "$IFACE" ]]; then
    echo "[WARN] No USB Wi-Fi adapter detected on the bus." >&2
    echo "       If you expected your Alfa, it is NOT enumerated — check:" >&2
    echo "         lsusb    (look for a Realtek 0bda:88xx)" >&2
    echo "         dmesg | tail -30   (watch for 'error -71' / disconnects = power/cable)" >&2
    BUILTIN=$(iw dev | awk '/Interface/{print $2}' | head -n1 || true)
    if [[ -z "$BUILTIN" ]]; then
      echo "No wireless interface found at all." >&2
      exit 1
    fi
    echo "       Falling back to the BUILT-IN radio '$BUILTIN' — any [OK] below is" >&2
    echo "       about the built-in, NOT your Alfa." >&2
    IFACE="$BUILTIN"
  fi
fi

if is_usb_iface "$IFACE"; then WHICH="USB adapter"; else WHICH="built-in radio"; fi
echo "==> Testing interface: $IFACE  ($WHICH)"
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
