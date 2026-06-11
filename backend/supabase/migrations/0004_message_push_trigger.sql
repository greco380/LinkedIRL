-- Linkup message push trigger (session 4 — APNs fan-out on chat_message insert).
--
-- When a chat_message row is inserted, fire an HTTP POST to the deployed APNs
-- Edge Function with the recipient's push token. Uses the pg_net extension
-- (Supabase ships this enabled). The trigger is non-blocking: any failure is
-- swallowed so message inserts always succeed even when APNs is misconfigured.
--
-- Two settings drive routing (configured per-project via `alter database ...
-- set <name> = <value>`):
--   - app.apns_function_url   — full URL of the deployed APNs Edge Function
--                                (e.g. https://<ref>.supabase.co/functions/v1/apns/apns/send)
--   - app.apns_function_token — optional bearer token if the function requires JWT
--
-- If app.apns_function_url is unset the trigger is a no-op.

-- 1. push_token column on linkup_account (idempotent — may already exist).
alter table public.linkup_account
  add column if not exists push_token text;

-- 2. pg_net for outbound HTTP from Postgres.
create extension if not exists pg_net;

-- 3. Trigger function. Best-effort: NEVER raise, NEVER block the insert.
create or replace function public.notify_chat_message_push()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_push_token   text;
  v_sender_name  text;
  v_event_name   text;
  v_title        text;
  v_body         text;
  v_url          text;
  v_token        text;
  v_headers      jsonb;
  v_payload      jsonb;
begin
  begin
    select coalesce(la.push_token, '') into v_push_token
      from public.linkup_account la
      where la.id = new.recipient_account_id;

    if v_push_token is null or v_push_token = '' then
      return new;
    end if;

    select coalesce(la.display_name, 'Someone') into v_sender_name
      from public.linkup_account la
      where la.id = new.sender_account_id;

    -- If the sender currently has an active presence row, append the event name.
    select lp.event_name into v_event_name
      from public.live_presence lp
      where lp.account_id = new.sender_account_id
        and lp.expires_at > now()
      limit 1;

    if v_event_name is not null and length(v_event_name) > 0 then
      v_title := v_sender_name || ' at ' || v_event_name;
    else
      v_title := v_sender_name;
    end if;

    v_body := left(coalesce(new.body, ''), 80);

    -- Resolve config (unset -> no-op).
    begin
      v_url := current_setting('app.apns_function_url', true);
    exception when others then
      v_url := null;
    end;
    if v_url is null or v_url = '' then
      return new;
    end if;

    begin
      v_token := current_setting('app.apns_function_token', true);
    exception when others then
      v_token := null;
    end;

    v_headers := jsonb_build_object('content-type', 'application/json');
    if v_token is not null and v_token <> '' then
      v_headers := v_headers || jsonb_build_object('authorization', 'Bearer ' || v_token);
    end if;

    v_payload := jsonb_build_object(
      'deviceToken', v_push_token,
      'title', v_title,
      'body', v_body,
      'payload', jsonb_build_object(
        'type', 'message',
        'threadId', new.thread_id,
        'senderAccountId', new.sender_account_id,
        'eventName', v_event_name
      )
    );

    perform net.http_post(
      url := v_url,
      headers := v_headers,
      body := v_payload
    );
  exception when others then
    -- Swallow: APNs failures must never block the message insert.
    raise notice 'notify_chat_message_push: % %', sqlstate, sqlerrm;
  end;
  return new;
end;
$$;

drop trigger if exists trg_chat_message_push on public.chat_message;
create trigger trg_chat_message_push
  after insert on public.chat_message
  for each row execute function public.notify_chat_message_push();

-- Deployer note: after deploying the APNs Edge Function, run:
--   alter database postgres set app.apns_function_url = 'https://<ref>.supabase.co/functions/v1/apns/apns/send';
-- and (optionally) the matching app.apns_function_token. Until then the trigger
-- is a silent no-op.
