#!/usr/bin/env bash
#
# crack_handshake.sh — recover the passphrase of YOUR OWN network from a
# captured handshake, by testing candidate passwords offline against it.
#
# HOW THIS WORKS (and its limits):
#   The captured handshake lets a tool test a guessed passphrase by re-deriving
#   the key and checking the MIC. It's a pure dictionary/brute check — it can
#   ONLY find passwords that are in your wordlist (or your brute-force space).
#   A strong, random WPA2 passphrase is effectively uncrackable this way; that
#   is the security lesson. Weak/common passwords fall quickly. This is exactly
#   why you should use a long random passphrase on your real router.
#
# Two engines:
#   aircrack-ng  — CPU, simple, great for learning. Good on a Pi for small lists.
#   hashcat      — far faster with rules/masks; convert the .cap to .hc22000.
#
#   sudo bash wifi/crack_handshake.sh --cap captures/handshake-01.cap \
#        --bssid AA:BB:CC:DD:EE:FF [--wordlist /path/list.txt] [--engine aircrack|hashcat]
#
set -euo pipefail

CAP="" BSSID="" WORDLIST="" ENGINE="aircrack"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cap)      CAP="$2"; shift 2;;
    --bssid)    BSSID="$2"; shift 2;;
    --wordlist) WORDLIST="$2"; shift 2;;
    --engine)   ENGINE="$2"; shift 2;;
    -h|--help)  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
done

[[ -f "$CAP" ]] || { echo "Capture file not found: $CAP" >&2; exit 1; }

# Pick a default wordlist if none given. rockyou is the classic teaching list.
if [[ -z "$WORDLIST" ]]; then
  for cand in /usr/share/wordlists/rockyou.txt \
              /usr/share/wordlists/rockyou.txt.gz \
              wordlists/rockyou.txt; do
    if [[ -f "$cand" ]]; then WORDLIST="$cand"; break; fi
  done
fi
if [[ -z "$WORDLIST" ]]; then
  cat <<'EOF' >&2
No wordlist found. Provide one with --wordlist, e.g. the classic teaching list:
    sudo apt-get install wordlists
    sudo gunzip -k /usr/share/wordlists/rockyou.txt.gz
Then: --wordlist /usr/share/wordlists/rockyou.txt
EOF
  exit 1
fi
# rockyou often ships gzipped
if [[ "$WORDLIST" == *.gz ]]; then
  echo "[*] Decompressing $WORDLIST"; gunzip -k "$WORDLIST"; WORDLIST="${WORDLIST%.gz}"
fi

echo "[*] Engine=$ENGINE  cap=$CAP  wordlist=$WORDLIST  bssid=${BSSID:-<any>}"
echo "[*] Reminder: only crack a handshake from a network you own."
echo

case "$ENGINE" in
  aircrack)
    if [[ -n "$BSSID" ]]; then
      aircrack-ng -w "$WORDLIST" -b "$BSSID" "$CAP"
    else
      aircrack-ng -w "$WORDLIST" "$CAP"
    fi
    ;;
  hashcat)
    command -v hcxpcapngtool >/dev/null || {
      echo "Install hcxtools:  sudo apt-get install hcxtools" >&2; exit 1; }
    OUT="${CAP%.*}.hc22000"
    echo "[*] Converting $CAP -> $OUT (WPA-PBKDF2-PMKID+EAPOL / mode 22000)"
    hcxpcapngtool -o "$OUT" "$CAP"
    [[ -s "$OUT" ]] || { echo "Conversion produced no hashes (no valid handshake?)." >&2; exit 1; }
    echo "[*] Running hashcat mode 22000…"
    hashcat -m 22000 "$OUT" "$WORDLIST"
    echo "[*] Show cracked results with:  hashcat -m 22000 $OUT --show"
    ;;
  *)
    echo "Unknown engine '$ENGINE' (use aircrack or hashcat)." >&2; exit 1;;
esac
