-- 0021_weapons.sql — server-authoritative weapon ownership. Weapons were client-local (didn't persist
-- online, weren't grantable). Now: an Arsenal that syncs across devices, cash-checked server buys, and
-- weapons that packages can grant (rare-gun loot). weapon_defs mirrors the client weapons.json catalog.

create table if not exists weapon_defs (
  id text primary key,
  name text not null,
  category text not null,
  threat int not null default 0,
  legal_price int not null default 0,
  legal_available boolean not null default false,
  nfa boolean not null default false,
  black_price int not null default 0
);
insert into weapon_defs (id, name, category, threat, legal_price, legal_available, nfa, black_price) values
  ('knife_folding_pocket_knife','Folding pocket knife','knife',2,25,true,false,15),
  ('knife_hunting_fixed_blade','Hunting fixed blade','knife',3,80,true,false,60),
  ('knife_combat_utility_knife','Combat utility knife','knife',4,70,true,false,55),
  ('knife_karambit','Karambit','knife',4,90,true,false,70),
  ('knife_bowie_knife','Bowie knife','knife',4,110,true,false,80),
  ('knife_switchblade','Switchblade','knife',3,60,true,false,50),
  ('knife_butterfly_knife','Butterfly knife','knife',3,45,true,false,40),
  ('knife_machete','Machete','knife',4,40,true,false,30),
  ('knife_cleaver','Cleaver','knife',3,35,true,false,25),
  ('knife_tactical_tanto','Tactical tanto','knife',4,130,true,false,95),
  ('shiv_toothbrush_shank','Toothbrush shank','shiv',2,0,false,false,20),
  ('shiv_sharpened_spoon','Sharpened spoon','shiv',1,0,false,false,15),
  ('shiv_glass_shard_wrap','Glass shard wrap','shiv',2,0,false,false,10),
  ('shiv_filed_rebar_spike','Filed rebar spike','shiv',3,0,false,false,25),
  ('shiv_prison_made_shank','Prison-made shank','shiv',3,0,false,false,40),
  ('shiv_ice_pick_shiv','Ice-pick shiv','shiv',3,0,false,false,30),
  ('shiv_razor_knuckles','Razor knuckles','shiv',2,0,false,false,35),
  ('shiv_screwdriver_shiv','Screwdriver shiv','shiv',2,0,false,false,18),
  ('shiv_bike_spoke_pick','Bike-spoke pick','shiv',2,0,false,false,12),
  ('shiv_padlock_in_sock','Padlock-in-sock','shiv',2,0,false,false,8),
  ('handgun_striker_9_compact','Striker 9 Compact','handgun',5,520,true,false,650),
  ('handgun_m_p_pattern_9mm','M&P-pattern 9mm','handgun',5,480,true,false,600),
  ('handgun_p320_pattern_9mm','P320-pattern 9mm','handgun',5,550,true,false,700),
  ('handgun_pocket_380','Pocket .380','handgun',4,280,true,false,400),
  ('handgun_1911_45','1911 .45','handgun',6,700,true,false,850),
  ('handgun_92_pattern_9mm','92-pattern 9mm','handgun',5,600,true,false,720),
  ('handgun_38_snub_revolver','.38 snub revolver','handgun',4,400,true,false,520),
  ('handgun_hand_cannon_50','Hand-cannon .50','handgun',7,1800,true,false,2400),
  ('handgun_budget_9mm_hi_point_ish','Budget 9mm (Hi-Point-ish)','handgun',4,180,true,false,300),
  ('handgun_polymer_40','Polymer .40','handgun',5,420,true,false,560),
  ('rifle_ar_pattern_5_56','AR-pattern 5.56','rifle',7,900,true,false,1600),
  ('rifle_ak_pattern_7_62','AK-pattern 7.62','rifle',7,950,true,false,1700),
  ('rifle_22_plinker','.22 plinker','rifle',3,300,true,false,450),
  ('rifle_bolt_action_hunter_308','Bolt-action hunter .308','rifle',6,700,true,false,1000),
  ('rifle_mini_ranch_rifle','Mini ranch rifle','rifle',6,1100,true,false,1600),
  ('rifle_sks_7_62','SKS 7.62','rifle',6,500,true,false,800),
  ('rifle_lever_action_30_30','Lever-action .30-30','rifle',5,600,true,false,850),
  ('rifle_precision_308','Precision .308','rifle',7,1600,true,false,2400),
  ('rifle_pcc_9mm_carbine','PCC 9mm carbine','rifle',5,650,true,false,950),
  ('rifle_battle_rifle_308','Battle rifle .308','rifle',7,1900,true,false,2900),
  ('shotgun_pump_12ga','Pump 12ga','shotgun',6,350,true,false,550),
  ('shotgun_tactical_pump_12ga','Tactical pump 12ga','shotgun',6,500,true,false,750),
  ('shotgun_semi_auto_12ga','Semi-auto 12ga','shotgun',6,800,true,false,1200),
  ('shotgun_double_barrel','Double-barrel','shotgun',5,450,true,false,650),
  ('shotgun_sawed_off_illegal_sbs','Sawed-off (illegal SBS)','shotgun',6,0,false,false,900),
  ('shotgun_youth_20ga','Youth 20ga','shotgun',4,300,true,false,450),
  ('shotgun_riot_12ga','Riot 12ga','shotgun',6,600,true,false,900),
  ('shotgun_bullpup_12ga','Bullpup 12ga','shotgun',6,1100,true,false,1700),
  ('shotgun_coach_gun','Coach gun','shotgun',5,400,true,false,600),
  ('shotgun_mag_fed_12ga','Mag-fed 12ga','shotgun',6,700,true,false,1100),
  ('smg_mp_pattern_smg','MP-pattern SMG','smg',8,22000,true,true,3200),
  ('smg_uzi_pattern_smg','Uzi-pattern SMG','smg',7,18000,true,true,2600),
  ('smg_mac_pattern_machine_pistol','MAC-pattern machine pistol','smg',7,12000,true,true,1800),
  ('smg_scorpion_pattern','Scorpion-pattern','smg',7,16000,true,true,2400),
  ('smg_grease_gun_style','Grease-gun style','smg',6,14000,true,true,2000),
  ('smg_ppsh_pattern','PPSh-pattern','smg',7,15000,true,true,2200),
  ('smg_micro_smg','Micro SMG','smg',7,20000,true,true,2800),
  ('smg_suppressed_smg','Suppressed SMG','smg',8,25000,true,true,3800),
  ('smg_sten_pattern','Sten-pattern','smg',6,13000,true,true,1600),
  ('smg_p90_pattern_pdw','P90-pattern PDW','smg',8,28000,true,true,4200),
  ('machinegun_squad_lmg_5_56','Squad LMG 5.56','machinegun',9,35000,true,true,6500),
  ('machinegun_gpmg_7_62','GPMG 7.62','machinegun',9,45000,true,true,9000),
  ('machinegun_belt_fed_50_hmg','Belt-fed .50 HMG','machinegun',10,120000,true,true,20000),
  ('machinegun_light_mg_carbine','Light MG carbine','machinegun',8,30000,true,true,5500),
  ('machinegun_pkm_pattern','PKM-pattern','machinegun',9,40000,true,true,7500),
  ('machinegun_m60_pattern','M60-pattern','machinegun',9,42000,true,true,8000),
  ('machinegun_minigun_display','Minigun (display)','machinegun',10,250000,true,true,45000),
  ('machinegun_rpk_pattern_lmg','RPK-pattern LMG','machinegun',8,28000,true,true,5000),
  ('machinegun_mg42_pattern','MG42-pattern','machinegun',9,55000,true,true,10000),
  ('machinegun_vintage_bar','Vintage BAR','machinegun',8,38000,true,true,7000),
  ('explosive_pipe_device','Pipe device','explosive',8,0,false,true,400),
  ('explosive_frag_grenade','Frag grenade','explosive',9,0,false,true,900),
  ('explosive_composition_brick','Composition brick','explosive',10,0,false,true,3500),
  ('explosive_stick_charge','Stick charge','explosive',8,0,false,true,600),
  ('explosive_molotov','Molotov','explosive',5,0,false,true,20),
  ('explosive_improvised_roadside_device','Improvised roadside device','explosive',10,0,false,true,1200),
  ('explosive_smoke_incendiary','Smoke/incendiary','explosive',6,0,false,true,150),
  ('explosive_det_cord_bundle','Det cord bundle','explosive',8,0,false,true,800),
  ('explosive_thermite_pack','Thermite pack','explosive',8,0,false,true,700),
  ('explosive_breaching_charge','Breaching charge','explosive',9,0,false,true,1500)
on conflict (id) do update set name=excluded.name, category=excluded.category, threat=excluded.threat,
  legal_price=excluded.legal_price, legal_available=excluded.legal_available, nfa=excluded.nfa,
  black_price=excluded.black_price;

create table if not exists player_weapons (
  profile_id  uuid references profiles(id) on delete cascade,
  weapon_id   text not null,
  acquired    text not null default 'legal',   -- legal | black | grant
  acquired_at timestamptz not null default now(),
  primary key (profile_id, weapon_id)
);
alter table weapon_defs    enable row level security;
alter table player_weapons enable row level security;

-- get_my_state now carries weapons (adds to the 0010 cosmetics version).
create or replace function get_my_state() returns jsonb
  language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'profile',     (select to_jsonb(p) - 'banned' from profiles p where p.id = auth.uid()),
    'tier',        (select tier from profiles where id = auth.uid()),
    'inventory',   coalesce((select jsonb_object_agg(drug_id, grams) from inventory where profile_id = auth.uid()), '{}'::jsonb),
    'trap_houses', coalesce((select jsonb_agg(to_jsonb(t)) from trap_houses t where t.profile_id = auth.uid()), '[]'::jsonb),
    'buildings',   coalesce((select jsonb_agg(to_jsonb(b)) from buildings b where b.holder = auth.uid()), '[]'::jsonb),
    'modifiers',   coalesce((select jsonb_object_agg(key, value) from user_modifiers where profile_id = auth.uid() and (expires_at is null or expires_at > world_now())), '{}'::jsonb),
    'cosmetics',   coalesce((select jsonb_agg(cosmetic_id) from owned_cosmetics where profile_id = auth.uid()), '[]'::jsonb),
    'weapons',     coalesce((select jsonb_agg(weapon_id) from player_weapons where profile_id = auth.uid()), '[]'::jsonb)
  );
