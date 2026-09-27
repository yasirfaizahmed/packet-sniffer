#!/usr/bin/env python3
"""
crack_hashcat.py — offline WPA test on YOUR OWN captured handshake, using
hashcat mode 22000. Cross-platform: runs on Windows (with a GPU), Linux, macOS.

This is the Windows-friendly twin of wifi/crack_handshake.sh. It does NOT touch
any network or radio — it only tests password guesses against a handshake YOU
already captured from your OWN AP. Like all offline cracking it can only find a
passphrase that's in your wordlist; a long random passphrase stays safe, which
is the whole lesson.

No Docker, no venv, no pip installs — just Python's standard library plus the
hashcat binary (download the portable build from https://hashcat.net/hashcat/).

If you don't pass --wordlist, it downloads rockyou.txt once (into wordlists/),
unzips it, and uses that. If you don't pass --hashcat, it looks on PATH, then
downloads the official hashcat build once (into tools/) and uses that — the .7z
is unpacked with 7-Zip or the bundled `tar` (Win10+/macOS); install 7-Zip if
neither is present.

Usage (Windows PowerShell / cmd):
    python wifi\\crack_hashcat.py --hash star_dust.hc22000 --hashcat C:\\hashcat\\hashcat.exe
    python wifi\\crack_hashcat.py --hash star_dust.hc22000 --wordlist rockyou.txt ^
        --hashcat C:\\hashcat\\hashcat.exe
    python wifi\\crack_hashcat.py --hash star_dust.hc22000 --show   # print result

Usage (Linux/macOS):
    python3 wifi/crack_hashcat.py --hash star_dust.hc22000            # auto rockyou
    python3 wifi/crack_hashcat.py --hash star_dust.hc22000 --wordlist rockyou.txt

--hash          the .hc22000 file (produced by hcxpcapngtool from your capture).
--wordlist      path to a wordlist. If omitted (and no --mask), rockyou is fetched.
--wordlist-url  where to fetch rockyou when --wordlist is omitted.
--mask          brute-force MASK instead of a wordlist (hashcat -a 3), e.g.
                ?d?d?d?d?d?d?d?d for all 8-digit numbers (?d=digit, ?l=lower,
                ?u=upper, ?a=all). 8 digits = 10^8 = 100 million candidates.
--hashcat       path to the hashcat binary (default: on PATH, else downloaded).
--rules         optional hashcat rules file (e.g. rules/best64.rule).
--show          just print any already-cracked result and exit.
"""
import argparse
import os
import shutil
import subprocess
import sys
import urllib.request
import zipfile

MODE = "22000"  # WPA-PBKDF2-PMKID+EAPOL

# Raw download (the /blob/ page is HTML, not the zip). Community mirror of the
# classic rockyou list — a teaching wordlist, ~50 MB unzipped.
DEFAULT_WORDLIST_URL = "https://raw.githubusercontent.com/RykerWilder/rockyou.txt/main/rockyou.txt.zip"
# Official hashcat portable build (a .7z archive).
DEFAULT_HASHCAT_URL = "https://hashcat.net/files/hashcat-7.1.2.7z"
_REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Caches: wordlists next to the repo's wordlists/ folder, hashcat under tools/.
CACHE_DIR = os.path.join(_REPO, "wordlists")
TOOLS_DIR = os.path.join(_REPO, "tools")


def _hashcat_binary_name() -> str:
    return "hashcat.exe" if sys.platform.startswith("win") else "hashcat.bin"


def _find_hashcat_in(root: str) -> str | None:
    want = _hashcat_binary_name()
    for dirpath, _dirs, files in os.walk(root):
        if want in files:
            return os.path.join(dirpath, want)
    return None


