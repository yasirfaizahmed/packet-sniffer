# wifi/ — auditing your own WPA2 network

This module walks the standard "audit your own WiFi" exercise end-to-end. The
goal is to *understand WPA2-PSK*, not to break into anything — you already know
your own password; recovering it from a handshake is how you prove to yourself
(a) how the protocol works and (b) whether your passphrase is strong enough.

> **Copy-paste command reference (every step, all crack modes):**
> see [`CRACKING.md`](CRACKING.md) for this kit's scripts, and
> [`KALI-TOOLS.md`](KALI-TOOLS.md) for the raw Kali tools underneath them.

> **Only run this against an access point you own or are explicitly authorized
> to test.** The capture script makes you type `YES` to confirm the AP is yours,
> and the deauth step is targeted at a client MAC you supply (one of your own
> devices) rather than blasting everyone. Deauthing or cracking other people's
> networks is a crime.

## The concept: WPA2-PSK and the 4-way handshake

WPA2-Personal derives everything from your passphrase:

1. `PMK = PBKDF2(passphrase, SSID, 4096, 256)` — a slow hash of your password
   plus the network name. This is what makes cracking *slow* (that's a feature).
2. When a device joins, it and the AP run a **4-way handshake**, exchanging two
   random nonces (ANonce, SNonce) and MAC addresses to derive a session key
   (PTK) from the PMK.
3. The handshake frames include a **MIC** (a keyed checksum) computed with that
   key.

Capturing the handshake gives you the nonces, MACs, and MIC. With those you can
**test a guessed passphrase offline**: derive the PMK from the guess, derive the
PTK, recompute the MIC, and see if it matches. It never transmits your guesses
and never touches the AP again — it's pure local computation. And it can only
ever find a password that's *in your wordlist*. A long random passphrase is
computationally infeasible to recover — which is the whole point of the lesson.

## The workflow

```bash
# 0. Build the driver + confirm monitor mode (see ../setup/)
sudo bash ../setup/check_adapter.sh

# 1. Put the Alfa into monitor mode (assume it's wlan1 -> becomes wlan1mon)
sudo bash monitor_mode.sh start wlan1

# 2. Scan and note YOUR network's BSSID + channel
sudo bash scan.sh wlan1mon
#    ... find your SSID, copy its BSSID (AP MAC) and CH, then Ctrl-C

# 3. Capture the handshake for YOUR AP. Optionally deauth one of YOUR devices
#    (its MAC via 'scan.sh' station list) to force a quick reconnect.
sudo bash capture_handshake.sh \
     --iface wlan1mon --bssid AA:BB:CC:DD:EE:FF --channel 6 \
     --client 11:22:33:44:55:66 --deauth 3 --out ../captures/mynet

# 4. Recover the passphrase offline from the captured handshake.
sudo bash crack_handshake.sh \
     --cap ../captures/mynet-01.cap --bssid AA:BB:CC:DD:EE:FF \
     --wordlist /usr/share/wordlists/rockyou.txt

# 5. Turn monitor mode back off and reconnect normally
sudo bash monitor_mode.sh stop wlan1mon
```

## What you should take away

- **See the handshake happen.** In step 3, watch airodump's header flip to
  `WPA handshake: <bssid>` the instant a client reconnects. That's the moment
  the crackable material crosses the air.
- **Feel the cost.** `aircrack-ng` on a Pi does a few thousand guesses/sec;
  `hashcat` on a GPU does billions. Either way, an 18-char random passphrase is
  out of reach. Try cracking a deliberately weak test SSID vs. your real strong
  one to feel the difference.
- **Fix your own setup.** If your real passphrase falls to `rockyou.txt` in
  minutes, change it to something long and random. That's the actionable result
  of the whole exercise.

## Files

| File | Purpose |
|---|---|
| `monitor_mode.sh` | enable/disable monitor mode on the adapter |
| `scan.sh` | list nearby APs + clients (find *your* BSSID/channel) |
| `capture_handshake.sh` | capture the 4-way handshake for your AP (ownership-gated) |
| `crack_handshake.sh` | offline dictionary attack with aircrack-ng or hashcat |
