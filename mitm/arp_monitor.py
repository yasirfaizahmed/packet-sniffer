#!/usr/bin/env python3
"""
arp_monitor.py — detect ARP spoofing / MITM attempts on your LAN (defensive).

ARP has no authentication: any host can claim any IP by broadcasting an ARP
reply. That's the mechanism behind LAN man-in-the-middle — an attacker tells
your device "I am the router" and tells the router "I am your device", so
traffic flows through them. This tool is the *defensive* counterpart: it learns
the IP->MAC bindings it sees and shouts when one changes, which is the classic
signature of an ARP-spoofing MITM.

Running this while you experiment with the (consented, own-device) proxy in
inspect_own_device.sh is a great way to *see* the attack from the victim's side.

Usage (on a network you own):
    sudo python3 mitm/arp_monitor.py -i eth0
    sudo python3 mitm/arp_monitor.py -i wlan0 --gateway 192.168.1.1
"""
import argparse
import sys
from datetime import datetime

try:
    from scapy.all import sniff
    from scapy.layers.l2 import ARP
except ImportError:
    sys.exit("scapy is required:  pip3 install scapy")

bindings: dict[str, str] = {}   # ip -> mac we believe is correct
GATEWAY = None


def log(level: str, msg: str):
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"{ts}  [{level}] {msg}")


def on_arp(pkt):
    if ARP not in pkt:
        return
    a = pkt[ARP]
    # op 2 == is-at (a reply asserting ip->mac). These are what get spoofed.
    if a.op != 2:
        return
    ip, mac = a.psrc, a.hwsrc.lower()

    known = bindings.get(ip)
    if known is None:
        bindings[ip] = mac
        tag = "GATEWAY" if ip == GATEWAY else "host"
        log("INFO", f"learned {tag} {ip} is-at {mac}")
    elif known != mac:
        sev = "CRITICAL" if ip == GATEWAY else "ALERT"
        log(sev, f"ARP CHANGE for {ip}: was {known}, now {mac} "
                 f"— possible ARP spoofing / MITM!")
        # Keep the first-seen binding as the trusted one; report every conflict.


def main() -> int:
    ap = argparse.ArgumentParser(description="Detect ARP spoofing on your LAN.")
    ap.add_argument("-i", "--iface", help="interface to watch")
    ap.add_argument("--gateway", help="your router IP, to flag gateway spoofing loudly")
    args = ap.parse_args()

    global GATEWAY
    GATEWAY = args.gateway

    log("INFO", f"watching ARP on {args.iface or 'default iface'}"
                + (f", gateway={GATEWAY}" if GATEWAY else "")
                + " — Ctrl-C to stop.")
    log("INFO", "A change in an IP's MAC (especially the gateway's) is the "
                "signature of a MITM. This tool only watches; it changes nothing.")
    try:
        sniff(iface=args.iface, filter="arp", prn=on_arp, store=False)
    except PermissionError:
        return "Permission denied — run with sudo."
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