def _extract_7z(archive: str, dest: str) -> bool:
    """Unpack a .7z using any available tool: 7z CLI, or bsdtar (Win10+/macOS)."""
    os.makedirs(dest, exist_ok=True)
    # Prefer a real 7-Zip CLI.
    for name in ("7z", "7za", "7zr", "7z.exe", "7za.exe"):
        exe = shutil.which(name)
        if exe:
            if subprocess.run([exe, "x", "-y", f"-o{dest}", archive],
                              stdout=subprocess.DEVNULL).returncode == 0:
                return True
    for cand in (r"C:\Program Files\7-Zip\7z.exe", r"C:\Program Files (x86)\7-Zip\7z.exe"):
        if os.path.isfile(cand):
            if subprocess.run([cand, "x", "-y", f"-o{dest}", archive],
                              stdout=subprocess.DEVNULL).returncode == 0:
                return True
    # Fallback: the bundled `tar` on Windows 10+/macOS is bsdtar and reads 7z.
    tar = shutil.which("tar")
    if tar and subprocess.run([tar, "-xf", archive, "-C", dest]).returncode == 0:
        return True
    return False


def ensure_hashcat(explicit: str | None, url: str) -> str:
    """Return a hashcat binary: the one given, one on PATH, cached, or downloaded."""
    if explicit:
        if os.path.isfile(explicit) or shutil.which(explicit):
            return explicit
        sys.exit(f"hashcat not found at: {explicit}")

    for name in ("hashcat", "hashcat.exe", "hashcat.bin"):
        p = shutil.which(name)
        if p:
            return p

    if os.path.isdir(TOOLS_DIR):
        cached = _find_hashcat_in(TOOLS_DIR)
        if cached:
            print(f"[*] Using cached hashcat: {cached}")
            return cached

    os.makedirs(TOOLS_DIR, exist_ok=True)
    archive = os.path.join(TOOLS_DIR, os.path.basename(url))
    print(f"[*] hashcat not found; downloading (~13 MB) from:\n    {url}")
    try:
        urllib.request.urlretrieve(url, archive)
    except Exception as e:
        sys.exit(f"Download failed: {e}\nInstall hashcat manually and pass --hashcat <path>.")

    print(f"[*] Extracting {archive} …")
    if not _extract_7z(archive, TOOLS_DIR):
        sys.exit(
            f"Downloaded {archive} but couldn't extract the .7z automatically.\n"
            "Install 7-Zip (https://www.7-zip.org/) or extract it yourself, then re-run\n"
            "with --hashcat <path to hashcat.exe>."
        )

    binary = _find_hashcat_in(TOOLS_DIR)
    if not binary:
        sys.exit("Extracted hashcat but couldn't locate the binary; pass --hashcat manually.")
    if not sys.platform.startswith("win"):
        try:
            os.chmod(binary, 0o755)
        except OSError:
            pass
    print(f"[*] hashcat ready: {binary}")
    return binary


def ensure_wordlist(explicit: str | None, url: str) -> str:
    """Return a usable wordlist path: the one given, or a cached/downloaded rockyou."""
    if explicit:
        if not os.path.isfile(explicit):
            sys.exit(f"Wordlist not found: {explicit}")
        return explicit

    os.makedirs(CACHE_DIR, exist_ok=True)
    txt = os.path.join(CACHE_DIR, "rockyou.txt")
    if os.path.isfile(txt) and os.path.getsize(txt) > 0:
        print(f"[*] Using cached wordlist: {txt}")
        return txt

    zip_path = os.path.join(CACHE_DIR, "rockyou.txt.zip")
    print(f"[*] No --wordlist given; downloading rockyou (~50 MB, one-time) from:\n    {url}")
    try:
        urllib.request.urlretrieve(url, zip_path)
    except Exception as e:  # network/URL/SSL errors
        sys.exit(f"Download failed: {e}\nPass --wordlist <file> manually instead.")

    print(f"[*] Unzipping -> {txt}")
    try:
        with zipfile.ZipFile(zip_path) as z:
            members = [m for m in z.namelist() if m.lower().endswith("rockyou.txt")]
            name = members[0] if members else z.namelist()[0]
            with z.open(name) as src, open(txt, "wb") as dst:
                shutil.copyfileobj(src, dst)
    except zipfile.BadZipFile:
        sys.exit("Downloaded file is not a valid zip (the URL may have returned an HTML page).\n"
                 "Use the RAW GitHub URL, or pass --wordlist manually.")
    finally:
        try:
            os.remove(zip_path)
        except OSError:
            pass

    if not (os.path.isfile(txt) and os.path.getsize(txt) > 0):
        sys.exit("Wordlist extraction produced an empty file.")
    print(f"[*] Wordlist ready: {txt}")
    return txt


