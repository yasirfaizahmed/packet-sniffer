# Concepts — plain-English notes

Short explanations of the ideas behind each tool. Read a section when the
matching stage in `00-start-here.md` uses it.

## The layers you'll see

| Layer | Unit | Addressing | Tool that shows it |
|---|---|---|---|
| Link (L2) | frame | MAC address | `packet_sniffer.py` (Ether/ARP) |
| Network (L3) | packet | IP address | `packet_sniffer.py` (IP) |
| Transport (L4) | segment | ports | `packet_sniffer.py` (TCP/UDP) |
| Application | messages | names/URLs | `dns_monitor.py`, `http_monitor.py` |

## ARP (Address Resolution Protocol)
Maps an IP to a MAC on the local network: "who has 192.168.1.1? tell me." It's
unauthenticated — any host can answer, truthfully or not. That's why it's both
the basis of `lan_hosts.py` (ask everyone, see who answers) and of LAN MITM
(answer falsely to redirect traffic). `arp_monitor.py` watches for the false
answers.

## DNS (Domain Name System)
Turns `example.com` into an IP. Nearly every connection starts with a DNS query,
and classic DNS is **plaintext UDP/53**, so logging queries tells you what a
network is talking to without touching the encrypted payload. Note: some devices
use **DoH/DoT** (encrypted DNS) and won't show up here — a real-world caveat.

## TCP handshake
`SYN` -> `SYN/ACK` -> `ACK`. In `packet_sniffer.py` you'll see flags render as
`S`, `SA`, `A`. Teardown is `F`/`FA`. Watching these makes connection setup
concrete.

## TLS / HTTPS
Encrypts the application layer. A sniffer sees the TCP connection and the TLS
handshake but **not** the URLs, headers, or content. This is why `http_monitor.py`
sees almost nothing on a modern network, and why the only honest way to inspect
HTTPS is to make an endpoint you own trust your proxy's CA (the mitm/ module).
**Certificate pinning / HSTS** makes even that fail for some apps — by design.

## Monitor mode vs. managed mode
- *Managed*: the normal client mode; the radio only hands up frames addressed to
  you (plus broadcast).
- *Monitor*: the radio hands up **every** 802.11 frame it can hear, including
  management frames (beacons, deauth) and other networks' traffic headers. This
  is required to capture the WPA handshake. Your Alfa (RTL8812AU) supports it
  with the aircrack-ng driver; the Pi's built-in radio doesn't do it reliably.

## WPA2-PSK and the 4-way handshake
See `wifi/README.md` for the full walkthrough. Key idea: the passphrase is run
through a slow hash (PBKDF2, 4096 iterations) with the SSID to make a master key;
the 4-way handshake proves both sides know it without sending it. Capturing the
handshake lets you *test* guesses offline — only guesses in your wordlist can
ever match, so a long random passphrase stays safe.

## Deauthentication frames
802.11 management frames that tell a client "you're disconnected." They're
unprotected on WPA2-Personal, so anyone can send them — which is how you force a
reconnect to capture a handshake, and also why open/PSK WiFi is vulnerable to
nuisance disconnects. (WPA3 and 802.11w/PMF protect against this.) In this lab
you only ever send them to **your own** devices, targeted by MAC.

## Why "attacker skills" are really defender skills
Every technique here has a defensive mirror: monitor mode → wireless IDS;
handshake cracking → "is my passphrase strong?"; ARP spoofing → `arp_monitor.py`;
TLS interception → "why pinning matters." The value you're building is the
ability to recognize and stop these on networks you're responsible for.

## Further reading
- Wireshark's docs and sample captures (wireshark.org) — the gold standard for
  reading traffic.
- aircrack-ng.org — the WiFi tooling and tutorials (against your own gear).
- mitmproxy.org — the proxy docs, including transparent mode and CA setup.
- The Arch/Debian wiki pages on `iw`, `NetworkManager`, and monitor mode.
