-- 0017_packages.sql — welcome + care packages. A package is a server-defined bundle (cash/cred/xp/
-- cosmetics/inventory) that gets QUEUED for a player (on signup, by an admin, or by an event) and is
-- CLAIMED on next login. All grants + claims are server-authoritative — the client can't mint a
-- package or its contents.

create table if not exists package_defs (
  id          text primary key,
  name        text not null,
  kind        text not null default 'care',        -- welcome | care | supporter | award
  contents    jsonb not null default '{}',          -- {cash,cred,xp, cosmetics:[ids], inventory:{drug:g}}
  description text
);
create table if not exists pending_packages (
  id         bigint generated always as identity primary key,
  profile_id uuid references profiles(id) on delete cascade,
  package_id text references package_defs(id),
  granted_at timestamptz not null default now(),
  claimed_at timestamptz
);
create index if not exists pending_packages_unclaimed on pending_packages(profile_id) where claimed_at is null;
alter table package_defs      enable row level security;
alter table pending_packages  enable row level security;

insert into package_defs (id, name, kind, contents, description) values
  ('welcome',       'Welcome to the block', 'welcome',
     '{"cash": 1000, "cred": 250, "xp": 50, "cosmetics": ["emblem_the_re_up"]}',
     'A little to get you started — cash, CRED, and an emblem.'),
  ('welcome_beta',  'Beta Pioneer kit',     'welcome',
     '{"cash": 2500, "cred": 1000, "xp": 100, "cosmetics": ["badge_beta_pioneer", "emblem_the_re_up"]}',
     'Thanks for testing. Extra cash + CRED and the Beta Pioneer badge.'),
  ('care_restock',  'Restock drop',         'care',
     '{"cash": 500, "inventory": {"weed": 28}}', 'A resupply care package.'),
  ('care_cooldown', 'Cool-down kit',         'care',
     '{"cred": 200}', 'Lay low — a little CRED for the trouble.')
  on conflict (id) do update set name = excluded.name, kind = excluded.kind,
    contents = excluded.contents, description = excluded.description;

-- Queue a package for a player. Staff-only (admin tooling) / service (events + the signup trigger).
create or replace function grant_package(p_user uuid, p_package text) returns jsonb
  language plpgsql security definer set search_path = public as $$
begin
  if not is_staff(auth.uid()) then raise exception 'not_staff'; end if;
  if not exists (select 1 from package_defs where id = p_package) then raise exception 'no_such_package'; end if;
  insert into pending_packages(profile_id, package_id) values (p_user, p_package);
  return jsonb_build_object('ok', true, 'user', p_user, 'package', p_package);
end $$;

-- What's waiting for me to claim.
create or replace function my_pending_packages() returns table(id bigint, name text, description text, contents jsonb)
  language sql stable security definer set search_path = public as $$
  select pp.id, pd.name, pd.description, pd.contents
  from pending_packages pp join package_defs pd on pd.id = pp.package_id
  where pp.profile_id = auth.uid() and pp.claimed_at is null
  order by pp.granted_at;
$$;

-- Claim a package: apply its contents to MY account (server-authoritative), mark claimed.
create or replace function claim_package(p_id bigint) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare me profiles; c jsonb; drug text; g int; cos text;
begin
  me := require_player();
  select contents into c from pending_packages pp join package_defs pd on pd.id = pp.package_id
    where pp.id = p_id and pp.profile_id = me.id and pp.claimed_at is null;
  if c is null then raise exception 'no_such_package'; end if;

  update profiles set
      cash = cash + coalesce((c->>'cash')::bigint, 0),
      cred = cred + coalesce((c->>'cred')::bigint, 0),
      xp   = xp   + coalesce((c->>'xp')::bigint, 0)
    where id = me.id;
  for cos in select jsonb_array_elements_text(coalesce(c->'cosmetics', '[]'::jsonb)) loop
    insert into owned_cosmetics(profile_id, cosmetic_id) values (me.id, cos)
      on conflict do nothing;
  end loop;
  for drug, g in select key, value::int from jsonb_each_text(coalesce(c->'inventory', '{}'::jsonb)) loop
    insert into inventory(profile_id, drug_id, grams) values (me.id, drug, g)
      on conflict (profile_id, drug_id) do update set grams = inventory.grams + g;
  end loop;

  update pending_packages set claimed_at = now() where id = p_id;
  return jsonb_build_object('ok', true, 'claimed', p_id, 'contents', c);
end $$;

revoke execute on function grant_package(uuid, text)   from public, anon;
grant  execute on function grant_package(uuid, text)   to authenticated;   -- is_staff-gated inside
grant  execute on function my_pending_packages()       to authenticated;
grant  execute on function claim_package(bigint)       to authenticated;
