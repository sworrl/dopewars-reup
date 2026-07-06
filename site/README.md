# Marketing site

Static landing page for Dope Wars: Re-Up. Self-contained: one `index.html` plus `assets/`
(logo, banner, screenshots, fonts). No build step, no dependencies.

## Deploy

Dev/temp: **dopewars.falcontechnix.com**. Production later on the real domain.

**Cloudflare Pages (recommended):**
1. Point Pages at this repo, set the build output directory to `site/`, no build command.
2. Add the custom domain `dopewars.falcontechnix.com` in the Pages project.

**Or any static host:** upload the contents of `site/` as-is.

## Notes

- The hero uses a small WebGL shader (the red-route map motif). It falls back to a flat dark
  background where WebGL is unavailable, and respects `prefers-reduced-motion`.
- Update the screenshots in `assets/screens/` as the game changes; they are copies of `docs/screens/`.
- Swap `dopewars.falcontechnix.com` and the GitHub links for the real domain at production.
