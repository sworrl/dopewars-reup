# Licensing (decision pending)

The final license for Dope Wars: Re-Up isn't chosen yet. The `LICENSE` file is a deliberate
"all rights reserved" placeholder so the public repo doesn't default to an unintended license.

**The goal:** public code + outside contributors + transparency, *but only the project owner
monetizes.* A true OSI open-source license can't restrict others' commercial use, so this is
inherently **source-available**, not classic FOSS. The two realistic paths:

- **Option A — Open client, closed server (recommended).** The game client is genuinely
  open-source (AGPL/GPL); the Supabase backend + official service stay private. In a multiplayer
  freemium game essentially all value lives in the server, so this gives full transparency and
  contribution while keeping monetization exclusive by construction.
- **Option B — FSL / BSL (source-available, time-delayed open).** Everything public and
  contributor-friendly, but commercial/competing use is prohibited for ~2 years, then each release
  auto-converts to Apache/MIT. The most literal match to "only I monetize," at the cost of not
  being OSI-"open source" during the window.

Monetization boundary (fixed): real money buys **playtime access only** (never advantage). Cosmetics
are earned/granted, never sold. Billing runs through the platforms (Steam / Play).

**Before accepting outside contributions**, finalize the license here and add a Contributor License
Agreement if Option A/dual-licensing is chosen (so the owner can relicense/run the paid service).
