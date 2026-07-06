-- 0013_online_access.sql — pay-to-play ONLINE gating.
--
-- Offline single-player is FREE and never touches the server (a modded local client can't reach the
-- online world at all). ONLINE play is a paid entitlement, enforced SERVER-SIDE so the open-source,
-- moddable client can't bypass it: every action RPC funnels through require_player(), so gating that
-- one function gates all online play. Read-only RPCs (get_my_state, leaderboard_top, my_*) use
-- auth.uid() directly and stay OPEN — a free account can still sign in, see it isn't entitled, and be
-- prompted to buy in.
--
-- Entitlement = a non-free account tier (beta/supporter/premium/founder/dev/admin — comped or paid)
-- OR a future `online_until` (a purchased time-boxed pass / subscription). Money buys ACCESS/playtime,
-- never advantage — consistent with the no-pay-to-win pillar.

alter table profiles add column if not exists online_until timestamptz;   -- null = no purchased access

-- Pay-to-play: the free tier is now OFFLINE-ONLY. Every other tier keeps online (comped or paid).
-- can_play_online is the existing per-tier switch in tier_config.
update tier_config set can_play_online = false where tier = 'free';

-- Internal helper. Never client-callable; the definer functions below call it as owner. Entitlement =
-- the account's tier allows online (can_play_online) OR a purchased pass/sub is still valid.
create or replace function has_online_access(p profiles) returns boolean
  language sql stable set search_path = public as $$
  select coalesce((select tc.can_play_online from tier_config tc where tc.tier = p.tier), false)
      or (p.online_until is not null and p.online_until > world_now());
$$;

-- The gate: require_player() now also enforces online access. Preserves the original checks.
create or replace function require_player() returns profiles
  language plpgsql security definer set search_path = public as $$
declare p profiles;
begin
  select * into p from profiles where id = auth.uid();
  if p.id is null then raise exception 'no_profile';            end if;
  if p.banned    then raise exception 'account_suspended';      end if;
  if not has_online_access(p) then raise exception 'online_access_required'; end if;
  return p;
end $$;

-- Grant / extend online access (subscription-style: stacks on any remaining time). Staff-only for
-- manual grants + tests; the payment webhook (an Edge Function running as service_role) sets
-- online_until directly after validating the purchase with Steam / Play / Stripe.
create or replace function admin_grant_online_access(p_user uuid, p_days int) returns jsonb
  language plpgsql security definer set search_path = public as $$
begin
  if not is_staff(auth.uid()) then raise exception 'not_staff'; end if;
  update profiles
    set online_until = greatest(coalesce(online_until, world_now()), world_now())
                       + make_interval(days => p_days)
    where id = p_user;
  return jsonb_build_object('ok', true, 'user', p_user, 'days', p_days);
end $$;

-- Client-facing: "am I entitled to play online?" So a signed-in free account can be shown the
-- buy-in prompt and stay in offline mode instead of hammering gated action RPCs.
create or replace function my_online_access() returns boolean
  language sql stable security definer set search_path = public as $$
  select coalesce((select has_online_access(p.*) from profiles p where p.id = auth.uid()), false);
$$;

-- Lockdown hygiene (0008): internal helpers stay un-granted; expose only the client/staff RPCs.
revoke execute on function has_online_access(profiles) from public, anon, authenticated;
revoke execute on function admin_grant_online_access(uuid, int) from public, anon;
grant  execute on function admin_grant_online_access(uuid, int) to authenticated;   -- is_staff-gated inside
grant  execute on function my_online_access()                  to authenticated;
