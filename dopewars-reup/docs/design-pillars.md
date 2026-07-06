# Design Pillars

Single source of truth for the locked design decisions. Update by PR. Things not here aren't decided.

## Tone

- **The Wire / Cormac McCarthy, not GTA.** Realism + consequences. No glamorization. See [`anti-glorification.md`](anti-glorification.md).
- Fun comes from the puzzle of running an operation, not from depicting use.

## World

- **Real US lower-48 map.** OpenStreetMap raster tiles, US-bounded.
- **Test region (v0.1–v0.5):** Steubenville OH + 150-mile radius. Lower-48 expansion in v0.7.
- **Real-time literal travel.** Walking NYC→LA = 46 real days. No dev time-scale.
- **Travel modes** gated by ownership/class: walk, bicycle, motorcycle, car, public transport (Wolfline bus, OmniCoach, Boober, Splift, regional metros), plane (endgame).
- **Vehicles require gas, registration, tags, insurance, maintenance.** Bad tags → pull-over multiplier. Stolen → arrest risk.
- **Personal day** = local-TZ midnight rollover. Governs personal allowances only (action budget, loan tick, daily quests). Market is continuous global.
- **Geographic isolation**: players see only proximate players. Cross-country interaction is endgame via cartel networks.

## Economy

- **Continuous global market.** Per-city floating prices. Buy → price up, sell → price down. Random events. Slow mean-reversion.
- **Environment events** (DEA stings, hurricanes, festivals) prop up density when player count is low.

## Property

- **Live county-assessor valuations** drive purchase tier:
  - `> $40k` → "offer-they-can't-refuse" negotiation minigame, ~10× market.
  - `$15-40k` → easier minigame.
  - `< $15k` → squattable; ongoing detection rolls scaled by operation size + neighborhood watch.
- **Sanity checks** via OSM polygons + Microsoft Building Footprints + waterway/landcover layers (no meth lab on water, no drug house on a freeway, etc.).
- **Street View** fetched only on claim/buy/move-in (cost control); cached forever. Procedural building render fallback if no SV imagery.

## Information asymmetry (core mechanic)

Other players' inventories are private. Public information pipeline:

1. **Police bust reports** — deterministic. Handle, city, what was seized.
2. **In-game social media** — players post, can be true or lies. Follower graph.
3. **NPC rumors / grapevine** — noisy aggregate signals per city.
4. **Snitches** — paid NPC intel. Better signal, risk of double-cross.
5. **Within-network** — your cartel members you see fully.

## Mechanics

- **D&D 5e / BG3 dice** for all checks. `d20 + stat_mod + skill_prof + situational ± advantage/disadvantage` vs DC. Crits matter.
- **Stat array** (six): STR (combat/intimidation/carry), DEX (stealth/driving/sleight), CON (toughness/drug-tolerance/prison), INT (chemistry/business/investigation), WIS (street-smarts/threat-detection), CHA (negotiation/deception/leadership).
- **Bethesda-style chargen** with appearance sliders + procedural backstory generation from chosen stats.
- **Robbery is PvP minigames** (street mug, stickup, home invasion, carjack — more over time). Both perspectives interactive. Asymmetric. Defender pre-sets a "sleep mode" stance for offline auto-resolution.
- **Offline robbery alert**: push notification → 15-min real-time defense window → auto-resolve via sleep-mode stance.
- **Achievements** comprehensive; tag events at source from day one.

## Death / legacy

- Hard-to-kill PCs.
- **Evidence-based sentencing** — full simulation: evidence atoms, chain of custody, lawyers, plea bargaining (depth grows over the v0.4 → v1.0 ladder).
- **Wills + trusts** — players designate succession.
- **On death** → assume control of next-in-line. 3rd-line backup is choose-1-of-3 lower-level lieutenants. All 5 down = full run end + achievement.
- **Cartel members are full PCs** (own class/stats/level/inventory).

## Orgs (10+ at launch)

Cartel · Ma-and-pop · Cult · Biker gang · Street crew · Mafia family · Mexican cartel · Russian bratva · Crooked motorcycle club · Prison gang · (more TBD).

Each: unique attributes, unit composition, gameplay shifts. Start new OR join existing (player-invite OR NPC-led with rise-through-ranks via tasks → takeover via anointed will / political coup / raw kill).

## Identity / anti-alt

- 5 system-generated handle picks at start; rename gated by reputation threshold ("would NPCs/players actually care").
- **Reputation + intimidation** are first-class stats with real game effects.
- Anti-alt: Google Play Integrity API + device fingerprint + email/creds + single-device-login enforcement.

## Stack

- **Engine:** Godot 4.6 + GDScript. Rust via godot-rust GDExtension only if perf-critical native is needed. **No C/C++ in our code.**
- **Server:** Supabase — Postgres + Realtime + Edge Functions (TypeScript/Deno). Server-authoritative writes only (never client-direct DB writes).
- **Map:** OSM raster tiles in GDScript (no MapLibre Native — C++ banned by memory-safety rule).
- **Push:** UnifiedPush + ntfy.sh primary. FCM optional.
- **License:** AGPLv3.
- **Distribution:** Google Play Store only.

## Monetization

- Cosmetic IAP store ($1–$15 SKUs).
- "Heat Pass" seasonal cosmetic battle pass ($5/season, meaningful free track).
- Supporter sub ($5/mo or $50/yr) — purely cosmetic perks.
- DLC story/region expansions ($5–$10) — Hawaii 5-0, Miami 1985, Cartel Wars: Tijuana, etc.
- Off-store donations (GitHub Sponsors, Liberapay, OpenCollective, Ko-fi).
- **No ads, ever. No P2W, ever.**

## Vertical slice ladder

| Version | Scope |
|---|---|
| **v0.1** | Godot+Android stack works. OSM US map. Walk between 2 cities (Steubenville ↔ Pittsburgh ~40mi). Buy/sell 1 drug. Solo. Local push on arrival. *Verifies the stack.* |
| **v0.2** | Supabase auth + persistence. Full drug catalog. Continuous global market. Daily action budget. Jail = timer. Backstory generation script (Deno + Claude API, batch 20). |
| **v0.3** | Multiplayer presence (proximity-based). PvP robbery minigames. Procedural sprite component library. |
| **v0.4** | Pick-org-at-start (3 types: cartel, ma-and-pop, biker). Evidence-based sentencing v1 (evidence atoms + accumulated cop-knowledge). Achievements scaffolding wired into the event bus. |
| **v0.5** | Wills + succession + permadeath legacy chain. |
| **v0.6** | Information warfare: in-game social media, NPC rumors, snitches, bust reports feed. |
| **v0.7** | All 10+ org types. NPC-led orgs. Rise-through-ranks. Lower-48 map expansion. |
| **v0.8** | Cartels endgame: cross-country distribution networks, multi-character coordination. |
| **v0.9** | Lawyers, plea bargaining, evidence sub-game depth. Polish. |
| **v1.0** | Beta. |
