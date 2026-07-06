# Drug Wars: Re-Up Edition

A free, open-source, realistic drug-trade simulation MMO for Android. Real US map. Real-time travel. Real consequences. Tone is *The Wire*, not *GTA*.

## Status

**Pre-alpha (v0.1 in progress).** Not playable yet. See `docs/` for design pillars and the vertical-slice ladder.

## Stack

- **Engine:** [Godot 4.6](https://godotengine.org/) + GDScript
- **Server:** [Supabase](https://supabase.com/) (Postgres + Realtime + Edge Functions in TypeScript/Deno) — to be wired in v0.2
- **Map:** OpenStreetMap raster tiles (no MapLibre Native — memory-safe stack policy excludes C/C++ in our code)
- **Distribution:** Google Play Store only (anti-cheat via Play Integrity)
- **Source:** GitHub, AGPLv3 — anyone can read, fork, audit, run their own server

## License

AGPLv3 — see [`LICENSE`](LICENSE). Source-available, copyleft, server-side share-alike.

## Project layout

```
drugwars-reup/
├── project.godot              # Godot 4 project config
├── scenes/                    # .tscn scene files
├── scripts/                   # GDScript modules
├── data/                      # Static game data
│   └── brands.json            #   Fictional-brand registry
├── assets/                    # Runtime assets
│   ├── sprites/               #   Procedurally-assembled character sprites + components
│   ├── tiles/                 #   OSM tile cache (gitignored)
│   └── backstories/           #   LLM-generated backstory pool (committed for reproducibility)
├── tools/                     # Dev scripts (Deno/TS, asset pipeline, etc.)
└── docs/                      # Design pillars + decision records
```

## Anti-glorification

This game uses real CDC overdose data, DEA threat assessments, and county crime stats. Player actions cause visible community harm in the simulated world. Drug *use* is depicted clinically, not as a reward. If a feature would romanticize use or trade, it gets cut. See [`docs/anti-glorification.md`](docs/anti-glorification.md).

## Funding

Free to play. No ads, ever. No pay-to-win, ever. Monetization is purely cosmetic IAP, a $5/season cosmetic battle pass, an optional cosmetic supporter sub, and paid DLC story/region expansions. Donations welcome off-store via GitHub Sponsors / Liberapay / OpenCollective.

## Reference

The original `druglord2.exe` (Drug Wars clone, 1998-ish abandonware) lives in `../reference/` for mechanic reference. None of its code is used; this is a clean reimplementation.
