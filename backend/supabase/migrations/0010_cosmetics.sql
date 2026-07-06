-- 0010_cosmetics.sql — cosmetic economy. HARD RULE: cosmetics never touch gameplay. They are
-- bought with CRED (an earned prestige currency, never real money) or granted by supporter tiers /
-- awards. Real money in this game buys ONLY playtime access (premium tier). Nothing purchasable
-- can help a player win. Cred is separate from cash ($) and does nothing but unlock flair.

alter table profiles add column if not exists cred     bigint not null default 0;
alter table profiles add column if not exists equipped  jsonb  not null default '{}';  -- {category: cosmetic_id}

-- Supporter tiers (added to the enum separately). Config rows:
insert into tier_config (tier, label, daily_action_limit, can_play_online, early_features, ranked, is_staff, notes) values
  ('supporter_gold','Supporter (Gold)', 200, true, true,  true, false, 'Higher supporter tier. Exclusive cosmetics, still no gameplay edge.'),
  ('founder',       'Founder',          -1,  true, true,  true, false, 'Early founding supporter. Unlimited playtime + founder-exclusive cosmetics. No gameplay edge.')
on conflict (tier) do update set label=excluded.label, daily_action_limit=excluded.daily_action_limit,
  early_features=excluded.early_features, notes=excluded.notes;

create table cosmetics (
  id             text primary key,
  name           text not null,
  category       text not null,   -- emblem|title|nameplate|frame|accent|badge|marker|tag|charm
  rarity         text not null,   -- common|uncommon|rare|epic|legendary|mythic|exclusive
  cred_cost      int  not null default 0,      -- 0 = not purchasable (earned/granted/award only)
  supporter_only boolean not null default false, -- granted by supporter tier, never bought
  source         text not null default 'store',  -- store|earned|supporter|award
  art            text,            -- res:// path (art generated in batches later)
  description    text
);

create table owned_cosmetics (
  profile_id  uuid references profiles(id) on delete cascade,
  cosmetic_id text references cosmetics(id),
  source      text,
  acquired_at timestamptz not null default now(),
  primary key (profile_id, cosmetic_id)
);

alter table cosmetics       enable row level security;
alter table owned_cosmetics enable row level security;
create policy "cosmetics readable"    on cosmetics       for select using (true);
create policy "read own cosmetics"    on owned_cosmetics for select using (profile_id = auth.uid());

-- ---- catalog + player cosmetic actions (server-authoritative) ----
create or replace function cosmetics_catalog() returns setof cosmetics
  language sql stable security definer set search_path = public as $$ select * from cosmetics order by category, rarity, name; $$;

create or replace function my_cosmetics() returns jsonb
  language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'cred', (select cred from profiles where id = auth.uid()),
    'equipped', (select equipped from profiles where id = auth.uid()),
    'owned', coalesce((select jsonb_agg(cosmetic_id) from owned_cosmetics where profile_id = auth.uid()), '[]'::jsonb));
$$;

create or replace function buy_cosmetic(p_id text) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare me profiles; c cosmetics;
begin
  me := require_player();
  select * into c from cosmetics where id = p_id;
  if c.id is null then raise exception 'no_such_cosmetic'; end if;
  if exists(select 1 from owned_cosmetics where profile_id = me.id and cosmetic_id = p_id) then raise exception 'already_owned'; end if;
  if c.supporter_only or c.source <> 'store' or c.cred_cost <= 0 then raise exception 'not_purchasable'; end if;
  if me.cred < c.cred_cost then raise exception 'insufficient_cred'; end if;
  update profiles set cred = cred - c.cred_cost where id = me.id;
  insert into owned_cosmetics(profile_id, cosmetic_id, source) values (me.id, p_id, 'store');
  return jsonb_build_object('ok', true, 'id', p_id, 'cred_left', me.cred - c.cred_cost);
end $$;

