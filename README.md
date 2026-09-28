# homelab-netsec — a personal network-security learning lab

A hands-on toolkit for **learning practical networking and wireless security on
your own equipment**. Built for a Raspberry Pi 5 with an **Alfa AWUS036ACH** USB
WiFi adapter (Realtek RTL8812AU chipset). Works on **Kali Linux** (recommended —
most tools ship preinstalled) or **Raspberry Pi OS** (Bookworm, 64-bit).

The goal is to *understand how the layers of a network actually work* by
observing and testing **the network you own and control** — your own router,
your own devices, your own traffic. Everything here is standard material from
network-security coursework (the same tools taught with aircrack-ng, scapy,
bettercap, mitmproxy, and Wireshark).

---

## ⚠️ Read this first — scope, ethics, and the law

This lab is **only** for equipment you own or have explicit, written permission
to test.

- ✅ **Allowed:** your own router, your own phones/laptops/IoT devices, your own
  home LAN, a lab network you built.
- ❌ **Not allowed:** anyone else's WiFi, a neighbour's / café / office /
  university network, any device you don't own, any network where you lack
  written authorization.

Capturing traffic, cracking WiFi keys, or intercepting connections on networks
you don't own is a **crime** in most countries (in India, e.g., the IT Act 2000
§43/§66; elsewhere the US CFAA, the UK Computer Misuse Act, etc.), regardless of
intent. "I was just learning" is not a legal defence.

Every script here is deliberately scoped so **you must supply your own
target** (your BSSID, your gateway, your interface). Nothing auto-discovers and
attacks strangers, and there is nothing here for hiding your tracks or evading
detection — those aren't learning, they're wrongdoing.

Treat any credentials, keys, or personal data you capture on your own network as
sensitive: keep them local, don't commit them, delete them when you're done.

---

## What's in here

| Module | What you learn | Key tools |
|---|---|---|
| [`setup/`](setup/) | Get the RTL8812AU adapter + monitor mode working (Kali or Raspbian) | `aircrack-ng`, DKMS driver |
| [`sniffing/`](sniffing/) | Read live packets, watch DNS/HTTP, map your LAN | `scapy`, `tcpdump` |
| [`recon/`](recon/) | Inventory your own network: hosts, open ports, services, OS | `nmap`, `kismet` |
| [`wifi/`](wifi/) | WPA2 handshake **and** PMKID capture, WPS audit, offline/GPU cracking — **on your own AP** (see `CRACKING.md`, `KALI-TOOLS.md`) | `airodump-ng`, `hcxdumptool`, `reaver`, `wifite`, `hashcat` |
| [`dns_resolver/`](dns_resolver/) | Make the Pi your LAN's DNS resolver (+ optional DHCP), log every query, block domains — foundation for a filtering DNS | `dnsmasq` |
| [`mitm/`](mitm/) | ARP, how MITM works, run **your own** AP (`ap_lab.sh`) + inspect **your own** device's HTTPS | `hostapd`, `bettercap`, `mitmproxy` |
| [`defense/`](defense/) | The blue team: detect deauth floods, rogue APs, ARP spoofing | `scapy` |
| [`docs/`](docs/) | Plain-English notes on the concepts behind each tool | — |

Or just run the guided menu: **`sudo bash netlab.sh`**.

## Quick start

```bash
# 1. Clone onto the Pi
git clone <your-fork-url> homelab-netsec && cd homelab-netsec

# 2. Install dependencies + the RTL8812AU driver. Review the script first!
#    Kali (recommended):
sudo bash setup/kali_setup.sh
#    Raspberry Pi OS instead:
#    sudo bash setup/install_deps.sh && sudo bash setup/setup_adapter.sh

# 3. Confirm the adapter can enter monitor mode
sudo bash setup/check_adapter.sh

# 4. Start with passive observation — no attacks, just watching your LAN.
#    Sniff the interface that actually carries your traffic (often eth0,
#    not wlan0). This picks it automatically:
IFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
sudo python3 sniffing/dns_monitor.py -i "$IFACE"

# …or drive everything from the guided menu:
sudo bash netlab.sh
```

> **Seeing nothing?** A passive sniffer only prints when traffic is actually
> flowing. In another terminal run `nslookup example.com` (or just browse) to
> generate DNS. Two caveats on a home network: on a *switched* LAN the Pi sees
> only its **own** + broadcast DNS, not other devices' — to watch others, point
> a device's DNS at the Pi or read the router logs. And if a device uses
> encrypted DNS (DoH/DoT) its lookups never hit UDP/53, so `nslookup` (classic
> :53) is the reliable test. The `wifi/` modules need the Alfa adapter plugged
> in (`iw dev` should list a `wlan1`); confirm with `setup/check_adapter.sh`.

**New here?** [`docs/FIELD-GUIDE.md`](docs/FIELD-GUIDE.md) explains every concept
in plain English and walks through the real problems we hit and how we fixed
them (with a troubleshooting table) — the best beginner on-ramp.

Work through the modules in order (`docs/00-start-here.md` is the guided path).
Start passive (`sniffing/`), understand what you see, and only then move to the
active WiFi/MITM exercises **against your own gear**.

## Hardware notes

- **Pi 5 / Raspberry Pi OS Bookworm** — 64-bit `aarch64`, kernel 6.x.
- **Kali** — most tools here (aircrack-ng, wifite, reaver, hcxdumptool, kismet,
  bettercap, nmap, hashcat) ship in `kali-linux-default`. `setup/kali_setup.sh`
  installs the RTL8812AU driver from Kali's `realtek-rtl88xxau-dkms` package —
  much simpler than a manual build.
- **AWUS036ACH** — Realtek **RTL8812AU**. This chipset is *not* supported by the
  in-tree kernel driver for monitor mode / injection. On Raspberry Pi OS,
  `setup/setup_adapter.sh` builds the community `aircrack-ng/rtl8812au` DKMS
  driver; on Kali the packaged driver above does the same job.
- The Pi's **built-in `wlan0`** cannot do monitor mode/injection reliably — use
  the Alfa for capture and keep the internal radio (or Ethernet) for your normal
  connection. After the driver installs, the Alfa usually appears as `wlan1`.

## Requirements

See [`requirements.txt`](requirements.txt) for the Python packages. System tools
are installed by `setup/install_deps.sh`.

## License

MIT — see [`LICENSE`](LICENSE). Provided for education. You are responsible for
how you use it.
