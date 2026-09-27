# `dns_resolver/` — make the Pi your LAN's DNS resolver (and filter)

This module is the honest, robust foundation for an **AI-powered filtering DNS
server** ("block adult/ads, allow the rest"). It does **not** sniff or decrypt
anyone's traffic. Instead the Pi *becomes the DNS server* every device asks —
by design, in the clear — which is exactly how Pi-hole, NextDNS and every
parental-control DNS works.

## Why this, and not "sniff everyone"

On a normal switched/WPA2 LAN you **cannot** passively capture other devices'
web traffic just by knowing the WiFi password — the switch doesn't forward it
to you, and WPA2 encrypts the air per-session. Trying to would mean actively
intercepting each device, which this kit refuses to build. The DNS-resolver
approach gets you **every device's every lookup, cleanly and by consent**, and
gives you the natural place to allow/block. It's less code and it *is* the
product you want to build.

```
Router DHCP: "DNS server = <Pi IP>"
      │
  every device ──DNS query──▶  Pi (dnsmasq)
      │                           │  log  → baseline dataset (log_to_csv.py)
      │                           │  classify → block/allow (build_blocklist.py)
      └──────── answer / 0.0.0.0 ◀┘
```

## The one thing scripts can't do

A script on the Pi cannot tell your other devices to use it — that's a setting
on your **router** (DHCP → *DNS server* = the Pi's IP). Both scripts print the
exact value and remind you. Everything on the Pi is automated and reversible.

## Quick start

```bash
# 1. Make the Pi the resolver (serves on your wired LAN by default; NEVER wlan0).
sudo bash dns_resolver/setup_resolver.sh
#    Serve over the Alfa instead (once plugged in + joined to your SSID, managed mode):
#    sudo bash dns_resolver/setup_resolver.sh --iface wlan1

# 2. Do the ONE router step it prints: set the LAN's DNS server to the Pi's IP.

# 3. Build the baseline dataset from real queries:
python3 dns_resolver/log_to_csv.py --follow              # watch live
python3 dns_resolver/log_to_csv.py --out baseline.csv    # save the dataset

# 4. Turn on blocking (drop domain lists in dns_resolver/lists/ first):
sudo python3 dns_resolver/build_blocklist.py \
    --block dns_resolver/lists/adult.txt --allow dns_resolver/lists/allow.txt --reload

# 5. Undo everything on the Pi (it reminds you to revert the router):
sudo bash dns_resolver/cleanup.sh
```

## Files

| File | Does |
|---|---|
| `setup_resolver.sh` | Installs/points dnsmasq at a LAN interface you choose, logs every query, loads the blocklist. Refuses `wlan0` (Pi built-in); asks you to type `YES`. |
| `log_to_csv.py` | Parses dnsmasq's log into tidy `client,qtype,domain` CSV — your baseline. `--follow` for live view. |
| `build_blocklist.py` | Compiles domain lists into `/etc/netlab/blocklist.hosts`. Has a `classify()` **AI hook** — return `True` to block. |
| `cleanup.sh` | Stops/disables dnsmasq, removes the config, restores backups. Tells you the router field to revert. |
| `lists/` | Your block/allow lists (git-ignored — may be large or sensitive). |

## Where your AI plugs in

`build_blocklist.py` has a `classify(domain) -> bool` function that currently
returns `False` (block nothing beyond the list files). Point it at your model
and it becomes the model's deploy step; use the CSV baseline from `log_to_csv.py`
as training/eval data. Categorisation should end in a policy you *own* — this is
your household network, and a filtering resolver is a visible, honest service on
it, not covert surveillance of guests.

## Hardening lesson

Running your own resolver means every device now trusts the Pi for DNS. Keep it
patched, **never expose UDP/53 to the internet**, and consider a DNS-over-TLS
upstream (e.g. `--upstream 1.1.1.1` with dnsmasq DoT, or unbound) so your ISP
can't read your lookups either. A resolver you don't secure is a single point
your whole LAN depends on.
