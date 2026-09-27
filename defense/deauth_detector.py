#!/usr/bin/env python3
"""
deauth_detector.py — a tiny wireless IDS: detect 802.11 deauth/disassoc floods.

Deauthentication and disassociation are unprotected management frames on
WPA2-Personal, so a flood of them is the signature of a deauth attack (used to
knock clients off, or to force the reconnect that reveals a handshake). This
tool listens in monitor mode and alerts when it sees an abnormal burst.

Run this on your monitor interface while you experiment with
wifi/capture_handshake.sh --deauth — you'll watch your own attack from the
defender's chair. On WPA3 / 802.11w (PMF) these frames are protected and you
should see far fewer, which is the upgrade lesson.

Usage (monitor mode required; your own network):
    sudo python3 defense/deauth_detector.py -i wlan1mon
    sudo python3 defense/deauth_detector.py -i wlan1mon --threshold 20 --window 10
"""
import argparse
import sys
import time
from collections import defaultdict, deque
from datetime import datetime

try:
    from scapy.all import sniff
    from scapy.layers.dot11 import Dot11, Dot11Deauth, Dot11Disas
except ImportError:
    sys.exit("scapy is required:  pip3 install scapy")

events: dict[str, deque] = defaultdict(deque)  # bssid -> timestamps of frames
alerted: dict[str, float] = {}


def log(level, msg):
    print(f"{datetime.now():%H:%M:%S}  [{level}] {msg}")


def main() -> int:
    ap = argparse.ArgumentParser(description="Detect 802.11 deauth/disassoc floods.")
    ap.add_argument("-i", "--iface", required=True, help="monitor-mode interface")
    ap.add_argument("--threshold", type=int, default=15,
                    help="frames per window from one source before alerting")
    ap.add_argument("--window", type=float, default=10.0, help="rolling window in seconds")
    args = ap.parse_args()

    def on_frame(pkt):
        if not pkt.haslayer(Dot11):
            return
        is_deauth = pkt.haslayer(Dot11Deauth)
        is_disas = pkt.haslayer(Dot11Disas)
        if not (is_deauth or is_disas):
            return

        now = time.time()
        d11 = pkt[Dot11]
        # addr3 is usually the BSSID for management frames.
        bssid = (d11.addr3 or d11.addr2 or "??:??:??:??:??:??").lower()
        kind = "deauth" if is_deauth else "disassoc"
        reason = getattr(pkt[Dot11Deauth] if is_deauth else pkt[Dot11Disas], "reason", "?")

        q = events[bssid]
        q.append(now)
        while q and now - q[0] > args.window:
            q.popleft()

        if len(q) >= args.threshold:
            # rate-limit alerts to once per window per bssid
            if now - alerted.get(bssid, 0) > args.window:
                log("ALERT", f"{kind.upper()} FLOOD from/for BSSID {bssid}: "
                             f"{len(q)} frames in {args.window:.0f}s (reason={reason}) "
                             f"— likely a deauth attack.")
                alerted[bssid] = now
        else:
            log("info", f"{kind} for {bssid} (reason={reason}) "
                        f"[{len(q)}/{args.threshold} in window]")

    log("info", f"listening on {args.iface}; threshold={args.threshold}/"
                f"{args.window:.0f}s — Ctrl-C to stop.")
    log("info", "This is passive: it only listens and never transmits.")
    try:
        sniff(iface=args.iface, prn=on_frame, store=False)
    except OSError as e:
        return f"Could not open {args.iface} — is it in monitor mode? ({e})"
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