$$;
grant execute on function get_my_state() to authenticated;

-- Server-authoritative weapon buy: cash checked + deducted on the server clock, ownership recorded.
create or replace function buy_weapon(p_id text, p_black boolean) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare me profiles; wd weapon_defs; price int;
begin
  me := require_player();
  select * into wd from weapon_defs where id = p_id;
  if wd.id is null then raise exception 'no_such_weapon'; end if;
  if exists (select 1 from player_weapons where profile_id = me.id and weapon_id = p_id) then
    raise exception 'already_owned'; end if;
  if p_black then
    if wd.black_price <= 0 then raise exception 'no_black_market'; end if;
    price := wd.black_price;
  else
    if not wd.legal_available then raise exception 'no_legal_sale'; end if;
    price := wd.legal_price;
  end if;
  if me.cash < price then raise exception 'insufficient_cash'; end if;
  update profiles set cash = cash - price where id = me.id;
  insert into player_weapons(profile_id, weapon_id, acquired)
    values (me.id, p_id, case when p_black then 'black' else 'legal' end);
  return jsonb_build_object('ok', true, 'weapon', p_id, 'price', price);
end $$;
revoke execute on function buy_weapon(text, boolean) from public, anon;
grant  execute on function buy_weapon(text, boolean) to authenticated;

