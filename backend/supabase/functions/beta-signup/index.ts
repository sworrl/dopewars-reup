// Public beta-signup endpoint. Site form posts {email, handle?, note?} here; we queue the
// request and DM the admin on Telegram with Approve/Deny buttons (replying 1/2 works too —
// that side lives in telegram-webhook).
//
// Deploy:  supabase functions deploy beta-signup --no-verify-jwt
// Secrets: supabase secrets set TELEGRAM_BOT_TOKEN=... TELEGRAM_ADMIN_CHAT_ID=...
// (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY are injected automatically.)
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { cors } from "../_shared/cors.ts";

const supa = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);
const BOT = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";
const ADMIN = Deno.env.get("TELEGRAM_ADMIN_CHAT_ID") ?? "";

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "content-type": "application/json" } });
const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

async function ipHash(req: Request): Promise<string> {
  const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(ip + BOT));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "bad json" }, 400); }

  // Honeypot: the site form has an invisible "website" field. Bots fill it; humans can't.
  if (String(body.website ?? "").length > 0) return json({ ok: true, status: "pending" });

  const email = String(body.email ?? "").trim().toLowerCase().slice(0, 254);
  const handle = String(body.handle ?? "").trim().slice(0, 32);
  const note = String(body.note ?? "").trim().slice(0, 280);
  if (!EMAIL_RE.test(email)) return json({ error: "That doesn't look like an email address." }, 400);

  // Rate limits: 3/hour per address hash, 30/hour globally (protects Telegram + the mailer).
  const hash = await ipHash(req);
  const hourAgo = new Date(Date.now() - 3600_000).toISOString();
  const { count: mine } = await supa.from("beta_signups")
    .select("*", { count: "exact", head: true }).eq("ip_hash", hash).gt("created_at", hourAgo);
  if ((mine ?? 0) >= 3) return json({ error: "Easy — you've asked a few times already. Try again in an hour." }, 429);
  const { count: global } = await supa.from("beta_signups")
    .select("*", { count: "exact", head: true }).gt("created_at", hourAgo);
  if ((global ?? 0) >= 30) return json({ error: "The beta queue is slammed right now. Try again in an hour." }, 429);

  // One request per email — repeat visits get an honest status instead of a dupe error.
  const { data: existing } = await supa.from("beta_signups")
    .select("status").eq("email", email).maybeSingle();
  if (existing) {
    const msg = existing.status === "approved"
      ? "You're already approved — check your email (and spam) for the invite."
      : existing.status === "pending"
        ? "You're already in the queue. Hang tight — you'll get an email when you're approved."
        : "This email's request was closed. Reach out on GitHub if you think that's wrong.";
    return json({ ok: true, status: existing.status, message: msg });
  }

  const { data: row, error } = await supa.from("beta_signups")
    .insert({ email, handle: handle || null, note: note || null, ip_hash: hash })
    .select("id").single();
  if (error) {
    console.error("insert failed:", error.message);
    return json({ error: "Something hiccuped — try again in a minute." }, 500);
  }

  // DM the admin. If Telegram is down/unconfigured the row still exists — nothing is lost.
  if (BOT && ADMIN) {
    const { count: pending } = await supa.from("beta_signups")
      .select("*", { count: "exact", head: true }).eq("status", "pending");
    const text = [
      "🚨 <b>Beta request</b>",
      `✉️ ${esc(email)}`,
      handle ? `🎮 ${esc(handle)}` : "",
      note ? `📝 ${esc(note)}` : "",
      "",
      `Tap a button, or reply <b>1</b>/<b>yes</b> to approve, <b>2</b>/<b>no</b> to deny. (${pending ?? 1} pending)`,
    ].filter(Boolean).join("\n");
    try {
      const tg = await fetch(`https://api.telegram.org/bot${BOT}/sendMessage`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          chat_id: ADMIN, text, parse_mode: "HTML",
          reply_markup: { inline_keyboard: [[
            { text: "✅ Approve", callback_data: `approve:${row.id}` },
            { text: "❌ Deny", callback_data: `deny:${row.id}` },
          ]] },
        }),
      });
      const tgj = await tg.json();
      if (tgj?.ok) {
        await supa.from("beta_signups").update({ tg_message_id: tgj.result.message_id }).eq("id", row.id);
      } else {
        console.error("telegram sendMessage failed:", JSON.stringify(tgj));
      }
    } catch (e) {
      console.error("telegram unreachable:", (e as Error).message);
    }
  } else {
    console.error("TELEGRAM_BOT_TOKEN / TELEGRAM_ADMIN_CHAT_ID not set — request queued silently");
  }

  return json({ ok: true, status: "pending", message: "Request received — you'll get an email when you're approved." });
});
