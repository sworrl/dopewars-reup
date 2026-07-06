-- 0014_freemium_online.sql — freemium online model (revises 0013's hard offline-only free tier).
--
-- Free tier PLAYS ONLINE, but CAPPED (a server-counted daily action limit). Paying (a higher tier, or
-- an active online_until pass/sub) raises/removes the cap. Free needs no email/PII — free accounts are
-- ANONYMOUS (GoTrue anonymous sign-in); email + billing PII are captured only at purchase, by linking
-- an email to the anonymous user.
--
-- EVERY gate is server-side so a modded open-source client can't bypass a pay tier:
--   * the daily cap is counted in consume_action() against usage_daily, on the SERVER clock (world_now)
--   * the pass/sub timer (online_until) lives in profiles, settable ONLY by admin / the billing webhook
--   * both run inside SECURITY DEFINER functions; the client can't forge the count or the entitlement

-- Free can play online again — the CAP is the paywall now, not an on/off switch.
update tier_config set can_play_online = true where tier = 'free';

-- consume_action(): an active paid pass/sub grants unlimited actions regardless of base tier, so a
-- subscription works even on a free (anonymous) account. Otherwise the per-tier daily cap applies.
create or replace function consume_action() returns boolean
  language plpgsql security definer set search_path = public as $$
declare lim int; used int; me profiles;
begin
  select * into me from profiles where id = auth.uid();
  if me.id is null then return false; end if;
  -- Server-timed paid access = unlimited. online_until is only ever set by admin / billing webhook.
  if me.online_until is not null and me.online_until > world_now() then
    return true;
  end if;
  select daily_action_limit into lim from tier_config where tier = me.tier;
  if lim is null or lim < 0 then return true; end if;         -- unlimited-tier
  insert into usage_daily(profile_id, day, actions)
    values (auth.uid(), (world_now())::date, 1)
    on conflict (profile_id, day) do update set actions = usage_daily.actions + 1
    returning actions into used;
  return used <= lim;                                          -- server-counted daily cap
end $$;

-- Client-facing entitlement summary: whether they're capped and how much play is left today. Lets the
-- app show "X free actions left / upgrade for unlimited" without trusting the client to compute it.
create or replace function my_play_status() returns jsonb
  language plpgsql security definer set search_path = public as $$
declare me profiles; lim int; used int; unlimited boolean;
begin
  select * into me from profiles where id = auth.uid();
  if me.id is null then return jsonb_build_object('ok', false); end if;
  unlimited := (me.online_until is not null and me.online_until > world_now());
  select daily_action_limit into lim from tier_config where tier = me.tier;
  if lim is null or lim < 0 then unlimited := true; end if;
  select coalesce(actions, 0) into used from usage_daily
    where profile_id = me.id and day = (world_now())::date;
  return jsonb_build_object(
    'ok', true,
    'tier', me.tier,
    'unlimited', unlimited,
    'daily_cap', case when unlimited then null else lim end,
    'used_today', coalesce(used, 0),
    'remaining', case when unlimited then null else greatest(0, lim - coalesce(used, 0)) end,
    'online_until', me.online_until);
end $$;

revoke execute on function my_play_status() from public, anon;
grant  execute on function my_play_status() to authenticated;
