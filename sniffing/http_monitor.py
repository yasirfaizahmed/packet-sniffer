#!/usr/bin/env python3
"""
http_monitor.py — log plaintext HTTP requests seen on the wire.

This exists to teach an important lesson: **plain HTTP is fully readable** to
anyone on the path — host, URL, headers, cookies, and body are all cleartext.
It logs the method, Host, and path of HTTP requests it observes.

The flip side (also the lesson): almost everything today is **HTTPS**, and you
will see very little here — just a TLS handshake with an unreadable payload.
That's the point. To inspect HTTPS on a device *you own*, you install a trusted
CA on that device and use a proxy — see the mitm/ module, which is the honest,
consented way to do it.

Usage (on a network you own):
    sudo python3 sniffing/http_monitor.py -i wlan0
"""
import argparse
import sys
from datetime import datetime

try:
    from scapy.all import sniff
    from scapy.layers.inet import IP, TCP
except ImportError:
    sys.exit("scapy is required:  pip3 install scapy")


def on_packet(pkt):
    if not (pkt.haslayer(TCP) and pkt.haslayer(IP) and pkt[TCP].payload):
        return
    raw = bytes(pkt[TCP].payload)
    # Cheap check for an HTTP request line before decoding the whole payload.
    if not raw[:8].split(b" ")[0] in (b"GET", b"POST", b"PUT", b"HEAD",
                                      b"DELETE", b"OPTIONS", b"PATCH"):
        return
    try:
        text = raw.decode("latin-1")
    except Exception:
        return
    lines = text.split("\r\n")
    request_line = lines[0]
    host = next((l.split(":", 1)[1].strip() for l in lines
                 if l.lower().startswith("host:")), "?")
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"{ts}  {pkt[IP].src:<15} -> http://{host}  {request_line}")


def main() -> int:
    ap = argparse.ArgumentParser(description="Log cleartext HTTP requests.")
    ap.add_argument("-i", "--iface", help="interface to listen on")
    args = ap.parse_args()
    print(f"[*] Watching for cleartext HTTP on {args.iface or 'default iface'} — Ctrl-C to stop.")
    print("[*] You'll see little here if your traffic is HTTPS — that's good, and the point.")
    print("[*] Only monitor networks you own or are authorized to test.\n")
    # dst port 80 catches typical HTTP; add 8080 if you run dev servers there.
    sniff(iface=args.iface, filter="tcp port 80 or tcp port 8080",
          prn=on_packet, store=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
