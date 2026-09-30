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
# add --serve-ca to also generate + HOST the mitmproxy CA on the AP, so the
# device can install it at http://10.42.0.1:8000/ before you run the proxy:
sudo bash mitm/ap_lab.sh start --iface wlan1 --uplink eth0 \
     --ssid MyLabAP --pass labpass123 --channel 6 --serve-ca
# `--serve-ca` serves an HONEST, clearly-labelled two-step lab portal at
# http://10.42.0.1:8000/ :
#   • index.html — "Lab Wi-Fi" welcome, OPTIONAL email (client-side only, never
#     sent/stored), → Continue
#   • ca.html    — CA download (.cer/.pem) + iOS/Android install & trust steps
# It states "your own device only", collects nothing, and does NOT impersonate
# any brand/network. It is deliberately NOT a credential-harvesting evil-twin
# portal (this kit builds detectors, not that). Edit mitm/portal/*.html to taste.
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

### Who's connected to the AP?

```bash
# devices ASSOCIATED to the AP radio (authoritative), with signal/traffic:
sudo iw dev wlan1 station dump
iw dev wlan1 station dump | awk '/Station/{print $2}'     # just the MACs
# DHCP leases the AP handed out (MAC · IP · hostname):
sudo cat /var/lib/misc/dnsmasq.leases
# live IP<->MAC neighbours on the AP subnet:
ip neigh show dev wlan1
# active sweep of the AP subnet (names/vendors):
sudo arp-scan --interface=wlan1 --localnet      # apt install arp-scan
sudo python3 ../sniffing/lan_hosts.py -i wlan1  # this kit's discovery script
```
`iw … station dump` = who's on the **Wi-Fi**; the leases file = who got an
**IP** (+ hostname). Together: MAC + IP + name + signal.

### Captive portal (awareness demo) — `--captive-portal`

Add `--captive-portal` to make the AP show the **"Sign in to Wi-Fi network"**
notification and force every joining device to a lab splash — the exact
mechanism cafés/hotels/airports (and evil-twin attackers) use, so students *feel*
how a network they don't control seizes what they see first:

```bash
sudo bash mitm/ap_lab.sh start --iface wlan1 --uplink eth0 \
     --ssid MyLabAP --pass labpass123 --channel 6 --captive-portal
#   needs ipset:  sudo apt install ipset
```

What it does (all standard captive-portal tech — this is what `nodogsplash` /
CoovaChilli do for guest Wi-Fi; full theory in
[`../docs/CAPTIVE-PORTALS.md`](../docs/CAPTIVE-PORTALS.md)):

- **Intercepts the OS connectivity check.** Each client's TCP `:80` (incl. the
  `generate_204` / `hotspot-detect.html` probes) is redirected to the on-AP
  portal, which answers `302` instead of the expected success token → the OS
  raises the **"Sign in to Wi-Fi"** notification.
- **Walled garden.** Until the student clicks through, the client can reach only
  DNS + the portal; everything else is blocked (so the page stays in front).
- **Release on click-through.** Tapping **"connect me"** hits `/continue`, which
  adds the client's IP to an `ipset` the firewall treats as authenticated — now
  traffic flows and the notification clears. (Skipping this step is why a
  half-built portal leaves a device stuck on "no internet".)
- The splash (`mitm/portal/captive.html`) is **honest**: it says it's a lab,
  **collects no login details** (the nickname field never leaves the browser),
  and **installs no certificate**. Edit it to taste.

