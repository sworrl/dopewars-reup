#!/usr/bin/env bash
# One-shot setup for the beta-approval Telegram bot.
#
#   TELEGRAM_BOT_TOKEN=123456:ABC... backend/tools/setup_telegram_bot.sh
#
# Prereqs (once):
#   1. In Telegram, talk to @BotFather -> /newbot -> copy the token.
#   2. supabase login   (so `supabase secrets set` / `functions deploy` work)
#
# What it does:
#   - generates a webhook secret and points Telegram at the telegram-webhook edge function
#   - helps you discover your admin chat id (message the bot /id after webhook is live)
#   - prints/sets the supabase secrets and deploys both functions
set -euo pipefail

TOKEN="${TELEGRAM_BOT_TOKEN:?set TELEGRAM_BOT_TOKEN (from @BotFather)}"
REF="${PROJECT_REF:-wnrtrhhdxazqzdcpspsg}"
URL="https://$REF.supabase.co/functions/v1/telegram-webhook"
SECRET="${TELEGRAM_WEBHOOK_SECRET:-$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 40)}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

echo ">> 1/4 sanity: who is this bot?"
curl -fsS "https://api.telegram.org/bot$TOKEN/getMe" | python3 -c \
  "import json,sys; r=json.load(sys.stdin)['result']; print('   @'+r['username'])"

echo ">> 2/4 supabase secrets + deploy (needs 'supabase login' done once)"
( cd "$HERE" \
  && npx supabase secrets set --project-ref "$REF" \
       TELEGRAM_BOT_TOKEN="$TOKEN" TELEGRAM_WEBHOOK_SECRET="$SECRET" \
  && npx supabase functions deploy telegram-webhook --project-ref "$REF" --no-verify-jwt \
  && npx supabase functions deploy beta-signup     --project-ref "$REF" --no-verify-jwt )

echo ">> 3/4 point Telegram at the webhook"
curl -fsS "https://api.telegram.org/bot$TOKEN/setWebhook" \
  -d "url=$URL" -d "secret_token=$SECRET" \
  -d 'allowed_updates=["message","callback_query"]' >/dev/null
echo "   webhook -> $URL"

echo ">> 4/4 admin chat id"
if [ -n "${TELEGRAM_ADMIN_CHAT_ID:-}" ]; then
  ( cd "$HERE" && npx supabase secrets set --project-ref "$REF" TELEGRAM_ADMIN_CHAT_ID="$TELEGRAM_ADMIN_CHAT_ID" )
  echo "   admin chat id set to $TELEGRAM_ADMIN_CHAT_ID"
else
  cat <<EOF
   Now open Telegram, find your bot, and send it:   /id
   It replies with your chat id. Then finish with:
     cd backend && npx supabase secrets set --project-ref $REF TELEGRAM_ADMIN_CHAT_ID=<that id>
EOF
fi

echo
echo "Done. Test: submit the site's beta form -> the bot DMs you -> reply 1 (or tap ✅)."
echo "The tester gets a Supabase invite email and can log straight in."
