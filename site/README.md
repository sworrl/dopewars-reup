# Marketing site

Static landing page for Dope Wars: Re-Up. Self-contained: `index.html` plus `assets/`
(logo, banner, screenshots, fonts). No build step, no dependencies.

`install/` is the browser installer (WebUSB) — a **committed build output**; its source lives in
`../web-installer/` (rebuild there after edits). The `/download/*` endpoints are served by the
Cloudflare Pages Function at the repo root (`functions/download/[[path]].js`), which proxies
GitHub release assets same-origin (GitHub sends no CORS headers) and gives stable URLs like
`/download/latest.apk`.

## Deploy

Dev/temp: **dopewars.falcontechnix.com**. Production later on the real domain.

**Cloudflare Pages (recommended):**
1. Point Pages at this repo (root directory = repo root), build output directory `site/`, no
   build command. The `functions/` dir at the repo root is picked up automatically.
2. Add the custom domain `dopewars.falcontechnix.com` in the Pages project.

Or one-shot from the CLI: `npx wrangler pages deploy site --project-name dopewars-reup`
(run `npx wrangler login` first). Test locally with `npx wrangler pages dev site`.

**Or any static host:** upload the contents of `site/` as-is — but `/download/*` (and therefore
the web installer and the stable APK links) only work where Pages Functions run.

## Notes

- The hero uses a small WebGL shader (the red-route map motif). It falls back to a flat dark
  background where WebGL is unavailable, and respects `prefers-reduced-motion`.
- Update the screenshots in `assets/screens/` as the game changes; they are copies of `docs/screens/`.
- Swap `dopewars.falcontechnix.com` and the GitHub links for the real domain at production.