def run(cmd: list[str], cwd: str | None = None) -> int:
    print("[*] " + " ".join(cmd) + "\n")
    try:
        return subprocess.run(cmd, cwd=cwd).returncode
    except FileNotFoundError:
        sys.exit(f"Could not execute: {cmd[0]}")
    except KeyboardInterrupt:
        print("\n[*] Interrupted.")
        return 130


def hashcat_cwd(hc: str) -> str | None:
    """hashcat resolves its OpenCL/ kernels relative to the CWD, so for a
    portable/extracted build we must run it FROM its own folder. A system
    install (on PATH) finds its kernels elsewhere, so leave CWD alone there."""
    d = os.path.dirname(os.path.abspath(hc))
    return d if os.path.isdir(os.path.join(d, "OpenCL")) else None


def main() -> int:
    ap = argparse.ArgumentParser(description="Crack YOUR OWN WPA handshake with hashcat (mode 22000).")
    ap.add_argument("--hash", required=True, help="the .hc22000 hash file")
    ap.add_argument("--wordlist", help="wordlist file; if omitted, rockyou is auto-downloaded")
    ap.add_argument("--wordlist-url", default=DEFAULT_WORDLIST_URL,
                    help="URL to fetch rockyou when --wordlist is omitted")
    ap.add_argument("--mask", help="brute-force this hashcat mask (-a 3), e.g. ?d?d?d?d?d?d?d?d")
    ap.add_argument("--hashcat", help="path to hashcat binary; if omitted, it's auto-downloaded")
    ap.add_argument("--hashcat-url", default=DEFAULT_HASHCAT_URL,
                    help="URL to fetch hashcat when --hashcat is omitted")
    ap.add_argument("--rules", help="optional hashcat rules file")
    ap.add_argument("--show", action="store_true", help="print already-cracked result and exit")
    args = ap.parse_args()

    if not os.path.isfile(args.hash):
        sys.exit(f"Hash file not found: {args.hash}")
    # Paths must be ABSOLUTE because we run hashcat from its own directory.
    hash_abs = os.path.abspath(args.hash)

    hc = ensure_hashcat(args.hashcat, args.hashcat_url)
    cwd = hashcat_cwd(hc)
    print("[*] Reminder: only crack a handshake from a network you own.\n")

    if args.show:
        return run([hc, "-m", MODE, hash_abs, "--show"], cwd=cwd)

    if args.mask:
        # Brute-force attack (mode 3): hashcat generates candidates from the mask.
        n = 1
        for tok in args.mask.replace("?", " ?").split():
            if tok in ("?d", "?l", "?u", "?s", "?a", "?b", "?h", "?H"):
                n *= {"?d": 10, "?l": 26, "?u": 26, "?s": 33, "?a": 95, "?b": 256, "?h": 16, "?H": 16}[tok]
        print(f"[*] Mask attack: {args.mask}  (~{n:,} candidates)")
        cmd = [hc, "-m", MODE, hash_abs, "-a", "3", args.mask, "-w", "3"]
    else:
        wordlist = os.path.abspath(ensure_wordlist(args.wordlist, args.wordlist_url))
        cmd = [hc, "-m", MODE, hash_abs, wordlist, "-w", "3"]
        if args.rules:
            cmd += ["-r", os.path.abspath(args.rules)]
    rc = run(cmd, cwd=cwd)

    # Whatever the run's exit code, surface any cracked passphrase.
    print("\n[*] Cracked results (if any):")
    run([hc, "-m", MODE, hash_abs, "--show"], cwd=cwd)
    return rc


if __name__ == "__main__":
    sys.exit(main())
