# Field Guide — concepts, gotchas & fixes (start here if you're new)

This is the **plain-English walkthrough** of everything in this lab: what each
piece *is*, the **problems we actually hit**, *why* they happened, and the fix
that worked. Read it top to bottom the first time — it follows the real order
you'll work in, and each "wall" teaches a concept.

> **Ethics first (non-negotiable):** everything here is for **your own network
> and your own devices** (or ones you have written permission to test). The
> active tools make you type `YES` to confirm ownership. Capturing, cracking, or
> intercepting other people's traffic is a crime. Every attack below ends in a
> **defense** — that's the point of the lab.

**Jargon key (used throughout):**
- **AP** = Access Point (a Wi-Fi router's radio). **BSSID** = the AP's MAC address. **SSID/ESSID** = the network *name*. **Client/STATION** = a device connected to an AP.
- **Interface / `iface`** = a network port (e.g. `eth0` wired, `wlan0` built-in Wi-Fi, `wlan1` the USB Alfa).
- **Monitor mode** = a Wi-Fi mode where the radio hears *all* nearby frames, not just its own. **Injection** = transmitting crafted frames.
- **dBm** = signal strength (negative; closer to 0 = stronger; `-40` great, `-80` weak).

---

## Part 0 — the hardware, and the fix that unblocked everything

**Gear:** Raspberry Pi 5 (the computer) + an **Alfa AWUS036ACH** USB Wi-Fi
adapter (chipset Realtek RTL8812AU, driver `88XXau`). The Alfa is the
*capture/attack* radio; it shows up as **`wlan1`**. The Pi's built-in Wi-Fi is
`wlan0`; the wired port is `eth0`.

### 🧱 Wall #1: the Alfa kept "dropping" and injection failed
Symptoms: `dmesg` showed `error -71` and `USB disconnect` every few minutes;
scanning worked but deauth/injection didn't.

**Why:** the **Pi 5 caps total USB power at 600 mA** unless its power supply
negotiates 5 A. The Alfa is power-hungry — *receiving* fit under the cap, but
*transmitting* (injection) browned it out and knocked it off the bus.

**Fix that worked:**
```bash
echo "usb_max_current_enable=1" | sudo tee -a /boot/firmware/config.txt
sudo reboot            # ONLY with the official 27W PSU
```
(Alternative: a **powered USB hub**.) After this: zero drops, injection worked.
**Lesson:** on a Pi, "flaky USB Wi-Fi adapter" is almost always *power*, not the
driver or the adapter.

---

## Part 1 — sniffing & DNS (watching a network, passively)

### The theory
A **packet sniffer** reads network packets off an interface. But two facts trip
up every beginner:

1. **Sniff the interface that carries the traffic.** Your traffic leaves via
   `eth0` (wired), not `wlan0`. Find the right one:
   ```bash
   ip route get 8.8.8.8      # the "dev X" it prints is the interface to sniff
   ```
2. **A switched LAN only shows you *your own* + broadcast traffic.** A network
   switch sends each device's packets only to that device's port, so the Pi
   can't see other devices' traffic just by listening. To see *others*, you must
   become a chokepoint (be their DNS resolver, mirror a port, or use Wi-Fi
   monitor mode).

**DNS** is the phone-book of the internet (name → IP). It's the *cleanest* way
to see "what sites is this device visiting," because almost every connection
starts with a DNS lookup — and classic DNS is **plaintext** (port 53).

### 🧱 Wall #2: `dns_monitor.py` printed nothing
**Why:** we ran it on `wlan0` (no traffic) and expected instant output. A
passive sniffer only prints when packets flow.

**Fix:** run it on the live interface and *generate* a lookup:
```bash
IFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')   # e.g. eth0
sudo python3 sniffing/dns_monitor.py -i "$IFACE"
# in another terminal:  nslookup example.com
```
**Caveat — encrypted DNS (DoH/DoT):** modern browsers/OSes can send DNS *inside*
HTTPS, so it never appears on port 53. `nslookup` uses classic 53 and is the
reliable test.

---

## Part 2 — make the Pi your LAN's DNS resolver (`dns_resolver/`)

**Goal:** instead of sniffing, *become* the DNS server every device asks — the
honest way to see (and later filter) all lookups. This is how Pi-hole works.

### The theory
Set the Pi up with `dnsmasq` (a small DNS+DHCP server). Point your devices'
DNS at the Pi (via the router's DHCP settings). Now every lookup comes to the
Pi, in the clear, by design — no interception. You can **log** them (a dataset)
and **block** domains (return `0.0.0.0`), which is the foundation of a filtering
DNS.

```bash
sudo bash dns_resolver/setup_resolver.sh          # Pi becomes the resolver
python3 dns_resolver/log_to_csv.py --follow       # watch every query live
sudo python3 dns_resolver/build_blocklist.py --block lists/adult.txt --reload
sudo bash dns_resolver/cleanup.sh                 # undo it
```

### 🧱 Wall #3: the router had **no "DNS server" field**
Some routers (like the one here) won't let you hand out a custom DNS via DHCP.

**Fix:** let the **Pi run DHCP too** — turn the router's DHCP *off*, then:
```bash
sudo bash dns_resolver/set_static_ip.sh           # pin the Pi's IP first!
sudo bash dns_resolver/setup_resolver.sh --serve-dhcp \
     --gateway 192.168.0.1 --dhcp-range 192.168.0.110,192.168.0.199
```
**Why the static IP first:** the Pi normally gets its own IP *from* the router's
DHCP. If you turn that off, the Pi would lose its address — so pin it static
(via a netplan override) before disabling router DHCP.

**The one thing scripts can't do:** flip the router's setting. That's always a
manual step in the router's admin page — no Pi script can reach into the router.

---

## Part 3 — Wi-Fi handshake capture & cracking (`wifi/`)

This is the big one. Full command reference lives in
[`../wifi/CRACKING.md`](../wifi/CRACKING.md) (this kit's scripts) and
[`../wifi/KALI-TOOLS.md`](../wifi/KALI-TOOLS.md) (raw Kali tools).

### The theory: WPA2-PSK and the 4-way handshake
- Your Wi-Fi password (the **PSK**) is stretched into a master key:
  `PMK = PBKDF2(password, network-name, 4096 rounds)`. That slow hash is *why
  cracking is slow* — on purpose.
- When a device joins, it and the AP do a **4-way handshake** (four EAPOL
  messages, **M1–M4**) exchanging random numbers to derive a session key, and
  include a **MIC** (a keyed checksum).
- Capturing that handshake lets you **test password guesses offline**: for each
  guess, derive the key and check the MIC. It **never reveals the password
  directly**, and it can *only* find a password that's in your wordlist/space.
  A long random passphrase is effectively uncrackable — **that's the lesson.**

### The workflow (and where each wall was)
```bash
sudo bash wifi/monitor_mode.sh start wlan1        # 1. monitor mode
sudo bash wifi/scan_once.sh wlan1 25              # 2. find YOUR AP -> CSV
sudo bash wifi/capture_handshake.sh --iface wlan1 --bssid <YOURS> \
     --channel <CH> --client <YOUR-DEVICE> --deauth 1 --seconds 150 --out captures/mynet
# 3. it auto-converts to captures/mynet-01.hc22000 on success
```

### 🧱 Wall #4: monitor interface name
`airmon-ng start wlan1` on this driver **keeps the name `wlan1`** (it does *not*
make `wlan1mon`). Also `airmon-ng check` and `airmon-ng start` are *separate*
commands, and `start`'s second argument is a **channel**, not the interface.
Check reality with `iw dev`.

### 🧱 Wall #5: "no handshake captured" — the deauth saga
A 4-way handshake only happens when a device **(re)joins**. To force it we send
a **deauth** (a "you got disconnected" frame) so the device reconnects. We hit a
chain of sub-problems:

- **PMKSA fast-reconnect (0 EAPOL):** just toggling the phone's Wi-Fi made it
  reuse a cached key and *skip* the handshake → nothing to capture. **Fix:**
  a *deauth* or a **"forget network + rejoin"** forces a *full* handshake.
- **PMF (802.11w):** if the AP protects management frames, deauth is *ignored* —
  the phone never drops. Check: `tshark -r cap -Y wlan.rsn.capabilities.mfpr`.
  This one's AP wasn't using PMF, so deauth *should* work…
- **Over-deauth (the subtle one):** we then flooded deauth every 10 s and *still*
  got no complete handshake — because a continuous flood keeps kicking the
  client *before* the 4-way can finish. **Fix:** one gentle burst (`--deauth 1`),
  then **stay quiet ~30 s** so the handshake completes, then repeat.
- **Missing M2:** partial captures had M1/M3/M4 but not **M2** (the client's
  reply, which carries the MIC). Without a valid message *pair* there's nothing
  to crack. The gentle-deauth fix got the full set.

### 🧱 Wall #6: wrong channel / regulatory domain
One router was on **channel 12**. The Alfa was in the **world ("99") regulatory
domain**, where **channels 12–13 are receive-only** — so our capture silently
sat on channel 1 and the deauth never went out. **Fixes:** `sudo iw reg set IN`
(enable 12/13 where legal), or simplest — since it's *your* router, **change its
channel to 1–11** in the router admin.

### 🧱 Wall #7: signal / distance (`PWR = -1`)
For a far router, `airodump` showed the client at **`PWR -1`** = never heard
directly. **You must be in radio range of BOTH the AP and the target client**
(the client sends M2/M4, and your deauth must reach it). Rule of thumb: aim for
the **client's** signal better than ~**-65 dBm**. A far AP with 1 beacon and no
client frames simply can't be captured — move closer or use a directional
antenna.

### 🧱 Wall #8: the "no handshake" **false alarm**
The script kept saying "no handshake" even when we *had* one. Cause: it checked
a **hardcoded `-01.cap`**, but `airodump` increments the filename each run
(`-02`, `-03`, …). **Fix:** verify the **newest** capture, using
`hcxpcapngtool` (which definitively reports a crackable PMKID/EAPOL) — and the
script now **auto-converts** the `.cap` to a `.hc22000` on success.

### Cracking it (offline)
```bash
# on the Pi (CPU, slow):
sudo bash wifi/crack_handshake.sh --cap captures/mynet-01.cap --bssid <YOURS>
# on a GPU box (fast) — cross-platform, auto-downloads hashcat + rockyou:
python wifi/crack_hashcat.py --hash mynet.hc22000
```
`crack_hashcat.py` supports: multiple `--wordlist`s, `--fetch seclists|crackstation|weakpass`
(auto-download), `--mask` (e.g. `?d?d?d?d?d?d?d?d` = all 8-digit numbers),
`--brute 8 --charset lower|alpha|alnum|all`, and `--rules`.

**Speed & the hardening math** (WPA is slow; ~325 kH/s on a mid GPU, ~2.5 MH/s
on an RTX 4090):
| Password shape | Combinations | Mid GPU | RTX 4090 |
|---|---|---|---|
| 8 digits | 10⁸ | ~5 min | ~40 s |
| 8 lowercase | 26⁸ ≈ 2×10¹¹ | ~7 days | ~1 day |
| 8 mixed-case | 52⁸ ≈ 5×10¹³ | years | months |
| 4–5 random words | astronomical | never | never |

**Result of *this* lab:** an 8-digit Wi-Fi password fell in **minutes** on a
GPU. → **Use a long random passphrase, disable WPS, enable WPA3/PMF.**

### 🧱 Wall #9: PMKID didn't work (`hcxdumptool`)
The "clientless" PMKID method failed with *"failed to arm interface."* Cause:
**`hcxdumptool` 7.x dropped support for the Realtek `88XXau` driver** and changed
its CLI. **Fix:** on this adapter, use the 4-way-handshake path instead (PMKID
needs an `mt76`/`ath9k_htc` adapter).

---

## Part 4 — MITM: see your *own* device's HTTPS (`mitm/`)

**Goal:** watch your own phone's web traffic — including **HTTPS** — decrypted.
Command reference: [`../mitm/README.md`](../mitm/README.md) — including a
**mitmproxy interface cheat-sheet** (view / export / edit / replay / intercept).

### The theory: why you can't just sniff HTTPS
HTTPS wraps traffic in **TLS** encryption between the browser and the server.
Sniffing shows only ciphertext + a little metadata (destination IP, and the
**SNI** = which domain). To read *inside*, you put a **proxy in the middle**
(mitmproxy) that terminates TLS on both sides. But to impersonate a site, the
proxy must present a certificate the phone **trusts** — so you install
mitmproxy's **CA certificate** on *your own* device.

> **This is the ethical wall built into the internet:** only a device's owner can
> add a trusted CA. You literally cannot silently decrypt someone else's HTTPS.
> That's why this is a *self*-inspection lab, not an attack.

### Building your own AP (not an "evil twin")
`mitm/ap_lab.sh` makes the Pi broadcast **your own** SSID; your test device joins
it and routes through the Pi (NAT out to the internet), so all its traffic
transits the Pi.
```bash
sudo apt install hostapd dnsmasq
sudo bash mitm/ap_lab.sh start --iface wlan1 --uplink eth0 \
     --ssid MyLabAP --pass labpass123 --channel 6 --serve-ca
# --open for a no-password AP; --serve-ca also hosts the CA at http://10.42.0.1:8000/
sudo bash mitm/ap_lab.sh stop     # full teardown
```

### 🧱 Wall #10: "connected but no internet" — MTU/MSS
The phone got an IP and DNS worked, but pages hung. Cause: forwarded TCP packets
were **too big for the ISP's WAN link** (PPPoE/fibre often ~1492 bytes, not
1500), so big packets were silently dropped. **Fix: MSS clamping** — tell both
ends to negotiate a smaller packet size (`ap_lab.sh` now does this).

### 🧱 Wall #11: rules didn't apply / wouldn't clear — **iptables backends**
Modern Linux has **two firewall backends**: `iptables-legacy` and
`iptables-nft`, and the kernel enforces **both at once**. We added rules under
legacy, then switched the default to nft — and the *legacy* rules stayed live but
invisible to the nft tool, black-holing the phone. **Fix:** clean up in **both**
backends (`ap_lab.sh stop` now does this automatically).

### 🧱 Wall #12: transparent proxy didn't catch traffic — **QUIC**
`mitm.it` said *"traffic is not going through mitmproxy."* Cause: Chrome uses
**QUIC (HTTP/3 over UDP 443)**, which sails past a TCP-only redirect. **Fix:**
block UDP 443 so the browser falls back to interceptable TCP TLS
(`inspect_own_device.sh` now does this).

### 🧱 Wall #13: the CA certificate — three separate traps
1. **Couldn't find the CA file:** mitmproxy scatters it under whatever HOME
   `sudo` used. **Fix:** we standardized it at **`/etc/netlab-mitm`** and have the
   script generate + serve it: open `http://10.42.0.1:8000/` on the phone.
2. **Which file?** mitmproxy makes 6 files. Install **only one**:
   `mitmproxy-ca-cert.cer` (Android) or `.pem` (iOS/laptop). **Never** install
   `mitmproxy-ca.pem` — that one has the private key and stays on the Pi.
3. **Wrong store (Android):** installing it as a **Wi-Fi certificate** does
   nothing — that's for enterprise Wi-Fi login. It must go in as a **CA
   certificate** (Settings → search "CA certificate" → *Install a certificate →
   CA certificate*). You'll get a "network may be monitored" warning — that
   *confirms* it's in the right store.

### 🧱 Wall #14: proxy startup gremlins
- `[Errno 98] address already in use` → a **stale mitmproxy** held port 8080.
  Fix: the script now force-frees it (kill by PID, TERM→KILL).
- Script **exited silently after the CA banner** → a `set -e` bug where a
  no-match `grep` looked like an error. Fixed.
- Quitting the proxy **killed the phone's internet** → the script used
  `exec mitmproxy`, which replaced the shell so its cleanup **never ran**. Fixed
  (run as a child; cleanup now fires on quit/crash).

### What decrypts, and what (correctly) doesn't
- ✅ **Browser HTTPS** on the device where you trusted the CA → decrypted.
- ❌ **Apps on Android** → they use the *system* CA store, not your user CA, so
  they log "client does not trust proxy cert." That's **Android protecting
  apps** — expected. Decrypting app traffic needs the CA in the *system* store
  (root/Magisk or an emulator).
- ❌ **Pinned / HSTS sites** (banking, WhatsApp, Google) → refuse even a trusted
  CA. That's **certificate pinning** protecting users — the healthy outcome.

---

## Troubleshooting quick-reference

| Symptom | Likely cause | Fix |
|---|---|---|
| Alfa drops, `error -71`, no injection | Pi 5 USB power cap | `usb_max_current_enable=1` + 27W PSU, or powered hub |
| Sniffer prints nothing | wrong iface / no traffic / encrypted DNS | sniff `ip route get 8.8.8.8` dev; generate `nslookup` |
| `airmon-ng start` "invalid channel" | mixed up `check`/`start`; 2nd arg is channel | `airmon-ng start wlan1` (name stays `wlan1`) |
| Capture: 0 EAPOL after Wi-Fi toggle | PMKSA fast-reconnect | forget+rejoin, or deauth |
| Capture: deauth ignored, phone never drops | PMF (802.11w), or wrong channel/reg-domain, or too far | check `mfpr`; `iw reg set IN` or move AP to ch 1–11; get closer |
| Capture: lots of deauth, still no handshake | over-deauth flood | `--deauth 1`, wait ~30 s, repeat |
| "No handshake" but there is one | script checked `-01.cap` | fixed: checks newest + hcxpcapngtool |
| `hcxdumptool` "failed to arm interface" | 7.x dropped Realtek `88XXau` | use 4-way handshake path |
| Client "connected, no internet" | MTU/MSS too big for WAN | MSS clamp (built into `ap_lab.sh`) |
| Rules won't apply / won't clear | iptables legacy vs nft, both live | clean both backends (`ap_lab.sh stop`) |
| `mitm.it`: "not going through mitmproxy" | Chrome QUIC bypass | block UDP 443 (built into `inspect_own_device.sh`) |
| Phone shows cert warning / TLS failed | CA not trusted, or wrong store | install as **CA certificate**, not Wi-Fi cert; trust it |
| `[Errno 98] address already in use` | stale mitmproxy on 8080 | script force-frees it; or `sudo kill -9 <pid>` |
| Android apps: "client doesn't trust cert" | user CA ≠ system CA | expected; need system store (root/emulator) for apps |

---

## The through-line: every attack → a defense

| You learned to… | So defend with… |
|---|---|
| Crack a weak Wi-Fi password offline | long **random passphrase** (4–5 words), **disable WPS** |
| Deauth a client to force a handshake | **WPA3 / PMF (802.11w)** (ignores deauth) |
| Read open-network traffic in the air | **WPA2/WPA3**; treat open/public Wi-Fi as hostile |
| MITM your own device's HTTPS via a trusted CA | **never install unknown CAs / click past cert warnings**; use a **VPN** on untrusted networks |
| See app traffic resist interception | **certificate pinning** (why good apps are safe) |

If you understood *why* each wall existed, you now understand how these networks
actually work — which is the entire point of this lab.

---

## Want it on a phone?

Everything here ports to Android via **Kali NetHunter**, using your **Alfa over
a USB-OTG cable** for the Wi-Fi parts (phone internal chipsets can't inject, same
as the Pi's built-in). See [`ANDROID-NETHUNTER.md`](ANDROID-NETHUNTER.md) for the
safe no-root path and the full root + NetHunter install (with the bricking/Play-
Integrity warnings).
