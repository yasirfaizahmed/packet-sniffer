#!/usr/bin/env python3
"""
log_to_csv.py — turn dnsmasq's query log into a tidy baseline dataset.

Once the Pi is your LAN's resolver (see setup_resolver.sh), dnsmasq logs every
lookup to /var/log/netlab/dnsmasq.log. Those lines are noisy (queries, forwards,
replies, cache hits). This reads them and keeps just the useful signal — WHO
(client IP) asked for WHAT (domain), WHEN, and of which TYPE — as clean CSV.

That CSV is the "baseline" for your future AI DNS filter: real examples of what
your network requests, ready to label good / ads / adult / etc.

Nobody's traffic is intercepted here: these are DNS questions devices sent to
the Pi *on purpose*, because it is their configured resolver.

Usage:
    python3 dns_resolver/log_to_csv.py                      # summary of the log
    python3 dns_resolver/log_to_csv.py --follow             # live, like tail -f
    python3 dns_resolver/log_to_csv.py --out baseline.csv   # write the dataset
    python3 dns_resolver/log_to_csv.py --out baseline.csv --follow
    python3 dns_resolver/log_to_csv.py --log /path/to/dnsmasq.log --top 30
"""
import argparse
import csv
import re
import sys
import time
from collections import Counter
from datetime import datetime

DEFAULT_LOG = "/var/log/netlab/dnsmasq.log"

# e.g. "Sep 27 20:00:00 dnsmasq[1234]: query[A] example.com from 192.168.0.50"
QUERY_RE = re.compile(
    r"^(?P<ts>\w{3}\s+\d+\s+[\d:]+).*?query\[(?P<qtype>[A-Z0-9]+)\]\s+"
    r"(?P<domain>\S+)\s+from\s+(?P<client>\S+)"
)


def parse_line(line: str):
    m = QUERY_RE.search(line)
    if not m:
        return None
    return m.group("ts"), m.group("client"), m.group("qtype"), m.group("domain")


def main() -> int:
    ap = argparse.ArgumentParser(description="dnsmasq query log -> tidy CSV baseline.")
    ap.add_argument("--log", default=DEFAULT_LOG, help=f"dnsmasq log (default {DEFAULT_LOG})")
    ap.add_argument("--out", help="append parsed queries to this CSV")
    ap.add_argument("--follow", action="store_true", help="keep reading new lines (tail -f)")
    ap.add_argument("--top", type=int, default=20, help="rows in the summary")
    args = ap.parse_args()

    writer = fh = None
    if args.out:
        try:
            fh = open(args.out, "a", newline="")
        except PermissionError:
            sys.exit(f"Cannot write {args.out} — try another path or use sudo.")
        writer = csv.writer(fh)
        if fh.tell() == 0:
            writer.writerow(["timestamp", "client", "qtype", "domain"])

    domains: Counter = Counter()
    clients: Counter = Counter()

    def handle(rec):
        ts, client, qtype, domain = rec
        domains[domain] += 1
        clients[client] += 1
        if writer:
            writer.writerow([datetime.now().isoformat(), client, qtype, domain])
            fh.flush()
        if args.follow:
            print(f"{client:<39} {qtype:<5} {domain}")

    try:
        src = open(args.log, "r", errors="replace")
    except FileNotFoundError:
        sys.exit(f"No log at {args.log}. Is the resolver running? (setup_resolver.sh)")
    except PermissionError:
        sys.exit(f"Cannot read {args.log} — try: sudo python3 {sys.argv[0]} ...")

    try:
        with src:
            for line in src:
                rec = parse_line(line)
                if rec:
                    handle(rec)
            if args.follow:
                print(f"[*] Following {args.log} — Ctrl-C to stop.\n")
                while True:
                    where = src.tell()
                    line = src.readline()
                    if not line:
                        time.sleep(0.5)
                        src.seek(where)
                        continue
                    rec = parse_line(line)
                    if rec:
                        handle(rec)
    except KeyboardInterrupt:
        pass
    finally:
        if fh:
            fh.close()

    if not args.follow:
        print(f"Parsed {sum(domains.values())} queries from {args.log}\n")
        print(f"Top {args.top} domains:")
        for d, n in domains.most_common(args.top):
            print(f"  {n:>6}  {d}")
        print(f"\nBusiest clients:")
        for c, n in clients.most_common(args.top):
            print(f"  {n:>6}  {c}")
        if args.out:
            print(f"\nAppended to {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
