// Stripe webhook → grant online access. The ONLY thing that turns money into entitlement.
//
// Flow: player buys on the website via a Stripe Payment Link (with ?client_reference_id=<profile-id>).
// Stripe calls this function; it verifies the Stripe signature, maps the purchased price to a duration
// kind, and calls apply_purchase() as service_role. A modded game client is irrelevant — it never
// touches this path and can't forge a Stripe-signed event or set its own online_until.
//
// Deploy:  supabase functions deploy stripe-webhook --no-verify-jwt
// Secrets: supabase secrets set STRIPE_SECRET_KEY=... STRIPE_WEBHOOK_SECRET=... \
//            STRIPE_PRICE_MONTHLY=price_... STRIPE_PRICE_YEARLY=price_... STRIPE_PRICE_LIFETIME=price_... \
//            STRIPE_PRICE_BETA_MONTHLY=price_... STRIPE_PRICE_BETA_YEARLY=price_...
// (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY are injected automatically.)

import Stripe from "https://esm.sh/stripe@16?target=deno";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, { apiVersion: "2024-06-20" });
const WEBHOOK_SECRET = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;
const supa = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// Stripe price id → entitlement duration. Beta variants map to their duration (the cheap price is
// grandfathered by Stripe for existing subscribers automatically).
const PRICE_KIND: Record<string, string> = {
  [Deno.env.get("STRIPE_PRICE_MONTHLY") ?? "_m"]: "monthly",
  [Deno.env.get("STRIPE_PRICE_YEARLY") ?? "_y"]: "yearly",
  [Deno.env.get("STRIPE_PRICE_LIFETIME") ?? "_l"]: "lifetime",
  [Deno.env.get("STRIPE_PRICE_BETA_MONTHLY") ?? "_bm"]: "monthly",
  [Deno.env.get("STRIPE_PRICE_BETA_YEARLY") ?? "_by"]: "yearly",
};

async function grant(userId: string, kind: string) {
  const { error } = await supa.rpc("apply_purchase", { p_user: userId, p_kind: kind });
  if (error) throw new Error(`apply_purchase: ${error.message}`);
  console.log(`granted ${kind} to ${userId}`);
}

Deno.serve(async (req) => {
  const sig = req.headers.get("stripe-signature");
  const body = await req.text();
  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(body, sig!, WEBHOOK_SECRET);
  } catch (e) {
    return new Response(`bad signature: ${(e as Error).message}`, { status: 400 });
  }

  try {
    if (event.type === "checkout.session.completed") {
      const s = event.data.object as Stripe.Checkout.Session;
      const userId = s.client_reference_id;
      if (!userId) return new Response("no client_reference_id", { status: 200 });
      const items = await stripe.checkout.sessions.listLineItems(s.id, { limit: 1 });
      const kind = PRICE_KIND[items.data[0]?.price?.id ?? ""];
      if (kind) {
        await grant(userId, kind);
        // Remember the Stripe customer so renewals (invoice.paid) can find this player.
        if (s.customer) {
          await supa.from("profiles").update({ stripe_customer_id: String(s.customer) }).eq("id", userId);
        }
      }
    } else if (event.type === "invoice.paid") {
      // Subscription renewal — no client_reference_id; look the player up by Stripe customer.
      const inv = event.data.object as Stripe.Invoice;
      const kind = PRICE_KIND[inv.lines.data[0]?.price?.id ?? ""];
      if (kind && inv.customer) {
        const { data } = await supa.from("profiles").select("id")
          .eq("stripe_customer_id", String(inv.customer)).maybeSingle();
        if (data?.id) await grant(data.id, kind);
      }
    }
  } catch (e) {
    console.error(e);
    return new Response("handler error", { status: 500 });
  }
  return new Response("ok", { status: 200 });
});
