-- 0023: beta signup queue, approved from Telegram.
-- Flow: site form -> beta-signup edge fn -> row here + Telegram DM to the admin ->
-- admin replies 1/2 (or taps a button) -> telegram-webhook edge fn flips status and,
-- on approval, invites the email via GoTrue (account + magic-link email).
--
-- Service-role only: 0008's default-privilege revokes mean anon/authenticated get no
-- grants, and RLS with zero policies double-bolts the door. No client API surface.

create table if not exists beta_signups (
  id            uuid primary key default gen_random_uuid(),
  email         text not null,
  handle        text,
  note          text,
  status        text not null default 'pending'
                check (status in ('pending','approved','denied')),
  tg_message_id bigint,       -- admin-DM message id; lets a Telegram reply target this row
  ip_hash       text,         -- salted hash for rate limiting, never the raw address
  created_at    timestamptz not null default now(),
  decided_at    timestamptz
);

create unique index if not exists beta_signups_email_uq on beta_signups (lower(email));
create index if not exists beta_signups_pending_ix on beta_signups (created_at) where status = 'pending';

alter table beta_signups enable row level security;
