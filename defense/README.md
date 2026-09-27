# defense/ — the blue-team side

Every offensive technique in this kit has a defensive mirror, and the defensive
skill is the more valuable one: it's what lets you protect networks you're
responsible for. Run these *while* you run the matching attack against your own
gear, and watch the attack from the target's perspective.

| Tool | Detects | Pairs with |
|---|---|---|
| `deauth_detector.py` | 802.11 deauth/disassoc floods (a WiFi DoS, or handshake-forcing) | `wifi/capture_handshake.sh --deauth` |
| `rogue_ap_detector.py` | evil-twin / rogue APs cloning your ESSID | (the attack it detects is intentionally NOT built here) |

Both need the Alfa in **monitor mode** (`sudo bash ../wifi/monitor_mode.sh start wlan1`)
and both are strictly passive — they only listen.

## Exercises

**Deauth, both sides.** Terminal A:
`sudo python3 defense/deauth_detector.py -i wlan1mon`.
Terminal B: capture your own handshake with `--deauth 3 --client <your-device>`.
Watch the detector fire. Then read `../docs/concepts.md` on 802.11w/PMF and WPA3
— the upgrade that makes those frames protected.

**Evil twin.** Run
`sudo python3 defense/rogue_ap_detector.py -i wlan1mon --essid "YourSSID" --known <your-bssid>`.
It flags any other AP advertising your network name. This is why you should be
suspicious of open networks that share a name with one you trust.

## Why detection, not an evil twin

Tools like fluxion/wifiphisher build a fake AP + captive portal to trick people
into typing their WiFi password. That's deception aimed at victims, not
learning, so it's deliberately absent here. The rogue-AP *detector* teaches the
same protocol facts and leaves you defending rather than phishing.

## Hardening checklist (what all this points to)

- Use a long, random WPA2/WPA3 passphrase (defeats `wifi/crack_*`).
- **Disable WPS** on the router (defeats `wifi/wps_audit.sh`).
- Prefer **WPA3 / enable 802.11w (PMF)** where supported (defeats deauth).
- Keep an eye out for duplicate SSIDs (`rogue_ap_detector.py`).
- Watch for gateway ARP changes (`../mitm/arp_monitor.py`).
