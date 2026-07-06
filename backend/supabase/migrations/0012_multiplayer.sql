-- 0012_multiplayer.sql — crews, presence, and the layered comms model (local earshot / crew /
-- whisper / phone). Server-authoritative: the client sends intents, the server decides who hears
-- what. Tables are never API-exposed; only the functions below are callable. See the comms design:
-- the channel you use IS your exposure.

-- ============================ crews ============================
create table crews (
  id         bigint generated always as identity primary key,
  name       text not null,
  tag        text unique,
  leader     uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create table crew_members (
  crew_id    bigint references crews(id) on delete cascade,
  profile_id uuid references profiles(id) on delete cascade,
  role       text not null default 'member',   -- leader | officer | member
  joined_at  timestamptz not null default now(),
  primary key (crew_id, profile_id)
);
create unique index crew_members_one_per_player on crew_members(profile_id);  -- one crew (v1)

-- ============================ presence ============================
-- Opted-in online position. Only ever written by the server from the player's own committed moves.
create table presence (
  profile_id uuid primary key references profiles(id) on delete cascade,
  lat        double precision,
  lon        double precision,
  opted_in   boolean not null default false,
  updated_at timestamptz not null default now()
);

-- ============================ messages (comms) ============================
create table messages (
  id         bigint generated always as identity primary key,
  sender     uuid references profiles(id) on delete cascade,
  scope      text not null,          -- local | crew | whisper | phone
  target     uuid references profiles(id) on delete cascade,   -- whisper/phone recipient
  crew_id    bigint references crews(id) on delete cascade,    -- crew scope
  lat        double precision,       -- local (earshot) origin
  lon        double precision,
  body       text not null,
  created_at timestamptz not null default now()
);
create index messages_local_time on messages(created_at desc) where scope = 'local';

alter table crews        enable row level security;
alter table crew_members enable row level security;
alter table presence     enable row level security;
alter table messages     enable row level security;
-- No direct policies: function-only, like the rest of the schema.

-- ---- crews ----
create or replace function create_crew(p_name text, p_tag text) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare me profiles; cid bigint;
begin
  me := require_player();
  if exists(select 1 from crew_members where profile_id = me.id) then raise exception 'already_in_crew'; end if;
  insert into crews(name, tag, leader) values (p_name, p_tag, me.id) returning id into cid;
  insert into crew_members(crew_id, profile_id, role) values (cid, me.id, 'leader');
  return jsonb_build_object('ok', true, 'crew', cid);
end $$;

create or replace function join_crew(p_crew bigint) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare me profiles;
begin
  me := require_player();
  if exists(select 1 from crew_members where profile_id = me.id) then raise exception 'already_in_crew'; end if;
  if not exists(select 1 from crews where id = p_crew) then raise exception 'no_such_crew'; end if;
  insert into crew_members(crew_id, profile_id, role) values (p_crew, me.id, 'member');
  return jsonb_build_object('ok', true, 'crew', p_crew);
end $$;

create or replace function leave_crew() returns jsonb
  language plpgsql security definer set search_path = public as $$
declare me profiles;
begin
  me := require_player();
  delete from crew_members where profile_id = me.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function my_crew() returns jsonb
  language sql stable security definer set search_path = public as $$
  select case when c.id is null then '{}'::jsonb else jsonb_build_object(
    'id', c.id, 'name', c.name, 'tag', c.tag, 'leader', c.leader,
    'roster', (select jsonb_agg(jsonb_build_object('handle', p.handle, 'role', m2.role))
               from crew_members m2 join profiles p on p.id = m2.profile_id where m2.crew_id = c.id))
  end
  from crew_members m join crews c on c.id = m.crew_id where m.profile_id = auth.uid();
$$;

-- ---- presence ----
create or replace function update_presence(p_opted_in boolean) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare me profiles;
begin
  me := require_player();
  -- position comes from SERVER-owned profile state, never the client (anti-teleport).
  insert into presence(profile_id, lat, lon, opted_in, updated_at)
    values (me.id, me.lat, me.lon, p_opted_in, world_now())
    on conflict (profile_id) do update set lat = me.lat, lon = me.lon, opted_in = p_opted_in, updated_at = world_now();
  return jsonb_build_object('ok', true);
end $$;

-- ---- comms: the channel is the exposure ----
create or replace function send_message(p_scope text, p_body text, p_target uuid default null, p_crew bigint default null) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare me profiles;
begin
  me := require_player();
  if length(coalesce(p_body,'')) = 0 or length(p_body) > 500 then raise exception 'bad_message'; end if;
  if not consume_action() then raise exception 'daily_limit_reached'; end if;
  if p_scope = 'local' then
    insert into messages(sender, scope, lat, lon, body) values (me.id, 'local', me.lat, me.lon, p_body);
  elsif p_scope = 'crew' then
    if not exists(select 1 from crew_members where profile_id = me.id) then raise exception 'not_in_crew'; end if;
    insert into messages(sender, scope, crew_id, body)
      select me.id, 'crew', crew_id, p_body from crew_members where profile_id = me.id;
  elsif p_scope in ('whisper','phone') then
    if p_target is null then raise exception 'no_target'; end if;
    insert into messages(sender, scope, target, body) values (me.id, p_scope, p_target, p_body);
  else raise exception 'bad_scope'; end if;
  return jsonb_build_object('ok', true);
end $$;

-- Earshot: local messages within a rough radius of YOUR server-owned position, last 10 minutes.
create or replace function hear_local(p_radius double precision default 0.02) returns table(handle text, body text, at timestamptz)
  language sql stable security definer set search_path = public as $$
  select p.handle, m.body, m.created_at
  from messages m
  join profiles me on me.id = auth.uid()
  join profiles p on p.id = m.sender
  where m.scope = 'local' and m.created_at > world_now() - interval '10 minutes'
    and m.lat between me.lat - p_radius and me.lat + p_radius
    and m.lon between me.lon - p_radius and me.lon + p_radius
  order by m.created_at desc limit 100;
$$;

create or replace function my_crew_chat() returns table(handle text, body text, at timestamptz)
  language sql stable security definer set search_path = public as $$
  select p.handle, m.body, m.created_at from messages m
  join profiles p on p.id = m.sender
  where m.scope = 'crew' and m.crew_id = (select crew_id from crew_members where profile_id = auth.uid())
  order by m.created_at desc limit 100;
$$;

-- Whispers/phone: only the two ends can read them.
create or replace function my_whispers() returns table(handle text, body text, scope text, mine boolean, at timestamptz)
  language sql stable security definer set search_path = public as $$
  select p.handle, m.body, m.scope, m.sender = auth.uid(), m.created_at from messages m
  join profiles p on p.id = case when m.sender = auth.uid() then m.target else m.sender end
  where m.scope in ('whisper','phone') and (m.sender = auth.uid() or m.target = auth.uid())
  order by m.created_at desc limit 100;
$$;

grant execute on function create_crew(text,text)                          to authenticated;
grant execute on function join_crew(bigint)                               to authenticated;
grant execute on function leave_crew()                                    to authenticated;
grant execute on function my_crew()                                       to authenticated;
grant execute on function update_presence(boolean)                        to authenticated;
grant execute on function send_message(text,text,uuid,bigint)             to authenticated;
grant execute on function hear_local(double precision)                    to authenticated;
grant execute on function my_crew_chat()                                  to authenticated;
grant execute on function my_whispers()                                   to authenticated;
