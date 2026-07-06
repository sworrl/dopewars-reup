-- 0005_buildings.sql — occupy REAL map locations as operations. Server-owned, contested.
-- A building is an actual coordinate (an OSM footprint/POI) in the town you're playing. Two players
-- can't hold the same location; the unique index + validated RPCs enforce that server-side.

create table buildings (
  id          bigint generated always as identity primary key,
  osm_id      text,                                   -- OSM way/node id when known
  lat         double precision not null,
  lon         double precision not null,
  city_id     text not null,
  kind        text not null default 'trap_house',     -- trap_house | stash_house | front | corner
  name        text,
  holder      uuid references profiles(id) on delete set null,   -- null = unoccupied
  storage_lb  int not null default 120,
  slots       int not null default 1,
  stash       jsonb not null default '{}',
  employees   jsonb not null default '[]',
  last_tick   timestamptz not null default now(),
  acquired_at timestamptz,
  created_at  timestamptz not null default now()
);
-- One holder per physical spot: a location is identified by its rounded coordinate.
create unique index buildings_spot on buildings (round(lat::numeric,5), round(lon::numeric,5));
create index buildings_holder on buildings (holder);
create index buildings_city on buildings (city_id);

alter table buildings enable row level security;
-- You can see buildings you hold. Others' locations are discovered through gameplay (a nearby fn),
-- never by reading the whole table — that would lift the fog of war (SURF · Visibility).
create policy "read own buildings" on buildings for select using (holder = auth.uid());

-- Claim an unoccupied real location as an operation. Server decides if it's free.
create or replace function acquire_building(p_lat double precision, p_lon double precision,
    p_city text, p_kind text default 'trap_house', p_cost bigint default 250) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare me profiles; existing buildings; b_id bigint;
begin
  me := require_player();
  if not consume_action() then raise exception 'daily_limit_reached'; end if;
  -- Is this physical spot already held?
  select * into existing from buildings
    where round(lat::numeric,5) = round(p_lat::numeric,5)
      and round(lon::numeric,5) = round(p_lon::numeric,5);
  if existing.id is not null and existing.holder is not null then
    raise exception 'location_taken';
  end if;
  if me.cash < p_cost then raise exception 'insufficient_funds'; end if;

  update profiles set cash = cash - p_cost where id = me.id;
  if existing.id is not null then
    update buildings set holder = me.id, kind = p_kind, acquired_at = now(), last_tick = now()
      where id = existing.id returning id into b_id;
  else
    insert into buildings (lat, lon, city_id, kind, holder, acquired_at, last_tick)
      values (p_lat, p_lon, p_city, p_kind, me.id, now(), now()) returning id into b_id;
  end if;
  insert into ledger(profile_id, kind, cash_delta, city_id) values (me.id, 'building', -p_cost, p_city);
  return jsonb_build_object('ok', true, 'building', b_id);
end $$;

create or replace function release_building(p_id bigint) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare me profiles;
begin
  me := require_player();
  update buildings set holder = null where id = p_id and holder = me.id;
  if not found then raise exception 'not_your_building'; end if;
  return jsonb_build_object('ok', true);
end $$;

-- Discovery: buildings within a rough radius (degrees) — the only way to see others' operations,
-- and even then only occupied ones, so the world reveals through presence, not a table dump.
create or replace function buildings_near(p_lat double precision, p_lon double precision,
    p_radius double precision default 0.05) returns table(id bigint, lat double precision,
    lon double precision, kind text, is_mine boolean)
  language sql stable security definer set search_path = public as $$
  select id, lat, lon, kind, holder = auth.uid()
  from buildings
  where holder is not null
    and lat between p_lat - p_radius and p_lat + p_radius
    and lon between p_lon - p_radius and p_lon + p_radius
  limit 200;
$$;

grant execute on function acquire_building(double precision,double precision,text,text,bigint) to authenticated;
grant execute on function release_building(bigint) to authenticated;
grant execute on function buildings_near(double precision,double precision,double precision) to authenticated;
