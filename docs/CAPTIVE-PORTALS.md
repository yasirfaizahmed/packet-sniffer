# How captive portals work (the "Sign in to Wi-Fi" mechanism), in detail

A **captive portal** is the "you must sign in / accept terms to use this Wi-Fi"
page you meet at cafés, hotels, and airports. This doc explains the whole
mechanism end to end: how your phone *quietly* decides a network has a portal,
how the network *forces* the page to appear, how you get released to the real
internet, the quirks, and why the same mechanism is abused by evil-twin
attackers (and how to defend).

> This is concept/theory. This kit **does not** build a portal that auto-pushes
> a MITM certificate onto whoever connects — see the end for why.

---

## 1. The core problem the OS is solving

When your phone joins a Wi-Fi network, "connected to Wi-Fi" is **not** the same
as "has working internet." The network might:
- give you an IP but block everything until you log in (a **captive portal**), or
- be genuinely online, or
- be online-but-broken (no upstream).

The OS can't tell these apart just from the Wi-Fi association. So every modern
OS runs a **connectivity check** (a.k.a. *captive portal detection*) right after
joining: it fetches a **known URL with a known expected answer**. What comes
back tells it which of the three states it's in.

---

## 2. The "quiet check" — what each OS actually fetches

The OS requests a tiny URL on a server the OS vendor controls, and compares the
response to a **known-good** value. The check is deliberately over **plain
HTTP** (see §6 for why).

| OS / app | Probe URL (HTTP) | Expected "all good" answer |
|---|---|---|
| **Android** | `http://connectivitycheck.gstatic.com/generate_204` (also `…/gen_204`, `play.googleapis.com/generate_204`) | **HTTP `204 No Content`** (empty body) |
| **Android** (validation) | `https://www.google.com/generate_204` | `204` over HTTPS (proves real internet) |
| **iOS / macOS** | `http://captive.apple.com/hotspot-detect.html` | body is exactly `<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>` |
| **Windows (NCSI)** | `http://www.msftconnecttest.com/connecttest.txt` | body is exactly `Microsoft Connect Test` |
| **Windows (NCSI)** | DNS lookup of `dns.msftncsi.com` | resolves to `131.107.255.255` |
| **Firefox** | `http://detectportal.firefox.com/success.txt` | body is `success` |

The rule is the same everywhere: **"Did I get the exact expected token?"**
- **Yes** → the network is really online → mark **validated**, no notification.
- **No** (a redirect, a login page, wrong body, or a timeout) → **a portal (or
  no internet) is in the way** → tell the user.

On Android you can even inspect/point these:
```bash
adb shell settings get global captive_portal_http_url
adb shell settings get global captive_portal_https_url
```

---

## 3. How the network *forces* the portal to appear

The portal appears because the **gateway (the AP/router) intercepts that check**
and answers with something other than the success token. Two common techniques,
usually combined:

1. **HTTP redirect (the classic).** The gateway catches the probe's HTTP request
   (any `:80` request, really) and replies:
   ```
   HTTP/1.1 302 Found
   Location: http://portal.example/login
   ```
   The OS expected a `204`/`Success`; it got a `302` to a login page → it
   concludes **"captive portal"** and surfaces it (see §4).

2. **DNS hijack.** The gateway's DNS answers the probe domains (and everything
   else) with the portal's IP, so the probe lands on the portal instead of the
   vendor's server.

Under the hood on a Linux AP this is just NAT/redirect, e.g. "send every
unauthenticated client's TCP :80 to the local portal server":
```
iptables -t nat -A PREROUTING -i wlan0 -m mark ! --mark 1 -p tcp --dport 80 \
         -j DNAT --to-destination 10.0.0.1:8080
```
(Real portal daemons — **`nodogsplash`**, **CoovaChilli**, pfSense's portal —
do exactly this, plus the release step in §5.)

---

## 4. What the user sees (per OS)

Once the OS decides "captive portal," it reacts:
- **Android** → a heads-up notification **"Sign in to Wi-Fi network"**; tapping
  it opens the portal URL in a **special captive-portal login screen**.
- **iOS / macOS** → automatically pops the **CNA** (*Captive Network Assistant*)
  — a small built-in browser sheet — showing the portal.
- **Windows** → an "Action needed" prompt / auto-opens the portal in a browser.

These built-in screens are **stripped-down webviews**: often no cookies, no
extensions, limited JavaScript, no password manager. That's why real portals are
kept simple, and why they sometimes tell you to "open your browser and go to any
site" if the mini-browser chokes.

---

## 5. Getting released — the "walled garden" and whitelist

