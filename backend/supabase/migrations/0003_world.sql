-- 0003_world.sql — trap houses (passive economy on the SERVER clock) + leaderboards.
--
-- This is where the current client's #1 cheat vector (AC-T1: roll the device clock forward to
-- mint passive income) is closed permanently: last_tick and elapsed are computed from world_now()
-- inside a SECURITY DEFINER function. The client cannot influence how much time "passed."

create table trap_houses (
  id          bigint generated always as identity primary key,
  profile_id  uuid references profiles(id) on delete cascade,
  city_id     text not null,
  tier_id     text not null,
  name        text not null,
  storage_lb  int  not null,
  slots       int  not null,
  stash       jsonb not null default '{}',          -- {drug_id: grams}
  employees   jsonb not null default '[]',          -- [{push_per_day, skim, ...}]
  last_tick   timestamptz not null default now(),   -- SERVER time
  created_at  timestamptz not null default now(),
  unique (profile_id, city_id)
);
alter table trap_houses enable row level security;
create policy "read own trap houses" on trap_houses for select using (profile_id = auth.uid());

-- One in-game day of pushing = 6 real minutes (mirrors the client's Trap.DAY_SECONDS).
create or replace function settle_trap_house(p_house bigint) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare me profiles; h trap_houses; elapsed_days numeric; push_budget numeric; avg_skim numeric;
        emp jsonb; k text; g int; px numeric; take int; gross bigint := 0; sold int := 0; net bigint;
begin
  me := require_player();
  select * into h from trap_houses where id = p_house and profile_id = me.id;
  if h.id is null then raise exception 'no_such_house'; end if;

  -- SERVER-clock elapsed. Never trusts the client. Clamp to a sane ceiling.
  elapsed_days := least(extract(epoch from (world_now() - h.last_tick)) / 360.0, 90.0);
  update trap_houses set last_tick = world_now() where id = h.id;

  if jsonb_array_length(h.employees) = 0 or elapsed_days <= 0 then
    return jsonb_build_object('sold', 0, 'net', 0);
  end if;

  push_budget := 0; avg_skim := 0;
  for emp in select * from jsonb_array_elements(h.employees) loop
    push_budget := push_budget + (emp->>'push_per_day')::numeric * elapsed_days;
    avg_skim := avg_skim + (emp->>'skim')::numeric;
  end loop;
  avg_skim := avg_skim / jsonb_array_length(h.employees);

  -- Sell stashed product at the SERVER price, highest-value first.
  for k, g in select key, value::int from jsonb_each_text(h.stash) order by price_of(h.city_id, key) desc loop
    exit when push_budget <= 0;
    px := price_of(h.city_id, k);
    take := least(g, floor(push_budget)::int);
    if take <= 0 then continue; end if;
    gross := gross + (take * px)::bigint;
    sold  := sold + take;
    push_budget := push_budget - take;
    if g - take <= 0 then h.stash := h.stash - k;
    else h.stash := jsonb_set(h.stash, array[k], to_jsonb(g - take)); end if;
  end loop;

  net := floor(gross * (1 - avg_skim));
  update trap_houses set stash = h.stash where id = h.id;
  if net > 0 then
    update profiles set cash = cash + net where id = me.id;
    insert into ledger(profile_id, kind, cash_delta, city_id) values (me.id, 'settle', net, h.city_id);
  end if;
  return jsonb_build_object('sold', sold, 'gross', gross, 'net', net, 'days', round(elapsed_days,2));
end $$;

-- ============================================================================
-- Leaderboard: net worth reconstructed from SERVER-owned state only (never a client number).
-- dev/admin and unranked tiers excluded.
-- ============================================================================
create or replace function leaderboard_top(p_limit int default 100)
  returns table(rank bigint, handle text, net_worth bigint)
  language sql stable security definer set search_path = public as $$
  select row_number() over (order by nw desc) as rank, handle, nw::bigint
  from (
    select p.handle,
      p.cash + coalesce((
        select sum(i.grams * d.base_price_per_g)
        from inventory i join drugs d on d.id = i.drug_id
        where i.profile_id = p.id), 0) as nw
    from profiles p
    join tier_config tc on tc.tier = p.tier
    where not p.banned and tc.ranked
  ) s
  order by nw desc
  limit greatest(1, least(p_limit, 500));
$$;

grant execute on function settle_trap_house(bigint) to authenticated;
grant execute on function leaderboard_top(int)      to authenticated, anon;