create or replace function equip_cosmetic(p_id text) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare me profiles; c cosmetics;
begin
  me := require_player();
  select * into c from cosmetics where id = p_id;
  if c.id is null then raise exception 'no_such_cosmetic'; end if;
  if not exists(select 1 from owned_cosmetics where profile_id = me.id and cosmetic_id = p_id) then raise exception 'not_owned'; end if;
  update profiles set equipped = jsonb_set(coalesce(equipped,'{}'::jsonb), array[c.category], to_jsonb(p_id)) where id = me.id;
  return jsonb_build_object('ok', true, 'category', c.category, 'id', p_id);
end $$;

-- ---- staff: award cosmetics & cred (the "special items I can give out" + awards) ----
create or replace function admin_grant_cosmetic(p_user uuid, p_cosmetic text) returns jsonb
  language plpgsql security definer set search_path = public as $$
begin
  if not is_staff(auth.uid()) then raise exception 'not_authorized'; end if;
  insert into owned_cosmetics(profile_id, cosmetic_id, source) values (p_user, p_cosmetic, 'award')
    on conflict do nothing;
  return jsonb_build_object('ok', true, 'user', p_user, 'cosmetic', p_cosmetic);
end $$;

create or replace function admin_grant_cred(p_user uuid, p_amount bigint) returns jsonb
  language plpgsql security definer set search_path = public as $$
begin
  if not is_staff(auth.uid()) then raise exception 'not_authorized'; end if;
  update profiles set cred = cred + p_amount where id = p_user;
  return jsonb_build_object('ok', true, 'user', p_user, 'cred_added', p_amount);
end $$;

-- Supporter tiers auto-own their exclusive cosmetics: grant all supporter_only cosmetics a player's
-- tier qualifies for. Staff calls this after a tier change (or on login).
create or replace function sync_supporter_cosmetics(p_user uuid) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare t account_tier; n int := 0;
begin
  if not is_staff(auth.uid()) and auth.uid() <> p_user then raise exception 'not_authorized'; end if;
  select tier into t from profiles where id = p_user;
  insert into owned_cosmetics(profile_id, cosmetic_id, source)
    select p_user, id, 'supporter' from cosmetics
    where supporter_only and (
      (t in ('supporter','supporter_gold','founder','dev','admin') and rarity <> 'exclusive') or
      (t in ('supporter_gold','founder','dev','admin')) or
      (t in ('founder','dev','admin')))
    on conflict do nothing;
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'granted', n);
end $$;

-- ---- extend get_my_state with cosmetics ----
create or replace function get_my_state() returns jsonb
  language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'profile',     (select to_jsonb(p) - 'banned' from profiles p where p.id = auth.uid()),
    'tier',        (select tier from profiles where id = auth.uid()),
    'inventory',   coalesce((select jsonb_object_agg(drug_id, grams) from inventory where profile_id = auth.uid()), '{}'::jsonb),
    'trap_houses', coalesce((select jsonb_agg(to_jsonb(t)) from trap_houses t where t.profile_id = auth.uid()), '[]'::jsonb),
    'buildings',   coalesce((select jsonb_agg(to_jsonb(b)) from buildings b where b.holder = auth.uid()), '[]'::jsonb),
    'modifiers',   coalesce((select jsonb_object_agg(key, value) from user_modifiers where profile_id = auth.uid() and (expires_at is null or expires_at > world_now())), '{}'::jsonb),
    'cosmetics',   coalesce((select jsonb_agg(cosmetic_id) from owned_cosmetics where profile_id = auth.uid()), '[]'::jsonb)
  );
$$;

grant execute on function cosmetics_catalog()                to authenticated, anon;
grant execute on function my_cosmetics()                     to authenticated;
grant execute on function buy_cosmetic(text)                 to authenticated;
grant execute on function equip_cosmetic(text)               to authenticated;
grant execute on function admin_grant_cosmetic(uuid,text)    to authenticated;
grant execute on function admin_grant_cred(uuid,bigint)      to authenticated;
grant execute on function sync_supporter_cosmetics(uuid)     to authenticated;
grant execute on function get_my_state()                     to authenticated;
