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

--hash            the .hc22000 file, OR a raw capture (.cap/.pcap/.pcapng) which
                  is auto-converted with hcxpcapngtool if it's installed here.
--wordlist        a wordlist; REPEATABLE (--wordlist a.txt --wordlist b.txt).
                  If omitted (and no --mask), rockyou is auto-downloaded.
--wordlist-url    where to fetch rockyou when --wordlist is omitted.
--fetch           download+use a named list (repeatable): seclists, crackstation,
                  weakpass, rockyou. Saved (cached) into the repo's wordlists/.
--fetch-url       download+use a wordlist from any URL (.txt/.gz/.zip/.7z).
--yes             skip the confirm prompt for large downloads.
--brute LEN       brute-force ALL LEN-char combos, no wordlist, with --charset:
                  digit(10) lower(26) upper(26) alpha(52) alnum(62) all(95).
                  e.g. --brute 8 --charset lower = 26^8 = 208,827,064,576 combos.
--mask            pure brute-force MASK (hashcat -a 3), e.g. ?d?d?d?d?d?d?d?d
                  for all 8-digit numbers (?d=digit, ?l=lower, ?u=upper, ?a=all).
--hybrid-append   word + MASK  (hashcat -a 6), e.g. ?d?d?d?d -> cactus1984
--hybrid-prepend  MASK + word  (hashcat -a 7), e.g. ?d?d?d?d -> 1984cactus
--rules           mutate the wordlist with a rules file (e.g. best64.rule).
--hashcat         path to hashcat (default: on PATH, else auto-downloaded).
--show            just print any already-cracked result and exit.

