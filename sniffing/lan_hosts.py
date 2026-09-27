#!/usr/bin/env python3
"""
lan_hosts.py — discover which devices are alive on your local network.

Sends ARP "who-has" requests across your subnet and lists everything that
replies (IP, MAC, and a best-effort vendor guess from the MAC prefix). This is
the standard first step of understanding a LAN: who is actually on it.

ARP only works within your own broadcast domain (your subnet), which is exactly
the scope you should be operating in — your own network.

Usage (on a network you own):
    sudo python3 sniffing/lan_hosts.py                 # auto-detect subnet
    sudo python3 sniffing/lan_hosts.py -r 192.168.1.0/24
    sudo python3 sniffing/lan_hosts.py -i eth0 -t 3
"""
import argparse
import ipaddress
import socket
import sys

try:
    from scapy.all import srp, conf
    from scapy.layers.l2 import Ether, ARP
except ImportError:
    sys.exit("scapy is required:  pip3 install scapy")


def default_cidr() -> str:
    """Guess the local /24 from the primary interface's IP."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))  # no packets sent; just picks the route
        ip = s.getsockname()[0]
    finally:
        s.close()
    net = ipaddress.ip_network(f"{ip}/24", strict=False)
    return str(net)


def scan(cidr: str, iface: str | None, timeout: int):
    print(f"[*] ARP-scanning {cidr}" + (f" on {iface}" if iface else "") + " …\n")
    ans, _ = srp(
        Ether(dst="ff:ff:ff:ff:ff:ff") / ARP(pdst=cidr),
        timeout=timeout, iface=iface, verbose=False,
    )
    hosts = []
    for _, r in ans:
        hosts.append((r.psrc, r.hwsrc))
    hosts.sort(key=lambda h: tuple(int(o) for o in h[0].split(".")))
    return hosts


def main() -> int:
    ap = argparse.ArgumentParser(description="ARP host discovery on your LAN.")
    ap.add_argument("-r", "--range", help="CIDR to scan (default: auto-detected /24)")
    ap.add_argument("-i", "--iface", help="interface to use")
    ap.add_argument("-t", "--timeout", type=int, default=3, help="seconds to wait for replies")
    args = ap.parse_args()

    if args.iface:
        conf.iface = args.iface
    cidr = args.range or default_cidr()

    try:
        hosts = scan(cidr, args.iface, args.timeout)
    except PermissionError:
        return "Permission denied — run with sudo."

    print(f"{'IP ADDRESS':<16} {'MAC ADDRESS':<18} VENDOR-OUI")
    print("-" * 50)
    for ip, mac in hosts:
        print(f"{ip:<16} {mac:<18} {mac[:8].upper()}")
    print(f"\n[*] {len(hosts)} host(s) responded on {cidr}.")
    print("[*] Tip: cross-reference the OUI (first 3 MAC bytes) at "
          "https://standards-oui.ieee.org/ to identify device makers.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
