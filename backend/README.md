# Dope Wars: Re-Up — Backend (Supabase)

Server-authoritative backend for the multiplayer game. **The client is untrusted.** Clients read
only their own rows (RLS) and can write *nothing* directly — every mutation goes through a
`SECURITY DEFINER` function that validates against server-owned state and the **server clock**.
See the full posture in the Threat & Realism doc.

This directory is **firewalled from the game client** (the Godot project in `../dopewars-reup`): no
shared authoritative code path, so reverse-engineering the open client teaches nothing about how the
server validates.

## What's here

```
supabase/
  config.toml                  project + auth config
  migrations/
    0001_core.sql              server clock (world_now), account tiers, profiles, RLS, usage limits
    0002_economy.sql           drugs, inventory, ledger, server-priced buy()/sell()
    0003_world.sql             trap houses + settle_trap_house() on the SERVER clock, leaderboard_top()
    0004_seed.sql              tier config, drug catalog, admin tooling (promote beta testers)
  functions/
    travel/index.ts            OSRM route fetch server-side (client can't forge distance/ETA)
    _shared/cors.ts
```

## Deploy

1. Create a project at supabase.com. Grab the **project ref**, the **anon key**, and the **URL**.
2. Install the CLI (`brew install supabase/tap/supabase`) and:
   ```bash
   cd backend
   supabase link --project-ref <your-ref>
   supabase db push                 # applies all migrations in order
   supabase functions deploy travel
   ```
3. **Bootstrap your first admin** (service role bypasses RLS — run in the SQL editor):
   ```sql
   update profiles set tier = 'admin' where id = '<your-auth-user-uuid>';
   ```
   After that, admins promote others via `select admin_set_tier_by_handle('runner_ab12cd34', 'beta');`.

## Account levels (built in, ready for testing + the future)

Edit limits any time in `tier_config` — no code change needed.

| Tier | Daily cap | Ranked | For |
|---|---|---|---|
| `free` | 40 actions | yes | Default. The freemium gate caps **quantity of play**, never power — honors no-pay-to-win. |
| `beta` | 200 | yes | Invited testers. Relaxed cap, early features, feedback. |
| `supporter` | 200 | yes | Paid supporter. Cosmetic/support only, no gameplay edge. |
| `premium` | unlimited | yes | Paid. Removes the daily play cap (buys **access**, not power). |
| `dev` | unlimited | no | Internal testing. Unlimited, unranked, debug allowed. |
| `admin` | unlimited | no | Full control. |

**Onboard a beta tester:** they sign up (auto-gets a `free` profile) → an admin runs
`admin_set_tier_by_handle('<handle>', 'beta')`. That's the whole flow.

## How the client calls it

```js
const { data } = await supabase.rpc('buy',  { p_drug: 'weed', p_grams: 28 });
const { data } = await supabase.rpc('sell', { p_drug: 'weed', p_grams: 28 });
const { data } = await supabase.rpc('settle_trap_house', { p_house: 12 });
const board    = await supabase.rpc('leaderboard_top', { p_limit: 100 });
// external/routed logic goes through Edge Functions:
const trip     = await supabase.functions.invoke('travel', { body: { dest_lat, dest_lon, mode: 'car' }});
```
The client sends **intents only** — never a price, a cash figure, or a timestamp. The server supplies
all of those. Cash/inventory/XP are server-owned columns with no client write path.

## Anti-cheat wins already baked in

- **Clock-forward is dead (AC-T1):** `settle_trap_house` computes elapsed from `world_now() - last_tick`, clamped. The device clock is irrelevant.
- **Price forgery is dead (AC-E2):** `buy`/`sell` call `price_of()` server-side; the client never sends a price.
- **State edits are dead (AC-E1):** cash/inventory only change inside validated RPCs; clients have no write policy.
- **Route/ETA forgery is dead (AC-M2):** the `travel` function fetches OSRM server-side from the player's server-owned origin.
- **Leaderboards are reconstructable:** `leaderboard_top` derives net worth from server state + the ledger, never a submitted number.

## Next to build

- `begin_travel` RPC + `travels` table: persist the trip with `arrival_at = world_now() + eta` so arrival is server-timed; port battery drain + phone traceability into the arrival settle.
- **Buildings**: server-owned occupation of real OSM locations (see the buildings design memo) — trap houses/fronts become actual map coordinates a player holds.
- Realtime presence channels for the proximity system (observed-crime + perception rolls resolved server-side).
- Carry-capacity + vehicle/phone/employee state moved server-side; port `owned_vehicles`, `phone`, employees into validated RPCs.
- Vehicle & phone acquisition (order-online vs mapped-store) as server transactions.
