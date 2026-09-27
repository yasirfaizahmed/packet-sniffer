# CLAUDE.md — project memory for Claude Code

This file is auto-loaded by Claude Code. It carries the context of this project
so any new session (local CLI on the Pi, or web) continues coherently.

## What this repo is

`homelab-netsec` — a personal **network-security learning lab** for the owner to
study practical networking and wireless security **on their own equipment only**.
Educational use, authorized targets only. See `README.md`.

## Hard rules (do not relax these)

- **Ownership scope:** every active tool targets only gear the owner controls.
  Active scripts require the user to pass their own target (BSSID/gateway/iface)
  and to type `YES` to confirm ownership. Keep that gate on anything new.
- **No victim-facing tooling:** build detectors, not attacks against third
  parties. E.g. the kit has a rogue-AP *detector*, deliberately **not** an
  evil-twin credential harvester. Do not add credential-phishing, detection
  evasion, mass-targeting, or DoS tooling.
- Every offensive technique here must end in a **hardening lesson** (strong
  passphrase, disable WPS, WPA3/PMF, watch for rogue APs).
- Do not commit real captures/handshakes/creds — see `.gitignore`.

## Hardware / OS

- **Raspberry Pi 5** running **Kali Linux** (was briefly Raspberry Pi OS).
- **Alfa AWUS036ACH** USB adapter (Realtek **RTL8812AU**) — the capture/monitor
  radio, usually enumerates as `wlan1`.
- Pi built-in radio is `wlan0` (Broadcom BCM4345/6). On this Kali image it runs
  **nexmon** firmware, so `wlan0` can *also* do monitor mode.

## Current environment state (as of last session)

- **Uplink is Ethernet: `eth0` = 192.168.0.106/24** (working). Keep it as the
  uplink so `airmon-ng check kill` (invoked by monitor mode) doesn't cut access.
- `wlan0` was last seen `unavailable` in NetworkManager (likely left in monitor
  mode, or `wpa_supplicant` killed by a prior `airmon-ng check kill`). rfkill is
  clear and firmware loads fine — it's a software-state issue, not hardware.
- Alfa not yet connected/tested at time of writing.

## Known gotchas (things that already bit us)

- **Sniff the interface that actually carries traffic.** The owner's traffic is
  on `eth0`, not `wlan0`. `ip route get 8.8.8.8` shows the right `dev`.
- **Switched-LAN limit:** the Pi only sees its own + broadcast traffic. To see
  *other* devices' DNS/sites, make the Pi the DNS resolver (dnsmasq), read the
  router logs, ARP-spoof (own devices), or capture in WiFi monitor mode.
- **Encrypted DNS (DoH/DoT):** Kali Firefox / systemd-resolved may encrypt DNS,
  so it won't appear on UDP/53. Test with `nslookup` (uses classic 53).
- **Monitor mode drops normal WiFi** and kills NetworkManager/wpa_supplicant on
  that radio; `wifi/monitor_mode.sh stop` restarts NetworkManager.

## Layout

`setup/` (Kali + Raspbian install, RTL8812AU driver, monitor mode) ·
`sniffing/` (packet/DNS/HTTP sniffers, host discovery, systemd DNS unit) ·
`recon/` (guided nmap) · `wifi/` (scan, 4-way handshake, PMKID, WPS, wifite,
crack) · `mitm/` (ARP detector, consented mitmproxy) · `defense/` (deauth &
rogue-AP detectors) · `docs/` (guided path + concepts) · `netlab.sh` (menu).

Run `sudo bash netlab.sh` for a menu, or follow `docs/00-start-here.md`.

## Conventions

- Work on branch **`claude/clever-goldberg-nbors6`**; commit + push there.
- Bash: `set -euo pipefail`, root check, `--help` from the header comment.
- Python: scapy-based, argparse, graceful `PermissionError`/`KeyboardInterrupt`.
- Keep docstrings/READMEs teaching the *why*, not just commands.
