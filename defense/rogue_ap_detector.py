#!/usr/bin/env python3
"""
rogue_ap_detector.py — spot "evil twin" / rogue access points near you.

An evil twin is a rogue AP broadcasting the SAME network name (ESSID) as a
legitimate one, to lure devices into connecting to the attacker instead. The
detectable signature: your ESSID advertised from a BSSID (AP MAC) that isn't
yours, or from an unexpected channel, or suddenly on a weaker security setting.

You give it your real network name and your AP's real BSSID(s); it watches
beacons and probe responses and alerts on any *other* AP claiming your name.
This is the defensive answer to evil-twin attacks — this kit deliberately does
NOT build an evil twin (that's for phishing victims); it builds the detector.

Usage (monitor mode; your own environment):
    sudo python3 defense/rogue_ap_detector.py -i wlan1mon \
        --essid "MyHomeWiFi" --known AA:BB:CC:DD:EE:FF
    # multiple legit APs (e.g. mesh): repeat --known
"""
import argparse
import sys
from datetime import datetime

try:
    from scapy.all import sniff
    from scapy.layers.dot11 import Dot11, Dot11Beacon, Dot11ProbeResp, Dot11Elt
except ImportError:
    sys.exit("scapy is required:  pip3 install scapy")

seen: dict[str, dict] = {}   # bssid -> info


def log(level, msg):
    print(f"{datetime.now():%H:%M:%S}  [{level}] {msg}")


def channel_of(pkt):
    """Read the channel from the DS Parameter Set element (ID 3)."""
    el = pkt.getlayer(Dot11Elt)
    while el:
        if el.ID == 3 and el.info:      # DS Parameter Set = current channel
            return el.info[0]
        el = el.payload.getlayer(Dot11Elt)
    return "?"


def parse_security(pkt) -> str:
    """Best-effort crypto summary from the beacon information elements."""
    caps = pkt.sprintf("{Dot11Beacon:%Dot11Beacon.cap%}"
                       "{Dot11ProbeResp:%Dot11ProbeResp.cap%}")
    has_rsn = has_wpa = False
    el = pkt.getlayer(Dot11Elt)
    while el:
        if el.ID == 48:
            has_rsn = True              # RSN => WPA2/WPA3
        elif el.ID == 221 and el.info.startswith(b"\x00P\xf2\x01"):
            has_wpa = True              # vendor-specific WPA1
        el = el.payload.getlayer(Dot11Elt)
    if has_rsn:
        return "WPA2/3"
    if has_wpa:
        return "WPA1"
    return "OPEN/WEP" if "privacy" not in caps else "WEP"


def main() -> int:
    ap = argparse.ArgumentParser(description="Detect rogue / evil-twin APs for your ESSID.")
    ap.add_argument("-i", "--iface", required=True, help="monitor-mode interface")
    ap.add_argument("--essid", required=True, help="the network name to protect")
    ap.add_argument("--known", action="append", default=[],
                    help="a legitimate BSSID for that ESSID (repeat for several)")
    args = ap.parse_args()

    known = {b.lower() for b in args.known}
    log("info", f"protecting ESSID {args.essid!r}; known-good BSSIDs: "
                f"{sorted(known) or '(none given — every match will be flagged)'}")
    log("info", "passive listen only. Ctrl-C to stop.\n")

    def on_beacon(pkt):
        if not (pkt.haslayer(Dot11Beacon) or pkt.haslayer(Dot11ProbeResp)):
            return
        try:
            essid = pkt[Dot11Elt].info.decode(errors="replace")
        except Exception:
            return
        if essid != args.essid:
            return

        bssid = (pkt[Dot11].addr2 or "??").lower()
        channel = channel_of(pkt)
        sec = parse_security(pkt)

        if bssid not in seen:
            seen[bssid] = {"channel": channel, "sec": sec}
            if known and bssid not in known:
                log("ALERT", f"ROGUE AP for {essid!r}: BSSID {bssid} "
                             f"(ch {channel}, {sec}) is NOT in your known list "
                             f"— possible evil twin!")
            elif not known:
                log("WARN", f"{essid!r} seen at BSSID {bssid} (ch {channel}, {sec}) "
                            f"— pass --known to distinguish yours from rogues.")
            else:
                log("ok", f"legit AP {bssid} for {essid!r} (ch {channel}, {sec})")

    try:
        sniff(iface=args.iface, prn=on_beacon, store=False)
    except OSError as e:
        return f"Could not open {args.iface} — is it in monitor mode? ({e})"
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
