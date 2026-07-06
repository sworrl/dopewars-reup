-- 0004_seed.sql — account-level config, drug catalog, and admin tooling for beta testers.

-- ============================================================================
-- ACCOUNT LEVELS. Tune limits here without touching code. daily_action_limit = -1 is unlimited.
-- ============================================================================
insert into tier_config (tier, label, daily_action_limit, can_play_online, early_features, ranked, is_staff, notes) values
  ('free',      'Free',       40,  true,  false, true,  false, 'Default. Freemium daily cap = access/quantity, never power (no pay-to-win).'),
  ('beta',      'Beta Tester',200, true,  true,  true,  false, 'Invited testers. Relaxed cap + early features + feedback.'),
  ('supporter', 'Supporter',  200, true,  false, true,  false, 'Paid supporter. Cosmetic/support perks only, no gameplay edge.'),
  ('premium',   'Premium',    -1,  true,  false, true,  false, 'Paid. Removes the daily play cap (buys access, not power).'),
  ('dev',       'Developer',  -1,  true,  true,  false, true,  'Internal testing. Unlimited, unranked, debug allowed.'),
  ('admin',     'Admin',      -1,  true,  true,  false, true,  'Full control.')
on conflict (tier) do update set
  label=excluded.label, daily_action_limit=excluded.daily_action_limit,
  can_play_online=excluded.can_play_online, early_features=excluded.early_features,
  ranked=excluded.ranked, is_staff=excluded.is_staff, notes=excluded.notes;

-- ============================================================================
-- Drug catalog (mirrors the client's data/drugs.json). Prices are in-game canon.
-- ============================================================================
insert into drugs (id, name, base_price_per_g, volatility, weight_per_unit_g, legal_severity) values
  ('weed',     'Weed',      12,   0.20, 1.0,    1),
  ('hash',     'Hash',      35,   0.25, 1.0,    1),
  ('cocaine',  'Cocaine',   100,  0.30, 1.0,    4),
  ('meth',     'Meth',      110,  0.40, 1.0,    5),
  ('heroin',   'Heroin',    150,  0.35, 1.0,    5),
  ('fentanyl', 'Fentanyl',  180,  0.50, 1.0,    6),
  ('oxy',      'Oxycodone', 80,   0.25, 0.5,    4),
  ('mdma',     'MDMA',      90,   0.30, 0.1,    3),
  ('lsd',      'LSD',       4500, 0.35, 0.0001, 3),
  ('shrooms',  'Mushrooms', 12,   0.30, 1.0,    2)
on conflict (id) do update set base_price_per_g=excluded.base_price_per_g, volatility=excluded.volatility;

-- Baseline demand = 1.0 everywhere unless a region profile says otherwise. Seed a couple of
-- illustrative regional skews (Rust Belt meth/fentanyl priority); expand from region profiles later.
insert into region_demand (city_id, drug_id, demand) values
  ('steubenville_oh', 'meth',     1.3),
  ('steubenville_oh', 'fentanyl', 1.25),
  ('steubenville_oh', 'weed',     0.9),
  ('pittsburgh_pa',   'cocaine',  1.15),
  ('cleveland_oh',    'heroin',   1.2)
on conflict (city_id, drug_id) do update set demand=excluded.demand;

-- ============================================================================
-- Admin tooling for testing + beta management.
-- Bootstrap your FIRST admin manually in the Supabase SQL editor (service role bypasses RLS):
--     update profiles set tier='admin' where id = '<your-auth-user-uuid>';
-- After that, admins can promote others with admin_set_tier(...).
-- ============================================================================
create or replace function is_staff(uid uuid) returns boolean
  language sql stable security definer set search_path = public as $$
  select coalesce((select tc.is_staff from profiles p join tier_config tc on tc.tier=p.tier where p.id=uid), false);
$$;

create or replace function admin_set_tier(p_user uuid, p_tier account_tier) returns jsonb
  language plpgsql security definer set search_path = public as $$
begin
  if not is_staff(auth.uid()) then raise exception 'not_authorized'; end if;
  update profiles set tier = p_tier where id = p_user;
  return jsonb_build_object('ok', true, 'user', p_user, 'tier', p_tier);
end $$;

-- Promote a beta tester by their handle (convenience for the invite flow).
create or replace function admin_set_tier_by_handle(p_handle text, p_tier account_tier) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare uid uuid;
begin
  if not is_staff(auth.uid()) then raise exception 'not_authorized'; end if;
  select id into uid from profiles where handle = p_handle;
  if uid is null then raise exception 'no_such_handle'; end if;
  update profiles set tier = p_tier where id = uid;
  return jsonb_build_object('ok', true, 'handle', p_handle, 'tier', p_tier);
end $$;

grant execute on function is_staff(uuid)                         to authenticated;
grant execute on function admin_set_tier(uuid, account_tier)      to authenticated;
grant execute on function admin_set_tier_by_handle(text, account_tier) to authenticated;
