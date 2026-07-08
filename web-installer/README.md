# Web installer (source)

Meshtastic-style browser installer: plug an Android phone into a desktop, open the page in
Chrome/Edge, click **Connect**, click **Install**. Built on WebUSB + WebADB
([ya-webadb](https://github.com/yume-chan/ya-webadb)).

The deployable output is **committed** at `site/install/` (so Cloudflare Pages needs no build
step). This folder is only the source; rebuild after editing:

```bash
cd web-installer
npm install
./build.sh          # bundles src/app.js + index.html -> site/install/
```

## How the APK reaches the browser

GitHub's release CDN sends no CORS headers, so the page can't fetch the APK from github.com.
`functions/download/[[path]].js` (a Cloudflare Pages Function at the repo root) proxies release
assets same-origin and provides stable URLs:

- `/download/latest.apk` — newest signed APK (resolved via the `latest.json` release asset)
- `/download/latest.json` — release manifest `{version, url, sha256, notes}`
- `/download/windows` — the Windows one-click installer zip
- `/download/sha256sums.txt` — checksums
- `/download/<tag>/<asset>` — pinned release assets (apk/zip/txt/json only)

The page verifies the APK's SHA-256 against `latest.json` before installing.

## Idiot-proofing map

- Android visitor → direct APK download path (no cable talk at all)
- iOS visitor → honest "Android only" dead end
- No WebUSB (Firefox/Safari) → pointed at Chrome/Edge or the direct APK
- Unauthorized device → "look at your phone, tap Allow" nudge after 2.5 s
- Interface claimed (adb/Android Studio/scrcpy running) → named culprits
- `INSTALL_FAILED_UPDATE_INCOMPATIBLE` → one-click "remove old copy & install fresh" (with a
  local-save-loss warning; online progress is server-side)
- Downgrade / wrong CPU / no storage → plain-English outcomes

## Testing locally

```bash
npx wrangler pages dev site --port 8788   # from the repo root; functions/ is auto-detected
# open http://localhost:8788/install/
```

Real-device install needs an actual phone over USB — test on hardware before announcing.
