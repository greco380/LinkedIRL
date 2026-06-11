-- Linkup core persistence schema (applied live to project ghkzdhdwnpppeivwyaej on 2026-05-30).
-- Mirrors the Swift Codable models in Linkup/Models/LinkupModels.swift.
-- account_id FK throughout. RLS enabled with default-deny: only the Edge
-- Function (service_role, which bypasses RLS) reads/writes for now. When
-- Supabase Auth is wired, add per-user policies keyed to auth.uid() = account_id.
--
-- This file is the version-controlled record of what the Supabase MCP applied.
-- To reproduce via the CLI: `supabase db push` after `supabase link`.

-- 1. linkup_account ---------------------------------------------------------
create table if not exists public.linkup_account (
  id                        uuid primary key,
  display_name              text not null default '',
  email                     text not null default '',
  auth_method               text not null default 'email',
  apple_subject             text,
  google_subject            text,
  linkedin_connected        boolean not null default false,
  linkedin_url              text,
  linkedin_member_id        text,
  linkedin_profile_slug     text,
  linkedin_verified_at      timestamptz,
  linkedin_imported_at      timestamptz,
  linkedin_connection_count integer not null default 0,
  created_at                timestamptz not null default now(),
  last_signed_in_at         timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);

-- 2. linkedin_import_record -------------------------------------------------
create table if not exists public.linkedin_import_record (
  id           uuid primary key,
  account_id   uuid not null references public.linkup_account(id) on delete cascade,
  source       text not null,
  imported_at  timestamptz not null,
  row_count    integer not null default 0,
  file_hash    text not null default '',
  created_at   timestamptz not null default now()
);
create index if not exists idx_import_record_account on public.linkedin_import_record(account_id);

-- 3. linkedin_profile -------------------------------------------------------
-- Profile id (e.g. "linkedin:in:slug") is unique within an account's network.
create table if not exists public.linkedin_profile (
  account_id     uuid not null references public.linkup_account(id) on delete cascade,
  id             text not null,
  normalized_url text not null default '',
  slug           text,
  first_name     text,
  last_name      text,
  company        text,
  position       text,
  updated_at     timestamptz not null default now(),
  primary key (account_id, id)
);

-- 4. linkedin_connection ----------------------------------------------------
create table if not exists public.linkedin_connection (
  id                    uuid primary key,
  account_id            uuid not null references public.linkup_account(id) on delete cascade,
  connection_profile_id text not null,
  import_id             uuid references public.linkedin_import_record(id) on delete set null,
  verification_state    text not null default 'imported',
  confidence_score      double precision not null default 0.65,
  field_mask            jsonb not null default '{}'::jsonb,
  first_name            text not null default '',
  last_name             text not null default '',
  profile_url           text not null,
  email_hash            text,
  company               text,
  position              text,
  connected_on          timestamptz,
  imported_at           timestamptz not null,
  created_at            timestamptz not null default now(),
  unique (account_id, connection_profile_id)
);
create index if not exists idx_connection_account on public.linkedin_connection(account_id);

-- 5. linkedin_profile_observation ------------------------------------------
create table if not exists public.linkedin_profile_observation (
  id            uuid primary key,
  account_id    uuid not null references public.linkup_account(id) on delete cascade,
  profile_id    text not null,
  import_id     uuid references public.linkedin_import_record(id) on delete set null,
  source        text not null,
  observed_at   timestamptz not null,
  first_name    text,
  last_name     text,
  company       text,
  position      text,
  raw_url       text not null default '',
  raw_row_hash  text not null default '',
  created_at    timestamptz not null default now()
);
create index if not exists idx_observation_account on public.linkedin_profile_observation(account_id);
create index if not exists idx_observation_import on public.linkedin_profile_observation(import_id);

-- updated_at maintenance ----------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_account_updated_at on public.linkup_account;
create trigger trg_account_updated_at
  before update on public.linkup_account
  for each row execute function public.set_updated_at();

drop trigger if exists trg_profile_updated_at on public.linkedin_profile;
create trigger trg_profile_updated_at
  before update on public.linkedin_profile
  for each row execute function public.set_updated_at();

-- Row-Level Security: enable on every table with NO policies.
-- Effect: anon/authenticated clients are denied all access; the Edge Function
-- uses the service_role key, which bypasses RLS. This is the secure
-- "default deny" posture until Supabase Auth is integrated. The INFO-level
-- "rls_enabled_no_policy" advisor notice is expected and intentional here.
alter table public.linkup_account               enable row level security;
alter table public.linkedin_import_record       enable row level security;
alter table public.linkedin_profile             enable row level security;
alter table public.linkedin_connection          enable row level security;
alter table public.linkedin_profile_observation enable row level security;
