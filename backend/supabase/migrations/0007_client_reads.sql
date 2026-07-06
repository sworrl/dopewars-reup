-- 0007_client_reads.sql — the client reads its state through ONE function, never direct table
-- selects. This lets you keep "automatically expose new tables" OFF: tables are never granted to
-- the API roles; the only interface is SECURITY DEFINER functions (which run as owner and read only
-- the caller's own rows). Tightest possible surface.

create or replace function get_my_state() returns jsonb
  language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'profile',     (select to_jsonb(p) - 'banned' from profiles p where p.id = auth.uid()),
    'tier',        (select tier from profiles where id = auth.uid()),
    'inventory',   coalesce((select jsonb_object_agg(drug_id, grams)
                             from inventory where profile_id = auth.uid()), '{}'::jsonb),
    'trap_houses', coalesce((select jsonb_agg(to_jsonb(t))
                             from trap_houses t where t.profile_id = auth.uid()), '[]'::jsonb),
    'buildings',   coalesce((select jsonb_agg(to_jsonb(b))
                             from buildings b where b.holder = auth.uid()), '[]'::jsonb),
    'modifiers',   coalesce((select jsonb_object_agg(key, value)
                             from user_modifiers
                             where profile_id = auth.uid()
                               and (expires_at is null or expires_at > world_now())), '{}'::jsonb)
  );
$$;

grant execute on function get_my_state() to authenticated;
