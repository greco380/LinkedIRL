-- Linkup Supabase Auth RLS migration (session 4).
--
-- Design call: we map linkup_account.id 1:1 to auth.users.id (prd.md §5,
-- §14). The iOS client passes its Supabase Auth UUID as the account UUID, so
-- `auth.uid()` resolves directly against `linkup_account.id`. We still add a
-- nullable `auth_user_id` column for the rare case where the two need to
-- diverge (e.g. account merge, future multi-identity support); all policies
-- below match on `id` directly, falling back to `auth_user_id` if set.
--
-- After this migration the service-role Edge Function still bypasses RLS
-- (Supabase default), so existing endpoints keep working. New endpoints that
-- run with the user's JWT (or direct PostgREST from iOS post-Auth-cutover)
-- pick up the per-user scoping automatically.
--
-- To reproduce via CLI: `supabase db push` after `supabase link`.

-- 1. Add the (nullable) auth_user_id link. Idempotent.
alter table public.linkup_account
  add column if not exists auth_user_id uuid references auth.users(id) on delete set null;

create index if not exists idx_linkup_account_auth_user_id
  on public.linkup_account (auth_user_id);

-- Helper: resolve the current request's linkup_account.id. Wrapped in a SQL
-- function so policies stay readable and the planner can fold it into joins.
create or replace function public.current_linkup_account_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id
    from public.linkup_account
   where id = auth.uid()
      or auth_user_id = auth.uid()
   limit 1;
$$;

-- 2. linkup_account policies ------------------------------------------------
alter table public.linkup_account enable row level security;

do $$ begin
  create policy linkup_account_select_own
    on public.linkup_account
    for select
    using (id = auth.uid() or auth_user_id = auth.uid());
exception when duplicate_object then null; end $$;

do $$ begin
  create policy linkup_account_insert_self
    on public.linkup_account
    for insert
    with check (id = auth.uid() or auth_user_id = auth.uid());
exception when duplicate_object then null; end $$;

do $$ begin
  create policy linkup_account_update_own
    on public.linkup_account
    for update
    using (id = auth.uid() or auth_user_id = auth.uid())
    with check (id = auth.uid() or auth_user_id = auth.uid());
exception when duplicate_object then null; end $$;

do $$ begin
  create policy linkup_account_delete_own
    on public.linkup_account
    for delete
    using (id = auth.uid() or auth_user_id = auth.uid());
exception when duplicate_object then null; end $$;

-- 3. linkedin_import_record policies ---------------------------------------
alter table public.linkedin_import_record enable row level security;

do $$ begin
  create policy linkedin_import_record_select_own
    on public.linkedin_import_record
    for select
    using (account_id = public.current_linkup_account_id());
exception when duplicate_object then null; end $$;

do $$ begin
  create policy linkedin_import_record_write_own
    on public.linkedin_import_record
    for all
    using (account_id = public.current_linkup_account_id())
    with check (account_id = public.current_linkup_account_id());
exception when duplicate_object then null; end $$;

-- 4. linkedin_profile policies ---------------------------------------------
alter table public.linkedin_profile enable row level security;

do $$ begin
  create policy linkedin_profile_select_own
    on public.linkedin_profile
    for select
    using (account_id = public.current_linkup_account_id());
exception when duplicate_object then null; end $$;

do $$ begin
  create policy linkedin_profile_write_own
    on public.linkedin_profile
    for all
    using (account_id = public.current_linkup_account_id())
    with check (account_id = public.current_linkup_account_id());
exception when duplicate_object then null; end $$;

-- 5. linkedin_connection policies ------------------------------------------
alter table public.linkedin_connection enable row level security;

do $$ begin
  create policy linkedin_connection_select_own
    on public.linkedin_connection
    for select
    using (account_id = public.current_linkup_account_id());
exception when duplicate_object then null; end $$;

do $$ begin
  create policy linkedin_connection_write_own
    on public.linkedin_connection
    for all
    using (account_id = public.current_linkup_account_id())
    with check (account_id = public.current_linkup_account_id());
exception when duplicate_object then null; end $$;

-- 6. linkedin_profile_observation policies ---------------------------------
alter table public.linkedin_profile_observation enable row level security;

do $$ begin
  create policy linkedin_profile_observation_select_own
    on public.linkedin_profile_observation
    for select
    using (account_id = public.current_linkup_account_id());
exception when duplicate_object then null; end $$;

do $$ begin
  create policy linkedin_profile_observation_write_own
    on public.linkedin_profile_observation
    for all
    using (account_id = public.current_linkup_account_id())
    with check (account_id = public.current_linkup_account_id());
exception when duplicate_object then null; end $$;

-- 7. live_presence policies -------------------------------------------------
-- Presence is fundamentally public-to-matched-connections; for v1 we restrict
-- direct selects to the row's owner. The Edge Function (service role) still
-- runs the matching query and returns filtered results to iOS.
alter table public.live_presence enable row level security;

do $$ begin
  create policy live_presence_select_own
    on public.live_presence
    for select
    using (account_id = public.current_linkup_account_id());
exception when duplicate_object then null; end $$;

do $$ begin
  create policy live_presence_write_own
    on public.live_presence
    for all
    using (account_id = public.current_linkup_account_id())
    with check (account_id = public.current_linkup_account_id());
exception when duplicate_object then null; end $$;

-- 8. chat_message policies (additive: recipient may also select) -----------
-- 0003 already added a sender-or-recipient select policy. Re-create it here
-- against current_linkup_account_id() so it also works for accounts that link
-- via auth_user_id instead of id. Then add owner insert/update for sender.
alter table public.chat_message enable row level security;

do $$ begin
  drop policy if exists chat_message_select_own on public.chat_message;
exception when others then null; end $$;

do $$ begin
  create policy chat_message_select_own
    on public.chat_message
    for select
    using (
      sender_account_id = public.current_linkup_account_id()
      or recipient_account_id = public.current_linkup_account_id()
    );
exception when duplicate_object then null; end $$;

do $$ begin
  drop policy if exists chat_message_insert_self on public.chat_message;
exception when others then null; end $$;

do $$ begin
  create policy chat_message_insert_self
    on public.chat_message
    for insert
    with check (sender_account_id = public.current_linkup_account_id());
exception when duplicate_object then null; end $$;

-- Service role still bypasses every policy above (Supabase default).
