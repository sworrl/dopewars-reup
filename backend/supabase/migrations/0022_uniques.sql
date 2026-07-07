-- 0022_uniques.sql — TRULY UNIQUE server-single items. Each exists in exactly ONE copy globally; once
-- claimed it can never be claimed again. This migration ships only the TABLE + claim mechanics. The 20
-- actual items (their real names/stats/flavor) are seeded from a GITIGNORED private file so they can't
-- be datamined from the public repo — in code they surface only as opaque random codes and a "mystery".

create table if not exists unique_items (
  code       text primary key,               -- opaque random token; the only id that ever touches code
  name       text not null,                  -- the real fancy name (lives only in the live DB / private seed)
  category   text not null default 'relic',
  threat     int  not null default 12,
  flavor     text,
  claimed_by uuid references profiles(id) on delete set null,
  claimed_at timestamptz
);
alter table unique_items enable row level security;
create index if not exists unique_items_unclaimed on unique_items(code) where claimed_by is null;

-- get_my_state now also carries the uniques I own (resolved server-side; names never live in the repo).
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
    'weapons',     coalesce((select jsonb_agg(weapon_id) from player_weapons where profile_id = auth.uid()), '[]'::jsonb),
    'uniques',     coalesce((select jsonb_agg(jsonb_build_object('code',code,'name',name,'category',category,'threat',threat,'flavor',flavor))
                             from unique_items where claimed_by = auth.uid()), '[]'::jsonb)
  );
$$;
grant execute on function get_my_state() to authenticated;

-- claim_package: adds a unique roll. A package whose contents has {"unique": true} atomically claims ONE
-- unclaimed unique for the opener (skip-locked so two openers never grab the same one). If every unique
-- is already claimed, it falls back to a random rare weapon so the box is never empty. Supersedes 0021.
create or replace function claim_package(p_id bigint) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare me profiles; c jsonb; drug text; g int; cos text; wid text; uq unique_items; fb text;
begin
  me := require_player();
  select coalesce(pp.contents_override, pd.contents) into c
    from pending_packages pp join package_defs pd on pd.id = pp.package_id
    where pp.id = p_id and pp.profile_id = me.id and pp.claimed_at is null;
  if c is null then raise exception 'no_such_package'; end if;

  if coalesce((c->>'unique')::boolean, false) then
    select * into uq from unique_items where claimed_by is null order by random() for update skip locked limit 1;
    if uq.code is not null then
      update unique_items set claimed_by = me.id, claimed_at = now() where code = uq.code;
      c := jsonb_set(c, '{rolled_unique}', jsonb_build_object(
        'code', uq.code, 'name', uq.name, 'category', uq.category, 'threat', uq.threat, 'flavor', uq.flavor));
    else
      select id into fb from weapon_defs where threat >= 7 or nfa order by random() limit 1;
      if fb is not null then
        insert into player_weapons(profile_id, weapon_id, acquired) values (me.id, fb, 'grant') on conflict do nothing;
        c := jsonb_set(c, '{weapons}', coalesce(c->'weapons','[]'::jsonb) || to_jsonb(array[fb]));
      end if;
    end if;
  end if;

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

-- A mystery-crate package def (generic name/flavor — reveals nothing). Its unique flag drives the roll.
insert into package_defs (id, name, kind, contents, description) values
  ('mystery_crate', 'Sealed crate', 'award', '{"unique": true, "cred": 500}',
   'An unmarked crate. No telling what''s inside until it''s open.')
on conflict (id) do update set name=excluded.name, kind=excluded.kind,
  contents=excluded.contents, description=excluded.description;
