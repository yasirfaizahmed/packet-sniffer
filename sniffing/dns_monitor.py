#!/usr/bin/env python3
"""
dns_monitor.py — watch which domains devices on YOUR LAN are looking up.

DNS is the cleanest, least invasive way to answer "what sites is my network
talking to?" — almost every connection starts with a DNS lookup, and DNS
queries are plaintext (unless a device uses DoH/DoT). This passively logs each
DNS *question* it sees, with the client IP that asked, and keeps a running
tally.

This does NOT intercept, block, or modify anything. It only reads DNS packets
the interface already receives. To see queries from *other* devices on a
switched network you generally need either:
  - to run this on the router / DNS server itself, or
  - a mirrored/monitor port, or
  - your interface in monitor mode (WiFi) capturing the air.
On your own gear, the honest and simplest option is to point your devices'
DNS at the Pi (or run it on the router).

Usage (on a network you own):
    sudo python3 sniffing/dns_monitor.py -i wlan0
    sudo python3 sniffing/dns_monitor.py -i eth0 --top 20
    sudo python3 sniffing/dns_monitor.py -i wlan0 --csv captures/dns.csv
"""
import argparse
import csv
import signal
import sys
from collections import Counter
from datetime import datetime

try:
    from scapy.all import sniff
    from scapy.layers.inet import IP
    from scapy.layers.inet6 import IPv6
    from scapy.layers.dns import DNS, DNSQR
except ImportError:
    sys.exit("scapy is required:  pip3 install scapy")

QTYPES = {1: "A", 28: "AAAA", 5: "CNAME", 15: "MX", 16: "TXT", 33: "SRV", 65: "HTTPS"}

domain_counter: Counter = Counter()
client_counter: Counter = Counter()
csv_writer = None
csv_fh = None


def on_packet(pkt):
    if not pkt.haslayer(DNS) or pkt[DNS].qr != 0 or pkt[DNS].qd is None:
        return  # only outgoing queries (qr==0)

    client = pkt[IP].src if pkt.haslayer(IP) else (pkt[IPv6].src if pkt.haslayer(IPv6) else "?")
    # A query can technically hold multiple questions; iterate defensively.
    qd = pkt[DNS].qd
    for i in range(pkt[DNS].qdcount or 1):
        try:
            q = qd[i] if pkt[DNS].qdcount and pkt[DNS].qdcount > 1 else qd
        except (IndexError, TypeError):
            q = qd
        if not isinstance(q, DNSQR):
            break
        name = q.qname.decode(errors="replace").rstrip(".")
        qtype = QTYPES.get(q.qtype, str(q.qtype))
        ts = datetime.now().strftime("%H:%M:%S")
        print(f"{ts}  {client:<39} {qtype:<5} {name}")

        domain_counter[name] += 1
        client_counter[client] += 1
        if csv_writer:
            csv_writer.writerow([datetime.now().isoformat(), client, qtype, name])
            csv_fh.flush()
        break  # scapy usually exposes just the first question conveniently


def print_summary(top: int):
    print("\n" + "=" * 60)
    print(f"Top {top} domains queried:")
    for name, n in domain_counter.most_common(top):
        print(f"  {n:>5}  {name}")
    print(f"\nMost active clients:")
    for ip, n in client_counter.most_common(top):
        print(f"  {n:>5}  {ip}")
    print("=" * 60)


def main() -> int:
    ap = argparse.ArgumentParser(description="Passively log DNS queries on your LAN.")
    ap.add_argument("-i", "--iface", help="interface to listen on")
    ap.add_argument("--top", type=int, default=15, help="how many rows in the summary")
    ap.add_argument("--csv", help="append each query to this CSV file")
    args = ap.parse_args()

    global csv_writer, csv_fh
    if args.csv:
        csv_fh = open(args.csv, "a", newline="")
        csv_writer = csv.writer(csv_fh)
        if csv_fh.tell() == 0:
            csv_writer.writerow(["timestamp", "client", "qtype", "domain"])

    def _summary_and_exit(*_):
        print_summary(args.top)
        if csv_fh:
            csv_fh.close()
        sys.exit(0)

    signal.signal(signal.SIGINT, _summary_and_exit)

    print(f"[*] Logging DNS queries on {args.iface or 'default iface'} — Ctrl-C for summary.")
    print("[*] Only monitor networks you own or are authorized to test.\n")
    print(f"{'TIME':<8}  {'CLIENT':<39} {'TYPE':<5} DOMAIN")
    sniff(iface=args.iface, filter="udp port 53", prn=on_packet, store=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
