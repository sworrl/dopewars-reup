-- 0006_modifiers.sql — per-user account modifiers: entitlements, DLC, feature flags, boosts.
-- A flexible bag of grants we can attribute to any user to unlock special features or DLC later,
-- without a schema change each time. Server-owned; the client can only read its own.
--
-- Key convention (free-form, namespaced):
--   dlc:pilot_pack        owns the aviation DLC
--   feature:early_map     early-access map features
--   cosmetic:gold_plate   a cosmetic unlock (no gameplay edge)
--   boost:xp_mult         value {"x":1.5} — an event/support boost
--   flag:beta_forms       gates an experimental UI
-- value is jsonb so a modifier can carry data (a multiplier, a count, a config).

create table user_modifiers (
  profile_id uuid references profiles(id) on delete cascade,
  key        text not null,
  value      jsonb not null default '{}',
  source     text,                          -- 'purchase' | 'grant' | 'promo' | 'beta' | 'event'
  granted_at timestamptz not null default now(),
  expires_at timestamptz,                    -- null = permanent
  primary key (profile_id, key)
);
alter table user_modifiers enable row level security;
create policy "read own modifiers" on user_modifiers for select using (profile_id = auth.uid());

-- Does the CALLER hold an active (non-expired) modifier?
create or replace function has_modifier(p_key text) returns boolean
  language sql stable security definer set search_path = public as $$
  select exists(
    select 1 from user_modifiers
    where profile_id = auth.uid() and key = p_key
      and (expires_at is null or expires_at > world_now()));
$$;

-- The value of an active modifier (or a default), for boosts/config.
create or replace function modifier_value(p_key text, p_default jsonb default '{}') returns jsonb
  language sql stable security definer set search_path = public as $$
  select coalesce((
    select value from user_modifiers
    where profile_id = auth.uid() and key = p_key
      and (expires_at is null or expires_at > world_now())), p_default);
$$;

-- Admin/staff attribute a modifier to a user (DLC grant, promo, event boost, feature access).
create or replace function admin_grant_modifier(p_user uuid, p_key text,
    p_value jsonb default '{}', p_source text default 'grant', p_expires timestamptz default null) returns jsonb
  language plpgsql security definer set search_path = public as $$
begin
  if not is_staff(auth.uid()) then raise exception 'not_authorized'; end if;
  insert into user_modifiers(profile_id, key, value, source, expires_at)
    values (p_user, p_key, p_value, p_source, p_expires)
    on conflict (profile_id, key) do update set value = excluded.value,
      source = excluded.source, expires_at = excluded.expires_at, granted_at = now();
  return jsonb_build_object('ok', true, 'user', p_user, 'key', p_key);
end $$;

create or replace function admin_revoke_modifier(p_user uuid, p_key text) returns jsonb
  language plpgsql security definer set search_path = public as $$
begin
  if not is_staff(auth.uid()) then raise exception 'not_authorized'; end if;
  delete from user_modifiers where profile_id = p_user and key = p_key;
  return jsonb_build_object('ok', true);
end $$;

-- A player fetches their own active modifiers (so the client can light up unlocked features).
create or replace function my_modifiers() returns table(key text, value jsonb, expires_at timestamptz)
  language sql stable security definer set search_path = public as $$
  select key, value, expires_at from user_modifiers
  where profile_id = auth.uid() and (expires_at is null or expires_at > world_now());
$$;

grant execute on function has_modifier(text)            to authenticated;
grant execute on function modifier_value(text, jsonb)    to authenticated;
grant execute on function my_modifiers()                 to authenticated;
grant execute on function admin_grant_modifier(uuid,text,jsonb,text,timestamptz) to authenticated;
grant execute on function admin_revoke_modifier(uuid,text) to authenticated;
