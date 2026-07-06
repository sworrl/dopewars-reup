-- 0019_org_income.sql — the org's crew slots now EARN. Each slot pushes product over time (its push
-- rate, less the earner's skim), generating cash for the crew and drawing heat. Runs on the SERVER
-- clock (world_now), so idle income can't be gamed by rolling a device clock; capped at a week of
-- idle to keep clock-forward pointless. Reads slot_stats() — so NPC and real-player fills earn
-- through the exact same path (the payoff of the interchangeable-slots design).

alter table crews add column if not exists last_settle timestamptz not null default now();

create or replace function settle_org(p_crew bigint) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare me profiles; ls timestamptz; hours numeric; income bigint := 0; heat numeric := 0;
        s record; st jsonb; n int := 0;
begin
  me := require_player();
  if not exists (select 1 from crew_members where crew_id = p_crew and profile_id = me.id and role in ('leader','officer'))
    then raise exception 'not_crew_officer'; end if;
  select last_settle into ls from crews where id = p_crew;
  hours := least(extract(epoch from (world_now() - ls)) / 3600.0, 168);   -- cap at a week idle
  for s in select id from crew_slots where crew_id = p_crew loop
    st := slot_stats(s.id);
    income := income + floor((st->>'push')::numeric * hours * 12 * (1 - (st->>'skim')::numeric));
    heat := heat + (st->>'heat')::numeric;
    n := n + 1;
  end loop;
  update crews set last_settle = world_now() where id = p_crew;
  if income > 0 then
    update profiles set cash = cash + income where id = me.id;   -- paid to the settling officer
  end if;
  return jsonb_build_object('ok', true, 'income', income, 'hours', round(hours, 1),
    'heat', heat, 'slots', n);
end $$;

grant execute on function settle_org(bigint) to authenticated;
