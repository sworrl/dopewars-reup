// PayPal webhook → grant online access. Mirror of the Stripe path (same apply_purchase grant), using
// PayPal Subscriptions (monthly/yearly) + one-time Orders (lifetime). Adapted from the proven
// WanderMage billing_paypal pattern: fail-closed signature verification, custom_id = our profile id.
//
// PayPal Sandbox needs NO business verification, so this works for testing today; flip PAYPAL_ENV=live
// once the PayPal Business account is ready.
//
// Deploy:  supabase functions deploy paypal-webhook --no-verify-jwt
// Secrets: supabase secrets set PAYPAL_ENV=sandbox PAYPAL_CLIENT_ID=... PAYPAL_SECRET=... \
//            PAYPAL_WEBHOOK_ID=... PAYPAL_PLAN_MONTHLY=P-... PAYPAL_PLAN_YEARLY=P-... \
//            PAYPAL_PLAN_BETA_MONTHLY=P-... PAYPAL_PLAN_BETA_YEARLY=P-...

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ENV = (Deno.env.get("PAYPAL_ENV") ?? "sandbox").toLowerCase();
const API = ENV === "live" ? "https://api-m.paypal.com" : "https://api-m.sandbox.paypal.com";
const CLIENT_ID = Deno.env.get("PAYPAL_CLIENT_ID") ?? "";
const SECRET = Deno.env.get("PAYPAL_SECRET") ?? "";
const WEBHOOK_ID = Deno.env.get("PAYPAL_WEBHOOK_ID") ?? "";
const supa = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

// PayPal subscription plan id → entitlement kind. Beta plans map to their duration.
const PLAN_KIND: Record<string, string> = {
  [Deno.env.get("PAYPAL_PLAN_MONTHLY") ?? "_m"]: "monthly",
  [Deno.env.get("PAYPAL_PLAN_YEARLY") ?? "_y"]: "yearly",
  [Deno.env.get("PAYPAL_PLAN_BETA_MONTHLY") ?? "_bm"]: "monthly",
  [Deno.env.get("PAYPAL_PLAN_BETA_YEARLY") ?? "_by"]: "yearly",
};

async function token(): Promise<string> {
  const r = await fetch(`${API}/v1/oauth2/token`, {
    method: "POST",
    headers: {
      "Authorization": "Basic " + btoa(`${CLIENT_ID}:${SECRET}`),
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
  });
  return (await r.json()).access_token;
}

// Fail closed: an unverified callback is never trusted.
async function verified(h: Headers, body: unknown): Promise<boolean> {
  if (!CLIENT_ID || !SECRET || !WEBHOOK_ID) return false;
  try {
    const t = await token();
    const r = await fetch(`${API}/v1/notifications/verify-webhook-signature`, {
      method: "POST",
      headers: { "Authorization": `Bearer ${t}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        auth_algo: h.get("paypal-auth-algo"),
        cert_url: h.get("paypal-cert-url"),
        transmission_id: h.get("paypal-transmission-id"),
        transmission_sig: h.get("paypal-transmission-sig"),
        transmission_time: h.get("paypal-transmission-time"),
        webhook_id: WEBHOOK_ID,
        webhook_event: body,
      }),
    });
    return (await r.json()).verification_status === "SUCCESS";
  } catch (e) {
    console.error("verify error", e);
    return false;
  }
}

// Renewal payments (PAYMENT.SALE.COMPLETED) carry the subscription id but no plan — look it up.
async function planForSubscription(subId: string): Promise<string> {
  try {
    const t = await token();
    const r = await fetch(`${API}/v1/billing/subscriptions/${subId}`, {
      headers: { "Authorization": `Bearer ${t}` },
    });
    const s = await r.json();
    return s.plan_id ?? "";
  } catch { return ""; }
}

async function grant(userId: string, kind: string) {
  const { error } = await supa.rpc("apply_purchase", { p_user: userId, p_kind: kind });
  if (error) throw new Error(error.message);
  console.log(`granted ${kind} to ${userId}`);
}

Deno.serve(async (req) => {
  const body = await req.json();
  if (!(await verified(req.headers, body))) return new Response("bad signature", { status: 400 });

  const type = body.event_type as string;
  const res = body.resource ?? {};
  const userId = res.custom_id ?? res.custom ?? res.subscriber?.custom_id;
  try {
    if (type === "BILLING.SUBSCRIPTION.ACTIVATED") {
      const kind = PLAN_KIND[res.plan_id ?? ""];
      if (userId && kind) await grant(userId, kind);
    } else if (type === "PAYMENT.SALE.COMPLETED") {
      // subscription renewal — resolve the plan from the subscription id
      const kind = PLAN_KIND[await planForSubscription(res.billing_agreement_id ?? "")];
      if (userId && kind) await grant(userId, kind);
    } else if (type === "PAYMENT.CAPTURE.COMPLETED" || type === "CHECKOUT.ORDER.APPROVED") {
      // one-time order = lifetime
      if (userId) await grant(userId, "lifetime");
    }
  } catch (e) {
    console.error(e);
    return new Response("handler error", { status: 500 });
  }
  return new Response("ok", { status: 200 });
});
