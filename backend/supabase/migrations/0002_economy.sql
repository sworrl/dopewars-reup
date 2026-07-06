-- 0002_economy.sql — server-authoritative economy: prices, inventory, trades, ledger.
-- The client NEVER sends a price or a cash figure. It sends "buy N grams of drug D"; the server
-- supplies the price, checks funds, mutates state, and writes an immutable ledger row.

create table drugs (
  id                text primary key,
  name              text    not null,
  base_price_per_g  numeric not null,
  volatility        numeric not null default 0.20,
  weight_per_unit_g numeric not null default 1.0,
  legal_severity    int     not null default 1
);

create table region_demand (
  city_id text    not null,
  drug_id text    not null references drugs(id),
  demand  numeric not null default 1.0,
  primary key (city_id, drug_id)
);

-- SERVER-OWNED inventory & append-only ledger (audit + leaderboard source of truth).
create table inventory (
  profile_id uuid references profiles(id) on delete cascade,
  drug_id    text references drugs(id),
  grams      int  not null check (grams >= 0),
  primary key (profile_id, drug_id)
);

create table ledger (
  id         bigint generated always as identity primary key,
  profile_id uuid references profiles(id) on delete cascade,
  kind       text   not null,                 -- buy | sell | settle | travel_cost | vehicle | phone
  drug_id    text,
  grams      int,
  unit_price numeric,
  cash_delta bigint not null,
  city_id    text,
  created_at timestamptz not null default now()
);
create index ledger_profile_time on ledger(profile_id, created_at desc);

alter table drugs         enable row level security;
alter table region_demand enable row level security;
alter table inventory     enable row level security;
alter table ledger        enable row level security;
create policy "drugs public"         on drugs         for select using (true);
create policy "region_demand public" on region_demand for select using (true);
create policy "read own inventory"   on inventory     for select using (profile_id = auth.uid());
create policy "read own ledger"      on ledger        for select using (profile_id = auth.uid());

-- ============================================================================
-- SERVER-AUTHORITATIVE price. Deterministic per (city, drug, 6h window) so it can't be forged
-- and every client sees the same market, but it drifts on the server clock. Buying/selling
-- pressure can be layered on later; this is the tamper-proof base.
-- ============================================================================
create or replace function price_of(p_city text, p_drug text) returns numeric
  language plpgsql stable security definer set search_path = public as $$
declare base numeric; vol numeric; dem numeric; window_ix bigint; seed bigint; wobble numeric;
begin
  select base_price_per_g, volatility into base, vol from drugs where id = p_drug;
  if base is null then raise exception 'unknown_drug'; end if;
  select demand into dem from region_demand where city_id = p_city and drug_id = p_drug;
  dem := coalesce(dem, 1.0);
  window_ix := floor(extract(epoch from world_now()) / 21600);   -- 6-hour price windows
  seed := ('x' || substr(md5(p_city || ':' || p_drug || ':' || window_ix::text), 1, 8))::bit(32)::bigint;
  wobble := 1.0 + vol * (((seed & 4294967295) / 4294967295.0) - 0.5) * 2.0;
  return round(base * dem * greatest(wobble, 0.2), 2);
end $$;

-- ============================================================================
-- BUY / SELL. The only way inventory or cash ever changes from trading.
-- ============================================================================
create or replace function buy(p_drug text, p_grams int) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare me profiles; px numeric; cost bigint;
begin
  me := require_player();
  if p_grams <= 0 or p_grams > 1000000 then raise exception 'bad_quantity'; end if;
  if not consume_action() then raise exception 'daily_limit_reached'; end if;
  px   := price_of(me.current_city_id, p_drug);
  cost := ceil(px * p_grams);
  if me.cash < cost then raise exception 'insufficient_funds'; end if;

  update profiles set cash = cash - cost, last_active = now() where id = me.id;
  insert into inventory(profile_id, drug_id, grams) values (me.id, p_drug, p_grams)
    on conflict (profile_id, drug_id) do update set grams = inventory.grams + p_grams;
  insert into ledger(profile_id, kind, drug_id, grams, unit_price, cash_delta, city_id)
    values (me.id, 'buy', p_drug, p_grams, px, -cost, me.current_city_id);
  return jsonb_build_object('ok', true, 'unit_price', px, 'cost', cost);
end $$;

create or replace function sell(p_drug text, p_grams int) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare me profiles; px numeric; revenue bigint; have int; gained_xp int;
begin
  me := require_player();
  if p_grams <= 0 then raise exception 'bad_quantity'; end if;
  if not consume_action() then raise exception 'daily_limit_reached'; end if;
  select grams into have from inventory where profile_id = me.id and drug_id = p_drug;
  if coalesce(have,0) < p_grams then raise exception 'not_enough_to_sell'; end if;

  px      := price_of(me.current_city_id, p_drug);
  revenue := floor(px * p_grams);
  gained_xp := greatest(1, (revenue / 40)::int);

  update inventory set grams = grams - p_grams where profile_id = me.id and drug_id = p_drug;
  delete from inventory where profile_id = me.id and drug_id = p_drug and grams <= 0;
  update profiles set cash = cash + revenue, xp = xp + gained_xp, last_active = now() where id = me.id;
  insert into ledger(profile_id, kind, drug_id, grams, unit_price, cash_delta, city_id)
    values (me.id, 'sell', p_drug, p_grams, px, revenue, me.current_city_id);
  return jsonb_build_object('ok', true, 'unit_price', px, 'revenue', revenue, 'xp', gained_xp);
end $$;

grant execute on function price_of(text,text) to authenticated;
grant execute on function buy(text,int)       to authenticated;
grant execute on function sell(text,int)       to authenticated;
