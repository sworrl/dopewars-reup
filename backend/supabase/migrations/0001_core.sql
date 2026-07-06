-- 0001_core.sql — server clock, account levels, profiles, RLS foundation.
--
-- THE SPINE: the client is untrusted. Clients get SELECT on their own rows only; they get NO
-- direct INSERT/UPDATE/DELETE on any game-state table. Every mutation goes through a
-- SECURITY DEFINER function that validates against server-owned state and the server clock.

create extension if not exists pgcrypto;

-- ============================================================================
-- Server clock — the single source of time truth. Every time-based calculation
-- (accrual, battery, cooldowns, price windows) MUST read world_now(), never a
-- client-supplied timestamp. now() is transaction-start time on the DB server.
-- ============================================================================
create or replace function world_now() returns timestamptz
  language sql stable as $$ select now() $$;

-- ============================================================================
-- Account levels. Many tiers for testing today + monetization tomorrow.
--   free      – default; freemium daily cap (access, never power → honors no-pay-to-win)
--   beta      – invited testers; relaxed caps + early features + feedback flag
--   supporter – paid supporter; cosmetic/support perks, NO gameplay edge
--   premium   – paid; removes the daily play cap (buys ACCESS/quantity, not power)
--   dev       – internal; unlimited, excluded from leaderboards, debug allowed
--   admin     – full control
-- ============================================================================
create type account_tier as enum ('free','beta','supporter','premium','dev','admin');

create table tier_config (
  tier               account_tier primary key,
  label              text    not null,
  daily_action_limit int     not null,          -- -1 = unlimited
  can_play_online    boolean not null default true,
  early_features     boolean not null default false,
  ranked             boolean not null default true,   -- counts on public leaderboards
  is_staff           boolean not null default false,
  notes              text
);

-- ============================================================================
-- Profiles: one per auth user. Holds game identity AND the server-owned economy.
-- cash / xp / inventory are SERVER-OWNED — never writable by the client.
-- ============================================================================
create table profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  handle          text unique,
  tier            account_tier not null default 'free',
  class_id        text,
  stats           jsonb  not null default '{"STR":10,"DEX":10,"CON":10,"INT":10,"WIS":10,"CHA":10}',
  xp              int    not null default 0,
  cash            bigint not null default 2000,           -- SERVER-OWNED
  lat             double precision not null default 40.3698,
  lon             double precision not null default -80.6339,
  current_city_id text   not null default 'steubenville_oh',
  phone           jsonb  not null default '{}',
  owned_vehicles  jsonb  not null default '{}',
  banned          boolean not null default false,
  is_online_account boolean not null default true,        -- online accounts are server-born
  created_at      timestamptz not null default now(),
  last_active     timestamptz not null default now()
);

-- Auto-create a profile when an auth user signs up.
create or replace function handle_new_user() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, handle)
  values (new.id, 'runner_' || substr(replace(new.id::text,'-',''),1,8));
  return new;
end $$;
create trigger on_auth_user_created
  after insert on auth.users for each row execute function handle_new_user();

-- ============================================================================
-- Shared guards used by every RPC.
-- ============================================================================
create or replace function require_player() returns profiles
  language plpgsql security definer set search_path = public as $$
declare p profiles;
begin
  select * into p from profiles where id = auth.uid();
  if p.id is null then raise exception 'no_profile';        end if;
  if p.banned    then raise exception 'account_suspended';  end if;
  return p;
end $$;

-- Freemium / rate lever. Returns true and increments if under the tier's daily cap.
create table usage_daily (
  profile_id uuid references profiles(id) on delete cascade,
  day        date not null,
  actions    int  not null default 0,
  primary key (profile_id, day)
);

create or replace function consume_action() returns boolean
  language plpgsql security definer set search_path = public as $$
declare lim int; used int; t account_tier;
begin
  select tier into t from profiles where id = auth.uid();
  select daily_action_limit into lim from tier_config where tier = t;
  if lim is null or lim < 0 then return true; end if;      -- unlimited
  insert into usage_daily(profile_id, day, actions)
    values (auth.uid(), (world_now())::date, 1)
    on conflict (profile_id, day) do update set actions = usage_daily.actions + 1
    returning actions into used;
  return used <= lim;
end $$;

-- ============================================================================
-- RLS: read-your-own, write-nothing-directly.
-- ============================================================================
alter table profiles    enable row level security;
alter table usage_daily enable row level security;
alter table tier_config enable row level security;

create policy "read own profile"  on profiles    for select using (id = auth.uid());
create policy "read own usage"     on usage_daily for select using (profile_id = auth.uid());
create policy "tier_config public" on tier_config for select using (true);
-- No INSERT/UPDATE/DELETE policies on purpose: clients cannot write. RPCs (SECURITY DEFINER,
-- owned by postgres) bypass RLS and are the ONLY mutation path.

grant execute on function world_now()      to authenticated, anon;
grant execute on function require_player()  to authenticated;
grant execute on function consume_action()  to authenticated;
