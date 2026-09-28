# Running this kit on Android — Kali NetHunter (+ your Alfa over OTG)

Everything you did on the Pi can run on an Android phone via **Kali NetHunter**,
Kali's official Android build. This page covers the **safe (no-root)** path and
the **full-root** path, with the honest warnings.

> **Same ethics as the whole lab:** your own devices and networks (or written
> authorization) only. Rooting/flashing is *your* phone, *your* risk.

> ⚠️ **Read before you flash anything:**
> - Unlocking the bootloader **wipes the phone completely** (factory reset).
> - Rooting can **brick** the device, **voids warranty**, and **breaks Play
>   Integrity/SafetyNet** — banking, payment, and some streaming apps may stop
>   working.
> - Root itself is a **security downgrade** (more ways for malware to persist).
> - **Do this on a spare/test phone, not your daily driver.** Back up first.

---

## The three editions (pick by how much access you have)

| Edition | Needs | Gives you |
|---|---|---|
| **Rootless** | no root (Termux) | full Kali CLI tools; **no** injection on internal Wi-Fi |
| **Lite** | root, any device | above + system access; still no internal-Wi-Fi injection |
| **Full** | root **+ NetHunter kernel** (supported device) | Wi-Fi injection/monitor (with adapter), HID/BadUSB, MANA evil-AP, full menu |

**The Wi-Fi limitation is the same as the Pi:** phone *internal* chipsets don't
do monitor mode/injection — so for capture/deauth you use an **external USB
adapter over a USB-OTG cable**. Your **Alfa AWUS036ACH (RTL8812AU)** works with
NetHunter, so the whole `wifi/` workflow (scan → handshake → crack) ports over.

---

## Option A — Rootless (safe, start here)

No bootloader unlock, no brick risk. Great for tool demos (nmap, Metasploit,
sqlmap, hydra, hashcat, recon, web).

1. Install **Termux** and **Termux:API** from **F-Droid** (the Play Store
   builds are outdated — use F-Droid or GitHub releases).
2. In Termux:
   ```bash
   pkg update && pkg install wget
   wget -O install-nethunter-termux https://offs.ec/2MceZWr
   chmod +x install-nethunter-termux && ./install-nethunter-termux
   ```
   (That's Kali's official rootless installer. Or, for a plain CLI Kali:
   `pkg install proot-distro && proot-distro install kali`.)
3. Start it: `nethunter` (or `kali`), then `apt update && apt install kali-linux-default`.

CLI tools work; anything needing **raw sockets / injection on internal Wi-Fi**
won't — add the Alfa over OTG for that (works best with full NetHunter).

---

## Option B — Full root + NetHunter (the capable path)

Steps are **device-specific** — always follow the guide for *your exact model*.
This is the general Magisk flow that most devices use.

### 0. Prerequisites
- A **NetHunter-supported device** (check the list at
  <https://www.kali.org/get-kali/#kali-mobile> / the NetHunter docs). Supported
  models have prebuilt kernels; others need building.
- A computer with **`adb`** and **`fastboot`** (`sudo apt install android-tools-adb android-tools-fastboot` on Kali/the Pi).
- **Full backup** — the next step erases everything.

### 1. Enable developer options
Settings → About phone → tap **Build number** 7×. Then Settings → System →
Developer options → enable **OEM unlocking** and **USB debugging**.

### 2. Unlock the bootloader (⚠️ wipes the phone)
```bash
adb reboot bootloader
fastboot flashing unlock        # some devices: fastboot oem unlock
# confirm on the phone's screen (Volume/Power) — it factory-resets
```
(Samsung uses Download mode + Odin instead of fastboot; Xiaomi needs their Mi
Unlock tool + a waiting period. Follow your model's guide.)

### 3. Root with Magisk
The modern way (no custom recovery needed on most devices):
1. Download the **stock boot image** for your exact firmware build.
2. Install the **Magisk** app, use **"Patch a file"** → select `boot.img` → it
   outputs `magisk_patched.img`.
3. Flash it:
   ```bash
   adb reboot bootloader
   fastboot flash boot magisk_patched.img
   fastboot reboot
   ```
4. Open Magisk → confirm root is active.
(Devices that use TWRP recovery instead: flash **TWRP**, then flash the Magisk
zip from recovery.)

### 4. Install NetHunter
- Grab the **NetHunter image for your device/Android version** from
  <https://www.kali.org/get-kali/#kali-mobile>.
- Flash it via **TWRP** (flash the NetHunter zip), **or** install the
  **NetHunter installer app** and let it deploy. This provides the NetHunter
  **kernel** (for injection/HID) + the **Kali chroot** + the **NetHunter app**.
- In Magisk, grant root to the NetHunter app; open it → **Kali Chroot Manager**
  → install the chroot → `App` menu gives you Kali + NetHunter modules.

### 5. Use it
- Terminal: NetHunter Terminal → Kali → `apt update && apt install kali-linux-default`.
- Wi-Fi: plug the **Alfa via USB-OTG**, then in the Kali terminal it's the same
  as the Pi — `airmon-ng`, `airodump-ng`, this repo's `wifi/` scripts, etc.
  (Copy the repo over: `git clone` inside the chroot.)
- Extras full NetHunter adds: **HID/BadUSB** (phone acts as a USB keyboard),
  **DuckHunter**, **MANA** evil-AP, **MITM framework**, Wardriving.

---

## After rooting — practical caveats
- **Banking/payment/streaming apps** may refuse to run (Play Integrity detects
  root). Magisk's **Zygisk + DenyList** can hide root from specific apps, with
  mixed success.
- **OTA updates** often fail or unroot you; you re-patch `boot.img` after each.
- Keep the phone **offline/burner-style** for lab use; a rooted daily phone is a
  bigger attack surface.

## Portability summary
- **Software tool demos** → Rootless Termux/Kali (no risk). 
- **Real Wi-Fi capture/RF/HID** → Full NetHunter + **Alfa over OTG** → same
  workflow as this repo's `wifi/`, in your pocket.

Official docs: <https://www.kali.org/docs/nethunter/> (device lists, images,
per-model install guides — always prefer these for your exact phone).