Attacks are mutually exclusive: pick --mask, OR --hybrid-*, OR wordlist(s).
"""
import argparse
import gzip
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

# Named wordlists for --fetch. Each: (url, approx-size note). Formats .txt/.gz/
# .zip/.7z are all handled. URLs can rot — override any with --fetch-url <URL>.
# "seclists" grabs xato-net's top-1,000,000 password list, not the whole repo.
WORDLIST_CATALOG = {
    "rockyou":      (DEFAULT_WORDLIST_URL, "~130 MB unzipped"),
    "seclists":     ("https://raw.githubusercontent.com/danielmiessler/SecLists/master/Passwords/Common-Credentials/xato-net-10-million-passwords-1000000.txt", "~8.5 MB, top 1,000,000"),
    "crackstation": ("https://crackstation.net/files/crackstation-human-only.txt.gz", "~680 MB unzipped"),
    "weakpass":     ("https://download.weakpass.com/wordlists/1948/weakpass_3a.7z", "MULTI-GB (if the link 404s, pass --fetch-url with a current weakpass URL)"),
}

# Charsets for --brute (pure brute force, no wordlist). "custom" means we pass a
# hashcat -1 custom set and the mask uses ?1. size = number of symbols.
BRUTE_CHARSETS = {
    "digit": {"token": "?d", "size": 10},
    "lower": {"token": "?l", "size": 26},
    "upper": {"token": "?u", "size": 26},
    "alpha": {"token": "?1", "size": 52, "custom": "?l?u"},
    "alnum": {"token": "?1", "size": 62, "custom": "?l?u?d"},
    "all":   {"token": "?a", "size": 95},
}


def _fmt_secs(s: float) -> str:
    for unit, n in (("y", 31536000), ("d", 86400), ("h", 3600), ("m", 60)):
        if s >= n:
            return f"{s / n:.1f}{unit}"
    return f"{s:.0f}s"
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


def _confirm_big(name: str, size_note: str, assume_yes: bool) -> None:
    if assume_yes or "MB" in size_note and "MULTI" not in size_note.upper():
        return  # small/medium: no prompt
    try:
        ans = input(f"  '{name}' is {size_note}. Download now? [y/N] ").strip().lower()
    except EOFError:
        ans = ""
    if ans not in ("y", "yes"):
        sys.exit("Aborted (skipped large download). Use --yes to skip this prompt.")


def download_and_extract(url: str, dest_dir: str, assume_yes: bool = False,
                         name: str = "", size_note: str = "") -> str:
    """Download URL into dest_dir and return a plain-text wordlist path.
    Handles .txt / .gz / .zip / .7z. Caches: skips re-download if already there."""
    os.makedirs(dest_dir, exist_ok=True)
    base = url.split("?")[0].rstrip("/").split("/")[-1] or "wordlist"
    stem = base
    for ext in (".gz", ".zip", ".7z", ".txt"):
        if stem.lower().endswith(ext):
            stem = stem[: -len(ext)]
            break
    out_txt = os.path.join(dest_dir, stem if stem.lower().endswith(".txt") else stem + ".txt")
    if os.path.isfile(out_txt) and os.path.getsize(out_txt) > 0:
        print(f"[*] Using cached wordlist: {out_txt}")
        return out_txt

    if size_note:
        _confirm_big(name or base, size_note, assume_yes)

    archive = os.path.join(dest_dir, base)
    print(f"[*] Downloading {name or base} ({size_note or 'size unknown'})\n    {url}")
    try:
        urllib.request.urlretrieve(url, archive)
    except Exception as e:
        sys.exit(f"Download failed: {e}\nTry --fetch-url with a current link, or --wordlist <file>.")

    low = base.lower()
    if low.endswith(".gz"):
        print(f"[*] Decompressing .gz -> {out_txt}")
        with gzip.open(archive, "rb") as src, open(out_txt, "wb") as dst:
            shutil.copyfileobj(src, dst)
        os.remove(archive)
    elif low.endswith(".zip"):
        print(f"[*] Unzipping -> {out_txt}")
        with zipfile.ZipFile(archive) as z:
            members = [m for m in z.namelist() if m.lower().endswith(".txt")] or z.namelist()
            with z.open(members[0]) as src, open(out_txt, "wb") as dst:
                shutil.copyfileobj(src, dst)
        os.remove(archive)
    elif low.endswith(".7z"):
        print(f"[*] Extracting .7z (needs 7z or bsdtar) …")
        subdir = os.path.join(dest_dir, stem + "_x")
        if not _extract_7z(archive, subdir):
            sys.exit(f"Downloaded {archive} but couldn't extract the .7z (install 7-Zip).")
        # pick the largest file inside as the wordlist
        biggest, bsize = None, -1
        for dp, _d, fs in os.walk(subdir):
            for f in fs:
                p = os.path.join(dp, f); sz = os.path.getsize(p)
                if sz > bsize:
                    biggest, bsize = p, sz
        if not biggest:
            sys.exit("7z extracted nothing usable.")
        shutil.move(biggest, out_txt)
        shutil.rmtree(subdir, ignore_errors=True)
        os.remove(archive)
    else:  # plain .txt
        if os.path.abspath(archive) != os.path.abspath(out_txt):
            shutil.move(archive, out_txt)

    if not (os.path.isfile(out_txt) and os.path.getsize(out_txt) > 0):
        sys.exit("Wordlist download produced an empty file.")
    print(f"[*] Wordlist ready: {out_txt}  ({os.path.getsize(out_txt)/1e6:.1f} MB)")
    return out_txt


def fetch_named(name: str, assume_yes: bool) -> str:
    key = name.strip().lower()
    if key not in WORDLIST_CATALOG:
        sys.exit(f"Unknown --fetch '{name}'. Choices: {', '.join(WORDLIST_CATALOG)}")
    url, size_note = WORDLIST_CATALOG[key]
    return download_and_extract(url, CACHE_DIR, assume_yes, name=key, size_note=size_note)


def resolve_wordlists(explicit: list[str] | None, url: str) -> list[str]:
    """Return absolute paths for the given wordlists, validating each; if none
    were given, auto-download rockyou and return that single list."""
    if explicit:
        out = []
        for w in explicit:
            if not os.path.isfile(w):
                sys.exit(f"Wordlist not found: {w}")
            out.append(os.path.abspath(w))
        return out
    return [os.path.abspath(ensure_wordlist(None, url))]


def gather_wordlists(args) -> list[str]:
    """All wordlists to use: explicit --wordlist(s), --fetch names, --fetch-url
    downloads; falls back to auto-rockyou if nothing else was requested."""
    out: list[str] = []
    for w in (args.wordlist or []):
        if not os.path.isfile(w):
            sys.exit(f"Wordlist not found: {w}")
        out.append(os.path.abspath(w))
    for name in (args.fetch or []):
        out.append(os.path.abspath(fetch_named(name, args.yes)))
    for url in (args.fetch_url or []):
        out.append(os.path.abspath(download_and_extract(url, CACHE_DIR, args.yes, name="custom")))
    if not out:
        out.append(os.path.abspath(ensure_wordlist(None, args.wordlist_url)))
    return out


def ensure_hash22000(path: str) -> str:
    """Accept a mode-22000 hash as-is, or convert a raw capture to one."""
    low = path.lower()
    if low.endswith((".hc22000", ".22000")):
        return path
    if low.endswith((".cap", ".pcap", ".pcapng")):
        tool = shutil.which("hcxpcapngtool")
        if not tool:
            sys.exit(
                "Got a capture file, but hcxpcapngtool isn't installed here.\n"
                "Convert it on the Pi/Kali first:\n"
                "    hcxpcapngtool -o out.hc22000 " + path + "\n"
                "then pass --hash out.hc22000  (Kali: sudo apt install hcxtools)."
            )
        out = os.path.splitext(path)[0] + ".hc22000"
        print(f"[*] Converting capture -> {out}")
        subprocess.run([tool, "-o", out, path], stdout=subprocess.DEVNULL)
        if not (os.path.isfile(out) and os.path.getsize(out) > 0):
            sys.exit("Conversion produced no hash — the capture may lack a complete handshake.")
        return out
    return path  # unknown extension: assume it's already a hash file


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
    ap.add_argument("--wordlist", action="append",
                    help="wordlist file; repeatable. If omitted, rockyou is auto-downloaded")
    ap.add_argument("--wordlist-url", default=DEFAULT_WORDLIST_URL,
                    help="URL to fetch rockyou when --wordlist is omitted")
    ap.add_argument("--fetch", action="append", metavar="NAME",
                    help="download+use a named list (repeatable): " + ", ".join(WORDLIST_CATALOG))
    ap.add_argument("--fetch-url", action="append", metavar="URL",
                    help="download+use a wordlist from any URL (.txt/.gz/.zip/.7z); repeatable")
    ap.add_argument("--yes", action="store_true", help="skip the large-download confirm prompt")
    ap.add_argument("--mask", help="brute-force this hashcat mask (-a 3), e.g. ?d?d?d?d?d?d?d?d")
    ap.add_argument("--brute", type=int, metavar="LEN",
                    help="brute-force ALL LEN-char combos, no wordlist (e.g. --brute 8 --charset lower)")
    ap.add_argument("--charset", default="lower", choices=list(BRUTE_CHARSETS),
                    help="charset for --brute: digit/lower/upper/alpha/alnum/all (default lower)")
    ap.add_argument("--hybrid-append", help="word + MASK (hashcat -a 6), e.g. ?d?d?d?d")
    ap.add_argument("--hybrid-prepend", help="MASK + word (hashcat -a 7), e.g. ?d?d?d?d")
    ap.add_argument("--hashcat", help="path to hashcat binary; if omitted, it's auto-downloaded")
    ap.add_argument("--hashcat-url", default=DEFAULT_HASHCAT_URL,
                    help="URL to fetch hashcat when --hashcat is omitted")
    ap.add_argument("--rules", help="optional hashcat rules file")
    ap.add_argument("--show", action="store_true", help="print already-cracked result and exit")
    args = ap.parse_args()

    if not os.path.isfile(args.hash):
        sys.exit(f"Hash file not found: {args.hash}")
    # Accept a raw capture and convert, or take a .hc22000 as-is.
    # Paths must be ABSOLUTE because we run hashcat from its own directory.
    hash_abs = os.path.abspath(ensure_hash22000(args.hash))

    hc = ensure_hashcat(args.hashcat, args.hashcat_url)
    cwd = hashcat_cwd(hc)
    print("[*] Reminder: only crack a handshake from a network you own.\n")

    if args.show:
        return run([hc, "-m", MODE, hash_abs, "--show"], cwd=cwd)

    if args.mask:
        # Pure brute-force (mode 3): hashcat generates candidates from the mask.
        n = 1
        for tok in args.mask.replace("?", " ?").split():
            n *= {"?d": 10, "?l": 26, "?u": 26, "?s": 33, "?a": 95,
                  "?b": 256, "?h": 16, "?H": 16}.get(tok, 1)
        print(f"[*] Mask attack: {args.mask}  (~{n:,} candidates)")
        cmd = [hc, "-m", MODE, hash_abs, "-a", "3", args.mask, "-w", "3"]
    elif args.brute:
        # Pure brute-force of every LEN-char combo from a charset (no wordlist).
        cs = BRUTE_CHARSETS[args.charset]
        mask = cs["token"] * args.brute
        total = cs["size"] ** args.brute
        est = total / 325000.0   # ~a mid GPU's WPA rate
        print(f"[*] Brute force: {args.brute} x {args.charset} ({cs['size']} symbols) "
              f"= {cs['size']}^{args.brute} = {total:,} combinations")
        print(f"[*] Rough time @ ~325 kH/s (a mid GPU): ~{_fmt_secs(est)} — your GPU may differ")
        cmd = [hc, "-m", MODE, hash_abs, "-a", "3"]
        if "custom" in cs:
            cmd += ["-1", cs["custom"]]
        cmd += [mask, "-w", "3"]
    elif args.hybrid_append or args.hybrid_prepend:
        base = gather_wordlists(args)[0]
        if args.hybrid_append:
            print(f"[*] Hybrid: word + {args.hybrid_append}  (-a 6)")
            cmd = [hc, "-m", MODE, hash_abs, base, "-a", "6", args.hybrid_append, "-w", "3"]
        else:
            print(f"[*] Hybrid: {args.hybrid_prepend} + word  (-a 7)")
            cmd = [hc, "-m", MODE, hash_abs, "-a", "7", args.hybrid_prepend, base, "-w", "3"]
    else:
        wls = gather_wordlists(args)
        print(f"[*] Dictionary attack over {len(wls)} wordlist(s).")
        cmd = [hc, "-m", MODE, hash_abs, *wls, "-w", "3"]
        if args.rules:
            cmd += ["-r", os.path.abspath(args.rules)]
    rc = run(cmd, cwd=cwd)

    # Whatever the run's exit code, surface any cracked passphrase.
    print("\n[*] Cracked results (if any):")
    run([hc, "-m", MODE, hash_abs, "--show"], cwd=cwd)
    return rc


if __name__ == "__main__":
    sys.exit(main())
