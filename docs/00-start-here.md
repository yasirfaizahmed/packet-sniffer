# Start here — a guided path

Work top-to-bottom. Each stage builds intuition for the next. Do the passive
stages first; you'll get far more out of the active WiFi/MITM stages once you
can already read what's on the wire. **Everything is on your own network.**

## 0. Setup (once)
- `sudo bash setup/install_deps.sh` — tools.
- `sudo bash setup/setup_adapter.sh` — RTL8812AU driver for the AWUS036ACH.
- `sudo bash setup/check_adapter.sh` — prove monitor mode works.
- Read `docs/concepts.md` alongside — it explains every term below.

## 1. See the network (passive, safe)
- `sudo python3 sniffing/lan_hosts.py` — who is on my LAN?
- `sudo python3 sniffing/packet_sniffer.py -i eth0` — watch raw packets; find a
  TCP handshake (`S`, `SA`, `A`) and an ARP exchange.
- `sudo python3 sniffing/dns_monitor.py -i eth0` — which domains are being
  looked up? Leave it running while you browse on another device routed through
  the Pi. **This alone answers "what sites is my network visiting".**
- `sudo python3 sniffing/http_monitor.py -i eth0` — notice how little cleartext
  HTTP there is. Almost everything is HTTPS. Good.

## 2. Audit your own WiFi (active, own AP only)
Read `wifi/README.md` first — it explains the WPA2 handshake.
- `sudo bash wifi/monitor_mode.sh start wlan1`
- `sudo bash wifi/scan.sh wlan1mon` — find *your* BSSID + channel.
- `sudo bash wifi/capture_handshake.sh --iface wlan1mon --bssid <yours> --channel <n> --client <your-device> --deauth 3`
- `sudo bash wifi/crack_handshake.sh --cap captures/handshake-01.cap --bssid <yours>`
- Lesson: try it against a deliberately weak test passphrase, then your real
  strong one. Feel why length + randomness wins.

## 3. Man-in-the-middle, both sides (own devices only)
Read `mitm/README.md` first.
- Defender: `sudo python3 mitm/arp_monitor.py -i eth0 --gateway <router-ip>`
- Attacker (consented): `sudo bash mitm/inspect_own_device.sh --iface eth0 --target <your-phone>`, install the CA on your phone, watch decrypted requests.
- Lesson: HTTPS with pinning refuses to decrypt. That's the protection working.

## 4. Reflect
- Change your real WiFi passphrase if step 2 cracked it.
- Note which of your devices leak the most via DNS.
- Understand that the same techniques are illegal off your own network — the
  skill you're building is *defensive understanding*, most valuable when you can
  spot and stop these attacks.
