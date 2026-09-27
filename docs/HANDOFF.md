# Session handoff — carrying context into a new Claude Code session

This is a plain-language log of what was done and where things stand, so you (or
a fresh Claude Code session on the Pi) can pick up without re-deriving it all.
`CLAUDE.md` (repo root) has the short version that Claude auto-loads; this file
is the fuller story.

## How to resume on the Pi

1. On the Pi, get the branch:
   ```bash
   git clone https://github.com/yasirfaizahmed/packet-sniffer.git
   cd packet-sniffer
   git checkout claude/clever-goldberg-nbors6
   # or if already cloned:  git pull origin claude/clever-goldberg-nbors6
   ```
2. Start Claude Code in that directory:
   ```bash
   claude
   ```
   It automatically reads `CLAUDE.md`, so it starts with the project context,
   the ethical scope, and the known gotchas below.
3. (Optional) To hand it the live thread of this work, paste the "Open items"
   section below as your first message, or just say "read docs/HANDOFF.md".

> Note: a cloud/web Claude Code chat and the local CLI are separate sessions —
> the *conversation transcript* doesn't transfer, but `CLAUDE.md` + this file +
> the git history carry all the context that matters.

## What we built (two commits on this branch)

1. Initial lab: `setup/`, `sniffing/`, `wifi/` (handshake capture + crack),
   `mitm/` (ARP detector + consented mitmproxy), `docs/`.
2. Kali expansion: `setup/kali_setup.sh`, `wifi/pmkid_capture.sh`,
   `wifi/wps_audit.sh`, `wifi/wifite_guided.sh`, `recon/nmap_scan.sh`,
   `defense/` (deauth + rogue-AP detectors), `sniffing/dns-monitor.service`,
   `netlab.sh` launcher, README/docs updates.

## Current state of the Pi (verified via the owner's terminal)

- `eth0` up, `192.168.0.106/24`, internet works.
- `wlan0` (built-in, nexmon firmware) shows `unavailable` in NetworkManager.
  rfkill is clear (soft+hard = no); `brcmfmac` + firmware load fine. So the
  block is software state, most likely: interface left in **monitor mode**, or
  **wpa_supplicant** not running (killed by a prior `airmon-ng check kill`).
- Alfa AWUS036ACH not yet plugged in / tested.

## Open items / next steps

1. **Fix `wlan0` if the owner wants built-in WiFi** (optional — Ethernet works):
   - `iw dev wlan0 info` → if `type monitor`: set it back to `managed`
     (`ip link set wlan0 down; iw dev wlan0 set type managed; ip link set wlan0 up`)
     then `systemctl restart NetworkManager`.
   - else check `systemctl status wpa_supplicant`; if dead/masked:
     `systemctl unmask wpa_supplicant; systemctl enable --now wpa_supplicant;
     systemctl restart NetworkManager`.
2. **Make dns_monitor actually show data:** run it on the interface that carries
   traffic (`ip route get 8.8.8.8` → currently `eth0`), and verify with
   `nslookup example.com`. If nothing on `eth0`, DoH/DoT is on (check Firefox
   DNS-over-HTTPS and `resolvectl status`).
3. **Whole-LAN visibility (the owner's original goal):** set up the Pi as the
   LAN DNS resolver (dnsmasq) and point the router's DHCP DNS at 192.168.0.106,
   then `dns_monitor.py -i eth0` sees every device. (Not yet built — could add a
   `sniffing/dnsmasq-resolver.md` or setup script.)
4. **First hands-on run:** `setup/check_adapter.sh` once the Alfa is in, then the
   two-terminal exercise (deauth detector + handshake capture) from
   `docs/00-start-here.md` §4.

## Ideas raised but not yet done

- `CHEATSHEET.md` at repo root (the capability brief in one page).
- WPA3/SAE + 802.11w explainer in `docs/`.
- Kismet logging config.
- A `pytest` smoke test validating each script's `--help`/arg-parsing for CI.
