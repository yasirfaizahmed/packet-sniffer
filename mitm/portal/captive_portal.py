#!/usr/bin/env python3
"""
captive_portal.py — the tiny web server behind ap_lab.sh's --captive-portal.

It does three things, and nothing sneaky:

  1. Serves an HONEST splash page (captive.html) that states it's a lab, collects
     no login details, and pushes NO certificate.
  2. Answers every other request (including each OS's connectivity-check probe)
     with a 302 redirect to that splash. Getting a redirect instead of the
     expected "204/Success" token is what makes the phone raise its
     "Sign in to Wi-Fi network" notification. (See docs/CAPTIVE-PORTALS.md.)
  3. On GET /continue, RELEASES the client: it adds the client's IP to the
     ipset that the walled-garden firewall rules treat as "authenticated", so
     traffic starts flowing and the OS notification clears. This is the same
     redirect-then-whitelist logic real portal daemons (nodogsplash, CoovaChilli)
     use — the release step is mandatory, or the device is stuck with no internet.

Deliberately NOT here: no credential capture, no CA/profile delivery. This is the
honest half of the mechanism the kit otherwise only documents.

Run (ap_lab.sh does this for you, as root so ipset works):
  sudo python3 captive_portal.py --addr 10.42.0.1 --port 8000 \
       --ipset netlab_captive --dir /path/to/portal
"""
import argparse
import html
import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ARGS = None


def whitelist(ip: str) -> bool:
    """Add client IP to the 'authenticated' ipset. Returns True on success."""
    if not ip:
        return False
    try:
        subprocess.run(["ipset", "add", ARGS.ipset, ip, "-exist"],
                       check=True, capture_output=True)
        print(f"[portal] released {ip} -> internet (added to ipset {ARGS.ipset})",
              flush=True)
        return True
    except Exception as e:  # noqa: BLE001 - best effort, keep serving
        print(f"[portal] WARN could not whitelist {ip}: {e}", flush=True)
        return False


SPLASH_URL_CACHE = None


def splash_url() -> str:
    global SPLASH_URL_CACHE
    if SPLASH_URL_CACHE is None:
        SPLASH_URL_CACHE = f"http://{ARGS.addr}:{ARGS.port}/"
    return SPLASH_URL_CACHE


SUCCESS_PAGE = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Connected — Lab Wi-Fi</title>
<style>body{{margin:0;font:16px/1.55 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;
background:#0f1720;color:#e7eef6;padding:24px}}
@media(prefers-color-scheme:light){{body{{background:#eef2f7;color:#16212e}}}}
.wrap{{max-width:560px;margin:0 auto}}.card{{background:#16212e;border-radius:14px;padding:22px;
margin:14px 0}}@media(prefers-color-scheme:light){{.card{{background:#fff}}}}
h1{{font-size:1.3rem}}.ok{{color:#37c07a}}.mut{{color:#9fb0c3;font-size:.92rem}}</style></head>
<body><div class="wrap"><div class="card">
<h1><span class="ok">&#10003;</span> You're connected</h1>
<p>Your device is now released to the internet.</p>
<p class="mut">What just happened, and why it matters: tapping the button did the
<b>release step</b> a real portal performs &mdash; it told the network's firewall
to <b>whitelist your device</b>, so your traffic now flows and your phone's
&ldquo;Sign in to Wi-Fi&rdquo; notice clears. Before that click the network had
you in a <b>walled garden</b>: it forced you to one page and blocked everything
else. A network you don't control can do this to <i>you</i> &mdash; that's the
lesson.</p>
<p class="mut">This lab stored no login details and installed no certificate.</p>
</div></div></body></html>"""


class Handler(BaseHTTPRequestHandler):
    server_version = "netlab-captive/1.0"

    def log_message(self, fmt, *a):  # quieter, prefixed
        print(f"[portal] {self.client_address[0]} {fmt % a}", flush=True)

    def _redirect_to_splash(self):
        self.send_response(302)
        self.send_header("Location", splash_url())
        self.send_header("Content-Length", "0")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()

    def _send_html(self, body: str, code: int = 200):
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _serve_file(self, name: str) -> bool:
        path = os.path.join(ARGS.dir, name)
        if not os.path.isfile(path):
            return False
        try:
            with open(path, "rb") as f:
                data = f.read()
        except OSError:
            return False
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)
        return True

    def do_GET(self):  # noqa: N802 (http.server API)
        path = self.path.split("?", 1)[0]

        # Release step: whitelist this client, then confirm.
        if path == "/continue":
            ok = whitelist(self.client_address[0])
            note = "" if ok else (
                "<p class='mut'>(Note: the firewall whitelist call did not "
                "succeed &mdash; check that ipset is installed and this ran as "
                "root; you may still be in the walled garden.)</p>")
            self._send_html(SUCCESS_PAGE.format() + note)
            return

        # Serve the splash itself at "/" or when the splash file is asked for.
        if path in ("/", "/index.html", "/captive.html"):
            if self._serve_file("captive.html"):
                return
            # Fallback splash if the file is missing.
            self._send_html(
                "<h1>Lab Wi-Fi</h1><p>Training network. "
                f"<a href='/continue'>Continue to the internet &rarr;</a></p>")
            return

        # Everything else (all OS captive-check probes, any other host/URL the
        # device tries) -> 302 to the splash. That non-"204/Success" answer is
        # what triggers the "Sign in to Wi-Fi" notification.
        self._redirect_to_splash()

    def do_POST(self):  # noqa: N802
        # We collect nothing; treat any POST as a benign continue.
        if self.path.split("?", 1)[0] == "/continue":
            whitelist(self.client_address[0])
            self._send_html(SUCCESS_PAGE.format())
            return
        self._redirect_to_splash()


def main():
    global ARGS
    ap = argparse.ArgumentParser(description="Honest lab captive-portal server.")
    ap.add_argument("--addr", required=True, help="AP gateway IP to bind/redirect to")
    ap.add_argument("--port", type=int, default=8000)
    ap.add_argument("--ipset", default="netlab_captive",
                    help="ipset name the firewall treats as authenticated clients")
    ap.add_argument("--dir", required=True, help="directory holding captive.html")
    ARGS = ap.parse_args()

    if not os.path.isfile(os.path.join(ARGS.dir, "captive.html")):
        print(f"[portal] WARN captive.html not found in {ARGS.dir}", file=sys.stderr)

    httpd = ThreadingHTTPServer((ARGS.addr, ARGS.port), Handler)
    print(f"[portal] serving honest lab splash on http://{ARGS.addr}:{ARGS.port}/ "
          f"(release -> ipset {ARGS.ipset})", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
