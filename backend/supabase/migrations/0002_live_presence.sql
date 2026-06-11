-- Linkup live presence schema (session 3 — real-time "who's at this event").
-- Adds the one table the multi-device Discover feature needs: a row per account
-- that is *actively sharing* their location at an event right now. The Edge
-- Function (service_role, bypasses RLS) upserts/reads these rows; the iOS app
-- polls /presence/nearby to render the other connections on the venue map.
--
-- Matching (who sees whom) is computed in the Edge Function, not here: device A
-- sees presence B only if B is in A's linkedin_connection list (slug or name).
-- This table just stores the live broadcast.
--
-- To reproduce via CLI: `supabase db push` after `supabase link`. Or apply via
-- the Supabase MCP `apply_migration`.

create table if not exists public.live_presence (
  account_id      uuid primary key references public.linkup_account(id) on delete cascade,
  display_name    text not null default '',
  headline        text not null default '',
  linkedin_slug   text,                       -- the sharer's OWN slug, lowercased (may be null)
  linkedin_url    text,
  event_name      text not null default '',   -- original event label, for display
  event_name_key  text not null default '',   -- lowercased/trimmed, for matching
  map_x           double precision not null default 0.5,
  map_y           double precision not null default 0.5,
  started_at      timestamptz not null default now(),
  expires_at      timestamptz not null,
  updated_at      timestamptz not null default now()
);

-- Fast lookup of "everyone live at this event right now".
create index if not exists idx_live_presence_event
  on public.live_presence (event_name_key, expires_at);

-- Keep updated_at fresh on every upsert (reuses the function from 0001).
drop trigger if exists trg_live_presence_updated_at on public.live_presence;
create trigger trg_live_presence_updated_at
  before update on public.live_presence
  for each row execute function public.set_updated_at();

-- Same default-deny posture as every other table: RLS on, no policies, so only
-- the service_role Edge Function can read/write. The expected INFO-level
-- "rls_enabled_no_policy" advisor notice is intentional.
alter table public.live_presence enable row level security;
