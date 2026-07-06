-- 0016_profiles_media.sql — custom profile images + PII posture.
--
-- Profile images live in a PRIVATE Storage bucket ('avatars'); nothing is world-readable — the app
-- fetches a short-lived signed URL. RLS on storage.objects scopes every read/write to the owner's own
-- folder (auth.uid()), so it stays inside the no-cross-table-access model: you can only touch your own
-- image. Custom avatars unlock at LEVEL 10 (mid-game), enforced server-side. Profile "embellishments"
-- are the existing frame cosmetics (paid or earned/gifted) equipped around the avatar — no new system.
--
-- PII: free play needs none. The only PII we hold is the email (in auth.users, encrypted at rest by
-- the platform) and the avatar image (private bucket). Billing PII stays in Stripe, not our DB.

alter table profiles add column if not exists avatar_path text;   -- e.g. '<uid>/avatar.png'

-- Server-side level from XP (mirrors the client curve: L1=100, L2=500, else 100*n^2.32 cumulative).
create or replace function player_level(p_xp bigint) returns int
  language sql immutable set search_path = public as $$
  select coalesce(max(n), 0)::int from generate_series(0, 200) n
  where (case when n = 0 then 0 when n = 1 then 100 when n = 2 then 500
              else round(100 * power(n, 2.32)) end) <= p_xp;
$$;

-- Private avatars bucket (idempotent).
insert into storage.buckets (id, name, public) values ('avatars', 'avatars', false)
  on conflict (id) do nothing;

-- Own-folder-only access to avatars (path is '<uid>/...'). Nobody can read another player's image.
do $$
begin
  if not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='avatars_own_all') then
    create policy "avatars_own_all" on storage.objects for all to authenticated
      using      (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
      with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
  end if;
end $$;

-- Record the avatar reference — level-gated + path-validated (must be in the caller's own folder).
create or replace function set_avatar(p_path text) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare me profiles;
begin
  me := require_player();
  if player_level(me.xp) < 10 then raise exception 'level_too_low'; end if;
  if p_path is null or p_path not like me.id::text || '/%' then raise exception 'bad_path'; end if;
  update profiles set avatar_path = p_path where id = me.id;
  return jsonb_build_object('ok', true, 'avatar_path', p_path);
end $$;

create or replace function clear_avatar() returns jsonb
  language plpgsql security definer set search_path = public as $$
declare me profiles;
begin
  me := require_player();
  update profiles set avatar_path = null where id = me.id;
  return jsonb_build_object('ok', true);
end $$;

revoke execute on function player_level(bigint) from public, anon, authenticated;
grant  execute on function set_avatar(text)  to authenticated;
grant  execute on function clear_avatar()    to authenticated;
