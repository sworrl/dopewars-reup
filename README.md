# Dope Wars: Re-Up

A realistic drug-trade MMO on a real US map. The Wire, not GTA — realism educates, never glorifies.
Native Android (Godot 4.6), desktop/Steam to follow, backed by a server-authoritative Supabase layer.

- **Client** — `drugwars-reup/` (Godot project)
- **Backend** — `backend/` (Supabase: server-authoritative economy, account levels, RLS)

---

## Install it on your phone

### Flash from your browser (no tools — like Meshtastic's web flasher)

The quickest way to sideload a build: plug your Android phone into a computer and install straight
from Chrome. This uses the **WebUSB API + WebADB** (the [`ya-webadb`/Tango](https://github.com/yume-chan/ya-webadb)
library speaking the ADB wire protocol in the browser) — the same idea as
[Meshtastic's web flasher](https://flasher.meshtastic.org/), which uses Web Serial for ESP firmware.
There's nothing to install on your machine.

**Web installer: `https://install.dopewars-reup.com`** *(hosted alongside the site — see build notes)*

1. On the phone: **Settings → About → tap Build number 7×** to unlock Developer options, then enable
   **USB debugging**.
2. Plug the phone into a **desktop Chrome or Edge** (WebUSB is desktop-Chromium only; not Firefox/Safari,
   not mobile browsers).
3. Open the installer page, click **Connect**, and approve the WebUSB device prompt.
4. On the phone, tap **Allow** on the "Allow USB debugging?" dialog.
5. Click **Install Dope Wars** — the page pushes the current APK over ADB and installs it.

> The installer page is a small static web app (WebUSB + `@yume-chan/adb`) hosted on Cloudflare
> Pages next to the marketing site. It reads the latest signed APK from GitHub Releases and installs
> it — no server round-trip, all in the browser. WebUSB requires HTTPS, which the hosted page has.

### Manual sideload (works today)

```bash
adb install dwreup-final.apk
```
Grab the APK from **Releases**, or build it yourself (see `drugwars-reup/` build notes).

---

## Beta testing

Sign in through the app; you get a `free` account automatically. An admin promotes you to the
`beta` tier (relaxed limits + early features) — see `backend/README.md` for the account levels and
the one-line promotion command. Accounts, progress, and leaderboards live on the server.

## Status

Single-player is playable now (sideload a build). Multiplayer, leaderboards, and cross-device sync
come online with the Supabase backend. See the in-repo Threat Posture & Realism doc for the
server-authoritative design.

## Building from source

The client is a Godot 4.6.2 project in `drugwars-reup/`. The Android build uses the gradle template,
whose native libraries (`android/build/libs/`, over 100 MB) are not committed. Restore them once in
the Godot editor: Project menu, Install Android Build Template. Then build the APK; `tools/release.sh`
wraps the full signed-release build. The backend is in `backend/` (Supabase, see `backend/README.md`).

## Art is AI-generated (placeholder)

All 57 images in the game were generated with Google Imagen 4 Ultra (`imagen-4.0-ultra-generate-001`)
using the scripts in `drugwars-reup/tools/`. This covers the class portraits, drug icons, transport
and phone art, the app icon, and the menu and loading backgrounds. The 100 cosmetic items defined in
the backend have no art yet. The fonts are licensed typefaces (SIL OFL), not AI. `ASSETS.md` tracks
every asset and its status.

The art direction is documentary and anti-glorification: product shown as sealed police evidence,
worn gear, a desaturated rust-belt tone. The Wire, not GTA. The game does not depict or glamorize
drug use.

## Artists wanted

The creator is not an artist. The AI art exists so the game could be built and the vision tested; it
is a placeholder, not the goal. Real, human-made art should replace it.

If you draw, paint, model, or design and this project interests you, help is wanted for:

- Class portraits, drug and gear icons, phone and vehicle art
- The 100 cosmetic items (emblems, titles, nameplates, badges) that have no art yet
- The app icon, wordmark, and loading art

Keep the tone documentary and non-glamorizing, per the direction above. To contribute, open an issue
with samples or a pull request against the relevant asset, and update the asset's row in `ASSETS.md`.
Credited work replaces the AI version. (Contribution licensing is being finalized; see `LICENSING.md`.)
