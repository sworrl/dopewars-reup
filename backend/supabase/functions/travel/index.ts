// travel — server-authoritative trip planning.
//
// Why an Edge Function and not an RPC: this reaches an EXTERNAL service (OSRM). Fetching the route
// server-side means the client can't forge distance or ETA (closes AC-M2). The player's ORIGIN is
// read from server-owned state, never taken from the client (closes part of AC-M1). The returned
// ETA is computed from the server-fetched distance; a follow-up `begin_travel` RPC persists the trip
// with arrival_at = world_now() + eta so arrival is decided by the server clock.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { cors } from "../_shared/cors.ts";

const OSRM = "https://router.project-osrm.org";

// mph per mode; -1 = trust OSRM's driving duration.
const MODE_SPEED: Record<string, number> = {
  walk: 3, bike: 12, motorcycle: 55, car: -1, bus: -1, rideshare: -1, plane: 500,
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const { dest_lat, dest_lon, mode = "car" } = await req.json();
    if (typeof dest_lat !== "number" || typeof dest_lon !== "number") {
      return json({ error: "bad_destination" }, 400);
    }

    // Authenticated client scoped to the caller's JWT — RLS applies, so we read only THEIR row.
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: req.headers.get("Authorization")! } } },
    );
    const { data: me, error } = await supabase
      .from("profiles").select("lat, lon, banned").single();
    if (error || !me) return json({ error: "no_profile" }, 401);
    if (me.banned) return json({ error: "account_suspended" }, 403);

    // Server-side route fetch — the client cannot shorten this.
    const url =
      `${OSRM}/route/v1/driving/${me.lon},${me.lat};${dest_lon},${dest_lat}` +
      `?overview=false&alternatives=3`;
    const r = await fetch(url, { headers: { "User-Agent": "DopeWarsReUp/0.2 (+server)" } });
    if (!r.ok) return json({ error: "routing_unavailable" }, 502);
    const doc = await r.json();
    if (doc.code !== "Ok" || !doc.routes?.length) return json({ error: "no_route" }, 404);

    const routes = doc.routes.map((rt: any) => {
      const miles = rt.distance / 1609.344;
      const speed = MODE_SPEED[mode] ?? -1;
      const eta_s = speed > 0 ? (miles / speed) * 3600 : rt.duration;
      return { miles: round(miles, 1), eta_s: Math.round(eta_s), distance_m: rt.distance };
    });

    return json({ ok: true, mode, routes });
  } catch (_e) {
    return json({ error: "bad_request" }, 400);
  }
});

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const round = (n: number, d: number) => Math.round(n * 10 ** d) / 10 ** d;
