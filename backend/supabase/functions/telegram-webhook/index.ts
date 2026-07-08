// Telegram webhook: turns the admin's taps/replies into beta approvals.
//
// Accepts either an inline-button press (✅/❌ under the request DM) or a plain text
// message from the admin: "1"/"yes"/"y"/"approve" approves, "2"/"no"/"n"/"deny" denies.
// Replying to a specific request message targets that request; a bare 1/2 targets the
// OLDEST pending request. On approval the email gets a GoTrue invite (creates the
// account + sends a magic-link email), so the tester can log straight in.
//
// Security: Telegram calls carry X-Telegram-Bot-Api-Secret-Token (set at setWebhook —
// see tools/setup_telegram_bot.sh); anything without it is dropped. Commands are only
// obeyed from TELEGRAM_ADMIN_CHAT_ID. "/id" is answered for anyone, once, to help you
// discover your chat id during setup.
//
// Deploy:  supabase functions deploy telegram-webhook --no-verify-jwt
// Secrets: TELEGRAM_BOT_TOKEN, TELEGRAM_ADMIN_CHAT_ID, TELEGRAM_WEBHOOK_SECRET
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supa = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);
const BOT = Deno.env.get("TELEGRAM_BOT_TOKEN")!;
const ADMIN = Deno.env.get("TELEGRAM_ADMIN_CHAT_ID") ?? "";
const SECRET = Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "";

const API = `https://api.telegram.org/bot${BOT}`;
const ok = () => new Response("ok"); // always 200 so Telegram doesn't retry-spam

async function tg(method: string, payload: Record<string, unknown>) {
  const res = await fetch(`${API}/${method}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload),
  });
  const j = await res.json().catch(() => null);
  if (!j?.ok) console.error(`${method} failed:`, JSON.stringify(j));
  return j;
}
const say = (text: string) => tg("sendMessage", { chat_id: ADMIN, text, parse_mode: "HTML" });
const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

type Signup = { id: string; email: string; handle: string | null; status: string; tg_message_id: number | null };

async function decide(row: Signup, approve: boolean): Promise<string> {
  // Flip pending -> decided atomically; a second tap/reply finds zero rows and reports it.
  const { data: updated } = await supa.from("beta_signups")
    .update({ status: approve ? "approved" : "denied", decided_at: new Date().toISOString() })
    .eq("id", row.id).eq("status", "pending").select("id");
  if (!updated?.length) return `Already handled: <b>${esc(row.email)}</b> is ${row.status}.`;

  let verdict: string;
  if (approve) {
    const { error } = await supa.auth.admin.inviteUserByEmail(row.email, {
      data: { handle: row.handle ?? undefined, beta: true },
    });
    if (error) {
      // Most common cause: the account already exists. The approval stands either way.
      console.error("invite failed:", error.message);
      verdict = `✅ Approved <b>${esc(row.email)}</b>, but the invite email failed: <i>${esc(error.message)}</i>. ` +
        `If they already have an account they can just log in; otherwise re-run the invite from the dashboard.`;
    } else {
      verdict = `✅ Approved <b>${esc(row.email)}</b> — invite email sent. They can log in as soon as they click it.`;
    }
  } else {
    verdict = `❌ Denied <b>${esc(row.email)}</b>. No email sent.`;
  }

  // Mark the original request DM so the chat history shows resolved state at a glance.
  if (row.tg_message_id) {
    await tg("editMessageReplyMarkup", { chat_id: ADMIN, message_id: row.tg_message_id, reply_markup: { inline_keyboard: [] } });
    await tg("sendMessage", {
      chat_id: ADMIN, text: verdict, parse_mode: "HTML",
      reply_parameters: { message_id: row.tg_message_id, allow_sending_without_reply: true },
    });
    return ""; // already messaged
  }
  return verdict;
}

const APPROVE_WORDS = new Set(["1", "yes", "y", "approve", "approved", "👍"]);
const DENY_WORDS = new Set(["2", "no", "n", "deny", "denied", "👎"]);

Deno.serve(async (req) => {
  if (SECRET && req.headers.get("x-telegram-bot-api-secret-token") !== SECRET) {
    return new Response("forbidden", { status: 403 });
  }
  let update: Record<string, any>;
  try { update = await req.json(); } catch { return ok(); }

  // ---- inline button press ----
  const cb = update.callback_query;
  if (cb) {
    await tg("answerCallbackQuery", { callback_query_id: cb.id });
    if (String(cb.message?.chat?.id) !== ADMIN) return ok();
    const m = /^(approve|deny):([0-9a-f-]{36})$/.exec(cb.data ?? "");
    if (!m) return ok();
    const { data: row } = await supa.from("beta_signups")
      .select("id,email,handle,status,tg_message_id").eq("id", m[2]).maybeSingle();
    if (!row) { await say("That request no longer exists."); return ok(); }
    const msg = await decide(row as Signup, m[1] === "approve");
    if (msg) await say(msg);
    return ok();
  }

  // ---- plain text ----
  const msg = update.message;
  if (!msg?.text) return ok();
  const chatId = String(msg.chat?.id ?? "");
  const text = String(msg.text).trim().toLowerCase();

  // Setup helper: anyone may ask for their chat id; nothing else works for strangers.
  if (text === "/id" || text === "/start") {
    await tg("sendMessage", { chat_id: chatId, text: `This chat's id is <code>${chatId}</code>.`, parse_mode: "HTML" });
    return ok();
  }
  if (chatId !== ADMIN) return ok();

  const approve = APPROVE_WORDS.has(text);
  const deny = DENY_WORDS.has(text);
  if (!approve && !deny) {
    if (text === "pending" || text === "/pending") {
      const { data: rows } = await supa.from("beta_signups")
        .select("email,created_at").eq("status", "pending").order("created_at").limit(10);
      await say(rows?.length
        ? "<b>Pending:</b>\n" + rows.map((r, i) => `${i + 1}. ${esc(r.email)}`).join("\n")
        : "No pending requests. 🎉");
    }
    return ok();
  }

  // Reply-to targets that request; a bare 1/2 targets the oldest pending one.
  let row: Signup | null = null;
  const replyId = msg.reply_to_message?.message_id;
  if (replyId) {
    const { data } = await supa.from("beta_signups")
      .select("id,email,handle,status,tg_message_id").eq("tg_message_id", replyId).maybeSingle();
    row = data as Signup | null;
    if (!row) { await say("That message isn't a beta request I know about."); return ok(); }
  } else {
    const { data } = await supa.from("beta_signups")
      .select("id,email,handle,status,tg_message_id").eq("status", "pending")
      .order("created_at").limit(1).maybeSingle();
    row = data as Signup | null;
    if (!row) { await say("Nothing pending to decide. 🎉"); return ok(); }
  }

  const verdict = await decide(row, approve);
  if (verdict) await say(verdict);
  return ok();
});
