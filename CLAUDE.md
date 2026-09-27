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
- **Networking is netplan → systemd-networkd (+ cloud-init)**, NOT ifupdown/NM
  for `eth0`. `eth0` gets its IP by **DHCP from the router** (`networkctl status
  eth0` confirms). `/etc/netplan/50-cloud-init.yaml` is authoritative; to pin a
  static IP, drop a `99-…` override (see `dns_resolver/set_static_ip.sh`) and
  disable cloud-init net regen. NetworkManager marks `eth0` unmanaged, `wlan0`
  unavailable — expected.
- **Alfa now WORKS.** `wlan1` = RTL8812AU on driver `88XXau` (phy varies, phy2/3
  as it re-enumerates), monitor + injection confirmed. `wlan0` = built-in
  BCM43455 (`brcmfmac`, phy0), also monitor-capable via nexmon.
- **Alfa USB-power fix (root cause of all the earlier grief):** the Pi 5 caps
  USB at 600 mA unless the PSU negotiates 5A, which starved the Alfa → injection
  failed and it dropped off USB (`error -71`) while RX still worked. Fixed with
  `usb_max_current_enable=1` in `/boot/firmware/config.txt` (needs official 27W
  PSU) + reboot. Alternative: powered USB hub.

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
- **Alfa keeps the name `wlan1`** in monitor mode (airmon does NOT create
  `wlan1mon` for the `88XXau` driver). `airmon-ng start <iface> [channel]` — the
  2nd arg is a *channel*, not the interface; `check` and `start` are separate.
- **hcxdumptool 7.x does NOT support the Realtek `88XXau` driver** ("failed to
  arm interface") and changed its CLI (no `--filtermode`; uses a compiled BPF,
  and it arms the radio itself — give it a *managed* iface). So PMKID via
  hcxdumptool is out on this adapter; use the aircrack-ng 4-way path.
- **PMF (802.11w) blocks deauth.** Check with
  `tshark -r cap -Y wlan.rsn.capabilities.mfpr`. If required, deauth won't
  disconnect clients — capture passively or trigger a real reconnect.
- **Over-deauth PREVENTS the handshake** — a continuous flood keeps kicking the
  client before the 4-way completes. Send ONE small burst (`--deauth 1`), stay
  quiet ~30 s, repeat. This adapter *can* inject + capture on one radio at once.
- **PMKSA fast-reconnect → 0 EAPOL.** A simple Wi-Fi toggle reuses the cached
  key and skips the 4-way. A device **forget + rejoin** forces a full handshake.
- **Signal/distance:** you must hear BOTH the AP and the target **client**
  (client sends M2/M4; deauth must reach it). Aim for client PWR better than
  ~-65 dBm; `-1`/blank client = can't capture. (A far AP with 1 beacon / no
  client frames — e.g. `Airtel_Zayyan` — cannot be captured from here.)

## Layout

`setup/` (Kali + Raspbian install, RTL8812AU driver, monitor mode) ·
`sniffing/` (packet/DNS/HTTP sniffers, host discovery, systemd DNS unit) ·
`recon/` (guided nmap) · `wifi/` (scan, 4-way handshake, PMKID, WPS, wifite,
crack; + `scan_once.sh`, `crack_hashcat.py`, and docs `CRACKING.md` /
`KALI-TOOLS.md`) · `dns_resolver/` (make the Pi the LAN DNS resolver + optional
DHCP, query logging, blocklist, static-IP helper) · `mitm/` (ARP detector,
consented mitmproxy) · `defense/` (deauth & rogue-AP detectors) · `docs/`
(guided path + concepts) · `netlab.sh` (menu).

Run `sudo bash netlab.sh` for a menu, or follow `docs/00-start-here.md`.

## Session log — 2026-09-28 (WiFi audit end-to-end + DNS resolver)

Ran the full "audit my own WiFi" loop on the owner's AP `star_dust` (BSSID
`98:25:4A:28:6B:7D`, ch 3) — confirmed owned via the router admin MAC matching
the BSSID. Fixed the Alfa (USB power, above), captured a real 4-way handshake
hands-off, cracked it on the owner's Windows GPU box (it was an 8-digit numeric
key → fell to a mask attack in minutes → hardening lesson delivered).

Built / fixed (all validated):
- `setup/check_adapter.sh` — detects USB vs built-in radio; no longer
  false-passes on `wlan0` when the Alfa is absent.
- `wifi/scan_once.sh` — NEW non-interactive scan → CSV; bails if the adapter
  drops off USB.
- `wifi/capture_handshake.sh` — added `--seconds` (unattended), gentle periodic
  deauth (1 burst / 30 s quiet), and fixed the handshake check (was hardcoded
  `-01.cap`; now newest cap + `hcxpcapngtool` detection).
- `wifi/pmkid_capture.sh` — rewritten for hcxdumptool 7.x (BPF); still blocked
  by the 88XXau-unsupported limitation above.
- `wifi/crack_hashcat.py` — NEW cross-platform GPU cracker (Windows-friendly):
  auto-downloads hashcat `.7z` + rockyou, runs from hashcat's dir (OpenCL fix),
  supports wordlist(s) / `--mask` / `--hybrid-append|prepend` / `--rules`.
- `wifi/CRACKING.md`, `wifi/KALI-TOOLS.md` — NEW command references (incl.
  client enumeration + dBm signal guidance + top-10-by-power CSV one-liners).
- `dns_resolver/` — NEW module: `setup_resolver.sh` (Pi as caching DNS resolver
  on a chosen iface, never `wlan0`; optional `--serve-dhcp`), `cleanup.sh`,
  `log_to_csv.py` (baseline dataset), `build_blocklist.py` (with an AI hook),
  `set_static_ip.sh` (netplan override). Router has NO DHCP-DNS field, so the
  LAN-wide route is `--serve-dhcp` after disabling the router's DHCP.

Not yet committed at session end (owner to decide branch).

## Conventions

- Work on branch **`claude/clever-goldberg-nbors6`**; commit + push there.
- Bash: `set -euo pipefail`, root check, `--help` from the header comment.
- Python: scapy-based, argparse, graceful `PermissionError`/`KeyboardInterrupt`.
- Keep docstrings/READMEs teaching the *why*, not just commands.
