# recon/ — mapping your own network

Reconnaissance is inventory: knowing exactly what's on your network and what
each device exposes. On your own LAN this is pure good hygiene — you often find
a forgotten device with an open admin port.

## Tools

- `nmap_scan.sh` — guided nmap wrapper with sensible profiles (discover →
  services → full → vuln). Saves output in all three nmap formats for later.

Pair it with `../sniffing/lan_hosts.py` (fast ARP host discovery) to first learn
who's up, then `nmap_scan.sh --profile services <ip>` to see what they run.

## Typical flow

```bash
# 1. Who is on my network?
sudo python3 ../sniffing/lan_hosts.py
# 2. Fast sweep with nmap too (cross-check)
sudo bash nmap_scan.sh --target 192.168.1.0/24 --profile discover
# 3. What does that one mystery device run?
sudo bash nmap_scan.sh --target 192.168.1.37 --profile services
# 4. Go deeper on it (OS, scripts)
sudo bash nmap_scan.sh --target 192.168.1.37 --profile full
```

## Other Kali tools worth exploring (on your own network)

- **kismet** — a full wireless detector/IDS with a web UI. Great for passively
  mapping every AP and client around you and logging over time. Launch with
  `sudo kismet -c wlan1mon` then open `http://<pi>:2501`.
- **bettercap** — interactive `net.probe`/`net.recon` build a live host map;
  its web UI (`bettercap -caplet http-ui`) is a friendly way to explore.
- **arp-scan** — `sudo arp-scan --localnet` is a one-liner host discovery.

Only scan networks and hosts you own or are explicitly authorized to test.
