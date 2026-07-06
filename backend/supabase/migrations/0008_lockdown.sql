-- 0008_lockdown.sql — the hard lockdown. API roles (anon, authenticated) can touch NO tables and
-- NO sequences directly, and can execute ONLY the intended client-facing functions. Everything else
-- is reached exclusively through SECURITY DEFINER functions (which run as owner and bypass this).
-- This is "automatically expose new tables = OFF" enforced in SQL.

-- 1. Tables & sequences: no direct API access, now or in future.
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
grant usage on schema public to anon, authenticated;   -- needed for RPC routing

-- 2. Functions: revoke everything (incl. the default PUBLIC grant), then re-grant ONLY the
--    client-facing API surface. Revoking from anon/authenticated alone leaves the PUBLIC grant,
--    so internal helpers stay callable — must revoke from PUBLIC too.
revoke execute on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;

grant execute on function get_my_state()                            to authenticated;
grant execute on function buy(text,int)                             to authenticated;
grant execute on function sell(text,int)                            to authenticated;
grant execute on function settle_trap_house(bigint)                 to authenticated;
grant execute on function acquire_building(double precision,double precision,text,text,bigint) to authenticated;
grant execute on function release_building(bigint)                  to authenticated;
grant execute on function buildings_near(double precision,double precision,double precision)   to authenticated;
grant execute on function my_modifiers()                            to authenticated;
grant execute on function leaderboard_top(int)                      to authenticated, anon;
grant execute on function world_now()                               to authenticated, anon;
grant execute on function admin_set_tier(uuid, account_tier)         to authenticated;
grant execute on function admin_set_tier_by_handle(text, account_tier) to authenticated;
grant execute on function admin_grant_modifier(uuid,text,jsonb,text,timestamptz) to authenticated;
grant execute on function admin_revoke_modifier(uuid,text)          to authenticated;
-- price_of / require_player / consume_action / is_staff / has_modifier / modifier_value stay
-- INTERNAL — the definer functions call them as owner, so clients never need direct access.

-- 3. Auto-enable RLS on any future table (best-effort; needs elevated privs — skipped cleanly if not).
do $outer$
begin
  create or replace function auto_enable_rls() returns event_trigger language plpgsql as $fn$
  declare obj record;
  begin
    for obj in select * from pg_event_trigger_ddl_commands() where command_tag = 'CREATE TABLE' loop
      if obj.schema_name = 'public' then
        execute format('alter table %s enable row level security', obj.object_identity);
      end if;
    end loop;
  end $fn$;
  begin
    drop event trigger if exists auto_rls;
    create event trigger auto_rls on ddl_command_end when tag in ('CREATE TABLE')
      execute function auto_enable_rls();
    raise notice 'auto_rls event trigger installed';
  exception when others then
    raise notice 'auto_rls event trigger skipped (insufficient privilege is fine): %', sqlerrm;
  end;
end $outer$;
