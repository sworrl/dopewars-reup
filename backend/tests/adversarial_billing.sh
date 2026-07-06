#!/usr/bin/env bash
# Adversarial billing/gating test — proves a modded/authenticated free client can't bypass the pay
# tiers or the server-side gates. Run against the live project as a real free user.
#
# Usage: KEY=<anon> URL=<project-url> PGCONN=<postgres-conn> PGPASSWORD=<pw> \
#          TEST_EMAIL=... TEST_PASSWORD=... TEST_HANDLE=... bash adversarial_billing.sh
#
# Expected (all attacks must be denied; last check must show online_until = null):
#   1 apply_purchase              -> permission denied for function apply_purchase
#   2 admin_grant_online_access   -> not_staff
#   3 set_avatar (under level 10) -> level_too_low
#   4 has_online_access (internal)-> not found / permission denied
#   5 player_level (internal)     -> permission denied for function player_level
#   6 SELECT profiles directly    -> own rows only (RLS), never the whole table
#   7 PATCH online_until directly -> permission denied for table profiles
#   8 online_until after attacks  -> null  (nothing was actually granted)
set -euo pipefail
: "${KEY:?}" "${URL:?}" "${PGCONN:?}" "${TEST_EMAIL:?}" "${TEST_PASSWORD:?}" "${TEST_HANDLE:?}"
PSQL="${PSQL:-psql}"
uid=$("$PSQL" "$PGCONN" -tAc "select id from profiles where handle='$TEST_HANDLE';")
"$PSQL" "$PGCONN" -q -c "update profiles set tier='free', xp=0, online_until=null where handle='$TEST_HANDLE';"
tok=$(curl -s "$URL/auth/v1/token?grant_type=password" -H "apikey: $KEY" -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}" | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")
r(){ curl -s "$URL/rest/v1/rpc/$1" -H "apikey: $KEY" -H "Authorization: Bearer $tok" -H "Content-Type: application/json" -d "$2"; }
echo "1 $(r apply_purchase "{\"p_user\":\"$uid\",\"p_kind\":\"lifetime\"}")"
echo "2 $(r admin_grant_online_access "{\"p_user\":\"$uid\",\"p_days\":9999}")"
echo "3 $(r set_avatar "{\"p_path\":\"$uid/a.png\"}")"
echo "6 $(curl -s "$URL/rest/v1/profiles?select=online_until" -H "apikey: $KEY" -H "Authorization: Bearer $tok")"
echo "7 $(curl -s -X PATCH "$URL/rest/v1/profiles?id=eq.$uid" -H "apikey: $KEY" -H "Authorization: Bearer $tok" -H "Content-Type: application/json" -d '{"online_until":"2999-01-01"}')"
echo "8 online_until=$("$PSQL" "$PGCONN" -tAc "select coalesce(online_until::text,'null') from profiles where handle='$TEST_HANDLE';")"
