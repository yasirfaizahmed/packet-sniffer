#!/usr/bin/env bash
#
# netlab.sh — a friendly menu that ties the whole lab together. It just calls
# the module scripts with the right arguments after asking you a few questions,
# so you don't have to remember every flag. Read the module READMEs to
# understand what each option actually does.
#
#   sudo bash netlab.sh
#
set -euo pipefail
cd "$(dirname "$0")"

if [[ $EUID -ne 0 ]]; then echo "Run as root:  sudo bash netlab.sh" >&2; exit 1; fi

# ask PROMPT [DEFAULT] -> echoes the answer (or the default if blank)
ask() { local a; read -r -p "$1 ${2:+[$2] }" a; echo "${a:-${2:-}}"; }
pause() { read -r -p $'\nPress Enter to return to the menu…'; }

menu() {
  cat <<'EOF'

  ┌───────────────────────────────────────────────────────────┐
  │  homelab-netsec — your network, your rules                 │
  ├───────────────────────────────────────────────────────────┤
  │  SETUP                                                      │
  │   1) Check adapter / monitor-mode support                  │
  │   2) Enable monitor mode        3) Disable monitor mode    │
  │  OBSERVE (passive)                                          │
  │   4) Discover hosts on my LAN   5) Live packet sniffer     │
  │   6) DNS query monitor          7) Nmap scan (guided)      │
  │  WIFI (own AP only)                                         │
  │   8) Scan for APs               9) Capture handshake       │
  │  10) PMKID capture             11) WPS audit               │
  │  12) Crack a capture           13) wifite (single BSSID)   │
  │  DEFEND                                                     │
  │  14) Deauth-flood detector     15) Rogue-AP detector       │
  │  16) ARP-spoofing monitor                                  │
  │   q) Quit                                                  │
  └───────────────────────────────────────────────────────────┘
EOF
}

while true; do
  menu
  choice="$(ask '  Choose:')"
  case "$choice" in
    1)
      args=(setup/check_adapter.sh)
      i="$(ask '  Interface (blank=auto):')"; [[ -n "$i" ]] && args+=("$i")
      bash "${args[@]}"; pause;;
    2) bash wifi/monitor_mode.sh start "$(ask '  Adapter (e.g. wlan1):' wlan1)"; pause;;
    3) bash wifi/monitor_mode.sh stop  "$(ask '  Monitor iface (e.g. wlan1mon):' wlan1mon)"; pause;;
    4)
      args=(sniffing/lan_hosts.py)
      r="$(ask '  CIDR (blank=auto):')"; [[ -n "$r" ]] && args+=(-r "$r")
      python3 "${args[@]}"; pause;;
    5)
      args=(sniffing/packet_sniffer.py -i "$(ask '  Interface:' eth0)")
      f="$(ask '  BPF filter (blank=all):')"; [[ -n "$f" ]] && args+=(-f "$f")
      python3 "${args[@]}"; pause;;
    6) python3 sniffing/dns_monitor.py -i "$(ask '  Interface:' eth0)"; pause;;
    7) bash recon/nmap_scan.sh --target "$(ask '  Target IP/CIDR:')" \
            --profile "$(ask '  Profile (discover/services/full/vuln):' discover)"; pause;;
    8) bash wifi/scan.sh "$(ask '  Monitor iface:' wlan1mon)"; pause;;
    9)
      args=(wifi/capture_handshake.sh --iface "$(ask '  Monitor iface:' wlan1mon)"
            --bssid "$(ask '  YOUR BSSID:')" --channel "$(ask '  Channel:')")
      c="$(ask '  Your client MAC (blank=none):')"
      [[ -n "$c" ]] && args+=(--client "$c" --deauth 3)
      bash "${args[@]}"; pause;;
    10) bash wifi/pmkid_capture.sh --iface "$(ask '  Monitor iface:' wlan1mon)" \
             --bssid "$(ask '  YOUR BSSID:')"; pause;;
    11) bash wifi/wps_audit.sh --iface "$(ask '  Monitor iface:' wlan1mon)" \
             --bssid "$(ask '  YOUR BSSID:')" --channel "$(ask '  Channel:')"; pause;;
    12)
      args=(wifi/crack_handshake.sh --cap "$(ask '  Capture file (.cap/.pcapng):')"
            --engine "$(ask '  Engine (aircrack/hashcat):' aircrack)")
      b="$(ask '  BSSID (blank=any):')"; [[ -n "$b" ]] && args+=(--bssid "$b")
      bash "${args[@]}"; pause;;
    13) bash wifi/wifite_guided.sh --bssid "$(ask '  YOUR BSSID:')"; pause;;
    14) python3 defense/deauth_detector.py -i "$(ask '  Monitor iface:' wlan1mon)"; pause;;
    15) python3 defense/rogue_ap_detector.py -i "$(ask '  Monitor iface:' wlan1mon)" \
             --essid "$(ask '  Your ESSID:')" --known "$(ask '  Your BSSID:')"; pause;;
    16) python3 mitm/arp_monitor.py -i "$(ask '  Interface:' eth0)" \
             --gateway "$(ask '  Gateway IP:')"; pause;;
    q|Q) echo "  Stay ethical. 73!"; exit 0;;
    *) echo "  Unknown choice.";;
  esac
done
