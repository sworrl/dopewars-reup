-- 0009_harden.sql — CVE-of-our-own: acquire_building took the cost as a client parameter, so a
-- malicious client could pass a NEGATIVE cost and mint cash. Fix: drop the vulnerable signature;
-- the cost is now computed SERVER-SIDE from the building kind and can't be influenced by the client.

drop function if exists acquire_building(double precision,double precision,text,text,bigint);

create or replace function acquire_building(p_lat double precision, p_lon double precision,
    p_city text, p_kind text default 'trap_house') returns jsonb
  language plpgsql security definer set search_path = public as $$
declare me profiles; existing buildings; b_id bigint; cost bigint;
begin
  me := require_player();
  if not consume_action() then raise exception 'daily_limit_reached'; end if;

  -- SERVER sets the price. The client sends only lat/lon/city/kind.
  cost := case p_kind
    when 'stash_spot'  then 250
    when 'corner'      then 500
    when 'trap_house'  then 1200
    when 'stash_house' then 4000
    when 'front'       then 6000
    else 1000 end;

  select * into existing from buildings
    where round(lat::numeric,5) = round(p_lat::numeric,5)
      and round(lon::numeric,5) = round(p_lon::numeric,5);
  if existing.id is not null and existing.holder is not null then raise exception 'location_taken'; end if;
  if me.cash < cost then raise exception 'insufficient_funds'; end if;

  update profiles set cash = cash - cost where id = me.id;
  if existing.id is not null then
    update buildings set holder = me.id, kind = p_kind, acquired_at = now(), last_tick = now()
      where id = existing.id returning id into b_id;
  else
    insert into buildings (lat, lon, city_id, kind, holder, acquired_at, last_tick)
      values (p_lat, p_lon, p_city, p_kind, me.id, now(), now()) returning id into b_id;
  end if;
  insert into ledger(profile_id, kind, cash_delta, city_id) values (me.id, 'building', -cost, p_city);
  return jsonb_build_object('ok', true, 'building', b_id, 'cost', cost);
end $$;

revoke execute on function acquire_building(double precision,double precision,text,text) from public;
grant execute on function acquire_building(double precision,double precision,text,text) to authenticated;
