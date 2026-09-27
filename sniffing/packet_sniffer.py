#!/usr/bin/env python3
"""
packet_sniffer.py — a small, readable live packet sniffer built on scapy.

The point of this script is to *see the layers*: for every packet it prints the
Ethernet/IP/transport headers and a short summary, so you can watch TCP
handshakes, ARP chatter, DNS lookups, etc. as they happen on your own LAN.

Usage (run as root, on a network you own):
    sudo python3 sniffing/packet_sniffer.py -i wlan0
    sudo python3 sniffing/packet_sniffer.py -i eth0 -f "tcp port 443" -c 100
    sudo python3 sniffing/packet_sniffer.py -i wlan0 -w captures/session.pcap

Options:
    -i/--iface   interface to listen on (default: scapy's default route iface)
    -f/--filter  BPF capture filter, e.g. "tcp", "udp port 53", "host 192.168.1.1"
    -c/--count   stop after N packets (0 = run until Ctrl-C)
    -w/--write   also save raw packets to a .pcap for later Wireshark analysis

This is passive: it only reads frames the interface already receives. On a
switched LAN you'll mostly see your own traffic + broadcasts unless the
interface is in monitor/promiscuous mode.
"""
import argparse
import sys
from datetime import datetime

try:
    from scapy.all import sniff, wrpcap
    from scapy.layers.l2 import Ether, ARP
    from scapy.layers.inet import IP, TCP, UDP, ICMP
    from scapy.layers.inet6 import IPv6
    from scapy.layers.dns import DNS
except ImportError:
    sys.exit("scapy is required:  pip3 install scapy  (or run setup/install_deps.sh)")

# TCP flag bits -> letters, so a handshake reads S / SA / A, a teardown F/FA…
_TCP_FLAGS = [
    (0x02, "S"), (0x10, "A"), (0x01, "F"),
    (0x04, "R"), (0x08, "P"), (0x20, "U"),
]


def tcp_flags(flags: int) -> str:
    return "".join(letter for bit, letter in _TCP_FLAGS if flags & bit) or "-"


def describe(pkt) -> str:
    """Return a one-line, human-readable summary of a packet's key layers."""
    ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]

    # Link layer
    if ARP in pkt:
        a = pkt[ARP]
        op = {1: "who-has", 2: "is-at"}.get(a.op, f"op{a.op}")
        return f"{ts}  ARP   {a.psrc:<15} {op} {a.pdst:<15} ({a.hwsrc})"

    # Network layer
    src = dst = proto = "?"
    if IP in pkt:
        src, dst, proto = pkt[IP].src, pkt[IP].dst, "IP"
    elif IPv6 in pkt:
        src, dst, proto = pkt[IPv6].src, pkt[IPv6].dst, "IP6"
    elif Ether in pkt:
        return f"{ts}  L2    {pkt[Ether].src} -> {pkt[Ether].dst}  type=0x{pkt[Ether].type:04x}"

    # Transport / application layer
    if TCP in pkt:
        t = pkt[TCP]
        extra = ""
        if DNS in pkt:
            extra = "  " + _dns_summary(pkt[DNS])
        return (f"{ts}  {proto}/TCP {src}:{t.sport} -> {dst}:{t.dport} "
                f"[{tcp_flags(int(t.flags))}] seq={t.seq}{extra}")
    if UDP in pkt:
        u = pkt[UDP]
        extra = "  " + _dns_summary(pkt[DNS]) if DNS in pkt else ""
        return f"{ts}  {proto}/UDP {src}:{u.sport} -> {dst}:{u.dport}{extra}"
    if ICMP in pkt:
        return f"{ts}  {proto}/ICMP {src} -> {dst}  type={pkt[ICMP].type}"

    return f"{ts}  {proto}   {src} -> {dst}"


def _dns_summary(dns: DNS) -> str:
    if dns.qr == 0 and dns.qd is not None:  # query
        try:
            return f"DNS? {dns.qd.qname.decode(errors='replace').rstrip('.')}"
        except Exception:
            return "DNS?"
    if dns.qr == 1:
        return f"DNS* {dns.ancount} answer(s)"
    return "DNS"


def main() -> int:
    ap = argparse.ArgumentParser(description="Readable live packet sniffer (scapy).")
    ap.add_argument("-i", "--iface", help="interface to sniff on")
    ap.add_argument("-f", "--filter", default=None, help="BPF filter (e.g. 'tcp port 443')")
    ap.add_argument("-c", "--count", type=int, default=0, help="stop after N packets (0=forever)")
    ap.add_argument("-w", "--write", help="also save raw packets to this .pcap file")
    args = ap.parse_args()

    saved = []

    def handle(pkt):
        print(describe(pkt))
        if args.write:
            saved.append(pkt)

    print(f"[*] Sniffing on {args.iface or 'default iface'} "
          f"filter={args.filter!r} count={args.count or '∞'} — Ctrl-C to stop.")
    print("[*] Reminder: only capture on networks you own or are authorized to test.\n")
    try:
        sniff(iface=args.iface, filter=args.filter, prn=handle,
              count=args.count, store=False)
    except PermissionError:
        return "Permission denied — run with sudo."
    except KeyboardInterrupt:
        pass
    finally:
        if args.write and saved:
            wrpcap(args.write, saved)
            print(f"\n[*] Wrote {len(saved)} packets to {args.write}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