Before you sign in, the portal software runs a **walled garden**: it lets the
client reach only the **portal server** (and the OS probe domains), and
blocks/redirects everything else. That's why nothing works until you complete
the page.

When you finish the portal (accept terms / log in / pay), the portal software
**whitelists your device** — typically by your **MAC or IP**, via an
`iptables`/`ipset` rule or a firewall "mark":
```
# conceptually: mark this client authenticated so it bypasses the redirect
iptables -t mangle -A PREROUTING -m mac --mac-source <client> -j MARK --set-mark 1
```
Now:
1. Your traffic flows normally.
2. The OS **re-runs the connectivity check** in the background.
3. This time it gets the real `204`/`Success` → marks the network **validated** →
   the "Sign in" notification disappears.

**Key point:** a portal that redirects the check but never whitelists leaves the
device stuck showing "no internet" forever — the release step is mandatory.

---

## 6. Why the check is plain HTTP (and the HTTPS twist)

Captive detection uses **HTTP** on purpose: a gateway can transparently
**redirect** HTTP (there's no certificate to forge). It **cannot** transparently
redirect **HTTPS** — intercepting `https://…/generate_204` would require
presenting a fake certificate, which fails with a TLS error (that's TLS working).

So OSes use the HTTP probe to *detect and display* the portal, and an **HTTPS
probe** to decide the network is *genuinely validated*. This is also why an
attacker's transparent proxy can't silently sit in front of the HTTPS probe
without breaking it — and why, when a MITM proxy is running, phones often show
**"limited connectivity"**: the HTTPS validation probe hits the untrusted proxy
cert and fails.

---

## 7. Timeline of a normal café portal

```
phone joins Wi-Fi ─▶ gets IP by DHCP
      │
      ├─▶ OS probe:  GET http://connectivitycheck.gstatic.com/generate_204
      │             gateway (walled garden) ─▶ 302 to http://portal/login
      │             OS: "not 204 → captive portal"  ─▶ shows "Sign in to Wi-Fi"
      │
   user taps ─▶ mini-browser opens http://portal/login ─▶ accepts terms
      │             portal server ─▶ whitelists this MAC (firewall rule)
      │
      └─▶ OS re-probes ─▶ now gets 204 ─▶ "validated", notification clears ─▶ internet works
```

---

## 8. Legitimate uses vs. the evil-twin abuse

**Legitimate:** guest Wi-Fi sign-in, terms acceptance, paid access, and
**disclosed** corporate TLS-inspection networks that ask you to install their CA
(with a real IT policy behind it). Standard implementations: `nodogsplash`,
CoovaChilli, pfSense/OPNsense captive portal, commercial gateways.

**The abuse (evil twin):** an attacker runs a rogue AP (often cloning a real
SSID), uses this **exact** captive-portal mechanism to force a page onto anyone
who connects, and that page either:
- **harvests credentials** ("log in with your email/Google to use Wi-Fi"), or
- **pushes a rogue CA** ("install this certificate to get access") so the
  attacker can then MITM the victim's HTTPS.

The mechanism is identical to the café portal — only the *intent* and the
*honesty of the page* differ. That's why this kit:
- **builds the detector, not the trap** (`defense/rogue_ap_detector.py`), and
- serves its lab CA page only at a **URL you open on your own device**, and
  **deliberately does not** auto-force it via captive detection onto whoever
  connects (that auto-delivery is the weaponised part). See
  [`../mitm/README.md`](../mitm/README.md).

---

## 9. Defenses (what to teach / do)

- **Never install a certificate or "profile" to get on Wi-Fi.** A real network
  never needs that. This is the #1 tell of an evil-twin portal.
- **Don't enter real credentials** into a Wi-Fi login page; never "log in with
  Google/Facebook" to a portal.
- **Use a VPN** on untrusted Wi-Fi — the walled garden lets you reach the portal,
  but once connected your VPN tunnels everything past any interception.
- **Be suspicious of a portal that appears where you didn't expect one**, or that
  reappears repeatedly, or that asks for more than "accept terms."
- **On your own AP:** you can watch who connects (`iw dev wlan1 station dump`,
  dnsmasq leases) and detect rogue twins of your SSID with the `defense/` tools.

### Try it safely
- Inspect your own OS's probe: `curl -v http://connectivitycheck.gstatic.com/generate_204`
  (you'll get an empty `204`) or `curl http://captive.apple.com/hotspot-detect.html`
  (you'll see the `Success` page).
- Read the source of a legit portal daemon (`nodogsplash`) to see the
  redirect-then-whitelist logic in real code.