Watch it work: `tail -f /run/netlab-ap/captive.log` (releases) and
`sudo ipset list netlab_captive` (who's been let through).

**One line it won't cross:** `--captive-portal` and `--serve-ca` are mutually
exclusive, so the auto-redirect can never land on the CA-install page.
**Auto-forcing a "install this MITM certificate to get Wi-Fi" page onto every
device that connects** is the evil-twin CA-*delivery* mechanism — it pushes a
traffic-reading cert at bystanders who never sought it, and the honest label is
the only thing separating it from the real attack. So the CA page stays a URL you
open on your *own* device (`--serve-ca`, `http://<AP-IP>:8000/`), never something
shoved at everyone who joins. (Recognising that auto-popup-then-install-a-cert
flow is exactly what the `defense/` detectors and this awareness demo teach.)

## Android: apps break / "limited connectivity" while inspecting

A transparent proxy intercepts **all** TLS, but on Android **only browsers trust
a user-installed CA** — apps use the *system* store and reject mitmproxy's cert,
so they show "no internet." **Pinned apps** (Medium, X/Twitter, banking) fail
even harder, and Android flags the Wi-Fi **"limited connectivity"** because its
own reachability check is an HTTPS probe that hits the untrusted cert. This is
expected, not a misconfiguration.

Options:
- **Just browsing?** Only run the proxy while inspecting; quit it (`q`) and apps
  return.
- **Keep the phone usable while you inspect the browser** — pass those hosts
  through undecrypted with `--ignore` (repeatable; also fixes "limited
  connectivity" by letting the Google probe through):
  ```bash
  sudo bash mitm/inspect_own_device.sh --iface wlan1 \
       --ignore 'gstatic\.com|googleapis\.com' --ignore 'medium\.com' --ignore 'twitter\.com|x\.com'
  ```
- **Decrypt *app* traffic** → the CA must be in the **system** store (root +
  Magisk `MagiskTrustUserCerts`, or an emulator). Even then, **pinned** apps
  still won't decrypt — that's certificate pinning working.

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

## Using the mitmproxy interface (view / export / edit / replay)

Once `inspect_own_device.sh` is running, the full-screen **mitmproxy TUI** in
that terminal *is* your viewer. Press `:` for the command console (Tab
auto-completes), `?` for all keybindings, `q` to go back / quit.

**Prefer a clickable browser UI?** Add `--web` to use **mitmweb** instead — it
**renders responses by type: images/media preview inline, JSON/HTML are
pretty-printed** — the best generic response viewer, and it's already in Kali:
```bash
sudo bash mitm/inspect_own_device.sh --iface wlan1 --web
# it prints a URL with ?token=... — open that in a browser (http://<Pi-IP>:8081/)
```
mitmweb still needs the CA installed on the device (same as the TUI); `--web`
only changes the *viewer*. The keys/commands below apply to the TUI.

**Navigate:** `↑/↓` (or `k/j`) move · `Enter` open a flow · `Tab` cycle
Request / Response / Detail.

**Export a request/response** (`@focus` = highlighted flow; also `@all`,
`@shown`, `@marked`):
```
:export.file curl @focus captures/req.curl     # also: httpie, raw, raw_request, raw_response
:export.file raw  @focus captures/flow.txt
:export.clip curl @focus                       # clipboard (needs xclip/xsel + display; often n/a on headless Pi)
```
Save just a body: open the flow → Response tab → press `b` → give a path.

**Save whole flows (re-loadable):** `w` (or `:save.file @focus captures/session.mitm`,
`@all` for everything). Reload later with `mitmproxy -r captures/session.mitm`.

**Edit** a flow: open it (`Enter`) → `e` → pick a component (method, url, path,
query, header, form, raw body, status code…) → it opens `$EDITOR`; save + exit
to apply. Press `D` first to **duplicate** the flow if you want to keep the
original.

**Send / replay:** `r` = client-replay the (edited) request and capture the
fresh response (`:replay.client @focus`). So the loop is `Enter → e → r`.

**Modify in-flight (intercept):** `i` then a filter (e.g. `~u example.com`,
`~m POST`) → matching flows pause → edit with `e` → `a` to resume that one (`A`
resumes all). Lets you alter a request before it reaches the server, or a
response before it reaches the device.

**Filters** (for `:` commands, `f` display filter, `i` intercept): `~u <regex>`
URL · `~d <domain>` · `~m <method>` · `~c 200` status · `~q` requests · `~s`
responses.

> **Where files go:** relative paths save to mitmproxy's working directory (the
> repo folder), and since it runs under `sudo` the files are **root-owned**.
> Save into **`captures/`** (git-ignored, so real traffic is never committed);
> `sudo chown pi:pi captures/<file>` if you need to open it as `pi` later.

**Viewing exported files (Kali):** for the best all-in-one viewer use `--web`
(mitmweb) above — it previews images/media/JSON/HTML in the browser. For files
you saved to disk (via `b` or `:export.file`):
```bash
file captures/body.bin                 # identify what it is
xdg-open captures/img.png              # open with the default app
feh captures/img.png ; display captures/img.png   # image viewers (feh / ImageMagick)
mpv captures/clip.mp4 ; vlc captures/clip.mp4      # video/audio
python3 -m json.tool captures/resp.json | less     # pretty-print JSON
```
For **unencrypted HTTP** captured as a pcap (e.g. `tcpdump -i wlan1 -w cap.pcap`),
open it in **Wireshark** and use **File → Export Objects → HTTP** to dump every
image/file from the streams at once. (Wireshark can't read mitmproxy's decrypted
HTTPS flows — use mitmweb for those.)

### Content views (the response "view" dropdown) & watching video

The view dropdown (Image, JavaScript, JSON, Hex, gRPC, Protobuf, HTTP/2 frames,
HTTP/3 frames, …) is a set of **inspectors for data formats — not media
players**. Common ones:

| View | Use for |
|---|---|
| `Auto` | best guess — leave it here normally |
| `Image` | renders `image/*` inline |
| `JSON` / `XML/HTML` / `JavaScript` / `CSS` | pretty-print text bodies |
| `Hex` / `Raw` | raw bytes — the fallback for any binary (incl. video chunks) |
| `gRPC` / `Protobuf` | decode protobuf API payloads |
| `HTTP/2 frames` / `HTTP/3 frames` | low-level transport frames (debugging the protocol, not the content) |

**There is no "Video" view.** To watch a captured video:
1. **Download** the response body (mitmweb Download button, or `b` /
   `:export.file raw @focus captures/clip.mp4`) and play it: `mpv clip.mp4`.
2. **But video is usually segmented**, so one response is only a *fragment*:
   - **HLS** = a `.m3u8` playlist + many `.ts`/`.m4s` segments
   - **MPEG-DASH** = a `.mpd` manifest + segments
   - or a big file fetched via **HTTP range requests** (many `206` responses)

   So find the **manifest** URL (`.m3u8`/`.mpd`) in the flow list and reassemble:
   ```bash
   yt-dlp "https://…/master.m3u8" -o video.mp4     # handles HLS/DASH
   ffmpeg -i "https://…/playlist.m3u8" -c copy video.mp4
   ```
3. **DRM (Widevine, etc.)** streams are encrypted end-to-end — you can capture
   the bytes but **cannot play them**, by design.

**Reassembling `.m4s` segments into an `.mp4`.** `.m4s` are fragmented-MP4
segments; one alone won't play because the codec/track headers live in a
separate **init segment**. Concatenate init-first, then remux:
```bash
# init segment first (often init.mp4 / init.m4s / the "0" segment), then media
# segments IN ORDER (ls -v = numeric), then remux without re-encoding:
cat init.mp4 $(ls -v seg-*.m4s) > combined.mp4
ffmpeg -i combined.mp4 -c copy output.mp4

# DASH usually splits audio and video into two segment sets — do each, then mux:
cat video-init.mp4 $(ls -v video-*.m4s) > video.mp4
cat audio-init.mp4 $(ls -v audio-*.m4s) > audio.mp4
ffmpeg -i video.mp4 -i audio.mp4 -c copy output.mp4
```
Gotchas: the **init segment is mandatory**; keep segment **order** correct; if
`-c copy` yields a broken file, re-encode with `ffmpeg -i combined.mp4 output.mp4`.
Easiest of all — if you still have the manifest, skip hand-assembly and let
`yt-dlp "…/manifest.mpd" -o out.mp4` (or `ffmpeg -i …m3u8 -c copy out.mp4`) do it.

## bettercap (optional, advanced)

`bettercap` (installed by `setup/install_deps.sh`) is the modern all-in-one for
this. On your own lab network you can explore its `net.probe`, `net.recon`, and
`net.sniff` modules to map hosts and watch traffic. Read its docs and keep every
target inside your own network.
