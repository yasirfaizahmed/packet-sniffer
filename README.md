# homelab-netsec — a personal network-security learning lab

A hands-on toolkit for **learning practical networking and wireless security on
your own equipment**. Built for a Raspberry Pi 5 running Raspberry Pi OS
(Bookworm, 64-bit) with an **Alfa AWUS036ACH** USB WiFi adapter
(Realtek RTL8812AU chipset).

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
| [`setup/`](setup/) | Get the RTL8812AU adapter working + monitor mode on Raspbian | `aircrack-ng`, DKMS driver |
| [`sniffing/`](sniffing/) | Read live packets, watch DNS/HTTP, map your LAN | `scapy`, `tcpdump` |
| [`wifi/`](wifi/) | The WPA2 4-way handshake, capture & offline cracking — **on your own AP** | `airodump-ng`, `aircrack-ng`, `hashcat` |
| [`mitm/`](mitm/) | ARP, how MITM works, inspecting **your own** device's HTTPS, detecting spoofing | `bettercap`, `mitmproxy` |
| [`docs/`](docs/) | Plain-English notes on the concepts behind each tool | — |

## Quick start

```bash
# 1. Clone onto the Pi
git clone <your-fork-url> homelab-netsec && cd homelab-netsec

# 2. Install dependencies (Debian/Raspbian). Review the script first!
sudo bash setup/install_deps.sh

# 3. Build the RTL8812AU driver for the AWUS036ACH (needs monitor mode)
sudo bash setup/setup_adapter.sh

# 4. Confirm the adapter can enter monitor mode
sudo bash setup/check_adapter.sh

# 5. Start with passive observation — no attacks, just watching your LAN
sudo python3 sniffing/dns_monitor.py -i wlan0
```

Work through the modules in order (`docs/00-start-here.md` is the guided path).
Start passive (`sniffing/`), understand what you see, and only then move to the
active WiFi/MITM exercises **against your own gear**.

## Hardware notes

- **Pi 5 / Raspberry Pi OS Bookworm** — 64-bit `aarch64`, kernel 6.x.
- **AWUS036ACH** — Realtek **RTL8812AU**. This chipset is *not* supported by the
  in-tree kernel driver for monitor mode / injection; `setup/setup_adapter.sh`
  installs the community `aircrack-ng/rtl8812au` DKMS driver, which is.
- The Pi's **built-in `wlan0`** cannot do monitor mode/injection reliably — use
  the Alfa for capture and keep the internal radio (or Ethernet) for your normal
  connection. After the driver installs, the Alfa usually appears as `wlan1`.

## Requirements

See [`requirements.txt`](requirements.txt) for the Python packages. System tools
are installed by `setup/install_deps.sh`.

## License

MIT — see [`LICENSE`](LICENSE). Provided for education. You are responsible for
how you use it.
