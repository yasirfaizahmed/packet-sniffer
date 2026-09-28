# mitm/ — man-in-the-middle: how it works, from both sides

This module teaches the LAN man-in-the-middle concept the responsible way:

- **Understand the mechanism** (ARP, IP forwarding, TLS interception).
- **See it as the attacker** — but only against **a device you own**, that has
  **consented** by trusting your proxy's CA.
- **See it as the defender** — detect the same attack with `arp_monitor.py`.

> Positioning yourself between other people's devices and reading their traffic
> is illegal and is not "learning". Everything here is scoped to your own gear
> and requires you to type `YES` to confirm ownership. There is nothing here to
> defeat certificate pinning or to intercept devices that haven't opted in — a
> device that refuses interception is TLS working correctly, and that's a
> lesson too.

## The concept

A LAN MITM has two parts:

1. **Redirection** — get the victim's packets to flow through you. On a LAN the
   classic trick is **ARP spoofing**: ARP has no authentication, so you send
   forged "the router is at *my* MAC" replies. (In this lab you instead route
   your *own* device through the Pi explicitly — same effect, no deception.)
2. **Interception** — once traffic flows through you, forward it (IP forwarding)
   and inspect it. Plain HTTP is readable immediately. **HTTPS is not** — to
   read it, the endpoint must trust your CA, which is why the honest exercise is
   to install the proxy's CA on the device you own.

## "Check all the sites my router / LAN is talking to"

You have three honest options, cleanest first:

1. **DNS logging** (recommended, no interception): run
   `../sniffing/dns_monitor.py` on the Pi with the Pi acting as your LAN's DNS
   resolver (point your router's DHCP DNS at the Pi, or run it on the router).
   You get a live list of every domain each client looks up — which is exactly
   "what sites is my network visiting" — without decrypting anyone's traffic.
2. **Router-side view**: many home routers expose a traffic/connection log or
   can forward logs (syslog) to the Pi. This is the most complete and the least
   invasive, because the router already sees everything.
3. **Proxy your own device** (`inspect_own_device.sh`): full request/response
   detail (URLs, headers, bodies) for **one device you own** that trusts the CA.

## Run your own AP and route a device through it — `ap_lab.sh`

The cleanest MITM lab is to **be the access point** (no ARP tricks): your own
SSID, your own client. The Alfa (`wlan1`, AP-mode capable) broadcasts an AP,
NATs to the internet via your router uplink, and **every packet from the
connected device transits the Pi**, where you inspect it.

```bash
sudo apt install hostapd dnsmasq                       # one-time
sudo bash mitm/ap_lab.sh start --iface wlan1 --uplink eth0 \
     --ssid MyLabAP --pass labpass123 --channel 6      # type YES to confirm
# or an OPEN network (no password) — traffic is unencrypted on the air,
# a vivid demo of why open WiFi is unsafe:
sudo bash mitm/ap_lab.sh start --ssid MyLabAP --open
# connect a device YOU OWN to "MyLabAP", then inspect its traffic:
sudo tcpdump -i wlan1 -n                                # cleartext + DNS + SNI + metadata
tail -f /run/netlab-ap/dns.log                          # domains the client looks up
sudo bash mitm/inspect_own_device.sh --iface wlan1      # HTTPS, decrypted (CA on the device)
sudo bash mitm/ap_lab.sh status
sudo bash mitm/ap_lab.sh stop                           # tear down (restores the radio + NAT)
```

**Not an evil twin:** it advertises an SSID *you chose* and is for a device you
own and knowingly connect. Without the mitmproxy CA installed on that device,
HTTPS stays encrypted (you still see DNS/SNI/metadata) — the same boundary as
`inspect_own_device.sh`. Impersonating another network to trap other people's
devices is out of scope and not built here.

## Files

| File | Role | Perspective |
|---|---|---|
| `ap_lab.sh` | run YOUR OWN AP so a device you own routes through the Pi for inspection (`start`/`stop`/`status`) | attacker (consented) |
| `arp_monitor.py` | detect ARP-spoofing / MITM on your LAN | defender |
| `inspect_own_device.sh` | transparent mitmproxy for a device you own (CA-based) | attacker (consented) |

## Suggested exercise

1. In terminal A, start the defender: `sudo python3 arp_monitor.py -i eth0 --gateway 192.168.1.1`
2. In terminal B, route one of your own phones through the Pi and run
   `sudo bash inspect_own_device.sh --iface eth0 --target <your-phone-ip>`.
3. Install the mitmproxy CA on that phone, then browse. The reliable way (the
   `http://mitm.it` page only works when the transparent redirect is perfectly
   catching traffic) is to serve the CA straight off the Pi by IP:
   ```bash
   # CA lives in the fixed folder /etc/netlab-mitm (inspect_own_device.sh
   # generates it there on first run). In a second terminal:
   sudo python3 -m http.server 8000 --directory /etc/netlab-mitm
   # on the device: open http://<AP-or-Pi-IP>:8000/ and install + TRUST
   #   mitmproxy-ca-cert.cer (Android) / .pem (iOS: enable in Certificate Trust
   #   Settings). Install the CA BEFORE starting the proxy, or HTTPS breaks.
   ```
4. Watch decrypted requests appear in mitmproxy — and watch `arp_monitor.py`
   (if you use ARP redirection) light up with the gateway MAC change. You've now
   seen the same event as both attacker and defender.
5. Now try a site with HSTS/pinning (e.g. a banking app) and watch it *fail* to
   decrypt. Understand why that protects real users.

## bettercap (optional, advanced)

`bettercap` (installed by `setup/install_deps.sh`) is the modern all-in-one for
this. On your own lab network you can explore its `net.probe`, `net.recon`, and
`net.sniff` modules to map hosts and watch traffic. Read its docs and keep every
target inside your own network.
