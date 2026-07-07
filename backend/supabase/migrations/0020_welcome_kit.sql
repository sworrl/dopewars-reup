-- 0020_welcome_kit.sql — mystery welcome kits with a RANDOM rare item.
--
-- A package's contents normally come from its package_def (fixed bundle). A welcome kit instead rolls
-- a random top-rarity cosmetic PER GRANT, so it can't live in the shared def. We add a per-grant
-- contents_override; claim_package prefers it when present. Contents stay server-authoritative and are
-- never revealed to the client until the box is opened (claimed).

alter table pending_packages add column if not exists contents_override jsonb;

-- Claim a package: apply MY package's contents (override if set, else the def's) to my account, mark
-- claimed. Server-authoritative — the client can't mint a package or pick what's inside.
create or replace function claim_package(p_id bigint) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare me profiles; c jsonb; drug text; g int; cos text;
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

-- Roll a welcome kit for a player: founder flair (CRED + XP) plus ONE random top-rarity cosmetic they
-- don't already own — the "rare item". Queued as an unopened box; the roll is hidden until they open it.
-- Staff-only (admin tooling / signup trigger via service_role).
create or replace function grant_welcome_kit(p_user uuid) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare pick text; contents jsonb;
begin
  if not is_staff(auth.uid()) then raise exception 'not_staff'; end if;
  select c.id into pick from cosmetics c
    where c.rarity in ('mythic', 'exclusive')
      and c.id not in (select oc.cosmetic_id from owned_cosmetics oc where oc.profile_id = p_user)
    order by random() limit 1;
  contents := jsonb_build_object('cred', 2000, 'xp', 200,
    'cosmetics', case when pick is not null then jsonb_build_array(pick) else '[]'::jsonb end);
  insert into pending_packages(profile_id, package_id, contents_override)
    values (p_user, 'welcome_beta', contents);
  return jsonb_build_object('ok', true, 'user', p_user, 'rare_item', pick);
end $$;

revoke execute on function grant_welcome_kit(uuid) from public, anon;
grant  execute on function grant_welcome_kit(uuid) to authenticated;   -- is_staff-gated inside
