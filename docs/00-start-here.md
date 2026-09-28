# Start here — a guided path

Work top-to-bottom. Each stage builds intuition for the next. Do the passive
stages first; you'll get far more out of the active WiFi/MITM stages once you
can already read what's on the wire. **Everything is on your own network.**

> **New to all this?** Read [`FIELD-GUIDE.md`](FIELD-GUIDE.md) alongside this
> page — it explains the concepts in plain English and walks through every
> real-world problem we hit (and the fix), with a troubleshooting table.

> In a hurry? `sudo bash netlab.sh` gives you a menu that runs any of the steps
> below with the right flags. This page explains *why* you're doing each one.

## 0. Setup (once)
- **Kali:** `sudo bash setup/kali_setup.sh` — installs the toolset + RTL8812AU
  driver from Kali's package.
- **Raspberry Pi OS:** `sudo bash setup/install_deps.sh` then
  `sudo bash setup/setup_adapter.sh`.
- `sudo bash setup/check_adapter.sh` — prove monitor mode works.
- Read `docs/concepts.md` alongside — it explains every term below.

## 1. See the network (passive, safe)
- `sudo python3 sniffing/lan_hosts.py` — who is on my LAN?
- `sudo bash recon/nmap_scan.sh --target 192.168.1.0/24 --profile discover` —
  cross-check, then `--profile services <ip>` to see what a host runs.
- `sudo python3 sniffing/packet_sniffer.py -i eth0` — watch raw packets; find a
  TCP handshake (`S`, `SA`, `A`) and an ARP exchange.
- `sudo python3 sniffing/dns_monitor.py -i eth0` — which domains are being
  looked up? **This alone answers "what sites is my network visiting".**
- `sudo python3 sniffing/http_monitor.py -i eth0` — notice how little cleartext
  HTTP there is. Almost everything is HTTPS. Good.

## 2. Audit your own WiFi (active, own AP only)
Read `wifi/README.md` first — it explains the WPA2 handshake.
- `sudo bash wifi/monitor_mode.sh start wlan1`
- `sudo bash wifi/scan.sh wlan1mon` — find *your* BSSID + channel.
- **4-way handshake:** `sudo bash wifi/capture_handshake.sh --iface wlan1mon --bssid <yours> --channel <n> --client <your-device> --deauth 3`
- **PMKID (clientless):** `sudo bash wifi/pmkid_capture.sh --iface wlan1mon --bssid <yours>`
- **WPS weakness:** `sudo bash wifi/wps_audit.sh --iface wlan1mon --scan` then test your router.
- **Crack it offline:** `sudo bash wifi/crack_handshake.sh --cap captures/handshake-01.cap --bssid <yours>`
- **Or automate the whole pipeline:** `sudo bash wifi/wifite_guided.sh --bssid <yours>`
- Lesson: try it against a deliberately weak test passphrase, then your real
  strong one. Feel why length + randomness wins — and disable WPS.

## 3. Man-in-the-middle (own devices only)
Read `mitm/README.md` first.
- Consented interception: `sudo bash mitm/inspect_own_device.sh --iface eth0 --target <your-phone>`, install the CA on your phone, watch decrypted requests.
- Lesson: HTTPS with pinning refuses to decrypt. That's the protection working.

## 4. Defend — see every attack from the blue-team chair
Read `defense/README.md`. Run these *while* you run the matching attack above.
- `sudo python3 defense/deauth_detector.py -i wlan1mon` — catches the `--deauth`
  step from stage 2.
- `sudo python3 defense/rogue_ap_detector.py -i wlan1mon --essid "<yours>" --known <your-bssid>` — catches evil twins.
- `sudo python3 mitm/arp_monitor.py -i eth0 --gateway <router-ip>` — catches the
  MITM redirection from stage 3.

## 5. Reflect
- Change your real WiFi passphrase if stage 2 cracked it; **disable WPS**;
  enable WPA3/PMF if your router supports it.
- Note which of your devices leak the most via DNS.
- Understand that the same techniques are illegal off your own network — the
  skill you're building is *defensive understanding*, most valuable when you can
  spot and stop these attacks (that's what stage 4 is really about).
