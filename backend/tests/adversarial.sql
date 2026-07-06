-- adversarial.sql — act as a malicious authenticated client and try to break every rule.
-- Entirely inside a transaction that ROLLS BACK, so prod stays clean. For each attack that is
-- SUPPOSED to be blocked, PASS = the server blocked it; FAIL = it leaked.

\set ON_ERROR_STOP on
begin;

-- Phase 0 (as postgres): two victims. Profiles auto-created by the on-signup trigger.
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
  ('a0000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-000000000000','authenticated','authenticated','a@test', now(), now()),
  ('b0000000-0000-0000-0000-00000000000b','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b@test', now(), now());

-- B owns a trap house and a building, so A can try to touch them.
insert into trap_houses (profile_id, city_id, tier_id, name, storage_lb, slots)
  values ('b0000000-0000-0000-0000-00000000000b','steubenville_oh','trap_house','B house',600,2);
insert into buildings (lat, lon, city_id, kind, holder, acquired_at)
  values (39.5, -80.5, 'steubenville_oh', 'trap_house', 'b0000000-0000-0000-0000-00000000000b', now());

-- Stash B's asset ids in session GUCs — the attacker CAN'T read the tables to find them (that's
-- the point), so we hand the ids in via a side channel to test the function-level guards.
select set_config('test.bhouse', (select id::text from trap_houses where name='B house'), false);
select set_config('test.bbuild', (select id::text from buildings where holder='b0000000-0000-0000-0000-00000000000b'), false);

-- Become attacker A (authenticated role + A's JWT claim).
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);

do $$
declare pass int := 0; fail int := 0; r jsonb;
  bhouse bigint := current_setting('test.bhouse')::bigint;
  bbuild bigint := current_setting('test.bbuild')::bigint;
  cash_before bigint;
begin
  -- 1. negative quantity
  begin perform buy('weed', -5); fail:=fail+1; raise notice 'FAIL 1  negative-qty buy allowed';
  exception when others then pass:=pass+1; raise notice 'PASS 1  negative-qty buy blocked'; end;

  -- 2. zero quantity
  begin perform buy('weed', 0); fail:=fail+1; raise notice 'FAIL 2  zero-qty buy allowed';
  exception when others then pass:=pass+1; raise notice 'PASS 2  zero-qty buy blocked'; end;

  -- 3. buy beyond funds
  begin perform buy('weed', 1000000); fail:=fail+1; raise notice 'FAIL 3  over-funds buy allowed';
  exception when others then pass:=pass+1; raise notice 'PASS 3  over-funds buy blocked'; end;

  -- 4. oversell what you do not hold
  begin perform sell('weed', 100); fail:=fail+1; raise notice 'FAIL 4  oversell allowed';
  exception when others then pass:=pass+1; raise notice 'PASS 4  oversell blocked'; end;

  -- 5. CONTROL: a legit buy should still work
  begin r := buy('weed', 10);
    if (r->>'ok')='true' then pass:=pass+1; raise notice 'PASS 5  legit buy works';
    else fail:=fail+1; raise notice 'FAIL 5  legit buy returned not-ok'; end if;
  exception when others then fail:=fail+1; raise notice 'FAIL 5  legit buy errored: %', sqlerrm; end;

  -- 6. direct table write: forge cash
  begin update profiles set cash = 999999999 where id = auth.uid(); fail:=fail+1; raise notice 'FAIL 6  direct cash edit allowed';
  exception when others then pass:=pass+1; raise notice 'PASS 6  direct cash edit blocked'; end;

  -- 7. direct table write: spawn inventory
  begin insert into inventory(profile_id, drug_id, grams) values (auth.uid(),'cocaine',100000); fail:=fail+1; raise notice 'FAIL 7  direct inventory insert allowed';
  exception when others then pass:=pass+1; raise notice 'PASS 7  direct inventory insert blocked'; end;

  -- 8. call an internal helper directly (price probe)
  begin perform price_of('steubenville_oh','weed'); fail:=fail+1; raise notice 'FAIL 8  internal price_of callable';
  exception when others then pass:=pass+1; raise notice 'PASS 8  internal price_of denied'; end;

  -- 9. settle ANOTHER player's trap house
  begin r := settle_trap_house(bhouse); fail:=fail+1; raise notice 'FAIL 9  settled B''s trap house';
  exception when others then pass:=pass+1; raise notice 'PASS 9  cannot settle another player''s house'; end;

  -- 10. release ANOTHER player's building
  begin perform release_building(bbuild); fail:=fail+1; raise notice 'FAIL 10 released B''s building';
  exception when others then pass:=pass+1; raise notice 'PASS 10 cannot release another player''s building'; end;

  -- 11. privilege escalation: self-promote to admin
  begin perform admin_set_tier(auth.uid(), 'admin'); fail:=fail+1; raise notice 'FAIL 11 self-promoted to admin';
  exception when others then pass:=pass+1; raise notice 'PASS 11 non-staff cannot set tiers'; end;

  -- 12. privilege escalation: grant self DLC/modifier
  begin perform admin_grant_modifier(auth.uid(),'dlc:pilot_pack'); fail:=fail+1; raise notice 'FAIL 12 self-granted DLC';
  exception when others then pass:=pass+1; raise notice 'PASS 12 non-staff cannot grant modifiers'; end;

  -- 13. read another player's state via direct table select
  begin
    perform 1 from profiles where id = 'b0000000-0000-0000-0000-00000000000b';
    -- with no table grant this errors; if it somehow returns, that's a leak
    if found then fail:=fail+1; raise notice 'FAIL 13 read B profile directly'; else pass:=pass+1; raise notice 'PASS 13 no rows / blocked'; end if;
  exception when others then pass:=pass+1; raise notice 'PASS 13 direct profile read blocked'; end;

  -- 14. acquire a location B already holds (double-occupy)
  begin perform acquire_building(39.5, -80.5, 'steubenville_oh'); fail:=fail+1; raise notice 'FAIL 14 double-occupied B''s spot';
  exception when others then pass:=pass+1; raise notice 'PASS 14 cannot occupy a held location'; end;

  -- 15. mint cash via a NEGATIVE building cost (client-supplied cost param)
  begin
    select (get_my_state()->'profile'->>'cash')::bigint into cash_before;
    perform acquire_building(41.0, -81.0, 'steubenville_oh', 'trap_house', -500000);
    if (get_my_state()->'profile'->>'cash')::bigint > cash_before
      then fail:=fail+1; raise notice 'FAIL 15 negative-cost building MINTED CASH';
      else pass:=pass+1; raise notice 'PASS 15 negative cost did not mint'; end if;
  exception when others then pass:=pass+1; raise notice 'PASS 15 negative-cost acquire rejected'; end;

  raise notice '================  RESULT: % passed, % FAILED  ================', pass, fail;
end $$;

rollback;