-- claim_package now also grants weapons (rare-gun loot). Supersedes the 0020 version.
create or replace function claim_package(p_id bigint) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare me profiles; c jsonb; drug text; g int; cos text; wid text;
begin
  me := require_player();
  select coalesce(pp.contents_override, pd.contents) into c
    from pending_packages pp join package_defs pd on pd.id = pp.package_id
    where pp.id = p_id and pp.profile_id = me.id and pp.claimed_at is null;
  if c is null then raise exception 'no_such_package'; end if;

  update profiles set
      cash = cash + coalesce((c->>'cash')::bigint, 0),
      cred = cred + coalesce((c->>'cred')::bigint, 0),
      xp   = xp   + coalesce((c->>'xp')::bigint, 0)
    where id = me.id;
  for cos in select jsonb_array_elements_text(coalesce(c->'cosmetics', '[]'::jsonb)) loop
    insert into owned_cosmetics(profile_id, cosmetic_id) values (me.id, cos) on conflict do nothing;
  end loop;
  for wid in select jsonb_array_elements_text(coalesce(c->'weapons', '[]'::jsonb)) loop
    insert into player_weapons(profile_id, weapon_id, acquired) values (me.id, wid, 'grant') on conflict do nothing;
  end loop;
  for drug, g in select key, value::int from jsonb_each_text(coalesce(c->'inventory', '{}'::jsonb)) loop
    insert into inventory(profile_id, drug_id, grams) values (me.id, drug, g)
      on conflict (profile_id, drug_id) do update set grams = inventory.grams + g;
  end loop;

  update pending_packages set claimed_at = now() where id = p_id;
  return jsonb_build_object('ok', true, 'claimed', p_id, 'contents', c);
end $$;
grant execute on function claim_package(bigint) to authenticated;

-- Fence a weapon (online): ~45% of black-market value, ownership removed. Server-authoritative.
create or replace function sell_weapon(p_id text) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare me profiles; wd weapon_defs; payout int;
begin
  me := require_player();
  if not exists (select 1 from player_weapons where profile_id = me.id and weapon_id = p_id) then
    raise exception 'not_owned'; end if;
  select * into wd from weapon_defs where id = p_id;
  payout := floor(coalesce(wd.black_price, 0) * 0.45);
  delete from player_weapons where profile_id = me.id and weapon_id = p_id;
  update profiles set cash = cash + payout where id = me.id;
  return jsonb_build_object('ok', true, 'payout', payout);
end $$;
revoke execute on function sell_weapon(text) from public, anon;
grant  execute on function sell_weapon(text) to authenticated;
