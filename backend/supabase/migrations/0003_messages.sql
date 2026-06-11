-- Linkup messaging schema (session 4 — real cross-device DMs).
-- Replaces the simulated canned replies in iOS with a real persistence layer.
--
-- Threading: a thread is keyed by the canonical sorted pair of account UUIDs
-- joined with ':' (lexicographic). This avoids needing a separate thread table
-- and keeps every message addressable by (thread_id, sent_at).
--
-- RLS posture: enabled with explicit per-user policies. A row is selectable by
-- its sender OR recipient when their auth.uid() matches the corresponding
-- account_id column. The service-role Edge Function still bypasses RLS for
-- send/poll endpoints called before the Supabase Auth migration lands. Once
-- iOS moves to Supabase Auth (see 0005), clients can read directly.
--
-- To reproduce via CLI: `supabase db push` after `supabase link`. Or apply via
-- the Supabase MCP `apply_migration`.

create table if not exists public.chat_message (
  id                    uuid primary key default gen_random_uuid(),
  thread_id             text not null,
  sender_account_id     uuid not null references public.linkup_account(id) on delete cascade,
  recipient_account_id  uuid not null references public.linkup_account(id) on delete cascade,
  body                  text not null,
  sent_at               timestamptz not null default now(),
  delivered_at          timestamptz,
  read_at               timestamptz
);

create index if not exists idx_chat_message_thread
  on public.chat_message (thread_id, sent_at);

create index if not exists idx_chat_message_recipient
  on public.chat_message (recipient_account_id, sent_at);

-- Server-side delivered_at: set on insert so the receiving side has a single
-- authoritative timestamp even if the client clock is skewed.
create or replace function public.set_chat_message_delivered_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.delivered_at is null then
    new.delivered_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_chat_message_delivered_at on public.chat_message;
create trigger trg_chat_message_delivered_at
  before insert on public.chat_message
  for each row execute function public.set_chat_message_delivered_at();

-- RLS: default-deny, then add a sender-or-recipient select policy. Postgres
-- versions vary on whether CREATE POLICY supports IF NOT EXISTS, so we wrap.
alter table public.chat_message enable row level security;

do $$
begin
  create policy chat_message_select_own
    on public.chat_message
    for select
    using (
      auth.uid() = sender_account_id
      or auth.uid() = recipient_account_id
    );
exception when duplicate_object then null;
end $$;

do $$
begin
  create policy chat_message_insert_self
    on public.chat_message
    for insert
    with check (auth.uid() = sender_account_id);
exception when duplicate_object then null;
end $$;

-- Service role bypasses all of the above (Supabase default).
