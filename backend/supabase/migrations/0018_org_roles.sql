-- 0018_org_roles.sql — org role SLOTS filled by an NPC or a real player, INTERCHANGEABLY.
--
-- The key idea: the empire simulation never asks "is this an NPC or a player?" It reads slot_stats(),
-- which returns the same shape (push/skim/heat/threat/loyalty) whether the slot is held by server AI
-- or a real person. So you build your org mostly with NPCs; at scale, real players fill the same
-- slots via claim_slot(); when a player leaves, an NPC backfills via vacate_slot() so the org never
-- breaks. Same code path at 1k users or 1M. Server-authoritative.

create table if not exists role_defs (
  id text primary key, name text not null,
  base_push numeric not null default 1, base_skim numeric not null default 0.1,
  base_heat numeric not null default 1, base_threat int not null default 3, description text
);
insert into role_defs (id,name,base_push,base_skim,base_heat,base_threat,description) values
  ('runner',     'Runner',     2, 0.15,  1, 2, 'Moves product on the street.'),
  ('muscle',     'Muscle',     0, 0.05,  2, 6, 'Protection and enforcement.'),
  ('lookout',    'Lookout',    0, 0.05, -1, 2, 'Watches for cops/rivals; lowers heat.'),
  ('cook',       'Cook',       0, 0.10,  2, 3, 'Produces product.'),
  ('lieutenant', 'Lieutenant', 3, 0.25,  1, 5, 'Runs a cell; higher take.'),
  ('driver',     'Driver',     1, 0.10,  1, 3, 'Transport and getaway.')
  on conflict (id) do nothing;

create table if not exists crew_slots (
  id         bigint generated always as identity primary key,
  crew_id    bigint references crews(id) on delete cascade,
  role_id    text references role_defs(id),
  fill_type  text not null default 'npc',                    -- npc | player
  profile_id uuid references profiles(id) on delete set null, -- when fill_type = player
  npc_name   text, npc_seed int,                              -- when fill_type = npc (deterministic)
  loyalty    numeric not null default 0.7,
  filled_at  timestamptz not null default now()
);
alter table role_defs  enable row level security;
alter table crew_slots enable row level security;

create or replace function _npc_name() returns text language sql volatile as $$
  select (array['Dee','Marlo','Bodie','Snoop','Chris','Wee-Bey','Poot','Cutty','Slim','Bubbles',
                'Prop Joe','Vondas','Sydnor','Herc','Carv','Randy'])[1 + floor(random()*16)::int]
      || ' ' || substr(md5(random()::text), 1, 4);
$$;

-- THE ROLE INTERFACE: effective stats for a slot — identical shape for NPC or real player. The sim
-- reads only this. Player competence scales with level; NPC competence is deterministic from a seed.
create or replace function slot_stats(p_slot bigint) returns jsonb
  language plpgsql stable security definer set search_path = public as $$
declare s crew_slots; rd role_defs; mult numeric; lvl int;
begin
  select * into s from crew_slots where id = p_slot;
  if s.id is null then return '{}'::jsonb; end if;
  select * into rd from role_defs where id = s.role_id;
  if s.fill_type = 'player' then
    select player_level(xp) into lvl from profiles where id = s.profile_id;
    mult := 1.0 + 0.05 * coalesce(lvl, 0);
  else
    mult := 0.6 + (abs(coalesce(s.npc_seed, 0)) % 61) / 100.0;   -- 0.60 .. 1.20
  end if;
  return jsonb_build_object(
    'slot', s.id, 'role', rd.id, 'fill', s.fill_type,
    'name', coalesce(s.npc_name, (select handle from profiles where id = s.profile_id), 'unfilled'),
    'push', round(rd.base_push * mult, 2), 'skim', rd.base_skim, 'heat', rd.base_heat,
    'threat', round(rd.base_threat * mult), 'loyalty', s.loyalty);
end $$;

-- Add a slot to your crew. v1 fills with an NPC; the player-matchmaking pool plugs in right here at
-- scale (prefer an available real player, else NPC).
create or replace function add_slot(p_crew bigint, p_role text) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare me profiles; sid bigint;
begin
  me := require_player();
  if not exists (select 1 from crew_members where crew_id = p_crew and profile_id = me.id and role in ('leader','officer'))
    then raise exception 'not_crew_officer'; end if;
  if not exists (select 1 from role_defs where id = p_role) then raise exception 'no_such_role'; end if;
  insert into crew_slots(crew_id, role_id, fill_type, npc_name, npc_seed)
    values (p_crew, p_role, 'npc', _npc_name(), (random()*100000)::int) returning id into sid;
  return jsonb_build_object('ok', true, 'slot', sid, 'stats', slot_stats(sid));
end $$;

-- A real player takes over a slot — seamless NPC → player swap (same slot, sim unaffected).
create or replace function claim_slot(p_slot bigint) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare me profiles;
begin
  me := require_player();
  update crew_slots set fill_type = 'player', profile_id = me.id, npc_name = null, filled_at = now()
    where id = p_slot;
  return jsonb_build_object('ok', true, 'stats', slot_stats(p_slot));
end $$;

-- Player leaves → an NPC backfills so the org never breaks.
create or replace function vacate_slot(p_slot bigint) returns jsonb
  language plpgsql security definer set search_path = public as $$
begin
  update crew_slots set fill_type = 'npc', profile_id = null,
      npc_name = _npc_name(), npc_seed = (random()*100000)::int, filled_at = now()
    where id = p_slot and profile_id = auth.uid();
  return jsonb_build_object('ok', true, 'stats', slot_stats(p_slot));
end $$;

create or replace function crew_roster_slots(p_crew bigint) returns table(stats jsonb)
  language sql stable security definer set search_path = public as $$
  select slot_stats(id) from crew_slots where crew_id = p_crew order by filled_at;
$$;

revoke execute on function _npc_name()          from public, anon, authenticated;
revoke execute on function slot_stats(bigint)   from public, anon, authenticated;
grant  execute on function add_slot(bigint,text)     to authenticated;
grant  execute on function claim_slot(bigint)        to authenticated;
grant  execute on function vacate_slot(bigint)       to authenticated;
grant  execute on function crew_roster_slots(bigint) to authenticated;
