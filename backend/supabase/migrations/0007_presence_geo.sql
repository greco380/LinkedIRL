-- Linkup presence geolocation columns (session iOS-GPS).
-- Adds real lat/lng/accuracy to `live_presence` so the iOS CoreLocation feed
-- can be persisted alongside the existing normalized map_x/map_y. Per PRD §6:
-- the client drops fixes worse than 100m accuracy; this migration just stores
-- whatever the client decides to send (the Edge Function should range-check).
--
-- Idempotent: ADD COLUMN IF NOT EXISTS so it can be applied to a database that
-- already has the prior six migrations without errors.
--
-- Apply via Supabase MCP `apply_migration` or `supabase db push`.

alter table public.live_presence
  add column if not exists lat double precision,
  add column if not exists lng double precision,
  add column if not exists accuracy_m double precision;

-- Range guards. NULL values are still allowed (synthetic positions arrive
-- without a GPS fix); when a value is present it must be physically valid.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'live_presence_lat_range'
  ) then
    alter table public.live_presence
      add constraint live_presence_lat_range
      check (lat is null or (lat >= -90 and lat <= 90));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'live_presence_lng_range'
  ) then
    alter table public.live_presence
      add constraint live_presence_lng_range
      check (lng is null or (lng >= -180 and lng <= 180));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'live_presence_accuracy_nonneg'
  ) then
    alter table public.live_presence
      add constraint live_presence_accuracy_nonneg
      check (accuracy_m is null or accuracy_m >= 0);
  end if;
end $$;
