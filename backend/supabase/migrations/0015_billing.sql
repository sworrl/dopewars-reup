-- 0015_billing.sql — server-only entitlement grant for WEB (Stripe) purchases.
--
-- Called ONLY by the Stripe webhook Edge Function (running as service_role) after it verifies a real,
-- Stripe-signed payment event. Never granted to any client role, so a modded source client can't
-- invoke it or forge access. Duration is set here (server clock), not sent by anyone.

-- Maps a Stripe customer back to the account so subscription RENEWALS (invoice.paid, which carry no
-- client_reference_id) can extend the right player. Written by the webhook (service_role) only.
alter table profiles add column if not exists stripe_customer_id text;
create index if not exists profiles_stripe_customer on profiles(stripe_customer_id)
  where stripe_customer_id is not null;

create or replace function apply_purchase(p_user uuid, p_kind text) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare base timestamptz; result timestamptz;
begin
  if p_kind not in ('monthly', 'yearly', 'lifetime') then
    raise exception 'bad_kind';
  end if;
  if not exists (select 1 from profiles where id = p_user) then
    raise exception 'no_such_user';
  end if;
  -- Stack onto any remaining time (renewals extend; a sub bought early doesn't lose days).
  base := greatest(coalesce((select online_until from profiles where id = p_user), world_now()), world_now());
  update profiles set online_until = case p_kind
      when 'lifetime' then 'infinity'::timestamptz
      when 'yearly'   then base + interval '366 days'
      else                 base + interval '31 days'      -- monthly
    end
    where id = p_user
    returning online_until into result;
  return jsonb_build_object('ok', true, 'user', p_user, 'kind', p_kind, 'online_until', result);
end $$;

-- Client roles can NEVER call this. service_role (the webhook) bypasses grants.
revoke execute on function apply_purchase(uuid, text) from public, anon, authenticated;
